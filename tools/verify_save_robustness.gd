extends SceneTree
## 存档健壮性回归。
##
## 守的是三件玩家真正会遇到的坏事，按"坏到什么程度"从轻到重排：
##  ① 崩在写一半 —— 进程被杀/断电/Web 上关标签页，把正本截成半份；
##  ② 存档被外部改坏 —— 纯垃圾、空文件、手滑改了个字符；
##  ③ 存档"读得出来但是坏的" —— 值越界、键不认识。
##
## ① 和 ② 的根因是同一件事，而且量出来之前谁也想不到：
## **`ConfigFile.load()` 对截断、纯垃圾、空文件一律返回 OK**。所以旧版
## `_load_save()` 判的是 `cfg.load(SAVE_PATH) != OK` —— 崩在写一半的存档
## "读档成功"，版本号取到默认值 0 ≠ SAVE_VERSION，于是走 `_clear_save()`
## **把玩家整趟行程删掉**。第 1 节把这个前提钉成断言：哪天引擎改了行为，
## 这份脚本会告诉你，而不是让你继续以为回退逻辑是多余的。
##
## ③ 的判据量的是**玩家下一帧真的读出来的那几个量**（碎片站到访次数、
## 顶栏「已过 n 驿」、明信片档位），不是存档文件里那几个字符串。
##
## 跑法： godot --headless --path . --script tools/verify_save_robustness.gd
## 全程在 user://gift188.{cfg,cfg.tmp,cfg.bak} 上写：开跑前备份三份，跑完原样还回去。

var _fails: Array = []
var _oks := 0
var _gm = null
var _sd = null
var _rd = null

const FILES := ["user://gift188.cfg", "user://gift188.cfg.tmp", "user://gift188.cfg.bak"]


func _initialize() -> void:
	call_deferred("_run")


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


func _write(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## 手写一份"格式完全正确"的存档，绕过 _save_game()，用来把存档摆成任意形状。
func _craft(collected: String, econ: Dictionary) -> String:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "version", int(_gm.SAVE_VERSION))
	cfg.set_value("game", "collected", collected)
	cfg.set_value("game", "progress_km", 42.0)
	cfg.set_value("game", "onboarding_shown", 1)
	cfg.set_value("game", "economy", JSON.stringify(econ))
	return cfg.encode_to_text()


## 只把**内存**里的状态清成默认值，一个字节都不碰盘上的存档。
##
## 为什么不能拿 `reset()` 代替：玩家真实的流程是「存 → 退进程 → 开机读」，
## 中间**没有**任何一步会删文件。而 `reset()` 走 `_clear_save()`，
## 于是「存 → reset → 读」量到的是"存档被自己删了还能读回来"——
## 恒绿，而且和被测的东西毫无关系（同族：`verify_minimap.gd` 第 9 节
## 那个"游戏里根本走不到的存档"）。
func _wipe_memory() -> void:
	_gm.collected = _gm._new_collected()
	_gm._collected_fired = false
	_gm._maxed_fired = false
	_gm.current_state = int(_gm.State.GIFT_BOX)
	_gm.progress_km = 0.0
	_gm.onboarding_shown = false
	_gm.lvbi = 0
	_gm.inv = {}
	_gm.spent_km = 0.0
	_gm.earned_tags = {}
	_gm.seen_stations = {}
	_gm.mood = int(_gm.MOOD_INITIAL)
	_gm.seen_villain = 0
	_gm.prologue_done = false
	_gm.ending_id = ""


## 走真实入口读档。和玩家启动时读的是同一条路。
func _reload() -> void:
	_wipe_memory()
	_gm._load_save()


func _run() -> void:
	_gm = get_root().get_node_or_null("GameManager")
	if _gm == null:
		print("[ABORT] 拿不到 GameManager autoload")
		quit(1)
		return
	_sd = load("res://scripts/shop_data.gd").new()
	_rd = load("res://scripts/road_data.gd").new()
	if _sd == null or _rd == null:
		print("[ABORT] 加载 shop_data / road_data 失败")
		quit(1)
		return

	# ---- 存档备份：测试全程在这三份上写，跑完原样还回去 ----
	var backup := {}
	for p in FILES:
		backup[p] = _read(str(p))
	_gm.reset()

	_section1_platform()
	_section2_roundtrip()
	_section3_atomic()
	_section4_truncated()
	_section5_both_broken()
	_section6_sanitise()
	_section7_clear()

	# ---- 还原存档 ----
	_gm._clear_save()
	for p in FILES:
		if str(backup[p]) != "":
			_write(str(p), str(backup[p]))

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)


