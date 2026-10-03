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

	_finish()


## 取 `float NAME = …` 那一行的**整行**文本。找不到返回空串。
func _decl_of(name: String) -> String:
	var marker := "float " + name + " ="
	var i := _frag.find(marker)
	if i < 0:
		return ""
	var eol := _frag.find("\n", i)
	return _frag.substr(i, (eol if eol > 0 else _frag.length()) - i)


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
