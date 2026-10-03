extends SceneTree
## lookdev_postcard.gd — 明信片纸面分级 + 终局二选一的定妆照
##
## **不能加 --headless，也不能加 --quit-after。**
## --headless 用 dummy renderer，SubViewport 的纹理是空的，导出的 PNG 会是一片
## 纯色/空白，看着像「纸色都对了」其实什么都没画。必须带真窗口跑。
## --quit-after 按帧数计，这台机器窗口模式能跑 280+ FPS，给小了会在中途把进程
## 掐掉，所以脚本自己 quit()。计时一律用 Time.get_ticks_msec() 比墙钟。
##
## 数据层（档位夹取、四件散件互不覆盖、_variant 不被档位带偏）由
## verify_postcard_ending.gd 断言，这里只补人眼看的事：
##   01-04  四个纸面档位并排能不能看出差别（另配纸带像素抽查，六对两两分色）
##   05     珍藏笺 + 四件散件全上：金边、帘纹、纤维、蜡封、信封折角同框
##   06     没买套餐只买宣纸：散件不能被档位挡掉
##   07-08  背面两态：守住归途 / 打破循环
##   09/09b/09c  未竟：朝圣者缺格 / 大师缺第五格 / 背面留白
##   10     二选一覆盖层：两张卡片的字号、间距、命中范围
##   11     选完后揭示：明信片 + 按钮栏 + 落款纸名
##   12     重新开始前的「这一趟」回执（EndCard._show_run_recap）
##
## 用法： godot --path . --script tools/lookdev_postcard.gd

const SAVE_DIR := "user://lookdev_postcard"
## 渲染视口尺寸（和 EndCard.gd 导出用的 PostcardExport 一致）
const SHOT_SIZE := Vector2i(1920, 1080)
## 明信片留一点边，别贴着 PNG 边导致外框被裁掉看不全。
## Vector2i 减 Vector2 会编译报错，所以内容尺寸单独给一份。
const MARGIN := 40.0
const CONTENT_SIZE := Vector2(1840.0, 1000.0)

var _fails := 0
var _gm: Node = null
var _loc: Node = null
var _pc_script: GDScript = null
var _frag_idx: Array = []
var _shots := 0
const EXPECTED_SHOTS := 19


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails += 1
		print("[FAIL] ", msg)


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


## 摆 5 个碎片驿站各打卡 3 次 = 完满评级（正面满格 + 右上金印），
## 让每一张定妆照都展示「挣的那层」的完整形态。
func _fill_inventory(tier: int, extras: Array, ending: String) -> void:
	_gm.reset()
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 3
	# 正面顶上那张路线图读的就是 seen_stations（十六个点哪些实心）。
	# 只摆 collected 的话图上会写着「已过 0 驿」配着一圈实心碎片站，
	# 那是一张玩家永远不会拿到的卡 —— 定妆照得是挣的那层的完整形态。
	for st_idx in _frag_idx:
		_gm.seen_stations[st_idx] = true
	_gm.inv.clear()
	if tier > 0:
		_gm.inv["postcard_tier"] = tier
	for id in extras:
		_gm.inv[id] = 1
	if ending != "":
		_gm.set_ending(ending)


