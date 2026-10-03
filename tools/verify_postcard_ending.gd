extends SceneTree
## verify_postcard_ending.gd — 明信片纸面分级 + 终局二选一 回归
##
## 整合方案 §5.3 把明信片分成三层，只有第一层是买的。这个脚本验「买的那层」
## 和「选的那层」，中间「挣的那层」（五块碎片 → _variant）只验它没被档位带偏：
##   1. 纸面档位：0/1/2/3 各自的纸色、外框、帘纹、墨色
##   2. 越界档位：postcard_tier 被写成 99 或 -5 都要夹住，不能踩出调色板
##   3. 散件：宣纸 / 松烟墨 / 蜡封 / 信封 各管各的那一笔，且互不覆盖
##   4. 终局二选一：覆盖层压在明信片揭示之前；keep 把那句写上背面、
##      break 让背面留白并把封口的蜡掰开——抉择必须落在正面（导出那张 PNG）上，
##      不只是"多一句可改的预填"；点描述文字也算命中
##   5. 未竟：碎片不齐直接出明信片，背面留白
##   6. EndCard 管线：显示用的 Postcard 与导出用的 PostcardExport 拿到同一套纸面
##
## 颜色与档位名一律从 Postcard.gd 和 Localization 自己取（get_script_constant_map()
## + Localization.t()），不硬编码：改调色板或改文案不会把这条回归弄红。
## 购买链路（价格、碎片门槛、幂等扣账）已由 verify_economy.gd /
## verify_shop_world.gd 覆盖，所以这里直接摆 GameManager.inv，
## 只测「摆好之后画成什么样」。
##
## 像素级观感要带窗口看，见 tools/lookdev_postcard.gd。
##
## 用法： godot --headless --path . --script tools/verify_postcard_ending.gd

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _pc_script: GDScript = null
var _frag_idx: Array = []


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_ck(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _ensure_autoloads() -> void:
	var paths := {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}
	for n in paths:
		if root.get_node_or_null(n) == null:
			var node: Node = load(paths[n]).new()
			node.name = n
			root.add_child(node)


## 从 Postcard.gd 的常量表取调色板，别在测试里再抄一份颜色值。
func _pc(name: String) -> Variant:
	return _pc_script.get_script_constant_map().get(name, "<<missing: %s>>" % name)


## 摆背包再实例化一张明信片。tier <= 0 表示没买套餐。
func _make_postcard(tier: int, extras: Array) -> Control:
	_gm.reset()
	_gm.inv.clear()
	if tier > 0:
		_gm.inv["postcard_tier"] = tier
	for id in extras:
		_gm.inv[id] = 1
	var pc: Control = _pc_script.new()
	pc.name = "PC"
	pc.size = Vector2(900, 506)
	root.add_child(pc)
	await process_frame
	return pc


## 让 5 个碎片驿站都记 1 次打卡，使 _needs_choice() 成立。
func _collect_all() -> void:
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 1


## 摆 EndCard 并等两帧（_ready() 里有 tween，一帧不够）。
func _make_endcard() -> Control:
	var card: Control = load("res://scenes/EndCard.tscn").instantiate()
	root.add_child(card)
	await process_frame
	await process_frame
	return card


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
		await process_frame


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_loc.set_language("zh")
	_pc_script = load("res://scripts/Postcard.gd")
	_frag_idx = load("res://scripts/road_data.gd").get_script_constant_map().get(
		"FRAGMENT_SLOT_STATION_IDX", [])
	_gm.reset()
	_run.call_deferred()


func _run() -> void:
	print("=== 明信片纸面分级 + 终局二选一 ===")
	_ck("取到 5 个碎片驿站索引", _frag_idx.size() == 5, "got %d" % _frag_idx.size())

	# 每个 audit 都是协程（内部 await 帧），必须逐条 await，
	# 否则 _run() 跑完第一行就抢跑到汇总，全部断言变成"跑在 quit 之后"。
	await _audit_tiers()
	await _audit_extras()
	await _audit_variant_independent()
	await _audit_ending_choice()
	await _audit_ending_restored()
	await _audit_unfinished()
	await _audit_endcard_pipeline()
	await _audit_run_recap()

	_gm._clear_save()
	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)


func _audit_tiers() -> void:
	print("\n---------- 1. 纸面档位 ----------")
	var p0 = await _make_postcard(0, [])
	_eq("tier 0: _tier", p0._tier, 0)
	_eq("tier 0: 纸色", p0._paper, _pc("LAND_COL"))
	_eq("tier 0: 墨色", p0._ink, _pc("INK_COL"))
	_eq("tier 0: 外框色", p0._frame_col, _pc("FRAME_PLAIN"))
	_eq("tier 0: 外框宽", p0._frame_w, 4.0)
	_eq("tier 0: 无帘纹", p0._laid_lines, false)
	_eq("tier 0: 不打纸名", p0.tier_name(), "")
	var col0 = p0._paper
	await _free(p0)

	var p1 = await _make_postcard(1, [])
	_eq("tier 1: _tier", p1._tier, 1)
	_eq("tier 1: 素笺有自己的纸色", p1._paper, _pc("PAPER_PLAIN"))
	# 素笺必须和「没买套餐」分得开：买了张素笺却渲染成同一张纸，
	# 玩家根本看不出自己花了钱。
	_eq("tier 1 与 tier 0 纸色不同", p1._paper != col0, true)
	_eq("tier 1: 纸名", p1.tier_name(), _loc.t("tier_plain"))
	await _free(p1)

	var p2 = await _make_postcard(2, [])
	_eq("tier 2: _tier", p2._tier, 2)
	_eq("tier 2: 换了纸色", p2._paper, _pc("PAPER_FINE"))
	_eq("tier 2: 上笺有帘纹", p2._laid_lines, true)
	_eq("tier 2: 外框仍是素框", p2._frame_col, _pc("FRAME_PLAIN"))
	_eq("tier 2: 墨色未变", p2._ink, _pc("INK_COL"))
	_eq("tier 2: 纸名", p2.tier_name(), _loc.t("tier_fine"))
	await _free(p2)

	var p3 = await _make_postcard(3, [])
	_eq("tier 3: _tier", p3._tier, 3)
	_eq("tier 3: 换了纸色", p3._paper, _pc("PAPER_RARE"))
	_eq("tier 3: 金描边", p3._frame_col, _pc("FRAME_GOLD"))
	_eq("tier 3: 外框加宽", p3._frame_w, 6.0)
	_eq("tier 3: 有帘纹", p3._laid_lines, true)
	_eq("tier 3: 纸名", p3.tier_name(), _loc.t("tier_rare"))
	await _free(p3)

	# 存档被写坏 / 玩家手改过 inv 时档位可能是任意值，必须夹住
	var pbig = await _make_postcard(99, [])
	_eq("tier 99 夹到 3", pbig._tier, 3)
	_eq("tier 99 用珍藏纸", pbig._paper, _pc("PAPER_RARE"))
	await _free(pbig)

	var pneg = await _make_postcard(-7, [])
	_eq("tier -7 夹到 0", pneg._tier, 0)
	_eq("tier -7 不打纸名", pneg.tier_name(), "")
	await _free(pneg)


