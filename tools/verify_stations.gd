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

## 这张表**只从产品那份读**，不手抄。
##
## 原来这里是 14 行手抄的副本，而它已经和 `World3D.STATION_GLB_CONFIG` 漂开了：
## 琴台那一行少了 `rot_y`（产品转 120°、副本按 0° 量），而 `scale` 还停在 10.0。
## 后果不是"断言太松"，是**量错了对象**——旋转后的包围盒比轴对齐的大，
## 于是"脚底净空"这一节量的是一件产品里不存在的东西（本轮它报 7.27m，
## 真实的那一份是 7.20m，方向一致、量级一致，所以看不出来）。
## 这正是 CLAUDE.md 里「手抄的常量副本会自己长出一套预算曲线」那条：
## 凡是回归里手抄一份产品的表，就该直接读产品那份。
static var STATION_GLB_CONFIG: Array = []

static func _load_product_config() -> Array:
	if not STATION_GLB_CONFIG.is_empty():
		return STATION_GLB_CONFIG
	var scr: GDScript = load("res://scripts/World3D.gd")
	if scr == null:
		return []
	var m := scr.get_script_constant_map()
	if not m.has("STATION_GLB_CONFIG"):
		return []
	STATION_GLB_CONFIG = m["STATION_GLB_CONFIG"]
	return STATION_GLB_CONFIG

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
	# 正对照：先断「产品那份真的读到了」。读不到的话下面每一处
	# `STATION_GLB_CONFIG[...]` 都会 IndexError 把协程掐断，而汇总照样打 PASS。
	# 14 是产品表真实的长度（槽位 0..13，其中 2 已退役留空）。
	var cfg_tbl: Array = _load_product_config()
	_check("产品 World3D.STATION_GLB_CONFIG 真的读得到（14 条）",
		cfg_tbl.size() == 14, "实测 %d 条" % cfg_tbl.size())
	if cfg_tbl.size() < 6:
		print("[ABORT] 产品配置表读不到，无法继续")
		quit(1)
		return
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

	# 已退役的 model_idx（station_2 的图生 3D 在 2026-10-05 被换掉）留的是**空槽**，
	# 而 model_idx 是 road_data.gd 里手抄的下标——把某座站留在退役槽上，
	# 上面两条断言照样全绿（槽位在范围内、指向的路径也不是空串而是空），
	# 而世界里那一座站会静悄悄地没有模型。这条是这个家族里唯一拦得住它的判据。
	var retired_hits: Array[int] = []
	for i in range(model_idxs.size()):
		var cfg = STATION_GLB_CONFIG[model_idxs[i]]
		if bool(cfg.get("retired", false)):
			retired_hits.append(i)
	_check("没有驿站指向已退役的 model_idx 槽位",
			retired_hits.is_empty(),
			"站 idx " + str(retired_hits) + " 停在退役槽上")

	var missing: Array[String] = []
	var live_slots := 0
	for cfg in STATION_GLB_CONFIG:
		var p: String = str(cfg.get("path", ""))
		if p == "":
			continue          # 退役槽位：没有文件可查
		live_slots += 1
		if not ResourceLoader.exists(p):
			missing.append(p)
	# 正对照：只断「没有缺失」的话，一个把所有槽位都清空的数组照样全绿
	_check("这份名单里确实有活着的槽位（正对照）", live_slots == 13,
			"活槽位 %d（应 13 = 14 槽 - 1 退役）" % live_slots)
	_check("所有 STATION_GLB_CONFIG 指向的 GLB 都存在于 res://",
			missing.is_empty(),
			"缺: " + str(missing))

	# 每个新 GLB 都能被 load() 且不报错
	var load_err: Array[String] = []
	var loadable := 0
	for i in range(6, STATION_GLB_CONFIG.size()):
		var p: String = str(STATION_GLB_CONFIG[i]["path"])
		if p == "":
			continue          # 退役槽位（槽位 2 在 6 之前，这循环本来也碰不到它，
		                      # 但留着这一句，换个下标退役时也不会静默 load("")）
		loadable += 1
		var s = load(p)
		if s == null:
			load_err.append(p)
	_check("新加的 8 个 GLB 都能 load 成 PackedScene（正对照）", loadable == 8,
			"只 load 了 %d 个" % loadable)
	_check("新加的 8 个 GLB 都能 load 成 PackedScene",
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
	# 正对照：`rot_y` 是这一节量"旋转后包围盒"的唯一入口，而它缺了不会报错、
	# 只会让净空算成一个产品里不存在的数。先断"真的有几座是转过的"。
	var rotated: Array[String] = []
	for c in STATION_GLB_CONFIG:
		if c.has("path") and str(c.get("path", "")) != "" \
				and absf(float(c.get("rot_y", 0.0))) > 0.01:
			rotated.append("%s %.0f°" % [str(c.get("path", "")).get_file(),
				float(c.get("rot_y", 0.0))])
	_check("配置表里至少 3 条带非零 rot_y（否则这一节量的是没转过的盒子）",
		rotated.size() >= 3, "实测 %d 条: %s" % [rotated.size(), ", ".join(rotated)])
	var on_road: Array[int] = []
	var unreachable: Array[int] = []
	var plaza_overlap: Array[int] = []
	var worst_dmin := INF
	var worst_who := ""
	for i in range(stations.size()):
		var st = stations[i]
		var mp: int = int(st.get("model_idx", -1))
		var ctr_w: Vector3 = _rd.get_station_world_pos(i)
		var ctr := Vector2(ctr_w.x, ctr_w.z)
		var m_scale := 1.0
		var m_rot := 0.0
		var la := AABB()
		if mp >= 0 and mp < STATION_GLB_CONFIG.size():
			var cfg = STATION_GLB_CONFIG[mp]
			m_scale = float(cfg.get("scale", 1.0))
			m_rot = deg_to_rad(float(cfg.get("rot_y", 0.0)))
			la = _world_aabb(str(cfg.get("path", "")), 1.0, 0.0)
		# 中心线到「模型自己那个盒子」的距离：沿中心线每 0.25m 取一个采样点，
		# 把采样点**转回模型的本地坐标系**再算点到盒的精确距离。
		#
		# 这一节换过三把尺子，前两把都量错了对象而且**都没有红**，所以记在这里：
		# ① 「旋转后的世界 AABB」的 4 个角 —— 角是盒子的角，不是模型的角。
		#    琴台转 120° 时离路最近的那个角比模型最近处远 6.5m（5.82m 是假的）。
		# ② 同上但量 8 个本地角点变换后的最小值 —— 这一把**又松了**：对盒子来说
		#    远点的最近点通常落在面的内部而不是角上，把琴台 scale 翻到 20
		#    （几何上早压到路面了）它照样报 9.67m 通过。
		# ③ 精确的「点到旋转盒」——把采样点转回本地系，盒子自然就是轴对齐的，
		#    用标准三段式公式即可。琴台实测 11.7m（= 18 − 10 × 0.63，
		#    0.63 是它本地 z 轴那一侧的半跨，也就是台阶那一头；六棵树在另一头）。
		var dmin := INF
		if la.size.x > 0.0:
			var lc := Vector2(la.position.x + la.size.x * 0.5,
					la.position.z + la.size.z * 0.5)
			var lh := Vector2(la.size.x * 0.5, la.size.z * 0.5)
			var unrot := Basis(Vector3.UP, -m_rot)
			for j in range(pts.size() - 1):
				var a: Vector3 = pts[j]
				var b: Vector3 = pts[j + 1]
				var seglen := Vector2(b.x - a.x, b.z - a.z).length()
				var steps: int = maxi(2, int(ceil(seglen / 0.25)))
				for k in range(steps + 1):
					var t := float(k) / float(steps)
					var p := Vector2(a.x, a.z).lerp(Vector2(b.x, b.z), t)
					var lv := unrot * Vector3(p.x - ctr.x, 0.0, p.y - ctr.y)
					dmin = minf(dmin, _point_box_dist(
							Vector2(lv.x, lv.z) / m_scale, lc, lh) * m_scale)
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


## 实例化 GLB 后取**旋转后**的模型脚底角点（世界 XZ，含 scale 与 rot_y）。
##
## 这里量的是 8 个**变换过的**本地 AABB 角点，不是"变换完再取轴对齐盒"。
## 差别有多大：琴台转 120°，本地半跨 0.777 → 旋转后半跨 1.02（×1.37），
## 而旧写法量的 1.06 是把旋转后的形状又压回轴对齐得到的另一个盒子。
## 两者都还包着模型，但只有前者是"模型实际占的那块地"——玩家看到的是琴台
## 站在那儿，不是站在一个更大的方框里。
##
## 注意这**不是**把判据放松：门槛（离沥青外沿 1m 余量）与量法无关。
## 而产品那份 keepout 走的是 `World3D._measure_station_aabb()`，
## 那里用 `st.global_transform.affine_inverse()` **把站的旋转抵消掉了**，
## 量到的是没转过的本地盒——那是另一件事（撞车半径），不在这一节里。
## 旋转后那个盒子的中心平移到站心。`_world_aabb()` 量的是"模型原点即中心"的
## 局部结果，脚底净空要的是它落在世界哪里，所以这里把站心加回去。
func _world_aabb_at(path: String, scale: float, rot_y_deg: float,
		ctr: Vector3) -> AABB:
	var b := _world_aabb(path, scale, rot_y_deg)
	if b.size.x <= 0.0:
		return b
	return AABB(b.position + ctr, b.size)


## 点到轴对齐盒（XZ 平面）的精确距离。经典三段式：盒外取逐轴超出量的模，
## 盒内取 0（点到盒的最近距离在内部恒为 0）。盒内那一支别省——自交点广场
## 那一座站的中心线就在盘心，量不到它的话那一站会凭空多出一大截"净空"。
func _point_box_dist(p: Vector2, c: Vector2, h: Vector2) -> float:
	var q := Vector2(absf(p.x - c.x), absf(p.y - c.y)) - h
	if q.x <= 0.0 and q.y <= 0.0:
		return 0.0
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


## 世界空间 AABB（原点即模型中心，含 scale 与 rot_y）。只给"量屋顶多高"用——
## 绕 Y 转不改变 y，所以这里的顶面和旋转无关。
func _world_aabb(path: String, scale: float, rot_y_deg: float) -> AABB:
	var pts := _rot_corners(path, scale, rot_y_deg)
	if pts.is_empty():
		return AABB()
	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)
	for w in pts:
		minv = minv.min(w)
		maxv = maxv.max(w)
	return AABB(minv, maxv - minv)


func _rot_corners(path: String, scale: float, rot_y_deg: float) -> Array:
	var res = load(path)
	if res == null or not (res is PackedScene):
		return []
	var sc2: Node = res.instantiate()
	var sc3: Node3D = sc2 as Node3D
	if sc3 != null:
		sc3.scale = Vector3(scale, scale, scale)
		sc3.rotation = Vector3(0.0, deg_to_rad(rot_y_deg), 0.0)
	root.add_child(sc2)
	var pts: Array = []
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
					pts.append(mi.global_transform * c)
	root.remove_child(sc2)
	sc2.free()
	return pts


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
