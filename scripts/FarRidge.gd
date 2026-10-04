extends Node3D
class_name FarRidge
## FarRidge — 远景山线。世界是个 800×800 的方形地形，边缘之外什么都没有，
## 于是地平线是一条笔直的草绿接天蓝——"把家乡的山水装进行囊"这句话在屏幕上
## 找不到任何山。这里补三层环形山脊，纯几何零贴图。
##
## 三层是刻意的：单层山脊在 8 字路这种"哪儿都能望出去"的平地上会像贴上去的
## 壁纸，三层按距离递淡（顶点色直接烘进空气透视）才有纵深。
##
## 半径都要大于地形半对角线（800/2·√2 ≈ 566m），否则山会插进地形里。

const SEGMENTS := 360
## 山脊底边压到地平线以下，免得从任何角度看到"山脚浮在草地上方"
const BASE_Y := -70.0

## 每层：半径、最低峰、最高峰、颜色。
##
## 颜色是**反着调的**，别照着天空去挑：场景走的是 AGX 色调映射，中间调会被
## 显著提亮并去饱和。按"看起来该是深青灰"去填色（0.3 左右）渲出来是一线白。
## 调映射前给的是下面这几个很暗的值，渲出来才落到想要的空气透视梯度上。
##
## 三层的跨度要**压住**（2026-10-01 看 road_eye / hilltop 两张量出来的）：
## 原来的近/中/远是 0.13 / 0.30 / 0.52，AGX 之后中远两层一起被推到接近白，
## 于是三层里只有近层那条暗绿读得出来，另两层糊成一道白痕贴在天上——
## "三层纵深"在图上根本不存在，horizon 看着是三条平色带而不是山。
##
## ## 然后整条 ramp 还要再压一档（2026-10-04，量出来的）
##
## 上一版压完跨度之后仍然**越了另一条线**：空气透视要求远处的山**不比天亮**，
## 而 1900m 那层渲出来是 sRGB(179,191,221)、它背后那一行天是 (122,150,219)
## ——**亮 43 个单位**。于是地平线上横着一道**比天还白的硬边**，轮廓又硬又是亮的，
## 骑行视角下读成"天上贴了一条褪色的纸"，而它被记成了"天穹地平线那道硬缝"。
## 逐层去看还是错认成天自己的缺陷——因为判据的取样带落在别人身上
## （CLAUDE.md：「判据的取样点自己得先问一句落在什么东西上」）。
##
## 正解是**判据换成这条**（"最外层山不比天亮"）并配一组正对照
## （"它得仍然读得出来"、"三层仍然分得开"），而修法是把整条 ramp 压到
## **AGX 还有斜率的那一段**：乘 0.70 之后亮度 0.155 / 0.181 / 0.204。
##
## 为什么不压得更狠、也不压得更松：两头都有硬约束。
## 压得更狠（×0.5）三层一起掉到 54 / 61 / 67，**远层比它背后的天暗 82 个单位**，
## 那就不是空气透视而是一条黑墙；压得更松（×1.0）远层是 176、比天亮 **27**，
## 那就是现在图上那道比天还白的硬边。而 ×0.70 落在 95 / 105 / 115：
## 每层都**比自己那一段天暗**（−85 / −62 / −34），三层之间还各差 10 个单位。
##
## 系数是量出来的（`tools/probe_sky_grass.gd --cal`，**每一层单独**放出来量
## 它自己那一圈，逐列自定位轮廓顶）：渲出来的亮度对 tint 的响应在 AGX
## 高光那一头极不平——反照率砍掉四成渲出来只掉 8%——所以**三层得各扫各的**，
## 拿远层的系数去推近层，两层会并到同一个亮度上。
## 而把天整张藏掉之后**一个像素的硬边都找不到**：那道缝从头到尾是山自己的
## 轮廓，不是天穹的（第一版把 `sky_curve` 从 0.15 扫到 10，缝只从 88 掉到 36）。
##
## ## 然后是**层与层的间距**（2026-10-04，`--spread` 量出来的）
##
## 上一版压完之后三层的填色只剩 0.155 / 0.181 / 0.204 —— 相邻两层差 13%，
## 渲出来在黄昏那一档**并成同一块**：天到第一层是 -81 的巨阶，
## 再往下只剩 **-3.4 / -3.8**，而判据要的是每条边 ≥ 8（`lookdev_journey`
## 第 12f 节）。那一档报「黄昏 2/5 列」，正午报 4/5——**两条都压在门槛上**。
##
## **抬乘数救不了它**：`DayCycle.DUSK_RIDGE_TINT` 是三层同乘的，
## 改不了彼此的比值。实测乘数 1.25 把第一条边从 24 推到 36 而**中间那条
## 只从 9.0 动到 9.5**；到 1.8 远层比天还亮 +8（判据当场红）而列数掉回 2/5。
## 于是分工是写死的：**层与层的比值归这里，绝对位置归 `DUSK_RIDGE_TINT`**。
##
## ## 这一段的前提后来被推翻了两次，两次的教训都留着
##
## ①「不抬远层」是**照着一个假的天量出来的结论**。当时量到「正午远层比天亮
##    +20」，于是判成抬远层会先在正午破掉「最外层山不比天亮」。可那个 +20
##    是 `lookdev_journey` 的一张 t≈0.167 的天给的——里程计在拍正午那张之前
##    就推过了门槛，转场已经走了 1.5/9 秒。改正之后真正的正午读到的是
##    **−10**（远层比天暗），方向正好反过来。教训见下面那句"一把尺子量两次"。
## ②「往下压近层」压不动：`verify_far_ridge.gd` 有 `near_lum >= 0.14` 的下限，
##    而近层已经正好卡在 0.14102。抬中层去配比值又会破掉严格的近<中<远。
##
## 现在这三档是**正午那一档扫出来的**（`tools/probe_sky_grass.gd --spread-noon`）：
## 正午的乘数是白的（`t=0` → `Color.WHITE.lerp(DUSK_RIDGE_TINT, 0)` = 白），
## 所以正午的层间距**只能由 `LAYERS` 自己扛**，黄昏那份抬乘数一点忙都帮不上。
## 基线实测三层与天的差 **−60 / −32 / −10**，逐列凑齐三条边的列数 3/5——
## 中间那一档到远层只有 22 个单位，是三段里最薄的一段。
## 抬远层能立刻换成 5/5（×1.15/×1.35 实测 42.6/31.0/24.0），**代价是远层
## 比天亮 +25**，直接破掉 12f。所以没抬。
##
## **这三行必须写满精度，不许四舍五入到三位小数**：那把尺子（`RIDGE_EDGE_MIN`
## 逐通道 8、`lookdev_journey` 第 12f 节）是**离散阈值探测器**，同样一档配置
## 在同一个进程里重复五次数值逐位相同，而把三层色各改 **0.2%** 就足以让列数
## 从 5/5 翻成 4/5、台阶挪掉 10 个单位左右。所以「同一进程里可复现」不等于
## 「换个配置还稳」——定下来的值要按**余量**选，不是按「这次过了」选。
const LAYERS := [
	{"r": 800.0, "lo": 60.0, "hi": 130.0, "col": Color(0.10092, 0.15433, 0.12712), "seed": 3.0},
	{"r": 1350.0, "lo": 130.0, "hi": 260.0, "col": Color(0.132318, 0.179514, 0.201069), "seed": 11.0},
	{"r": 1900.0, "lo": 220.0, "hi": 400.0, "col": Color(0.156992, 0.194064, 0.231128), "seed": 23.0},
]

