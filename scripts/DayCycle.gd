extends Node3D
## DayCycle — 骑满一圈之后，天色从正午走到黄昏。
##
## 这个世界的环路只有 1228.8m（见 CLAUDE.md 的已知陷阱），满速跑一圈 82 秒。
## 一趟 20~30 分钟（改版之后的下限是 3.1 分钟）就是好几圈同一片地：路、驿站、树、
## 天空，全都一模一样地看好几遍。
## 光照是唯一能让"同一段路"读起来像"另一段路"的东西，而且它几乎不要钱——
## 改的是几盏灯和天空的几个色，不是资产也不是贴图（本作零贴图）。
##
## 三个必须一起改的东西，少一个就露馅：
##   1. 主光的**方向**：只改颜色的话影子长度和方向没变，太阳像被人换了灯泡。
##   2. 天空与环境光：地是暖的、天是青白的，那不是黄昏，那是贴了张滤色片。
##   3. 远景山线：它 `SHADING_MODE_UNSHADED` 且 `disable_fog`（空气透视烘在
##      顶点色里），所以它**不吃场景光照**。不给它单独上色，三层山会顶着青灰色
##      站在一片橙里，天一暗整个地平线都在打架。
##
## 第 2 条是这个文件里最贵的一段：场景的环境是 `BG_SKY` + `AMBIENT_SOURCE_SKY`，
## 而它那份 ProceduralSky 是 Godot 3 的老数据、4.6 载入时静默丢掉了。于是
## `background_color` 和 `ambient_light_color` **一个像素都不影响画面**，
## 只改它们的话整段转场只有太阳和雾在动。得自己建一个真的
## `ProceduralSkyMaterial`（见下面那组 DAY_SKY_* / DUSK_SKY_* 的注释），
## 建好之后环境光自动跟着天空走。
##
## 起步档不做成两段跳变：转场 9 秒。骑过一圈要 82 秒，天在 9 秒里暗下去是
## 正常的；1 秒切完就成了有人拉了灯闸。

## 第几圈开始进黄昏。1.0 = 第二圈（骑满一整圈之后）。
##
## 原来是 2.0，那时候一趟要 20~30 分钟，于是黄昏那一档是「多骑几圈才看得到」的
## 彩蛋。现在一趟的下限是 **3.1 分钟**（`tools/play_newcomer.gd`），而满速跑一圈
## 只要 82 秒——2.0 意味着天在**这一趟快结束的时候**才开始暗，转场 9 秒还没走完
## 就跳结算页了。于是把这一整档放到一圈之内：一趟基本读成「第 1 圈白天 → 第 2 圈
## 黄昏」，而黄昏正是全场最好看的景之一，不该只给愿意再骑三圈的人看。
##
## 注意记里程的是**玩家实际走过的距离**（`_odometer_units`），而打卡要拐下路到亭子
## 跟前去，所以里程跑得比沿中心线快——1.0 实际比"骑满一圈"更早到。这条门槛是
## 观感门槛不是数学门槛，别拿它去反推"第几秒"。
const DUSK_FROM_LAP := 1.0
## 转场时长（秒）。
const FADE_SEC := 9.0

## 黄昏档：太阳压到 9°（白昼那档约 38°），再沿方位角转 38°。
## 方向必须改 —— 影子拉长是黄昏最认得出的特征，比任何颜色都管用。
const DUSK_ELEV_DEG := 9.0
const DUSK_AZIM_SWING_DEG := 38.0

# ---- 天色 ----
#
# 这两档**不能从场景里读**：World3D.tscn 里那份 ProceduralSky 是 Godot 3 的老
# 数据（键名是 sky_horizon / sky_energy），4.6 载入时把那整个 sub_resource 静默
# 丢掉了，运行时读出来 `sky.sky_material == null`。而 `background_mode = 2`（BG_SKY）
# 配一个空 material 渲出来的是引擎自带的兜底渐变 —— 于是两件事同时成立：
#   · `Environment.background_color` **完全不起作用**（BG_SKY 模式下不画它），
#   · `ambient_light_source = 3`（AMBIENT_SOURCE_SKY）取的是那份兜底天的辐照度，
#     所以 `ambient_light_color` 同样不起作用，环境光**只认 `ambient_light_energy`**。
# 换句话说：只改 background_color / ambient_light_color 的那套写法，天和暗部
# 一个像素都不动，整段"走到黄昏"只有太阳和雾在动，地面亮度纹丝不动。
#
# 所以这里建一个真的 ProceduralSkyMaterial。下面的白昼档不是抄来的，是把
# World3D.tscn 里被丢掉的那几个键原样搬回来（lookdev_horizon.gd 早就照着同一组
# 数在渲远景定妆照，两边必须一样，否则山线定妆照判的就不是游戏里的天）。
# 建了之后环境光自动跟着天空走 —— 这才是对的：黄昏地面变暗是因为**天在暗**，
# 不是因为有人在灯上打了个折。

