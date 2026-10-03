extends SceneTree
## verify_layout_editor.gd — `res://layout.json` 的读写 + 编辑模式检测
##
## ---- 第一版这条回归一个断言都没有 ----
## 它从头到尾只有 `print`，最后无条件打一行 `=== ALL OK ===` 然后 `quit(0)`。
## 每一个数都得人眼去比，而人眼比不过它——它在自检表里于是既不算通过也不算失败，
## 只是安静地跑完了。现在每一条都变成 `[OK]` / `[FAIL]`。
##
## ---- 它还会删掉你编辑模式的成果 ----
## 原版直接往 `res://layout.json` 写测试数据、最后 `LayoutData.clear()`。
## 那个文件是**编辑模式 Ctrl+S 存出来的产物**，跑一次回归就没了。
## 现在开头把原文件备份到内存、结尾原样写回去；本来没有就还它没有。

var _fails := 0


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _init() -> void:
	print("=== verify_layout_editor ===")

	# ---- 0. 备份已有的 layout.json，跑完还回去 ----
	var had_layout := FileAccess.file_exists("res://layout.json")
	var backup := ""
	if had_layout:
		var f := FileAccess.open("res://layout.json", FileAccess.READ)
		backup = f.get_as_text()
		f.close()
		print("（发现已有 layout.json，已备份，跑完原样还回）")

	# ---- 1. 编辑模式的三种开关 ----
	# 命令行 / 环境变量 / 标记文件。CLAUDE.md 写的是"任一"，所以三条都得认。
	var is_editor := false
	for arg in OS.get_cmdline_args():
		if arg == "--gift-editor":
			is_editor = true
	print("cmdline --gift-editor detected: ", is_editor)
	print("env GIFT188_EDITOR: ", OS.get_environment("GIFT188_EDITOR"))
	print("res://.editor_mode exists: ", FileAccess.file_exists("res://.editor_mode"))
	_ck("命令行 --gift-editor 能被认出来（不是靠环境变量兜底）", is_editor)

	# ---- 2. 写入 / 读回 ----
	var sample_stations := [
		{"idx": 0, "pos": Vector3(1.0, 2.0, 3.0), "rot_y_deg": 30.0},
		{"idx": 5, "pos": Vector3(-2.0, 0.5, 4.0), "rot_y_deg": 90.0},
	]
	var sample_plants := [
		{"type": "bush", "pos": Vector3(10.0, 1.0, -5.0), "rot_y_deg": 45.0, "scale": 1.5, "seg_idx": 100},
		{"type": "tree", "pos": Vector3(-3.0, 1.5, 7.0), "rot_y_deg": 0.0, "scale": 2.0, "seg_idx": 200},
	]
	var save_err := LayoutData.save(sample_stations, sample_plants)
	print("save err: ", save_err, " (0=OK)")
	_ck("save() 成功", save_err == 0, "错误码 %d" % save_err)
	_ck("save() 之后文件真的在", LayoutData.exists())

	var loaded := LayoutData.load()
	var l_st: Array = loaded.get("stations", [])
	var l_pl: Array = loaded.get("plants", [])
	print("loaded version: ", loaded.get("version", "MISSING"))
	_ck("读回带版本号（没有版本号的旧档不该被当成当前格式）",
			loaded.has("version"), "读到 %s" % str(loaded.get("version", "MISSING")))
	_ck("驿站覆盖原样往返（2 条）", l_st.size() == 2, "读到 %d 条" % l_st.size())
	_ck("植物覆盖原样往返（2 条）", l_pl.size() == 2, "读到 %d 条" % l_pl.size())

	# 位置必须逐分量相等：编辑模式存的就是位置，漂了 0.01m 玩家就看不出东西移没移。
	#
	# 注意 JSON 读回来的是**数组**而不是 Vector3：写 `var p0: Vector3 = l_st[0]["pos"]`
	# 会在运行时报 "Trying to assign value of type Array to a variable of type Vector3"，
	# 把整个脚本掐死——前六条断言照样打出来，看着像只差一条，实际后面六条一条没跑。
	# 第一版就是这么写的，而 `check_all.sh` 只看 `[FAIL]` 会把它判成 FAIL 而不是没跑成。
	if l_st.size() == 2 and l_st[0]["pos"] is Array:
		var p0: Array = l_st[0]["pos"]
		_ck("位置逐分量往返（idx 0）",
				absf(float(p0[0]) - 1.0) < 1e-4
				and absf(float(p0[1]) - 2.0) < 1e-4
				and absf(float(p0[2]) - 3.0) < 1e-4,
				"读到 %s" % str(p0))
		_ck("旋转角往返（idx 0 = 30°）", absf(float(l_st[0]["rot_y_deg"]) - 30.0) < 1e-4,
				"读到 %s" % str(l_st[0]["rot_y_deg"]))

	# ---- 3. 查询接口 ----
	var ov := LayoutData.get_station_override(loaded, 0)
	print("station idx=0 override: ", ov)
	_ck("查得到 idx 0 的覆盖", not ov.is_empty())
	var ov_missing := LayoutData.get_station_override(loaded, 999)
	print("station idx=999 override (should be empty): ", ov_missing)
	_ck("查不到的下标返回空而不是崩（16 站之外的输入很常见）", ov_missing.is_empty())

	var by_type := LayoutData.get_plant_overrides_by_type(loaded)
	var n_bush: int = (by_type.get("bush", []) as Array).size()
	var n_tree: int = (by_type.get("tree", []) as Array).size()
	print("plant overrides keys: ", by_type.keys())
	_ck("植物按类型分组（bush 1 / tree 1）", n_bush == 1 and n_tree == 1,
			"bush %d / tree %d" % [n_bush, n_tree])

	# ---- 4. 容错：损坏的 JSON ----
	# 这条路径必须返回空字典而不是抛异常——玩家手动编辑 layout.json 写坏一个
	# 逗号是常事，为它崩掉整个游戏是最差的反应。
	var bad_file := FileAccess.open("res://layout.json", FileAccess.WRITE)
	bad_file.store_string("{not valid json")
	bad_file.close()
	var bad_load := LayoutData.load()
	print("bad JSON load returns {}: ", bad_load.is_empty())
	_ck("损坏的 JSON 读成空字典（不抛异常）", bad_load.is_empty())

	# ---- 5. clear ----
	LayoutData.clear()
	_ck("clear() 之后文件真的没了", not LayoutData.exists())

	# ---- 6. 还回原来的 layout.json ----
	if had_layout:
		var w := FileAccess.open("res://layout.json", FileAccess.WRITE)
		w.store_string(backup)
		w.close()
		print("（已把原来的 layout.json 还回去）")

	print("[verify_layout_editor] " + ("PASS" if _fails == 0 else "FAIL") + "  (失败 %d)" % _fails)
	quit(0 if _fails == 0 else 1)