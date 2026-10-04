extends SceneTree
## probe_road_hue.gd — **一次性探针**：只拍 `lookdev_journey` 里 `12b_day_正午`
## 那一档，把路面那两个色相量打印出来。改着色器时用它迭代，别用 lookdev_journey。
##
## ## 为什么要有这个探针
##
## `lookdev_journey.gd` 一次跑 27 张、约 4 分钟，而改路面颜色这件事要来回看
## 十几遍。第一版真的用它迭代过一轮，4 分钟一轮、每轮只能改一个数，
## 而**推导出想要的颜色需要同时定三个通道**——于是改成这个探针。
##
## ## 它量的是玩家真正看见的那一块，不是"我填进去的那个数"
##
## 这里用的是 `ROAD_BOX` / `GRASS_BOX` 那两个框，**逐像素**算完 `b−r` 和饱和度
## 再取中位数（不是各通道中位数相减，理由见 lookdev_journey 的同名注释）。
## 沥青到草皮的整条过渡带上还有别的面，而这条判据量的是"沥青读成什么"，
## 取样宽一点就量到路肩砾石、窄一点就量到中心白虚线——两个都不是路面本身。
##
## ## 机位必须和 lookdev_journey 的 `12b` 那一档完全一致
##
## 它**不自己造相机**：用的就是 `Player3D._update_camera` 那台跟随相机，
## 玩家摆在环路 18% 处、车头顺着路。CLAUDE.md 里记着「相机摆好了不等于在拍」
## 那一条——`root.get_texture()` 渲的是当前那台相机，所以这里一旦自己 `add_child`
## 一台就会被无视，而画面上仍然看得出"有图"。用真相机就没有这个问题。
##
## 用法： godot --path . --script tools/probe_road_hue.gd
## 不能加 --headless（dummy renderer 拍出来是纯色），也不能加 --quit-after。
## 加 --split 则跑「蓝是哪盏灯的」那一节（见下面 `_split_lights()`）。

const SHOT := Vector2i(1280, 720)
const SAVE_DIR := "user://lookdev_journey"

## 与 `lookdev_journey.gd` 的 `ROAD_BOX` / `GRASS_BOX` 逐值相同。
## **不许只改一边**——这个探针存在的意义就是和定妆照量同一块地方。
const ROAD_BOX := Rect2(0.12, 0.62, 0.50, 0.20)
const GRASS_BOX := Rect2(0.10, 0.47, 0.16, 0.08)
## 同一个框的**两块更干净的取样区**，只给 `--split` 那一节用。
## 拆光的时候必须有两块对照：CLAUDE.md 里「判据的取样点自己得先问一句
## 落在什么东西上」——`ROAD_BOX` 里既有沥青，也有那台车（占掉中间一大块）
## 和左上角一条草，而 640×144 的框里车占到三成，改一盏灯它就跟着动。
const ROAD_CLEAN_BOX := Rect2(0.14, 0.76, 0.22, 0.05)
## 路肩砾石那条。**量它是为了量"接缝"**：把沥青的反照率调暖去抵消蓝光，
## 而路肩那一段用的是**另一族近中性的灰**（`dirt_color` 0.430/0.420/0.398
## 与 `RoadVerge.GRAVEL` 0.395/0.386/0.368）——于是只暖沥青的话，
## 路面渲成中性而路肩还是偏蓝，两条并排读就是一道色差。
## 判据是"路肩与路面同族"，不是"路肩也蓝"也不是"路肩也中性"：
## 界取 20 个单位（约八分之一条判据门槛），超了就是接缝。
const SHOULDER_BOX := Rect2(0.14, 0.575, 0.22, 0.035)
const SKY_BOX := Rect2(0.30, 0.05, 0.40, 0.08)

var _world: Node = null
var _split: bool = false
var _nosdfgi: bool = false
var _off: String = ""
var _albedo: String = ""
var _grain: String = ""
var _profile: bool = false
var _nosky: bool = false


