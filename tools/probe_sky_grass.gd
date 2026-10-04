extends SceneTree
## probe_sky_grass.gd — **一次性探针**：把第五轮第二批（天穹地平线那道硬缝）
## 与第三批（黄昏草皮饱和度）的旋钮一个一个摆上去，量**渲出来的像素**。
##
## ## 为什么要有这个探针
##
## `lookdev_journey.gd` 一次 27 张、约 4 分钟，而这两批要调的是 `sky_curve`
## 与几个地面色的**比值**，一轮里只能定一个数。第一版真的用它迭代过一轮，
## 4 分钟一轮、每轮只能改一个数——而**判据是"缝两边的反差 ≤ 24"**，
## 那个数得连着扫五档才量得出趋势。
##
## ## 它量的是玩家真正看见的那一块
##
## 取样行 / 取样列 / 三个框都**逐值抄自 `lookdev_journey.gd`**
## （`SKY_COLS` / `SKY_ROWS` / `SKY_HUE_ROW` / `GRASS_BOX`）。
## **不许只改一边**——这个探针存在的意义就是和定妆照量同一块地方，
## 而这一族已经栽过一次"两把尺子架在不同的世界上"（见 `probe_road_hue.gd`
## 的 `_report_lighting()` 那段）。
##
## ## 机位必须和 `12b_day_正午` / `12c_dusk_黄昏` 完全一致
##
## 它**不自己造相机**：用的就是 `Player3D._update_camera` 那台跟随相机。
## CLAUDE.md 里记着「相机摆好了不等于在拍」那一条——`root.get_texture()`
## 渲的是当前那台相机，而这里一旦自己 `add_child` 一台就会被无视。
## 而且正午那张与黄昏那张**必须是同一个机位**，否则两帧之间混进了机位差，
## 看的人分不清哪些变化是天色给的、哪些是视角给的。
##
## ## 一轮里连着改旋钮为什么这里可以
##
## `probe_road_hue.gd` 那套 `--split` **必须一个旋钮一个进程**，因为 SDFGI 的
## 级联是渐进重建的，"关掉再打开"只等十几帧的话后面几档量到的是半重建的
## 中间态。天与草的旋钮**没有级联**——`ProceduralSkyMaterial` 的颜色和草皮的
## `set_shader_parameter()` 都是当帧生效、下一帧背景就重画了，所以一轮里
## 连着扫是安全的。哪一族有级联、哪一族没有，先问清楚再决定要不要拆进程。
##
## ## 一格量三样，都与定妆照的判据同量
##
##   远山 —— 最外层山线那一圈渲出来的亮度，以及它与自己背后那行天之差
##          （定妆照的判据是"层−天 ≤ 4"，见 `lookdev_journey.gd` 第 12f 节；
##          这一族原来的"缝 ≤ 24"量的是**同一道边**，而方向反了）
##   天色 —— `SKY_HUE_ROW` 那一行的 g/r、b/r（黄昏两档都 ≥ 0.45）
##   草   —— `GRASS_BOX` 中位饱和度（黄昏 ≤ 0.55，正午 ≤ 0.50）
##
## 用法： godot --path . --script tools/probe_sky_grass.gd [--noon] [--dusk]
## 不能加 --headless（dummy renderer 拍出来是纯色），也不能加 --quit-after。

const SHOT := Vector2i(1280, 720)
const SAVE_DIR := "user://lookdev_journey"

## ---- 下面四个常量逐值抄自 `lookdev_journey.gd`，**不许只改一边** ----
const SKY_COLS := [0.06, 0.14, 0.22, 0.30, 0.38]
const SKY_ROWS := [0.10, 0.14, 0.18, 0.22]
const SKY_HUE_ROW := 0.12
const GRASS_BOX := Rect2(0.10, 0.47, 0.16, 0.08)

## 扫带的上沿（像素行）。`HUD3D` 那条衬底是 62px，所以从 66 起——
## 再往上量到的是顶栏，不是天。
const SKY_SCAN_TOP := 66

## ---- 山线那把尺子：逐值抄自 `lookdev_journey.gd`，见 `_edge_ladder()` ----
const RIDGE_SCAN_TOP := 62
const RIDGE_SCAN_BOTTOM := 0.34
const RIDGE_EDGE_MIN := 8.0
const RIDGE_MAX_EDGES := 3

var _world: Node = null
var _noon := false
var _dusk := true
var _ridge := false
var _cal := false
var _spread := false
var _spread_noon := false


func _initialize() -> void:
	Engine.max_fps = 60
	var args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	_noon = args.has("--noon")
	if args.has("--noon-only"):
		_dusk = false
	_ridge = args.has("--ridge")
	_cal = args.has("--cal")
	_spread = args.has("--spread")
	# 山线那一组旋钮**黄昏和正午各有一份答案**：黄昏要的是层与层的台阶够大，
	# 正午要的是最外层不比天亮。把 `--spread` 只排在黄昏那一侧，正午就没人管了。
	_spread_noon = args.has("--spread-noon")
	root.size = SHOT
	_run.call_deferred()


