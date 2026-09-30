extends SceneTree
## 无头验证:layout.json 读写 + GameManager.is_editor_mode() 检测
## 跑法:"D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe" --headless --path . --script tools/verify_layout_editor.gd --quit-after 5

func _init() -> void:
	print("=== verify_layout_editor ===")
	# 1. 编辑模式检测:命令行 --gift-editor 应识别
	#    (此脚本由 --script 触发,不进入游戏主场景,但仍能调 GameManager 类)
	var is_editor := false
	for arg in OS.get_cmdline_args():
		if arg == "--gift-editor":
			is_editor = true
	print("cmdline --gift-editor detected: ", is_editor)
	# env var
	print("env GIFT188_EDITOR: ", OS.get_environment("GIFT188_EDITOR"))
	# file flag
	print("res://.editor_mode exists: ", FileAccess.file_exists("res://.editor_mode"))

	# 2. LayoutData 写入/读回
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
	print("file exists after save: ", LayoutData.exists())

	var loaded := LayoutData.load()
	print("loaded version: ", loaded.get("version", "MISSING"))
	print("loaded stations size: ", (loaded.get("stations", []) as Array).size())
	print("loaded plants size: ", (loaded.get("plants", []) as Array).size())

	var station_override := LayoutData.get_station_override(loaded, 0)
	print("station idx=0 override: ", station_override)
	var station_override_missing := LayoutData.get_station_override(loaded, 999)
	print("station idx=999 override (should be empty): ", station_override_missing)

	var plant_overrides_by_type := LayoutData.get_plant_overrides_by_type(loaded)
	print("plant overrides keys: ", plant_overrides_by_type.keys())
	print("bush count: ", (plant_overrides_by_type.get("bush", []) as Array).size())
	print("tree count: ", (plant_overrides_by_type.get("tree", []) as Array).size())

	# 3. 容错:损坏的 JSON
	var bad_file := FileAccess.open("res://layout.json", FileAccess.WRITE)
	bad_file.store_string("{not valid json")
	bad_file.close()
	var bad_load := LayoutData.load()
	print("bad JSON load returns {}: ", bad_load.is_empty())

	# 4. clear
	LayoutData.clear()
	print("after clear, exists: ", LayoutData.exists())

	print("=== ALL OK ===")
	quit()