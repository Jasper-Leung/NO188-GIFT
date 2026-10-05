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
##
## **而这两个数是"染色"不是"天色"** —— 这是 Godot 4 改不掉的坑：
## `ProceduralSkyMaterial` 在 4.x **只有物理散射一种模型**（4.0 删掉了 Preetham，
## 连 `sky_type` 这个属性都不存在了），`sky_top_color` / `sky_horizon_color`
## 是**乘在散射结果上的滤镜**，不是天本身的颜色。太阳压到 9° 时散射结果**自己**
## 就是一条深红带，于是再乘一层饱和的橙 (0.95, 0.52, 0.26)：红乘 0.95 几乎不动，
## 而绿先被散射压到很小、再乘 0.52 —— **两个红相乘，小通道被压两遍**。
## 实测 `12c_dusk` 那一屏整条天带是 sRGB(0.377, 0.007, 0.030)，**g/r = 0.019**
## （输入的 g/r 是 0.55），绿和蓝在物理上归零，读成一张红色滤色片而不是天。
## 排除过的两条，别再重新怀疑：`tonemap_mode = 3`（AGX）**不背这个锅**——同一个
## (0.95,0.52,0.26) 单独过 AGX 出来是 (1.000, 0.702, 0.369)，绿反而被抬上去；
## 心神遮罩也不背（同一帧顶栏金字日/昏两档逐通道相同）。
## 所以滤镜本身要收着写：**暖意交给散射和太阳，滤镜只留一点点偏红**。
const DUSK_SKY_TOP := Color(0.14, 0.16, 0.32, 1.0)
const DUSK_SKY_HORIZON := Color(0.98, 0.74, 0.68, 1.0)
const DUSK_GND_HORIZON := Color(0.40, 0.28, 0.24, 1.0)
const DUSK_GND_BOTTOM := Color(0.13, 0.11, 0.12, 1.0)
## ## 0.10 → 3.00，地平线的蓝 0.58 → 0.68（2026-10-04，量出来的）
##
## 「黄昏的天留住绿与蓝」那条判据量的是 `SKY_HUE_ROW`(fy 0.12) 那一行的
## g/r 与 b/r，原读数 0.420 / 0.225——整片天读成一张红色滤色片。
##
## 第一版认定这条**够不到**，依据是逐条扫旋钮：`ground_horizon_color`
## 换成 `sky_horizon_color` 之后那个数**一格没动**（0.42/0.22 → 0.42/0.22，
## 因为 `eyedir.y > 0` 时 `ground_*` 那个分支压根不取样），而 `sky_curve`
## 从 0.10 扫到 10.0 也只把 b/r 抬到 0.41 就**平了**。
## 那个结论是**错的**，错在一次只动一个旋钮：把两条摆成一张网格再扫就出来了
## （`tools/probe_sky_grass.gd`，逐格都渲了像素）：
##
## | `sky_curve` \ 地平线蓝 | 0.58 | 0.68 | 0.78 | 0.90 |
## |---|---|---|---|---|
## | 0.10 | .42/.22 | .42/.35 | .42/.52 | .42/.81 |
## | 1.00 | .64/.37 | .64/.52 | .64/.69 | .64/.88 |
## | 3.00 | .68/.40 | **.68/.56** | .68/.73 | .68/.90 |
##
## 两个旋钮各管一路，互不干扰：**g/r 由 `sky_curve` 管**（地平线色往上铺多远），
## **b/r 由地平线蓝管**。取 3.00 / 0.68 那一格——两路都有 ≥0.11 的余量，
## 而 0.10 那一行不管地平线蓝调到多少 g/r 都钉在 0.42。
##
## 地平线调淡不只是为了过判据：`verify_day_cycle.gd` 早就写明黄昏地平线是
## **乘在散射结果上的滤镜**，而散射自己已经是深红带，所以「滤镜不许自己先饱和」
## （min/max ≥ 0.50）。原来 0.58/0.98 = 0.59 刚过线，蓝通道要被连压两遍；
## 0.68/0.98 = 0.69 之后黄昏那一档从「红」读成「暖橙」，而它仍然 r > b
## （同一条的正对照，所以两条一起绿）。
const DUSK_SKY_CURVE := 3.00
const DUSK_GND_CURVE := 0.05
const DUSK_SUN_ANGLE_MAX := 24.0
const DUSK_SUN_CURVE := 0.10

# ---- 灯与雾 ----

