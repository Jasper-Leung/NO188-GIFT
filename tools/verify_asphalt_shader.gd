extends SceneTree
## asphalt.gdshader 回归 —— 判据全部**读源码文本**。
##
## 为什么只能是文本：`--headless` 用的是 dummy renderer，**不编译着色器**，
## 所以语法错和观感错在无头下都静默通过。几何/材质那一侧量不到
## "画没画出那条线"，而量得到的"材质类型对不对"与"颜色亮不亮"都不在这一族上。
## 做法照 `verify_grass_scatter.gd` 的草皮着色器那一节与 `verify_terrain_shader.gd`：
## 把那几个值从**文本**里读出来，让断言钉在真实出处上。
##
## 守的是一条已经真实发生过一次的缺陷：`edge_line_color` 这个 uniform
## 在着色器第 12 行**声明了整整一个项目，从来没有被任何一行读过**。
## 它合法、没有任何报错、也没有任何回归会红——而 CLAUDE.md 的「零纹理资产」
## 那一节正写着路面有"双黄虚线"，于是**文档和代码各说各的，两边都绿**。
## 「声明了却没人读」是「写进字段不等于读进世界」那一族里最难发现的一种：
## 它的症状是**另一个人在文档里写下的那句话**，而不是任何一条断言。
##
## 用法： godot --headless --path . --script tools/verify_asphalt_shader.gd


const SHADER_PATH := "res://assets/shaders/asphalt.gdshader"
const ROADBUILDER_PATH := "res://scripts/RoadBuilder.gd"

var _fails: Array = []
var _oks := 0
var _src := ""
## `_fragment_body` 里那一段。着色器函数体用大括号配对，数深度而不是
## 找行号 —— 往后有人在上面插几行，按行号切就切错地方了。
var _frag := ""


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


## 取 `void fragment()` 的函数体。找不到就返回空串，由调用方那条
## "函数体找得到"兜住 —— 空串会让下面每一条都红，而那正是想要的样子。
func _extract_fragment(src: String) -> String:
	var i := src.find("void fragment()")
	if i < 0:
		return ""
	var open := src.find("{", i)
	if open < 0:
		return ""
	var depth := 0
	for j in range(open, src.length()):
		if src[j] == "{":
			depth += 1
		elif src[j] == "}":
			depth -= 1
			if depth == 0:
				return src.substr(open + 1, j - open - 1)
	return ""


## 从 `vec4 NAME : source_color = vec4(...)` 里取默认值三通道。
func _uniform_default(name: String) -> Color:
	var rx := RegEx.new()
	rx.compile("uniform\\s+vec4\\s+" + name + "\\s*:\\s*source_color\\s*=\\s*vec4\\(([^)]*)\\)")
	var hit := rx.search(_src)
	if hit == null:
		return Color(-1, -1, -1)
	var parts: PackedStringArray = hit.get_string(1).split(",")
	if parts.size() < 3:
		return Color(-1, -1, -1)
	return Color(parts[0].strip_edges().to_float(),
			parts[1].strip_edges().to_float(),
			parts[2].strip_edges().to_float())


## 同一个取法，只是从任意一份着色器源码里读 `uniform vec4 NAME : source_color`。
## 手抄一份 `ground_color` 到这里的话，terrain_grass.gdshader 一改这边就安静地
## 过期——那正是「手抄的常量副本会自己长出一套预算曲线」这一族。
func _shader_color_of(src: String, name: String) -> Color:
	var rx := RegEx.new()
	rx.compile("uniform\\s+vec4\\s+" + name + "\\s*:\\s*source_color\\s*=\\s*vec4\\(([^)]*)\\)")
	var hit := rx.search(src)
	if hit == null:
		return Color(-1, -1, -1)
	var parts: PackedStringArray = hit.get_string(1).split(",")
	if parts.size() < 3:
		return Color(-1, -1, -1)
	return Color(parts[0].strip_edges().to_float(),
			parts[1].strip_edges().to_float(),
			parts[2].strip_edges().to_float())