func _run() -> void:
	_ensure_autoloads()
	root.get_node("GameManager")._clear_save()
	root.get_node("Localization").set_language("zh")
	var gm: Node = root.get_node("GameManager")
	gm.onboarding_shown = true
	gm.prologue_done = false
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout

	# 与 `probe_road_hue.gd` 同一条：序章和新手引导不放回来就量不到东西
	# ——序章把玩家冻住，`Player3D._update_camera` 整个不跑，相机不跟摆位走。
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

	# 草皮是逐格流式建的。第一版探针只等 1.5 秒就拍，取样框里根本没有草皮卡片、
	# 量到的是裸地形——而两者渲出来的颜色差着一档。
	for i in 300:
		_world._grass_scatter.set_focus(_world._player.global_position)
		_world._grass_scatter.tick(1.0 / 60.0)
		await process_frame
	# 冻**在**推里程计之前，而不是在 `_sweep_noon()` 开头才冻：里程计一推过门槛，
	# `DayCycle` 下一个物理帧就开始按 FADE_SEC 走，而下面这次 `create_timer(1.5)`
	# 期间没人挡着它 —— 于是正午那一档量到的是 **t≈0.167** 处的一个天，
	# 天空自己的纵向落差读成 **1%**（真正的正午是 23%）。
	# 两边各自都正常，而它让"抬远层"这条结论整个建立在半个黄昏的天上。
	_freeze()
	_world._odometer_units = (_world._day_cycle.DUSK_FROM_LAP + 0.5) * _world._total_arclen
	await create_timer(1.5).timeout

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# 山线那两节必须在**黄昏真的到位之后**才量：`--cal` / `--ridge` 排在
	# `_sweep_dusk()` 前面，而它自己那次「推到 t=1」在那后面——于是量到的是
	# 还在淡入的路上（t≈0.17）的一个世界，标定表整张作废。
	# 条件不能只看 `_dusk`：`--noon-only` 会把 `_dusk` 清掉，于是"只跑标定"
	# 恰好把那次淡入也跳过了，而基线 tint 读出来是 (0.977,0.940,0.937)——
	# 那不是产品值，是 1.5 秒 / 9 秒 = 0.167 处的一个中间态。
	if _spread_noon:
		await _ridge_spread()
	if _noon:
		await _sweep_noon()
	if _dusk or _cal or _ridge or _spread:
		await _force_dusk()
	if _spread:
		await _ridge_spread()
	if _cal:
		await _ridge_cal()
	if _ridge:
		await _ridge_ladder()
	if _dusk:
		await _sweep_dusk()
	quit(0)


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


## 把 `_apply()` 冻住，让摆进去的值留住。`set_laps()` 每个物理帧都会重写一遍，
## 而 `set_laps()` 第一行就 early-return。**退出前必须改回去**——它是别的回归
## 要量的一个前提。
func _freeze() -> void:
	_world._day_cycle._ready_done = false


## 让 `DayCycle` 自己把黄昏走完（里程计推过门槛 → 等 FADE_SEC + 余量），
## 然后冻住，免得后面每一档量到的都是淡入途中的某一个中间态。
func _force_dusk() -> void:
	# 正午那一档为了按住"还没开始淡入"把 `DayCycle` 冻上了，而 `set_laps()` 在
	# 冻着的时候直接 return ——不先解冻的话，推完里程计时**天还是一动不动**，
	# 而读出来的那一整套表看着完全正常。
	_world._day_cycle._ready_done = true
	_world._odometer_units = (_world._day_cycle.DUSK_FROM_LAP + 2.0) * _world._total_arclen
	await create_timer(11.0).timeout


## 正午那一档。摆的是 `DAY_SKY_CURVE` 与 `DAY_GND_HORIZON`。
##
## 成因假设有两条，各自带一档对照：
##   ① `sky_curve` 太小 → 天空那一侧在接近地平线时**还没走到** `sky_horizon_color`，
##      于是缝的上侧是接近天顶的那一档饱和色；
##   ② `ground_horizon_color` 与 `sky_horizon_color` 本来就是两个颜色，
##      而它们是结构性地贴在视线水平那一行上的。
## 两条不冲突，所以 `same` 那一档（两个地平线色设成同一个）单独跑一遍。
func _sweep_noon() -> void:
	var sk: ProceduralSkyMaterial = _world._day_cycle._sky_mat
	_freeze()
	print("[sky] ==== 正午（t=0）====")
	print("[sky] 产品值 sky_curve=%.2f  sky_horizon=%s  ground_horizon=%s"
			% [sk.sky_curve, str(sk.sky_horizon_color),
			str(sk.ground_horizon_color)])
	await _shoot("p_noon_base")
	for c in [0.40, 0.80, 1.50, 3.00, 6.00, 10.00]:
		sk.sky_curve = float(c)
		await _shoot("p_noon_curve%s" % str(c))
	# ②：两个地平线色设成同一个，看缝还剩多少。
	sk.sky_curve = 0.15
	sk.ground_horizon_color = sk.sky_horizon_color
	await _shoot("p_noon_sameh")
	# 两条一起上。
	sk.sky_curve = 3.00
	await _shoot("p_noon_curve3_sameh")
	print("[sky] 图: %s/p_noon_*.png" % SAVE_DIR)


