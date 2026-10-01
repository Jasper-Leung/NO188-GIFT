extends Node
## web_smoke.gd — **只给 Web 导出实测用**，不是产品的一部分。
##
## 它量的是三件在桌面回归里永远量不到、而恰恰是 Web 独有的事：
##   1. `user://` 落到 IndexedDB（IDBFS）之后，**刷新页面还能不能读回来**
##   2. 明信片导出走 `JavaScriptBridge` 那条 Web 专用分支时，PNG 真的下载得到
##   3. 控制台里有没有 Web 特有的报错
##
## 分两拍跑，**靠刷新页面自己切换**，所以只需要一份构建：
##   第 1 拍（存档里没有 PROBE 值）：走真实 `GameManager.check_in()` 写盘 → 导出 PNG
##   第 2 拍（刷新后）：读存档，值还在就说明 IDBFS 真的落盘并读回了
##
## 用法：把本场景设成主场景，导出 Web，在浏览器里打开跑两遍。
## 跑完记得把 project.godot 的主场景改回 res://scenes/GiftBox.tscn。

const PROBE_STATION := 7   # FRAGMENT_SLOT_STATION_IDX[0]，云影台


func _ready() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		_fin("GM_MISSING")
		return
	await get_tree().process_frame

	# 分拍判据用 collected[7]，不用旅币：check_in() 自己会算旅币并回写，
	# 第一版拿 lvbi 当标志位，结果每次都被覆盖成 1，第二拍永远进不去。
	if int((gm.get("collected") as Dictionary).get(PROBE_STATION, 0)) > 0:
		await _phase_roundtrip(gm)
	else:
		await _phase_write(gm)

	_fin("DONE")


## 第 1 拍：写盘 + 导 PNG
func _phase_write(gm: Node) -> void:
	print("[web_smoke] phase=write OS=%s web_feature=%s" % [
			OS.get_name(), str(OS.has_feature("web"))])

	gm.set("lvbi", 424242)
	# 走真实入口：check_in 内部才调 _save_game()。
	# 直接写 GameManager.collected[i] 不发信号，也就测不到"打卡这条路上会落盘"。
	gm.call("check_in", PROBE_STATION)
	await get_tree().process_frame

	var cfg := ConfigFile.new()
	var err := cfg.load("user://gift188.cfg")
	var blob = JSON.parse_string(str(cfg.get_value("game", "economy", "{}")))
	print("[web_smoke] save_load_err=%d lvbi=%d collected_csv=%s" % [
			err,
			int(blob.get("lvbi", -1)) if blob is Dictionary else -1,
			str(cfg.get_value("game", "collected", ""))])
	if err != OK:
		_fin("SAVE_WRITE_FAILED")
		return

	# 导 PNG：走 EndCard 真实的 _on_export_pressed()，里面自己会分叉到 Web 分支。
	var end: Node = load("res://scenes/EndCard.tscn").instantiate()
	add_child(end)
	# SubViewport 要真的渲染过 get_texture() 才有东西；等够帧数而不是等固定秒数
	for i in 20:
		await get_tree().process_frame
	# dummy renderer 下 SubViewport 拿不到真画面（headless 专属，Web 上是真渲染器）。
	# 坑在**判 texture 不够**：get_texture() 照样给回一个非 null 的对象，
	# 真正抛 `Parameter "t" is null` 的是链上去的 get_image()，而那是在
	# EndCard._on_export_pressed() 内部抛的 —— 守卫写在调用之前，
	# 只能拿 image 出来自己判。
	var img = end.get("_export_viewport").get_texture().get_image()
	if img == null:
		print("[web_smoke] export_skipped=no_viewport_image")
		return
	end.call("_on_export_pressed")
	for i in 10:
		await get_tree().process_frame
	print("[web_smoke] export_pressed")


## 第 2 拍：刷新之后
func _phase_roundtrip(gm: Node) -> void:
	var n: int = int((gm.get("collected") as Dictionary).get(PROBE_STATION, 0))
	print("[web_smoke] phase=roundtrip station7_visits=%d lvbi=%d" % [n, int(gm.get("lvbi"))])
	_fin("ROUNDTRIP_OK" if n > 0 else "ROUNDTRIP_LOST")


func _fin(code: String) -> void:
	print("[web_smoke] result=%s" % code)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if code in ["DONE", "ROUNDTRIP_OK"] else 1)
