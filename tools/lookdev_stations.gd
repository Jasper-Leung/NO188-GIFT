extends SceneTree
## lookdev_stations.gd — 驿站布局定妆照
##
## **不能加 --headless，也不能加 --quit-after。** --headless 用 dummy renderer，
## 截出来的 PNG 是一片纯色，看着像"路和亭子都在"其实什么都没画；--quit-after
## 按墙钟折算，这台机器窗口模式能跑 280+ FPS，给小了会在中途把进程掐掉。
## 脚本自己 quit()。
##
## 数据层的硬断言（每个驿站脚底离中心线的净空）在 verify_stations.gd 里，
## 这里只补人眼要看的那件事：**亭子确实没架在沥青上**。用的是真 World3D，
## 驿站是 _setup_stations() 摆的真 GLB，不是模拟。
##
##   01..05  俯拍几个代表驿站（含广场那个交叉点驿站）：路从亭子旁边过
##   06      全路线高空俯视：16 个亭子都落在 8 字外侧
##   07      骑行视角：贴在路面上朝前看，亭子在路肩外
##   08..23  **十六座站逐个从骑行视角拍**：每一座的牌子上都真的有字
##
## 第 08 段是这一族真正要量的一件玩家读得出的事。模型一共只有 12 栋
## （3 对共用 + 1 座是榕树），而站心离路心线 18m——所以量的是**每座站在
## 骑行那一档有没有报出自己的名字**。
##
## 机位只有一个：**就站在中心线上**（站心离路 18m），抬到 `Player3D.CAM_UP`
## 那一档，也就是纯骑行视角。`STATION_PASS_RADIUS` 是 15m，所以 18m 上
## 提示圈不亮、打卡也不开——玩家在路上的每一秒看的就是它。视轴对着站脚到
## 牌子的中点，让房脚和牌子都落在画幅里（见下面那一段注释）。
##
## 判据在**像素**上，但量的不是"这块是什么颜色"。第一版量的是房子的颜色
## 分布，拿"两座站之间差多远"当判据——跑出来的分布是：同一个 GLB 的
## 起程驿楼↔东岭驿楼 d=0.0114，而真的一对不同建筑（琴音林↔竹雨庭）
## d=0.0407，离阈值 0.04 只差 0.0007。**同一族的量分不开它们**，取哪条线
## 都是噪声，所以那一版的两条判据是量了个寂寞。
##
## 现在量的是**牌子上真的画出了字**：按字体度量把**字身**那块摆到屏上，
## 数它中间那条横带里有几根竖笔画。空白的天 0 根、一整块暗墙 1 根，
## 而一行四字在 22px 上是 50~93 根。而玩家在路上问的本来也不是"这是不是同一种
## 亭子"，是"我现在到的是哪一座"——那是牌子回答的。
##
## 取样框这件事折了三折，每一折都是被**图**判的死刑、不是被数字判的，
## 所以值得写在这儿：①按 `outline_size × pixel_size` 反推，描边并不按那个
## 算米铺开，框比真牌子高出三倍；②改问 `Label3D.get_aabb()`，它给的是一个
## **立方体**（三条边都等于那行字的**总宽**），框于是上头顶进天空、下头顶进
## 屋顶；③按 `global_transform` 投，可是 billboard 是在**顶点着色器里**转的、
## 节点自己的矩阵根本没跟着转，于是牌子是侧着看的，同一批四字站量出
## 8/27/38/75px 四种宽度。现在这个框**一处都不问节点**，宽度
## `get_string_size()`、高度 `get_height()`、两根轴取相机的 right/up。
##
## 房子的颜色签名仍然算、仍然打出来，但只当诊断：它是"这一族修好之前长
## 什么样"的底片。
##
## **突变做过**：`STATION_LABEL_PIXEL_SIZE` 退回 0.002（字身 9.6cm、18m 上 3px）
## → 框缩成 12×4px、笔画掉到 0~6 根，判据当场红。**拿 halo 加粗当突变是错的**：
## `outline_size` 从字身向外膨胀，而墨核永远画在最上层，加粗到 60 也一根不少。
##
## 用法： godot --path . --script tools/lookdev_stations.gd

