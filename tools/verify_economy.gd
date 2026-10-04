extends SceneTree
## 经济系统回归 —— 旅币/背包/心神/遮罩/存档，外加 shop_data 与 road_data 的一致性。
##
## 所有预算数字都在本脚本里按公式重算，**不要照抄**。
## 改 GameManager 的 LVBI_* 常量或 shop_data.gd 的价格后，这里会自己算出新结果。
##
## 跑法： godot --headless --path . --script tools/verify_economy.gd
## 会在 user://gift188.cfg 上读写存档：开跑前备份，跑完还原。

var _fails: Array = []
var _oks := 0
var _gm = null
var _sd = null
var _rd = null


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


func _basket_cost(ids: Array) -> int:
	var c := 0
	for gid in ids:
		c += int(_sd.good(str(gid)).get("price", 0))
	return c


func _count_shops_on_fragment_stations() -> int:
	var n := 0
	for i in range(_rd.stations.size()):
		if _rd.stations[i].get("shop", "") != "" and _rd.station_has_fragment(i):
			n += 1
	return n


## 里程不许再出现在任何玩家可见的文案里。
##
## 世界只有 1228.8m 一圈，188 摊上去就是 2km/s —— 玩家骑三十秒就能心算出
## 7200km/h，然后顶栏、灯铺那道 60km 的门、郑铎那三场 50/100/150km 的戏会一起
## 变成噪音。以后有人想再加一条带里程的提示，这条会当场拦下。
##
## 关键词要查全：只查 "km" 会漏掉中文的「公里」和英文的 "kilometer"——
## 第一版就漏了 onboarding_subtitle 的「沿188公里环形路线」。
## 还要再带上英式拼法 "kilometre"：它不是 "kilometer" 的子串（e 和 r 换了位置），
## ending_keep_desc 里的 "188 kilometres" 就是这么活到现在的。
##
## 里程碑牌号走正则而不是关键词表。原来写的是 "K0" 和 "K188" 两个**字面量**，
## 于是 villain_2_1 的「K91 那一带有一条老路基…」两个都匹配不到 ——
## 而那是全表里唯一真带着里程的一句正文，偏偏被一条看着齐全的扫描放过了。
## 现在用 K\\d+ 匹配任意编号，以后写 K7、K250 一样拦得住。
const _KM_WORDS := ["km", "公里", "kilometer", "kilometre"]


func _check_km_offscreen() -> void:
	var loc_script: GDScript = load("res://scripts/Localization.gd")
	var milepost := RegEx.new()
	milepost.compile("K\\d+")
	var hits: Array[String] = []
	for lang in ["zh", "en"]:
		var table: Dictionary = loc_script.STRINGS[lang]
		for key in table.keys():
			var s := str(table[key])
			for w in _KM_WORDS:
				if s.contains(w):
					hits.append("[%s] %s 命中「%s」：%s" % [lang, key, w, s])
			var m := milepost.search(s)
			if m != null:
				hits.append("[%s] %s 命中里程碑牌号「%s」：%s" % [lang, key, m.get_string(), s])
	# 一次断言报全部，而不是每个 key 每种写法各报一条 ——
	# 漏网必须是"看得见的一件事"，不能被淹没在几百条 OK 里。
	_ck("STRINGS 里没有任何里程（逐条列在下面）", hits.is_empty(),
			"\n        " + "\n        ".join(hits))