## 竖直剖面：一条列带（车右侧那一段）从上往下每 6px 打一行均值。
##
## 存在的理由是**取样框是靠猜的**——第一版的 `SHOULDER_BOX` 以为落在
## 路肩砾石上，看图才发现它骑在路沿上，于是量到的"路肩"其实是路面。
## 而"路面和路肩同族"这件事是这轮修法的核心风险（只暖沥青的话
## 路肩那一族还是中性灰，并排读就是一道色差），
## 框落错了地方这条风险就量不出来。
func _print_profile() -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	# 左侧路肩那一列。第一版挑的是 x 0.55~0.78（车右边），剖面出来
	# y=300..606 **整段全是沥青**——那条带子里根本没有路肩，
	# 而据此量到的"路肩 −9"其实是路面，于是"路面和路肩同族"这条风险
	# 当时量的是一个不存在的东西。可推广的一条同族：
	# **判据的取样框要先证明它落在被测物上**，
	 # 用剖面打一遍比盯着框猜一遍便宜。
	var x0: int = int(SHOT.x * 0.02)
	var x1: int = int(SHOT.x * 0.13)
	print("[prof] 列带 x=%d..%d，自上而下每 6px 一行" % [x0, x1])
	for y in range(330, 640, 6):
		var r := 0.0
		var g := 0.0
		var b := 0.0
		var n := 0
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1
		var mx: float = maxf(r, maxf(g, b)) / maxf(float(n), 1.0)
		var mn: float = minf(r, minf(g, b)) / maxf(float(n), 1.0)
		print("[prof] y=%3d  sRGB(%3.0f,%3.0f,%3.0f)  b−r=%+4.0f  饱和=%.3f"
				% [y, r / float(n) * 255.0, g / float(n) * 255.0, b / float(n) * 255.0,
				(b - r) / float(n) * 255.0, (mx - mn) / maxf(mx, 0.001)])


func _initialize() -> void:
	Engine.max_fps = 60
	var args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	_split = args.has("--split")
	_nosdfgi = args.has("--nosdfgi")
	_profile = args.has("--profile")
	_nosky = args.has("--nosky")
	for a in args:
		if str(a).begins_with("--off="):
			_off = str(a).substr(6)
		if str(a).begins_with("--albedo="):
			_albedo = str(a).substr(9)
		if str(a).begins_with("--grain="):
			_grain = str(a).substr(8)
	_ensure_autoloads()
	root.get_node("GameManager")._clear_save()
	root.get_node("Localization").set_language("zh")
	root.size = SHOT
	_run.call_deferred()


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


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.onboarding_shown = true
	gm.prologue_done = false
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout
	# 收掉新手引导和序章那两道模态。**不放回来就量不到东西**：序章把玩家冻住，
	# 而 `Player3D._update_camera` 整个不会跑，相机永远不跟摆位走 ——
	# 于是拍出来的是一片没人看过的起始机位，量到的路面根本不是环路上的路面。
	# 第一版探针就漏了这一段，量出来两个框的 `b−r` 都是 +10（正本该是 −78），
	# 而画面上根本没有路——两个数"看着都在门槛内"于是差点当成通过。
	_world._headless_mode = false
	_world._onboarding.visible = false
	_world._dialogue_popup.visible = false
	gm.mark_prologue_done()
	_world._player.set_can_move(true)
	_world._player.set_camera_locked(false)

	var pts: Array = _world._road_builder.get_road_data().points
	var di: int = int(pts.size() * 0.18)
	var p_on: Vector3 = pts[di]
	var fwd: Vector3 = pts[(di + 1) % pts.size()] - pts[di - 1]
	fwd.y = 0.0
	fwd = fwd.normalized()
	_world._player.position = p_on
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._player.look_at(p_on + fwd * 100.0, Vector3.UP)
	_world._player.set_camera_locked(false)

	# 草皮是**逐格流式**建的，铺满一圈要几十帧。第一版探针只等 1.5 秒就拍，
	# 于是取样框里根本没有草皮卡片、量到的是裸地形——而裸地形和草皮卡片
	# 渲出来的颜色差着一档（同一块地：草皮 sRGB(162,168,87)、裸地形
	# sRGB(140,190,135)），于是探针的数与定妆照的数对不上，
	# 而两边各自都"量到了草地"。
	# 判据是"这一帧和定妆照那一帧**画面上是同一个世界**"，
	# 不是"我等够了时间"。
	for i in 300:
		_world._grass_scatter.set_focus(_world._player.global_position)
		_world._grass_scatter.tick(1.0 / 60.0)
		await process_frame
	# 里程计**必须压在这一步的最后**：它是个累加器，越过黄昏门槛之后
	# `DayCycle` 立刻按 FADE_SEC(9s) 开始往黄昏走，而这一屏要的是
	# **刚开始走**的那一档（定妆照那一张是推过去之后 1.5 秒拍的，t≈0.17）。
	# 放在铺草皮之前的话，探针自己那 6 秒就把 t 推到 0.985、
	# 量到的是一张黄昏的图，于是调出来的数一条也搬不到定妆照上。
	_world._odometer_units = (_world._day_cycle.DUSK_FROM_LAP + 0.5) * _world._total_arclen
	await create_timer(1.5).timeout

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if _profile:
		await _print_profile()
		quit(0)
		return
	if _split:
		await _split_lights()
	else:
		# `--nosdfgi` 是**干净的单档 A/B**：关掉 SDFGI 之后只拍一张。
		# 为什么不能靠 `--split` 里那几档 `*_nosdfgi`：SDFGI 的级联是渐进
		# 重建的，在一轮里"关掉再打开"只等十几帧的话，后面几档量到的是
		# **半重建**的中间态（实测 `sun_only` 反而比 `sun_only_nosdfgi`
		# 更不蓝，+2 对 +14，与光无关）——于是那一列互相矛盾，
		# 量出来的是"我等了多久"而不是"SDFGI 贡献多少"。
		# 结论要拿一个**只关一次、从头到尾没开过**的进程去量。
		if _nosdfgi:
			_world._day_cycle._env.sdfgi_enabled = false
			print("[probe] 已关 sdfgi_enabled（产品配置是 true）")
		if _nosky:
			var sk: ProceduralSkyMaterial = _world._day_cycle._sky_mat
			sk.sky_top_color = Color(0, 0, 0)
			sk.sky_horizon_color = Color(0, 0, 0)
			sk.ground_horizon_color = Color(0, 0, 0)
			sk.ground_bottom_color = Color(0, 0, 0)
			print("[probe] 已把四个天空滤镜全拉黑（`DAY_SKY_*` 是滤镜，不是天自己的颜色）")
		if _off != "":
			_off_one_light(_off)
			print("[probe] 已关 %s" % _off)
		if _albedo != "":
			var n: int = _set_asphalt_param("asphalt_color", _albedo)
			print("[probe] asphalt_color=%s（改了 %d 个材质；产品值在 .gdshader 里）"
					% [_albedo, n])
		if _grain != "":
			var n2: int = _set_asphalt_param("grain_dark_color", _grain)
			print("[probe] grain_dark_color=%s（改了 %d 个材质）" % [_grain, n2])
		var r: Array = await _shoot("probe_road_hue")
		_last = r
		_report_lighting()
		_verdict("", r[0], r[1])
		print("[probe] 图: %s/probe_road_hue.png" % SAVE_DIR)
	quit(0)


