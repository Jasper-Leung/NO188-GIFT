extends SceneTree
## verify_home_base.gd — 主角的家（scripts/HomeBase.gd）的回归
##
## 这一族守的是一件**画面上极容易坏、而数字上看不出来**的事：一栋房子如果
## 悄悄挪了位置、或者干脆没建出来，**顶栏、小地图、脚下的圈、16 座驿站的
## 数量**全都照绿——玩家只是"路上少了一栋房子"，而叙事上「出门 → 回家」
## 的那一半就悬空了。所以这里量的不是"代码里有没有那个节点"，而是**从
## 世界的真实数据重新算一遍落点合不合法**：road_data 的 16 座站、地形高度、
## 行道树表、路碑表、玩家的挡车半径，全部重新算一遍，不信 `HomeBase`
## 自己报回来的数。
##
## 十一节，各自盯一件会悄悄坏掉的事：
##   1  落点合法（广场 / 驿站 / 高程 / 四角平不平，全部**重算**）
##   2  房子真的建出来了（逐个节点名——属性名写错会让 GDScript 在运行时
##      中止 `_build_house()`，后面那些子节点一个都没 add_child）
##   3  门朝着路（不是朝着世界原点——8 字环的中心在 (0, 43)）
##   4  两份常量不许漂（门牌字号 / 到家半径）
##   5  行道树让开这块地（**带正对照**：那一片真的种着树）
##   6  离路碑够远（这一条是事后量的，见 HomeBase.CLEAR_OF_STELE）
##   7  玩家不许骑进屋子里（**带正对照**：圈外的人不许被推）
##   8  **被推出去之后还骑得到**——家和驿站不同，驿站背后有 15m 的打卡圈
##      撑着，家背后没有；推出点离中心线一旦超过 `SOFT_BOUND`，边界力与
##      挡车墙在同一点上对拉（CLAUDE.md「推出和回弹的先后会互相抵消」）
##   9  **不许变成第 17 座驿站**（`verify_stations` / `verify_story` 各有一条
##      断言全工程恰好 16 座，这里再钉一次是因为家是这一轮新加的东西）
##  10 小地图上那枚钉
##  11 「到家」那一句是**边沿触发**（停着不重弹、出去再进才又来一次）
##
## 第 4 / 5 / 6 / 7 节的数值全部从 `HomeBase.get_script_constant_map()` 现读，
## 不在本文件里手抄一份——手抄的常量会长出第二套预算（CLAUDE.md 第五轮 ③）。

## 只用来读**常量**（`HOME_LABEL_FONT_PX` / `CLEAR_OF_STELE` 那几处），
## 不用它去调 `get_script_constant_map()`——那是实例方法，拿类名直接调会报
## "Cannot call non-static function ... directly"。常量一律走下面运行中那个
## 实例现读。
const HomeBaseRef = preload("res://scripts/HomeBase.gd")

## 断言条数下限。**这一条是替整份回归兜底的**：`_run()` 里任何一节抛异常，
## 被 await 的协程不会把异常往上抛，剩下的节照跑、汇总照样打
## 「PASS 失败 0」——而一整节断言一行没跑，报告却全绿
## （CLAUDE.md 陷阱清单里那两条同族）。所以条数钉一个下限在末尾。
const HOME_MIN_CK := 34

## House 底下必须真的存在的节点名。少一个就是 `_build_house()` 中途抛了。
## 少一个节点时其余所有断言照样全绿——房子只是"缺了一扇窗"。
const HOUSE_CHILDREN := ["Plinth", "Wall", "Beam0", "Beam1", "Roof0", "Roof1",
		"Chimney", "Door", "WinF0", "WinF1", "WinS0", "WinS1", "Plate"]

var _fails := 0
var _ck_total := 0
var _gm: Node = null
var _world: Node = null
var _loc: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	_ck_total += 1
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _ensure_autoloads() -> void:
	for n in {"GameManager": "res://scripts/GameManager.gd",
			"AudioManager": "res://scripts/AudioManager.gd",
			"Localization": "res://scripts/Localization.gd"}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_gm._clear_save()
	_gm.headless_mode = true
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	_loc = root.get_node("Localization")
	root.size = Vector2i(1280, 720)
	# 世界**直接拿在手里**，不去 `get_children()` 里认：认错一个节点的话
	# `_run()` 里那句 `_world._home` 会在协程里抛异常，而被 await 的协程
	# 不会把异常往上抛——SceneTree 挂死不退出，一行断言都没打过。
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	_run.call_deferred()