## 把一个 Control 摆进 1920x1080 的 SubViewport，渲染两帧后导出 PNG。
## 两帧是因为 queue_redraw 要到下一帧才真正画上。
func _snap(name: String, node: Control) -> Color:
	var svp := SubViewport.new()
	svp.size = SHOT_SIZE
	svp.transparent_bg = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)

	var stage := Control.new()
	stage.anchor_left = 0.0
	stage.anchor_top = 0.0
	stage.anchor_right = 1.0
	stage.anchor_bottom = 1.0
	svp.add_child(stage)

	# 深底托明信片：浅底会和珍藏笺的暖白纸色糊在一起。SubViewport 没有
	# render_clear_color 属性——赋值会抛运行时脚本错误并直接中断本函数，
	# 而下面的断言全在 save 之后，于是"失败 0"会看着像通过、PNG 却一张没写。
	# 底色只能靠一张铺满的 ColorRect。
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.10, 0.09, 0.08, 1.0)
	backdrop.anchor_left = 0.0
	backdrop.anchor_top = 0.0
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	stage.add_child(backdrop)

	stage.add_child(node)
	await process_frame
	await process_frame

	var img: Image = svp.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	var err: int = img.save_png(path)
	_ck("%s 导出成功（%dx%d）" % [name, img.get_width(), img.get_height()],
			err == OK and img.get_width() == SHOT_SIZE.x,
			"err=%d size=%dx%d" % [err, img.get_width(), img.get_height()])

	# 抽查中心像素不是纯黑：dummy renderer 下导出的图会整张 0，带窗口的正常
	var c := img.get_pixel(SHOT_SIZE.x / 2, SHOT_SIZE.y / 2)
	_ck("%s 画面非空（中心像素 %s）" % [name, str(c)], c.a > 0.0)

	# 计数放在所有断言之后：函数中途抛脚本错误就不算一张，
	# 让末尾的张数断言能抓出「全部静默跳过」这种假通过。
	_shots += 1
	node.queue_free()
	svp.queue_free()
	await process_frame
	return _band_avg(img)


## 明信片底部纸带的渲染色均值。这块只画 _paper，别的什么都没叠，
## 所以它是「档位真的换了纸色」最直接的证据。卡片摆在 (MARGIN, MARGIN)、
## 尺寸 CONTENT_SIZE：面板占到高 0.85，路牌在 x 0.5 / y 0.92，落款在右下，
## 取左边中段那块是纯纸面。
func _band_avg(img: Image) -> Color:
	var x0 := int(MARGIN + 300)
	var y0 := int(MARGIN + 860)
	var acc := Vector3.ZERO
	var n := 0
	for dx in range(200):
		for dy in range(40):
			var x := x0 + dx
			var y := y0 + dy
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				var p := img.get_pixel(x, y)
				acc += Vector3(p.r, p.g, p.b)
				n += 1
	if n == 0:
		return Color.BLACK
	return Color(acc.x / n, acc.y / n, acc.z / n)


func _col_dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _make_postcard() -> Control:
	var pc: Control = _pc_script.new()
	pc.name = "PC"
	pc.position = Vector2(MARGIN, MARGIN)
	pc.size = CONTENT_SIZE
	return pc


func _make_back(text: String) -> Control:
	var b: Control = load("res://scenes/PostcardBack.tscn").instantiate()
	b.position = Vector2(MARGIN, MARGIN)
	b.size = CONTENT_SIZE
	# 必须显式塞文案：PostcardBack 自己不知道终局结局，
	# 不塞的话"守住归途"那张背面和"未竟留白"那张完全一样，看不出差别。
	if text != "" and b.has_method("set_back_text"):
		b.set_back_text(text)
	return b


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_gm._clear_save()
	_loc.set_language("zh")
	_pc_script = load("res://scripts/Postcard.gd")
	_frag_idx = load("res://scripts/road_data.gd").get_script_constant_map().get(
			"FRAGMENT_SLOT_STATION_IDX", [])
	_run.call_deferred()