## ---------------------------------------------------------------- ① 平台前提
##
## 这一节是整份脚本的地基。它量的是**引擎自己的行为**，不是我们的代码 ——
## 所以它是这一族里唯一"改产品代码也不会红"的一节，而这正是它该有的样子：
## 它守的是"回退逻辑不是多余的"这个前提，前提塌了后面全部推理都要重来。
func _section1_platform() -> void:
	print("--- 1. 平台前提：ConfigFile 对坏文件一律返回 OK ---")
	var main := str(_gm.SAVE_PATH)
	var probe := "user://_save_probe.cfg"

	var cases := {
		"截断的存档（崩在写一半）": "[game]\n\nversion=3\ncollected=\"7:2,10:1\"\nprog",
		"纯垃圾": "<<< not a config at all >>> [[[",
		"空文件": "",
	}
	for label in cases.keys():
		_write(probe, str(cases[label]))
		var cfg := ConfigFile.new()
		var rc := cfg.load(probe)
		_ck("ConfigFile.load 对「%s」返回 OK" % label, rc == OK, "got=%d" % rc)

	# 正对照：一份好存档当然也要 load 得动。
	# **没有这条，上面那三条恒绿也证明不了什么** —— 一个"什么都返回错误"的
	# load() 同样能让那三条红，而那时回退逻辑照样是多余的。
	_write(probe, _craft("7:2,10:1,13:0,14:0,4:0", {"lvbi": 7}))
	var good := ConfigFile.new()
	_ck("正对照：好存档也 load 得动（不是 load 永远失败）",
		good.load(probe) == OK and int(good.get_value("game", "version", 0)) == int(_gm.SAVE_VERSION))

	DirAccess.remove_absolute(probe)


## ---------------------------------------------------------------- ② 完整往返
##
## 正对照：一份**合法**存档该原样回来。少了这一节，下面 ③④⑤ 三节
## 全都可以靠"把所有值都清成默认值"而恒绿 —— 那是把存档丢光，不是健壮。
func _section2_roundtrip() -> void:
	print("--- 2. 正对照：合法存档原样往返 ---")
	_gm.reset()
	_gm.lvbi = 123
	_gm.mood = 2
	_gm.spent_km = 7.5
	_gm.seen_villain = 2
	_gm.prologue_done = true
	_gm.ending_id = "keep"
	_gm.inv["paper"] = 1
	_gm.inv["lamp"] = 2
	_gm.inv["postcard_tier"] = 2
	_gm.seen_stations[0] = true
	_gm.seen_stations[3] = true
	_gm.seen_stations[9] = true
	_gm.earned_tags["frag_7"] = true
	_gm.collected[7] = 3
	_gm.collected[10] = 1
	_gm._save_game()

	var lvbi := int(_gm.lvbi)
	var mood := int(_gm.mood)
	var seen := int(_gm.seen_stations.size())
	var tier := int(_gm.get_postcard_tier())
	_reload()

	_eq("旅币原样回来", int(_gm.lvbi), lvbi)
	_eq("心神原样回来", int(_gm.mood), mood)
	_eq("到过驿数原样回来（顶栏那句「已过 n 驿」）", _gm.seen_stations.size(), seen)
	_eq("到过的是那三座，不是别的", _gm.seen_stations.has(0) and _gm.seen_stations.has(9), true)
	_eq("明信片档位原样回来", int(_gm.get_postcard_tier()), tier)
	_eq("商品数量原样回来（可叠两件的灯笼）", int(_gm.get_item_count("lamp")), 2)
	_eq("限购一件的商品原样回来", int(_gm.get_item_count("paper")), 1)
	_eq("郑铎场次原样回来", int(_gm.seen_villain), 2)
	_eq("序章标记原样回来", _gm.prologue_done, true)
	_eq("结局原样回来", _gm.ending_id, "keep")
	_eq("碎片到访次数原样回来", int(_gm.collected.get(7, 0)), 3)
	_eq("幂等账本原样回来", _gm.earned_tags.has("frag_7"), true)
	_ck("正对照：真的存下东西了（不是回到全零）", lvbi > 0 and seen == 3 and tier == 2,
		"lvbi=%d seen=%d tier=%d" % [lvbi, seen, tier])