## 黄昏那一档。摆的是 `DUSK_SKY_CURVE` / `DUSK_GND_HORIZON`，
## 外加草皮饱和度的两个候选旋钮。
##
## 草皮那两条各有各的代价，所以都摆一遍量：
##   · `DUSK_FILL_ENERGY` —— **只影响黄昏**（补光是冷紫的 `DUSK_FILL_COL`，
##     给暗面一点和太阳相反的色），白昼那一档一格不动；
##   · 草皮反照率的蓝通道 —— **两档都影响**，而 `verify_grass_scatter.gd`
##     钉着"草叶不许比脚下的地暗、绿红比不许塌"（`blade_base` 蓝 0.270
##     → 红 0.430，中途还有 0.17 的余量）。
func _sweep_dusk() -> void:
	print("[sky] ==== 黄昏（t=%.3f）====" % _world._day_cycle.get_t())

	var sk: ProceduralSkyMaterial = _world._day_cycle._sky_mat
	_freeze()
	print("[sky] 产品值 sky_curve=%.2f  sky_horizon=%s  ground_horizon=%s"
			% [sk.sky_curve, str(sk.sky_horizon_color),
			str(sk.ground_horizon_color)])
	await _shoot("p_dusk_base")
	for c in [0.40, 0.80, 1.00, 1.50, 2.00, 3.00, 6.00]:
		sk.sky_curve = float(c)
		await _shoot("p_dusk_curve%s" % str(c))
	sk.sky_curve = 0.10
	sk.ground_horizon_color = sk.sky_horizon_color
	await _shoot("p_dusk_sameh")
	sk.sky_curve = 3.00
	await _shoot("p_dusk_curve3_sameh")

	# ---- 第二批 2.4 的那两条杠杆，摆在一起扫 ----
	#
	# 判据是「黄昏那行的 g/r 与 b/r 都要 ≥ 0.45」。先量清楚它到底可不可达：
	# · `ground_horizon_color` 换成 `sky_horizon_color`——**一个像素都不动**
	#   （0.42/0.22 → 0.42/0.22）。那行量的是地平线**以上**的天空，
	#   `ground_*` 画的是地平线以下，而 `eyedir.y > 0` 时那个分支压根不取样
	# · `sky_curve` 0.10 → 3.0 把 b/r 从 0.225 抬到 **0.40**，再往上到 10.0
	#   也只有 0.41——**平的**。所以只拧它到不了 0.45
	# 而 `DUSK_SKY_HORIZON` 自己（(0.98,0.74,0.58) 过 `srgb_to_linear`）的
	# b/r 就是 **0.31**：那一行读到的绝大部分是地平线色，所以**门槛比产品自己
	# 那个地平线色还严**。剩下唯一能动的是把地平线色调淡。
	for c in [0.10, 1.00, 3.00]:
		for hb in [0.58, 0.68, 0.78, 0.90]:
			sk.sky_curve = float(c)
			sk.sky_horizon_color = Color(0.98, 0.74, float(hb), 1.0).srgb_to_linear()
			await _shoot("p_dusk_c%s_hb%s" % [str(c), str(hb)])
	sk.sky_curve = 0.10
	sk.sky_horizon_color = Color(0.98, 0.74, 0.58, 1.0).srgb_to_linear()

	# ---- 草皮饱和度 ----
	# 天**必须先摆回产品那一档**，草皮的数才和定妆照读的是同一个世界：
	# 草皮吃的是环境光，而环境光来自天，实测把 `sky_curve` 推到 3.0 之后
	# 同一片草皮的饱和度从 0.568 涨到 0.689——比草皮自己的任何旋钮都大。
	# 第一版把天留在"修好之后"那一档再量草皮，于是量到的是另一个世界的草。
	#
	# 而"产品那一档"本身会变：天色那一族修好之后 `DUSK_SKY_CURVE` 是 3.00、
	# 地平线蓝是 0.68，**这里写死旧值就等于把世界拨回去**——
	# 于是草皮那 0.581 是在一个已经不存在的天底下量出来的，
	# 而照着它去推 `DUSK_GRASS_SKY_MIX` 只会推出一个错的旋钮。
	# 所以这一组数**不许手抄**：从 `DayCycle` 的常量上取。
	var dc: Node = _world._day_cycle
	sk.sky_curve = dc.DUSK_SKY_CURVE
	sk.sky_horizon_color = dc.DUSK_SKY_HORIZON.srgb_to_linear()
	sk.ground_horizon_color = dc.DUSK_GND_HORIZON.srgb_to_linear()
	sk.ground_bottom_color = dc.DUSK_GND_BOTTOM.srgb_to_linear()
	print("[grass] 天已摆回产品档 sky_curve=%.2f  sky_horizon=%s"
			% [sk.sky_curve, str(sk.sky_horizon_color)])
	print("[grass] ==== 黄昏草皮饱和度（天已摆回产品档）====")
	var fill_e0: float = _world._day_cycle._fill.light_energy
	print("[grass] 产品值 fill_energy=%.2f  %s" % [fill_e0,
			str(_world._day_cycle._fill.light_color)])
	for e in [0.90, 1.30, 1.80, 2.40]:
		_world._day_cycle._fill.light_energy = float(e)
		await _shoot("p_dusk_fill%s" % str(e))
	_world._day_cycle._fill.light_energy = fill_e0

	# 另一条：抬草皮反照率的蓝通道。`verify_grass_scatter.gd` 的蓝通道上限是
	# `c.z <= c.x + 0.02`，所以 blade 最多能到 0.45、地色最多到 0.40。
	print("[grass] ==== 抬草皮 albedo 蓝通道（fill 复位到产品值 %.2f）====" % fill_e0)
	await _shoot("p_dusk_blade_base")
	for b in [0.34, 0.40, 0.45]:
		_set_grass("blade_base", Color(0.430, 0.520, float(b)))
		_set_grass("blade_tip", Color(0.520, 0.610, float(b) + 0.030))
		_set_grass("ground_color", Color(0.375, 0.475, float(b) + 0.015))
		_set_grass("ground_dark", Color(0.255, 0.335, float(b) - 0.065))
		await _shoot("p_dusk_blade%s" % str(b))

	# ---- 第三条，也是真正对的那一条：light_tint 往天光那边挪 ----
	#
	# 前两条都扫过了，都到不了门槛（fill 2.4 → 0.707，蓝通道顶格 → 0.763，
	# 门槛 0.55）。因为它们都在拧**能量**，而饱和度是**色相**的问题：
	# `ALBEDO = col * light_tint * light_energy`，黄昏那一档的 `light_tint`
	# 是归一化的太阳色 (1.00, 0.80, 0.64)，绿草乘上去立刻偏橙。
	#
	# 而真实黄昏里草皮主要是被**天穹**照着的（卡片是竖着的、吃环境光，
	# 太阳压到 9° 之后掠射贡献很小），天穹那一档是紫蓝的——也就是
	# `DUSK_FILL_COL (0.40,0.44,0.72)`。所以正解是让 tint 往那边**混**，
	# 而不是把补光能量拧大：补光那盏灯本来就照着草皮，只是它在**灯**那一侧，
	# 而橙调是在 **albedo** 那一侧乘进来的，灯侧加得再多也压不住。
	var fill_c: Color = _world._day_cycle._fill.light_color
	var fm: float = maxf(fill_c.r, maxf(fill_c.g, fill_c.b))
	var sky_hue := Color(fill_c.r / fm, fill_c.g / fm, fill_c.b / fm)
	var sun_hue := Color(1.0, 0.80, 0.64)
	# 基准能量得**从材质上读回来**，不能拿 `DUSK_FILL_ENERGY`(0.55) 顶替——
	# 那是补光那盏灯的数，而 `light_energy` 是 `DayCycle._apply_grass_light()`
	# 自己算出来再夹过一次的。第一版写死 0.55，于是 tint=0.70 那档探针报 0.380、
	# 产品报 0.568，同一个参数两个数。
	var gm: ShaderMaterial = _world._grass_scatter.grass_material()
	# 上一档扫把 albedo 的蓝通道顶到了 0.45 而**没有摆回去**，于是这一族读到的
	# 每一档都还带着那一档的反照率（tint=0.70 量到 0.372，而产品同一组参数是
	# 0.568）。扫完不摆回去，下一节量的就不是它自己那个旋钮了。
	_set_grass("blade_base", Color(0.430, 0.520, 0.270))
	_set_grass("blade_tip", Color(0.520, 0.610, 0.300))
	_set_grass("ground_color", Color(0.375, 0.475, 0.285))
	_set_grass("ground_dark", Color(0.255, 0.335, 0.205))
	var e0: float = gm.get_shader_parameter("light_energy")
	var t0: Color = gm.get_shader_parameter("light_tint")
	print("[grass] 产品值 light_energy=%.4f  light_tint=%s" % [e0, str(t0)])
	# `GrassScatter.set_light()` 会把 tint **归一化**再写进去（实测产品那一份是
	# (0.7723,0.7486,1.0)，正是 lerp 0.70 那档除以它的蓝），所以扫的时候补的
	# 那个均值系数得分母也用归一化之后的那一份——不归一化的话每一档算出来的
	# 能量都比产品那一档大一截（0.9678 vs 1.0337）。
	# 而 `e0` 是**已经补过**的那一份，所以基准得先反解回未补的那个，
	# 否则补偿会被做两遍（第一版 tint=0.70 探针 0.363、产品 0.568）。
	var prod_mix: float = dc.DUSK_GRASS_SKY_MIX
	var prod_tint: Color = sun_hue.lerp(sky_hue, prod_mix)
	var _m: float = float(maxf(prod_tint.r, maxf(prod_tint.g, prod_tint.b)))
	prod_tint = Color(prod_tint.r / _m, prod_tint.g / _m, prod_tint.b / _m)
	var e_raw: float = e0 * ((prod_tint.r + prod_tint.g + prod_tint.b) / 3.0) \
			/ ((sun_hue.r + sun_hue.g + sun_hue.b) / 3.0)
	print("[grass] 反解出未补的基准能量 e_raw=%.4f（产品 mix=%.2f）" % [e_raw, prod_mix])
	print("[grass] ==== light_tint 往天光混（太阳 %s → 天光 %s）===="
			% [str(sun_hue), str(sky_hue)])
	# 摆的是**产品那条完整算式**（`DayCycle._apply_grass_light()`），不是只摆 tint：
	# 那一档还带一个把三路均值补回来的能量系数，而 AGX 在这个亮度上不是线性的，
	# 于是只扫 tint 时量到的数**低于**产品真实渲出来的那个（实测 tint=0.70 时
	# 探针 0.505、产品 0.568）。扫一半算式量出来的数不能用来推产品的旋钮。
	for k in [0.85, 0.90, 0.95, 1.00]:
		var tint: Color = sun_hue.lerp(sky_hue, float(k))
		var tm: float = float(maxf(tint.r, maxf(tint.g, tint.b)))
		var tn: Vector3 = Vector3(tint.r / tm, tint.g / tm, tint.b / tm)
		_set_grass("light_tint", tint)
		_set_grass("light_energy", e_raw * ((sun_hue.r + sun_hue.g + sun_hue.b) / 3.0)
				/ maxf((tn.x + tn.y + tn.z) / 3.0, 0.0001))
		await _shoot("p_dusk_tint%s" % str(k))
	_set_grass("light_tint", sun_hue)
	# 归属测量**必须排在最后**：它要把整片草皮藏起来拍，而 SDFGI 的级联是
	# 渐进重建的，藏完再等 8 帧量到的是**半重建状态**——第一版把它排在前面，
	# 于是后面每一档的路面亮度都被抬高了 2.4 倍（0.099 → 0.243），
	# 而草皮自己的数反倒还可用，于是"顺手摆一下"改掉了后面所有帧的底。
	# 同一条坑 CLAUDE.md 里记着：「单旋钮对照实验必须一个旋钮一个进程」，
	# 这里更狠——不是重启，是**顺序**。
	await _attribute_box()
	print("[sky] 图: %s/p_dusk_*.png" % SAVE_DIR)