func _audit_extras() -> void:
	print("\n---------- 2. 散件 ----------")

	var pp = await _make_postcard(1, ["paper"])
	_eq("宣纸: 纤维标记", pp._fiber, true)
	_eq("宣纸: 顺带帘纹", pp._laid_lines, true)
	_eq("宣纸: 不改纸色（仍是素笺纸）", pp._paper, _pc("PAPER_PLAIN"))
	await _free(pp)

	var pi = await _make_postcard(1, ["ink"])
	_eq("松烟墨: 换墨色", pi._ink, _pc("INK_PINE"))
	_eq("松烟墨: 不动帘纹", pi._laid_lines, false)
	_eq("松烟墨: 不动纸色", pi._paper, _pc("PAPER_PLAIN"))
	await _free(pi)

	var ps = await _make_postcard(1, ["seal"])
	_eq("蜡封: 封口标记", ps._has_wax, true)
	_eq("蜡封: 不动纸色", ps._paper, _pc("PAPER_PLAIN"))
	await _free(ps)

	var pe = await _make_postcard(1, ["env"])
	_eq("信封: 折角标记", pe._has_env, true)
	_eq("信封: 不动纸色", pe._paper, _pc("PAPER_PLAIN"))
	await _free(pe)

	# 四件散件同时持有，每一件都得生效
	var pall = await _make_postcard(2, ["paper", "ink", "seal", "env"])
	_eq("全购: 纤维", pall._fiber, true)
	_eq("全购: 帘纹", pall._laid_lines, true)
	_eq("全购: 墨色", pall._ink, _pc("INK_PINE"))
	_eq("全购: 蜡封", pall._has_wax, true)
	_eq("全购: 信封", pall._has_env, true)
	_eq("全购: 仍是上笺纸", pall._paper, _pc("PAPER_FINE"))
	await _free(pall)

	# 宣纸的帘纹在素笺档也要生效——散件不该被档位挡掉
	var pplain_fiber = await _make_postcard(0, ["paper"])
	_eq("宣纸在 tier 0 也给帘纹", pplain_fiber._laid_lines, true)
	_eq("tier 0 + 宣纸仍不打纸名", pplain_fiber.tier_name(), "")
	await _free(pplain_fiber)


func _audit_variant_independent() -> void:
	print("\n---------- 3. 碎片档位不被纸面档位带偏 ----------")

	# 3 个碎片驿站各打 1 次 = 朝圣者（_variant 2），与纸面档位无关
	_gm.reset()
	for i in _frag_idx.size():
		if i < 3:
			_gm.collected[_frag_idx[i]] = 1
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 3
	var pc: Control = _pc_script.new()
	pc.name = "PC"
	pc.size = Vector2(900, 506)
	root.add_child(pc)
	await process_frame
	_eq("3 碎片 + 珍藏笺：_variant", pc._variant, 2)
	_eq("3 碎片 + 珍藏笺：_tier", pc._tier, 3)

	# 反过来：没买任何套餐，碎片档位照样算
	await _free(pc)
	_gm.reset()
	_collect_all()
	var pc2: Control = _pc_script.new()
	pc2.name = "PC"
	pc2.size = Vector2(900, 506)
	root.add_child(pc2)
	await process_frame
	_eq("5 碎片 + 无套餐：_variant", pc2._variant, 3)
	_eq("5 碎片 + 无套餐：_tier", pc2._tier, 0)
	await _free(pc2)

	# 五档布局里「占位灰块」与「真碎片」必须严格互斥：
	# 占位 ⇔ slot_idx < 0。历史上完满档第 5 格被误标成占位，玩家集齐五件
	# 却在最后一格看到灰底「?」，正好戳破「五块碎片无价」那层承诺。
	var layouts: Array = _pc("VARIANT_LAYOUTS")
	_eq("布局档位齐全", layouts.size(), 5)
	for li in layouts.size():
		for entry in layouts[li]:
			_ck("布局 %d 第 %s 格 占位标记与槽位一致" % [li, str(entry[0])],
					entry[1] == (entry[0] < 0), "entry=%s" % str(entry))

	await _audit_panel_identity()
	await _audit_route_map()