## 预算按公式重算，不引用任何硬编码结论
func _recompute() -> Dictionary:
	var km := int(floorf(float(_gm.TOTAL_ROUTE_KM)))
	var passes := int(_rd.stations.size())
	var frags := int(_rd.FRAGMENT_SLOT_STATION_IDX.size())
	var repeats := int(_gm.MAX_VISITS_PER_STATION) - 1

	var full := 0
	full += km * int(_gm.LVBI_PER_KM)
	full += passes * int(_gm.LVBI_PER_PASS)
	full += frags * int(_gm.LVBI_FIRST_CHECKIN)
	full += frags * repeats * int(_gm.LVBI_REPEAT_CHECKIN)
	full += frags * int(_gm.LVBI_MINI_WIN)
	full += frags * int(_gm.LVBI_PER_FRAGMENT)

	# 合理全购：明信片只算最高一档，其余按 max_own 买满
	var sens := 0
	var best_tier := 0
	for g in _sd.GOODS:
		if str(g.get("grant", "")) == "postcard_tier":
			best_tier = maxi(best_tier, int(g.get("tier_rank", 1)))
	for g in _sd.GOODS:
		if str(g.get("grant", "")) == "postcard_tier":
			if int(g.get("tier_rank", 0)) == best_tier:
				sens += int(g.get("price", 0))
		else:
			sens += int(g.get("price", 0)) * int(g.get("max_own", 1))

	var ride_only := km * int(_gm.LVBI_PER_KM) + passes * int(_gm.LVBI_PER_PASS)

	return {
		"km": km, "passes": passes, "frags": frags, "repeats": repeats,
		"full": full, "sensible": sens, "gap": sens - full, "ride_only": ride_only,
		"plain": int(_sd.good("kit_plain").get("price", -1)),
		"fine": int(_sd.good("kit_fine").get("price", -1)),
		"rare": int(_sd.good("kit_rare").get("price", -1)),
	}


