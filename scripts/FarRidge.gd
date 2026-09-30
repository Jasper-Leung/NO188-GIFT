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
const LAYERS := [
	{"r": 800.0, "lo": 60.0, "hi": 130.0, "col": Color(0.13, 0.20, 0.17), "seed": 3.0},
	{"r": 1350.0, "lo": 130.0, "hi": 260.0, "col": Color(0.30, 0.42, 0.46), "seed": 11.0},
	{"r": 1900.0, "lo": 220.0, "hi": 400.0, "col": Color(0.52, 0.64, 0.74), "seed": 23.0},
]

## 峰形的频率比全取无理数，否则各倍频会周期对齐、每 2π 重复一次同样的轮廓
const _FREQS := [1.0, 2.7183, 4.4814, 7.3891, 12.426, 20.086]
const _AMPS := [0.52, 0.24, 0.13, 0.07, 0.04, 0.02]


func _ready() -> void:
	for layer in LAYERS:
		add_child(_build_layer(layer))


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
	return mi


func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3,
		c0: Color, c1: Color, c2: Color) -> void:
	st.set_color(c0)
	st.add_vertex(p0)
	st.set_color(c1)
	st.add_vertex(p1)
	st.set_color(c2)
	st.add_vertex(p2)