## 太阳：压低 + 转暖，光强要真的降下来。只把 38° 压到 9° 是不够的 —— 草皮是
## 一片片**竖着的**卡片，侧面朝着方位角，太阳压低反而打得更正对，卡片比
## 地面本身亮得多；能量只从 1.1 降到 1.05 时渲出来是一片亮黄油的草，
## 配一片灰粉的天，看着是"下午起了雾"，不是黄昏。
const DUSK_SUN_COL := Color(1.0, 0.80, 0.64, 1.0)
const DUSK_SUN_ENERGY := 0.70
## 太阳色也一起收着，理由和上面那两个滤镜同源、但机制不同：这一份是**真的**
## 乘在每一张草皮卡片上的，而草皮是竖着的卡片、吃满这份光。旧值 (1.0,0.70,0.42)
## 自身 sRGB 饱和度 0.58，量到的是**黄昏农田饱和度从白昼的 0.39 跳到 0.74**
## （右侧背光那片更极端，0.45 → 0.94），而亮度只有白昼的 12% —— 于是全屏没有
## 一个像素过曝（实测 clipped = 0.000），却读成一层饱和橙。
## **「过曝」和「高饱和」在图上长得一样，但修的旋钮不同**：过曝要降能量，
## 高饱和要降色纯度，而降能量会把黄昏压成一团黑。
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
##
## 它是**三层同乘**的，所以它管不了层与层的**比值**，只管整条 ramp 落在 AGX 的
## 哪一段上——而黄昏要的恰恰是"整条抬上去"：天色那一轮把 `DUSK_SKY_CURVE`
## 从 0.10 提到 3.00、地平线蓝从 0.58 提到 0.68 之后，黄昏的天**亮了一大截**，
## 而山线还是原来那份偏暗的填色，于是它在黄昏读成 L 76/86/94 的三道暗带，
## 层与层的间距掉到判据（≥5）之下。**天一亮，山就得跟着抬**，否则空气透视
## 的方向反了——原来这一档写的是 (0.86,0.64,0.62)，那是"跟着天一起暗"，
## 是修天之前那个更暗的黄昏才对的数。
##
## 抬多少是量出来的（`tools/probe_sky_grass.gd --spread`）：**比值归 `LAYERS` 管，
## 余量归这里管**，两头各扫各的。层与层的间距在 `LAYERS` 里拉开之后，剩下的
## 是把整条 ramp 推离 AGX 的趾部。
const DUSK_RIDGE_TINT := Color(1.30, 0.97, 0.94, 1)
## 水面另有一份。黄昏的水本来就靠"比天更暗一档"压住远景，跟着山线一起抬到
## 1.30 会让水在天底下发白——而山线和水从来没有同一个理由被同一个数管过。
const DUSK_WATER_TINT := Color(0.86, 0.64, 0.62, 1)

var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _ridge: FarRidge = null
## 草皮（scripts/GrassScatter.gd）。草皮的颜色是整片写死的常量，不走 PBR，
## 也不像山线和水面那样已经挂了一层 set_tint —— 昼夜切换必须单独推一次，
## 否则黄昏那一档它是全屏最亮的一块。setup() 的最后一个参数。
var _grass: Node = null
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
		ridge: FarRidge, water: Node3D = null, grass: Node = null) -> void:
	_sun = sun
	_fill = fill
	_ridge = ridge
	_water = water
	_grass = grass
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
	# 引擎侧先量过一遍：**Godot 4.6 的 `ProceduralSkyMaterial` 没有任何云属性。**
	# 整张属性表 25 条（`sky_top_color` / `sky_horizon_color` / `sky_curve` /
	# `ground_*` / `sun_angle_max` / `sun_curve` / `sky_cover` /
	# `sky_cover_modulate` / `*_energy_multiplier` / `use_debanding` …），
	# 没有 `cloud_*`、没有 `coverage` —— 所以"给天加几朵云"在本引擎上
	# 不是一个旋钮，要做只能是另铺一层自己的网格。
	#
	# 而另铺一层在这个取景下量不到好处，只量得到代价（2026-10-05 实测）：
	# 骑行视角 `12b_day_正午.png` 里**看得见的天只有 fy 0.086~0.15 一条**——
	# 上面是顶栏衬底（fy 0.086 以下），下面 `FarRidge` 三层的轮廓顶实测在
	# fy 0.15~0.28 —— 也就是**屏高 6%**。而 `lookdev_journey.gd` 的
	# `SKY_HUE_ROW = 0.12`（`day_row.r < day_row.b * 0.75`、黄昏那两条色相方向）
	# 量的是**同一条带**，而且 `_sky_row()` 是 **5 列的均值不是中位数**——
	# 一朵跨住两列的白云就足以把 r/b 推过 0.75。那会红，而那个红的意思是
	# "云画对了"，不是产品坏了。
	#
	# 所以这里**不加云，也不放宽那两条判据**（它们当初是因为评审那条红滤片带
	# 才加的）。要看天，把相机抬起来拍 `lookdev_horizon.gd` 的 `road_eye` /
	# `hilltop`，那两张开角大得多，云层在那儿是有的地方可放的。
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
		_water.set_tint(Color.WHITE.lerp(DUSK_WATER_TINT, t))
	if _grass != null:
		_apply_grass_light(t)


