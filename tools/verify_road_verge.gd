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

	# 内沿那一列是砾石，要比草暗一点才读得出"从路上下来"
	_ck("内沿的砾石比草地暗（读得出是从沥青上走下来的）",
			_lum(prof[0][1]) < _lum(ground),
			"gravel=%.3f grass=%.3f" % [_lum(prof[0][1]), _lum(ground)])

	# ------------------------------------------- ④ 别把土调回来（这一轮的判据）
	# 这一族原来整条带子是**土**（DIRT 0.300/0.250/0.170、MIX 0.360/0.320/0.200），
	# 于是沿整条环路两侧读成两条泥带。现在中间三档换成低饱和的灰砾石。
	#
	# **这条判据量的是"有没有调回土色"，不是"好不好看"**——好看不好看只有
	# `lookdev_verge.gd` 的像素能量，而像素那一族又不能加 --headless，
	# 跑一次要开窗口。所以这里守的是一个**可复算的数**：通道差。
	# 砾石是低饱和的，所以最大通道差必然小；原来的土差 0.13，一档就分得开。
	#
	# 配一条**正对照**：`GRASS`（外沿，必须渲成和地形一样）通道差 0.242，
	# 远在门槛之外——不然"所有颜色都被去饱和"的世界里这条照样绿。
	var sat := func(c: Color) -> float:
		return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	# 名字表按**剖面的下标**排，不是按"要量哪几列"排——第一版写成三元素的
	# 名字数组再用剖面下标去取它，量到第三列时下标 3 直接越界，而脚本异常
	# 掐在 `quit()` 之前，于是整条回归**挂死到超时**，一行汇总都不打。
	# 这正是「一条回归自己抛异常时退出码是 0」那一族的极端形态：连
	# check_all 都只能靠 TIMEOUT 兜住它。
	var names: Array[String] = ["GRAVEL", "PACKED", "PACKED", "LINE", "LINE→GRASS", "GRASS"]
	for idx in [0, 1, 3]:
		var c: Color = prof[idx][1]
		var nm: String = names[idx]
		_ck("%s 读成砾石不是土（通道差 %.3f ≤ 0.06）" % [nm, sat.call(c)],
				sat.call(c) <= 0.06,
				"%s=(%.3f,%.3f,%.3f) 通道差=%.3f"
				% [nm, c.r, c.g, c.b, sat.call(c)])
	var gs: float = sat.call(prof[prof.size() - 1][1])
	_ck("正对照：外沿 GRASS 的通道差 %.3f 远在门槛之外（尺子量得到绿）" % gs,
			gs > 0.15,
			"正对照的通道差只有 %.3f，这条判据就成了恒绿" % gs)

	# ------------------------------------------------- ⑤ 砾石有石头一级的明暗
	# 真把带子建出来量，而不是量剖面表。
	#
	# 中心线在这里是**替身**：明暗是按**下标**算的（`_stone_mottle(i, c, sgn)`），
	# 而没有地形构建器时 `_terrain_h()` 恒返回 0，所以这一节量的**只有颜色**，
	# 与中心线摆在哪无关。点数取 2457 —— 1228.8m 的环路按 0.5m 重采样之后
	# 就是这个量级，而"翻转次数"那条判据量的是环上的密度，替身得给对。
	var ring: Array = []
	var cols_n: int = prof.size()
	var R := 180.0
	for i in 2457:
		var a: float = TAU * float(i) / 2457.0
		ring.append(Vector3(cos(a) * R, 0.0, sin(a) * R))
	var verge: Node3D = RV.new()
	verge.name = "VergeProbe"
	# 这份脚本 extends SceneTree，所以**没有** `add_child`——挂在 `root` 下面。
	# 第一版写成 `add_child(verge)` 的话 parse 就红，而 `--script` 模式下一行
	# parse 错之后 `quit()` 走不到，进程直接超时退出，看起来像"回归跑了很久"。
	root.add_child(verge)
	verge.call("build", ring, soft_bound)
	var vmesh: MeshInstance3D = verge.get_node("VergeMesh")
	var arr: Array = vmesh.mesh.surface_get_arrays(0)
	var _built_cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	# 每个中心线点铺 `cols * 2` 个顶点（路左一路右），不是 `cols`。
	# 第一版拿 `size / cols` 当行数，于是行数翻倍而循环仍按 `per_side` 步进，
	# 越界取到 29520 —— 症状是一行 SCRIPT ERROR、**汇总永远打不出来**。
	var _built_len: int = _built_cols.size() / (cols_n * 2)
	_ck("真把带子建出来了（正对照：%d 行 × %d 列）" % [_built_len, cols_n],
			_built_len > 2000,
			"只建出 %d 行——带子没铺满，量到的不是全线" % _built_len)

	# 上面第 ④ 节量的是**剖面表里那六个数**，而那条带子在被 build() 铺出去
	# 之前是**六列常量**——1228m 的环上每一个顶点都填同一个值。真砾石读成
	# 石头靠的是石子与石子之间的明暗差，而这里是零，所以骑行视角下它读成
	# 一条**水泥路肩**。这一节量的是**建出来的网格上的顶点色**，不是剖面表。
	#
	# 三条一起写：变化幅度、变化的粒度、以及一条**正对照**（漂白带那一列
	# 必须是常量——它要是也开始抖，第 ① 节「最亮的一列 == SOFT_BOUND」
	# 量的就不再是那条线了）。
	var per_side: int = cols_n * 2
	var gravel_lum: Array[float] = []
	var line_lum: Array[float] = []
	var flips: int = 0
	var prev := -1.0
	for v in _built_len:
		var base: int = v * per_side
		for c in range(0, cols_n):
			var col: Color = _built_cols[base + c]
			var l: float = _lum(col)
			if c == 0:
				gravel_lum.append(l)
				if prev >= 0.0 and signf(l - prev) != 0.0:
					flips += 1
				prev = l
			elif c == mark_i:
				line_lum.append(l)
	# 变化幅度：压暗系数下限是 STONE_DARK，所以最暗那个顶点至少要暗到
	# 常量的 80% 以下，否则等于没压。
	var gmin := INF
	var gmax := -INF
	for l in gravel_lum:
		gmin = minf(gmin, l)
		gmax = maxf(gmax, l)
	var g_spread: float = (gmax - gmin) / maxf(gmax, 0.0001)
	_ck("砾石那列有石头一级的明暗（跨度 %.3f ≥ 0.12）" % g_spread,
			g_spread >= 0.12,
			"最暗 %.4f 最亮 %.4f 跨度 %.4f" % [gmin, gmax, g_spread])
	# 变化的粒度：1200 多米的环上至少要有几十次明暗翻转。零翻转就是常量。
	_ck("明暗是逐顶点变的不是整条一起变（翻转 %d 次 ≥ 24）" % flips,
			flips >= 24,
			"只翻了 %d 次——这条带子还是一整块板子" % flips)
	# 正对照：漂白带那一列必须仍然是**常量**，它一抖第 ① 节量的就不是它了。
	var lmin := INF
	var lmax := -INF
	for l in line_lum:
		lmin = minf(lmin, l)
		lmax = maxf(lmax, l)
	var l_spread: float = (lmax - lmin) / maxf(lmax, 0.0001)
	_ck("正对照：漂白带那列保持常量（跨度 %.4f ≤ 0.001）" % l_spread,
			l_spread <= 0.001,
			"漂白带自己也在抖，跨度 %.4f——第 ① 节的亮峰就不是它了" % l_spread)
	# 「最暗的砾石仍比沥青亮」**这一条这里量不到，别装。**
	# 它手上有两个数在两个不同的空间里：手上的 gmin 是**反照率**的相对亮度
	# （0.077），而"沥青 0.378"那个数是 `lookdev_verge.gd` 正交俯拍量到的
	# **渲出来**的显示值。拿它们比，比的是两个量——而这正是本文件开头写的
	# 那条「反照率对比度不是渲出来的对比度」，第一版判据栽的也是它。
	# 反过来，按反照率比也不成立：沥青走的是 `asphalt.gdshader` 自己的那套
	# 处理，而路肩是 `SPECULAR_DISABLED` + 顶点色的裸 StandardMaterial3D，
	# 两者从反照率到屏幕像素的路不一样长。
	# 这条**归 `lookdev_verge.gd` 的像素判据**，它量的是同一张图上的
	# 「沥青那一列」与「砾石最暗的那一列」。这里只把数打出来备查。
	print("  （供 lookdev_verge 对拍：砾石反照率亮度 %.4f ~ %.4f）"
			% [gmin, gmax])

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