## ---------------------------------------------------------------- ③ 原子写
##
## `_save_game()` 现在是三步：临时文件 → 备份正本 → 换名盖掉。
## 量的是**换完之后盘上是什么样**：正本在、临时文件不在、备份里躺着的
## 是换名之前那一份（也就是上一趟的进度，不是这一趟的）。
func _section3_atomic() -> void:
	print("--- 3. 原子写：换名不留半份、备份是上一份 ---")
	_gm.reset()
	_gm._save_game()
	_gm.lvbi = 500
	_gm._save_game()

	var main := str(_gm.SAVE_PATH)
	var tmp := str(_gm.SAVE_TMP)
	var bak := str(_gm.SAVE_BAK)
	_ck("正本在", FileAccess.file_exists(main))
	_ck("临时文件用完就搬走了（不留半份在盘上）", not FileAccess.file_exists(tmp))
	_ck("备份在", FileAccess.file_exists(bak))

	# 备份里必须是**上一份**。这一条量的是"备份抢在换名之前"这个顺序：
	# 顺序反了的话备份会变成这一趟的副本，于是崩在写一半时退回的是
	# 同一份可能已经被截断的数据，退回等于没退。
	var bak_cfg := ConfigFile.new()
	bak_cfg.load(bak)
	_ck("备份里躺的是**上一份**（lvbi=0，不是这一趟的 500）",
		JSON.parse_string(str(bak_cfg.get_value("game", "economy", ""))).get("lvbi", -1) == 0,
		"got=%s" % str(JSON.parse_string(str(bak_cfg.get_value("game", "economy", "")))))

	var main_cfg := ConfigFile.new()
	main_cfg.load(main)
	_ck("正本是这一趟的（lvbi=500）",
		JSON.parse_string(str(main_cfg.get_value("game", "economy", ""))).get("lvbi", -1) == 500)


## ---------------------------------------------------------------- ④ 崩在写一半
##
## 这一节是整份脚本的主菜。做法就是把正本截掉一半 —— 崩在写一半的存档
## 在盘上就是这个形状。**正对照是这一节的一半**：光断"读档不炸"的话，
## 把 `_load_save()` 改成永远 `return`（于是清空一切）一样是绿的。
## 真正要断的是"玩家从**上一份好的**接着玩"。
func _section4_truncated() -> void:
	print("--- 4. 崩在写一半：从备份接着玩，而不是从头开始 ---")
	_gm.reset()
	_gm.lvbi = 111
	_gm.mood = 3
	_gm.collected[7] = 2
	_gm.seen_stations[5] = true
	_gm._save_game()          # 这一份成为"上一份好的"，躺进 .bak
	var good_lvbi := int(_gm.lvbi)

	_gm.lvbi = 222
	_gm.collected[7] = 3
	_gm.seen_stations[5] = true
	_gm.seen_stations[6] = true
	_gm._save_game()          # 这一份是正本

	# 崩在写一半：把正本截掉后半截
	var full := _read(str(_gm.SAVE_PATH))
	_write(str(_gm.SAVE_PATH), full.substr(0, int(full.length() * 0.5)))

	_reload()
	_eq("从备份恢复：旅币是上一份的 111，不是 0 也不是这一份的 222", int(_gm.lvbi), good_lvbi)
	_eq("从备份恢复：到过的驿没丢", _gm.seen_stations.has(5), true)
	_eq("从备份恢复：碎片次数没丢", int(_gm.collected.get(7, 0)), 2)
	_ck("正对照：这一趟新挣的（6 号驿 / 3 次）确实只存在于被截断的那一份里",
		not _gm.seen_stations.has(6) and int(_gm.collected.get(7, 0)) < 3,
		"seen6=%s cnt7=%d" % [str(_gm.seen_stations.has(6)), int(_gm.collected.get(7, 0))])

	# 纯垃圾与空文件走同一条路，也要能退回来
	for label in ["纯垃圾", "空文件"]:
		_gm.reset()
		_gm.lvbi = 333
		_gm._save_game()
		_gm.lvbi = 999
		_gm._save_game()
		_write(str(_gm.SAVE_PATH), "<<< 垃圾 >>>" if label == "纯垃圾" else "")
		_reload()
		_eq("存档是「%s」时也退回备份（lvbi=333）" % label, int(_gm.lvbi), 333)