## 三层山线一层一层放回去，靠**相减**认出"哪条轮廓属于哪一层"。
##
## ## 为什么必须相减而不能用颜色阈值
##
## 上一版把「天穹地平线那道硬缝」判成天自己的缺陷，改了半天 `sky_curve`
## ——而那道边是 `FarRidge` 1900m 那层的**轮廓**。判据的取样框落在别人身上，
## 这是 CLAUDE.md 里「判据的取样点自己得先问一句落在什么东西上」那一族。
## 而"认轮廓"这件事**用颜色猜不出来**：正午那道边是 sRGB(214 级) 的淡带、
## 黄昏是另一套色，阈值一挪就换一个身份。
##
## 相减是**纯几何**的：把某一层藏起来重拍两张，变了的那批像素就是那一层。
## 和 `lookdev_water.gd` 那张洋红掩膜同一个办法——谁也不用猜颜色。
##
## 逐层放（而不是逐层撤）是为了让每一步只多出一层，于是每一层的掩膜
## 都是"它自己那一圈"，不用再做差分。
## 远景山线的填色标定：**一层一层单独放出来**，量每一层单独占屏时渲出来的
## 亮度，然后乘一个总系数扫一遍。
##
## ## 为什么必须"单独放"而不是三层叠着量
##
## 三层叠着时每一层的可见部分只有它自己那一圈，重叠处渲出来的是**三层的和**——
## 而"逐层递淡"那条回归量到的是这个和，于是**三层一起淡成一样白它照样全绿**
## （CLAUDE.md 里那条：「凡是靠依次递淡当观感的项，都得再补一条最远那层
## 离天空还得有对比」）。上一轮就是这么把 0.42 当成了"渲出来 0.42"。
##
## ## 量的是**轮廓顶上那一行**
##
## 山线的填色烘在顶点色里（`SHADING_MODE_UNSHADED` + `disable_fog`），
## 所以渲出来是多少只由 `LAYERS` 那个数加一层 tint 决定，没有别的变量。
## 轮廓顶行由"逐列往下找第一条跳变 ≥20 的边"自定位——那道边横贯整片天，
## 写死像素行就等于把判据挂在别人的轮廓上。
##
## ## 系数是乘在 **tint** 上的，因为 `vertex_color_use_as_albedo` 打开时
## `albedo_color` 是个乘数——`FarRidge.set_tint()` 本来就是给黄昏整体换色用的。
## 改 `LAYERS` 常量做不到"扫一档"，而这里要的正是"同一批几何、只动填色"。
##
## **三层的响应曲线不一样**，所以三层各扫各的：AGX 在高光那一头压得极狠，
## 远层反照率砍掉四成渲出来只掉了 8%（191 → 176），
## 而近层那一头还有斜率——**拿远层的系数去推近层，两层会并到同一个亮度上**。
func _ridge_cal() -> void:
	_freeze()
	var layers: Array = _world._ridge.get_children()
	var base: Color = (layers[0] as MeshInstance3D).material_override.albedo_color
	print("[cal] %d 层，基线 tint=%s" % [layers.size(), str(base)])
	# 只往下扫是不够的：黄昏那一档的缺陷是**三层并成同一块**（层与层之间只剩
	# 3~4 个亮度单位，而门槛要 8），而 tint 是**三层同乘**的乘数——它改不了
	# 彼此的比值，只能改整条 ramp 落在 AGX 的哪一段上。所以这里往上扫。
	for m in [1.0, 1.25, 1.50, 1.80, 2.20]:
		_world._ridge.set_tint(Color(base.r * m, base.g * m, base.b * m))
		var line := "[cal] tint×%.2f" % m
		for k in range(layers.size()):
			var only: Image = await _shoot_only(layers, [k])
			var e: Array = _top_edge(only)
			line += " | %s 层 %3.0f  层−天 %+4.0f" % [["近", "中", "远"][k], e[0], e[0] - e[1]]
		var all: Image = await _shoot_only(layers, [0, 1, 2])
		var ed: Array = _edge_ladder(all)
		line += " || 三条边的列 %d/5  台阶 %s" % [ed[0], str(ed[1])]
		print(line)
	for l in layers:
		l.visible = true
	_world._ridge.set_tint(base)


