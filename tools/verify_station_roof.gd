extends SceneTree
## verify_station_roof.gd — 驿站屋顶色回归
##
## 要拦的是两件事：
##   1. 屋顶还是青瓦。全场是暖的，只有屋顶那块冷灰在跳，04_ride 定妆照上一眼就看见。
##   2. tint 顺手改了不该改的东西。13 个模型每个材质都是资产（朱红门、木色墙、纸窗），
##      乘色压平就没了，所以只认 "_roof" / "_roof_2" 后缀，且必须比对改前改后。
##
## 这里用 World3D 自己那对常量和 _tint_station_roofs()，不重演一遍——重演的话
## 这里绿了也证明不了游戏里那一屏是暖的。
##
## 用法： godot --headless --path . --script tools/verify_station_roof.gd

## 手工模型的 7 个文件名。贴图模型 (station_0..4) 不在表里：它们整个模型只有一个
## 烘了 basecolor 的材质，改不了单片屋顶，硬改就是给照片乘色。
const HAND_MODELS := ["驿楼", "茶寮", "岭台", "神苑", "凉亭", "廊", "亭灯", "琴台"]

## 屋顶必须"暖"：红 ≥ 蓝。差得越多越暖，平了算中性也可以，冷的一律不算。
## 比的是线性值不是 sRGB——sRGB 那道 gamma 会把 0.175/0.115 的差从 0.06 压到
## 0.014，用 sRGB 定门槛要么放过头要么一片都过不了。0.004 大约对应 sRGB 差 0.02，
## 够躲开浮点舍入，又小到"只是有点冷"的色照样被拦住。
const WARM_MIN := 0.004

## 屋顶必须比墙暗，但不能暗成一个洞。
##
## 屋顶是压住房子的那一片，墙上还有纸窗和木柱。渲到背光面纯黑的时候，
## 整栋楼有一半没了轮廓——比原来的冷灰更糟。这条拦的是"改色改过头"：
## 用错色彩空间（该 linear_to_srgb 却写成 srgb_to_linear）会让屋顶比墙暗 30 倍，
## 数字还是"暖的"，只有比值能看出来。
const ROOF_VS_STONE := [0.30, 0.90]

var _fails := 0


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://lookdev_station_roof")
	_run.call_deferred()