func _world_built() -> bool:
	# 写成独立函数而不是多行 lambda：GDScript 的 lambda 里换行要显式续行，
	# 漏一个就是 Parse Error，而 Parse Error 发生在**加载时**——`quit()` 永远
	# 走不到，整份回归一行断言都没打过。
	return _world.get_node_or_null("RoadSteles") != null and _world._home != null


func _run() -> void:
	await process_frame
	await process_frame
	print("=== verify_home_base ===")
	# 世界建完没有：`_ready()` 里那一大串（草皮 / 行道树 / 路碑）跑完才算。
	# 不等的话量到的是一个半成品，而"半成品"会长得像"家没建出来"。
	await _until(_world_built, "世界建完（RoadSteles + HomeBase 都在）", 120000)
	if _world._home == null or not _world._home.placed:
		_ck("家建起来了（选址没有失败）", false, "HomeBase 没就位")
		_report()
		return

	var home: Node3D = _world._home
	var rd = _world._road_builder.get_road_data()
	var tb: Node3D = _world._terrain_builder
	# `get_script_constant_map()` 是实例方法，拿类名直接调会报
	# "Cannot call non-static function ... directly"。而**用运行中那个实例**
	# 比用类更好：量的是这一趟真的在跑的那份脚本，不是磁盘上另一份副本。
	var HC: Dictionary = home.get_script().get_script_constant_map()
	var tc: Dictionary = _world._tree_scatter.get_script().get_script_constant_map()

	_section1_site(home, rd, tb, HC)
	_section2_nodes(home)
	_section3_facing(home)
	_section4_constants(HC)
	_section5_trees(home, tc)
	_section6_steles(home)
	await _section7_keepout(home, rd, HC)
	await _section9_not_a_station(rd)
	_section10_minimap(home)
	_section11_pass_line(home)

	_ck("整份回归真的跑完了（断言条数 ≥ %d，缺一节的话这里会红）" % HOME_MIN_CK,
			_ck_total >= HOME_MIN_CK, "实际 %d 条" % _ck_total)
	_report()