## 一行一档：拍一张、量那个框。
func _shoot(name: String) -> Array:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [SAVE_DIR, name])
	var road: Array = _region_hue(img, ROAD_BOX)
	var grass: Array = _region_hue(img, GRASS_BOX)
	var mean: Array = _region_mean(img, ROAD_BOX)
	var clean: Array = _region_hue(img, ROAD_CLEAN_BOX)
	var sky: Array = _region_hue(img, SKY_BOX)
	var shoulder: Array = _region_hue(img, SHOULDER_BOX)
	return [road, grass, mean, clean, sky, shoulder]


func _verdict(tag: String, road: Array, grass: Array) -> void:
	print("[probe]%s 路面  b−r=%+.0f  饱和度=%.3f   (门槛 |b−r|≤12 / ≤0.12)"
			% [tag, road[0] * 255.0, road[1]])
	print("[probe]%s 草地  b−r=%+.0f  饱和度=%.3f   (正对照，门槛 |b−r|≥25)"
			% [tag, grass[0] * 255.0, grass[1]])
	var sh: Array = _last[5]
	print("[probe]%s 路肩  b−r=%+.0f  饱和度=%.3f   (与路面之差 ≤20，否则是接缝)"
			% [tag, sh[0] * 255.0, sh[1]])
	print("[probe]%s 接缝  路面−路肩 b−r 差=%+.0f"
			% [tag, (road[0] - sh[0]) * 255.0])


var _last: Array = []