## 正面顶部那一块是「这一趟的路线图」：真中心线 + 16 座驿站的真实落点。
##
## 量的是几何，不是像素 —— `_draw()` 在 headless 下一笔都不落盘。投影抽成了
## `_map_project()`（不碰画笔的纯函数），所以「路有没有被框裁掉」在这里判得了；
## 以前那段云天连形状都没有，自然没什么可量的。
func _audit_route_map() -> void:
	print("\n---------- 3c. 正面路线图：这一趟真的画在这张卡上 ----------")
	var band: float = float(_pc("MAP_BAND_FRAC")) * 506.0
	_ck("顶部留给路线图的高度够画下一个 8 字（%.0fpx）" % band, band >= 150.0)
	# 顶部这一带 + 中间画区一共只能占 85%：底下 15% 压着路牌、落款和封口位。
	# 写成「frac + (0.85 - frac) == 0.85」是恒真的，等于没量——所以直接量
	# 地图方框的下沿：谁把 MAP_BAND_FRAC 调大，最先压住路牌的就是它。
	var pc: Control = await _make_postcard(1, [])
	pc._layout_map(900.0, band)
	var box: Rect2 = pc._map_rect
	_ck("地图方框是正方（%.0f×%.0f）" % [box.size.x, box.size.y],
			absf(box.size.x - box.size.y) < 0.5)
	_ck("地图方框整块在卡片里", box.position.x >= 0.0 and box.position.y >= 0.0
			and box.end.x <= 900.0 and box.end.y <= 506.0, "box=%s" % str(box))
	_ck("地图不压到中间那五格画区（方框下沿 %.0f ≤ 画区上沿 %.0f）" % [box.end.y, band],
			box.end.y <= band + 0.5)
	_ck("地图不压到底下那条路牌/落款（方框下沿 %.0f ≤ %.0f）" % [box.end.y, 506.0 * 0.85],
			box.end.y <= 506.0 * 0.85)

	# 16 座驿站**一个都不许被框裁掉**。fit 取的是 bbox 两边缩放的较小值，
	# 余量给负了的话 8 字的上下两个凸起正好压在框线上，定妆照上读成
	# 「图被裁了一刀」——而任何只量尺寸的断言都是绿的。
	var rd = load("res://scripts/road_data.gd").new()
	_ck("拿得到 16 座驿站", rd.stations.size() == 16)
	var worst := 1e9
	for i in rd.stations.size():
		var p: Vector2 = pc._map_project(rd.get_station_world_pos(i))
		worst = minf(worst, minf(minf(p.x - box.position.x, box.end.x - p.x),
				minf(p.y - box.position.y, box.end.y - p.y)))
	_ck("16 座驿站全在框内（离框最近的那个还有 %.1fpx）" % worst, worst >= 0.5)

	# 碎片站不能叠在同一个点上。这一条一断，图上就是「五个点全挤在一处」，
	# 而那恰好是最坏的读法：看着像五件都收了，其实只画出一处。
	var seen := {}
	for st_idx in [7, 10, 13, 14, 4]:
		var p: Vector2 = pc._map_project(rd.get_station_world_pos(int(st_idx)))
		var key := "%.0f,%.0f" % [p.x, p.y]
		_ck("碎片站 %d 在图上有自己的位置" % int(st_idx), not seen.has(key))
		seen[key] = true

	# 买了信封之后方框要让开左上角的折角。第一版没让开，框线的一角和 8 字
	# 的左上凸起都被折角削掉一块 —— 而当时所有断言都是绿的。
	var fold: float = minf(900.0, 506.0) * 0.16
	var penv: Control = await _make_postcard(1, ["env"])
	penv._layout_map(900.0, band)
	_ck("买了信封，地图方框让开折角（左边距 %.0fpx > 折角 %.0fpx）"
			% [penv._map_rect.position.x, fold], penv._map_rect.position.x > fold)
	_ck("让开之后方框仍然整块在卡片里",
			penv._map_rect.end.x <= 900.0 and penv._map_rect.end.y <= 506.0,
			"box=%s" % str(penv._map_rect))

	# 图上那几行字全部现算自存档，一个字都不另存：驿数走
	# GameManager，五件次数走 collected —— 玩家导出前改了存档，
	# 拿到的就该是改过的那张。
	# 注意顺序：_make_postcard() 自己会 _gm.reset()，所以存档必须**建完卡之后**
	# 再摆 —— 摆在前面会被它清掉，而三行断言于是全读成 0，看着像图不认存档。
	var pvis: Control = await _make_postcard(1, [])
	_gm.collected[7] = 2
	_gm.collected[10] = 1
	_gm.seen_stations[4] = true
	_gm.seen_stations[7] = true
	_eq("图上的驿数就是存档里的驿数", _gm.get_seen_station_count(), 2)
	# 驿数那行**不带分母**：原来写死「已过 %d/%d 驿」，那个 16 长在文案里，
	# 扩充驿站就得回来改字符串，改漏了顶栏就在说一个世界里已经没有的数。
	_ck("驿数那行是渲染后的整句，不是 key 本身",
			_loc.t("stations_seen") % [2] == "已过 2 驿",
			"got=%s" % (_loc.t("stations_seen") % [2]))
	_ck("驿数那行不写死分母（扩充驿站不用改文案）",
			not str(_loc.t("stations_seen")).contains("/"),
			"got=%s" % _loc.t("stations_seen"))
	_eq("云那格的次数就是存档里的次数", int(_gm.collected[7]), 2)
	_eq("茶那格的次数就是存档里的次数", int(_gm.collected[10]), 1)
	# 五个数逐个点过：抄一份下标表而顺序错了的话，只有这条会红
	var vis: Array = []
	for st_idx in [7, 10, 13, 14, 4]:
		vis.append(int(_gm.collected.get(st_idx, 0)))
	_eq("五件次数没串位（云 2 / 茶 1 / 琴 0 / 竹 0 / 禽 0）", str(vis), str([2, 1, 0, 0, 0]))

	# 图例那句话不许在中英两侧退化成 key 本身（Localization.t 查不到 key
	# 时返回 key 自己，既不报错也不返回空串——中文界面一路正常，
	# 只有切到英文的那一屏露 key）。
	for k in ["postcard_map_title", "postcard_map_legend"]:
		_ck("%s 有中文" % k, str(_loc.STRINGS["zh"].get(k, "")) != k)
		_ck("%s 有英文" % k, str(_loc.STRINGS["en"].get(k, "")) != k)
		_ck("%s 中英不是同一句" % k,
				str(_loc.STRINGS["zh"].get(k, "")) != str(_loc.STRINGS["en"].get(k, "")))

	await _free(pvis)
	await _free(penv)
	await _free(pc)

	await _audit_joys_column()
	await _audit_back_message()


