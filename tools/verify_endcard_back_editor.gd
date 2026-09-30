extends SceneTree
## verify_endcard_back_editor.gd — 背面写字编辑器(_show_back_editor)体检
##
## 这条代码路径原本有三处会各自中断执行的问题，全部在同一个函数里：
##   A. 4 处 Control.PRESET_CENTER_WIDE 不存在 -> 解析错误，脚本根本加载不了
##   B. _back_editor.bg_color：Control 没有这个属性 -> 运行到就中断，遮罩+子控件全加不上
##   C. te.max_length：TextEdit 没有这个属性（那是 LineEdit 的）-> 同样中断
##   另外 te 没有显式命名，_on_back_text_changed 按名字 "TextEdit" 取不到节点
##
## 本脚本在 1280x1280 和 1280x720(项目真实分辨率) 两种父尺寸下量几何，
## 并验证输入内容真的能读进 _back_text。
## 用法： godot --headless --path . --script tools/verify_endcard_back_editor.gd

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


func _ensure_autoloads() -> void:
	var paths := {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}
	for n in paths:
		if root.get_node_or_null(n) == null:
			var node: Node = load(paths[n]).new()
			node.name = n
			root.add_child(node)


func _has_prop(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if p.get("name", "") == prop:
			return true
	return false


func _initialize() -> void:
	_ensure_autoloads()
	_run.call_deferred()


func _run() -> void:
	print("=== 背面写字编辑器体检 ===")

	_check(not _has_prop(Control.new(), "bg_color"),
		"Control 确实没有 bg_color 属性")
	_check(not _has_prop(TextEdit.new(), "max_length"),
		"TextEdit 确实没有 max_length 属性")

	await _audit("默认")

	# 项目真实分辨率 1280x720：把根窗口调小再看一遍（确认百分比定位不会溢出屏幕）
	root.size = Vector2i(1280, 720)
	await create_timer(0.2).timeout
	await _audit("1280x720")

	print("\n================ 汇总 ================")
	print("[verify_endcard_back_editor] %s  (失败项 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _audit(tag: String) -> void:
	print("\n---------- 父尺寸 %s ----------" % tag)
	var card: Control = load("res://scenes/EndCard.tscn").instantiate()
	root.add_child(card)
	await process_frame
	await process_frame
	print("EndCard 根节点 size = %s" % str(card.size))
	var pw: float = card.size.x
	var ph: float = card.size.y

	card._show_back_editor()
	await process_frame
	await process_frame

	var ed: Control = card._back_editor
	_check(ed != null, "[%s] 背面编辑器已创建" % tag)
	if ed == null:
		return

	var i := 0
	var by_class := {}
	for c in ed.get_children():
		var r: Rect2 = c.get_rect()
		by_class[c.get_class()] = r
		var inside: bool = r.position.y >= -0.5 and r.end.y <= ed.size.y + 0.5 \
			and r.end.x <= ed.size.x + 0.5 and r.size.y > 0.0 and r.size.x > 0.0
		print("  [%d] %-10s rect=%s" % [i, c.get_class(), str(r)])
		_check(inside, "[%s] 子控件%d (%s) 正尺寸且完全在屏内" % [tag, i, c.get_class()])
		i += 1

	_check(ed.get_child_count() == 5,
		"[%s] 共 5 个子节点（遮罩+标题+输入框+2按钮），实际 %d" % [tag, ed.get_child_count()])

	# 各元素不能互相压住
	var rects: Array[Rect2] = []
	for c in ed.get_children():
		rects.append(c.get_rect())
	for a in range(rects.size()):
		for b in range(a + 1, rects.size()):
			var ra: Rect2 = rects[a]
			var rb: Rect2 = rects[b]
			if ra.size.x >= ph - 1.0 or rb.size.x >= ph - 1.0:
				continue   # 铺满整行的遮罩/标题跳过
			_check(not ra.intersects(rb, false),
				"[%s] 子控件%d 与 %d 不重叠" % [tag, a, b])

	# 输入内容读取链路
	var te: TextEdit = ed.get_node_or_null("TextEdit")
	_check(te != null, "[%s] 能按名字 'TextEdit' 取到输入框" % tag)
	if te != null:
		te.text = "测试祝福"
		card._on_back_text_changed()
		_check(card._back_text == "测试祝福",
			"[%s] 输入内容读进 _back_text（实际 '%s'）" % [tag, card._back_text])
		te.text = "字".repeat(300)
		card._on_back_text_changed()
		_check(card._back_text.length() == 200,
			"[%s] 超长输入截断到 200 字（实际 %d）" % [tag, card._back_text.length()])

	card.queue_free()
	await process_frame