## 草皮的昼夜染色。草皮是整片写死的常量色，不走上面那几套（有 PBR 的、
## 有 set_tint 的），所以必须单独推一次——否则黄昏那一档草皮是全屏最亮的一块。
##
## 色相与亮度分开算：合成一个 Color 再插值是错的——"天变红"和"天变暗"会互相
## 抵消，红得不够、暗得也不够，最后还是一块亮黄绿。
##
## 亮度以白昼那一档为 1.0，所以 t=0 时这个系数必须精确等于 1，
## 否则"按开始到第一次昼夜切换之间草皮被悄悄调过"这种漂移没人查得到。
##
## ## 色相为什么不能只报太阳色（2026-10-04，量出来的）
##
## 原来 tint 直接就是太阳色，而黄昏那一档归一化之后是 (1.00, 0.80, 0.64)——
## 绿的草皮乘上去**蓝通道只剩红通道的 0.64**，于是黄昏草带渲成 (99,61,13)、
## 中位饱和度 **0.869**，全屏最艳的一块，读出来像自发光（那个症状早就写在
## `grass.gdshader` 的注释里了，只是那一族旋钮一个都碰不到它）。
##
## 计划里给的两条候选都扫过、都够不到，而**够不到的原因正是它们都在拧能量**：
## · `DUSK_FILL_ENERGY` 0.55 → 2.4：0.819 → 0.707。那盏冷补光本来就照着草皮，
##   可它在**灯**那一侧，而橙调是在 **albedo** 那一侧乘进来的——灯侧加得再多
##   也压不住一个乘数
## · `blade_*` 蓝通道顶到 `verify_grass_scatter.gd` 允许的上限 0.45：→ 0.763
##
## 正解是**tint 往天光那边混**。真实黄昏里草皮主要被天穹照着：卡片是**竖着**
## 的、吃环境光，太阳压到 9° 之后掠射方向的贡献很小，而天穹那一档是紫蓝的
## ——就是 `DUSK_FILL_COL (0.40,0.44,0.72)`。
##
## 系数是量出来的（`tools/probe_sky_grass.gd`，**摆的是这一整条算式**
## 而不是只摆 tint——`GrassScatter.set_light()` 会把 tint 归一化，而 AGX 在这个
## 亮度上又不是线性的，只扫一半算式量到的数推不出产品的旋钮）。
## 取 **1.00**，也就是**把 tint 整个交给天光**：
## 0.85 → 0.586／0.90 → 0.558／0.95 → 0.530／**1.00 → 0.500**。
## 门槛 0.55，而 1.00 正好落在 **0.500**——"黄昏的草皮不许比正午的更艳"
## 这条线（`lookdev_journey.gd` 12g 的正午对照门槛也是 0.50）。
## 亮度 0.233，与正午那一档基本齐平，所以"降饱和"没有顺带降掉亮度。
##
## **这一档的数在同一天里被量过两遍，而两遍差 0.08**——记在这儿是因为它差点
## 变成又一次"同一个 bug 改了很多次都没改到"：第一遍是在**天色修好之前**
## 量的（那时 `DUSK_SKY_CURVE` 还是 0.10），曲线是 0.70→0.571 / 0.85→0.500，
## 于是选了 0.85；修好天之后同一个旋钮只到 0.586，定妆照当场红。
## 草皮吃环境光、环境光来自天，所以**改天之后草皮那条曲线整条作废**，
## 必须重扫——探针里那一组"摆回产品档"的天色参数现在是从 `DayCycle` 的常量
## 上取的（`DUSK_SKY_CURVE` 等），**不许再手抄一份**：抄旧值等于把世界拨回
## 那个已经不存在的天底下，然后照着一个假的数去推旋钮。
const DUSK_GRASS_SKY_MIX := 1.00
func _apply_grass_light(t: float) -> void:
	var sun_col: Color = _sun.light_color if _sun != null else Color.WHITE
	var fill_col: Color = _fill.light_color if _fill != null else Color.WHITE
	var sun_e: float = _sun.light_energy if _sun != null else 0.0
	var amb_e: float = _env.ambient_light_energy if _env != null else 0.0
	var day_e: float = float(_day.get("sun_energy", 1.0)) 			+ float(_day.get("amb_energy", 0.0))
	var e: float = (sun_e + amb_e) / maxf(day_e, 0.0001)
	var sun_h := _hue(sun_col)
	var tint: Color = sun_h.lerp(_hue(fill_col), t * DUSK_GRASS_SKY_MIX)
	# 归一化的 tint **只带色相不带亮度**，混过去之后三路的均值会掉
	#（0.813 → 0.750）。那部分得补回 `light_energy`，否则"降饱和"就顺带
	# "降了亮度"，而这两件事在图上长得一模一样。
	# t=0 时 tint == sun_h、比值精确为 1，所以白昼那一档一个像素都不动。
	e *= _mean(sun_h) / maxf(_mean(tint), 0.0001)
	# 下限不是 0.35：草皮在大景里是**唯一**还在的东西，压到接近零会让黄昏的
	# 路两侧读成两道黑边。实测这一档落在 0.55~0.6 之间，配上偏紫的 tint
	# 就已经是"暮色里的草"而不是"荧光棒"。
	_grass.set_light(tint, clampf(e, 0.35, 1.0))


static func _hue(c: Color) -> Color:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	return c if mx <= 0.0001 else Color(c.r / mx, c.g / mx, c.b / mx)


static func _mean(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


## 白昼那一档的原始值。给回归读（"t=0 时场景没被动过"这条只有它能量）。
func day_value(k: String) -> Variant:
	return _day.get(k)
