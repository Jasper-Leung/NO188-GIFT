extends SceneTree
## verify_terrain_shader.gd — 地形材质的四件事不能被改坏
##
## 1. 地面挂的是 terrain_grass.gdshader（ShaderMaterial），不是 StandardMaterial3D。
## 2. shader 里绝对不能出现 cull_disabled / cull_front。TerrainBuilder 建三角时
##    刻意翻转了缠绕顺序使 cross.y<0 为正面，加上剔除就会把整片地面剔没。
## 3. 顶点色必须还在，而且值域是 0.82~1.0。StandardMaterial3D 上的
##    vertex_color_use_as_albedo 换到 ShaderMaterial 后静默失效，shader 里
##    必须显式 col *= COLOR.rgb；忘了的现场是地面整体**变亮**。
## 4. 顶点色必须跨运行确定。早先这里用的是未播种的全局 randf()，每次跑
##    0.82~1.0 的明暗都不一样。
##
## 附带确认地形高度本身没被碰（这次只改了颜色和材质，不该动 _fbm）。
##
## 用法： godot --headless --path . --script tools/verify_terrain_shader.gd

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 地形草地质感着色器回归 ===")
	var TB = load("res://scripts/TerrainBuilder.gd")

	var a = TB.new()
	root.add_child(a)
	await process_frame
	var b = TB.new()
	root.add_child(b)
	await process_frame

	var mi_a: MeshInstance3D = a.get_child(0)
	_check(mi_a is MeshInstance3D, "TerrainBuilder 建出了 MeshInstance3D")
	if not (mi_a is MeshInstance3D):
		_report()
		return

	# --- 1. 材质类型 ---
	var mat = mi_a.material_override
	_check(mat is ShaderMaterial,
		"地面用的是 ShaderMaterial（实际 %s）" % mat.get_class())
	if not (mat is ShaderMaterial):
		_report()
		return

	var code: String = mat.shader.code
	_check(mat.shader.resource_path == TB.SHADER_PATH,
		"shader 路径 == TerrainBuilder.SHADER_PATH（%s）" % mat.shader.resource_path)

	# --- 2. 剔除模式 ---
	# 只看真正的 render_mode 语句行，不能对整段 code 做子串匹配：
	# shader 头注释里就写着"绝不能加 cull_disabled"，全串匹配会自我误报。
	var bad_cull := ""
	for line in code.split("\n"):
		var s: String = (line as String).strip_edges()
		if not s.begins_with("render_mode"):
			continue
		for pragma in ["cull_disabled", "cull_front", "cull_back"]:
			if s.contains(pragma):
				bad_cull = pragma
				break
		if bad_cull != "":
			break
	_check(bad_cull == "",
		"shader 里没有任何 render_mode 剔除pragma（地形靠 cross.y<0 为正面）"
		+ ("" if bad_cull == "" else " —— 出现了 %s" % bad_cull))

	# --- 3. 顶点色 ---
	var arrays: Array = mi_a.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(colors.size() == arrays[Mesh.ARRAY_VERTEX].size(),
		"顶点色数量 == 顶点数（%d / %d）" % [
			colors.size(), arrays[Mesh.ARRAY_VERTEX].size()])
	var lo := 2.0
	var hi := -1.0
	for c in colors:
		lo = minf(lo, c.r)
		hi = maxf(hi, c.r)
	_check(lo >= 0.8199 and hi <= 1.0001,
		"顶点明暗值域在 0.82~1.0（实测 %.4f~%.4f）" % [lo, hi])
	_check(code.contains("COLOR.rgb"),
		"shader 里显式读了 COLOR（替掉 StandardMaterial3D 的 vertex_color_use_as_albedo）")

	# --- 4. 确定性 ---
	var colors_b: PackedColorArray = b.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var same := colors_b.size() == colors.size()
	if same:
		for i in range(colors.size()):
			if absf(colors[i].r - colors_b[i].r) > 1e-6:
				same = false
				print("    顶点 %d 不一致: %.6f vs %.6f" % [i, colors[i].r, colors_b[i].r])
				break
	_check(same, "两个独立实例的顶点色逐点一致（不再用未播种的 randf()）")

	# --- 5. 材质参数接线 ---
	var gc = mat.get_shader_parameter("ground_color")
	_check(gc is Color and (gc as Color).is_equal_approx(TB.BASE_COLOR),
		"ground_color 已喂入 TerrainBuilder.BASE_COLOR（%s）" % str(gc))

	# --- 6. 高度路径没被碰 ---
	var probe := [Vector2(0, 0), Vector2(120, -80), Vector2(-300, 250)]
	var h_a := []
	var h_b := []
	for p in probe:
		h_a.append(a.get_height_at(p.x, p.y))
		h_b.append(b.get_height_at(p.x, p.y))
	var h_same := true
	for i in range(probe.size()):
		if absf(h_a[i] - h_b[i]) > 1e-9:
			h_same = false
		print("    get_height_at(%s) = %.6f" % [str(probe[i]), h_a[i]])
	_check(h_same, "get_height_at() 在两个实例上一致（高度路径未被本次改动影响）")

	# --- 7. 阴影开关保持关闭 ---
	_check(mi_a.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"地形仍不投射阴影（cast_shadow = OFF）")

	_report()


func _report() -> void:
	print("\n[verify_terrain_shader] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
