extends SceneTree
## RoadVerge 回归 —— 路肩外那道**看得见的**软边界。
##
## 评审 P1-2：车骑出路肩 15~20m 之后「找不着路」。机制在 CLAUDE.md 的陷阱
## 清单里早就记着（`SOFT_BOUND=12` 之外推力在 21m 处压过 `ACCEL=8.0`，
## 满速 15m/s 的车在 27m 处被钉住），当年的结论是「回归验证：无」。
##
## 本文件守的**不是**「这辆车能不能开回来」——那一族量的是机器（推力公式），
## 而这一轮按评审的要求**没有削弱推力**，所以把「最后 20m 平均速度 ≥ 8m/s」
## 钉成断言的话，正确的修法会让它一直红，唯一的绿法是把墙变矮。
## 那是一条**和修法互相拆台**的判据：屏幕在教玩家往哪骑，`play_newcomer`
## 是个只发按键、不看像素的脚本驾驶员，它永远学不会「看」这道带子。
## 所以这里量的是**这次修法真正交付的那件事**。
##
## 守三件：
##   ① **画出来的那道线，就是推你回来的那道力所在的那条线。**
##      这是全套里最要紧的一条：`World3D` 建这个节点时把 `SOFT_BOUND`
##      **当参数传进来**，而 `_apply_boundary_force()` 读的是同一个常量，
##      所以两边结构上不可能漂。断言钉的是「剖面里那一列的距离 == SOFT_BOUND」，
##      外加一条读源码文本的「`build()` 真的接了这个参数」。
##   ② **那道带子是一道「线」而不是一段路的末梢**：剖面里漂白带必须是最亮的
##      一列，而且**两侧各有一个台阶**（内侧的土、外侧朝草色褪的那一列）。
##      ——这一节**原来**量的是「漂白带对地形草色的 WCAG 对比度 ≥ 2.2:1」，
##      实测 2.58 一直全绿，而正交俯拍逐像素量到那六米渲出来是
##      sRGB 0.73~0.99 的**一整条白**。见下面「尺子」那一段的成因。
##      「看不看得见」由 `tools/lookdev_verge.gd` 的像素量，无头回归没有
##      那个能力——**量不到就别假装量得到**。
##   ③ **土径两头都不自己造硬边**：外沿必须落在地形自己的取值范围内，
##      内沿必须接住沥青路肩而不是悬在半空。
##
## 用法： godot --headless --path . --script tools/verify_road_verge.gd

var _fails: Array = []
var _oks := 0


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