## 白昼：天顶深蓝 → 地平线泛白，地面方向压成灰绿（别让天从草里透出来）。
##
## **这六个常量是按 sRGB 写的，交给 material 之前一律过一遍 `srgb_to_linear()`**
## （见 `_apply()`）。天空色在引擎里是**辐照度**、直接当线性值用，不像普通材质
## 那样帮你转一遍——所以 `DAY_SKY_HORIZON` 写成 (0.72, 0.85, 0.97) 这个"看着
## 是淡青白"的数，渲出来是 sRGB(0.87, 0.94, 0.99)，**几乎就是白的**。
## 而天上最亮的那一片进到 AGX 的高光肩之后会被再去一次饱和，于是整片天读成
## **一张一整片的灰蓝纸**：实测骑行视角下（仰角 0~22.5°）从天顶到地平线只有
## **8%** 的亮度差，而把那六个数原样换成线性值之后是 **37%**。
## 可推广的一条：**凡是"我照着显示器调了个颜色，结果渲出来不是那个颜色"，
## 先问那个颜色是不是要自己转色彩空间**——本工程已经栽过一次同族：
## `FarRidge` 的顶点色（见 CLAUDE.md 已知陷阱里 AGX 那条）。
const DAY_SKY_TOP := Color(0.27, 0.53, 0.95, 1.0)
const DAY_SKY_HORIZON := Color(0.72, 0.85, 0.97, 1.0)
const DAY_GND_HORIZON := Color(0.62, 0.70, 0.60, 1.0)
const DAY_GND_BOTTOM := Color(0.42, 0.48, 0.40, 1.0)
const DAY_SKY_CURVE := 0.15
const DAY_GND_CURVE := 0.02
## 白昼的太阳角度：DirectionalLight3D 才是太阳的真身，这两个只是决定天上那颗
## 亮斑糊成多大一片。
const DAY_SUN_ANGLE_MAX := 90.0
const DAY_SUN_CURVE := 0.04

## 黄昏：天顶压到深靛、地平线烧成橙红。渐变是黄昏唯一认得出的形状 —— 纯色
## 的天在日间是"平铺"，到黄昏就该是"上暗下亮"，不然读成"换了张滤色片"。
const DUSK_SKY_TOP := Color(0.10, 0.12, 0.28, 1.0)
const DUSK_SKY_HORIZON := Color(0.95, 0.52, 0.26, 1.0)
const DUSK_GND_HORIZON := Color(0.40, 0.28, 0.24, 1.0)
const DUSK_GND_BOTTOM := Color(0.13, 0.11, 0.12, 1.0)
const DUSK_SKY_CURVE := 0.10
const DUSK_GND_CURVE := 0.05
const DUSK_SUN_ANGLE_MAX := 24.0
const DUSK_SUN_CURVE := 0.10

# ---- 灯与雾 ----

## 太阳：压低 + 转暖，光强要真的降下来。只把 38° 压到 9° 是不够的 —— 草皮是
## 一片片**竖着的**卡片，侧面朝着方位角，太阳压低反而打得更正对，卡片比
## 地面本身亮得多；能量只从 1.1 降到 1.05 时渲出来是一片亮黄油的草，
## 配一片灰粉的天，看着是"下午起了雾"，不是黄昏。
const DUSK_SUN_COL := Color(1.0, 0.70, 0.42, 1.0)
const DUSK_SUN_ENERGY := 0.70
## 补光反过来：天光从青白转成冷紫，给暗面一点和太阳相反的色，黄昏才有层次。
const DUSK_FILL_COL := Color(0.40, 0.44, 0.72, 1.0)
const DUSK_FILL_ENERGY := 0.55
## 环境光 = 天空辐照度 × 这个系数。黄昏档略微抬一点：天空本身已经很暗，
## 不抬的话背光的树冠会黑成一团剪影，而山线是 unshaded 的、压根不吃这一套，
## 亮暗差一大，地平线上会出现一条断带。
const DUSK_AMB_ENERGY := 0.55
## 雾：转成暖橙，但要比天更暗一档。雾是唯一压住远景的东西，它不换色，远处
## 就还是白天那层青灰；反过来雾比天亮的话，地平线附近会浮出一条白带。
const DUSK_FOG_COL := Color(0.62, 0.40, 0.34, 1.0)
## 山线是 unshaded，albedo_color 在这里就是个乘数：白 = 原样。
## 天压暗之后乘数要跟着抬一点，否则最远那层会和天糊成一片，纵深又没了。
const DUSK_RIDGE_TINT := Color(0.86, 0.64, 0.62, 1)

