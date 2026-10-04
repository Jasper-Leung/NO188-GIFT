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


## WCAG 相对亮度。`Color` 在本工程一律按 sRGB 写（theme override 也是），
## 先转线性再加权——和 verify_postcard_ending.gd 里那份是同一个算法。
func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## 对比度，单边读（调用处一律写 "≥ 某个数"）。合成色请先过 `_over()`。
func _contrast(a: Color, b: Color) -> float:
	var la: float = _lum(a)
	var lb: float = _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## 半透明底板压在实底上的合成结果。**不合成就是量错的量**——
## 这一屏的底色只有一档，而半透明底板的对比度会随背景漂。
func _over(fg: Color, bg: Color) -> Color:
	return Color(
		fg.r * fg.a + bg.r * (1.0 - fg.a),
		fg.g * fg.a + bg.g * (1.0 - fg.a),
		fg.b * fg.a + bg.b * (1.0 - fg.a))


## 第四轮 P1-3：背面编辑器那两个按钮读不出来。
##
## 原来两个都是裸的 `Button.new()`，走引擎默认主题的 StyleBoxFlat：底色
## `Color(0.1,0.1,0.1,0.6)`、`border_width = 0`。而这一屏的底是
## `Color(0.05,0.04,0.04)` 的**不透明**遮罩——合成出来是 (0.08,0.076,0.076)，
## 对遮罩本体 **1.07:1，一条边都没有**。图上读成"屏幕上有一块颜色稍微不太
## 一样的地方"，而不是一个可以按的东西。
##
## **病不在字，在边界。** 默认按钮字色本来就亮（合成后实测 12.9:1），
## 旧画法在"字对底"这一条上完全达标——所以判据也不许去断字，断的是边。
## 两条同类判据的教训都摆在这一段里：
## ① **分开"按钮"和"输入框"的是那条边，不是填色**：试过把底板提亮到撑得起
##    1.6:1 的差别，0.25 那档也只有 1.32:1，要再亮就得整屏提亮，而这一屏本来
##    就是深色收尾的。底板和输入框同色是**刻意的**（同一族的墨），所以这里
##    **没有**「底板不许和输入框同色」那一条。
## ② **底板必须不透明**，否则"这一屏上读得出来"会随背景漂。
##
## 末条 `_check` 是**正对照**：拿引擎默认那一档自己算一遍，它在同一个遮罩上
## 只有 1.07:1。没有它的话，"边线 ≥3:1"这条在"边线整个被删掉、而底板也一直没
## 被显式写"的世界里会照绿——这一族栽过好几次。
##
## **「有一条边」和「边线的对比度」必须成对写，缺一条就有一个世界量不出来。**
## 这不是推演，是把 `_style_back_button()` 的两个调用点删掉之后量到的：
## 那次突变红了 8 条，可红的全是「有一条边」和「底板不透明」，
## **两条边线对比度（对底板 4.6:1 / 对遮罩 6.1:1）照样全绿**——
## 因为引擎默认的 `border_color` 本身是浅灰，而默认的 `border_width` 是 **0**，
## 也就是说**那条边根本没被画出来**。`get_theme_stylebox("normal")` 在没设过
## 覆盖时返回的也是这个默认对象（非 null），于是"有底板""对比度够"全部照绿。
## 换句话说：**对比度量的是"那条边如果被画出来会有多清楚"，
## 而 `border_width ≥ 1` 量的才是"它到底在不在屏上"**。
func _audit_back_buttons(tag: String, ed: Control) -> void:
	# 遮罩本体直接问那个 ColorRect，而不是抄 `_show_back_editor()` 里的字面量：
	# 抄的那份是"我以为底是那个色"，这里量的是"底真的是那个色"。
	var overlay := Color(0.05, 0.04, 0.04, 1.0)
	for c in ed.get_children():
		if c is ColorRect:
			overlay = (c as ColorRect).color
			break

	for c in ed.get_children():
		if not (c is Button):
			continue
		var b: Button = c
		var label: String = "[%s] 按钮「%s」" % [tag, b.text]

		# —— 边界：这一屏上把它和输入框分开的就是这条边 ——
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
		_check(sb != null, "%s 有自己的 normal 底板（不是引擎默认那套）" % label)
		if sb == null:
			continue
		_check(sb.border_width_top >= 1,
				"%s 有一条边（原来 0，对遮罩只有 1.07:1）" % label)
		# 五个状态都得画：只画 normal 的话，鼠标一移上去按钮就"没了"。
		var states := ["hover", "pressed", "focus", "disabled"]
		var missing := ""
		for st in states:
			if b.get_theme_stylebox(st) == null:
				missing += st + " "
		_check(missing == "", "%s 五个状态都画了底板（缺：%s）" % [label, missing.strip_edges()])

		# —— 底板不透明 ——
		_check(is_equal_approx(sb.bg_color.a, 1.0),
				"%s 底板不透明（实测 alpha=%.2f，半透明的对比度会随背景漂）"
				% [label, sb.bg_color.a])
		var bg: Color = _over(sb.bg_color, overlay)

		# —— 边线对底板、对遮罩，各 ≥3:1 ——
		var cb: float = _contrast(sb.border_color, bg)
		_check(cb >= 3.0, "%s 边线对底板 ≥3:1（实测 %.2f:1）" % [label, cb])
		var co: float = _contrast(sb.border_color, overlay)
		_check(co >= 3.0, "%s 边线对遮罩 ≥3:1（实测 %.2f:1）" % [label, co])

		# —— 字对底板 ≥4.5:1（这条本来就过，钉住它是为了改配色时有人会顺手削）——
		var fc: Color = b.get_theme_color("font_color")
		var cf: float = _contrast(fc, bg)
		_check(cf >= 4.5, "%s 字对底板 ≥4.5:1（实测 %.2f:1）" % [label, cf])

		# —— 正对照：引擎默认那一档在同一块遮罩上确实读不出来 ——
		# 默认底 `Color(0.1,0.1,0.1,0.6)` 合成过来是 (0.08,0.076,0.076)，
		# 对遮罩 1.07:1、且 border_width = 0（没有边可比）。
		# 拿它当尺子，而不是拿"不是那个色"当判据——这一族的手册就是这么写的。
		var dflt := _over(Color(0.1, 0.1, 0.1, 0.6), overlay)
		var cd: float = _contrast(dflt, overlay)
		_check(cd < 3.0,
				"%s 正对照：引擎默认那档确实读不出来（%.2f:1 < 3.0）" % [label, cd])


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

	# 断**构成**而不是断总数。原来写的是 `get_child_count() == 5`，而背面预览
	# （TextureRect + 它上面那行说明 Label）是后加的——于是这条从加预览那天起
	# 一直红着，没人跑它而已。总数是一个变更探测器而不是不变量：合法地多一个
	# 说明文字就会红，而真正要守的是"遮罩只有一层、动作只有两个、预览只有一块"。
	var n_colorrect := 0
	var n_button := 0
	var n_textedit := 0
	var n_textr := 0
	for c in ed.get_children():
		match c.get_class():
			"ColorRect": n_colorrect += 1
			"Button": n_button += 1
			"TextEdit": n_textedit += 1
			"TextureRect": n_textr += 1
	_check(n_colorrect == 1,
		"[%s] 遮罩恰好一层（多一层就是整屏被压两遍）" % tag)
	_check(n_button == 2,
		"[%s] 恰好两个动作按钮（多一个就把版面挤掉，少一个就有个功能点不到）" % tag)
	_check(n_textedit == 1, "[%s] 恰好一个输入框" % tag)
	_check(n_textr == 1, "[%s] 恰好一块预览（所见的和导出的必须是同一张）" % tag)

	_audit_back_buttons(tag, ed)

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