func _run() -> void:
	print("=== 明信片定妆照（带窗口跑）===")
	_ck("取到 5 个碎片驿站索引", _frag_idx.size() == 5, "got %d" % _frag_idx.size())
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# ---- 纸面档位 ----
	# 档位差别不能只靠人眼看：像素抽查把「上了笺却没换纸色」这种错也抓出来。
	_fill_inventory(0, [], "")
	var b0 := await _snap("01_tier0_未买套餐", _make_postcard())

	_fill_inventory(1, [], "")
	var b1 := await _snap("02_tier1_素笺", _make_postcard())

	_fill_inventory(2, [], "")
	var b2 := await _snap("03_tier2_上笺", _make_postcard())

	_fill_inventory(3, [], "")
	var b3 := await _snap("04_tier3_珍藏笺", _make_postcard())
	var bands := [b0, b1, b2, b3]
	print("    纸带均值 tier0=%s tier1=%s tier2=%s tier3=%s" % [b0, b1, b2, b3])
	# 四档四色，任何两档都得对得上各自的纸——素笺也有自己那一种沉色，
	# 不然「花了钱买了张素笺」和「没买套餐」在画面上还是同一张纸。
	for i in range(4):
		for j in range(i + 1, 4):
			var d := _col_dist(bands[i], bands[j])
			_ck("tier %d 与 tier %d 纸色分得开" % [i, j], d > 0.03,
					"d=%.3f" % d)

	_fill_inventory(3, ["paper", "ink", "seal", "env"], "")
	await _snap("05_tier3_满配", _make_postcard())

	# 没买套餐、只买宣纸：散件的帘纹不能被档位挡掉
	_fill_inventory(0, ["paper"], "")
	await _snap("06_未买套餐_仅宣纸", _make_postcard())

	# ---- 背面三态 ----
	_fill_inventory(3, ["paper", "ink", "seal", "env"], "keep")
	await _snap("07_背面_留门_写上了那句", _make_back(_loc.t("back_keep")))

	# 写满 200 字（MAX_CHARS 上限）时的样子。字号是**按这块纸自动定的**，
	# 所以字最多和字最少是两种排版——07 与 07b 必须成对看：只有 07 那一张，
	# "字变大了"看着像是把默认那句排得好看，而写满时缩回 60px 那一档
	# 才是玩家真正会遇到的第二种排版。
	_fill_inventory(3, ["paper", "ink", "seal", "env"], "keep")
	await _snap("07b_背面_写满200字",
			_make_back(("落霞把这条路染成了一段可以再来的理由。" as String).repeat(7).substr(0, 200)))

	# 放手：背面是空的。那句话退成了写字界面的占位提示，不落纸。
	_fill_inventory(3, ["paper", "ink", "seal", "env"], "break")
	await _snap("08_背面_放手_留白", _make_back(""))

	# ---- 抉择在正面留下的痕迹：封口的蜡 ----
	# 这两张必须成对看：抉择要是只改了背面那句，玩家翻到正面会发现两张卡
	# 一模一样，那我上一条"选择有真后果"就是假的。蜡封掰开与否是正面唯一的差别。
	_fill_inventory(3, ["paper", "ink", "seal", "env"], "keep")
	await _snap("08b_正面_留门_蜡封完好", _make_postcard())

	_fill_inventory(3, ["paper", "ink", "seal", "env"], "break")
	await _snap("08c_正面_放手_蜡封掰开", _make_postcard())

	# 没买蜡封的玩家也得看得到差别：空位也要画成掰开的口
	_fill_inventory(3, ["paper", "ink", "env"], "break")
	await _snap("08d_正面_放手_没蜡也画裂口", _make_postcard())

	# ---- 未竟：碎片不齐、ending_id 为空 → 背面留白 ----
	# 大师档（4 块）也必须画出第五格：布局表只有四格的话，正面看不出还缺一件，
	# 「未竟」和「满配」的区别就只剩背面留白。这条是数据层硬断言——
	# 只靠截图看不出布局表被改回四格。
	var layout3: Array = _pc_script.VARIANT_LAYOUTS[3]
	_ck("大师档布局有 5 格", int(layout3.size()) == 5,
			"got %d" % int(layout3.size()))
	_ck("大师档第五格是占位（slot -1）", int(layout3[4][0]) == -1,
			"got %s" % str(layout3[4]))
	_ck("大师档前四格是真碎片", int(layout3[3][0]) == 3,
			"got %s" % str(layout3[3]))
	var layout4: Array = _pc_script.VARIANT_LAYOUTS[4]
	_ck("完满档五格全是真碎片", int(layout4.size()) == 5
			and int(layout4[4][0]) == 4, "got %s" % str(layout4[4]))

	# 3 块 → 朝圣者，四格布局里本来就有一格占位
	_gm.reset()
	for i in _frag_idx.size():
		if i < 3:
			_gm.collected[_frag_idx[i]] = 1
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 1
	await _snap("09_未竟_三碎片缺格", _make_postcard())

	# 4 块 → 大师，靠新加的第五格体现「缺一件」。
	# 顺带把 seen_stations 摆上：正面顶部那张路线图读的是它，只摆 collected
	# 的话图上会写「已过 0 驿」配着一圈实心站——玩家永远拿不到的那种卡。
	for i in _frag_idx.size():
		if i < 4:
			_gm.collected[_frag_idx[i]] = 1
			_gm.seen_stations[_frag_idx[i]] = true
	await _snap("09c_未竟_大师四碎片缺第五格", _make_postcard())

	await _snap("09b_未竟_背面留白", _make_back(""))

	# ---- 二选一覆盖层（走真实 EndCard，用窗口截图）----
	root.size = Vector2i(1280, 720)
	await create_timer(0.2).timeout

	_fill_inventory(3, ["paper", "ink", "seal", "env"], "")
	var card: Control = load("res://scenes/EndCard.tscn").instantiate()
	root.add_child(card)
	await process_frame
	await process_frame
	_ck("二选一覆盖层已建", card._ending_overlay != null)
	await _snap_root("10_终局二选一")
	await _check_choice_joys_pixels(card)

	var keep_card: Control = card._ending_overlay.get_node("Choice_keep")
	_click(keep_card)
	await process_frame
	await process_frame
	_ck("选择后明信片已揭示", card._postcard.visible)
	# 等揭示动画走完（scale 0.6s、淡入 0.4s），否则截到半透明那帧
	await create_timer(0.9).timeout
	await _snap_root("11_揭示明信片")

	# ---- 12 重新开始前的「这一趟」回执 ----
	# 走 _on_restart_pressed()（玩家真按的那个键）而不是直接 _show_run_recap()：
	# 回执的全部内容都是从存档现算的，摆一份假存档等于拍了一张玩家不会看到的图。
	# 这份存档照着一趟真实的骑法摆：16 座过了 13 座、5 件赢 3 件、旅币剩 87。
	var rd = load("res://scripts/road_data.gd").new()
	for i in rd.stations.size():
		if i != 2 and i != 8 and i != 15:
			_gm.seen_stations[i] = true
	for i in [4, 7, 10]:
		_gm.earned_tags["mini_%d_win" % i] = true
	_gm.lvbi = 87
	card._on_restart_pressed()
	await process_frame
	await process_frame
	_ck("按重新开始弹出了回执", card._recap_overlay != null)
	await _snap_root("12_回执_这一趟")

	# 英文再拍一张：那句「没读到它们的话」连着三个驿站名，中文 400px、英文
	# 900px+，不换行就被裁掉右半截，而中文那张完全看不出来。
	_loc.set_language("en")
	await process_frame
	await process_frame
	await _snap_root("12b_recap_EN")
	_loc.set_language("zh")

	card.queue_free()
	await process_frame
	await process_frame

	_gm._clear_save()

	# 这张断言是必须的：历史上 _snap 里赋过一次不存在的属性，运行时抛错直接
	# 中断函数，十张 SubViewport 图全部静默跳过，而"失败 0"看着像通过。
	_ck("确实出了 %d 张定妆照（预期 %d）" % [_shots, EXPECTED_SHOTS],
			_shots == EXPECTED_SHOTS)

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_postcard] %s  (失败项 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


## 拍整个窗口（EndCard 直接挂在 root 上，不走 SubViewport）。
func _snap_root(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	var err: int = img.save_png(path)
	_ck("%s 导出成功（%dx%d）" % [name, img.get_width(), img.get_height()],
			err == OK and img.get_width() > 0, "err=%d size=%d" % [err, img.get_width()])
	_shots += 1


func _click(card: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	card.gui_input.emit(ev)


## 抉择屏底下那一行五件乐事：**图上真的画出来了没有**。
##
## 几何断言（`verify_postcard_ending.gd` §4）量的是控件摆在哪、有没有叠——
## 而 `FragmentIcon` 的五件全在 `_draw()` 里，`--headless` 一笔不落盘，
## 几何全绿而屏上五个空框是没有谁能拦住的。这里量像素。
##
## 判据是**每一格里都有一片那片颜色**，不是"五格颜色两两不同"：
## `FragmentIcon` 画的是 1~2px 的细线，五件摊在 56×56 上各占几十个像素，
## 所以按「取到几个接近本件颜色的像素」断，门槛取 8（实测 60~200），
## 既拦得住"一个都没画"，又留得住 AGX 之后色偏的余量。
## 而「五格真的并排排开」交给几何断言——这里量的只是**画没画**。
func _check_choice_joys_pixels(card: Control) -> void:
	var img: Image = root.get_texture().get_image()
	var cols: Array = load("res://scripts/Postcard.gd").FRAGMENT_COLS
	var ed: Control = card._ending_overlay
	if ed == null:
		_ck("抉择屏的五件乐事画出来了", false, "覆盖层是 Nil")
		return
	var icons: Array = []
	for c in ed.get_children():
		if c.get_class() == "Control" and c.get_script() != null \
				and c.get_script().resource_path.ends_with("FragmentIcon.gd"):
			icons.append(c)
	_ck("底栏那一行是五个图标控件", icons.size() == 5, "got %d" % icons.size())
	if icons.size() != 5:
		return
	var per: Array = []
	var on_name: Array = []
	for i in icons.size():
		var r: Rect2 = icons[i].get_global_rect()
		var want: Color = cols[i]
		var n := 0
		for dy in range(0, int(r.size.y)):
			for dx in range(0, int(r.size.x)):
				var c2: Color = img.get_pixel(int(r.position.x) + dx, int(r.position.y) + dy)
				# 用「色相对不对」而不是「三通道都接近」：图标是细线，线心可能
				# 落在高光上，而 hue 那一路在 AGX 之后仍然认得出是云还是竹。
				if absf(c2.r - want.r) < 0.22 and absf(c2.g - want.g) < 0.22 \
						and absf(c2.b - want.b) < 0.22:
					n += 1
		per.append(n)
		# 同一个颜色有没有跑到**名字那一行**上去。这一条量的是玩家看得见的
		# 那一件事：五件的设计范围并不是 ±16（竹到 y −24..+20、禽到 x +21），
		# 而 `FragmentIcon` 按 `size.x` 缩放、以控件中心为原点——框开成方形
		# 就一定装不下。第一版 56×56 装不下，竹的梢压着「竹」那个字，
		# 而**几何断言当时全绿**（控件不叠，都在屏内）。墨有没有落进名字行
		# 只有像素能量得到，所以判据就落在像素上。
		var nm_r: Rect2 = _name_rect_under(ed, icons[i])
		var m := 0
		if nm_r.size.x > 0.0:
			for dy in range(0, int(nm_r.size.y)):
				for dx in range(0, int(nm_r.size.x)):
					var c3: Color = img.get_pixel(int(nm_r.position.x) + dx,
							int(nm_r.position.y) + dy)
					if absf(c3.r - want.r) < 0.22 and absf(c3.g - want.g) < 0.22 \
							and absf(c3.b - want.b) < 0.22:
						m += 1
		on_name.append(m)
	_ck("五个图标都真的画出了自己的颜色（每件 ≥8 像素）",
			per.min() >= 8, "实际 %s" % str(per))
	_ck("没有一件的笔画压到自己名字那一行（0 像素）",
			on_name.max() == 0, "实际 %s" % str(on_name))


## 找出紧贴在某个图标框下面、横向对得上的那个名字 Label 的屏上矩形。
func _name_rect_under(ed: Control, icon: Control) -> Rect2:
	var ir: Rect2 = icon.get_global_rect()
	var best := Rect2()
	for c in ed.get_children():
		if not (c is Label):
			continue
		var r: Rect2 = c.get_global_rect()
		if r.position.y <= ir.end.y - 1.0:
			continue
		if absf((r.position.x + r.size.x * 0.5) - (ir.position.x + ir.size.x * 0.5)) > 1.0:
			continue
		if best.size.x == 0.0 or r.position.y < best.position.y:
			best = r
	return best