func _run() -> void:
	var world = load("res://scripts/World3D.gd").new()

	print("=== 驿站屋顶暖中性回归 ===")
	for name in HAND_MODELS:
		var path := "res://assets/models/station_%s.glb" % name
		var scene: PackedScene = load(path)
		if scene == null:
			_ck("%s 能加载" % name, false, path)
			continue

		var model = scene.instantiate()
		# 先拍下改之前的全部 override（此时全是 null），和原材质色一起存着
		var meshes_before := []
		for c in model.find_children("*", "MeshInstance3D", true, false):
			meshes_before.append(c)

		world._tint_station_roofs(model)

		var roof_hits := 0
		var stone_albedo := -1.0
		for c in meshes_before:
			var mi := c as MeshInstance3D
			for s in range(mi.mesh.get_surface_count()):
				var orig := mi.mesh.surface_get_material(s)
				if orig == null:
					continue
				var is_roof: bool = orig.resource_name.ends_with("_roof") \
						or orig.resource_name.ends_with("_roof_2")
				var dup := mi.get_surface_override_material(s) as StandardMaterial3D

				if not is_roof:
					# 非屋顶必须原封不动：既不能被 override，也不能已经被前一个模型污染
					_ck("%s/%s 保持原材质" % [name, orig.resource_name], dup == null,
							"被换成了 %s" % (dup.resource_name if dup else "?"))
					# stone 是同模型里最接近的中性面，拿它当"墙"的基准
					if orig.resource_name.ends_with("_stone"):
						stone_albedo = orig.albedo_color.get_luminance()
					continue

				roof_hits += 1
				if dup == null:
					_ck("%s/%s 有 override 材质" % [name, orig.resource_name], false)
					continue
				# duplicate 之后不能和原材质是同一个对象，否则改一个连带改一片
				_ck("%s/%s 材质已 duplicate" % [name, orig.resource_name], dup != orig)
				var lin := dup.albedo_color
				var warm := lin.r - lin.b
				_ck("%s/%s 屋顶是暖的" % [name, orig.resource_name], warm >= WARM_MIN,
						"linear rgb=(%.3f,%.3f,%.3f) 红-蓝=%+.3f" % [lin.r, lin.g, lin.b, warm])
				# 原色是青瓦（蓝最高），改完必须真的是换了而不是碰巧过检
				_ck("%s/%s 屋顶确实改了" % [name, orig.resource_name],
						not is_equal_approx(lin.r, orig.albedo_color.r),
						"改前后都是 %.3f" % lin.r)

		_ck("%s 至少换到一片屋顶" % name, roof_hits > 0, "一个都没匹配上")

		# 屋顶 vs 墙：太亮就跟墙糊平，太暗就成洞。
		# 亮的那片取刚换过的 roof 材质（不是 roof_2——那个本来就是亮档）
		var roof_lum := -1.0
		for c in meshes_before:
			var mi4 := c as MeshInstance3D
			for s in range(mi4.mesh.get_surface_count()):
				var om := mi4.mesh.surface_get_material(s)
				if om == null or not om.resource_name.ends_with("_roof"):
					continue
				var ov := mi4.get_surface_override_material(s) as StandardMaterial3D
				if ov != null:
					roof_lum = ov.albedo_color.get_luminance()
		_ck("%s 有 stone 可当墙的基准" % name, stone_albedo > 0.0)
		var ratio := roof_lum / maxf(stone_albedo, 0.0001)
		_ck("%s 屋顶比墙暗但不虚" % name,
				ratio >= ROOF_VS_STONE[0] and ratio <= ROOF_VS_STONE[1],
				"屋顶/墙 = %.2f（允许 %.2f~%.2f）" % [ratio, ROOF_VS_STONE[0], ROOF_VS_STONE[1]])

		# 共享资源必须没被就地改写：原材质现在还是青瓦才说明改的是副本
		for c in meshes_before:
			var mi2 := c as MeshInstance3D
			for s in range(mi2.mesh.get_surface_count()):
				var o := mi2.mesh.surface_get_material(s)
				if o != null and o.resource_name.ends_with("_roof"):
					_ck("%s/%s 导入缓存没被写脏" % [name, o.resource_name],
							o.albedo_color.b >= o.albedo_color.r,
							"原材质已变成 rgb=(%.3f,%.3f,%.3f)" % [
							o.albedo_color.r, o.albedo_color.g, o.albedo_color.b])
					break
			break

		# 走 queue_free 而不是 free()：带 surface override 的 MeshInstance3D 直接 free
		# 会在 dummy renderer 上吐 "Parameter material is null"（渲染后端拆除时的
		# 空指针），那行红字会被读成失败，其实和这个改动无关。
		model.queue_free()
		await process_frame

	# 贴图模型不能被误伤：5 个模型一个材质，名字是 tripo_mat_*，不该匹配上任何后缀
	for i in range(5):
		var p := "res://assets/models/station_%d.glb" % i
		var sc: PackedScene = load(p)
		if sc == null:
			continue
		var m2 = sc.instantiate()
		world._tint_station_roofs(m2)
		var touched := 0
		for c in m2.find_children("*", "MeshInstance3D", true, false):
			var mi3 := c as MeshInstance3D
			for s in range(mi3.mesh.get_surface_count()):
				if mi3.get_surface_override_material(s) != null:
					touched += 1
		_ck("贴图模型 station_%d 没被 tint" % i, touched == 0, "换了 %d 个 surface" % touched)
		m2.queue_free()
		await process_frame
	# world 最后一个释放：上面两个循环还要调它的 _tint_station_roofs()
	world.queue_free()
	await process_frame

	print("\n[verify_station_roof] %s  (失败 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