## 抬头右半那列（五件乐事各到访几次）。
##
## 它替掉的是**一整块空白的纸**：原来五个次数挤在「已过 n/16 驿」底下那一行，
## 剩下约 880×410px 什么也没有，而这是玩家唯一带走的那张卡的抬头。
## 判据量三件玩家读得出来的事：这一列**真的占到了右沿**（不是换了个地方
## 继续空着）、**不压在左边那一列的字上**、**每一行放得下**——
## 最后这条是必须的，因为 `draw_string` 的宽度参数是**裁切宽度**，
## 而次数是右对齐画上去的：字比列宽就整段被裁掉，而尺寸断言照样全绿。
func _audit_joys_column() -> void:
	print("\n---------- 3d. 抬头右半：五件乐事那一列 ----------")
	var font: Font = ThemeDB.fallback_font
	# 驿数那一行的最宽情形取**驿站总数**。从 road_data 独立取一次而不是读
	# `pc._rd`——那个字段正是被测的画笔自己算的，拿它当判据等于拿自己测自己。
	var total_stations: int = load("res://scripts/road_data.gd").new().stations.size()
	for lang in ["zh", "en"]:
		_loc.set_language(lang)
		for cw in [900.0, 1920.0]:
			var ch: float = cw * 900.0 / 1920.0
			var band: float = float(_pc("MAP_BAND_FRAC")) * ch
			var pc: Control = await _make_postcard(1, [])
			var k: float = pc._map_k(cw)
			pc._layout_map(cw, band)
			var xa: float = pc._map_rect.position.x + pc._map_rect.size.x + 22.0 * k
			var colw: float = pc._caption_col_w(font, k)
			var x0: float = xa + colw + cw * 0.05
			var r: Rect2 = pc._joys_column_rect(cw, band, k, x0)
			var tag := "%s %.0fpx" % [lang, cw]

			_ck("%s 这一列排得下（宽 %.0fpx）" % [tag, r.size.x], r.size.x > 0.0)
			# 真正要拦的是"换了个地方继续空着"：右沿离卡片右边不得超过两成宽
			var dead: float = cw - r.end.x
			_ck("%s 抬头右沿不留死区（右边还剩 %.0fpx = %.1f%% 宽）"
					% [tag, dead, dead / cw * 100.0], dead < cw * 0.2)
			# 不许压在左边那一列的字上。列宽是**量出来**的最宽情形，
			# 按实际驿数起步的话玩家到过的驿越多、这里离字越近。
			#
			# 注意这里**不拿 `_caption_col_w()` 当判据**：那条断言的两边
			# 读的是同一个函数，helper 算窄了它照样全绿（第一版的这个缺陷）。
			# 判据改成**在测试里把那三行字各自量一遍**——量的是"列 B 起点
			# 有没有越过左边真的画出去的那几行字的右沿"。
			var col_a_w: float = 0.0
			col_a_w = maxf(col_a_w, font.get_string_size(
					_loc.t("postcard_map_title"), HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(20 * k)).x)
			# 用**最宽的情形**那句（驿数最大时），和画笔里 `_caption_col_w()`
			# 同一个口径 —— 它取的是 `RoadData` 的驿站总数，不是这一趟的实际值。
			col_a_w = maxf(col_a_w, font.get_string_size(
					_loc.t("stations_seen") % [total_stations], HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(28 * k)).x)
			col_a_w = maxf(col_a_w, font.get_string_size(
					_loc.t("postcard_map_legend"), HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(14 * k)).x + 44.0 * k)
			_ck("%s 这一列起在左边那一列的字之后（%.0f ≥ %.0f + %.0f）"
					% [tag, r.position.x, xa, col_a_w],
					r.position.x >= xa + col_a_w - 0.5)
			_ck("%s `_caption_col_w` 没有算窄（%.0f ≥ %.0f）"
					% [tag, colw, col_a_w], colw >= col_a_w - 0.5)
			_ck("%s 这一列不压到地图方框" % tag, r.position.x > pc._map_rect.end.x)
			# 下沿不许压进中间那五格画区
			_ck("%s 这一列不压到五格画区（下沿 %.0f ≤ 带高 %.0f）"
					% [tag, r.end.y, band], r.end.y <= band + 0.5)
			# 右沿要给那只禽让开道（它画在 w-120k，半径 14.4k）
			_ck("%s 这一列和禽不叠" % tag, r.end.x <= cw - 150.0 * k + 0.5)
			# **每一行放得下**：名字 + 次数，右对齐在列宽之内
			var worst := 0.0
			for slot in 5:
				var name: String = _loc.t("fragment_%d" % slot)
				var cnt: String = _loc.t("postcard_visit_n") % 3
				var need: float = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT,
						-1, int(20 * k)).x + 12.0 * k \
						+ font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_RIGHT,
						-1, int(17 * k)).x
				worst = maxf(worst, need)
			_ck("%s 每一行放得下（最宽那行 %.0fpx ≤ 列宽 %.0fpx）"
					% [tag, worst, r.size.x], worst <= r.size.x)
			await _free(pc)
	_loc.set_language("zh")
	# 上面那十几条量的是**几何函数**，而几何函数对不对和画笔有没有去调它
	# 是两件事 —— 把 `_draw_map_caption()` 里那一行删掉，上面全绿而图上
	# 那一块重新变成空白的纸。所以照 `verify_mini_game.gd` 第 6g 节的读法，
	# 从**源码文本**里钉住这一行确实在画笔身上（`_draw` 在 headless 下
	# 一笔都不落盘，纯函数量不到调用点）。
	var src: String = FileAccess.get_file_as_string("res://scripts/Postcard.gd")
	var body: String = src.substr(src.find("func _draw_map_caption"),
			src.find("func _caption_col_w") - src.find("func _draw_map_caption"))
	_ck("_draw_map_caption 真的调了 _draw_joys_column",
			body.contains("_draw_joys_column("), "画笔没调它，那一块还是空白的纸")
	_ck("旧的「名字+次数挤成一行」已经拿掉了（%s%d 那个拼接）",
			not body.contains('"%s%d"'), "两列会同时画在这一带")
	for k in ["postcard_joys_title", "postcard_visit_n"]:
		_ck("%s 有中文" % k, str(_loc.STRINGS["zh"].get(k, "")) != k)
		_ck("%s 有英文" % k, str(_loc.STRINGS["en"].get(k, "")) != k)
		_ck("%s 中英不是同一句" % k,
				str(_loc.STRINGS["zh"].get(k, "")) != str(_loc.STRINGS["en"].get(k, "")))


func _audit_back_message() -> void:
	print("\n---------- 3e. 背面正文：预览里读不读得出自己写了什么 ----------")
	# 这一族量的**不是**"字号是 36"这种实现细节，是玩家在编辑器那一屏上
	# 真的看到多高的一行字。卡片在 SubViewport 里按 1920 宽画完再缩到预览上，
	# 于是屏上字高 = 卡片字号 × 预览宽 / 1920 —— 三个数缺一个都量不出来。
	var pb = load("res://scripts/PostcardBack.gd")
	var card: Control = pb.new()
	var font: Font = ThemeDB.fallback_font
	# 预览宽度的**下界**（第 3 节钉的就是这条：tw >= 400）。用下界算，
	# 判据就与玩家那台机器的分辨率无关了——屏越高预览越宽，只会更宽。
	const CARD_W := 1920.0
	const THUMB_FLOOR := 400.0

	var box: Rect2 = card._message_box(CARD_W, 1080.0)
	var max_w: float = box.size.x - card.MSG_PAD * 2.0
	var max_h: float = box.size.y - card.MSG_PAD * 2.0
	print("    正文框 %s → 可用 %.0f × %.0f" % [box, max_w, max_h])
	_ck("正文框在卡片里（没出屏、没退化成一条缝）",
			box.position.x >= 0.0 and box.end.x <= CARD_W
			and box.size.y > 0.3 * 1080.0,
			"%s" % box)

	var n: int = int(card.MAX_CHARS)
	for lang in ["zh", "en"]:
		_loc.set_language(lang)
		# 两种长度都要量：编辑器里**默认**预填的那句，和玩家真的写满 200 字
		# 的最坏情形。原来写死 36 时后者在框里只占四五行、留下大半张空纸。
		var cases := {
			"默认那句": _loc.t("back_keep"),
			"写满 %d 字" % n: ("写" if lang == "zh" else "word ")\
					.repeat(n).substr(0, n),
		}
		for cname in cases:
			var text: String = cases[cname]
			var tag := "%s·%s" % [lang, cname]
			var fs: int = card._message_font_size(font, text, max_w, max_h)
			var lines: Array = card._wrap_text(font, text, fs, max_w)

			var widest: float = 0.0
			for l in lines:
				widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT,
						-1, fs).x)
			_ck("%s 每一行都在框宽之内（最宽 %.0f ≤ %.0f）" % [tag, widest, max_w],
					widest <= max_w + 0.5)
			var block: float = lines.size() * (font.get_height(fs) + card.LINE_GAP)
			_ck("%s 整块在框高之内（%.0f ≤ %.0f）" % [tag, block, max_h],
					block <= max_h + 0.5)
			# 字号的**下限**是玩家读不看得见的那条线。预览宽 400（下界）
			# 时 12px 是一行 CJK 的及格线——再小就不是"字"，是纹理了。
			var on_screen: float = float(fs) * THUMB_FLOOR / CARD_W
			_ck("%s 预览里的一行字 ≥12px（卡片 %dpx → 屏上 %.1fpx）"
					% [tag, fs, on_screen], on_screen >= 12.0)

			# 反过来：字号是**从大往下找的第一个放得下的**，不是随便一个放得下的。
			# 少了这条，把 LINE_GAP 或 FONT_MAX 调小到"还更空"也照样全绿——
			# 和第 3d 节那条「`_caption_col_w` 没有算窄」同一个坑。
			# 顶上那档是 FONT_MAX，"再大一号"在它那儿不成立，所以那一种情形
			# 单独判成"顶到上限了"，别把它算成"还有余量没用"。
			var capped: bool = fs >= int(card.FONT_MAX)
			var bigger: Array = card._wrap_text(font, text, fs + 4, max_w)
			var b_block: float = bigger.size() * (font.get_height(fs + 4) + card.LINE_GAP)
			_ck("%s 字号用满了（%dpx 是 FONT_MAX，或者大一号 %.0f > %.0f 放不下）"
					% [tag, fs, b_block, max_h], capped or b_block > max_h)

	# 上面量的是纯函数，而"画笔有没有去调它"是另一件事：把 `_draw_message`
	# 里的 `var font_size := 36` 改回来，上面十条全绿，而预览里那行字
	# 又变回八像素。照 `verify_mini_game.gd` 第 6g 节的读法从源码文本里钉住。
	var src: String = FileAccess.get_file_as_string("res://scripts/PostcardBack.gd")
	var body: String = src.substr(src.find("func _draw_message"),
			src.find("func _wrap_line") - src.find("func _draw_message"))
	_ck("_draw_message 真的调了 _message_font_size（不是自己写死一个号）",
			body.contains("_message_font_size("), "画笔绕过了那个函数")
	_ck("_draw_message 里没有写死的 36", not body.contains("36"),
			"写死的字号就是原来那 8px 的根")
	_loc.set_language("zh")
	card.free()



