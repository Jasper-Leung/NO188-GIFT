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
	# 例外是纯格式化 key（`visits_left_n` 的值就是 "%d"，它不带语言）：
	# 判据写成"把 % 规格符全去掉之后还剩不下字"，而不是列一张白名单——
	# 白名单每加一个键就多一个可以忘更新的地方。
	var same := []
	for k in zh.keys():
		if not en.has(k):
			continue
		var v := str(zh[k])
		if v != str(en[k]):
			continue
		var stripped := v.replace("%d", "").replace("%s", "").replace("%f", "")
		if stripped.strip_edges() == "":
			continue
		same.append(str(k))
	_ck(same.is_empty(), "没有中英逐字相同的 key（否则切语言等于没切）", str(same))
	print("[dbg] key 总数 %d（中）/ %d（英）" % [zh.size(), en.size()])


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

	# 5.3 相机参数是手抄的，代码里早就从 `* 8 + (0,5,0)` 改成了 `* 6 + (0,4,0)`。
	# 这里不比单个数字，而是把 Player3D.gd 里那一整行 `target_pos = ...` 整句抠出来，
	# 要求文档里逐字有同一句——手工拼一个 `-forward * 6.0` 当 needle 是错的：
	# 代码写的是 `global_position - forward * 6.0`，减号两边有空格，
	# 少写一个空格就永远匹配不上，而"永远匹配不上"和"文档写错了"
	# 在这一行上长得一模一样（第一版就是这么把自己坑了一轮）。
	var player := FileAccess.get_file_as_string("res://scripts/Player3D.gd")
	var m := RegEx.new()
	m.compile("var target_pos = global_position - forward \\* [0-9.]+ \\+ Vector3\\(0, [0-9.]+, 0\\)")
	var hit: RegExMatch = m.search(player)
	_ck(hit != null, "Player3D.gd 里找得到相机的 target_pos 那一行（防正则失效的空跑）")
	if hit != null:
		var line: String = hit.get_string()
		_ck(doc.contains(line), "文档里的相机定位与代码逐字一致",
				"代码是：%s" % line)