func _run() -> void:
	print("=== 沥青着色器回归 ===")
	_src = FileAccess.get_file_as_string(SHADER_PATH)
	_ck("读得到着色器源码（%d 字节）" % _src.length(), _src.length() > 0)
	if _src.length() == 0:
		_finish()
		return
	_frag = _extract_fragment(_src)
	_ck("找得到 fragment() 的函数体", _frag.length() > 0,
			"按大括号配对没配上；函数体找得到这条不绿的话下面每一条都红")
	if _frag.length() == 0:
		_finish()
		return

	# ---- 1. 声明了的 uniform 必须被 fragment() 真的读过 ----
	# 这一族的头一条。`edge_line_color` 声明了从没被读过，而它在
	# 着色器里合法、没有任何报错——所以断言不能只查"声明在不在"，
	# 那正是它本来的样子。查的是**函数体里有没有一次读**。
	for u in ["edge_line_color", "center_line_color", "dirt_color",
			"asphalt_color", "grain_dark_color"]:
		_ck("uniform `%s` 被 fragment() 真的读过（不是只声明）" % u,
				_frag.contains(u + ".rgb"),
				"它在文件里有声明，可函数体里一次都没出现——声明了没人读的那一类")

	# ---- 2. 边线本身 ----
	# 实线（不随 dash 断续）而非常服中央虚线的断续：边线的作用是**定住
	# 那条边界**，断续的话边界反而读不出来。
	#
	# **两条不变量各自钉在**真正带着它的那一行**上，不是同一行**：
	# 位置是 `d_edge` 那一行的事（`abs(abs(lateral) - (road_half_width - 0.18))`），
	# 断续与否是 `edge_line` 那一行的事。第一版把两条都量在 `edge_line` 上，
	# 于是"位置从 road_half_width 推"那条当场红了——**判据红得对**，
	# 量错了行的是判据。教训同族：「纯函数量得到的东西」也得先确认
	# 那个函数里**哪一行**是这个量，读错行和写错代码在断言上长得一模一样。
	var d_edge: String = _decl_of("d_edge")
	var edge_line: String = _decl_of("edge_line")
	_ck("fragment() 里算出了 `d_edge`（边线到沥青外沿的距离）", d_edge != "")
	_ck("fragment() 里算出了 `edge_line`", edge_line != "")
	if d_edge != "":
		# 位置必须从 `road_half_width` 推出来，写死一个米数的话
		# 改 `RoadBuilder.ROAD_HALF_WIDTH` 就会和线错开——而沥青 mesh
		# 的外沿是从那个常量生成的，两边会一起动、看着还是对的。
		_ck("边线贴着**沥青外沿**（位置从 road_half_width 推，不是写死的米数）",
				d_edge.contains("road_half_width"),
				"d_edge 那一行：%s" % d_edge.strip_edges())
		# 必须在**外沿内侧**：线画在外沿之上（正的偏移）会被 mesh 的
		# 边界切掉一半，看上去就是一条忽粗忽细的亮带。
		_ck("边线在沥青外沿**内侧**（road_half_width 被减去一个内缩量）",
				d_edge.contains("road_half_width -"), d_edge.strip_edges())
	if edge_line != "":
		_ck("边线是**实线**（不跟中央线的 dash）", not edge_line.contains("dash"),
				"edge_line 那一行里有 dash：%s" % edge_line.strip_edges())
		# 广场模式下一律不画：广场的 `plaza_mode` 把 `road_half_width` 设成了
		# `PLAZA_RADIUS`，那里的边线会画成一圈箍住整块空地。
		_ck("边线在 plaza_mode 下不画", edge_line.contains("1.0 - plaza_mode"),
				"edge_line 那一行：%s" % edge_line.strip_edges())

	# ---- 3. 边线颜色的默认值必须是亮的 ----
	# `RoadBuilder` **不**给 `edge_line_color` 赋参数（只赋了三个宽度），
	# 所以线上那个颜色完全靠 uniform 的默认值。默认值要是哪天被调暗，
	# 线会在图上悄悄消失，而几何断言照绿。
	var ec := _uniform_default("edge_line_color")
	_ck("edge_line_color 的默认值够亮（%.3f ≥ 0.55）" % ec.get_luminance(),
			ec.get_luminance() >= 0.55,
			"RoadBuilder 不给它赋参数，全靠这个默认值")
	var cc := _uniform_default("center_line_color")
	_ck("边线和中央线是同一族的白（边 %.3f / 中 %.3f，差 %.3f）"
			% [ec.get_luminance(), cc.get_luminance(),
			absf(ec.get_luminance() - cc.get_luminance())],
			absf(ec.get_luminance() - cc.get_luminance()) <= 0.10,
			"差太远读成两种材料")

	# ---- 3b. 路肩那一层不许是土 ----
	# `dirt_color` 这个名字是历史留下来的：它驱动 `shoulder` 那条 smoothstep
	# （4.0→6.5m 的路肩）**和**路缘起灰那一层渐变，而它的值原来是
	# (0.300, 0.256, 0.184) ——**那是土**。于是沿整条环路两侧读成两条泥带，
	# 而"名字还叫 dirt"这件事让下一个人完全看不出它已经改过。
	#
	# 换成灰砾石 (0.430, 0.420, 0.398) 之后，量得到的那一条是**通道差**
	# （砾石低饱和，土高饱和，两者差一倍多）。这里钉上限，
	# 配一条**正对照**：`asphalt_color` 通道差 0.015（也是灰的），
	# 而"绿"的世界里草的通道差在 0.3 以上——用 `terrain_grass.gdshader`
	# 里那个 `ground_color` 当尺子的另一头，量的是"这把尺子分得开灰和绿"。
	var dc := _uniform_default("dirt_color")
	var sat := maxf(dc.r, maxf(dc.g, dc.b)) - minf(dc.r, minf(dc.g, dc.b))
	_ck("路肩不是土（dirt_color 通道差 %.3f ≤ 0.06）" % sat,
			sat <= 0.06,
			"dirt_color=(%.3f,%.3f,%.3f) 通道差=%.3f —— 土是 0.130"
			% [dc.r, dc.g, dc.b, sat])
	var tsrc: String = FileAccess.get_file_as_string(
			"res://assets/shaders/terrain_grass.gdshader")
	var gc: Color = _shader_color_of(tsrc, "ground_color")
	var gsat: float = maxf(gc.r, maxf(gc.g, gc.b)) - minf(gc.r, minf(gc.g, gc.b))
	_ck("正对照：地形草色通道差 %.3f 远在门槛之外（尺子分得开灰和绿）" % gsat,
			gsat > 0.15,
			"正对照只有 %.3f，这条判据就成了恒绿" % gsat)

	# ---- 4. 宽度常量不许和 RoadBuilder 悄悄错开 ----
	# 着色器里 `road_half_width` / `total_half_width` 的默认值和
	# `RoadBuilder` 的 `ROAD_HALF_WIDTH` / `TOTAL_HALF_WIDTH` 是**两份**。
	# 运行时 RoadBuilder 会 `set_shader_parameter` 覆盖过去，所以默认值
	# 写错**不会**让线画歪 —— 但它会让任何"照默认值算一遍"的判据算错，
	# 而那正是无头这一族唯一能算的东西。钉住它们相等。
	#
	# 宽度那几行是**一条链**（`ROAD_HALF_WIDTH := ROAD_WIDTH * 0.5` 而
	# `ROAD_WIDTH := LANE_WIDTH * 2.0`），所以判据**不许正则抄一遍算式**：
	# 正则会读到那个 `0.5` 而不是求值后的 4.0，于是它量的是"除数是不是 0.5"
	# ——恒绿，还绿得很有道理。这里走 `get_script_constant_map()`，
	# 读的是引擎**求值之后**的那份。
	var rb_script: GDScript = load(ROADBUILDER_PATH)
	var cm: Dictionary = rb_script.get_script_constant_map()
	_ck("RoadBuilder 的常量表读得到（%d 项）" % cm.size(), cm.size() > 0)
	_ck("常量表里有 ROAD_HALF_WIDTH", cm.has("ROAD_HALF_WIDTH"))
	_ck("常量表里有 TOTAL_HALF_WIDTH", cm.has("TOTAL_HALF_WIDTH"))
	if cm.has("ROAD_HALF_WIDTH") and cm.has("TOTAL_HALF_WIDTH"):
		var rh := float(cm["ROAD_HALF_WIDTH"])
		var th := float(cm["TOTAL_HALF_WIDTH"])
		_eq("着色器默认 road_half_width == RoadBuilder.ROAD_HALF_WIDTH",
				_uniform_float("road_half_width"), rh)
		_eq("着色器默认 total_half_width == RoadBuilder.TOTAL_HALF_WIDTH",
				_uniform_float("total_half_width"), th)
		# 边线画在沥青**外沿**上，而外沿到总宽之间还隔着路肩 ——
		# 两数相等就说明根本没有"路肩"这一层，边线会画在 mesh 的最外沿。
		_ck("沥青外沿到总宽之间还留出路肩（%.1fm > 0）" % (th - rh),
				th - rh > 0.0, "路肩宽度 %.1f" % (th - rh))

	# ---- 5. RoadBuilder 真的把两个宽度推给了材质 ----
	# 「写进字段不等于读进世界」的正解：这里量的是**赋值那几行在不在**，
	# 而着色器那边量的 uniform 确实被读了。两侧缺一头都是断的。
	var rb: String = FileAccess.get_file_as_string(ROADBUILDER_PATH)
	_ck("RoadBuilder 真的把 road_half_width 推给材质",
			rb.contains("set_shader_parameter(\"road_half_width\""))
	_ck("RoadBuilder 真的把 total_half_width 推给材质",
			rb.contains("set_shader_parameter(\"total_half_width\""))

	# ---- 6. 底色与微表面：量的是**物理量**，不是观感 ----
	# 2026-10-03 第四轮 P0-1。这一节守的三个数，**全部是量出来的**，
	# 而修复之前那 18 条断言一条都没红——因为它们守的是"边线画没画出来"，
	# 守不到"路面是什么颜色、法线有多陡"。这是 `edge_line_color` 那条的
	# **另一半**：那条是声明了没人读，这条是**读了但量错了量**。
	#
	# ① 底色反照率。真沥青的**线性**反照率大致 0.10~0.15。这两个常量带
	#    `source_color`，是 sRGB：旧值 0.168 → 线性 0.023，**暗四到五倍**，
	#    于是近处路面读成蓝紫霉斑，而黄昏把太阳压到 9° 时它没有余量可剩
	#    （P1-1 是这条的下游，不是并列的一条）。
	# ② 偏蓝。两个旧常量都是 b > g > r 的冷灰，而天空环境光本身偏蓝，
	#    底色再偏蓝一次就走样成椒盐。判据量的是**这三个通道的差**，
	#    不是"它是不是灰色"——灰色是三个数都小，而这是三个数不一样。
	# ③ 微表面走样。玩家眼高 1.6m、看 1~3m 处的路面时一个像素盖住好几个
	#    特征，所以**特征必须大过一个像素**，而法线梯度必须小到不会把
	#    每个微面片都掀翻（旧版 9cm 一个特征、梯度 ×16、混合 0.45：
	#    每个像素要么接到蓝天、要么接到地面，那片"斑块"是走样不是斑块）。
	# ④ 沥青没有金属度可言。`METALLIC = wet * 0.12` 那是在一片本来就
	#    接近纯黑的底子上加一面朝天的镜子，而它映的是天空。
	var ac := _uniform_default("asphalt_color")
	if ac.r >= 0.0:
		var alin := _lin_luma(ac)
		_ck("沥青底色的**线性**反照率落在真沥青那一档（%.3f ∈ [0.08, 0.18]）" % alin,
				alin >= 0.08 and alin <= 0.18,
				"sRGB %.3f → 线性 %.3f。带 : source_color 的默认值是 sRGB，"
				% [ac.get_luminance(), alin]
				+ "而 ALBEDO 是线性——中间隔着 srgb_to_linear 那一支，"
				+ "忘了它就会把「看着挺暗」当成「线性 0.168」")
		var skew := ac.b - ac.r
		_ck("底色不是偏蓝的冷灰（b - r = %.3f ≤ 0.02）" % skew,
				skew <= 0.02,
				"天空环境光本身偏蓝，底色再偏一次就叠加成椒盐")
	var gd := _uniform_default("grain_dark_color")
	if gd.r >= 0.0 and ac.r >= 0.0:
		var glin := _lin_luma(gd)
		_ck("颗粒暗色比底色暗、但仍在沥青这一族里（线性 %.3f < %.3f）"
				% [glin, _lin_luma(ac)],
				glin < _lin_luma(ac) and glin >= 0.02,
				"暗到 0.005 的话 grain 那一层就是往纯黑里混")

	var dp_line := _decl_of("dp")
	var dp := _last_factor(dp_line.replace("vec2 dp = wp *", ""))
	_ck("微表面特征大过一个像素（1/%.1f = %.0fcm ≥ 14cm）" % [dp, 100.0 / dp],
			dp > 0.0 and 1.0 / dp >= 0.14,
			"dp 那一行：%s" % dp_line.strip_edges())
	var grad := _frag_float("\\(\\s*d0\\s*-\\s*dxn\\s*\\)\\s*\\*\\s*([0-9]+(?:\\.[0-9]+)?)")
	var nmix := _frag_float("mix\\(\\s*NORMAL\\s*,\\s*normalize\\(\\s*micro\\s*\\)\\s*,\\s*([0-9]+(?:\\.[0-9]+)?)")
	_ck("法线扰动的强度（梯度 %.1f × 混合 %.2f = %.2f ≤ 1.5）不会逐像素走样"
			% [grad, nmix, grad * nmix],
			grad > 0.0 and nmix > 0.0 and grad * nmix <= 1.5,
			"旧版 16.0 × 0.45 = 7.2：每个微面片都在陡峭翻转，"
			+ "像素要么接到蓝天（蓝）要么接到地面（黑）")
	var mfac := _last_factor(_decl_of("METALLIC"))
	_ck("湿斑的金属度 ≤ 0.05（%.3f）——沥青不是金属" % mfac,
			mfac >= 0.0 and mfac <= 0.05,
			"METALLIC 那一行：%s" % _decl_of("METALLIC").strip_edges())
	var gmix := _frag_float("mix\\(\\s*col\\s*,\\s*grain_dark_color\\.rgb\\s*,\\s*grain\\s*\\*\\s*([0-9]+(?:\\.[0-9]+)?)")
	_ck("颗粒往暗色混的系数 ≤ 0.5（%.2f）" % gmix, gmix > 0.0 and gmix <= 0.5)

	_finish()