## 画区那一格的「颜色 / 图标 / 标签」必须讲同一件碎片。
## 历史上颜色表和图标分派各整体错位一格而标签是对的：五格里错四格，
## 而两张错位的表彼此自洽，缩略图一眼扫过去完全正常——可玩家存走的那张
## PNG 就是这张错位图。颜色已改成 FRAGMENT_COLS[slot_idx] 按下标查，
## 下面这三条把「三处同序」钉死：调色板不许分叉、五个名字不许重名、
## 完满档五格必须一次覆盖五件。
func _audit_panel_identity() -> void:
	print("\n---------- 3b. 画区颜色/图标/标签同序 ----------")
	var cols: Array = _pc("FRAGMENT_COLS")
	_eq("FRAGMENT_COLS 是五件", cols.size(), 5)

	# 顶栏碎片栏那份同名常量表是玩家最先认下的配色，两处不许分叉
	var fb = load("res://scripts/FragmentBar.gd")
	_ck("与 FragmentBar.FRAGMENT_COLORS 逐件一致",
			str(cols) == str(fb.FRAGMENT_COLORS),
			"postcard=%s bar=%s" % [str(cols), str(fb.FRAGMENT_COLORS)])

	# 五个格子写着五个字。两个 key 若指到同一句，上面那条同序就失去意义，
	# 而「云字下面配一只鸟」在图上仍然是自洽的，只能靠这里拦。
	var uniq := {}
	for i in 5:
		uniq[_loc.t("fragment_%d" % i)] = true
	_eq("五件碎片的名字互不相同", uniq.size(), 5)

	# 完满档五格全真，逐一确认它引用的正是 0..4 —— 布局表最容易出的错就是
	# 少一格或重一格，五个真格如果只是四个下标加一个重复，图标就会重影。
	var layout: Array = _pc_script.VARIANT_LAYOUTS[4]
	_eq("完满档五格", layout.size(), 5)
	var seen := {}
	for i in layout.size():
		var slot: int = layout[i][0]
		_eq("完满第 %d 格就是第 %d 件" % [i, i], slot, i)
		_eq("完满第 %d 格不是占位" % [i], layout[i][1], false)
		seen[cols[slot].to_html(false)] = true
	_ck("五格颜色恰好覆盖五件碎片", seen.size() == 5, "seen=%s" % str(seen.keys()))


