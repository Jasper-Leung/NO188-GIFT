extends SceneTree
## verify_provenance.gd — 资产来源清单不许和仓库对不上
##
## 这份清单（`PROVENANCE.md`）一旦没人对拍，它就会**自己变成第二个事实来源**：
## 半年后新增十个模型，清单上还是旧的，而每一次商用发行都拿它当依据。
## 那是 CLAUDE.md 里「手抄的常量副本会自己长出一套预算曲线」的同一个家族——
## 只不过这次被抄的不是一张常量表，而是**一份决定能不能收钱的凭据**。
##
## 所以这份脚本只做一件笨事：把 `assets/` 下**每一个**受管文件和两张文档对拍。
##
## 用法： godot --headless --path . --script tools/verify_provenance.gd
##
## 故意不做的事：**不判断某项的许可条款对不对**。它读不了 Tripo 的服务条款，
## 也追不到 Sketchfab 上那个 `10489` 是谁。它只守「清单与仓库同步」和
## 「内部清单与对外署名文件同步」——这两件是机器能判的，剩下的是人的活。

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


## `assets/` 下**受管**的文件 = 二进制资产本身。
## `.import` / `.uid` 是引擎和编辑器生成的边车文件，不登记（登记了就是噪音，
## 而噪音是让人不再看这份清单的理由）；`__pycache__` 同理。
func _managed_assets() -> Array[String]:
	var out: Array[String] = []
	_walk("res://assets", out)
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if name != "__pycache__":
				_walk(full, out)
		elif not (name.ends_with(".import") or name.ends_with(".uid")):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


## 登记表那一节里的每一行第一格（`` | `路径` | ``）里的路径。
## 只认那一节——正文散文里也会提到文件名（"占着 /tmp 那个 xxx.jpg"），
## 那些不是登记，把它们算进来会让「多出来的那几行」这条判据名不副实。
func _registry_paths(prov: String) -> Array[String]:
	var out: Array[String] = []
	var inside := false
	for raw in prov.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("## "):
			inside = line.contains("全量文件登记表")
			continue
		if not inside or not line.begins_with("| `"):
			continue
		var tick := line.find("`", 3)
		if tick > 0:
			out.append(line.substr(3, tick - 3))
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _initialize() -> void:
	print("=== 资产来源清单回归 ===")
	_run.call_deferred()


func _run() -> void:
	var prov := _read("res://PROVENANCE.md")
	var cred := _read("res://CREDITS.md")
	var lic := _read("res://LICENSE")

	_check(not prov.is_empty(), "PROVENANCE.md 存在且非空")
	_check(not cred.is_empty(), "CREDITS.md 存在且非空")
	if prov.is_empty() or cred.is_empty():
		print("\n================ 汇总 ================")
		print("[verify_provenance] FAIL  (失败项 %d)" % _failures)
		quit(1)
		return

	# —— 第一组：`assets/` 清单同步 ——
	# **正对照先摆**：走目录这个函数本身可能一个文件都列不出来（路径写错、
	# `DirAccess` 在导出后不可用），那时候下面每一条"已登记"都会绿。
	var files := _managed_assets()
	_check(files.size() >= 15,
			"走目录真的列出了东西（实测 %d 个，否则后面全是恒绿）" % files.size())

	var missing: Array[String] = []
	for f in files:
		var rel := f.trim_prefix("res://assets/")
		if not prov.contains("`%s`" % rel):
			missing.append(rel)
	_check(missing.is_empty(),
			"assets/ 下每个文件都在 PROVENANCE.md 里按相对路径登记过（漏了 %d 个：%s）"
			% [missing.size(), ", ".join(missing.slice(0, 6))])

	# 反向：登记表上写着一个**已经删掉**的文件，也是一份在骗人的清单——
	# 它会让下一个人去找一份不存在的授权凭证。
	# 所以这一组只认**登记表那一节**（§三），把两边的路径当集合对拍：
	# 既不许少（上面那条），也不许多（这一条）。
	var rows := _registry_paths(prov)
	var ghosts: Array[String] = []
	for r in rows:
		if not FileAccess.file_exists("res://assets/" + r):
			ghosts.append(r)
	_check(ghosts.is_empty(),
			"登记表里没有一个文件是已经删掉的（列了 %d 行，多出 %d 个：%s）"
			% [rows.size(), ghosts.size(), ", ".join(ghosts.slice(0, 6))])
	_check(rows.size() == files.size(),
			"登记表行数 == assets/ 实际文件数（表 %d 行 / 实际 %d 个）"
			% [rows.size(), files.size()])

	# —— 第二组：内部清单 vs 对外署名文件 ——
	# 这一组是这份脚本真正想守的东西。`PROVENANCE.md` 是内部档案，
	# `CREDITS.md` 是**随发行物发出去的**。未核实的项如果只停在内部档案里，
	# 发出去的那份就成了「只字未提」——那比写「待核实」糟得多。
	var open_marks := ["待核实", "未核实", "来源未知", "UNKNOWN"]
	var prov_open := 0
	for m in open_marks:
		prov_open += prov.count(m)
	_check(prov_open > 0,
			"PROVENANCE.md 里确实标着未核实项（%d 处）——全绿说明清单被抹平了" % prov_open)

	var cred_open := 0
	for m in open_marks:
		cred_open += cred.count(m)
	_check(cred_open >= 2,
			"CREDITS.md 对外也如实标着未核实项（%d 处）——内部有而对外没写是发版事故"
			% cred_open)

	# 第三组的正对照：`CREDITS.md` 里的待核实项必须在内部清单里也数得到。
	# 只有对外标了、内部没标的，说明两份文档已经各自长出一套说法。
	_check(prov_open >= cred_open,
			"CREDITS.md 没有比 PROVENANCE.md 报出更多未核实项（对外 %d / 内部 %d）"
			% [cred_open, prov_open])

	# —— 第三组：OFL 正文必须真的在署名文件里 ——
	# 字体是 OFL 1.1，而 OFL 要求「每一份副本都含版权声明与本许可」。
	# 这条钉的是**结论句**（"not be sold by itself" / "SIL OPEN FONT LICENSE"），
	# 不是碰巧出现的某个词——改字体、改条款、或者有人手贱把整段删了，它都会红。
	_check(cred.contains("SIL OPEN FONT LICENSE"), "CREDITS.md 里带着 OFL 的结论句")
	_check(cred.contains("Neither the Font Software nor any of its individual"),
			"CREDITS.md 里带着 OFL 核心限制条款（字体及其组件不得单独出售）")
	_check(cred.contains("lxgw/LxgwWenKai"), "CREDITS.md 里带着 LXGW 的版权行")

	# —— 第四组：LICENSE ——
	_check(lic.contains("Permission is hereby granted"), "LICENSE 存在且是一份真许可")
	_check(lic.contains("MIT License"), "LICENSE 写明了是哪一份许可")
	_check(lic.contains("第三方资产不在此授权范围内"),
			"LICENSE 明说第三方资产不在它授权范围内（MIT 只覆盖原创部分）")

	print("\n================ 汇总 ================")
	print("[verify_provenance] %s  (失败项 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