## 取 `float NAME = …` 那一行的**整行**文本。找不到返回空串。
## `METALLIC = …` 这种没有类型前缀的也认（第二遍找 `NAME =`）。
func _decl_of(name: String) -> String:
	for marker in ["float " + name + " =", name + " ="]:
		var i := _frag.find(marker)
		if i >= 0:
			var eol := _frag.find("\n", i)
			return _frag.substr(i, (eol if eol > 0 else _frag.length()) - i)
	return ""


## 从 `… * 2.5` 这种行里取最后一个乘数。取不到返回 -1。
func _last_factor(line: String) -> float:
	var rx := RegEx.new()
	rx.compile("\\*\\s*([0-9]+(?:\\.[0-9]+)?)\\s*;")
	var hit := rx.search(line)
	return -1.0 if hit == null else hit.get_string(1).to_float()


## sRGB 分量 → 线性。复制 Godot 那一支：着色器上带 `: source_color` 的
## vec4 默认值是**按 sRGB 解释**的，而 ALBEDO 是线性——中间隔着这一支。
## 忘了它就会把"0.168 看着挺暗"当成"线性 0.168"，而实际是 0.023。
func _s2l(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## 一个 sRGB 颜色的线性亮度。
func _lin_luma(c: Color) -> float:
	return 0.2126 * _s2l(c.r) + 0.7152 * _s2l(c.g) + 0.0722 * _s2l(c.b)


## 在 fragment() 函数体里按正则抓一个数，抓不到返回 -1。
func _frag_float(pattern: String) -> float:
	var rx := RegEx.new()
	rx.compile(pattern)
	var hit := rx.search(_frag)
	return -1.0 if hit == null else hit.get_string(1).to_float()


func _uniform_float(name: String) -> float:
	var rx := RegEx.new()
	rx.compile("uniform\\s+float\\s+" + name + "[^\\n]*?=\\s*([0-9]+(?:\\.[0-9]+)?)")
	var hit := rx.search(_src)
	return -1.0 if hit == null else hit.get_string(1).to_float()


func _finish() -> void:
	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)