func _audit_ending_choice() -> void:
	print("\n---------- 4. 终局二选一 ----------")
	_gm.reset()
	_collect_all()
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 2

	var card = await _make_endcard()
	_ck("需要抉择", card._needs_choice())
	_ck("覆盖层已建", card._ending_overlay != null)
	_ck("抉择期间明信片藏着", not card._postcard.visible)
	_ck("抉择期间按钮栏藏着", not card.get_node("VBox").visible)

	var ed: Control = card._ending_overlay
	_eq("覆盖层铺满", ed.size, card.size)
	_eq("覆盖层子节点数", ed.get_child_count(), 5)

	# 几何体检：项目在这上面摔过多次（锚点不写、size 与 offset 互踩）
	var i := 0
	for c in ed.get_children():
		var r: Rect2 = c.get_rect()
		var inside := r.position.y >= -0.5 and r.end.y <= ed.size.y + 0.5 \
				and r.end.x <= ed.size.x + 0.5 \
				and r.size.x > 0.0 and r.size.y > 0.0
		_ck("[%d] %s 正尺寸且在界内" % [i, c.get_class()], inside, "rect=%s" % str(r))
		i += 1

	_ck("两张抉择卡都在树里", ed.get_node_or_null("Choice_keep") != null
			and ed.get_node_or_null("Choice_break") != null)
	var keep_card: Control = ed.get_node("Choice_keep")
	var break_card: Control = ed.get_node("Choice_break")

	# 文案齐：标题、提示、两条分支的标题与正文
	# 卡片正文写的就是选完之后真正会发生的事：留门 = 背面就多这一句，
	# 放手 = 背面留白、蜡封掰开、那句话退成占位提示。所以这里比的是
	# back_keep 和 back_break_blank，不是"两个形容"。
	_eq("标题文案", card._choice_title.text, _loc.t("ending_title"))
	_eq("提示文案", card._choice_hint.text, _loc.t("ending_hint"))
	_eq("留门标题", card._choice_keep_title.text, _loc.t("ending_keep"))
	_eq("留门正文 = 背面那一句", card._choice_keep_desc.text, _loc.t("back_keep"))
	_eq("放手标题", card._choice_break_title.text, _loc.t("ending_break"))
	_eq("放手正文说的是留白", card._choice_break_desc.text, _loc.t("back_break_blank"))
	_ck("两条正文说的不是同一件事", card._choice_keep_desc.text != card._choice_break_desc.text)
	_eq("抉择前背面留白", card._back_text, "")
	_eq("抉择前 ending_id 为空", _gm.ending_id, "")

	# 松开 / 右键 / 点空区都不算选择
	_click(keep_card, false, MOUSE_BUTTON_LEFT)
	_eq("松开不算选择", _gm.ending_id, "")
	_click(keep_card, true, MOUSE_BUTTON_RIGHT)
	_eq("右键不算选择", _gm.ending_id, "")

	# 点「守住归途」
	_click(keep_card, true, MOUSE_BUTTON_LEFT)
	_eq("选择后 ending_id", _gm.ending_id, "keep")
	_eq("播种背面文案", card._back_text, _loc.t("back_keep"))
	_eq("背面卡片同步", card._back_postcard.get_back_text(), _loc.t("back_keep"))
	# 抉择必须落在**正面**上，否则玩家的收获就是"多一句可改的预填"。
	# 蜡封是留门/放手之间唯一画在正面的差别，而正面才是导出的那张 PNG。
	_ck("留门：蜡封是完好的", not card._postcard.seal_broken())
	_ck("留门：导出卡片的蜡封也是完好的", not card._postcard_export.seal_broken())
	_eq("覆盖层已清", card._ending_overlay, null)
	_ck("明信片已揭示", card._postcard.visible)
	_ck("按钮栏已揭示", card.get_node("VBox").visible)
	# queue_free 是延迟的，等两帧再验节点真的没了
	await process_frame
	await process_frame
	_ck("覆盖层节点已释放", not is_instance_valid(ed))
	_ck("抉择卡节点已释放", not is_instance_valid(keep_card))

	# 已选过就不能再弹
	_eq("选过后不再要求抉择", card._needs_choice(), false)

	# 背面编辑器拿到的应该是那句定稿，不是空框 + 占位提示
	card._show_back_editor()
	await process_frame
	_eq("编辑器预填默认文案", card._back_text_edit.text, _loc.t("back_keep"))

	# 写字时的卡片缩略图：这一屏原本是「空框 + 两个按钮」，玩家不知道字会印成什么样。
	# 缩略图抓的是导出同一个 SubViewport 的纹理，所以要拦的是"改了字、卡片没跟着改"
	# —— set_back_text() 原来只在确认时才调，整个写字过程里预览一直停在选完那句。
	_ck("编辑器里有卡片缩略图", card._back_thumb != null
			and is_instance_valid(card._back_thumb))
	_ck("缩略图不拦截点击", card._back_thumb.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_ck("缩略图有说明文字", card._back_thumb_caption != null
			and card._back_thumb_caption.text == _loc.t("back_preview_caption"))
	# 缩略图不能压到两个按钮上、也不能出屏。两处都拿真视口尺寸比：
	# 这一屏的布局全按 get_viewport_rect().size 算，写死 720 会在别的分辨率下
	# 拿一个不存在的屏高去判（headless 这里的视口就不是 720 高）。
	var vh: float = card.get_viewport_rect().size.y
	var skip_bottom: float = vh * float(card.THUMB_BTN_Y_FRAC) + float(card.THUMB_BTN_H)
	_ck("缩略图不遮按钮", card._back_thumb.offset_top > skip_bottom,
			"上沿 %.0f，按钮下沿 %.0f" % [card._back_thumb.offset_top, skip_bottom])
	_ck("两个按钮不叠在一起（叠着就各吃一行，预览的份额又少一截）",
			absf(card._back_skip_btn.offset_left - card._back_confirm_btn.offset_left)
					>= card._back_confirm_btn.offset_right
					- card._back_confirm_btn.offset_left - 1.0,
			"确认 %.0f~%.0f，跳过 %.0f~%.0f" % [
				card._back_confirm_btn.offset_left, card._back_confirm_btn.offset_right,
				card._back_skip_btn.offset_left, card._back_skip_btn.offset_right])
	_ck("两个按钮都在屏内",
			card._back_confirm_btn.offset_right <= card.get_viewport_rect().size.x
			and card._back_skip_btn.offset_right <= card.get_viewport_rect().size.x,
			"确认右沿 %.0f，跳过右沿 %.0f" % [card._back_confirm_btn.offset_right,
			card._back_skip_btn.offset_right])
	_ck("缩略图不出屏", card._back_thumb.offset_bottom <= vh,
			"底沿 %.0f，屏高 %.0f" % [card._back_thumb.offset_bottom, vh])
	_ck("说明行也没出屏", card._back_thumb_caption.offset_top >= 0.0
			and card._back_thumb_caption.offset_bottom <= card._back_thumb.offset_top,
			"caption %.0f~%.0f, thumb %.0f" % [card._back_thumb_caption.offset_top,
			card._back_thumb_caption.offset_bottom, card._back_thumb.offset_top])
	# 预览的意义全在"字看得清"。原来固定 200px 宽 —— 卡片在 SubViewport 里按原
	# 尺寸画完再缩下来，200px 宽的预览里一行字只剩七来个像素高，放大三倍也读不
	# 出是哪个字，"所见即导出"就成了一句空话。要 400 以上才认得出自己写的那句。
	# 判的是宽度下限：`_add_back_thumb` 先按屏宽算一遍（上限 460），再按"按钮
	# 下沿到屏底"的空当算一遍高度，取小的。headless 的视口比 720p 高，高度那道
	# 约束在这里不生效，所以量到的就是屏宽那一档 —— 正好是个下界。
	# 比 720p 更矮的屏上预览会等比缩下去，那是有意的降级，不在这里拦。
	var tw: float = card._back_thumb.offset_right - card._back_thumb.offset_left
	_ck("预览至少有 400px 宽（原来只有 200，字读不出来）", tw >= 400.0,
			"%.0fpx @ 视口 %dx%d" % [tw, int(card.get_viewport_rect().size.x), int(vh)])
	# 宽度只是这条链的**一半**：卡片在 SubViewport 里按 1920 宽画完再缩下来，
	# 屏上那行字多高 = 卡片上的字号 × 预览宽 / 1920。原来卡片上写死 36px，
	# 预览再宽也白搭（36 × 452 / 1920 = 8.5px），而两条都绿着。
	# 所以这里把**真预览**和**真字号**接起来量一次。
	var back: Control = card._back_postcard
	var pbox: Rect2 = back._message_box(1920.0, 1080.0)
	var bfs: int = back._message_font_size(ThemeDB.fallback_font, back.get_back_text(),
			pbox.size.x - back.MSG_PAD * 2.0, pbox.size.y - back.MSG_PAD * 2.0)
	var on_screen: float = float(bfs) * tw / 1920.0
	print("    预览 %.0fpx 宽（视口 %dx%d）× 卡片字号 %dpx → 屏上 %.1fpx"
			% [tw, int(card.get_viewport_rect().size.x), int(vh), bfs, on_screen])
	_ck("预览里那行字真的读得出来（%.1fpx ≥ 12px）" % on_screen, on_screen >= 12.0)

	# 手动发信号：程序化赋 .text 不发 text_changed（_on_back_confirmed 里也是因此
	# 才回头再读一次 TextEdit）。这里要的就是"玩家敲了一个键"那一刻发生的事。
	card._back_text_edit.text = "改过的字"
	card._back_text_edit.text_changed.emit()
	await process_frame
	_eq("打字立刻同步到背面卡片", card._back_postcard.get_back_text(), "改过的字")
	_eq("打字写进 _back_text", card._back_text, "改过的字")
	_ck("打字把缩略图置脏", card._back_thumb_dirty)
	# 节流是按累计 delta 掐的（THUMB_REFRESH_SEC = 0.12s），headless 下 process_frame
	# 的 delta 只有一两毫秒，跑两帧等不到阈值——必须等墙钟。
	await create_timer(0.25).timeout
	await process_frame
	_ck("缩略图已刷新回干净状态", not card._back_thumb_dirty)
	await _free(card)


func _click(card: Control, pressed: bool, button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.pressed = pressed
	ev.button_index = button
	# gui_input 的连接是带 bind(ending) 的，所以这里只发事件本身，
	# 分支参数由 connect 时绑的 ending 补齐
	card.gui_input.emit(ev)


func _audit_ending_restored() -> void:
	print("\n---------- 5. 存档恢复已选结局 ----------")
	# 读档后 ending_id 已经在，不该再弹一次二选一
	_gm.reset()
	_collect_all()
	_gm.set_ending("break")
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 3

	var card = await _make_endcard()
	_eq("已选过：不需要抉择", card._needs_choice(), false)
	_eq("已选过：没有覆盖层", card._ending_overlay, null)
	_ck("已选过：明信片直接出", card._postcard.visible)
	_ck("已选过：按钮栏直接出", card.get_node("VBox").visible)
	_eq("已选过（放手）：背面留白", card._back_text, "")
	_eq("已选过（放手）：背面卡片也留白", card._back_postcard.get_back_text(), "")
	_ck("已选过（放手）：蜡封是掰开的", card._postcard.seal_broken())
	# 那句话没有消失，只是退成了灰色占位提示——摆在那儿，拿不拿随玩家。
	card._show_back_editor()
	await process_frame
	_eq("放手时占位提示是那句没写上去的话",
			card._back_text_edit.placeholder_text, _loc.t("back_break"))
	_eq("放手时输入框仍然是空的", card._back_text_edit.text, "")
	await _free(card)


func _audit_unfinished() -> void:
	print("\n---------- 6. 未竟（碎片不齐） ----------")
	# 只到 4 块碎片就走 K188：不弹二选一，直接出一张正面缺格、背面空白的明信片。
	# 这是 §2.2「no failure state」在结局层的兑现——礼物仍然成立。
	_gm.reset()
	for i in _frag_idx.size():
		if i < 4:
			_gm.collected[_frag_idx[i]] = 1
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 1

	var card = await _make_endcard()
	_eq("未竟：不弹二选一", card._needs_choice(), false)
	_eq("未竟：没有覆盖层", card._ending_overlay, null)
	_ck("未竟：明信片照样出", card._postcard.visible)
	_eq("未竟：背面留白", card._back_text, "")
	_eq("未竟：背面卡片留白", card._back_postcard.get_back_text(), "")
	_eq("未竟：ending_id 保持空", _gm.ending_id, "")
	# 正面缺格：4 个碎片 → 大师（_variant 3）
	_eq("未竟：正面按碎片数出格", card._postcard._variant, 3)
	await _free(card)


func _audit_endcard_pipeline() -> void:
	print("\n---------- 7. 显示与导出拿同一套纸面 ----------")
	_gm.reset()
	_collect_all()
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 3
	for id in ["paper", "ink", "seal", "env"]:
		_gm.inv[id] = 1

	var card = await _make_endcard()
	# 抉择走完，两边才算真正的产出状态
	_click(card._ending_overlay.get_node("Choice_break"), true, MOUSE_BUTTON_LEFT)
	await process_frame
	await process_frame

	_eq("显示卡片 tier", card._postcard._tier, 3)
	_eq("导出卡片 tier", card._postcard_export._tier, 3)
	_eq("显示卡片纸色", card._postcard._paper, _pc("PAPER_RARE"))
	_eq("导出卡片纸色", card._postcard_export._paper, _pc("PAPER_RARE"))
	_eq("显示卡片金边", card._postcard._frame_col, _pc("FRAME_GOLD"))
	_eq("导出卡片金边", card._postcard_export._frame_col, _pc("FRAME_GOLD"))
	_eq("导出卡片松烟墨", card._postcard_export._ink, _pc("INK_PINE"))
	_eq("导出卡片蜡封", card._postcard_export._has_wax, true)
	_eq("导出卡片信封", card._postcard_export._has_env, true)
	_eq("导出卡片帘纹", card._postcard_export._laid_lines, true)
	_eq("导出卡片纸名", card._postcard_export.tier_name(), _loc.t("tier_rare"))
	# 抉择的痕迹必须一起进导出：显示的正面和导出的正面要是两回事，
	# 玩家看到的是掰开的蜡、拿到的 PNG 却是一枚完好的，那就成了渲染事故。
	_ck("放手：显示卡片蜡封掰开", card._postcard.seal_broken())
	_ck("放手：导出卡片蜡封也掰开", card._postcard_export.seal_broken())
	await _free(card)


## 走完整一趟之后按「重新开始」，弹出来的是这一趟真实漏掉的东西。
##
## 拦的是两种失败：**编**（说了玩家没做过的事，第二趟发现根本没有，比不弹
## 更伤）和**漏**（明明漏了却不说，回执变成一句客套）。所以每一条都对着
## 摆出来的存档逐字核对：报到几个驿、哪几块碎片没拿、哪几件没赢过。
func _audit_run_recap() -> void:
	print("\n---------- 8. 重新开始前的「这一趟」回执 ----------")
	var rd = load("res://scripts/road_data.gd").new()
	var total_stations: int = rd.stations.size()

	# 空存档：连一块碎片都没有，press restart 不该弹回执（nothing to recap）
	_gm.reset()
	var fresh = await _make_endcard()
	_eq("空存档：不弹回执", fresh._recap_worth_showing(), false)
	await _free(fresh)

	# 摆一趟"只骑了一半"的真实存档
	_gm.reset()
	var seen := [0, 1, 4, 7, 10]          # 5 座驿站，其中 4/7/10 是碎片站
	for i in seen:
		_gm.seen_stations[i] = true
	for st_idx in [_frag_idx[0], _frag_idx[1]]:
		_gm.collected[st_idx] = 1
	_gm.earned_tags["mini_%d_win" % _frag_idx[0]] = true
	_gm.earned_tags["mini_%d_lose" % _frag_idx[1]] = true
	_gm.lvbi = 40
	_gm.inv.clear()

	var card = await _make_endcard()
	_eq("半途：弹回执", card._recap_worth_showing(), true)

	var lines: Array = card._recap_lines()
	var joined := "\n".join(lines)
	print("    回执：\n      " + joined.replace("\n", "\n      "))

	# 没拿到的碎片：3 块，按碎片顺序点名，一个不多一个不少。
	# 拿渲染后的整句去比，不要拿 key 里的 "%s" 去 contains —— 那永远匹配不上。
	var missing: Array = []
	for st_idx in _frag_idx:
		if not _gm.is_collected(st_idx):
			missing.append(rd.station_display_fragment(st_idx))
	_eq("点出漏掉的碎片数", missing.size(), 3)
	_ck("漏碎片那一行逐字对得上",
			lines.has(_loc.t("recap_frag_missing") % _join(missing)),
			"lines=" + str(lines))

	# 驿数按实际 seen_stations 报，不按「游戏跑了多久」编。
	# 同样**不带分母**——原来写死「路过 %d/%d 座驿站」，那个总数长在文案里，
	# 扩充驿站就得回来改字符串（顶栏那行已经是这个毛病）。
	_ck("驿数按存档报 5 座（不带分母）",
			lines.has(_loc.t("recap_seen") % [seen.size()]), str(lines))
	_ck("回执那行也不写死分母",
			not str(_loc.t("recap_seen")).contains("/"),
			"got=%s" % _loc.t("recap_seen"))

	# 没赢过的：只赢了 _frag_idx[0]，另外四个都要被点名
	var lost: Array = []
	for st_idx in _frag_idx:
		if not _gm.earned_tags.has("mini_%d_win" % st_idx):
			lost.append(rd.station_display_fragment(st_idx))
	_eq("点出没赢过的件数", lost.size(), 4)
	_ck("没赢过的那一行逐字对得上",
			lines.has(_loc.t("recap_mini_lost") % _join(lost)), str(lines))
	_ck("赢了一件就报一件", lines.has(_loc.t("recap_mini") % [1]))
	# 没读到的风景话只点前三个，第四个不硬凑
	var all_unread: Array = []
	for i in total_stations:
		if not _gm.seen_stations.has(i):
			all_unread.append(rd.station_display_name(i))
	_ck("没读到的话点前三个", lines.has(_loc.t("recap_unread") % _join(all_unread.slice(0, 3))),
			str(lines))
	_ck("只点三个，不把剩下的也塞进去",
			not str(lines).contains(all_unread[3]))

	# 没选过结局就不提「另一边还空着」——没选过的事不能说
	_eq("没选过结局", _gm.ending_id, "")
	_ck("没选结局：不提另一边还空着", not joined.contains(_loc.t("ending_keep"))
			and not joined.contains(_loc.t("ending_break")))
	# 余额 40 > 0 才报没花完
	_ck("余额 40：报没花完", lines.has(_loc.t("recap_lvbi") % 40))
	# 正面只有 2 块碎片 → 探索者(1)，不是大师(3)，所以不该出现第五格那行
	_ck("评级没到大师：不提第五格问号", not joined.contains(_loc.t("postcard_variant_hint")))

	# 选过之后那一行必须出现，而且必须是他选的那一边
	_gm.set_ending("break")
	_ck("选了放手：报「另一边还空着」", card._recap_lines().has(
			_loc.t("recap_ending") % _loc.t("ending_break")))
	_ck("选了放手：不提留门", not str(card._recap_lines()).contains(_loc.t("ending_keep")))
	# 大师档（5 块碎片、没有一站到 3 次）才提示第五格
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 1
	_ck("大师档：提示第五格", card._recap_lines().has(_loc.t("postcard_variant_hint")))
	# 完满判据是 all_fragments_maxed()，不是"任意一站到访 3 次"。
	# 原来这里只把 [0] 摆到 3 就期望进完满档——那正是把旧那个 bug 当成规格写进了
	# 测试：玩家只把云影台刷满三次、另外四站只去过一次，正面就已经是"完满"，
	# 而导航还在指另外四站。现在只刷满一站仍是大师，五站全满才是完满。
	_gm.collected[_frag_idx[0]] = _gm.MAX_VISITS_PER_STATION
	_ck("只刷满一站：仍是大师，仍提示第五格", card._recap_lines().has(
			_loc.t("postcard_variant_hint")))
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = _gm.MAX_VISITS_PER_STATION
	_ck("完满档：不再提第五格", not card._recap_lines().has(
			_loc.t("postcard_variant_hint")))
	# 摆回半途基线：只有前两块碎片收过、没选结局。
	# 这里必须把五块全摆回去而不是只摆 [0]——上面那两行把其余三块也填上了，
	# 只还原 [0] 的话后面量到的碎片数是 5，「回执正文 == 开头那份 lines」也对不上。
	_gm.collected[_frag_idx[0]] = 1
	_gm.collected[_frag_idx[2]] = 0
	_gm.collected[_frag_idx[3]] = 0
	_gm.collected[_frag_idx[4]] = 0
	_gm.set_ending("")
	_eq("基线还原：碎片 2 块", _gm.get_collected_count(), 2)

	# 覆盖层：按重新开始弹出来、两个按钮都在、留下不重置
	card._on_restart_pressed()
	await process_frame
	_ck("按重新开始弹出回执", card._recap_overlay != null)
	if card._recap_overlay != null:
		_ck("回执标题是那句", card._recap_title.text == _loc.t("recap_title"))
		_ck("回执正文就是那些行", card._recap_body.text == joined,
				"got=" + card._recap_body.text)
		_ck("「再骑一趟」在", card._recap_again_btn != null
				and card._recap_again_btn.text == _loc.t("recap_again"))
		_ck("「留下这张卡」在", card._recap_stay_btn != null
				and card._recap_stay_btn.text == _loc.t("recap_stay"))
		card._on_recap_stay_pressed()
		await process_frame
		_eq("留下：回执收走", card._recap_overlay, null)
		_eq("留下：不重置存档", _gm.seen_stations.size(), seen.size())
		_eq("留下：碎片还在", _gm.get_collected_count(), 2)

	# 切语言：行数不变、每行都换过、且没有裸 key 漏出来
	var zh_lines: Array = card._recap_lines()
	_loc.set_language("en")
	var en_lines: Array = card._recap_lines()
	_eq("切语言后行数不变", en_lines.size(), zh_lines.size())
	_ck("切语言后每行都变了", _all_differ(en_lines, zh_lines))
	_ck("英文里没有漏掉的 key", not str(en_lines).contains("recap_"))
	_loc.set_language("zh")

	# 走到头：16 座全路过、5 件全赢、某一站到过 3 次（完满）、旅币花光 ——
	# 剩的仍然有而且必须有一样：另一边的结局没走过。keep/break 一次只选一个，
	# 存档又随重开清零，所以这一行永远不会消失，回执也就永远有事可说。
	# 要是哪天把它写成「全都走到了」，那才是真的在骗玩家。
	_gm.reset()
	for i in total_stations:
		_gm.seen_stations[i] = true
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 3
		_gm.earned_tags["mini_%d_win" % st_idx] = true
	_gm.set_ending("keep")
	_gm.lvbi = 0
	var full: Array = card._recap_lines()
	_eq("走到头：正文只剩一行", full.size(), 1)
	_eq("走到头：剩的就是另一边", full, [_loc.t("recap_ending") % _loc.t("ending_keep")])
	_ck("走到头：不再报驿数", not str(full).contains(_loc.t("recap_seen") % [total_stations]))
	_ck("走到头：不再报没赢过", not str(full).contains(_loc.t("recap_mini_lost")))
	_ck("走到头：不报没花完", not str(full).contains(_loc.t("recap_lvbi")))
	await _free(card)


## 接名字列表。分隔符要跟 EndCard._join_names 一致，所以调它而不是自己写死。
func _join(names: Array) -> String:
	return (", " if _loc.is_english() else "、").join(names)


func _all_differ(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] == b[i]:
			return false
	return true