const SAVE_DIR := "user://lookdev_stations"
const SHOT := Vector2i(1280, 720)
## 俯拍高度。够高才看得见"路从旁边过"，够低才分得清亭子和路肩。
const TOP_H := 55.0
## 骑行视角的相机高度，和 Player3D 的自行车视角一致。
const EYE_H := 1.6
## 第 08 段那一档的相机高度 = Player3D.CAM_UP（车后视比车把高 2.3m）。
const RIDE_CAM_H := 2.3
## 取样块相对投影包围盒的缩放，和它允许的半边长上下限（px）。
## 块要落在房子上，所以按**那一座自己的屏上尺寸**反解——写死一个像素数的话，
## 岭台那种大亭子会整块取到草坡上，而凉亭那种小的会被邻站的树裹进来。
const PATCH_FILL := 0.42
const PATCH_MIN_HALF := 12
const PATCH_MAX_HALF := 160
## 相邻两座的签名距离原先当判据用的那条线，现在只留在注释里当病历：
## 同一个 GLB 0.0114 / 真的一对不同建筑 0.0407，阈值取哪儿都是噪声。

## 一个汉字在牌子上至少要数出几根竖笔画。
##
## 实测：一行四字在 22px 的字身上是 50~93 根（每字 12~23 根），一行七字 125 根。
## 门槛取 **5 根**（还有两倍多的余量，但远高于"空白的天 0 根 / 一整块暗墙 1 根"）。
## 原来取 2.0 是在**取样框还量错**的时候定的——那时框里混着屋檐和树冠，
## 随便一个背景就有二三十根，于是门槛被定在了噪声里。
##
## 这条门槛拦的是**墨够不够黑、够不够多**，而**描边加粗多少它管不着**：
## `outline_size` 是从字身**向外**膨胀的，字身的墨核永远在最上层被画上去，
## 加粗到 60（墨核缩到屏上约 2px）也照样一根不少。第一版拿 halo 当突变是找错了
## 对手——真正的突变是把 `STATION_LABEL_PIXEL_SIZE` 退回 0.002（字身 9.6cm、
## 18m 上 3px），那时框只剩 12×4px，一行四字够不着 20 根。
const PLATE_MIN_RUNS_PER_CHAR := 5.0
## 墨色的亮度上限。牌子的字色是 Color(0.09,0.08,0.07)，走过 AGX 之后仍在 0.2 以下；
## 而米白描边（0.97）和正午的天都在 0.6 以上。
const INK_L_MAX := 0.30
## 站心离路心线的距离，和 road_data.STATION_OFFSET 一份。
const STATION_OFFSET := 18.0
## 代表驿站：0 起程驿楼、4 禽语湖湾、8 灯影亭（广场交叉点）、12 西谷岭台、15 榕树下。
## 12 是净空最紧的那座，8 是唯一落在广场盘上的。
const TOP_IDX := [0, 4, 8, 12, 15]

var _fails := 0
var _shots := 0
var _gm: Node = null
var _world: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


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


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_gm._clear_save()
	_gm.headless_mode = true
	# World3D 自带 OnboardingGuide（操作说明那整块），不置掉的话它盖满全屏，
	# 顶拍/骑拍都只能拍到它。
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	root.size = SHOT
	_run.call_deferred()


