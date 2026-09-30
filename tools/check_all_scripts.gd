extends SceneTree
## check_all_scripts.gd — 全项目 .gd 编译体检
## 逐个 load() 每个脚本：解析/编译失败时 Godot 会打印具体 SCRIPT ERROR，
## 这里在加载前先打路径，便于把错误归因到文件。
## 用法： godot --headless --path . --script tools/check_all_scripts.gd

const ROOTS := ["res://scripts", "res://scenes", "res://tools"]


func _initialize() -> void:
	_run.call_deferred()


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if name != "." and name != "..":
				_collect(dir_path.path_join(name), out)
		elif name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
		name = d.get_next()
	d.list_dir_end()


func _run() -> void:
	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	files.sort()
	print("=== 扫描到 %d 个 .gd 文件 ===" % files.size())

	var bad: Array[String] = []
	var n := 0
	for f in files:
		print("[load] ", f)
		var s: Variant = load(f)
		n += 1
		# 光判 null 会漏：解析失败的脚本 load() 照样返回 GDScript 对象，
		# 唯一可靠的区别是 can_instantiate() == false。HUD3D.gd 曾经写错过
		# powf()（Godot 4 没有这个函数），旧版本这里仍报 PASS。
		var ok := s != null
		if ok and s is GDScript:
			ok = (s as GDScript).can_instantiate()
		if not ok:
			bad.append(f)

	print("\n=== 结果：成功 %d / 失败 %d ===" % [n - bad.size(), bad.size()])
	for f in bad:
		print("  [FAIL] ", f)
	print("[check_all_scripts] %s" % ("PASS" if bad.is_empty() else "FAIL"))
	quit(0 if bad.is_empty() else 1)
