extends SceneTree
## 交叉点「路自此复」那块碑的回归。
##
## 为什么要有一个东西站在交叉点上：这里是**全世界唯一能一眼看完整条路**的位置
## （`lookdev_crossing.gd` 的 `0_aerial` 就站在这儿拍），而它原来是一块空的沥青。
## `verify_crossing.gd` 量的是路面在自交处的**高度连续**——玩家会不会感觉到台阶
## ——它对"这个位置长什么样"一个字都没说。几何回归量不出"空"，空是要人看的。
##
## 量的五件事：
##   1. 碑建出来了，题字是真的文案而不是露出来的 key；
##   2. **落点站得住**——不压沥青、不糊在驿站上，而且人真的能停到它跟前
##      （`_apply_boundary_force` 的推力压过油门的那个半径之外，车是被钉住的）；
##   3. 碑面朝交叉点，不朝世界原点；
##   4. 碑面后仰到"站着低头看得见"的那一档；
##   5. **刻线刻的真是这条路，而且刻出来是个 8**——两个半环的 x 区间必须交叠
##      （圆的两个半环不交叠），而 z 区间只在交叉点上相接。
##
## 第 5 条是这块碑的全部意义：刻线由 `RoadData.points` 生成，和 RoadBuilder
## 建沥青用的是同一份数据，所以这张图不可能说谎。改环路它自己跟着改——
## 而"跟着改"不等于"还读得出是 8"，那半条得单独量。
##
## 用法： godot --headless --path . --script tools/verify_crossing_mark.gd
## 注意 --quit-after 单位是帧不是秒。

const CrossingMarkRef = preload("res://scripts/CrossingMark.gd")

## World3D.SOFT_BOUND —— 离路心线超过这个数就开始往回推。
## 这里抄一份而不引 World3D：`--script` 模式下 class_name/单例引用不可靠
## （见 CLAUDE.md）。改 World3D 那个数这条会红，那正是它该做的。
const SOFT_BOUND := 12.0
## Player3D.ACCEL —— 边界推力压过它的时候，车就推不动了。
const PLAYER_ACCEL := 8.0
## World3D.PUSH_STRENGTH / HARD_BOUND，同上。
const PUSH_STRENGTH := 12.0
const HARD_BOUND := 25.0

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _mark: Node = null
var _rd = null
var _backup := ""


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _initialize() -> void:
	_gm = root.get_node_or_null("GameManager")
	_loc = root.get_node_or_null("Localization")
	if _gm == null or _loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return

	_backup = ""
	if FileAccess.file_exists(str(_gm.SAVE_PATH)):
		var rf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			_backup = rf.get_as_text()
			rf.close()

	_gm.reset()
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	_gm.headless_mode = true
	root.size = Vector2i(1280, 720)

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	_run.call_deferred()


func _nearest_road_dist(p: Vector2) -> float:
	var best := 1e9
	for c in _rd.points:
		var d := Vector2(c.x, c.z).distance_to(p)
		if d < best:
			best = d
	return best


func _nearest_road_point(p: Vector2) -> Vector2:
	var best := 1e9
	var at := Vector2.ZERO
	for c in _rd.points:
		var d := Vector2(c.x, c.z).distance_squared_to(p)
		if d < best:
			best = d
			at = Vector2(c.x, c.z)
	return at


## 点到线段的最短距离（XZ 平面）。树的 y 不参与——挡不挡视线是水平问题。
func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0))