## 「蓝是哪盏灯的」——把三盏光源逐个关掉重拍。
##
## 第五轮那条判据（`|b−r| ≤ 12`）是量**渲出来**的像素，而它量到的东西横跨
## 三个光源：主光、补光、以及 `AMBIENT_SOURCE_SKY` 那一路天光辐照度。
## 第一版是直接去调 `asphalt.gdshader` 里的反照率，改了三轮才发现
## **把 `ALBEDO` 换成完全中性的 `vec3(0.35)` 之后 b−r 只从 +30 掉到 +25** ——
## 也就是说蓝根本不在材质里，而在光里。可推广的一条同族：
## **"这个东西的颜色不对"先问它是被谁照的**，逐个关灯比调材质便宜得多，
## 而且改的是光源就意味着**全场一起改**（路面、路肩砾石、草地、树、
## 驿站屋顶全都吃同一份光），不会留下"路是中性灰、路肩是蓝的"那种接缝。
##
## 冻结手法：`set_laps()` 每个物理帧都会调 `_apply(t)` 把三盏灯重写一遍，
## 所以这里把 `_ready_done` 打成 false —— `set_laps()` 第一行就 early-return，
## 于是摆进去的值能留住。**改完之后必须改回去**，它是别的回归要量的一个前提。
func _split_lights() -> void:
	var dc: Node = _world._day_cycle
	_report_lighting()
	# 摆一份 baseline（照抄 `_apply(0.17)` 算出来的值，量出来的那几盏灯）
	var sun_c: Color = dc._sun.light_color
	var sun_e: float = dc._sun.light_energy
	var fill_c: Color = dc._fill.light_color
	var fill_e: float = dc._fill.light_energy
	var amb_e: float = dc._env.ambient_light_energy
	var sdfgi0: bool = dc._env.sdfgi_enabled

	dc._ready_done = false
	# `World3D._add_glow()` 给五座碎片站各挂了一盏 `OmniLight3D`，
	# 而它们是**运行时 new 出来的**、场景文件里一个都搜不到 ——
	# 拆光只关 `_sun` / `_fill` / 环境光的话，这五盏一直亮着，
	# 于是"三盏都关了路面还是蓝"这件事会被算到光上去。
	# **可推广的一条同族**：拆光源之前先确认这个世界里到底有几盏灯，
	# `grep` 场景文件只找得到手存的那两盏。
	var omnis: Array[OmniLight3D] = []
	_collect_lights(_world, omnis)
	for o in omnis:
		o.visible = false

	# 每档：[名字, 太阳能量, 补光能量, 环境光能量, 太阳色, 天空档 0=原样 1=中性灰 2=全黑, SDFGI]
	#
	# 前四档只是"逐个关灯"，量的是**贡献**；后面量的是**归属**。
	# 逐个关灯那一套在这里自相矛盾：`no_fill` 只让 b−r 从 +29 掉到 +26
	# （看着补光几乎不参与），而 `fill_only` 单独就有 +55（看着补光是主力）。
	# 打架的原因是 AGX 在高光那一头会去饱和，线性加法那套账在屏上不成立。
	# 于是改用**指定色**：把太阳换成纯红（`sun_red`）——纯红光打在沥青上
	# 渲出来还带蓝，就证明蓝不是漫反射来的；再把天整个拉黑（`*_nosky`）；
	# 最后 `black_nosdfgi` 是**正对照**：三盏全灭、SDFGI 也关掉之后
	# 路面必须是黑的，不黑就说明还有一盏我没想到的灯。
	#
	# `black`（只灭三盏、留着 SDFGI）实测是 sRGB(23,49,152) 的**亮蓝**，
	# 而 `sun_red` 下仍然是洋红偏蓝、`*_nosky` 与带天那档逐值相同——
	# **三盏灯全灭之后还有光**，而天色对它没有影响。`World3D.tscn` 的
	# `Env_sky` 里 `sdfgi_enabled = true`：SDFGI 是**从天空反推出来的间接反弹光**，
	# 它不走 `DirectionalLight3D.light_color`、也不是 `ambient_light_energy`
	# 那一路，所以「换纯红太阳它还是蓝」「拉黑天它一点不变」
	# 「三盏全灭它还亮着」三件事同时成立，一次解释掉。
	var modes := [
		["black", 0.0, 0.0, 0.0, sun_c, 2, true],
		["black_nosdfgi", 0.0, 0.0, 0.0, sun_c, 2, false],
		["all_on", sun_e, fill_e, amb_e, sun_c, 0, true],
		["all_on_nosdfgi", sun_e, fill_e, amb_e, sun_c, 0, false],
		["sun_only", sun_e, 0.0, 0.0, sun_c, 0, true],
		["sun_only_nosdfgi", sun_e, 0.0, 0.0, sun_c, 0, false],
		["fill_only", 0.0, fill_e, 0.0, sun_c, 0, true],
		["amb_only", 0.0, 0.0, amb_e, sun_c, 0, true],
		["sun_red", sun_e, 0.0, 0.0, Color(1.0, 0.0, 0.0), 0, true],
		["sun_only_nosky", sun_e, 0.0, 0.0, sun_c, 2, true],
		["all_on_nosky", sun_e, fill_e, amb_e, sun_c, 2, true],
	]
	var sky0: Array = [
		dc._sky_mat.sky_top_color, dc._sky_mat.sky_horizon_color,
		dc._sky_mat.ground_horizon_color, dc._sky_mat.ground_bottom_color,
	]
	for mi in modes.size():
		var m: Array = modes[mi]
		dc._sun.light_color = m[4]
		dc._sun.light_energy = m[1]
		dc._fill.light_energy = m[2]
		dc._env.ambient_light_energy = m[3]
		dc._sky_mat.sky_top_color = _sky_tint(m[5], sky0, 0)
		dc._sky_mat.sky_horizon_color = _sky_tint(m[5], sky0, 1)
		dc._sky_mat.ground_horizon_color = _sky_tint(m[5], sky0, 2)
		dc._sky_mat.ground_bottom_color = _sky_tint(m[5], sky0, 3)
		dc._env.sdfgi_enabled = m[6]
		# SDFGI 的级联是**渐进更新**的，切换之后要给它几帧重算，
		# 而 `_shoot()` 只等三帧——拍到的是上一档的残留就白量了。
		if mi > 0 and modes[mi - 1][6] != m[6]:
			for k in 12:
				await process_frame
		var r: Array = await _shoot("split_%s" % m[0])
		var road: Array = r[0]
		var mean: Array = r[2]
		var clean: Array = r[3]
		var sky: Array = r[4]
		print("[split] %-15s 路面 均值 sRGB(%3.0f,%3.0f,%3.0f) b−r=%+4.0f 饱和=%.3f | 净框 b−r=%+4.0f | 天 b−r=%+4.0f"
				% [m[0], mean[0] * 255.0, mean[1] * 255.0, mean[2] * 255.0,
				road[0] * 255.0, road[1], clean[0] * 255.0, sky[0] * 255.0])
	dc._sky_mat.sky_top_color = sky0[0]
	dc._sky_mat.sky_horizon_color = sky0[1]
	dc._sky_mat.ground_horizon_color = sky0[2]
	dc._sky_mat.ground_bottom_color = sky0[3]
	dc._sun.light_color = sun_c
	dc._sun.light_energy = sun_e
	dc._fill.light_energy = fill_e
	dc._env.ambient_light_energy = amb_e
	dc._env.sdfgi_enabled = sdfgi0
	for o in omnis:
		o.visible = true
	dc._ready_done = true
	print("[split] 图: %s/split_*.png" % SAVE_DIR)