## 定妆照第 12f 节那条判据的原样实现：**逐列**从扫描带上沿往下找跳变
## ≥ `RIDGE_EDGE_MIN` 的边，一列凑齐三条边才算"三层山线各认得出自己"。
##
## 三个常量与**判据本身**都逐字抄自 `lookdev_journey.gd._ridge_edges()`
## （`RIDGE_SCAN_TOP` / `RIDGE_SCAN_BOTTOM` / `RIDGE_EDGE_MIN` / `RIDGE_MAX_EDGES`），
## 连"跳变取**三通道最大差**而不是亮度差"、"两条边至少隔 3 行"这两条也照抄。
## 这不是抄一份差不多的：亮度差在暖调的天底下会系统性偏小（蓝通道被压得最狠），
## 于是同一张图上这把尺子报 3/5、定妆照报 2/5——而**两个数都看着像真的**。
## 抄在这里是有意的：探针不该 import 一个 27 张图、约 4 分钟的定妆照脚本。
##
## 台阶报的是**前三条**边各自多大（天→远、远→中、中→近），因为"并成一块"
## 这个缺陷的形状就是"台阶掉到门槛以下"，而光报列数看不出是差在哪一步。
func _edge_ladder(img: Image) -> Array:
	var y1: int = clampi(int(float(SHOT.y) * RIDGE_SCAN_BOTTOM),
			RIDGE_SCAN_TOP + 1, SHOT.y - 1)
	var ok: int = 0
	var steps: Array[float] = []
	for fx in SKY_COLS:
		var x: int = clampi(int(float(SHOT.x) * fx), 0, SHOT.x - 1)
		var edges: Array = []
		var last := -9
		for y in range(RIDGE_SCAN_TOP, y1):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x, y + 1)
			var j: float = maxf(absf(a.r - b.r),
					maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
			if j >= RIDGE_EDGE_MIN and y - last >= 3:
				edges.append(j)
				last = y
				if edges.size() >= RIDGE_MAX_EDGES:
					break
		if edges.size() < RIDGE_MAX_EDGES:
			continue
		ok += 1
		for i in range(RIDGE_MAX_EDGES):
			while steps.size() <= i:
				steps.append(0.0)
			steps[i] += float(edges[i])
	return [ok, steps.map(func(v): return v / maxf(float(ok), 1.0))]


## 只放 `keep` 里那几层、藏掉其余的，拍一张。
##
## 必须能**单独放中间那一层**——三层叠着时量到的是三层的和，
## 而"哪一层比天亮"这条判据量的必须是那一层自己的颜色。
func _shoot_only(layers: Array, keep: Array) -> Image:
	for j in layers.size():
		(layers[j] as MeshInstance3D).visible = keep.has(j)
	# 这里等 8 帧而不是 4：这一节全部是"改完立刻回读"的差分，
	# 而回读拿到的要是上一档的残留，整张标定表就是错的。
	for i in 8:
		await process_frame
	return root.get_texture().get_image()


## 逐列往下找**第一条**跳变 ≥20 的边——那就是山线的轮廓顶。
## 返回 `[山那一侧的亮度中位, 它上面那一行天的亮度中位, 找到的列数, 轮廓顶行]`。
##
## 扫带下沿放到 **fy 0.40**：三层山线的角高度很接近（远 6.6~11.9°、
## 中 5.5~10.9°、近 4.3~9.2°），而近层那条边落在 **fy 0.25 之下**——
## 第一版扫到 180 就收，于是**近层一张都找不到**、报成"亮度 0"，
## 而 0 看着像"这层是黑的"，实际是**根本没量到**。
## 这正是 CLAUDE.md 里「改了没反应要先确认你改的那个东西找得到」：
## 一个读数 0 和一个"没找到"长得一模一样。
func _top_edge(img: Image) -> Array:
	var ridge: Array[float] = []
	var sky: Array[float] = []
	var ys := PackedInt32Array()
	for fx in SKY_COLS:
		var x: int = clampi(int(float(SHOT.x) * fx), 0, SHOT.x - 1)
		var hit: int = -1
		for y in range(SKY_SCAN_TOP, int(float(SHOT.y) * 0.40)):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x, y + 1)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g),
					absf(a.b - b.b))) * 255.0 >= 20.0:
				hit = y
				break
		if hit < 1:
			continue
		ys.append(hit)
		ridge.append(_lum(img.get_pixel(x, hit + 1)))
		sky.append(_lum(img.get_pixel(x, hit - 1)))
	return [_median(ridge), _median(sky), ridge.size(), ys]