## ---------------------------------------------------------------- ⑤ 两份都坏
##
## 备份也是坏的时候，游戏必须**从头开始而不是崩**。这一节的判据是
## "不抛错、状态干净、盘上不留半份" —— 不是"玩家保住了什么"，
## 那种情况下已经没什么可保的了。
func _section5_both_broken() -> void:
	print("--- 5. 正本和备份都坏：从头开始，不崩 ---")
	_gm.reset()
	_gm.lvbi = 5000
	_gm.collected[7] = 3
	_gm._save_game()
	_write(str(_gm.SAVE_PATH), "<<< 垃圾 >>>")
	_write(str(_gm.SAVE_BAK), "")
	_ck("前提：两份坏文件真的在盘上（这一节不能靠 reset() 顺手删掉它们）",
		FileAccess.file_exists(str(_gm.SAVE_PATH)) and FileAccess.file_exists(str(_gm.SAVE_BAK)))

	_reload()
	_eq("旅币回到 0", int(_gm.lvbi), 0)
	_eq("碎片次数全零", int(_gm.collected.get(7, 0)), 0)
	_eq("到过驿数 0", _gm.seen_stations.size(), 0)
	_eq("坏存档被清掉了", FileAccess.file_exists(str(_gm.SAVE_PATH)), false)
	_eq("坏备份也被清掉了", FileAccess.file_exists(str(_gm.SAVE_BAK)), false)
	# 走过一次坏档之后，两个闩锁必须按"没有进度"对齐，而不是按崩之前那一次。
	_eq("集齐闩锁按零进度对齐", _gm._collected_fired, false)
	_eq("完满闩锁按零进度对齐", _gm._maxed_fired, false)

	# 旧版本号的存档：照旧从头开始，但**必须先试过备份**。
	# 这一条用"备份是新版本、正本是 v2"来断那个顺序 —— 只试正本的话
	# 玩家会白丢一份更新的进度。**要存两次**才真的有备份：第一份写完正本
	# 时备份还不存在（没有上一份可备），第二份才把它复制出来。
	# （第一版这里只存了一次，于是根本没有 .bak，这条量的是"没有备份时
	#  回到全零" —— 和第 5 节量的是同一件事。）
	_gm.reset()
	_gm.lvbi = 1
	_gm._save_game()
	_gm.lvbi = 777
	_gm._save_game()
	_ck("前提：备份确实在（正本=777，备份=1）", FileAccess.file_exists(str(_gm.SAVE_BAK)))
	var v2 := ConfigFile.new()
	v2.set_value("game", "version", 2)
	v2.set_value("game", "collected", "7:1")
	_write(str(_gm.SAVE_PATH), v2.encode_to_text())
	_reload()
	_eq("正本是旧版本时退回备份（备份躺的是上一份 lvbi=1，不是 0）", int(_gm.lvbi), 1)