func _run() -> void:
	print("=== 驿站布局定妆照（带窗口跑）===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# --script 模式仍会把 project.godot 里的 main_scene 挂上来（GiftBox），
	# 铺满全屏，不处理的话每一张俯拍都盖着它。
	#
	# **这里 hide() 而不是 queue_free()，而这条是量出来的，不是读代码猜的**：
	# 原来的 `c.queue_free()` 一跑到这行就**当场段错误**（signal 11），
	# 崩点在 World3D 的 `PausePanel._ready()` → `_update_quality_button()`，
	# 也就是**下一批新建文字的第一行字**被写进按钮的那一刻。改 hide() 就干净跑完。
	#
	# 三件事要说清，因为它们决定这条注释会不会变成误导：
	# · **与本站替换无关**——用 `git worktree` 拉一份 HEAD 单跑过，同样的摘法照样崩，
	#   所以这条工具此前是**跑不动的**（不是"最近才坏"，是"一直没跑过"）。
	# · **不是产品的问题**：`tools/verify_panel_keyboard.gd` 带窗口起同一个 World3D 是绿的，
	#   而游戏自己的换场走 `change_scene_to_packed()`、主场景在正常游玩里也是排完版才走的。
	#   崩的是"主场景刚挂上、还没排过版，就在同一帧被销毁"这个只有本脚本才有的时序。
	# · **为什么崩，一句话说不清**：换 `remove_child()` 再 `queue_free()` 一样崩，
	#   所以"销毁与重建撞车"那套解释是不成立的，我不写。量到的只有前面那两句。
	#
	# 只 hide 不 free 是安全的：GiftBox 是 2D Control，不抢相机，而本脚本后面
	# 会把 World3D 的 HUDLayer / HUD3D / FragmentBarLayer 一并 hide 掉，
	# 定妆照要的正是"什么都没有"的那一屏。
	for c in root.get_children():
		if c == _gm or c == root.get_node("AudioManager") \
				or c == root.get_node("Localization"):
			continue
		if c is CanvasItem:
			(c as CanvasItem).hide()
	await process_frame
	await process_frame

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	# 等 _setup_stations() 把 16 座亭子摆完（还有地形/路面/植被的构建）。
	await create_timer(2.5).timeout
	_ck("World3D 已建", _world != null and _world._stations.size() == 16,
			"stations=%d" % (0 if _world == null else _world._stations.size()))
	# HUD 会盖住俯拍画面，定妆照里一律关掉。**HUD3D 是 World3D 的直属子节点，
	# 不在 HUDLayer 底下**——漏掉它的话顶栏那条黑带横在每一张图的上沿，
	# 而第 08 段量的恰恰是「站上方那块牌子」，它正好被这条带子压在下面。
	for layer in ["HUDLayer", "HUD3D", "FragmentBarLayer", "JoystickLayer", "MiniGameLayer"]:
		if _world.has_node(layer):
			_world.get_node(layer).visible = false
	await process_frame

	var cam := Camera3D.new()
	cam.name = "LookDevCam"
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 2000.0
	root.add_child(cam)

	# ---- 俯拍每个代表驿站 ----
	var rd = load("res://scripts/road_data.gd").new()
	for idx in TOP_IDX:
		var p: Vector3 = _world._stations[idx].position
		cam.global_position = p + Vector3(0.0, TOP_H, 24.0)
		cam.look_at(p, Vector3.UP)
		cam.make_current()
		var nm := "%02d_top_%d_%s" % [_shots + 1, idx,
				str(rd.get("stations")[idx].get("name_en", "")).replace(" ", "")]
		await _snap(cam, nm)

	# ---- 全路线高空俯视 ----
	cam.fov = 45.0
	cam.global_position = Vector3(0.0, 420.0, 260.0)
	cam.look_at(Vector3(0.0, 0.0, 40.0), Vector3.UP)
	cam.make_current()
	await _snap(cam, "06_overview_全路线")

	# ---- 骑行视角：贴着路面朝灯影亭（广场那个）看 ----
	cam.fov = 65.0
	var st8: Vector3 = _world._stations[8].position
	# 站在驿站正对的那条路上，沿路往回退 22m，再抬到车把高度。
	var to_road := Vector3(0.0, 0.0, 43.0) - Vector3(st8.x, 0.0, st8.z)
	var back := to_road.normalized() * 22.0
	cam.global_position = Vector3(st8.x + back.x, EYE_H, st8.z + back.z)
	cam.look_at(Vector3(st8.x, EYE_H + 1.0, st8.z), Vector3.UP)
	cam.make_current()
	await _snap(cam, "07_rider_朝灯影亭")

	# ---- 十六座站逐个从骑行视角拍：玩家在路上认不认得出这是哪一座 ----
	# 先等 16 个 GLB 全部流进来。`_station_aabb` 是 GLB 到齐才由
	# `_measure_station_aabb()` 量的，没到齐的那几座还是零尺寸的空盒子，
	# 投影出来是 0×0，牌子那块取样区会落在站脚那一小块地而不是房顶上——
	# 第一版就这么把 6 座量成了背景的颜色（其中一座标准差 0.026，量到的是天）。
	var missing := 16
	var t0 := Time.get_ticks_msec()
	while missing > 0 and Time.get_ticks_msec() - t0 < 30000:
		missing = 0
		for i in _world._stations.size():
			if i >= _world._station_aabb.size() \
					or _world._station_aabb[i].size.length() < 0.01:
				missing += 1
		if missing > 0:
			await process_frame
	_ck("16 座站的模型全部到位（包围盒都量到了）", missing == 0, "还缺 %d 座" % missing)

	# 机位只有一处：站在站心正对的那条路的**中心线上**，抬到 Player3D 的车后视高
	# （CAM_UP = 2.3m）。站心离路心线 STATION_OFFSET(18m) 而 STATION_PASS_RADIUS 是
	# 15m，所以这一档上提示圈不亮、打卡也不开——玩家在路上的每一秒看的就是它。
	#
	# 视轴对着**站脚到牌子中点**，不是对着房顶也不是对着站心：牌子在 18m 那一档
	# 离画幅中线最远能到 10.2m，而 fov 60 的半高只有 10.39m——对着站心的话
	# 最高那几座（茶烟小筑、竹雨庭，牌子 12.2m）会贴着画幅上沿出去一点点。
	# 取中点是最老实的一档：房脚和牌子都在画幅里。
	var w3 = load("res://scripts/World3D.gd")
	var cmap = w3.get_script_constant_map()
	var label_y_for = w3.get("label_y_for")
	var pts: Array = rd.points
	var np: int = pts.size()
	cam.fov = 60.0
	var sigs := {}          # 站下标 → 房子那块的颜色签名（诊断用）
	var ride: Array = []    # 按最近中心线点排序 = 玩家骑行时会遇到的先后
	var no_plate: Array[int] = []
	var offscreen: Array[int] = []
	var worst_runs := INF
	var worst_who := ""
	for i in _world._stations.size():
		var st: Node3D = _world._stations[i]
		var sp: Vector3 = st.global_position
		# 最近的那一段中心线：站就是照着它摆的，中心线到站心的方向就是路在站的那一侧
		var bi := 0
		var bd := INF
		for k in np:
			var q: Vector3 = pts[k]
			var d: float = (Vector2(q.x - sp.x, q.z - sp.z)).length_squared()
			if d < bd:
				bd = d
				bi = k
		var st_off := Vector3(pts[bi].x - sp.x, 0.0, pts[bi].z - sp.z).normalized()
		var road_pt := Vector3(sp.x, 0.0, sp.z) + st_off * STATION_OFFSET
		var ab: AABB = _world._station_aabb[i]
		var plate_local := Vector3(0.0, float(label_y_for.call(ab.end.y)), 0.1)
		var plate_w: Vector3 = st.global_transform * plate_local
		cam.global_position = Vector3(road_pt.x, sp.y + RIDE_CAM_H, road_pt.z)
		cam.look_at(Vector3(sp.x, (sp.y + plate_w.y) * 0.5, sp.z), Vector3.UP)
		cam.make_current()
		var nm := "%02d_ride_%d_%s" % [_shots + 1, i,
				str(rd.get("stations")[i].get("name_en", "")).replace(" ", "")]
		var img: Image = await _snap(cam, nm)

		# 房子那块的颜色签名留着当诊断：它说明每座站在那一档上有多"不一样"。
		var brect: Rect2 = _building_rect(cam, st, ab)
		var bc := brect.get_center()
		var half: int = clampi(int(minf(brect.size.x, brect.size.y) * PATCH_FILL),
				PATCH_MIN_HALF, PATCH_MAX_HALF)
		sigs[i] = _patch_sig(img, bc, half)

		# 判据量的是**牌子上真的画出了字**。取样区是**字身**那一带，见
		# `_glyph_rect()`——不能直接问 Label3D 的 AABB，它给的是个立方体。
		var lbl: Node3D = st.get_node_or_null("StationNameLabel") as Node3D
		var grect := _glyph_rect(cam, lbl)
		if grect.position.x < 0.0 or grect.position.y < 0.0 \
				or grect.end.x > float(SHOT.x) or grect.end.y > float(SHOT.y):
			offscreen.append(i)
		var runs := _ink_runs(img, grect)
		if runs < PLATE_MIN_RUNS_PER_CHAR * _char_count(
				str(rd.get("stations")[i].get("name", ""))):
			no_plate.append(i)
		if runs < worst_runs:
			worst_runs = runs
			worst_who = str(rd.get("stations")[i].get("name", ""))
		print("    %2d %-22s model=%2d  房子 屏上 %3.0f×%3.0fpx 均值(%.2f %.2f %.2f) 标准差(%.3f %.3f %.3f)  字身 屏上 %3.0f×%3.0fpx 笔画 %d" % [
				i, str(rd.get("stations")[i].get("name", "")),
				int(rd.get("stations")[i].get("model_idx", -1)),
				brect.size.x, brect.size.y, sigs[i][0], sigs[i][1], sigs[i][2],
				sigs[i][3], sigs[i][4], sigs[i][5],
			grect.size.x, grect.size.y, runs])
		ride.append({"idx": i, "k": bi, "model": int(rd.get("stations")[i].get("model_idx", -1))})
	ride.sort_custom(func(a, b): return int(a["k"]) < int(b["k"]))

	_ck("每一座站的牌子都整块落在画幅里（%dx%d）" % [SHOT.x, SHOT.y],
			offscreen.is_empty(), "跑出画幅的 idx: " + str(offscreen))
	_ck("每一座站的牌子上都真的画出了字（每字 ≥ %.0f 根竖笔画，最少的 %s %d 根）" % [
			PLATE_MIN_RUNS_PER_CHAR, worst_who, worst_runs],
			no_plate.is_empty(), "没画出来的 idx: " + str(no_plate))

	# 诊断，不作判据：共用同一个模型的那三对在那一档上有多像。
	# **这个数不作断言**——上一版拿它当判据，量出来的分布是：同一个 GLB 的
	# 起程驿楼↔东岭驿楼 0.0114，而真的一对不同建筑（琴音林↔竹雨庭）0.0407，
	# 离阈值 0.04 只差 0.0007。同一族的量分不开它们，取哪条线都是噪声。
	# 玩家在路上问的也不是"这是不是同一种亭子"，是"我现在到的是哪一座"——
	# 那是牌子回答的，上面那两条判据量的是它。
	print("\n--- 共用同一个模型的站之间（诊断量，不作判据）---")
	var by_model := {}
	for r in ride:
		var mi := int(r["model"])
		if not by_model.has(mi):
			by_model[mi] = []
		by_model[mi].append(int(r["idx"]))
	for mi in by_model:
		var g: Array = by_model[mi]
		if g.size() < 2:
			continue
		for j in range(g.size() - 1):
			var a: int = int(g[j])
			var b: int = int(g[j + 1])
			print("    %2d↔%2d  model=%2d  d=%.4f" % [a, b, mi, _sig_dist(sigs[a], sigs[b])])

	_world.queue_free()
	await process_frame
	_gm._clear_save()

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_stations] %s  (失败项 %d, 共 %d 张)" % [
			"PASS" if _fails == 0 else "FAIL", _fails, _shots])
	quit(0 if _fails == 0 else 1)


