extends SceneTree
## verify_story.gd — 故事层的一致性：文案 key、碎片身份、文档不许说谎。
##
## 这一族回归守的不是"某个函数返回了某个数"，而是**三处互相对不上的副本**：
##   · `Localization.STRINGS`（玩家真正读到的字）
##   · `road_data.stations` / `Postcard`（碎片身份与顺序）
##   · `3D_RIDE_DESIGN.md`（写给下一个人的说明书）
## 每一处都自洽，翻两页看不出来错，而错的那一屏玩家看得见。
##
## 三个具体的洞，都是这一族：
##  1. `Localization.t()` 查不到 key 时**返回 key 本身**（"villain_1_1"），
##     不是空串也不是报错——一个字打错，屏幕上就出现那个 key，
##     而全工程没有任何一处会因此变红。
##  2. 中英两套 STRINGS 是各写各的，加了中文忘了英文（或者反过来）时，
##     中文界面一路正常，只有切到英文的那一屏露 key。
##  3. 设计文档里的驿站名 / 相机参数是**手抄**的。road_data 里禽语湖湾
##     早就改叫「花房·禽语湖湾 / Birdsong Cove Flower House」，
##     而文档还写着旧的「禽语湖湾 / Birdsong Cove」；
##     相机早就从 `-forward * 8 + (0,5,0)` 改成 `-forward * 6 + (0,4,0)`，
##     文档还写着 8 和 5。文档没人跑，下一个照着它改代码的人一定改错。
##
## 用法： godot --headless --path . --script tools/verify_story.gd

var _fails := 0
var _checks := 0
var _rd: Object = null
var _loc: Object = null


func _ck(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label, ("　—— " + detail) if detail != "" else "")