## WCAG 相对亮度。Godot 的 `Color` 就是 sRGB，先转线性再加权——
## 和 verify_postcard_ending.gd 里那份是同一个算法，两边量的是同一个量。
func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## 对比度，单边读（调用处一律写 "≥ 某个数"）。
func _contrast(a: Color, b: Color) -> float:
	var la: float = _lum(a)
	var lb: float = _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 路肩软边界回归 ===")

	# --script 模式下 analyzer 认不出 class_name + autoload 一起来的推断，
	# 用 load().new() 而不用类型注解。
	var RV = load("res://scripts/RoadVerge.gd")

	# World3D 的常量走 get_script_constant_map() 读**求值之后**的值，
	# 别在源码里正则去抠 "12.0"——那量到的是字面量不是那个距离。
	var wm: Dictionary = load("res://scripts/World3D.gd") \
			.get_script_constant_map()
	var soft_bound: float = wm["SOFT_BOUND"]
	var hard_bound: float = wm["HARD_BOUND"]
	var rb: Dictionary = load("res://scripts/RoadBuilder.gd") \
			.get_script_constant_map()
	var total_half: float = rb["TOTAL_HALF_WIDTH"]
	print("  （SOFT_BOUND=%.2f  HARD_BOUND=%.2f  TOTAL_HALF_WIDTH=%.2f）"
			% [soft_bound, hard_bound, total_half])

	# ---------------------------------------------------------------- 剖面
	var prof: Array = RV.verge_profile(soft_bound)
	_eq("剖面六列", prof.size(), 6)

	# 内沿必须正好接住沥青外沿。差半米的话土径和路肩之间裂一道，
	# 而那道缝在骑行视角下就是一条压过沥青的黑线。
	_eq("内沿接住沥青外沿", prof[0][0], total_half)
	_ck("外沿越过软边界（不然那道线在纸外，看不见）",
			prof[prof.size() - 1][0] > soft_bound,
			"outer=%.2f soft_bound=%.2f" % [prof[prof.size() - 1][0], soft_bound])
	_ck("外沿没铺到硬边界上（再远就是自己造的硬边）",
			prof[prof.size() - 1][0] < hard_bound,
			"outer=%.2f hard_bound=%.2f" % [prof[prof.size() - 1][0], hard_bound])

	# 距离单调递增且不重合——不单调的话画出来的带子自己会翻过去
	var mono := true
	for i in range(1, prof.size()):
		if prof[i][0] <= prof[i - 1][0]:
			mono = false
	_ck("剖面距离严格递增", mono)

	# ------------------------------------------------- ① 线 == 力（最要紧）
	# 找出漂白带那一列：LINE 是剖面里最亮的那一列。
	var mark_i := 0
	for i in prof.size():
		if _lum(prof[i][1]) > _lum(prof[mark_i][1]):
			mark_i = i
	# 这里原来还有一条 `_lum(prof[mark_i][1]) > 0.5`——"剖面里最亮的一列要够亮"。
	# 那是**反照率**口径的门槛，和第 ② 节那两条 WCAG 对比度同一个病：它量的是
	# 我填进去的那个数，中间隔着法线、太阳角、AGX 与雾。`LINE` 现在是 0.58/0.56/0.47
	# （线性相对亮度 0.273），而它在正交俯拍里渲成 sRGB 0.765——**它照亮的那条线**
	# 才是玩家读的东西，0.5 那条线拦的却是另一个。
	# 「找得到最亮的一列」这件事本身由第 ② 节那条严格版守（它逐列比，
	# 任何一列更亮都红），所以这里不再重复。
	_ck("**画出来的那道线就在推你回来的那道力所在的那条线上**",
			is_equal_approx(float(prof[mark_i][0]), soft_bound),
			"线在 %.3fm，力从 %.3fm 起（差 %.3fm）"
			% [prof[mark_i][0], soft_bound, prof[mark_i][0] - soft_bound])

	# 结构上防漂：`build()` 收的是 soft_bound 参数，不是自己再抄一个 12.0。
	# **先把注释行剔掉再搜**——第一版直接 `not src.contains("12.0")`，
	# 红的却是本文件开头那句解释「不是两边各抄一个 12.0」的注释本身。
	# 可推广的一条（和「正则抄算式量到的是除数」是同一条的两头）：
	# **文本断言搜到的那个串，得先确认它是代码而不是散文**——
	# 搜不到不等于性质成立，搜到了也不等于量的是被测的那件事。
	var src: String = FileAccess.get_file_as_string("res://scripts/RoadVerge.gd")
	var src_code := _strip_comments(src)
	_ck("剖面把 soft_bound 当参数收（代码里没有第二个 12.0）",
			src_code.contains("static func verge_profile(soft_bound: float)")
			and not src_code.contains("12.0"),
			"剖面签名 %s；代码里 12.0 出现 %d 次"
			% ["对" if src_code.contains("verge_profile(soft_bound: float)") else "错",
			src_code.count("12.0")])
	var wsrc: String = FileAccess.get_file_as_string("res://scripts/World3D.gd")
	_ck("World3D 把自己的 SOFT_BOUND 传给 build()（不是字面量）",
			wsrc.contains("_verge.build(_road_builder.get_centerline(), SOFT_BOUND)"),
			"没找到 `_verge.build(..., SOFT_BOUND)` 那一行")

	# ------------------------------------------------------- ② 线看得见
	# 地形那两档草色直接从着色器源码读——terrain_grass.gdshader 是权威，
	# 这里手抄一份的话它一改这边就安静地过期（同一族的第三个教训）。
	var tsrc: String = FileAccess.get_file_as_string("res://assets/shaders/terrain_grass.gdshader")
	var ground: Color = _shader_color(tsrc, "ground_color")
	var ground_dark: Color = _shader_color(tsrc, "ground_dark")
	_ck("读到了地形着色器的 ground_color", ground.a > 0.0)
	_ck("读到了地形着色器的 ground_dark", ground_dark.a > 0.0)
	if ground.a <= 0.0:
		ground = Color(0.360, 0.550, 0.240)
	if ground_dark.a <= 0.0:
		ground_dark = Color(0.240, 0.390, 0.160)

	var line_col: Color = prof[mark_i][1]
	# ---- 这一节原来的两条断言是**量错了东西**，而那正是产品坏掉的原因。
	#
	# 原判据：`_contrast(LINE, ground_color) >= 2.2:1`，实测 2.58，**全绿**。
	# 真值：正交俯拍逐像素量到，8.5~14.5m 那六米渲出来是
	# sRGB(0.73 … 0.93 … 0.99) —— **整条带子一起顶到白**，"一道线"根本
	# 不存在，读出来是一圈水泥地。而剖面里那个 `LINE` 确实是 0.84/0.82/0.70，
	# 一格不差：断的不是数据，是**尺子**。
	# 根因是 `vertex_color_is_srgb` 默认 false——引擎把数组里那个数当**线性**
	# 反照率用，0.84 的线性值换算成 sRGB 是 0.93。中间还隔着法线、太阳角、
	# AGX 与雾，一层都没量到。
	# 所以这里改成量**结构**（剖面自身的形状，量得到也守得住），
	# 把「看不看得见」交给 `tools/lookdev_verge.gd` 的像素——
	# 无头回归**量不了**渲染结果，这不是它不努力，是它没有那个能力。
	var mark_lum: float = _lum(line_col)
	var brightest := true
	for i in prof.size():
		if _lum(prof[i][1]) > mark_lum:
			brightest = false
	_ck("**漂白带是剖面里最亮的一列**（它得是个「线」，不是一段路的末梢）",
			brightest, "mark lum=%.3f" % mark_lum)
	# 一条"线"要读得出来，靠的是**两侧各有一个台阶**。内侧那一列是土，
	# 外侧那一列已经朝草色褪了；两个台阶都在，才有一条线而不是一条渐变。
	var inner_flank: float = _lum(prof[mark_i - 1][1])
	var outer_flank: float = _lum(prof[mark_i + 1][1])
	_ck("漂白带内侧有台阶（相邻那列 ≤ 它的 80%%，实测 %d%%）"
			% int(round(100.0 * inner_flank / maxf(mark_lum, 0.0001))),
			inner_flank <= mark_lum * 0.80,
			"inner=%.3f mark=%.3f" % [inner_flank, mark_lum])
	_ck("漂白带外侧有台阶（相邻那列 ≤ 它的 92%%，实测 %d%%）"
			% int(round(100.0 * outer_flank / maxf(mark_lum, 0.0001))),
			outer_flank <= mark_lum * 0.92,
			"outer=%.3f mark=%.3f" % [outer_flank, mark_lum])

	# ---- 下面两条是**这次真正修的那两个 bug**，量得到（读源码文本）。
	# 它们和剖面无关：剖面对不对、带子亮不亮，都盖不住"压根没人写
	# ARRAY_NORMAL"和"顶点色被当线性读"这两件事。
	_ck("网格写了法线（没有法线 → N·L 恒为 0 → 只吃天光 → 漂白带渲成一条深蓝沟）",
			src.contains("arrays[Mesh.ARRAY_NORMAL] = _face_normals("),
			"没找到 `arrays[Mesh.ARRAY_NORMAL] = ...` 那一行")
	_ck("顶点色按 sRGB 解释（`vertex_color_is_srgb`）",
			src.contains("mat.vertex_color_is_srgb = true"),
			"没找到 `vertex_color_is_srgb = true`；"
			+ "默认 false 会把剖面里那些数当线性反照率，整条带子凭空亮一档半")
	# 反照率本身的合理性只当**上限**守：线性口径下 0.84 那一档能过，
	# 所以这一条不负责"看不看得见"，只拦一个手滑进来的离谱值。
	_ck("漂白带的反照率没离谱（相对亮度 ≤ 0.45）", mark_lum <= 0.45,
			"lum=%.3f" % mark_lum)

	# ---------------------------------------------------- ③ 两头不造硬边
	var outer: Color = prof[prof.size() - 1][1]
	# 地形是 ground_color / ground_dark 之间的混合，回归拿**亮端**当上界：
	# 外沿比亮端还亮 = 土径尽头多出一道自己造的硬边。
	_ck("外沿不亮过地形自己的亮端（不自己造硬边）",
			_lum(outer) <= _lum(ground) + 0.02,
			"outer=%.3f ground_color=%.3f" % [_lum(outer), _lum(ground)])
	_ck("外沿也不暗成一截（留在一档之内，不是另一条黑边）",
			_lum(outer) >= _lum(ground_dark) - 0.02,
			"outer=%.3f ground_dark=%.3f" % [_lum(outer), _lum(ground_dark)])

	# 内沿那一列是土，要比草暗一点才读得出"从路上下来"
	_ck("内沿的土比草地暗（读得出是从沥青上走下来的）",
			_lum(prof[0][1]) < _lum(ground),
			"dirt=%.3f grass=%.3f" % [_lum(prof[0][1]), _lum(ground)])

	# ------------------------------------------------------------ 画笔接线
	# 纯函数对不对、和画笔有没有去调它是两件事（--headless 下一笔都不落盘）。
	_ck("画笔真的调了 verge_profile(...)",
			src.contains("var prof: Array = verge_profile(soft_bound)"),
			"没找到 build() 里那一行")
	_ck("剖面用顶点色铺（零纹理这一族约束没破）",
			src.contains("vertex_color_use_as_albedo = true")
			and not src.contains("load(\"res://assets/textures"),
			"vertex_color=%s" % src.contains("vertex_color_use_as_albedo = true"))

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)


## 剔掉整行注释（`##` 开头）。GDScript 没有块注释，所以按行剔就够。
func _strip_comments(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if not t.begins_with("#"):
			out += line + "\n"
	return out


## 从着色器源码里抠 `uniform vec4 <name> : source_color = vec4(a, b, c, d);`。
## 没抠到就返回 alpha=0 的哨兵——**不给"没抠到"编一个像样的颜色**，
## 那正是这一族量错尺子的老毛病（第一版拿手抄的 grass.gdshader 的
## ground_color 去当地形色，两份一改就只剩一边还在）。
func _shader_color(src: String, name: String) -> Color:
	var re := RegEx.new()
	re.compile("uniform\\s+vec4\\s+%s\\s*:\\s*source_color\\s*=\\s*vec4\\(([^)]*)\\)" % name)
	var m := re.search(src)
	if m == null:
		return Color(0, 0, 0, 0)
	var parts: PackedStringArray = m.get_string(1).split(",")
	if parts.size() < 3:
		return Color(0, 0, 0, 0)
	return Color(float(parts[0]), float(parts[1]), float(parts[2]), 1.0)