## 渲染两帧再导 PNG：queue_redraw / 材质编译都到下一帧才落地。
## 图返回出去给第 08 段量像素——判据要落在画出来的那张上，而不是数据源上。
func _snap(cam: Camera3D, name: String) -> Image:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	var err: int = img.save_png(path)
	_ck("%s 导出成功（%dx%d）" % [name, img.get_width(), img.get_height()],
			err == OK and img.get_width() == SHOT.x,
			"err=%d size=%dx%d" % [err, img.get_width(), img.get_height()])
	# dummy renderer 下导出的图整张是 0；带窗口的正常有内容。
	var c := img.get_pixel(SHOT.x / 2, SHOT.y / 2)
	_ck("%s 画面非空（中心像素 %s）" % [name, str(c)], c.a > 0.0)
	_shots += 1
	return img


## 一块矩形里的颜色签名：三个通道各自的均值与标准差，共 6 个数。
##
## 为什么是颜色分布而不是轮廓：站心离路心线 18m，fov 60 下视高约 20.8m，
## 1280 宽的画幅一格是 34px/m——一栋带顶的小房子在屏上占着两三百像素，
## 轮廓是量得到的。真正的问题不是"形状像不像"，而是"是不是同一种东西"：
## 玩家在路上要认出**这是哪一座**。而这三条道里 16 座站只用 12 个模型，
## 有三对是同一个 GLB 摆出来的——那一对从路上看过去本该逐像素一样。
##
## 取样块必须落在**房子上**，不能落在房子加背景上：同一栋楼摆在两块不同的
## 草坡前，量到的是坡不是楼，而那正是第一版把 3↔12（同模型）量成 0.07 的原因。
## 所以方块的位置与大小由**投影出来的模型包围盒**反解，见 `_building_rect()`。
func _patch_sig(img: Image, c: Vector2, half: int) -> Array:
	var acc := Vector3.ZERO
	var acc2 := Vector3.ZERO
	var n := 0
	var x0: int = maxi(0, int(c.x) - half)
	var x1: int = mini(img.get_width() - 1, int(c.x) + half)
	var y0: int = maxi(0, int(c.y) - half)
	var y1: int = mini(img.get_height() - 1, int(c.y) + half)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var p := img.get_pixel(x, y)
			acc += Vector3(p.r, p.g, p.b)
			acc2 += Vector3(p.r * p.r, p.g * p.g, p.b * p.b)
			n += 1
	if n == 0:
		return [0, 0, 0, 0, 0, 0]
	var m := acc / float(n)
	var v: Vector3 = (acc2 / float(n) - m * m).max(Vector3.ZERO)
	var sd := Vector3(sqrt(v.x), sqrt(v.y), sqrt(v.z))
	return [m.x, m.y, m.z, sd.x, sd.y, sd.z]