var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _ridge: FarRidge = null
## 三处水。参数默认 null 是为了让老的调用点（工具脚本）不用跟着改，
## 而"忘了传水"的表现是黄昏档的水仍然亮着——`set_tint` 里那个 null 判断
## 就是为它留的。
var _water: Node3D = null

var _day_basis := Basis.IDENTITY
var _dusk_basis := Basis.IDENTITY
var _day := {}          # 白昼那一档的原始值，setup() 里从场景读
var _t := 0.0          # 0 = 正午，1 = 黄昏
var _announced := false
var _ready_done := false


## 由 World3D 在自己 _ready() 末尾调。参数是那边已经建好的引用，
## 不在这里 get_node("../…") —— 万一以后这节点被挪进别的层级，跨层找节点
## 会在运行时报一串与本文件无关的 null。
func setup(sun: DirectionalLight3D, fill: DirectionalLight3D, world_env: WorldEnvironment,
		ridge: FarRidge, water: Node3D = null) -> void:
	_sun = sun
	_fill = fill
	_ridge = ridge
	_water = water
	if _sun == null or world_env == null or world_env.environment == null:
		push_warning("DayCycle.setup(): 缺主光或环境，昼夜切换不会发生")
		return
	# Environment 是 World3D.tscn 里的 **sub_resource**：场景的每个实例共用同一个
	# 资源对象。直接改它等于把 World3D.tscn 改了 —— 这一趟骑完回主菜单再进来，
	# 新的 World3D 开局就是黄昏，而 t=0 会去 lerp 一个已经被写成黄昏的"白昼档"，
	# 于是天色永远回不到白天。DirectionalLight3D 的颜色挂在**节点**上所以没事，
	# 别拿"灯没中招"推断"环境也不会"。
	_env = world_env.environment.duplicate()
	world_env.environment = _env
	# Sky 同样是 sub_resource，所以整个换掉而不是就地改它的 material。
	# 顺带把 `background_mode` 钉在 BG_SKY：白天的天就是靠它画的。
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = DAY_SKY_TOP.srgb_to_linear()
	_sky_mat.sky_horizon_color = DAY_SKY_HORIZON.srgb_to_linear()
	_sky_mat.sky_curve = DAY_SKY_CURVE
	_sky_mat.ground_horizon_color = DAY_GND_HORIZON.srgb_to_linear()
	_sky_mat.ground_bottom_color = DAY_GND_BOTTOM.srgb_to_linear()
	_sky_mat.ground_curve = DAY_GND_CURVE
	_sky_mat.sun_angle_max = DAY_SUN_ANGLE_MAX
	_sky_mat.sun_curve = DAY_SUN_CURVE
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY
	# 白昼那一档（灯、雾、环境光系数）**从场景里读**，不在这儿再抄一份。
	# 抄一份的话谁改了 World3D.tscn 里的颜色，转场第一帧就会跳一下。
	# 天空例外，理由见上面那组 DAY_SKY_* 的注释：场景里那份是空的，读不到。
	_day = {
		"sun_col": _sun.light_color, "sun_energy": _sun.light_energy,
		"fill_col": _fill.light_color if _fill != null else Color.WHITE,
		"fill_energy": _fill.light_energy if _fill != null else 0.0,
		"amb_energy": _env.ambient_light_energy,
		"fog_col": _env.fog_light_color,
	}
	# 但姿态要**只保住 Z 轴**地重正交化：World3D.tscn 里那盏灯的 basis
	# 三列长度是 0.997/0.99/0.812，不是正交阵，`Basis.slerp()` 会拒绝它
	# （"must be normalized in order to be casted to a Quaternion"，每帧刷一串红字）。
	# 而 `orthonormalized()` 走的是 Gram-Schmidt，它会连 Z 一起挪（实测太阳仰角
	# 从 38° 变 39.9°），等于顺手改掉了白天的影子。方向光只用 -Z，
	# 所以按 (仰角, 方位角) 重搭一套正的、Z 逐分量对齐，才是真的"没动过"。
	_day_basis = _basis_from_angles(_elev_of(_sun.basis), _azim_of(_sun.basis))
	_dusk_basis = _dusk_from(_day_basis)
	_ready_done = true
	_apply(0.0)


## 由 World3D 每帧按里程调。laps 是骑过的圈数（可以带小数），delta 用它自己
## 那个时钟的帧长 —— 不在函数里取 get_process_delta_time()，那读到的是**渲染**
## 帧长，和物理帧对不上，转场速度会随帧率飘。
func set_laps(laps: float, delta: float) -> void:
	if not _ready_done:
		return
	var target: float = 1.0 if laps >= DUSK_FROM_LAP else 0.0
	_t = move_toward(_t, target, maxf(delta, 0.0) / FADE_SEC)
	_apply(_t)
	if _t >= 1.0 and not _announced:
		_announced = true
		dusk_began.emit()