func _lum(c: Color) -> float:
	return (c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722) * 255.0


## ## 逐层拉开间距（`LAYERS` 那条 ramp 的形状）
##
## `set_tint()` 是**三层同乘**一个乘数，所以它改不了层与层的**比值**——
## 它只能把整条 ramp 平移到 AGX 的另一段上。上面那张表已经量死了这件事：
## 乘数 ×1.25 把第一条边从 24 推到 36，而**中间那条只从 9.0 动到 9.5**，
## 到 ×1.8 远层直接比天还亮（+8，第二条判据当场红）而边数反而掉回 2/5。
##
## 所以间距只能逐层调。三层的 `material_override` 是三个独立对象，
## 给它们各自乘一个数**等价于**改 `FarRidge.LAYERS` 里那三个色
## （`albedo_color` 与顶点色相乘，而那一层就是乘在 `LAYERS` 上的同一个位置），
## 于是这一族能在**一个进程**里扫完，不必一档一次编辑-重跑。
##
## ## 为什么这里扫的是**正午**（`--spread-noon`），而正午的乘数是白的
##
## 黄昏那一份有 `DayCycle.DUSK_RIDGE_TINT`（1.30）可以抬，正午没有：
## `t=0` → `Color.WHITE.lerp(DUSK_RIDGE_TINT, 0)` 就是白。所以正午的层间距
## **只能由 `LAYERS` 自己扛**，黄昏那份抬乘数一点忙都帮不上。
##
## ## 这一节的结论改过一次，方向正好反过来
##
## 原来这里写着「远层比天只暗 5 个单位，抬远层会先在正午破」——那个数是
## `lookdev_journey` 拍的**一张 t≈0.167 的天**给的（里程计在拍正午那张之前
## 就推过了门槛，转场已经走了 1.5/9 秒）。改正之后真正的正午远层比天
## **暗 10**，于是抬远层在正午本来是安全的；而当时为了追那个假数去
## 「往下压中层」的一档，反而把中层压得比近层还暗，正午的
## `d_gap_near ≥ 5` 当场红——**症状是采样的天脏了，修法却在旋钮上找**。
## 可推广的一条（同一族第三处）：`lookdev_journey` 与 `probe_sky_grass`
## 都在同一族里栽过，而两处现在各有一条前提断言钉住 `t == 0`。
##
## 下面是**确认表**不是搜索表：基线在真正的正午上已经是 −60 / −32 / −10、
## 3/5 列，抬远层能换到 5/5（×1.15 / ×1.35 实测台阶 42.6/31.0/24.0）
## **代价是远层比天亮 +25**，直接破掉「最外层山不比天亮」。所以没抬。
func _ridge_spread() -> void:
	_freeze()
	var layers: Array = _world._ridge.get_children()
	var base: Color = (layers[0] as MeshInstance3D).material_override.albedo_color
	print("[spread] 基线 tint=%s" % str(base))
	for row in [[1.00, 1.00, 1.00], [1.00, 1.00, 1.15], [1.00, 1.00, 1.35],
			[1.00, 1.08, 1.20], [1.00, 1.15, 1.35]]:
		for j in layers.size():
			var k: float = float(row[j])
			(layers[j] as MeshInstance3D).material_override.albedo_color = \
					Color(base.r * k, base.g * k, base.b * k)
		var img: Image = await _shoot_only(layers, [0, 1, 2])
		var ed: Array = _edge_ladder(img)
		var line := "[spread] 近×%.2f 中×%.2f 远×%.2f || 边 %d/5  台阶 %s" % [
				row[0], row[1], row[2], ed[0],
				str(ed[1].map(func(v): return "%.1f" % v))]
		# 三层单独放一遍，量"山−天"——抬亮的那几档必须靠这条拦下来
		for k in range(layers.size()):
			var only: Array = await _top_edge(await _shoot_only(layers, [k]))
			line += " | %s层−天 %+4.0f" % [["近", "中", "远"][k], only[0] - only[1]]
		print(line)
	for l in layers:
		l.visible = true
		l.material_override.albedo_color = base