func _collect_lights(n: Node, out: Array[OmniLight3D]) -> void:
	for c in n.get_children():
		if c is OmniLight3D:
			out.append(c)
		_collect_lights(c, out)


## 一次只关一个旋钮，其余全留产品值。**必须一个一个进程分开跑**——
## 理由同上面 `--nosdfgi` 那段：一轮里连着开关 SDFGI 会让后面几档量到
## 半重建的中间态。`--off=sun|fill|amb` 三档各跑一次，
## 每次都从"和基线一模一样的世界"出发。
func _off_one_light(which: String) -> void:
	var dc: Node = _world._day_cycle
	dc._ready_done = false
	match which:
		"sun":
			dc._sun.light_energy = 0.0
		"fill":
			dc._fill.light_energy = 0.0
		"amb":
			dc._env.ambient_light_energy = 0.0
		_:
			push_warning("[probe] --off=%s 不认识，这一档量的是基线" % which)


## 把沥青的反照率整个换掉重拍（`--albedo=R,G,B`，sRGB 分量）。
##
## `asphalt_color` 是 `.gdshader` 里那个带 `source_color` 的 uniform，
## `RoadBuilder` 从来没有 `set_shader_parameter()` 覆写过它——所以产品值
## **只存在于着色器源码里**，要试别的值就得在运行时铺一份进去。
## 这里按「材质的 shader 里有这个参数名」认，认不认得准比认节点名可靠：
## `World3D` 里路面有主环路与自交点广场两个 `ShaderMaterial`。
func _set_asphalt_param(param: String, spec: String) -> int:
	var parts: PackedStringArray = str(spec).split(",")
	if parts.size() < 3:
		push_warning("[probe] %s 要三个分量" % param)
		return 0
	var c := Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return _visit_materials(_world, param, c)