func _run() -> void:
	print("=== 经济系统回归 ===")

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
	_check_km_offscreen()

	# 存档备份：测试全程在 user://gift188.cfg 上写
	var backup := ""
	if FileAccess.file_exists(str(_gm.SAVE_PATH)):
		var rf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			backup = rf.get_as_text()
			rf.close()
	_gm.reset()

	var b: Dictionary = _recompute()

	# ---- 1. 预算口径 ----
	print("--- 预算（按公式重算）---")
	print("    里程 %d×%d + 路过 %d×%d + 首次打卡 %d×%d + 重复打卡 %d×%d + 小游戏 %d×%d + 碎片 %d×%d" % [
		b["km"], int(_gm.LVBI_PER_KM), b["passes"], int(_gm.LVBI_PER_PASS),
		b["frags"], int(_gm.LVBI_FIRST_CHECKIN), b["frags"] * b["repeats"], int(_gm.LVBI_REPEAT_CHECKIN),
		b["frags"], int(_gm.LVBI_MINI_WIN), b["frags"], int(_gm.LVBI_PER_FRAGMENT)])
	print("    全清 %d / 合理全购 %d / 缺口 %d / 只骑全程 %d" % [
		b["full"], b["sensible"], b["gap"], b["ride_only"]])

	_eq("全清总额 = 799", b["full"], 799)
	_eq("合理全购 = 1010", b["sensible"], 1010)
	_eq("缺口 = 211", b["gap"], 211)
	_eq("只骑全程 = 424", b["ride_only"], 424)
	_ck("缺口 ≥ 90（必须做一次减法）", b["gap"] >= 90)
	_eq("素笺 0 旅币（明信片永远拿得到）", b["plain"], 0)
	_ck("只骑全程买得上笺", b["ride_only"] >= b["fine"])
	_ck("只骑全程买不了珍藏", b["ride_only"] < b["rare"])
	_ck("全清买得起珍藏", b["full"] >= b["rare"])
	_budget_comment_section(b)

	# ---- 2. 商品表与铺子 ----
	_eq("商品数 10", int(_sd.GOODS.size()), 10)
	_eq("铺子数 3", int(_sd.SHOPS.size()), 3)
	for sn in ["驿铺", "茶铺", "灯铺"]:
		_ck("%s 有货可卖" % sn, not _sd.goods_for_shop(sn).is_empty())
	# 门槛是"路过多少座驿"，不是里程：km 门在 1228.8m 的世界里开局三十秒就冲过去了。
	_eq("灯铺 6 驿解锁", int(_sd.shop_unlock_seen("灯铺")), 6)
	_eq("驿铺开局即开", int(_sd.shop_unlock_seen("驿铺")), 0)
	_eq("铺子不占碎片站", _count_shops_on_fragment_stations(), 0)

	var tagged := 0
	for i in range(int(_rd.stations.size())):
		var tag = _rd.stations[i].get("shop", "")
		if tag != "":
			tagged += 1
			_ck("station %d 的铺子 '%s' 在 SHOPS 里" % [i, tag], _sd.SHOPS.has(tag))
			_eq("SHOPS['%s'].station_idx 对得上" % tag, int(_sd.shop_station_idx(tag)), i)
			_eq("shop_at_station(%d) 对得上" % i, str(_sd.shop_at_station(i)), tag)
	_eq("带 shop 字段的站 3 个", tagged, 3)

	var nfs = _sd.NOT_FOR_SALE
	_eq("无价栏 5 个字", int(nfs.size()), 5)
	for f in nfs:
		_eq("'%s' 不是可购买商品" % f, _sd.good(str(f)).is_empty(), true)
	for idx in _rd.FRAGMENT_SLOT_STATION_IDX:
		_ck("碎片站的 '%s' 都在无价栏" % str(_rd.stations[idx].get("fragment", "")),
			nfs.has(_rd.stations[idx].get("fragment", "")))

	# ---- 3. 三种收法都够买珍藏 ----
	var baskets = {
		"A": ["kit_rare", "lamp", "lamp", "env", "seal", "sachet"],
		"B": ["kit_rare", "lamp", "paper", "env", "seal", "sachet"],
		"C": ["kit_rare", "lamp", "ink", "env", "seal", "sachet"],
	}
	_eq("收法 A = 780", _basket_cost(baskets["A"]), 780)
	_eq("收法 B = 750", _basket_cost(baskets["B"]), 750)
	_eq("收法 C = 740", _basket_cost(baskets["C"]), 740)
	for name in baskets:
		_ck("收法 %s（%d）≤ 全清（%d）" % [name, _basket_cost(baskets[name]), b["full"]],
			_basket_cost(baskets[name]) <= b["full"])

	# ---- 4. earn 幂等 ----
	_gm.reset()
	_eq("初始旅币 0", int(_gm.lvbi), 0)
	_eq("首次 earn 入账", int(_gm.earn(5, "t1")), 5)
	_eq("earn 后余额 5", int(_gm.lvbi), 5)
	_eq("同 tag 重复 earn 返回 0", int(_gm.earn(5, "t1")), 0)
	_eq("同 tag 不重复入账", int(_gm.lvbi), 5)
	_eq("不同 tag 正常入账", int(_gm.earn(7, "t2")), 7)
	_eq("负数 earn 被拒", int(_gm.earn(-3, "t3")), 0)
	_eq("零值 earn 被拒", int(_gm.earn(0, "t4")), 0)

	# ---- 5. earn_km 只按整公里发钱 ----
	_gm.reset()
	var expect_full := int(floorf(float(_gm.TOTAL_ROUTE_KM))) * int(_gm.LVBI_PER_KM)
	_eq("满程一次发 376", int(_gm.earn_km(float(_gm.TOTAL_ROUTE_KM))), expect_full)
	_eq("满程后余额 376", int(_gm.lvbi), expect_full)
	_eq("满程后再发 0", int(_gm.earn_km(float(_gm.TOTAL_ROUTE_KM))), 0)
	_eq("负数里程不发负数", int(_gm.earn_km(-5.0)), 0)

	_gm.reset()
	_eq("0.5 km 不发钱", int(_gm.earn_km(0.5)), 0)
	_eq("0.9 km 不发钱", int(_gm.earn_km(0.9)), 0)
	_eq("到 1 km 发 2", int(_gm.earn_km(1.0)), int(_gm.LVBI_PER_KM))
	_eq("1.9 km 不增发", int(_gm.earn_km(1.9)), 0)
	_eq("到 3 km 再发 4", int(_gm.earn_km(3.0)), int(_gm.LVBI_PER_KM) * 2)
	_eq("倒退不发负数", int(_gm.earn_km(0.2)), 0)
	_eq("累计 3 公里 = 6", int(_gm.lvbi), int(_gm.LVBI_PER_KM) * 3)
	_eq("倒退后里程不倒扣", float(_gm.spent_km) >= 0.0, true)

	# ---- 6. 路过 / 打卡 / 小游戏 ----
	_gm.reset()
	_eq("首次路过 +3", int(_gm.on_station_pass(0)), int(_gm.LVBI_PER_PASS))
	_eq("重复路过不发", int(_gm.on_station_pass(0)), 0)
	var pass_total := int(_gm.LVBI_PER_PASS)
	for i in range(1, int(_rd.stations.size())):
		pass_total += int(_gm.on_station_pass(i))
	_eq("16 站路过合计 = 48", pass_total, 48)

	_gm.reset()
	_gm.check_in(0)
	_eq("非碎片站不记账", int(_gm.get_station_count(0)), 0)
	_eq("非碎片站不发旅币", int(_gm.lvbi), 0)

	_gm.reset()
	_gm.check_in(7)
	_eq("碎片站首次打卡 = 15 + 30", int(_gm.lvbi), int(_gm.LVBI_FIRST_CHECKIN) + int(_gm.LVBI_PER_FRAGMENT))
	_eq("首次打卡心神 4→3", int(_gm.mood), int(_gm.MOOD_INITIAL) - 1)
	_gm.check_in(7)
	_eq("第二次打卡 +5", int(_gm.lvbi),
		int(_gm.LVBI_FIRST_CHECKIN) + int(_gm.LVBI_PER_FRAGMENT) + int(_gm.LVBI_REPEAT_CHECKIN))
	_eq("第二次打卡心神不再掉", int(_gm.mood), int(_gm.MOOD_INITIAL) - 1)
	_gm.check_in(7)
	_eq("第三次打卡 +5", int(_gm.lvbi),
		int(_gm.LVBI_FIRST_CHECKIN) + int(_gm.LVBI_PER_FRAGMENT) + int(_gm.LVBI_REPEAT_CHECKIN) * 2)
	_gm.check_in(7)
	_eq("第四次打卡被拒", int(_gm.get_station_count(7)), int(_gm.MAX_VISITS_PER_STATION))
	_eq("碎片站打满 3 次 = 55", int(_gm.lvbi),
		int(_gm.LVBI_FIRST_CHECKIN) + int(_gm.LVBI_PER_FRAGMENT) + int(_gm.LVBI_REPEAT_CHECKIN) * 2)

	_gm.reset()
	_eq("小游戏成功 +20", int(_gm.on_mini_game(7, true)), int(_gm.LVBI_MINI_WIN))
	_eq("同站成功不重复", int(_gm.on_mini_game(7, true)), 0)
	_eq("失败也 +5", int(_gm.on_mini_game(7, false)), int(_gm.LVBI_MINI_LOSE))
	_eq("同站失败不重复", int(_gm.on_mini_game(7, false)), 0)

	# ---- 7. 心神下限与遮罩 ----
	_gm.reset()
	_eq("初始心神 4", int(_gm.mood), int(_gm.MOOD_INITIAL))
	for i in range(5):
		_gm.cost_mood(1)
	_eq("连扣 5 次只落到下限 1", int(_gm.mood), int(_gm.MOOD_FLOOR))
	_eq("下限不再掉", int(_gm.cost_mood(1)), 0)

	var alphas: Array = []
	for m in [5, 4, 3, 2, 1]:
		_gm.mood = m
		alphas.append(float(_gm.get_mood_mask_alpha()))
	_eq("心神 5 遮罩为 0", alphas[0], 0.0)
	_eq("心神 1 遮罩最浓", alphas[4], float(_gm.MOOD_MASK_MAX))
	_ck("遮罩随心神单调变浓", alphas[0] <= alphas[1] and alphas[1] <= alphas[2]
		and alphas[2] <= alphas[3] and alphas[3] <= alphas[4])
	_ck("遮罩不超上限", alphas[4] <= float(_gm.MOOD_MASK_MAX) + 1e-6)

	# 灯笼 / 香囊改走视野系数，不动遮罩。遮罩只随心神走。
	var near = func(a: float, b: float, e: float = 1e-6) -> bool: return absf(a - b) < e

	_gm.reset()
	_gm.mood = int(_gm.MOOD_FLOOR)
	var mask_at_floor := float(_gm.get_mood_mask_alpha())
	_gm.inv["lamp"] = 2
	_gm.inv["sachet"] = 1
	_eq("买了灯笼/香囊遮罩不变", float(_gm.get_mood_mask_alpha()), mask_at_floor)

	_gm.inv = {}
	_gm.mood = int(_gm.MOOD_CEIL)
	_ck("心神满视野全开", near.call(float(_gm.get_visibility_factor()), 1.0))
	_gm.mood = int(_gm.MOOD_FLOOR)
	_ck("心神 1 收到 0.65", near.call(float(_gm.get_visibility_factor()), 0.65),
			"got=%f" % float(_gm.get_visibility_factor()))
	_gm.inv["lamp"] = 1
	_ck("一盏灯笼 +25%", near.call(float(_gm.get_visibility_factor()), 0.65 * 1.25),
			"got=%f" % float(_gm.get_visibility_factor()))
	_gm.inv["lamp"] = 2
	# 方案 §7.1 的算例：0.65 × 1.50 = 0.975
	_ck("两件灯笼 = 0.975", near.call(float(_gm.get_visibility_factor()), 0.975),
			"got=%f" % float(_gm.get_visibility_factor()))
	_gm.inv["lamp"] = 3
	_ck("第三盏不再加", near.call(float(_gm.get_visibility_factor()), 0.975))
	_gm.inv["sachet"] = 1
	# 香囊把 0.35 的惩罚砍半成 0.175，1-0.175 = 0.825，再乘 1.5 = 1.2375 → 夹到 1.0
	_ck("买满仍不超基线", near.call(float(_gm.get_visibility_factor()), 1.0))
	_gm.inv = {"sachet": 1}
	_ck("香囊把心神惩罚减半", near.call(float(_gm.get_visibility_factor()), 1.0 - 0.35 * 0.5),
			"got=%f" % float(_gm.get_visibility_factor()))
	_ck("系数不低于下限", float(_gm.get_visibility_factor()) >= float(_gm.VIS_FLOOR))
	_ck("系数不超基线", float(_gm.get_visibility_factor()) <= 1.0)

	# ---- 8. 购物校验 ----
	_gm.reset()
	var plain = _sd.good("kit_plain")
	var fine = _sd.good("kit_fine")
	var rare = _sd.good("kit_rare")
	var lamp = _sd.good("lamp")
	var paper = _sd.good("paper")

	_eq("lvbi=0 能买素笺（无失败态证明）", _gm.can_buy(plain), true)
	_eq("lvbi=0 买素笺成功", _gm.buy(plain), true)
	_eq("素笺不花钱", int(_gm.lvbi), 0)
	_eq("档位升到 1", int(_gm.get_postcard_tier()), 1)
	_eq("素笺买了不能再买", _gm.can_buy(plain), false)
	_eq("lvbi=0 买不了上笺", _gm.can_buy(fine), false)
	_eq("lvbi=0 买不了珍藏", _gm.can_buy(rare), false)

	_gm.lvbi = 1000
	_eq("有钱能买上笺", _gm.can_buy(fine), true)
	_eq("上笺覆盖素笺", _gm.buy(fine), true)
	_eq("档位升到 2", int(_gm.get_postcard_tier()), 2)
	_eq("上笺后余额 820", int(_gm.lvbi), 820)
	_eq("同档不能重买", _gm.buy(fine), false)
	_eq("低档不能覆盖高档", _gm.buy(plain), false)
	_eq("碎片不足买不了珍藏", _gm.can_buy(rare), false)

	for st in _rd.FRAGMENT_SLOT_STATION_IDX:
		_gm.collected[st] = 1
	_eq("5 碎片后能买珍藏", _gm.can_buy(rare), true)
	_eq("买珍藏成功", _gm.buy(rare), true)
	_eq("档位升到 3", int(_gm.get_postcard_tier()), 3)

	_eq("灯笼第一只", _gm.buy(lamp), true)
	_eq("灯笼第二只", _gm.buy(lamp), true)
	_eq("灯笼第三只被拒", _gm.can_buy(lamp), false)
	_eq("灯笼已购 2", int(_gm.get_item_count("lamp")), 2)
	_eq("宣纸第一张", _gm.buy(paper), true)
	_eq("宣纸第二张被拒", _gm.can_buy(paper), false)
	_eq("背包里有宣纸", _gm.has_item("paper"), true)
	_eq("没买过的东西 has_item 为假", _gm.has_item("ink"), false)

	# ---- 9. 剧情进度 ----
	_gm.reset()
	_eq("序章未完成", _gm.prologue_done, false)
	_gm.mark_prologue_done()
	_eq("序章已完成", _gm.prologue_done, true)
	_gm.mark_prologue_done()
	_eq("序章标记幂等", _gm.prologue_done, true)

	_eq("第一场反派该播", _gm.claim_villain_scene(1), true)
	_eq("第一场不重播", _gm.claim_villain_scene(1), false)
	_eq("第三场不能先于第二场", _gm.claim_villain_scene(3), false)
	_eq("第二场该播", _gm.claim_villain_scene(2), true)
	_eq("第三场该播", _gm.claim_villain_scene(3), true)
	_eq("没有第四场", _gm.claim_villain_scene(4), false)
	_eq("seen_villain = 3", int(_gm.seen_villain), 3)

	_gm.set_ending("keep")
	_eq("结局已记录", _gm.ending_id, "keep")
	_gm.set_ending("break")
	_eq("结局可改", _gm.ending_id, "break")

	# ---- 10. 存档往返 ----
	_gm.reset()
	_gm.lvbi = 424
	_gm.earn_km(30.0)
	_gm.on_station_pass(5)
	_gm.collected[7] = 1
	_gm.mood = 2
	_gm.inv = {"postcard_tier": 2, "lamp": 1, "paper": 1}
	_gm.seen_villain = 2
	_gm.prologue_done = true
	_gm.ending_id = "keep"
	_gm._save_game()

	var want := {
		"lvbi": int(_gm.lvbi), "spent_km": float(_gm.spent_km), "mood": int(_gm.mood),
		"seen_villain": int(_gm.seen_villain), "prologue_done": _gm.prologue_done,
		"ending_id": _gm.ending_id, "tier": int(_gm.get_postcard_tier()),
		"lamp": int(_gm.get_item_count("lamp")), "paper": int(_gm.get_item_count("paper")),
		"collected": int(_gm.get_station_count(7)), "pass_tag": _gm.earned_tags.has("pass_5"),
	}

	# 注意：reset() 会 _clear_save() 把存档删掉，所以这里不调 reset，
	# 而是手动清零字段再读档。
	_gm.lvbi = 0
	_gm.inv = {}
	_gm.spent_km = 0.0
	_gm.earned_tags = {}
	_gm.seen_stations = {}
	_gm.mood = int(_gm.MOOD_INITIAL)
	_gm.seen_villain = 0
	_gm.prologue_done = false
	_gm.ending_id = ""
	for k in _gm.collected.keys():
		_gm.collected[k] = 0
	_gm._load_save()
	_eq("存档往返 lvbi", int(_gm.lvbi), want["lvbi"])
	_eq("存档往返 spent_km", float(_gm.spent_km), want["spent_km"])
	_eq("存档往返 mood", int(_gm.mood), want["mood"])
	_eq("存档往返 seen_villain", int(_gm.seen_villain), want["seen_villain"])
	_eq("存档往返 prologue_done", _gm.prologue_done, want["prologue_done"])
	_eq("存档往返 ending_id", _gm.ending_id, want["ending_id"])
	_eq("存档往返 postcard_tier", int(_gm.get_postcard_tier()), want["tier"])
	_eq("存档往返 lamp", int(_gm.get_item_count("lamp")), want["lamp"])
	_eq("存档往返 paper", int(_gm.get_item_count("paper")), want["paper"])
	_eq("存档往返 collected", int(_gm.get_station_count(7)), want["collected"])
	_eq("存档往返 earned_tags", _gm.earned_tags.has("pass_5"), want["pass_tag"])
	_eq("读档后同 tag 仍幂等", int(_gm.earn(int(_gm.LVBI_PER_PASS), "pass_5")), 0)
	_eq("读档后里程不重发", int(_gm.earn_km(30.0)), 0)

	# ---- 11. reset 清零 ----
	_gm.reset()
	_eq("reset 后 lvbi 0", int(_gm.lvbi), 0)
	_eq("reset 后背包空", _gm.inv.is_empty(), true)
	_eq("reset 后 spent_km 0", float(_gm.spent_km), 0.0)
	_eq("reset 后心神回初始", int(_gm.mood), int(_gm.MOOD_INITIAL))
	_eq("reset 后 seen_villain 0", int(_gm.seen_villain), 0)
	_eq("reset 后序章未完成", _gm.prologue_done, false)
	_eq("reset 后结局清空", _gm.ending_id, "")
	_eq("reset 后 earned_tags 空", _gm.earned_tags.is_empty(), true)
	_eq("reset 后 seen_stations 空", _gm.seen_stations.is_empty(), true)
	_eq("reset 后存档已删", FileAccess.file_exists(str(_gm.SAVE_PATH)), false)

	# ---- 还原存档 ----
	if backup != "":
		# 三份一起收：存档改成原子写之后，跑一遍会多出 .bak / .tmp，只写回正本会把它们留在盘上
		_gm._clear_save()
		var wf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	else:
		_gm._clear_save()

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)