func _report() -> void:
	print("\n[verify_home_base] %s  (断言 %d，失败 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _ck_total, _fails])
	_gm._clear_save()
	quit(0 if _fails == 0 else 1)


func _until(cond: Callable, what: String, ms: int = 120000) -> void:
	var t := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < t:
		if cond.call():
			return
		await process_frame
	push_error("[verify_home_base] 等不到：" + what)


# ---------------------------------------------------------------- 1 落点
## 落点合不合法，**从世界的数据重算一遍**，不信 HomeBase 自己报回来的数。
func _section1_site(home: Node3D, rd, tb: Node3D, HC: Dictionary) -> void:
	print("\n-- 1 落点合法（重算，不信 HomeBase 的返回值）--")
	_ck("家建起来了（选址没有失败）", home != null and home.placed,
			"placed=%s" % (str(home.placed) if home != null else "null"))
	if home == null or not home.placed:
		return
	var site: Vector3 = home.site
	var p := Vector2(site.x, site.z)
	var cross := Vector2(rd.points[0].x, rd.points[0].z)
	_ck("离 8 字自交点那块广场 ≥ %.0fm（PLAZA_CLEAR）" % HC["PLAZA_CLEAR"],
			p.distance_to(cross) >= float(HC["PLAZA_CLEAR"]),
			"%.1fm" % p.distance_to(cross))

	var near_st := 1e9
	for st in _world._stations:
		near_st = minf(near_st, Vector2(st.position.x, st.position.z).distance_to(p))
	_ck("离最近一座驿站 ≥ %.0fm（CLEAR_OF_STATION）" % HC["CLEAR_OF_STATION"],
			near_st >= float(HC["CLEAR_OF_STATION"]), "%.1fm" % near_st)

	var y: float = tb.get_height_at(p.x, p.y)
	_ck("落点真的是贴在地形上的（site.y == 地面高）", absf(y - site.y) < 0.05,
			"site.y=%.3f 地形=%.3f" % [site.y, y])
	_ck("地面高程 ≥ %.1fm（不在水里、不在被 clamp 出来的平地上）" % HC["MIN_GROUND"],
			y >= float(HC["MIN_GROUND"]), "%.2fm" % y)

	var hw: float = HC["HALF_W"]
	var hd: float = HC["HALF_D"]
	var flat := 0.0
	for c in [Vector2(hw, hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(-hw, -hd)]:
		flat = maxf(flat, absf(float(tb.get_height_at(p.x + c.x, p.y + c.y)) - y))
	_ck("房子四角高差 ≤ %.1fm（FLAT_MAX，墙竖着才站得住）" % HC["FLAT_MAX"],
			flat <= float(HC["FLAT_MAX"]), "%.2fm" % flat)

	var d_road := _dist_to_polyline(p, rd.points)
	_ck("离中心线 ≈ %.0fm（HOME_OFFSET；推出点还要留在 SOFT_BOUND 内，见第 8 节）"
			% HC["HOME_OFFSET"], absf(d_road - float(HC["HOME_OFFSET"])) < 0.6,
			"%.2fm" % d_road)
	# **下面两条才是 HOME_OFFSET 真正的门槛**，上面那条只量"落点与常量一致"。
	#
	# 写成「实测 == 常量」的话，改常量会把尺子一起搬走——第一版就是这么写的，
	# 于是把 15.0 调回 11.0（也就是 `RoadSteles` 自己记着的那个和行道树打架的
	# 那个数）之后，**这一族 49 条全绿**：房子横跨 8.0~14.0m，而
	# `RoadVerge` 在 `SOFT_BOUND`(12.0m) 刷的那道粉线会从屋子正中间穿过去，
	# 玩家读到的是"骑到这里就骑不动了"，而线的另一边就是家。
	# 判据要问的是那个**产品上的后果**，不是"落点与常量对得上"。
	var near_edge := d_road - float(HC["HALF_D"])
	_ck("房子靠路那一沿在 SOFT_BOUND(%.0fm) 之外（那道粉线不许从屋子里穿过去）"
			% float(_world.SOFT_BOUND), near_edge >= float(_world.SOFT_BOUND),
			"近沿 %.2fm" % near_edge)
	var keep_r: float = sqrt(float(HC["HALF_W"]) * float(HC["HALF_W"])
			+ float(HC["HALF_D"]) * float(HC["HALF_D"])) + float(HC["KEEPOUT_PAD"])
	_ck("被推出之后玩家仍在「到家」那一圈里（门真的骑得到）",
			d_road - keep_r <= float(_world.HOME_PASS_RADIUS),
			"推出后距家 %.2fm vs HOME_PASS_RADIUS %.1fm"
			% [d_road - keep_r, _world.HOME_PASS_RADIUS])
	_ck("正对照：房子没有远到骑不到（满油门平衡点约 20.7m）",
			d_road < 20.0, "离中心线 %.2fm" % d_road)


# ---------------------------------------------------------------- 2 节点
func _section2_nodes(home: Node3D) -> void:
	print("\n-- 2 房子真的建出来了（逐个节点名）--")
	_ck("HomeBase 底下有 House 节点", home != null and home.get_node_or_null("House") != null)
	if home == null or home.get_node_or_null("House") == null:
		return
	var house: Node3D = home.get_node("House")
	var missing: Array = []
	for n in HOUSE_CHILDREN:
		if house.get_node_or_null(n) == null:
			missing.append(n)
	_ck("13 个子节点一个都不缺（缺一个 = _build_house 中途抛了）",
			missing.is_empty(), "缺 " + str(missing))
	var plate: Label3D = house.get_node_or_null("Plate")
	_ck("门牌是 Label3D（headless 下不生成字形，字有没有画出来只有定妆照能判）",
			plate != null)
	if plate == null:
		return
	_ck("门牌上真的写着译好的文案（不是 key 自己 —— t() 查不到会返回 key）",
			plate.text != "" and plate.text != "home_name", "text=%s" % plate.text)
	# 字号是个**乘积**：font_size × pixel_size 折成米，玩家在 18m 上读到的是
	# 它。盯住任何一个因子都量不到玩家读到的那行字有多高（CLAUDE.md「字高是个
	# 乘积」）。所以这两条量的是乘积本身，以及它和驿站牌是不是同一档。
	# 两个因子**分开写两条**：写成一条 `and` 时，红了只告诉你"两个里有一个不对"，
	# 而这一族的病正是"一个因子各写一份"。
	_ck("门牌 pixel_size 走的是常量（不是又一个字面量）",
			is_equal_approx(plate.pixel_size, float(HomeBaseRef.HOME_LABEL_PIXEL_SIZE)),
			"%.5f vs %.5f" % [plate.pixel_size, float(HomeBaseRef.HOME_LABEL_PIXEL_SIZE)])
	_ck("门牌 font_size 走的是常量（不是又一个字面量）",
			plate.font_size == int(HomeBaseRef.HOME_LABEL_FONT_PX),
			"%d vs %d" % [plate.font_size, int(HomeBaseRef.HOME_LABEL_FONT_PX)])
	_ck("门牌和驿站牌同一档（家和驿站是玩家一路上并排看到的两块牌子）",
			is_equal_approx(plate.pixel_size, float(_world.STATION_LABEL_PIXEL_SIZE))
					and plate.font_size == int(_world.STATION_LABEL_FONT_PX),
			"家 %.4f×%d vs 站 %.4f×%d" % [plate.pixel_size, plate.font_size,
					_world.STATION_LABEL_PIXEL_SIZE, _world.STATION_LABEL_FONT_PX])
	var h_m: float = float(plate.font_size) * float(plate.pixel_size)
	_ck("门牌折成米之后还够一行字（≤0.30m 就是一块看不清的小木牌）",
			h_m > 0.30 and h_m < 1.0, "%.3fm" % h_m)


# ---------------------------------------------------------------- 3 朝向
func _section3_facing(home: Node3D) -> void:
	print("\n-- 3 门朝着路（不是朝着世界原点）--")
	if home == null or not home.placed or home.get_node_or_null("House") == null:
		return
	var house: Node3D = home.get_node("House")
	var to_road := Vector2(home.road_pt.x, home.road_pt.y) - Vector2(home.site.x, home.site.z)
	if to_road.length() < 1e-6:
		_ck("门朝着路", false, "road_pt 与落点重合，朝向无从算起")
		return
	# 门是局部 +Z 那一片（`Door` / `WinF*` / `Plate` 全在 +Z），所以量的是
	# 房子那根局部 +Z 轴在水平面上的投影。
	var fwd := Vector2(sin(house.rotation.y), cos(house.rotation.y))
	var dot := fwd.normalized().dot(to_road.normalized())
	_ck("门正面对着路（局部 +Z 与「房子→路」的方向一致）", dot > 0.99,
			"点积 %.4f，旋转 %.1f°" % [dot, rad_to_deg(house.rotation.y)])


# ---------------------------------------------------------------- 4 常量
func _section4_constants(HC: Dictionary) -> void:
	print("\n-- 4 两份常量不许漂 --")
	_ck("门牌字号折成米 == World3D.STATION_LABEL_PIXEL_SIZE（两处各写一份会长出两套）",
			is_equal_approx(float(HC["HOME_LABEL_PIXEL_SIZE"]),
					float(_world.STATION_LABEL_PIXEL_SIZE)),
			"HomeBase %.4f vs World3D %.4f" % [HC["HOME_LABEL_PIXEL_SIZE"],
					_world.STATION_LABEL_PIXEL_SIZE])
	_ck("门牌字号 == World3D.STATION_LABEL_FONT_PX（pixel_size 对上了、字号没对上，"
			+ "两块牌子在屏上仍是两档）",
			int(HC["HOME_LABEL_FONT_PX"]) == int(_world.STATION_LABEL_FONT_PX),
			"HomeBase %d vs World3D %d" % [HC["HOME_LABEL_FONT_PX"],
					_world.STATION_LABEL_FONT_PX])
	_ck("到家半径 == World3D.HOME_PASS_RADIUS（同一个数必须只存在一份）",
			is_equal_approx(float(HC["PASS_RADIUS"]), float(_world.HOME_PASS_RADIUS)),
			"HomeBase %.1f vs World3D %.1f" % [HC["PASS_RADIUS"], _world.HOME_PASS_RADIUS])


# ---------------------------------------------------------------- 5 行道树
func _section5_trees(home: Node3D, tc: Dictionary) -> void:
	print("\n-- 5 行道树让开这块地 --")
	if home == null or not home.placed:
		return
	var trees: Array = _world._tree_scatter.trees()
	# **正对照先摆**：树表是空的，那"没有一棵树靠近家"恒真，而它量的是空气。
	_ck("树表不是空的（正对照：这一带真的种着树）", trees.size() > 40,
			"%d 棵" % trees.size())
	if trees.is_empty():
		return
	var p := Vector2(home.site.x, home.site.z)
	var nearest := 1e9
	var in_band := 0
	var clear_r: float = tc["STATION_CLEAR"]
	for t in trees:
		var d := Vector2(t["pos"].x, t["pos"].z).distance_to(p)
		nearest = minf(nearest, d)
		if d > clear_r and d < 25.0:
			in_band += 1
	_ck("没有一棵树长在 %.0fm 里（STATION_CLEAR > 房子半对角线 5.0m）" % clear_r,
			nearest >= clear_r, "最近 %.1fm" % nearest)
	_ck("让位圈之外那一带仍然有树（正对照：让开的是一块地，不是一整片空白）",
			in_band > 0, "10~25m 内 %d 棵" % in_band)


# ---------------------------------------------------------------- 6 路碑
func _section6_steles(home: Node3D) -> void:
	print("\n-- 6 离路碑够远（选址早于路碑，只能事后量）--")
	if home == null or not home.placed:
		return
	var sp: Array = _world._steles.stele_positions
	_ck("路碑表不是空的（正对照：这一族量的是家与碑的间距，不是碑的个数）",
			sp.size() > 0, "%d 块" % sp.size())
	if sp.is_empty():
		return
	_ck("HomeBase 自己记下的 clear_of_steles 为真", home.clear_of_steles)
	var p := Vector2(home.site.x, home.site.z)
	var nearest := 1e9
	for s in sp:
		nearest = minf(nearest, Vector2(s.x, s.z).distance_to(p))
	_ck("离最近一块碑 ≥ %.0fm（CLEAR_OF_STELE，重算一遍）" % HomeBaseRef.CLEAR_OF_STELE,
			nearest >= HomeBaseRef.CLEAR_OF_STELE, "%.1fm" % nearest)


# ---------------------------------------------------------------- 7/8 挡车
func _section7_keepout(home: Node3D, rd, HC: Dictionary) -> void:
	print("\n-- 7/8 玩家不许骑进屋子里，而且被推出去之后还骑得到 --")
	if home == null or not home.placed:
		return
	var r: float = home.keepout_radius()
	_ck("挡车半径量出来了（不是 0）", r > 0.0, "%.2fm" % r)
	_ck("挡车半径 = 半对角线 + KEEPOUT_PAD（重算，不信返回值）",
			absf(r - (sqrt(float(HC["HALF_W"]) * float(HC["HALF_W"])
					+ float(HC["HALF_D"]) * float(HC["HALF_D"])) + float(HC["KEEPOUT_PAD"]))) < 1e-4,
			"%.3fm" % r)
	if r <= 0.0:
		return
	var p := Vector2(home.site.x, home.site.z)
	var to_road := Vector2(home.road_pt.x, home.road_pt.y) - p
	to_road = to_road.normalized() if to_road.length() > 1e-6 else Vector2(0, 1)

	# 正对照：圈外 3m 的人不许被推。这一条不摆的话，"推出函数压根没被调用"
	# 和"推出太狠"在断言里长得一模一样。
	var out_xz := p + to_road * (r + 3.0)
	_world._player.position = Vector3(out_xz.x, home.site.y, out_xz.y)
	_world._apply_station_keepout()
	var moved := Vector2(_world._player.position.x, _world._player.position.z).distance_to(out_xz)
	_ck("正对照：圈外 3m 的人不会被推（推出没有越界）", moved < 0.01, "动了 %.3fm" % moved)

	# ---- 从路那一侧骑进来（玩家唯一会走的来路）----
	# 这一侧才是"玩家骑得到门口"这件事真正要量的：推出方向朝着路，所以推出点
	# 离中心线 = HOME_OFFSET − r ≈ 8.4m，在 SOFT_BOUND 之内，边界力恰好是 0。
	# 驿站背后有 15m 的打卡圈撑着，墙大一圈也只是够不着；**家背后没有圈**，
	# 所以这一条是它独有的约束。
	var in_xz := p + to_road * 1.0
	_world._player.position = Vector3(in_xz.x, home.site.y, in_xz.y)
	_world._player._speed = 15.0
	_world._apply_station_keepout()
	var got := Vector2(_world._player.position.x, _world._player.position.z)
	var d := got.distance_to(p)
	_ck("骑进屋子里会被摆到墙外（不是留在屋子里）", d >= r - 0.05,
			"停在 %.2fm，半径 %.2fm" % [d, r])
	_ck("撞墙之后车慢下来了（不是贴着墙蹭着走）", _world._player.get_speed() < 15.0,
			"末速度 %.1f" % _world._player.get_speed())
	var d_road := _dist_to_polyline(got, rd.points)
	_ck("从路那侧推进去，推出点仍在 SOFT_BOUND(%.0fm) 里（推出和边界力不许在同一点打架）"
			% float(_world.SOFT_BOUND), d_road <= float(_world.SOFT_BOUND),
			"离中心线 %.2fm" % d_road)
	_ck("正对照：站在推出那一圈上仍然能触发「到家」（玩家真能骑到门口）",
			got.distance_to(p) <= float(_world.HOME_PASS_RADIUS),
			"距家 %.2fm vs HOME_PASS_RADIUS %.1fm"
			% [got.distance_to(p), _world.HOME_PASS_RADIUS])

	# ---- 从房子背面推进去 ----
	# 这一侧玩家正常骑不到（要绕过房子踩草地，而边界力先一步往回推），但
	# 硬推出是**无方向**的：背面推进去会被推到 HOME_OFFSET + r ≈ 21.6m，
	# 那已经越过 SOFT_BOUND。要断的不是"别越界"，而是**越界之后推得回来**：
	# 边界力朝路收，而挡车墙此刻已经满足（正好等于 r），两股力不再对拉。
	_world._player.position = Vector3(p.x - to_road.x * 1.0, home.site.y,
			p.y - to_road.y * 1.0)
	_world._apply_station_keepout()
	var back := Vector2(_world._player.position.x, _world._player.position.z)
	var d_back := _dist_to_polyline(back, rd.points)
	_ck("从背面推进去也推出去了", back.distance_to(p) >= r - 0.05,
			"停在 %.2fm" % back.distance_to(p))
	var before := d_back
	_world._apply_boundary_force(0.05)
	var after := _dist_to_polyline(Vector2(_world._player.position.x,
			_world._player.position.z), rd.points)
	_ck("背面那一点越过了 SOFT_BOUND（记下来：硬推出是无方向的）",
			before > float(_world.SOFT_BOUND), "离中心线 %.2fm" % before)
	_ck("越界之后边界力把人往回路面收（玩家不会被挡在房子背后出不来）",
			after < before - 0.001, "%.2fm → %.2fm" % [before, after])


# ---------------------------------------------------------------- 9 不是驿站
func _section9_not_a_station(rd) -> void:
	print("\n-- 9 不许变成第 17 座驿站 --")
	_ck("世界里仍然恰好 16 座驿站（节点）", _world._stations.size() == 16,
			"%d 座" % _world._stations.size())
	_ck("road_data 里仍然恰好 16 座（数据）", rd.stations.size() == 16,
			"%d 座" % rd.stations.size())
	_ck("家不是 _stations 里的任何一个", _world._stations.find(_world._home) == -1)
	# 真正会坏的那条：家坐在路旁边 15m，而驿站在 18m。**两者离得很近**，
	# 所以「家不冒充驿站」不能靠"离得远"来保证——得证明站到房子跟前时
	# `_nearby_*` 仍然是 -1（不加旅币、不进打卡圈、不能打卡）。
	_world._player.position = _world._home.site
	await process_frame
	await process_frame
	_world._player.position = _world._home.site
	await process_frame
	await process_frame
	var site: Vector3 = _world._home.site
	var nearest := 1e9
	for st in _world._stations:
		nearest = minf(nearest, st.position.distance_to(site))
	_ck("站到房子跟前时没有驿站被认成「到了」（_nearby_station_idx 仍是 -1）",
			_world._nearby_station_idx == -1,
			"got=%d，最近的站 %.1fm" % [_world._nearby_station_idx, nearest])
	_ck("房子也没被认成铺子（_nearby_shop_idx 仍是 -1）",
			_world._nearby_shop_idx == -1, "got=%d" % _world._nearby_shop_idx)


# ---------------------------------------------------------------- 10 小地图
func _section10_minimap(home: Node3D) -> void:
	print("\n-- 10 小地图上那枚钉（据点那一半：玩家随时回得去）--")
	var mm: Control = _world._minimap
	_ck("小地图收到了家", mm != null and mm.has_home)
	if mm == null or not mm.has_home:
		return
	_ck("钉在的就是房子真正的落点", mm.home_site.distance_to(home.site) < 0.01,
			"钉 %.3f vs 落点 %.3f" % [mm.home_site.distance_to(home.site), home.site.y])


# ---------------------------------------------------------------- 11 到家那一句
func _section11_pass_line(home: Node3D) -> void:
	print("\n-- 11 「到家」那一句是边沿触发 --")
	var hud: Control = _world._hud3d
	if home == null or not home.placed or hud == null:
		return
	var p := Vector3(home.site.x, home.site.y, home.site.z)
	var line: String = _loc.t("home_pass_line")
	_ck("到家那一句有文案（不是 key 自己 —— t() 查不到会返回 key）",
			line != "" and line != "home_pass_line", "got=%s" % line)
	_ck("中文那一句不是空的", line.strip_edges() != "")

	# 圈外 → 这一趟调用不该浮。
	#
	# **先按住计时再清空文字**：`show_pass_line` 只是给 `_pass_left` 续命，字是
	# HUD3D 自己按 `PASS_HOLD_SEC` 收走的。所以"屏上现在有没有字"量的是计时器，
	# 不是边沿——第 9 节把车停在家门口的那几帧已经浮过一次，不清干净的话
	# 这条量到的是上一次留下的残字。
	hud._pass_left = 999.0
	hud._pass_label.text = ""
	_world._player.position = p + Vector3(60.0, 0, 0)
	_world._check_home()
	_ck("不在家门口时这一趟调用不浮那一句", hud._pass_label.text == "",
			"got=%s" % hud._pass_label.text)

	# 圈外 → 圈内 → 浮
	_world._player.position = p
	_world._check_home()
	_ck("骑到家门口浮出那一句", hud._pass_label.text == line,
			"got=%s" % hud._pass_label.text)

	# 停在原地不许重弹（否则它会一直悬在屏上盖住别的话）。把计时按住、
	# 文字清空，再调一次——边沿触发的话它什么也不做。
	hud._pass_left = 999.0
	hud._pass_label.text = ""
	_world._check_home()
	_ck("停在家门口不重弹（边沿触发，不是每帧都浮）", hud._pass_label.text == "",
			"got=%s" % hud._pass_label.text)
	hud._pass_left = 0.0

	# 骑开 → 再回来才又来一次。这条真正在断的是"出去之后边沿标志被清了"。
	_world._player.position = p + Vector3(60.0, 0, 0)
	_world._check_home()
	_ck("骑开之后边沿标志跟着清掉", not _world._home_inside)
	_world._player.position = p
	_world._check_home()
	_ck("出去再回来会再浮一次", hud._pass_label.text == line,
			"got=%s" % hud._pass_label.text)
	hud._pass_left = 0.0
	hud._pass_label.text = ""


# ---------------------------------------------------------------- 工具
## 点到闭合折线的最短距离。**逐段**算而不是只比顶点——点落在两段之间时
## 只比顶点会量到一个偏大的数，而这一节的门槛是"SOFT_BOUND 之内"，
## 量偏大就会把一条真的能骑到的落点判成骑不到。
func _dist_to_polyline(p: Vector2, pts: Array) -> float:
	var best := 1e18
	for i in range(pts.size()):
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[(i + 1) % pts.size()].x, pts[(i + 1) % pts.size()].z)
		best = minf(best, _seg_dist(p, a, b))
	return best


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