func _initialize() -> void:
	# --script 模式下 class_name 类型注解会在编译期拉依赖、进而拉爆 autoload
	# 解析（见 CLAUDE.md 已知陷阱），所以一律用运行时 load()。
	_rd = load("res://scripts/road_data.gd").new()
	_loc = load("res://scripts/Localization.gd").new()
	_loc._load_language()

	_section_keys()
	_section_villain_keys()
	_section_fragments()
	_section_stations()
	_section_doc()

	print("\n[verify_story] %s  (%d 条断言，失败 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)


## 1. 中英两套 key 必须一字不差
func _section_keys() -> void:
	print("\n---- 1. Localization 中英 key 对齐 ----")
	var s: Dictionary = _loc.STRINGS
	if not (s.has("zh") and s.has("en")):
		_ck(false, "STRINGS 有 zh / en 两套")
		return
	_ck(true, "STRINGS 有 zh / en 两套")
	var zh: Dictionary = s["zh"]
	var en: Dictionary = s["en"]
	var only_zh := []
	for k in zh.keys():
		if not en.has(k):
			only_zh.append(str(k))
	var only_en := []
	for k in en.keys():
		if not zh.has(k):
			only_en.append(str(k))
	_ck(only_zh.is_empty(), "没有只在中文侧存在的 key", str(only_zh))
	_ck(only_en.is_empty(), "没有只在英文侧存在的 key", str(only_en))
	# 空串：key 在、字是空。切到那个语言时那一行就是一片空白，
	# 编译期和运行期都不报错，只有那一屏塌掉。
	var blank_zh := []
	for k in zh.keys():
		if str(zh[k]).strip_edges() == "":
			blank_zh.append(str(k))
	var blank_en := []
	for k in en.keys():
		if str(en[k]).strip_edges() == "":
			blank_en.append(str(k))
	_ck(blank_zh.is_empty(), "中文侧没有空串", str(blank_zh))
	_ck(blank_en.is_empty(), "英文侧没有空串", str(blank_en))
	# 中英同一个 key 不许是同一句话：整个界面切了语言等于没切。
	# 例外是**不带语言的那一类**：
	# ①纯格式化 key（`visits_left_n` 的值就是 "%d"）；
	# ②纯数字/符号的量本身（分辨率那三档 `resolution_720` 的值是
	#   "1280 × 720"，中英两侧必然逐字相同——把英文写成别的才是把
	#   尺寸说错，而尺寸没有第二种语言）。
	# 判据写成"剔掉 % 规格符之后还**不含任何一个字母或汉字**"，
	# 而不是列一张白名单——白名单每加一个键就多一个可以忘更新的地方。
	var same := []
	for k in zh.keys():
		if not en.has(k):
			continue
		var v := str(zh[k])
		if v != str(en[k]):
			continue
		if not _has_letters(v):
			continue
		same.append(str(k))
	_ck(same.is_empty(), "没有中英逐字相同的 key（否则切语言等于没切）", str(same))
	print("[dbg] key 总数 %d（中）/ %d（英）" % [zh.size(), en.size()])


## 这个串里有没有**任何一个字母或汉字**。`%d` / `%s` / `%f` 先剔掉，
## 所以 `"%d"` 与 `""` 都读作"不带语言"，而 `"1280 × 720"` 也是。
##
## 正则用 `[A-Za-z]` 而不是 `\w`：`\w` 在 GDScript 里也吃中文，
## 于是 `×` 之外什么都会被算成"有语言"，`"1280 × 720"` 会被误判成
## 需要翻译——而它两侧本来就该逐字相同。汉字另走一条 `_is_cjk()`。
func _has_letters(s: String) -> bool:
	var stripped := s.replace("%d", "").replace("%s", "").replace("%f", "")
	for i in stripped.length():
		var c := stripped.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
		if c >= 0x4E00 and c <= 0x9FFF:
			return true
	return false


## 2. 反派三场的台词 key 真的存在
##
## 只读源码文本，不实例化 World3D：这一节要量的只有 key 名单，
## 而实例化整个场景会把地形和植被全建一遍（几十秒），为几个字符串不值。
func _section_villain_keys() -> void:
	print("\n---- 2. 反派三场的台词 key 真的存在 ----")
	var src := FileAccess.get_file_as_string("res://scripts/World3D.gd")
	var zh: Dictionary = _loc.STRINGS["zh"]
	var en: Dictionary = _loc.STRINGS["en"]
	var re := RegEx.new()
	re.compile("\"(villain_[0-9]_[0-9]|villain_[0-9]_player|villain_speaker|player_speaker)\"")
	var missing := []
	var found := 0
	for m in re.search_all(src):
		found += 1
		var k: String = m.get_string(1)
		if not zh.has(k) or not en.has(k):
			missing.append(k)
	_ck(found >= 8, "在 World3D.gd 里找得到反派台词 key（防正则失效的空跑）",
			"只匹配到 %d 个" % found)
	_ck(missing.is_empty(), "反派台词 key 中英都齐", str(missing))


## 3. 五座碎片站的身份与顺序
func _section_fragments() -> void:
	print("\n---- 3. 五座碎片站的身份与顺序 ----")
	var slots: Array = _rd.FRAGMENT_SLOT_STATION_IDX
	_ck(slots.size() == 5, "碎片站正好 5 座", str(slots))
	# 碎片顺序 云/茶/琴/竹/禽 —— 与 Postcard.FRAGMENT_COLS / FragmentBar 同序。
	# 顺序是玩家带走的那张明信片上的顺序，错了就是错的那张错了。
	var want := ["云", "茶", "琴", "竹", "禽"]
	var got := []
	var uniq := {}
	for idx in slots:
		got.append(str(_rd.stations[int(idx)].get("fragment", "")))
		uniq[int(idx)] = true
	_ck(got == want, "碎片顺序是 云/茶/琴/竹/禽", str(got))
	_ck(uniq.size() == 5, "五座碎片站互不相同", str(slots))
	# 颜色表同序：Postcard 与 FragmentBar 两份必须逐值相同
	var post = load("res://scripts/Postcard.gd")
	var bar = load("res://scripts/FragmentBar.gd")
	var a: Array = post.FRAGMENT_COLS
	var b: Array = bar.FRAGMENT_COLORS
	var same_col := a.size() == b.size()
	if same_col:
		for i in a.size():
			if str(a[i]) != str(b[i]):
				same_col = false
	_ck(a.size() == 5, "颜色表正好 5 项（slot 0 是云这件事只许写一次）", str(a.size()))
	_ck(same_col, "Postcard.FRAGMENT_COLS 与 FragmentBar.FRAGMENT_COLORS 逐值相同",
			"%s vs %s" % [str(a), str(b)])


## 4. 十六座站的中英文本齐全
func _section_stations() -> void:
	print("\n---- 4. 十六座站的中英文本 ----")
	var st: Array = _rd.stations
	_ck(st.size() == 16, "驿站正好 16 座", str(st.size()))
	var no_name_en := []
	var no_text := []
	var frag_no_dialogue := []
	for i in st.size():
		var s: Dictionary = st[i]
		if str(s.get("name_en", "")) == "":
			no_name_en.append(str(s.get("name", "?")))
		# 11 座非碎片站的 text 曾经是死数据（唯一的读者是打卡弹窗，
		# 而它们根本不能打卡）。现在由 World3D 在进圈那一帧浮出来，
		# 所以它们现在**必须**有字，否则那一圈是空的。
		if str(s.get("text", "")) == "" or str(s.get("text_en", "")) == "":
			no_text.append(str(s.get("name", "?")))
		# 有碎片的站必须有对白，否则"完成乐事"那一下没有任何可推进的东西
		if str(s.get("fragment", "")) != "":
			if (s.get("dialogue", []) as Array).is_empty() \
					or (s.get("dialogue_en", []) as Array).is_empty():
				frag_no_dialogue.append(str(s.get("name", "?")))
	_ck(no_name_en.is_empty(), "16 座都有英文名", str(no_name_en))
	_ck(no_text.is_empty(), "16 座都有中英 text（11 座路边站那句现在有人读了）", str(no_text))
	_ck(frag_no_dialogue.is_empty(), "五座碎片站都有对白（中文+英文）", str(frag_no_dialogue))
	# 中英两套对白是**两份独立手抄的副本**，而原来的判据只查"两边都非空"——
	# 于是中文加到 3 句、英文忘了加（或者反过来），两边一句对不上，
	# 玩家在英文界面少读一句，而**没有任何一条回归会红**：
	# 少的那句是个合法的非空数组，key 集合也照样逐字相同。
	# 这正是 CLAUDE.md 里"三处互相对不上的副本"那一族，所以钉句数。
	var frag_line_mismatch := []
	var frag_same_line := []
	for i in st.size():
		var s2: Dictionary = st[i]
		if str(s2.get("fragment", "")) == "":
			continue
		var dz: Array = s2.get("dialogue", [])
		var de: Array = s2.get("dialogue_en", [])
		if dz.size() != de.size():
			frag_line_mismatch.append("%s zh=%d en=%d" % [str(s2.get("name", "?")),
					dz.size(), de.size()])
			continue
		for k in mini(dz.size(), de.size()):
			if str(dz[k]).strip_edges() == str(de[k]).strip_edges():
				frag_same_line.append("%s #%d" % [str(s2.get("name", "?")), k + 1])
	_ck(frag_line_mismatch.is_empty(),
			"五座碎片站中英对白句数一一对应（少一句没人会发现）", str(frag_line_mismatch))
	_ck(frag_same_line.is_empty(),
			"没有哪一句中英相同（相同就是漏译）", str(frag_same_line))
	# 世界里不许出现现实道路编号
	var names := ""
	for i in st.size():
		names += str(st[i].get("name", "")) + " " + str(st[i].get("name_en", ""))
	for word in ["G318", "国道", "省道"]:
		_ck(not names.contains(word), "站名里没有现实公路标识「%s」" % word)


## 5. 设计文档不许说谎
##
## 这一节是本文件的另一半，也是它区别于 verify_stations.gd 的地方：
## verify_stations 守的是「配置与资源一致」，这一节守的是**说明书与代码一致**。
## 文档错了不会有任何运行时后果，可它是下一个改这个项目的人唯一的入口。
func _section_doc() -> void:
	print("\n---- 5. 3D_RIDE_DESIGN.md 不许说谎 ----")
	if not FileAccess.file_exists("res://3D_RIDE_DESIGN.md"):
		_ck(false, "3D_RIDE_DESIGN.md 存在")
		return
	var doc := FileAccess.get_file_as_string("res://3D_RIDE_DESIGN.md")

	# 5.1 五座碎片站的站名，文档里写的必须和 road_data 逐字相同。
	# 旧文档一直写着「禽语湖湾 / Birdsong Cove」，而代码里早就是
	# 「花房·禽语湖湾 / Birdsong Cove Flower House」——两份各自自洽，
	# 没有任何一条回归会红，可下一个照着文档改代码的人一定改错。
	var slots: Array = _rd.FRAGMENT_SLOT_STATION_IDX
	for i in slots.size():
		var idx: int = int(slots[i])
		var s: Dictionary = _rd.stations[idx]
		var name_zh := str(s.get("name", ""))
		var name_en := str(s.get("name_en", ""))
		_ck(doc.contains(name_zh), "文档里有这一站的中文名「%s」" % name_zh)
		_ck(doc.contains(name_en), "文档里有这一站的英文名「%s」" % name_en)
		# 乐事那一件也要对得上：每座碎片站对应十六件乐事里的第几件
		var ev := str(s.get("event", ""))
		_ck(doc.contains(ev), "文档里有这一站对应的乐事「%s」" % ev)
	# 反向：旧的写法不许留在文档里（"包含"关系会让上面的正向断言失去意义）
	_ck(not doc.contains("S5 禽语湖湾 / Birdsong Cove —"),
			"文档里没有过时的写法「S5 禽语湖湾 / Birdsong Cove —」")

	# 5.2 km 已经不是玩家可见的单位了（P0-4），文档不许再把它说成"显示"。
	for lie in ["里程显示", "显示里程"]:
		_ck(not doc.contains(lie),
				"文档里没有「%s」这种把 km 说成玩家可见单位的说法" % lie)
	_ck(doc.contains("驿"), "文档写明顶栏走的是驿数口径（P0-4 把 km 换成了驿数）")

	# 5.3 相机参数是手抄的，代码里早就从 `* 8 + (0,5,0)` 改成了 `* 6 + (0,4,0)`，
	# 后来又加上了横向让位（`+ right * CAM_SIDE`）。
	# 这里不比单个数字，而是把 Player3D.gd 里那一整行 `target_pos = ...` 整句抠出来，
	# 要求文档里逐字有同一句——手工拼一个 `-forward * 6.0` 当 needle 是错的：
	# 代码写的是 `global_position - forward * 6.0`，减号两边有空格，
	# 少写一个空格就永远匹配不上，而"永远匹配不上"和"文档写错了"
	# 在这一行上长得一模一样（第一版就是这么把自己坑了一轮）。
	# 正则也不再写死数字与括号形状：参数名化之后它会整个失配，而上面那条
	# "防正则失效的空跑"只拦得住"找不到行"，认不出新写法照样是假绿。
	var player := FileAccess.get_file_as_string("res://scripts/Player3D.gd")
	var m := RegEx.new()
	m.compile("var target_pos = global_position[^\\n]*")
	var hit: RegExMatch = m.search(player)
	_ck(hit != null, "Player3D.gd 里找得到相机的 target_pos 那一行（防正则失效的空跑）")
	if hit != null:
		var line: String = hit.get_string().strip_edges()
		_ck(doc.contains(line), "文档里的相机定位与代码逐字一致",
				"代码是：%s" % line)

	# 5.4 标题页过场的总长。文档里写着一个秒数，代码里是五个常量——
	# 两边各写一份必然会漂，而漂了没有任何运行时后果（动画照跑，只是慢了），
	# 唯一还能看见的地方就是这份文档。
	# 判据从 `GiftBox.gd` 的**常量表**重算，而不是从墙钟：墙钟要带窗口跑两遍
	# 真实场景切换才看得出零点几秒，实测把 ROAD_HOLD_SEC 改回 1.5 之后
	# 墙钟那条（5.6s < 20s）照样是绿的。
	var cmap: Dictionary = load("res://scripts/GiftBox.gd").get_script_constant_map()
	var tsum := 0.0
	for k in ["BOX_OUT_SEC", "ROAD_IN_SEC", "ROAD_HOLD_SEC",
			"ROAD_OUT_SEC", "SWITCH_DELAY_SEC"]:
		_ck(cmap.has(k), "GiftBox 有 %s 常量（防正则/表名失效的空跑）" % k)
		tsum += float(cmap.get(k, 0.0))
	_ck(absf(float(cmap.get("START_TRANSITION_SEC", -1.0)) - tsum) < 0.001,
			"START_TRANSITION_SEC 等于五段之和",
			"常量表写 %s，五段和 %.2f" % [str(cmap.get("START_TRANSITION_SEC")), tsum])
	_ck(tsum <= 1.5, "标题页过场没有回到三秒（%.2fs ≤ 1.5s）" % tsum, "%.2fs" % tsum)
	_ck(doc.contains("%.2f" % tsum),
			"文档里写的过场总长与代码一致", "代码算出来是 %.2fs" % tsum)

	_doc_readme_section()


## 5.5 README 也不许说谎 —— 上一节只对拍了设计文档，漏了评委真正先读的那两份
##
## 这一节是踩过一次的：`85aa0d6` 把顶栏的「已过 n/16 驿」改成不带分母的
## 「已过 n 驿」（扩充驿站时不用再改文案），代码和 3D_RIDE_DESIGN.md 都跟着改了，
## **两个 README 没改**——而 5.1~5.4 全在对拍设计文档，于是"设计对、代码对、
## README 错、回归全绿"。和 `verify_asphalt_shader.gd` 开头记的
## `edge_line_color` 是同一族：文档和代码各说各的，两边都绿。
##
## 为什么不干脆把 README 也并进 5.1：README 是**对外**的（评委先读它），
## 它的错比设计文档的错更贵；而它和中英两套文案的关系是另一类问题。
## 所以单开一节，只钉"玩家真的会去核对的那几件事"。
func _doc_readme_section() -> void:
	print("\n---- 5.5 README 也不许说谎 ----")
	var readmes := {
		"res://README.md": "README.md",
		"res://README.en.md": "README.en.md",
	}
	for path in readmes:
		var label: String = readmes[path]
		if not FileAccess.file_exists(path):
			_ck(false, "%s 存在" % label)
			continue
		var txt := FileAccess.get_file_as_string(path)

		# 5.5.1 顶栏驿数的写法。分母已经拿掉了（驿数会变，抄死分母就得回来改文案），
		# 而两份 README 到本轮为止都还写着带分母的旧格式。
		for lie in ["已过 n/16 驿", "n/16 驿", "已过 0/16 驿"]:
			_ck(not txt.contains(lie),
				"%s 没有把顶栏驿数说成带分母的「%s」" % [label, lie])
		# 反向：得**真的**写了驿数这件事，不能因为删掉错的就不写了。
		_ck(txt.contains("驿") or txt.contains("station"),
			"%s 说明了顶栏那个数字是驿数" % label)

		# 5.5.2 188 不是一个距离。第一版这里写的是"README 里不许出现 km 字样"，
		# 跑出来两条红——**是判据错了，不是 README 错了**：两份 README 都故意
		# 引用了旧的「188 公里环线 / 188 km」说法来当场拆穿它，而那恰恰是这个
		# 项目最好的两段文字之一。子串匹配分不清"声称"和"引用来反驳"。
		# 所以改成钉**正面那句话**：README 必须明确否认 188 是里程。
		if label == "README.md":
			_ck(txt.contains("它不是里程"),
				"README.md 明确写了 188 不是里程（正面断言，不靠子串排除）")
		else:
			_ck(txt.contains("It is not a distance"),
				"README.en.md explicitly says 188 is not a distance")

		# 5.5.3 五座碎片站的站名，两份 README 都得和 road_data 逐字相同。
		# 这一条比顶栏格式更值钱：README 里有那张对照表，评委就是照着它
		# 认这五件乐事的，它错了等于整个作品介绍的第一屏就错了。
		var slots: Array = _rd.FRAGMENT_SLOT_STATION_IDX
		for i in slots.size():
			var s: Dictionary = _rd.stations[int(slots[i])]
			var name_zh := str(s.get("name", ""))
			# README.md 是中文的，只要求中文名；README.en.md 要求英文名。
			var want: String = name_zh if label == "README.md" else str(s.get("name_en", ""))
			_ck(want != "" and txt.contains(want),
				"%s 里有碎片站名「%s」" % [label, want])

	_doc_counts_section()


## 5.6 README 报的那几个数，是**数得出来的**那几个
##
## 上一节钉的是"说法对不对"，这一节钉的是"报的那个数还对不对"。
## README 开头「这个项目有 42 条回归 + 8 套出图 + 2 条探针」这一句，
## 到本轮为止**从来没被任何东西钉过**，而它已经错了两轮：
## 出图实际 11 套、探针实际 4 条，README 还写着 8 和 2。
## 症状和 `edge_line_color` 完全一样——两边各自都绿，因为"文档里的数"
## 和"仓库里的数"之间**没有任何对拍**。
##
## 钉哪几个数是选出来的，不是全钉：
## · **数得出来的**（仓库里几个文件就是几）→ 钉。回归条数、出图套数、探针条数，
##   以及 `check_all.sh` 里 `NEEDS_WINDOW` 那七条的条数（两份 runner 都钉，
##   .sh 和 .ps1 各写一份而它们本来就得一样）。
## · **跑一次才知道的**（PASS 几条、断言几千条）→ **不钉**。它们每加一条断言
##   就变，钉住的当天就开始说谎，而 README 上一版恰恰是把这两个数写死的。
##   所以那一句连同"以你自己那一次的输出为准"一起留在文档里。
##
## 少一格都拦不住：前两版判据只查"README 里有没有 42 这个数字"，
## 于是 README 把 8 改成 11 之后它照样绿。
func _doc_counts_section() -> void:
	print("\n---- 5.6 README 报的那几个数不许对不上仓库 ----")

	var verifies := _count_scripts("verify_")
	var lookdevs := _count_scripts("lookdev_")
	var probes := _count_scripts("probe_")
	# **正对照先摆**：`DirAccess` 在导出后的 Web 构建里列不出目录
	# （见 verify_provenance.gd 第 103 行那条注释），所以"数出来是 0"和
	# "仓库真的空了"在下游看起来一模一样。哪一格真的 0 了，后面那几条
	# 会安静地全绿，所以先断这一条。
	_ck(verifies >= 30, "正对照：tools/ 真的列出了 ≥30 条 verify_*.gd",
		"只列出 %d 条（导出后 DirAccess 不可用会让这一族空过）" % verifies)
	if verifies == 0:
		return

	var window_sh := _needs_window("res://tools/check_all.sh")
	var window_ps := _needs_window("res://tools/check_all.ps1")
	_ck(window_sh > 0, "正对照：check_all.sh 的 NEEDS_WINDOW 列得出来",
		"一格都没列出来，这一族会空过")
	if window_sh > 0:
		# 两份 runner 各写一份名单，而它们本来就必须一样——CLAUDE.md 里
		# 专门解释了 .ps1 为什么存在（没装 Git 的 Windows 上 bash 是 WSL）。
		# 只钉 .sh 的话，.ps1 少一条而默认轮次照跑不误。
		_ck(window_sh == window_ps,
			"check_all.sh 与 check_all.ps1 的 NEEDS_WINDOW 一样长",
			"sh=%d ps1=%d" % [window_sh, window_ps])

	var readmes := {"res://README.md": "README.md", "res://README.en.md": "README.en.md"}
	# **遍历字典只给 key，不给 pair**——第一版写成 `for pair in {...}` 之后
	# `pair[path]` 当场抛 "Invalid access ... on a base object of type 'String'"，
	# 于是这一节从中间掐断、下面 8 条一条没跑，而**汇总照样打 PASS**。
	# 那是 CLAUDE.md 里记着的"抛异常的回归退出码是 0"那一条的现场版：
	# 一行断言没打过的后半截看着像跑通了。所以末尾那条 `_ck(_checks >= …)`
	# 断的是"整份真的跑完了"，不是"跑到这儿为止都对"。
	for key in readmes:
		var path: String = key
		var label: String = readmes[key]
		if not FileAccess.file_exists(path):
			_ck(false, "%s 存在" % label)
			continue
		var txt := FileAccess.get_file_as_string(path)
		var is_en := label == "README.en.md"
		# **正向 + 反向成对写**。第一版只钉正向（"README 里得有 11 套出图"），
		# 突变验证把其中一处的 11 改回 8 —— 另一处还写着 11，于是
		# `contains` 照样为真、**一条都没红**。这和"落盘闸必须配正对照"、
		# "并集每一路都要配承重的正对照"是同一条：`contains` 量的是
		# "**某一处**写对了"，而同一件事在文档里会被写两遍（开头的总述 +
		# 下面那一节）。反向把**上一版的错值**钉死，"只改了一处"当场红。
		# **三元必须显式加括号**：GDScript 里 `a % n if c else b % n` 求值成
		# `(a if c else b) % n`——条件表达式的优先级比 `%` **高**，于是
		# 第一版把两种语言的后缀拿去当格式化参数，六个断言全红而读起来
		# "哪都对"。和 `ROAD_HALF_WIDTH := ROAD_WIDTH * 0.5` 那条同族：
		# 你以为谁先算，写出来才知道。
		var triples := [
			[("%d regressions" % verifies) if is_en else ("%d 条回归" % verifies),
				"four regressions" if is_en else "四条回归", "回归条数"],
			[("%d screenshot" % lookdevs) if is_en else ("%d 套出图" % lookdevs),
				"8 screenshot" if is_en else "8 套出图", "出图套数"],
			[("%d probes" % probes) if is_en else ("%d 条探针" % probes),
				"2 probes" if is_en else "2 条探针", "探针条数"],
		]
		for triple in triples:
			var want_txt: String = triple[0]
			var stale_txt: String = triple[1]
			var what: String = triple[2]
			_ck(txt.contains(want_txt), "%s 报的%s对得上仓库" % [label, what],
				"找不到「%s」" % want_txt)
			_ck(not txt.contains(stale_txt), "%s 里没有留下一处旧的%s" % [label, what],
				"还写着「%s」—— 同一件事文档里写了两遍，只改一处的话" % stale_txt
				+ "只钉正向那条永远不会红")
		if window_sh > 0:
			_ck(txt.contains("%d window-only" % window_sh if is_en
						else "%d 条要开窗口" % window_sh),
				"%s 报的要开窗口条数就是 NEEDS_WINDOW 的 %d 条" % [label, window_sh])

	# 整份真的跑完了吗。门槛 80 是**量出来的**：全绿跑一遍是 82 条，
	# 而 5.6 从中间掐断（字典迭代那个坑）时只有 74 条——差 8 条，
	# 汇总照样打 PASS。留 2 条余量给以后加断言。
	_ck(_checks >= 80, "这一整份真的跑完了（≥80 条断言，现在 %d）" % _checks,
		"某一节中途抛异常时汇总照样打 PASS —— 缺的那几条只有这条拦得住")


func _count_scripts(prefix: String) -> int:
	var d := DirAccess.open("res://tools")
	if d == null:
		return 0
	var n := 0
	for f in d.get_files():
		if f.begins_with(prefix) and f.ends_with(".gd"):
			n += 1
	return n


## 从 runner 脚本里把 `NEEDS_WINDOW` 那份名单数出来。**刻意不执行脚本**，
## 只数词——runner 自己就是按词拆的（`case " $NEEDS_WINDOW "`），
## 所以判据量的就是 runner 用的那一份。
##
## **必须跨行数**：`.ps1` 那份名单是折成两行写的，第一版只读 `NEEDS_WINDOW`
## 所在的那一行，于是数出来 0——而"0"和"这份 runner 没写名单"长得一模一样，
## 那条断言会安静地绿下去。同一族的教训：`grep` 到的一行不等于一份名单。
func _needs_window(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var in_list := false
	var names: Array[String] = []
	for raw in lines:
		var line: String = raw
		if not in_list:
			# .sh 写的是 `NEEDS_WINDOW="..."`，.ps1 写的是 `$NEEDS_WINDOW = @(...)`
			if not line.contains("NEEDS_WINDOW"):
				continue
			if not line.contains("="):
				continue
			in_list = true
			line = line.substr(line.find("=") + 1)
		names.append_array(_verify_names(line))
		# 收尾：这一行后面没有任何 `verify_` 了，且已经点过至少一个名字。
		# 收在"点过之后"而不是"行尾"，因为两份 runner 写完名单的那一行
		# 后面还跟着注释行，把注释里的 `verify_*` 数进去就虚高了。
		if names.size() > 0 and not line.contains("verify_"):
			break
	return names.size()


func _verify_names(line: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("verify_[A-Za-z0-9_]+")
	for m in re.search_all(line):
		out.append(m.get_string())
	return out