func _ridge_ladder() -> void:
	_freeze()
	var layers: Array = _world._ridge.get_children()
	print("[ridge] %d 层  LAYERS=%s" % [layers.size(),
			str(_world._ridge.LAYERS.map(func(l): return l["r"]))])
	var shots: Array = []
	for i in range(layers.size() + 1):
		for j in range(layers.size()):
			var mi: Node = layers[j]
			mi.visible = j >= i
		await _shoot_plain("p_ridge_%d" % i)
		var img: Image = root.get_texture().get_image()
		shots.append(img)
		print("[ridge] 第 %d 档：放出 %s" % [i,
				"（只剩天）" if i == 0 else "第 %d 层往后" % i])
	# 还原，免得影响后面任何东西
	for l in layers:
		l.visible = true
	var sky: Image = shots[0]
	for i in range(1, shots.size()):
		_report_layer(i, sky, shots[i])


## 报出「第 i 层那一圈」的中位亮度、它上面紧邻的那几行天（掩膜之外）的亮度，
## 以及两者之差——**带符号**。空气透视要求远处的山**不比天亮**，
## 所以正的差（山比天亮）才是缺陷，负的差（山比天暗）是正常的。
func _report_layer(idx: int, sky: Image, with_layer: Image) -> void:
	var changed: Array = []
	var lums_r: Array[float] = []
	for y in range(int(float(SHOT.y) * 0.08), int(float(SHOT.y) * 0.34)):
		for x in SKY_COLS:
			var xi: int = clampi(int(float(SHOT.x) * x), 0, SHOT.x - 1)
			var a := sky.get_pixel(xi, y)
			var b := with_layer.get_pixel(xi, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g),
					absf(a.b - b.b))) * 255.0 < 3.0:
				continue
			changed.append(Vector2i(xi, y))
			lums_r.append((b.r * 0.2126 + b.g * 0.7152 + b.b * 0.0722) * 255.0)
	if changed.is_empty():
		print("[ridge] 第 %d 层：在取样带里一个像素都没变（层序或可见性不对）" % idx)
		return
	var tops_y: Array[int] = []
	var sky_above: Array[float] = []
	for fx in SKY_COLS:
		var xi: int = clampi(int(float(SHOT.x) * fx), 0, SHOT.x - 1)
		var y_hit: int = -1
		for y in range(SKY_SCAN_TOP, int(float(SHOT.y) * 0.34)):
			var a := sky.get_pixel(xi, y)
			var b := with_layer.get_pixel(xi, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g),
					absf(a.b - b.b))) * 255.0 >= 3.0:
				y_hit = y
				break
		if y_hit < 1:
			continue
		tops_y.append(y_hit)
		var p := sky.get_pixel(xi, y_hit - 1)
		sky_above.append((p.r * 0.2126 + p.g * 0.7152 + p.b * 0.0722) * 255.0)
	var mr: float = _median(lums_r)
	var ms: float = _median(sky_above)
	print("[ridge] 第 %d 层 r=%5.0fm  占 %4d 像素  山亮度=%3.0f  它上面那行天=%3.0f  山−天=%+4.0f"
			% [idx, _world._ridge.LAYERS[idx - 1]["r"], changed.size(), mr, ms, mr - ms])
	print("           轮廓顶行 %s" % str(tops_y))


## 截图但不量四个判据（ladder 只关心逐像素相减）。
func _shoot_plain(name: String) -> void:
	for i in 4:
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [SAVE_DIR, name])


## 草皮的材质**走产品自己的出口** `GrassScatter.grass_material()`，
## 不在场景树里按 shader 源码文本重新发现一遍。
##
## 第一版是 `_meshes()` + `_mats_of()` 逐个节点找 `sh.code.find("blade_base")`，
## 结果四档全部打出「（0 个材质）」而后续帧逐字节相同——**改了个找不到的东西**，
## 于是那一整批旋钮从来没有被真的扫过。CLAUDE.md 里「改了没反应要先确认你改的
## 那个东西找得到」记的就是这一族：0 这个数看着像"调完没变化"，而它真正说的是
## "根本没匹配上"。产品把材质放在 `_mat` 里并且**由所有槽位共享**（一份材质、
## 几十个 `MultiMeshInstance3D`），所以按节点去找既是多余的，也是错的那条路。
func _set_grass(param: String, c: Variant) -> void:
	var m: ShaderMaterial = _world._grass_scatter.grass_material()
	if m == null or m.shader == null:
		print("[grass] %s —— 草皮材质是空的，这个旋钮没拧到任何东西上" % param)
		return
	if m.shader.code.find(param) < 0:
		print("[grass] %s —— 这个 uniform 在着色器源码里根本不存在" % param)
		return
	m.set_shader_parameter(param, c)
	print("[grass] %s = %s" % [param, str(c)])


## 拍一张、量三样、打印一行。
##
## **不再报"缝"**：那把尺子量的是 `FarRidge` 1900m 那层的**轮廓**，而山线是
## `SHADING_MODE_UNSHADED` 的硬边、轮廓本来就该硬——所以"缝 ≤ 24"量的不是缺陷。
## 真缺陷是**方向**（远山比天亮），判据与它的两条正对照已经搬进
## `lookdev_journey.gd` 第 12f 节；这里只留一个和那边同口径的读数方便对照。
##
## 帧数只等 4 帧：这一族没有级联（理由见文件头）。而**不能等成 1 帧**——
## `set_shader_parameter()` 改完之后那一帧的背景还是旧的。
func _shoot(name: String) -> void:
	for i in 4:
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [SAVE_DIR, name])
	var e: Array = _top_edge(img)
	var hue: Color = _sky_row(img, SKY_HUE_ROW)
	var grass: Array = _region_sat(img, GRASS_BOX)
	print("[m] %-22s 远山 %3.0f 层−天 %+4.0f（%d 列）| 天 r=%.2f g/r=%.2f b/r=%.2f | 落差 %2.0f%% | 草 饱和=%.3f 亮=%.3f"
			% [name, e[0], e[0] - e[1], e[2], hue.r, hue.g / maxf(hue.r, 0.001),
			hue.b / maxf(hue.r, 0.001), _sky_gradient(img) * 100.0,
			grass[0], grass[1]])


