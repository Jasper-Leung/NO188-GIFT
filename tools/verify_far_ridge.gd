extends SceneTree
## FarRidge 回归 —— 山脊材质不许被场景雾二次洗色。
##
## 只测材质标志位，测不了颜色。顶点色那套"反着调"的配色只有带窗口的
## lookdev_horizon.gd 能判（AGX 会提亮去饱和，数字读不出观感），
## 这里的职责是守住那行 disable_fog 不被谁顺手删掉。
##
## 这条为什么值得守：LAYERS 的颜色是照着最终观感调的、空气透视已经烘在顶点色里，
## 场景雾再叠一遍就是同一份雾算两次。1900m 那层透射率只剩 0.566，三层因此全线
## 偏白、没有纵深——实测 near 层和 mid 层几乎同一个明度，远景直接塌成一条带子。
##
## 用法： godot --headless --path . --script tools/verify_far_ridge.gd

var _fails: Array = []
var _oks := 0


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


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 远景山线回归 ===")

	# --script 模式下 analyzer 认不出 class_name + autoload 一起来的推断，
	# 整棵场景树现搭现查，别用类型注解。
	var ridge = load("res://scripts/FarRidge.gd").new()

	var mats: Array = []
	# 直接 add_child 就会触发 _ready，但 _ready 里的 add_child 也要等一帧才落定。
	root.add_child(ridge)
	await process_frame

	var kids: Array = ridge.get_children()
	_eq("建出三层山脊", kids.size(), 3)
	_ck("山脊在场景树里", ridge.get_parent() != null)

	for i in range(kids.size()):
		var mi: Node = kids[i]
		_ck("第 %d 层是 MeshInstance3D" % (i + 1), mi is MeshInstance3D)
		if not (mi is MeshInstance3D):
			continue
		var mat = mi.material_override
		_ck("第 %d 层有材质" % (i + 1), mat != null)
		if mat == null:
			continue
		mats.append(mat)
		_ck("第 %d 层关了雾" % (i + 1), bool(mat.disable_fog),
				"disable_fog=%s" % str(mat.disable_fog))
		_eq("第 %d 层不参与光照" % (i + 1), int(mat.shading_mode),
				int(BaseMaterial3D.SHADING_MODE_UNSHADED))
		_ck("第 %d 层用顶点色" % (i + 1), bool(mat.vertex_color_use_as_albedo))
		_ck("第 %d 层双面可见" % (i + 1),
				int(mat.cull_mode) == int(BaseMaterial3D.CULL_DISABLED))

	# 三层半径必须都大于地形半对角线（800/2·√2 ≈ 566m），否则山会插进地形里。
	var radii: Array = []
	for layer in FarRidge.LAYERS:
		radii.append(float(layer["r"]))
	var rmin: float = radii.min()
	_ck("最近一层也在地形之外", rmin > 566.0, "r=%f" % rmin)

	# 三层颜色必须按距离递淡（近深远浅），否则关了雾之后纵深就没了。
	for i in range(1, radii.size()):
		var near: Color = FarRidge.LAYERS[i - 1]["col"]
		var far: Color = FarRidge.LAYERS[i]["col"]
		_ck("第 %d 层比第 %d 层淡" % [i + 1, i], far.get_luminance() > near.get_luminance(),
				"near=%.3f far=%.3f" % [near.get_luminance(), far.get_luminance()])

	ridge.queue_free()
	await process_frame

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)