## 转场完成时发一次，好让 World3D 浮一行字告诉玩家"天暗了是故意的"。
## 没有这一句，玩家只会以为显卡掉了。
signal dusk_began

## 当前处在白昼还是黄昏（0..1）。给回归和定妆照读。
func get_t() -> float:
	return _t


## 由正午那档的 basis 推出黄昏那档：压低仰角、挪方位角。
##
## DirectionalLight3D 的光线沿自身 -Z 走，所以局部 +Z 指向太阳所在的那一侧，
## 直接拿 basis 的 Z 列当"太阳在哪"就行，不必去反光线方向。
static func _elev_of(b: Basis) -> float:
	return asin(clampf(b.z.normalized().y, -1.0, 1.0))


static func _azim_of(b: Basis) -> float:
	var s := b.z.normalized()
	return atan2(s.x, -s.z)


static func _dusk_from(day: Basis) -> Basis:
	return _basis_from_angles(deg_to_rad(DUSK_ELEV_DEG),
			_azim_of(day) + deg_to_rad(DUSK_AZIM_SWING_DEG))


## 太阳在 (仰角, 方位角) 上时 DirectionalLight3D 该摆的 basis。
## 约定与 HUD 的箭头一致：`a = atan2(v.x, -v.z)`，正前方 (-Z) 是 0、正右方 (+X) 是 +π/2。
static func _basis_from_angles(elev: float, azim: float) -> Basis:
	var z := Vector3(cos(elev) * sin(azim), sin(elev), -cos(elev) * cos(azim))
	var x := z.cross(Vector3.UP)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


func _apply(t: float) -> void:
	if _sun != null:
		# slerp 而不是在两套 basis 之间逐分量插值：欧拉角在接近万向节死锁时
		# 会绕远路，太阳会先往上蹿一下再落下去。
		_sun.basis = _day_basis.slerp(_dusk_basis, t)
		_sun.light_color = (_day["sun_col"] as Color).lerp(DUSK_SUN_COL, t)
		_sun.light_energy = lerpf(_day["sun_energy"], DUSK_SUN_ENERGY, t)
	if _fill != null:
		_fill.light_color = (_day["fill_col"] as Color).lerp(DUSK_FILL_COL, t)
		_fill.light_energy = lerpf(_day["fill_energy"], DUSK_FILL_ENERGY, t)
	if _sky_mat != null:
		# **lerp 在 sRGB 空间做、换算在最后做**：天空色之间那 9 秒的交叉淡入，
		# 在 sRGB 里插是"两种天互相溶"，在线性里插中段会塌成一团发灰的泥。
		# 反正常量是按 sRGB 写的（见上面那段），这样写连中间态都对。
		_sky_mat.sky_top_color = DAY_SKY_TOP.lerp(DUSK_SKY_TOP, t).srgb_to_linear()
		_sky_mat.sky_horizon_color = DAY_SKY_HORIZON.lerp(DUSK_SKY_HORIZON, t) \
				.srgb_to_linear()
		_sky_mat.sky_curve = lerpf(DAY_SKY_CURVE, DUSK_SKY_CURVE, t)
		_sky_mat.ground_horizon_color = DAY_GND_HORIZON.lerp(DUSK_GND_HORIZON, t) \
				.srgb_to_linear()
		_sky_mat.ground_bottom_color = DAY_GND_BOTTOM.lerp(DUSK_GND_BOTTOM, t) \
				.srgb_to_linear()
		_sky_mat.ground_curve = lerpf(DAY_GND_CURVE, DUSK_GND_CURVE, t)
		_sky_mat.sun_angle_max = lerpf(DAY_SUN_ANGLE_MAX, DUSK_SUN_ANGLE_MAX, t)
		_sky_mat.sun_curve = lerpf(DAY_SUN_CURVE, DUSK_SUN_CURVE, t)
	if _env != null:
		# 只有 ambient_light_energy 在动：环境光取的是天空辐照度（AMBIENT_SOURCE_SKY），
		# 天一暗地面自然跟着暗，ambient_light_color 在这个模式下压根不读。
		_env.ambient_light_energy = lerpf(_day["amb_energy"], DUSK_AMB_ENERGY, t)
		_env.fog_light_color = (_day["fog_col"] as Color).lerp(DUSK_FOG_COL, t)
	if _ridge != null:
		_ridge.set_tint(Color.WHITE.lerp(DUSK_RIDGE_TINT, t))
	if _water != null:
		_water.set_tint(Color.WHITE.lerp(DUSK_RIDGE_TINT, t))


## 白昼那一档的原始值。给回归读（"t=0 时场景没被动过"这条只有它能量）。
func day_value(k: String) -> Variant:
	return _day.get(k)