func _sky_row(img: Image, fy: float) -> Color:
	var y: int = clampi(int(float(SHOT.y) * fy), 0, SHOT.y - 1)
	var acc := Vector3.ZERO
	for fx in SKY_COLS:
		var p := img.get_pixel(clampi(int(float(SHOT.x) * fx), 0, SHOT.x - 1), y)
		acc += Vector3(p.r, p.g, p.b)
	var m := acc / float(SKY_COLS.size())
	return Color(m.x, m.y, m.z, 1.0)


## 天带落差，**逐字照抄 `lookdev_journey.gd._sky_gradient()` 改写后的那一版**：
## 逐列各自找它自己的山线轮廓顶，从扫描带上沿量到那一条边为止。
##
## 原来两边都取固定四行（fy 0.10~0.22），而实测 `FarRidge` 三层的轮廓顶就在
## fy 0.146~0.208 —— 后两行量到的是**山**不是天。探针这一版和定妆照那一版
## 报出来的数不一样（探针 38% / 定妆照 5%），差别全在取样的那两行落在什么上，
## 而两个数都看着像真的。抄改写后的那一版是为了让这个探针还能当那把尺子用。
func _sky_gradient(img: Image) -> float:
	var y1: int = clampi(int(float(SHOT.y) * RIDGE_SCAN_BOTTOM),
			RIDGE_SCAN_TOP + 1, SHOT.y - 1)
	var drops: Array[float] = []
	for fx in SKY_COLS:
		var x: int = clampi(int(float(SHOT.x) * fx), 0, SHOT.x - 1)
		var edge := -1
		for y in range(RIDGE_SCAN_TOP, y1):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x, y + 1)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0 \
					>= RIDGE_EDGE_MIN:
				edge = y
				break
		if edge <= RIDGE_SCAN_TOP + 1:
			continue
		var lo: float = _lum255(img.get_pixel(x, RIDGE_SCAN_TOP))
		var hi: float = _lum255(img.get_pixel(x, edge - 2))
		drops.append(absf(hi - lo) / maxf(lo, 0.001))
	if drops.is_empty():
		return -1.0
	drops.sort()
	return drops[drops.size() / 2]


static func _lum255(c: Color) -> float:
	return c.get_luminance() * 255.0


## 逐像素算完饱和度再取中位数（不是各通道中位数相减）。
## 返回 `[中位饱和度, 中位相对亮度]`——亮度一并打出来是因为"降饱和"和
## "降能量"在图上长得一样，而 CLAUDE.md 里记着黄昏过一次曝那一跤。
func _region_sat(img: Image, box: Rect2) -> Array:
	var sats: Array[float] = []
	var lums: Array[float] = []
	for y in _rows(box):
		for x in _cols(box):
			var c := img.get_pixel(x, y)
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			sats.append((mx - mn) / maxf(mx, 0.001))
			lums.append(c.get_luminance())
	return [_median(sats), _median(lums)]


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


## `GRASS_BOX` 里那一块像素到底是谁画的——**靠藏起来相减**认，不靠颜色猜。
##
## 为什么要先问这一句：`GRASS_BOX` 是 fy 0.47~0.55，正骑视角下落在路面上方、
## 行道树那一列那一带。把那一框裁出来放大四倍看，**满屏是大片的树冠卡片**
## （琥珀色 + 黑缝），而草皮卡片只有 0.24×0.085m，在那个距离上早就并成一层
## 平色了。也就是说「草 饱和=0.814」这个读数量的很可能是树，而 `blade_base`
## 那条旋钮**压根碰不到它**——去调一个够不着的数会把候选方案判死刑。
##
## 和山线那一族同一个办法：谁也不用猜颜色，变了的那批像素就是那一层。
## 顺带把「藏掉树之后那一块还剩多少饱和度」一起报出来——那才是
## `blade_*` 那几个旋钮真正能改的那个数。
func _attribute_box() -> void:
	var rows := _rows(GRASS_BOX)
	var cols := _cols(GRASS_BOX)
	var total: int = rows.size() * cols.size()
	var base: Image = await _hide_and_shoot([])
	var n_g: int = _changed_in_box(base,
			await _hide_and_shoot([_world._grass_scatter]))
	var no_tree: Image = await _hide_and_shoot([_world._tree_scatter])
	var n_t: int = _changed_in_box(base, no_tree)
	_world._grass_scatter.visible = true
	_world._tree_scatter.visible = true
	print("[box] GRASS_BOX 共 %d 像素：藏草皮变 %d（%.0f%%）　藏行道树变 %d（%.0f%%）"
			% [total, n_g, float(n_g) / float(total) * 100.0,
			n_t, float(n_t) / float(total) * 100.0])
	print("[box] 藏掉行道树之后 %s" % str(_region_sat(no_tree, GRASS_BOX)))


## 只藏住 `hide` 里那几样（其余照旧），拍一张。
func _hide_and_shoot(hide: Array) -> Image:
	_world._grass_scatter.visible = true
	_world._tree_scatter.visible = true
	for n in hide:
		n.visible = false
	for i in 8:
		await process_frame
	return root.get_texture().get_image()


func _changed_in_box(a: Image, b: Image) -> int:
	var n := 0
	for y in _rows(GRASS_BOX):
		for x in _cols(GRASS_BOX):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g),
					absf(p.b - q.b))) * 255.0 >= 3.0:
				n += 1
	return n