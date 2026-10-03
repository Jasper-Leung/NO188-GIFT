extends SceneTree
## probe_water.gd — 一次性探针（不是回归，也不是产品的一部分）
## 找「名字承诺了水」的那几座站附近，地形到底有没有真的凹下去，
## 以及**凹出来的那只碗里到底装得下多少水**。
##
## 第二个数才是判"湖还是土坑"的那一个：水面盖住碗的百分比。
## 自由板（碗心的自然高程 − 水位）越大，这个百分比越小——60m 宽的碗里
## 只露着半径 12m 的水，玩家看到的是一圈干土围着的一小滩蓝。

func _initialize() -> void:
	for n in {"GameManager": "res://scripts/GameManager.gd",
			"AudioManager": "res://scripts/AudioManager.gd",
			"Localization": "res://scripts/Localization.gd"}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)
	var gm = root.get_node("GameManager")
	gm._clear_save()
	gm.headless_mode = true
	gm.onboarding_shown = true
	gm.prologue_done = true
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://scenes/World3D.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var w = root.get_child(root.get_child_count() - 1)
	var tb = w._terrain_builder
	for b in tb.water_basins():
		var c: Vector2 = b["center"]
		var level: float = b["level"]
		var r_max: float = b["radius"]
		var along := Vector2(float(b["ax"]), float(b["az"]))
		var away := Vector2(along.y, -along.x)
		var squash: float = float(b["squash"])
		print("=== 站 %d  碗心 %s  半径 %.1f squash %.2f 挖深 %.2f 水位 %.2f 自然高程 %.2f"
				% [int(b["station"]), str(c), r_max, squash, float(b["depth"]), level,
				tb.natural_height_at(c.x, c.y)])
		var lost := 0
		var fill := 0.0
		var mn := INF
		var mx := 0.0
		for k in range(72):
			var a := TAU * float(k) / 72.0
			var dir := Vector2(cos(a), sin(a))
			# 沿这个方向走到碗沿还有多远。碗是椭圆，拿 radius 当上限会把
			# 长轴那一侧齐腰剪断（`squash` 就是干这个的）。
			var u: float = (dir.x * along.x + dir.y * along.y) / squash
			var v: float = dir.x * away.x + dir.y * away.y
			var span: float = r_max / maxf(sqrt(u * u + v * v), 1e-6)
			var edge := -1.0
			var r := 2.0
			while r <= span * 1.15:
				var p := c + dir * r
				if tb.get_height_at(p.x, p.y) - level >= 0.0:
					edge = r
					break
				r += 1.0
			if edge < 0.0:
				lost += 1
				print("   角 %5.1f° : 碗沿之外还没露出岸（!!）" % rad_to_deg(a))
				continue
			fill += edge / span
			mn = minf(mn, edge)
			mx = maxf(mx, edge)
		# 自由板 = 碗深 - 水深 = 碗心的自然高程 - 水位。
		print("   自由板 %.2fm／水面盖住碗的 %d%%／各方向水面半径 %.1f~%.1fm／%d 个角没找到岸"
				% [float(b["depth"]) - float(b["water_depth"]),
				int(100.0 * fill / 72.0), mn, mx, lost])
	quit(0)