func _run() -> void:
	print("=== 交叉点「路自此复」回归 ===")
	await create_timer(2.5).timeout
	_world._onboarding.visible = false

	_mark = _world._crossing_mark
	_rd = _world._road_builder.get_road_data()

	# ---- 1. 碑在场，题字是真的文案 ----
	_ck("CrossingMark 节点建出来了", _mark != null)
	if _mark == null:
		_finish()
		return
	var stele = _mark.get_node_or_null("CrossingStele")
	_ck("碑身建出来了（CrossingStele）", stele != null)
	if stele == null:
		_finish()
		return
	var face = stele.get_node_or_null("Face")
	var slab = stele.get_node_or_null("Face/Slab")
	var trace = stele.get_node_or_null("Face/Trace")
	var label = stele.get_node_or_null("Face/Mark")
	_ck("有碑面（Face）", face != null)
	_ck("有石板（Slab）", slab is CSGBox3D)
	_ck("有刻线（Trace）", trace is MeshInstance3D)
	_ck("有题字（Mark）", label is Label3D)

	# Localization.t() 查不到 key 时返回 key 自己、不报错也不返回空串 ——
	# 漏了英文的话中文界面一路正常，只有切到英文的那一屏露 key。
	var key := "crossing_mark_line"
	var zh: String = _loc.STRINGS.get("zh", {}).get(key, "")
	var en: String = _loc.STRINGS.get("en", {}).get(key, "")
	_ck("题字有中文", str(zh) != "")
	_ck("题字有英文", str(en) != "")
	_ck("题字中英不是同一句", str(zh) != str(en))
	if label is Label3D:
		_ck("碑上刻的是文案而不是 key 本身", label.text != key,
				"text=%s" % label.text)
		_ck("碑上的字和 Localization 一致", label.text == str(_loc.t(key)),
				"碑=%s 表=%s" % [label.text, str(_loc.t(key))])

	# ---- 2. 落点站得住 ----
	# 2.1 交叉点找对了：两条相隔半圈的支路在这里几乎重合。
	#     这一条先钉住"碑确实站在自交点上"——落点判据全建立在它之上，
	#     而它失效的症状是碑凭空站到环的另一边去，仍然全程无错。
	var cp: Vector3 = _mark.crossing_point
	var half := float(_rd.points.size()) * 0.5
	var gap := INF
	for i in range(_rd.points.size()):
		for j in range(i + 1, _rd.points.size()):
			if absf(float(j - i) - half) > 3.0:
				continue
			var d: float = Vector2(_rd.points[i].x - _rd.points[j].x,
					_rd.points[i].z - _rd.points[j].z).length()
			if d < gap:
				gap = d
	_ck("两条相隔半圈的支路真的在交叉点重合（%.3fm）" % gap, gap < 1.0)
	_ck("交叉点就在 (0, ?, 43) 附近（%.1f, %.1f）" % [cp.x, cp.z],
			cp.x * cp.x + (cp.z - 43.0) * (cp.z - 43.0) < 4.0)

	# 2.2 不压沥青。这是落点判据本身（_road_clearance），回归重算一遍而不是
	#     只读它报出来的数——落点算法改了而这个数没跟着改，回归要能看见。
	var mp: Vector3 = _mark.mark_position
	var here := Vector2(mp.x, mp.z)
	var road_d := _nearest_road_dist(here)
	_ck("碑不压沥青（离整条中心线 %.1fm）" % road_d, road_d > 9.0)
	_ck("落点余量是重算出来的，不是自报的那份", absf(road_d - float(_mark.road_clearance)) < 0.01,
			"重算=%.3f 自报=%.3f" % [road_d, float(_mark.road_clearance)])

	# 2.3 不糊在驿站上
	var st_min := 1e9
	for st in _world._stations:
		st_min = minf(st_min, Vector2(st.position.x, st.position.z).distance_to(here))
	_ck("碑离最近的驿站 %.1fm" % st_min, st_min >= 16.0)

	# 2.4 **人停得到它跟前**。这一条是这块碑最容易变成布景的方式：
	#     `_apply_boundary_force` 的推力是 12 × (d-12)/13，而车的油门是 8——
	#     推力一旦压过油门，车就被钉在原地、速度 15m/s 而距离一寸不变
	#     （实测 27.1m 处两股力精确抵消，那正是 play_newcomer 卡住的原因）。
	#     玩家要能停在碑旁边两米处读它，所以"碑在 16m"还不够，
	#     那个位置上的推力必须远小于油门。
	var player_d := road_d - 2.0
	var over := maxf(player_d - SOFT_BOUND, 0.0)
	var push := PUSH_STRENGTH * clampf(over / (HARD_BOUND - SOFT_BOUND), 0.0, 1.0) \
			+ maxf(over - (HARD_BOUND - SOFT_BOUND), 0.0) * 1.5
	_ck("人停在碑前两米（离中心线 %.1fm）没有推力" % player_d, player_d <= SOFT_BOUND + 0.001,
			"推力 %.1f m/s" % push)
	_ck("停在那儿推力远小于油门（推 %.2f / 油门 %.1f）" % [push, PLAYER_ACCEL],
			push < PLAYER_ACCEL * 0.5)

	# ---- 3. 正面朝交叉点，从交叉点看得见，且没被行道树挡死 ----
	# 这里不能照抄 RoadSteles 的"朝向不是按世界原点算的"：8 字的交叉点恰好
	# 就是环的中心 (0, 43)，于是"朝交叉点"和"朝 (0,43)"是同一句话，差值恒为
	# 0°，那条断言在这块碑上永远是绿的——一个量不到东西的判据比没有更坏。
	# 也不能改成"朝最近那段路"：碑落在上环两条臂之间的缺口里，离它最近的是
	# 12.7m 外的一段沥青，而真正会停下来读这块碑的人是**骑到交叉点上的那个**
	# （全世界只有那儿能一眼看完整条路）。所以正面朝交叉点。
	#
	# 法线有**两个**自由度，量它们要两把尺子，混用会各自造出一个假结果：
	#  · 朝向（yaw）量它落在 XZ 上的**投影**：碑面后仰 40°，完整法线本身就带
	#    0.64 的 Y 分量，拿它去点水平方向，dot 恒等于 cos(40°)=0.766，
	#    卡 0.95 就成了永远红的断言。
	#  · "字在不在正面那一侧"必须用**完整三维**法线：题字在面局部坐标里比
	#    石板低 1.24m，而法线朝上仰着，投到 XZ 上会把那 1.24m 折成
	#    -0.79 —— 一个由量法本身造出来的假失败（实测读到 -0.71）。
	var fwd := Vector3.ZERO
	if slab != null:
		fwd = slab.global_transform.basis.z.normalized()
		var yaw := Vector2(fwd.x, fwd.z).normalized()
		var want2 := (Vector2(cp.x, cp.z) - here).normalized()
		_ck("碑面朝交叉点（水平 dot=%.3f）" % yaw.dot(want2), yaw.dot(want2) > 0.95)
		# 字得刻在正面那一侧，别浮在石板的侧棱上（RoadSteles 第 4 节那一条）。
		if label is Label3D:
			var depth: float = (label.global_position - slab.global_position).dot(fwd)
			_ck("题字在石板正面那一侧（沿法线偏 %.2fm）" % depth, depth > 0.05)
			_ck("题字贴在石板上（沿法线偏 %.2fm）" % depth, depth < 0.25)
		# 3.3 **从交叉点看得见**。这是这块碑最容易变成布景的方式：树排沿着
		#     中心线外 9.5~12.5m 一条带子种，而碑离最近沥青 12.7m —— 正好在
		#     树的带子里。量的是"从交叉点到碑心"这条线段上有没有树，
		#     不是"碑离最近的树多远"（离得近也可能在视线的另一侧）。
		var trees: Array = []
		if _world._tree_scatter != null:
			trees = _world._tree_scatter._trees
		var blockers: Array = []
		for t in trees:
			var tp: Vector3 = t["pos"]
			if _seg_dist(Vector2(tp.x, tp.z), Vector2(cp.x, cp.z), here) < 2.5:
				blockers.append(tp)
		_ck("从交叉点到碑的视线没被行道树挡住（挡住的 %d 棵，共 %d 棵）"
				% [blockers.size(), trees.size()], blockers.is_empty())

	# ---- 4. 碑面立在石台上、**一截都没有被石台吃掉**，且高度在人眼附近 ----
	if face != null:
		var tilt := rad_to_deg(absf(face.rotation.x))
		# 判据不是"倾角够不够仪式感"，是**站着的人读不读得到**。原来的
		# 20°~60° 那条守着的是"要后仰"，而它和"要读得清"是打架的：
		# 一个 1.94m 的面后仰 40° 竖直跨度只剩 1.49m，为了不埋进石台就得
		# 整体抬高一米多，碑顶顶到 2.9m——仰头那一刻正好看到石板的一条窄边。
		# 14° 是"立着的碑"那一档：心在 1.49m、眼在 1.6m，正对着人看。
		_ck("碑面后仰 %.0f°（立着读得清，不是躺着的）" % tilt,
				tilt > 5.0 and tilt < 25.0)
	_ck("碑坐在地上（y=%.2f）" % mp.y,
			absf(mp.y - _world._terrain_builder.get_height_at(mp.x, mp.z)) < 0.01)

	# 4.1 **站在碑前的人读得到哪一段**——这一条量的是"离石台顶多高"，
	#     而**不是**离地多高。原来的 4.1 只问 y=0，于是 0.95m 的石台
	#     把 0.79m 的石板和整行题字一起吃掉了：图上是一个闭环加一条尾巴
	#     （下瓣被石台沿切掉），题字一个字没有，而包围盒、刻线对拍、
	#     面朝向**全部照绿**——没有任何一条问过"它在不在石台顶上面"。
	#     石台才是碑面下沿的地面：题字、刻线下半段量的是同一个量。
	if slab != null and label != null:
		var plinth: float = float(CrossingMarkRef.PLINTH_H)
		var lift: float = float(CrossingMarkRef.face_lift())
		var half_h: float = float(CrossingMarkRef.FACE_H) * 0.5
		_ck("石板下沿高过石台顶 %.2fm（不是架在石头里）"
				% (lift - half_h * cos(deg_to_rad(float(CrossingMarkRef.FACE_TILT_DEG)))
				- 0.11 * sin(deg_to_rad(float(CrossingMarkRef.FACE_TILT_DEG))) - plinth),
				lift - half_h * cos(deg_to_rad(float(CrossingMarkRef.FACE_TILT_DEG)))
				- 0.11 * sin(deg_to_rad(float(CrossingMarkRef.FACE_TILT_DEG))) > plinth)
		_ck("题字离石台顶 %.2fm（站在地上读得到）"
				% (float(CrossingMarkRef.local_height(lift, float(CrossingMarkRef.TEXT_Y)))
				- plinth),
				float(CrossingMarkRef.local_height(lift, float(CrossingMarkRef.TEXT_Y))) - plinth > 0.20)
		# 碑面心落在站着的人的眼前：玩家眼高 1.6m，心差过 ±0.35m 就不是
		# "正对着人看"了——低了他得低头，高了他得仰头。
		# `lift` 已经是**离碑座**的高度（碑座坐在地形上），别再减一次 mp.y：
		# 减了两次就等于把地形高度减两遍，断言会自己红给自己看。
		_ck("碑面心离地 %.2fm（人眼 1.6m 那一档）" % lift, absf(lift - 1.6) < 0.35)
		_ck("碑面顶端离地 %.2fm（不用仰头）"
				% (lift + half_h * cos(deg_to_rad(float(CrossingMarkRef.FACE_TILT_DEG)))),
				lift + half_h * cos(deg_to_rad(float(CrossingMarkRef.FACE_TILT_DEG))) < 2.6)

	# 4.2 **刻线不是背面**。这一条量的是"从碑正面看过去，刻线的正面朝着你"。
	#     第一版把 quad 逆时针发出去（Godot 的正面是顺时针），于是整条刻线
	#     全是背面、从正面看是一片空白石板——而带子、顶点朝向、包围盒、段数、
	#     逐点对拍全部正常。headless 一处都不红，只有图能判，所以这里补一条
	#     纯算术的：正面法线朝向相机，而不是背对。
	if trace is MeshInstance3D and trace.mesh != null and slab != null:
		var arrays: Array = trace.mesh.surface_get_arrays(0)
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_ck("刻线带法线（%d 个）" % norms.size(), norms.size() == verts.size() and norms.size() > 0)
		if norms.size() > 0:
			var n0: Vector3 = norms[0]
			_ck("刻线法线是 +Z（正面朝着碑前那个人，%.2f, %.2f, %.2f）"
					% [n0.x, n0.y, n0.z], n0.z > 0.9)

	# ---- 5. 刻线刻的真是这条路，而且刻出来是个 8 ----
	# 5.1 刻线不是空的、不是一条线
	var tb: Rect2 = _mark.trace_bounds
	_ck("刻线有面积（%.0f×%.0f cm）" % [tb.size.x * 100.0, tb.size.y * 100.0],
			tb.size.x > 0.3 and tb.size.y > 0.3)
	# 5.1b **刻线整条都在石板里**。原来这条写的是 `> -1.6 / <= 1.6`，
	# 而碑面才 2.4 高——那个上界比面还宽，于是**下瓣掉进石台里被切掉**
	# 这一件事它一次都没报过。这里按面高取界，四条边各自留 1cm。
	var hw: float = float(CrossingMarkRef.FACE_W) * 0.5 - 0.01
	var hh: float = float(CrossingMarkRef.FACE_H) * 0.5 - 0.01
	_ck("刻线整条都在石板之内（面 %.2f×%.2f）"
			% [CrossingMarkRef.FACE_W, CrossingMarkRef.FACE_H],
			tb.position.x > -hw and tb.end.x < hw
			and tb.position.y > -hh and tb.end.y < hh)
	# 5.1c 刻线不能被石台切。包围盒在面之内**不等于**看得见——石台是
	# 一块 1.4m 深的实心石头，面上任何低于它顶面的东西都在石头里面。
	var plinth2: float = float(CrossingMarkRef.PLINTH_H)
	var lift2: float = float(CrossingMarkRef.face_lift())
	_ck("刻线下沿离石台顶 %.2fm（整个 8 都露在外面）"
			% (float(CrossingMarkRef.local_height(lift2, tb.position.y)) - plinth2),
			float(CrossingMarkRef.local_height(lift2, tb.position.y)) - plinth2 > 0.15)
	# 一条线的 aspect 会趋于无穷；一个 8 是接近正方形的。
	var aspect: float = tb.size.x / maxf(tb.size.y, 0.001)
	_ck("刻线不是一条线（长宽比 %.2f）" % aspect, aspect > 0.4 and aspect < 2.5)

	# 5.2 **这才是「是个 8」的可量版本**，但要量**刻出来的那两条瓣**而不是源头
	#     那两条（见 5.3：量源头的版本在刻线换成一个圆时全绿）。
	var n: int = _rd.points.size()

	# 5.3 **刻线刻的真的是这条路**——从网格顶点反推，而不是从源数据推。
	#     这是本节第一版的盲区：原来那两条量的是 `_rd.points` 本身
	#     （"这条路是不是个 8"），量的是数据、不是碑；而顶点数那条又是
	#     无标度的——把刻线换成一个圆，顶点数一模一样（966），
	#     于是把"图上刻着一个圆、世界里是个 8"这个**这块碑唯一不能出的错**
	#     全绿放过去了。已做变异验证确认。
	#     判据：把网格里逐段的中心点，和中心线同样采样得到的点，
	#     各自按自己的包围盒归一化到 [0,1]，再逐点比。
	#     相似变换（平移 + 等比缩放 + 上下翻转）正是刻线做的事，
	#     归一化把它消掉，剩下的就是形状差。
	var step: int = maxi(1, int(float(n) / float(CrossingMarkRef.TRACE_SAMPLES)))
	var segs := _engraved_polyline(trace)
	_ck("刻线是按采样生成的带子（%d 段 / %d 顶点）" % [segs.size(),
			0 if trace == null or trace.mesh == null else trace.mesh.surface_get_array_len(0)],
			segs.size() > 100)
	if segs.size() > 100:
		# 段数必须对得上采样步长，否则"逐点比"比的是错位的两条线。
		_ck("刻线的段数就是环路按 TRACE_SAMPLES 采出来的那个数（%d）" % segs.size(),
				absi(segs.size() - int(ceil(float(n) / float(step)))) <= 1)
		var eng := _normalised(segs)
		var road := _normalised(_sample_centreline(step))
		_ck("两条线的点数一样", eng.size() == road.size(),
				"刻线 %d / 路 %d" % [eng.size(), road.size()])
		if eng.size() == road.size() and eng.size() > 100:
			# 两种朝向都试，取好的那个。`_to_face()` 里写的是 `-(p.z - mid.y)`，
			# 也就是刻线相对世界 z 上下翻了一次——那是"面朝着路"这个约定带来的
			# 取舍，不是缺陷。**固定只比一种朝向的话，这一条会在正常产品上红**
			#（实测最大差 1.0001 = 整个单位方框的边长，正是翻转的指纹），
			# 而放宽成"随便怎么对都行"又会把形状差一起放过去。
			# 归一化已经消掉了平移和等比缩放，剩下只许翻转这一个自由度。
			var worst := INF
			var flipped := false
			for f in [false, true]:
				var w := 0.0
				for i in range(eng.size()):
					var r: Vector2 = road[i]
					if f:
						r.y = 1.0 - r.y
					w = maxf(w, eng[i].distance_to(r))
				if w < worst:
					worst = w
					flipped = f
			_ck("刻线归一化后和环路逐点重合（最大差 %.4f%s）" % [
					worst, "，上下翻转" if flipped else ""], worst < 0.005)
			# 5.2 换成量**刻出来的那两条**瓣，而不是源头那两条。
			#     量源头的版本在 5.3 存在时是多余的：5.3 一旦红了就说明
			#     刻线和路已经不是同一件事了，源头的形状再对也没用。
			var eh: int = int(eng.size() / 2)
			var ex := _span(eng, 0, eh)
			var fx := _span(eng, eh, eng.size())
			var ez := _span(eng, 0, eh, true)
			var fz := _span(eng, eh, eng.size(), true)
			var ov := minf(ex.y, fx.y) - maxf(ex.x, fx.x)
			_ck("**刻出来的**两个瓣横向交叠 %.2f" % ov, ov > 0.15)
			_ck("**刻出来的**两个瓣只在交叉点相接（纵向交叠 %.3f）"
					% (minf(ez.y, fz.y) - maxf(ez.x, fz.x)),
					minf(ez.y, fz.y) - maxf(ez.x, fz.x) < 0.02)

	_finish()