func _visit_materials(n: Node, param: String, c: Color) -> int:
	var hits := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			for m in _mats_of(ch):
				if m is ShaderMaterial:
					var sh: Shader = m.shader
					if sh != null and sh.code.find("asphalt_color") >= 0:
						m.set_shader_parameter(param, c)
						hits += 1
		hits += _visit_materials(ch, param, c)
	return hits


func _mats_of(gi: GeometryInstance3D) -> Array:
	var out: Array = []
	if gi is MeshInstance3D:
		var mi: MeshInstance3D = gi
		if mi.material_override != null:
			out.append(mi.material_override)
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var m: Material = mesh.surface_get_material(s)
				if m != null:
					out.append(m)
	return out


## 天空那一档。0 = 原样，1 = 中性灰，2 = 全黑。
## 四个颜色都要动：`ProceduralSkyMaterial` 的天顶/地平线是**乘在物理散射上的滤镜**，
## 而**地面方向那两个颜色才是真的地面色**——只拉前两个的话天看着中性了，
## 环境光还从地面那半边捞着一份颜色，那一路就永远拉不干净。
func _sky_tint(mode: int, orig: Array, idx: int) -> Color:
	match mode:
		1:
			return Color(0.35, 0.35, 0.35)
		2:
			return Color(0.0, 0.0, 0.0)
		_:
			return orig[idx]


## 顺手把光照那几个旋钮打出来。
##
## 这一条是**给自己看的诊断**，不是判据：探针和定妆照量的是同一块地方，
## 而第一版两边的数差了 30 个单位（定妆照草地 `b−r = −78`、探针 `−5`），
## 画面上却都是"一片草地"。差在哪儿只有把旋钮打出来才看得见——
## **两把尺子读数不一致时，先确认两把尺子架在同一个世界上**，
## 再去怀疑被测的东西。
func _report_lighting() -> void:
	var dc: Node = _world._day_cycle
	print("[probe] sun=%s/%.3f  fill=%s/%.3f  amb=%.3f  sdfgi=%s  exposure=%.2f  tonemap=%d  fog=%.5f"
			% [str(dc._sun.light_color), dc._sun.light_energy, str(dc._fill.light_color),
			dc._fill.light_energy, dc._env.ambient_light_energy, str(dc._env.sdfgi_enabled),
			dc._env.tonemap_exposure, dc._env.tonemap_mode, dc._env.fog_density])
	print("[probe] odometer=%.1fm  dusk_t=%.3f  画质档=%s"
			% [_world._odometer_units, dc.get_t(),
			str(root.get_node_or_null("QualitySettings"))
			if root.get_node_or_null("QualitySettings") != null else "(无)"])


func _region_hue(img: Image, box: Rect2) -> Array:
	var brs: Array[float] = []
	var sats: Array[float] = []
	for y in _rows(box):
		for x in _cols(box):
			var c := img.get_pixel(x, y)
			brs.append(c.b - c.r)
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			sats.append((mx - mn) / maxf(mx, 0.001))
	return [_median(brs), _median(sats)]


## 同一个框的逐通道均值。**不是中位数**：拆光的时候要的是"这一档整体偏到哪儿"，
## 而中位数会把路面上那几道白虚线整条剔掉，读数于是偏暗。
func _region_mean(img: Image, box: Rect2) -> Array:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in _rows(box):
		for x in _cols(box):
			var c := img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1
	return [r / maxf(float(n), 1.0), g / maxf(float(n), 1.0), b / maxf(float(n), 1.0)]


func _rows(box: Rect2) -> Array:
	var y0: int = clampi(int(float(SHOT.y) * box.position.y), 0, SHOT.y - 1)
	var y1: int = clampi(y0 + int(float(SHOT.y) * box.size.y), 0, SHOT.y)
	var out := []
	for y in range(y0, y1):
		out.append(y)
	return out


func _cols(box: Rect2) -> Array:
	var x0: int = clampi(int(float(SHOT.x) * box.position.x), 0, SHOT.x - 1)
	var x1: int = clampi(x0 + int(float(SHOT.x) * box.size.x), 0, SHOT.x)
	var out := []
	for x in range(x0, x1):
		out.append(x)
	return out


func _median(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var s: Array[float] = v.duplicate()
	s.sort()
	return s[s.size() / 2]