## ---------------------------------------------------------------- ⑥ 值校验
##
## 到这里存档"读得出来"，但里面的值可能越界。判据量的是**玩家下一帧
## 真的读出来的那几个量**，不是存档文件里那几个字符串：
##  · 碎片站到访次数 > 3 → `is_station_exhausted()` 恒真 → 那一座**永久
##    打不了卡**，而顶栏「下一处」还指着它，玩家卡死在一个减不到 0 的数上。
##  · postcard_tier 是 `get_postcard_tier()` 直接读出来当档位的。
##  · `seen_stations.size()` 就是顶栏那句「已过 n 驿」。
func _section6_sanitise() -> void:
	print("--- 6. 值校验：坏存档不许让人赢不了或白赢 ---")
	var max_tier := 0
	for g in _sd.GOODS:
		if str(g.get("grant", "")) == "postcard_tier":
			max_tier = maxi(max_tier, int(g.get("tier_rank", 0)))
	var n_stations: int = _rd.stations.size()

	_write(str(_gm.SAVE_PATH), _craft(
		"7:99,10:-5,999:3,4:2",
		{
			"lvbi": -50, "inv": {"postcard_tier": 99, "free_stuff": 5, "kit_rare": 77},
			"spent_km": 99999.0, "earned_tags": {"frag_7": "yes"},
			"seen_stations": {"0": true, "9999": true, "-3": true, str(n_stations): true},
			"mood": 77, "seen_villain": 99, "prologue_done": true, "ending_id": "keep",
		}))
	_reload()

	_eq("到访次数夹到 MAX_VISITS_PER_STATION（7:99 → 3）",
		int(_gm.collected.get(7, 0)), int(_gm.MAX_VISITS_PER_STATION))
	_eq("负数夹到 0（10:-5 → 0）", int(_gm.collected.get(10, 0)), 0)
	_eq("不认识站号整个丢掉（999 不在 collected 里）", _gm.collected.has(999), false)
	_eq("collected 恰好五个键（顶层「已收 n 块」按这五个数）", _gm.collected.size(), 5)
	_ck("正对照：合法的那一座还在（4:2）", int(_gm.collected.get(4, 0)) == 2,
		"got=%d" % int(_gm.collected.get(4, 0)))

	_eq("旅币夹到 ≥0", int(_gm.lvbi), 0)
	_eq("明信片档位夹到商品表里真的存在的那一档", int(_gm.get_postcard_tier()), max_tier)
	_eq("档位没被夹成 0（夹过头也是坏的）", int(_gm.get_postcard_tier()) > 0, true)
	_eq("不认识的商品 id 丢掉（free_stuff）", _gm.inv.has("free_stuff"), false)
	_eq("单件限购的商品夹到 max_own（kit_rare:77 → 1）", int(_gm.get_item_count("kit_rare")), 1)
	_eq("spent_km 夹到 TOTAL_ROUTE_KM", float(_gm.spent_km), float(_gm.TOTAL_ROUTE_KM))
	_eq("幂等账本的值统一成 true", _gm.earned_tags.get("frag_7", false), true)
	_eq("到过驿只认真站号（0 号在）", _gm.seen_stations.has(0), true)
	_eq("越界站号丢掉（9999 / -3 / n）",
		_gm.seen_stations.has(9999) or _gm.seen_stations.has(-3) or _gm.seen_stations.size() > n_stations,
		false)
	_eq("到过驿数就是顶栏那句「已过 n 驿」", _gm.seen_stations.size(), 1)
	_eq("心神夹到 MOOD_CEIL", int(_gm.mood), int(_gm.MOOD_CEIL))
	_eq("郑铎场次夹到 VILLAIN_SCENE_COUNT（再高就少演一场）",
		int(_gm.seen_villain), int(_gm.VILLAIN_SCENE_COUNT))

	# 合法值不许被误伤
	_write(str(_gm.SAVE_PATH), _craft(
		"7:1,10:2,13:3,14:1,4:2",
		{
			"lvbi": 300, "inv": {"lamp": 2, "postcard_tier": 1},
			"seen_stations": {"0": true, "1": true, "2": true},
			"mood": 5, "seen_villain": 1, "prologue_done": false, "ending_id": "",
		}))
	_reload()
	_eq("正对照：合法值没被误伤（7 号站 1 次）", int(_gm.collected.get(7, 0)), 1)
	_eq("正对照：合法值没被误伤（13 号站满 3 次）", int(_gm.collected.get(13, 0)), 3)
	_eq("正对照：两盏灯笼都在（可叠两件）", int(_gm.get_item_count("lamp")), 2)
	_eq("正对照：到过三座驿", _gm.seen_stations.size(), 3)
	_eq("正对照：旅币 300 没被清掉", int(_gm.lvbi), 300)


## ---------------------------------------------------------------- ⑦ 清理
##
## 临时文件是崩溃的残留物。留着它不影响读档（`_load_save()` 只看正本和
## 备份），但"重新开始"必须把它一起收掉 —— 否则玩家点了重开之后盘上
## 还躺着自己刚才的存档碎片。
func _section7_clear() -> void:
	print("--- 7. 重新开始把三份一起收掉 ---")
	_gm.reset()
	_gm._save_game()
	_gm.lvbi = 9
	_gm._save_game()
	_write(str(_gm.SAVE_TMP), "崩在换名之前的残留")
	_ck("前提：三份都在盘上",
		FileAccess.file_exists(str(_gm.SAVE_PATH))
		and FileAccess.file_exists(str(_gm.SAVE_BAK))
		and FileAccess.file_exists(str(_gm.SAVE_TMP)))

	_gm.reset()
	_eq("正本删了", FileAccess.file_exists(str(_gm.SAVE_PATH)), false)
	_eq("备份删了", FileAccess.file_exists(str(_gm.SAVE_BAK)), false)
	_eq("临时残留也删了", FileAccess.file_exists(str(_gm.SAVE_TMP)), false)