## 799 / 1010 / 211 这个三连**在三个地方各手抄了一份**：这一段断言的字面量、
## `GameManager.gd` 头部的预算注释、`shop_data.gd` 头部的预算注释。
## 上面那几条 `_eq` 钉的是第一份，而**后两份谁都没钉**——加一件商品、
## 改一个 `LVBI_*` 常量之后，这三处会安静地分叉，而下一个人照着注释里的
## 799 去算预算，算出来的缺口已经不是产品的那个缺口了。
##
## 这一族和 `edge_line_color`、`_draw` 不落盘并排：**症状不是红，是一句错话**。
## 所以钉的方式是"从那两份注释里把数抠出来，和 `_recompute()` 当场比"，
## 而不是"注释里不许出现某个数"（后者改文案就红，而文案本来就是给人读的）。
##
## 判据量的是**注释**而不是代码，所以这里**刻意不剔注释**——那一节的规矩
## 是"搜到的字符串可能出现在注释里"，这里要的恰恰是那个注释。
## 词表（`全清` / `全购` / `缺口`）是锚点：认不出锚点会返回 -1，
## 那样 `_eq(-1, 799)` 照样红，所以每份文件先各断一条"锚点找得到"。
func _budget_comment_section(b: Dictionary) -> void:
	print("--- 预算注释不许和公式分叉 ---")
	for path in ["res://scripts/GameManager.gd", "res://scripts/shop_data.gd"]:
		var fname: String = path.get_file()
		if not FileAccess.file_exists(path):
			_ck("%s 存在" % fname, false)
			continue
		var txt := FileAccess.get_file_as_string(path)
		for pair in [["全清", int(b["full"])],
				["全购", int(b["sensible"])],
				["缺口", int(b["gap"])]]:
			var anchor: String = pair[0]
			var want: int = pair[1]
			var got := _number_after(txt, anchor)
			_ck("%s 里有「%s」那一行" % [fname, anchor], got != -1,
				"找不到锚点，后面那条会拿 -1 去比而看不出是'没找到'")
			_eq("%s 的「%s」和公式重算一致" % [fname, anchor], got, want)


## 取 anchor 之后**第一行**里的第一个整数。取第一行是有意的：
## `shop_data.gd` 那行三个数连着写（"全清总收入 799 旅币；合理全购 1010；
## 缺口 211"），而 `GameManager.gd` 是三行——两种排版用同一个办法都吃得下。
func _number_after(txt: String, anchor: String) -> int:
	for line in txt.split("\n"):
		var i := line.find(anchor)
		if i < 0:
			continue
		var tail := line.substr(i + anchor.length())
		var re := RegEx.new()
		re.compile("\\d+")
		var m := re.search(tail)
		if m != null:
			return int(m.get_string())
	return -1