## 从刻线网格里反推中心线：一个 quad 是 6 个顶点、沿路按段序排列。
##
## 取的是**这 6 个顶点的重心**，而它恰好精确等于该段两端的中点：
## 带子的四个角是 (pa+n, pa−n, pb+n, pb−n)，每个出现两次，于是
## `(2(pa+n) + 2(pa−n) + 2(pb+n) + 2(pb−n)) / 6 = (pa+pb)/2` ——
## 笔宽那一项自己消掉了。
##
## 写成重心而不是"取 v[6k] 和 v[6k+2]"是有原因的：后者**把缠绕方向写死
## 在下标里**了，而缠绕方向正是这个文件修过的一个 bug（Godot 正面顺时针）。
## 改完缠绕那一刻，逐点对拍的残差从 0.0000 跳到 0.0171——**产品一个数都没
## 变，是量法跟着变了**，而 0.02 的阈值差一点就被这个噪声顶穿。
## 重心这个写法对两种缠绕都成立，所以它量的是产品而不是量法。
func _engraved_polyline(trace: MeshInstance3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if trace == null or trace.mesh == null:
		return out
	var arrays: Array = trace.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return out
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var i := 0
	while i + 5 < verts.size():
		var c := Vector3.ZERO
		for k in range(6):
			c += verts[i + k]
		out.append(Vector2(c.x / 6.0, c.y / 6.0))
		i += 6
	return out


## 环路按同样步长取每段的**中点**，和上面那条逐点对拍。
func _sample_centreline(step: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = _rd.points.size()
	var i := 0
	while i < n:
		var a: Vector3 = _rd.points[i]
		var b: Vector3 = _rd.points[(i + step) % n]
		out.append(Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5))
		i += step
	return out


## 归一化到 [0,1]²（按自己的包围盒）。刻线做的是相似变换，
## 归一化把它消掉——剩下的差就是形状差，那才是要断的东西。
func _normalised(src: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if src.is_empty():
		return out
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in src:
		lo = lo.min(p)
		hi = hi.max(p)
	var d := hi - lo
	d.x = maxf(d.x, 1e-6)
	d.y = maxf(d.y, 1e-6)
	for p in src:
		out.append((p - lo) / d)
	return out


## [from, to) 这一段在某轴上的范围。y_axis = true 时量 y（世界 z）而不是 x。
func _span(src: PackedVector2Array, from: int, to: int, y_axis: bool = false) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in range(from, to):
		var v: float = src[i].y if y_axis else src[i].x
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(lo, hi)


func _finish() -> void:
	if _backup != "":
		var wf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(_backup)
			wf.close()
	print("\n[verify_crossing_mark] OK %d / FAIL %d" % [_oks, _fails.size()])
	for f in _fails:
		print("    FAIL: ", f)
	print("[verify_crossing_mark] %s" % ("PASS" if _fails.is_empty() else "FAIL"))
	quit(0 if _fails.is_empty() else 1)