## 两个签名之间的距离：均值的平均差 + 标准差的平均差。
## 均值那半量"这块是什么颜色"，标准差那半量"这块是不是有结构"——
## 一块纯草皮和一个有屋顶有墙有门的亭子，均值可能接近而标准差差很远。
func _sig_dist(a: Array, b: Array) -> float:
	var d := 0.0
	for i in range(3):
		d += absf(float(a[i]) - float(b[i]))
	for i in range(3, 6):
		d += absf(float(a[i]) - float(b[i]))
	return d / 6.0


## **字身**（不含描边）那一带投到屏上的矩形。
##
## **整块矩形都按字体度量算，一处都不问 `Label3D.get_aabb()`**。问过两次，
## 两次都量到不存在的东西：
## · 第一次它给的是一个**立方体**，三条边都等于那一行字的**总宽**
##   （"起程驿楼" 4 个字 → 2.30m，"花房·禽语湖湾" 7 个字 → 3.66m，y 与 z 一模一样）。
##   拿它当取样框，竖直方向比字身高三四倍，上头顶进天空、下头顶进屋顶，
##   数出来的"竖笔画"里混着屋檐和树冠。
## · 第二次它连宽度都是乱的：同一个 4 字站连跑三次，横向量到 27px / 8px / 75px。
##   它读的是那块还没建完的 mesh 自己的盒子。
## 而**两条设计都是被图上那张奶油色的牌子判的死刑**——描边加粗到 60
## （一个字整个糊成一坨奶油），判据照样全绿：量的不是"这块地方有没有字"，
## 是"这块地方够不够有结构"。
##
## 宽度用 `get_string_size()`、高度用 `get_height()`，都按 `pixel_size` 折成米，
## 取节点原点四周对半开——Label3D 那一行字是以原点为中心的（这一条量出来的
## 屏上尺寸与"4 个字 ≈ 80px / 7 个字 ≈ 140px"逐值对上，对不上就会看出来）。
##
## 描边是从字身**向外**长的，所以这个框整个落在描边里面，量字身永远切不到
## halo 上——反过来说，"墨够不够多"这件事由 halo 加粗多少根本左右不了，
## 字糊掉时它会被这一条判据当场抓住。
func _glyph_rect(cam: Camera3D, lbl: Node3D) -> Rect2:
	if lbl == null:
		return Rect2()
	var g = lbl as Label3D
	# 牌子上没有显式设字体，画的是引擎的兜底字体。`get_font()` 在没显式设过的
	# 时候返回 null（它给的是节点自己那个 Ref，不是绘制时才会去查的默认值），
	# 而 `ThemeDB.fallback_font` 正是绘制时用的那一份——`GameManager._ready()`
	# 已经把它整个换成了项目的 LXGW，所以这里读到的就是玩家看到的那套字形。
	var f: Font = g.get_font()
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return Rect2()
	var fs := float(g.font_size)
	var half: Vector2 = Vector2(
			f.get_string_size(g.text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x * 0.5,
			f.get_height(fs) * 0.5) * g.pixel_size
	# **按相机的 right/up 摆，而不是按 `g.global_transform`**：牌子的
	# `billboard = BILLBOARD_ENABLED` 是在**顶点着色器里**转的，节点的
	# `global_transform` 根本没跟着转——按它投的话，牌子是侧着看的，
	# 同一批四字站量出来的横向宽度是 8px / 27px / 38px / 75px（16m 外那栋
	# 楼的角度差一点就整块侧过去了），而竖直方向被投影拉长到 3 倍。
	# 牌子永远正对着相机，所以它的两根轴就是相机的两根轴。
	var ax := cam.global_transform.basis.x
	var ay := cam.global_transform.basis.y
	var c: Vector3 = g.global_position
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for cx in 2:
		for cy in 2:
			var wp: Vector3 = c + ax * (half.x if cx else -half.x) \
					+ ay * (half.y if cy else -half.y)
			if cam.is_position_behind(wp):
				continue
			var s := cam.unproject_position(wp)
			mn = mn.min(s)
			mx = mx.max(s)
	return Rect2(mn, mx - mn)


## 牌子那块里数出几根竖着的笔画。
##
## 判据问的是"这块地方**有没有画字**"，不是"这块地方是什么颜色"——
## `Color(0.09,0.08,0.07)` 的墨压在米白描边上，位置就在房子上方 2.2m 的
## 空中；空白的天是 0 根，一整块暗墙是 1 根，而一行四字在 22px 上是
## 50~93 根。所以数的是**游程**：沿字身中间那条横带一行行扫过去，一次
## "由亮转暗"算一根笔画。
##
## 只取中间那条带：`Font.get_height()` 含 ascent 与 descent，字身盒的上下
## 各有留白，取满整个盒子会把留白里的米白描边外沿也算成一根，
## 白白多出一项恒定项。
func _ink_runs(img: Image, rect: Rect2) -> int:
	var x0: int = maxi(0, int(rect.position.x))
	var x1: int = mini(img.get_width() - 1, int(rect.end.x))
	var y0: int = maxi(0, int(rect.position.y))
	var y1: int = mini(img.get_height() - 1, int(rect.end.y))
	if x1 <= x0 or y1 <= y0:
		return -1
	var mid: int = int((y0 + y1) * 0.5)
	var half_band: int = maxi(1, int((y1 - y0) * 0.22))
	var runs := 0
	for y in range(maxi(y0, mid - half_band), mini(y1, mid + half_band) + 1):
		var prev := false
		for x in range(x0, x1 + 1):
			var dark: bool = img.get_pixel(x, y).get_luminance() < INK_L_MAX
			if dark and not prev:
				runs += 1
			prev = dark
	return runs


## 牌子上有几个字（全角算 1 个、半角算 0.55 个）。
## 判据按它折算需要几根笔画。
func _char_count(text: String) -> float:
	var n := 0.0
	for i in text.length():
		n += 1.0 if text.unicode_at(i) > 0x2E80 else 0.55
	return n


## 站模型在屏上占的那块矩形：把 AABB 的 8 个角投到画面上取外框。
##
## `_station_aabb` 量的是**站局部坐标**里的盒子（`World3D._measure_station_aabb()`），
## 乘上站的 `global_transform` 才是世界里的盒子。投 8 个角而不是投中心和远角：
## 相机是**侧着**看这栋楼的（站在中心线上、站心在路肩外 18m），
## 中心和远角两个点的投影落在盒子的一半上。
func _building_rect(cam: Camera3D, st: Node3D, ab: AABB) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var p0 := ab.position
	var p1 := ab.end
	for cx in 2:
		for cy in 2:
			for cz in 2:
				var lp := Vector3(p1.x if cx else p0.x,
						p1.y if cy else p0.y, p1.z if cz else p0.z)
				var wp: Vector3 = st.global_transform * lp
				if cam.is_position_behind(wp):
					continue
				var s := cam.unproject_position(wp)
				mn = mn.min(s)
				mx = mx.max(s)
	return Rect2(mn, mx - mn)