## 峰形的频率比全取无理数，否则各倍频会周期对齐、每 2π 重复一次同样的轮廓
const _FREQS := [1.0, 2.7183, 4.4814, 7.3891, 12.426, 20.086]
const _AMPS := [0.52, 0.24, 0.13, 0.07, 0.04, 0.02]


var _mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	for layer in LAYERS:
		add_child(_build_layer(layer))


## 整体乘一层色。黄昏用（DayCycle 调）。
##
## 山线是 SHADING_MODE_UNSHADED，它**不吃场景光照** —— 空气透视烘在顶点色里，
## 这么调才保得住 LAYERS 那套递淡。可代价是环境一换色，三层山就顶着自己那套
## 青灰色站在一片橙里，地平线整个打架。`vertex_color_use_as_albedo` 打开时
## `albedo_color` 是个乘数，所以传白就是原样。
func set_tint(c: Color) -> void:
	for m in _mats:
		m.albedo_color = c


## 高度剖面：几个不同频率正弦叠加，再过一道 ridged 变换把圆钝的波峰掐成尖峰。
## 返回 0..1。
static func _profile(theta: float, seed: float) -> float:
	var s := 0.0
	for i in range(_FREQS.size()):
		s += sin(theta * _FREQS[i] + seed * (i + 1) * 1.7) * _AMPS[i]
	# 1 - |s| 把过零处的凹谷变尖、峰顶变平——这正是山脊而不是沙丘的剖面
	var ridged := 1.0 - absf(s) * 1.35
	return clampf(ridged, 0.0, 1.0)


func _build_layer(layer: Dictionary) -> MeshInstance3D:
	var r: float = layer["r"]
	var lo: float = layer["lo"]
	var hi: float = layer["hi"]
	var col: Color = layer["col"]
	var seed_off: float = layer["seed"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 底色比山脊色深一档，山体才有体积而不是一条平涂的色带
	var foot := col.darkened(0.30)
	for i in range(SEGMENTS):
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		var h0 := lo + (hi - lo) * _profile(a0, seed_off)
		var h1 := lo + (hi - lo) * _profile(a1, seed_off)
		var top0 := Vector3(cos(a0) * r, h0, sin(a0) * r)
		var top1 := Vector3(cos(a1) * r, h1, sin(a1) * r)
		var bot0 := Vector3(cos(a0) * r, BASE_Y, sin(a0) * r)
		var bot1 := Vector3(cos(a1) * r, BASE_Y, sin(a1) * r)
		# 站在环内看到的全是内侧面，绕序要反着来
		_tri(st, top0, bot0, top1, col, foot, col)
		_tri(st, top1, bot0, bot1, col, foot, foot)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	# 不参与光照：山在这个距离上本来就只被天空照着，再算一次方向光只会
	# 把它染成近处草地的绿色。空气透视交给顶点色。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	# 关掉场景雾。LAYERS 里的颜色是照着**最终观感**调出来的，空气透视已经烘在
	# 顶点色里；再让 fog_density=0.0003 叠一遍就是同一份雾算两次——1900m 那层
	# 透射率只剩 0.566，调好的颜色又被洗掉四成，三层因此全线偏白、没有纵深。
	# 改之前看着像"AGX 把中间调提亮了"，根角却在雾被算了两次。
	#
	# 代价：山脚会和被雾洗过的地形之间出现一道接缝。foot 色（col.darkened(0.30)）
	# 收得够暗就盖得住，改完必须跑 lookdev_horizon.gd 看图确认，不能靠数字判断。
	mat.disable_fog = true
	mi.material_override = mat
	_mats.append(mat)
	return mi


func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3,
		c0: Color, c1: Color, c2: Color) -> void:
	st.set_color(c0)
	st.add_vertex(p0)
	st.set_color(c1)
	st.add_vertex(p1)
	st.set_color(c2)
	st.add_vertex(p2)
