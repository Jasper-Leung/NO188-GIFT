extends SceneTree

## 验证 16 个驿站都能正确映射到 model_idx → GLB 配置，且**没有一座压在路面上**。
## headless 可跑：不加载 3D 场景，只检查数据一致性 + 文件存在性 + 布局净空。
## 最后一节用真 GLB 的 AABB 逐驿站量脚底净空，改 GLB 尺寸或改偏移都会被抓住。
##
## 注意：不能用 `var rd: RoadData = RoadData.new()`——class_name 类型注解会在
## 编译期拉 RoadData.gd，而 road_data.gd 引用了 Localization autoload。
## headless `--script` 模式下虽然 project.godot 里注册了 autoload，但 GDScript
## analyzer 在 --script 上下文里对 autoload 解析不可靠，直接报
## "Identifier not found: Localization"。改成运行时 `load(...).new()` 绕开
## 编译期依赖。

const STATION_GLB_CONFIG: Array = [
	{"path": "res://assets/models/station_0.glb", "scale": 10.0, "label_y": 12.0, "glow_y": 8.0, "glow_range": 12.0},
	{"path": "res://assets/models/station_1.glb", "scale": 10.0, "label_y": 10.0, "glow_y": 7.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_2.glb", "scale": 10.0, "label_y": 14.0, "glow_y": 10.0, "glow_range": 15.0, "rot_y": 180.0},
	{"path": "res://assets/models/station_3.glb", "scale": 10.0, "label_y": 10.0, "glow_y": 7.0, "glow_range": 10.0, "rot_y": 180.0},
	{"path": "res://assets/models/station_4.glb", "scale": 10.0, "label_y": 11.0, "glow_y": 8.0, "glow_range": 12.0, "rot_y": -120.0},
	{"path": "res://assets/models/tree.glb", "scale": 8.0, "label_y": 14.0, "glow_y": 10.0, "glow_range": 12.0, "rot_y": 0.0},
	{"path": "res://assets/models/station_驿楼.glb", "scale": 10.0, "label_y": 11.0, "glow_y": 7.0, "glow_range": 14.0},
	{"path": "res://assets/models/station_茶寮.glb", "scale": 10.0, "label_y": 10.0, "glow_y": 7.0, "glow_range": 12.0},
	{"path": "res://assets/models/station_岭台.glb", "scale": 10.0, "label_y": 12.0, "glow_y": 8.0, "glow_range": 14.0},
	{"path": "res://assets/models/station_神苑.glb", "scale": 10.0, "label_y": 9.0, "glow_y": 6.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_凉亭.glb", "scale": 12.0, "label_y": 8.0, "glow_y": 5.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_廊.glb", "scale": 10.0, "label_y": 8.0, "glow_y": 5.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_亭灯.glb", "scale": 14.0, "label_y": 10.0, "glow_y": 6.0, "glow_range": 10.0},
]

## 站名牌那一节的几把尺子（见 `_audit_name_plates()` 的注释）。
## 站心离路心线——和 `road_data.STATION_OFFSET` 一份。
const STATION_OFFSET := 18.0
## `_add_label()` 给有碎片的站用的是 font_size 48，回归按这一档量。
const LABEL_FONT_PX := 48
## 一个字在骑行那一档折到屏上至少要多高。12px 是"认得出是个字"的下限。
const LABEL_MIN_PX := 12

func _ok(msg: String) -> void:
	print("[OK]   ", msg)


func _fail(msg: String) -> void:
	print("[FAIL] ", msg)


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_ok(label)
	else:
		_fail(label + ("（" + detail + "）" if detail != "" else ""))


var _rd = null


## 运行时加载 RoadData.gd 并拿到 stations 数组。
## 不做类型注解，避免编译期解析 class_name → RoadData.gd。
## 顺手把 rd 留在 _rd 上，后面验路面净空还要用它的路径点。
func _load_stations() -> Array:
	var script_res = load("res://scripts/road_data.gd")
	if script_res == null:
		_fail("load('res://scripts/road_data.gd') 返回 null")
		return []
	_rd = script_res.new()
	var arr = _rd.get("stations")
	if arr == null:
		_fail("road_data.stations 为空")
		return []
	return arr


func _initialize() -> void:
	print("[BOOT] verify_stations starting")
	call_deferred("_run")


func _run() -> void:
	print("=== 驿站 → GLB 配置 ===")
	var stations: Array = _load_stations()
	if stations.is_empty():
		print("[ABORT] 拿不到 stations，无法继续")
		quit(1)
		return

	print("    驿站总数 ", stations.size())
	_check("16 个驿站", stations.size() == 16, "实测 %d" % stations.size())

	var model_idxs: Array[int] = []
	for i in range(stations.size()):
		model_idxs.append(int(stations[i].get("model_idx", -1)))
	print("    model_idx ", model_idxs)

	var neg_idxs: Array[int] = []
	for i in range(model_idxs.size()):
		if model_idxs[i] < 0:
			neg_idxs.append(i)
	_check("无 model_idx == -1 的驿站（都是路标 → 已换成真建筑）",
			neg_idxs.is_empty(),
			"缺模型的 idx: " + str(neg_idxs))

	var out_of_range: Array[int] = []
	for i in range(model_idxs.size()):
		if model_idxs[i] >= STATION_GLB_CONFIG.size():
			out_of_range.append(i)
	_check("所有 model_idx 都在 STATION_GLB_CONFIG 范围内",
			out_of_range.is_empty(),
			"越界: " + str(out_of_range))

	var missing: Array[String] = []
	for cfg in STATION_GLB_CONFIG:
		var p: String = str(cfg.get("path", ""))
		if not ResourceLoader.exists(p):
			missing.append(p)
	_check("所有 STATION_GLB_CONFIG 指向的 GLB 都存在于 res://",
			missing.is_empty(),
			"缺: " + str(missing))

	# 每个新 GLB 都能被 load() 且不报错
	var load_err: Array[String] = []
	for i in range(6, STATION_GLB_CONFIG.size()):
		var p: String = str(STATION_GLB_CONFIG[i]["path"])
		var s = load(p)
		if s == null:
			load_err.append(p)
	_check("新加的 7 个 GLB 都能 load 成 PackedScene",
			load_err.is_empty(),
			"load 失败: " + str(load_err))

	# 每个驿站都要有名字（中英）、color、event
	var bad_name: Array[int] = []
	var bad_color: Array[int] = []
	for i in range(stations.size()):
		var s = stations[i]
		if str(s.get("name", "")).is_empty() or str(s.get("name_en", "")).is_empty():
			bad_name.append(i)
		var c = s.get("color", null)
		if c == null or not (c is Color):
			bad_color.append(i)
	_check("每个驿站都有中英文名字", bad_name.is_empty(), "缺: " + str(bad_name))
	_check("每个驿站都有 Color", bad_color.is_empty(), "缺: " + str(bad_color))

	# 5 个碎片驿站仍然存在，且顺序正确
	var frag_stations: Array[int] = []
	for i in range(stations.size()):
		var frag = str(stations[i].get("fragment", ""))
		if frag != "":
			frag_stations.append(i)
	_check("5 个碎片驿站按 idx 顺序 [4, 7, 10, 13, 14]",
			frag_stations == [4, 7, 10, 13, 14],
			"实测: " + str(frag_stations))

	var frag_letters: Array[String] = []
	for i in frag_stations:
		frag_letters.append(str(stations[i].get("fragment", "")))
	# 按驿站 idx 顺序 [4, 7, 10, 13, 14] 提取的碎片字是 [禽, 云, 茶, 琴, 竹]
	# ——FRAGMENT_SLOT_STATION_IDX 里按诗意顺序映射的是 [7, 10, 13, 14, 4]，
	# 但 stations 数组里 4 排在 7 前面，所以直接按驿站 idx 序取字是 [禽, 云, 茶, 琴, 竹]
	_check("碎片字按驿站 idx 序是 [禽, 云, 茶, 琴, 竹]",
			frag_letters == ["禽", "云", "茶", "琴", "竹"],
			"实测: " + str(frag_letters))

	# 11 个标记驿站现在有真建筑（model_idx >= 0）
	var marker_idxs: Array[int] = []
	for i in range(stations.size()):
		if str(stations[i].get("fragment", "")) == "":
			marker_idxs.append(i)
	_check("11 个非碎片驿站", marker_idxs.size() == 11, "实测 %d" % marker_idxs.size())
	var with_model: Array[int] = []
	var missing_model_idx: Array[int] = []
	for i in marker_idxs:
		if model_idxs[i] >= 0:
			with_model.append(i)
		else:
			missing_model_idx.append(i)
	_check("11 个非碎片驿站全部有 GLB 模型", with_model.size() == 11,
			"缺模型的 idx: " + str(missing_model_idx))

	# 旧的"XX 路标"名字应该已经全部换成真建筑名
	var still_marker: Array[String] = []
	for i in range(stations.size()):
		var n = str(stations[i].get("name", ""))
		if n.ends_with("路标"):
			still_marker.append("%d:%s" % [i, n])
	_check("已经没有 XX 路标 这种占位名（全是真建筑名）",
			still_marker.is_empty(),
			"仍在: " + str(still_marker))

	# 15 号（榕树下）保留 tree.glb——语义就是"榕树下"，模型本身就是那棵树
	var idx15_model = model_idxs[15] if model_idxs.size() > 15 else -1
	var idx15_path = "" if idx15_model < 0 else str(STATION_GLB_CONFIG[idx15_model]["path"])
	_check("station 15（榕树下）指向真 GLB 文件",
			idx15_model >= 0 and ResourceLoader.exists(idx15_path),
			"model_idx=%d, path=%s" % [idx15_model, idx15_path])

	# 驿站名字唯一
	var names: Array[String] = []
	var dup: Array[String] = []
	for i in range(stations.size()):
		var n = str(stations[i].get("name", ""))
		names.append(n)
		if names.count(n) > 1:
			dup.append(n)
	_check("驿站名字全不重复", dup.is_empty(), "重复: " + str(dup))

	# 每个驿站 event 都非空（碎片站的 event 是诗意短语，非碎片站的 event 是分类）
	var bad_event: Array[int] = []
	for i in range(stations.size()):
		if str(stations[i].get("event", "")).is_empty():
			bad_event.append(i)
	_check("每个驿站都有 event", bad_event.is_empty(), "缺: " + str(bad_event))

	# ---- 驿站不能压在路面上 ----
	# 用真 GLB 的 AABB（含 scale 和 rot_y）算脚底，逐驿站验证：模型最靠近中心线的
	# 那个角也必须比 TOTAL_HALF_WIDTH 远，否则亭子会架在车道/路肩上。
	# 这是布局硬约束——GLB 换了模型尺寸也会被抓，不能只靠人眼截图。
	var rb_map = load("res://scripts/RoadBuilder.gd").get_script_constant_map()
	var half_w: float = float(rb_map.get("TOTAL_HALF_WIDTH", 6.5))
	var soft_bound: float = float(load("res://scripts/World3D.gd")
			.get_script_constant_map().get("SOFT_BOUND", 12.0))
	var pass_r: float = float(load("res://scripts/World3D.gd")
			.get_script_constant_map().get("STATION_PASS_RADIUS", 15.0))
	var rd_map = load("res://scripts/road_data.gd").get_script_constant_map()
	var cx_c: float = float(rd_map.get("CX", 400.0))
	var cy_c: float = float(rd_map.get("CY", 714.0))
	var sc_c: float = float(rd_map.get("SCALE", 0.5))
	var plaza_c: Vector2 = Vector2(0.0, 43.0)
	var plaza_r: float = float(rd_map.get("PLAZA_RADIUS", 12.0))
	var pts: Array = _rd.get("points")

	print("    路面半宽 %.1fm，广场盘 r=%.0fm" % [half_w, plaza_r])
	var on_road: Array[int] = []
	var unreachable: Array[int] = []
	var plaza_overlap: Array[int] = []
	var worst_dmin := INF
	var worst_who := ""
	for i in range(stations.size()):
		var st = stations[i]
		var mp: int = int(st.get("model_idx", -1))
		var hb: Vector2 = Vector2.ZERO
		if mp >= 0 and mp < STATION_GLB_CONFIG.size():
			var cfg = STATION_GLB_CONFIG[mp]
			hb = _half_extents(str(cfg.get("path", "")),
					float(cfg.get("scale", 1.0)), float(cfg.get("rot_y", 0.0)))
		var wp: Vector3 = _rd.get_station_world_pos(i)
		var ctr := Vector2(wp.x, wp.z)
		var dmin := INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var d := _seg_dist(ctr + Vector2(sx * hb.x, sy * hb.y), pts)
				if d < dmin:
					dmin = d
		var dctr := _seg_dist(ctr, pts)
		if dmin < worst_dmin:
			worst_dmin = dmin
			worst_who = str(st.get("name", ""))
		if dmin < half_w:
			on_road.append(i)
		if dctr - soft_bound > pass_r:
			unreachable.append(i)
		# 站在广场盘里的那个驿站（中心线就在盘心）必须被推到盘外
		var on_path := Vector2(
				(float(st["canvas"].x) - cx_c) * sc_c,
				(float(st["canvas"].y) - cy_c) * sc_c)
		if on_path.distance_to(plaza_c) < plaza_r and ctr.distance_to(plaza_c) < plaza_r:
			plaza_overlap.append(i)
		print("    %-16s 脚底净空 %6.2fm  到中心线 %6.2fm" % [
				str(st.get("name", "")), dmin, dctr])

	_check("没有任何驿站的脚底压在路面上（含路肩）",
			on_road.is_empty(), "仍压在路上的 idx: " + str(on_road))
	_check("最挤的驿站脚底净空也 >= 1m 余量",
			worst_dmin >= half_w + 1.0,
			"%s 净空 %.2fm（路面半宽 %.1fm）" % [worst_who, worst_dmin, half_w])
	_check("每个驿站玩家骑到路肩外沿就能触发打卡",
			unreachable.is_empty(), "够不着的 idx: " + str(unreachable))
	_check("广场盘上的驿站已推到盘外",
			plaza_overlap.is_empty(), "仍在盘内的 idx: " + str(plaza_overlap))

	_audit_name_plates(stations)

	print("")
	print("[verify_stations] 驿站 → GLB 配置验证完成")
	quit(0)


## 站名牌：从骑行那一档读不读得出自己是谁。
##
## 16 座站只用 12 个模型，三对是同一个 GLB 摆出来的——两座一模一样的亭子立在
## 同一条路肩上，玩家分不出谁是谁。而每座站**本来就带自己的名字**（`_add_label()`
## 建的 Label3D），所以这一节量的不是"模型够不够多"，是"那个名字在玩家唯一
## 看得到它的那一档上是不是真的读得出来"。
##
## 两件玩家读得出的事：
## · **牌子露在屋顶上方**——判据调的是产品里那个 `World3D.label_y_for()`，
##   不是把那一行的算式抄一遍（抄一遍的话改画不动测、测会一直绿）。
## · **一个字在骑行距离上折成多少像素**——这是**乘积**：字高(m) × 屏上每米
##   多少像素。原来写死 `pixel_size = 0.002`，字高 9.6cm，在 18m 上折合 3px，
##   而"牌子在"这一条照样绿。同一族的病：明信片背面那条量的是
##   「卡片字号 × 预览宽 / 1920」，只量任一个因子都量不到它。
func _audit_name_plates(stations: Array) -> void:
	print("")
	print("---- 站名牌（骑行视角：站心离路心线 %.0fm，720p / fov 60）----" % STATION_OFFSET)
	var w3 = load("res://scripts/World3D.gd")
	var cmap = w3.get_script_constant_map()
	var pixel_size: float = float(cmap.get("STATION_LABEL_PIXEL_SIZE", 0.0))
	var label_y_for = w3.get("label_y_for")
	_check("World3D.label_y_for() 是个能调的 static", label_y_for != null
			and w3.get_script_method_list().any(func(m): return m["name"] == "label_y_for"))

	# 屏上每米多少像素：站心离路心线 STATION_OFFSET，牌子就悬在那儿正上方。
	# 取一个**偏保守**的画幅（1080p 换算到 720p 的字高不变，所以这里只按 720p 算）。
	var view_h := 720.0
	var fov := 60.0
	var dist := STATION_OFFSET
	var px_per_m: float = view_h / (2.0 * dist * tan(deg_to_rad(fov) * 0.5))
	_check("骑行那一档每米 %.1fpx（%.0fm 处 / %dpx 高 / fov %d）" % [
			px_per_m, dist, int(view_h), fov], px_per_m > 0.0)

	# 每座站各自量：牌子在屋顶上方吗、字折到屏上多高。
	var buried: Array[int] = []
	var too_small: Array[int] = []
	var worst_px := INF
	var worst_who := ""
	for i in range(stations.size()):
		var mp: int = int(stations[i].get("model_idx", -1))
		if mp < 0 or mp >= STATION_GLB_CONFIG.size():
			continue
		var cfg = STATION_GLB_CONFIG[mp]
		var ab := _world_aabb(str(cfg.get("path", "")), float(cfg.get("scale", 1.0)),
				float(cfg.get("rot_y", 0.0)))
		if ab.size.length() < 0.01:
			continue
		var top := ab.end.y
		var y := float(label_y_for.call(top))
		var glyph_m: float = LABEL_FONT_PX * pixel_size
		var glyph_px: float = glyph_m * px_per_m
		if glyph_px < worst_px:
			worst_px = glyph_px
			worst_who = str(stations[i].get("name", ""))
		if y - top < 1.0:
			buried.append(i)
		if glyph_px < LABEL_MIN_PX:
			too_small.append(i)
		print("    %-16s 屋顶 %5.2fm → 牌子 %5.2fm（净空 %4.2fm）  字高 %.2fm = 屏上 %4.1fpx" % [
				str(stations[i].get("name", "")), top, y, y - top, glyph_m, glyph_px])

	_check("每一座站的牌子都露在屋顶上方（净空 ≥ 1m）",
			buried.is_empty(), "还埋在里面的 idx: " + str(buried))
	_check("牌子在骑行那一档读得出来（≥ %dpx，最小的 %s %.1fpx）" % [
			LABEL_MIN_PX, worst_who, worst_px], too_small.is_empty(),
			"太小的 idx: " + str(too_small))

	# 画笔真的调了那个 static：几何纯函数对不对、和画笔有没有去调它是两件事。
	# 把 `_measure_station_aabb()` 里那行改成写死的数，上面那十几条照样全绿。
	var src := FileAccess.get_file_as_string("res://scripts/World3D.gd")
	_check("World3D 真的调 label_y_for() 摆牌子（读源码文本）",
			src.contains("lbl.position.y = label_y_for(box.end.y)"))
	_check("牌子字号走 STATION_LABEL_PIXEL_SIZE，不是又写死了一个数（读源码文本）",
			src.contains("label.pixel_size = STATION_LABEL_PIXEL_SIZE")
			and not src.contains("label.pixel_size = 0.0"))


## 实例化 GLB 后取世界空间 AABB（原点即模型中心，含 scale 与 rot_y）。
func _world_aabb(path: String, scale: float, rot_y_deg: float) -> AABB:
	var res = load(path)
	if res == null or not (res is PackedScene):
		return AABB()
	var sc2: Node = res.instantiate()
	var sc3: Node3D = sc2 as Node3D
	if sc3 != null:
		sc3.scale = Vector3(scale, scale, scale)
		sc3.rotation = Vector3(0.0, deg_to_rad(rot_y_deg), 0.0)
	root.add_child(sc2)
	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)
	for n in sc2.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a: AABB = mi.mesh.get_aabb()
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var c := a.position + Vector3(
							a.size.x * sx, a.size.y * sy, a.size.z * sz)
					var w: Vector3 = mi.global_transform * c
					minv = minv.min(Vector3(w.x, w.y, w.z))
					maxv = maxv.max(Vector3(w.x, w.y, w.z))
	root.remove_child(sc2)
	sc2.free()
	if minv.x > maxv.x:
		return AABB()
	return AABB(minv, maxv - minv)


## 世界空间 AABB 的 XZ 半宽。
func _half_extents(path: String, scale: float, rot_y_deg: float) -> Vector2:
	var b := _world_aabb(path, scale, rot_y_deg)
	return Vector2(b.size.x * 0.5, b.size.z * 0.5)


## 到中心线折线的最近距离。
func _seg_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for j in range(pts.size() - 1):
		var a: Vector2 = Vector2(float(pts[j].x), float(pts[j].z))
		var b: Vector2 = Vector2(float(pts[j + 1].x), float(pts[j + 1].z))
		var ab: Vector2 = b - a
		var l2 := ab.length_squared()
		if l2 < 1e-9:
			best = minf(best, p.distance_to(a))
			continue
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best
