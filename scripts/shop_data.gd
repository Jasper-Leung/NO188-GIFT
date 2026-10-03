class_name ShopData
## 三铺与商品表 —— 纯数据，无逻辑。照 road_data.gd 的写法：静态数组 + 只读访问器。
##
## 三条铺子各占一座非碎片驿站，骑过去才买得到（road_data.gd 的 stations[i]["shop"] 与此表对齐）。
## 加商品只改这里的数组，ShopPanel 不硬编码任何价格或名字。
##
## 预算口径（见 tools/verify_economy.gd 重算，不要照抄）：
##   理想全清总收入 799 旅币；合理全购 1010 旅币；缺口 211（两盏半灯笼）。
##   素笺 0 旅币 = 「明信片永远拿得到」的机器证明。

## 三铺。key 与 road_data.gd 的 stations[i]["shop"] 完全一致（中文原名）。
## name_en 用于英文界面；seen_unlock > 0 的铺子在"路过这么多座驿"之前不开。
##
## 门槛原来写的是 km_unlock = 60，那是道纸糊的门：世界一圈只有 1228.8m，
## 顶栏按 188 换算下来 2km/s，开局三十秒就冲过 60 了 —— 一个必然被白送跨过的
## 解锁条件等于没有。改成驿数，玩家在顶栏就能看着这个数往上爬。
const SHOPS := {
	"驿铺": {"name_en": "Station Shop", "station_idx": 0, "seen_unlock": 0},
	"茶铺": {"name_en": "Tea Shop", "station_idx": 2, "seen_unlock": 0},
	"灯铺": {"name_en": "Lantern Shop", "station_idx": 8, "seen_unlock": 6},
}

## 明信片三档套餐等级，与 Postcard.gd 的档位对应。互斥升级：只买更高的一档。
const KIT_PLAIN := 1
const KIT_FINE := 2
const KIT_RARE := 3

## 商品表。grant 是纯字符串标记，写入 inv 的语义由 GameManager 解析：
##   kit_*  → 写 inv["postcard_tier"]（取最高档，不叠）
##   其它    → inv[id] = 已有数量 + 1，上限 max_own（缺省 1）
## tier_rank / max_own / cap 只在需要的商品上出现，其余 .get() 兜底。
const GOODS := [
	{"id": "kit_plain", "name": "素笺", "name_en": "Plain Sheet",
		"price": 0, "sell_at": "驿铺", "requires_fragments": 0,
		"grant": "postcard_tier", "tier_rank": 1,
		"desc": "最普通的纸。能写字，这就够了。",
		"desc_en": "Plainest paper. It holds ink, which is enough."},
	{"id": "kit_fine", "name": "上笺", "name_en": "Fine Sheet",
		"price": 180, "sell_at": "驿铺", "requires_fragments": 0,
		"grant": "postcard_tier", "tier_rank": 2,
		"desc": "帘纹细密，压得住墨。",
		"desc_en": "Fine laid, it holds ink without bleeding."},
	{"id": "kit_rare", "name": "珍藏笺", "name_en": "Rare Sheet",
		"price": 460, "sell_at": "驿铺", "requires_fragments": 5,
		"grant": "postcard_tier", "tier_rank": 3,
		"desc": "需要五块碎片齐了才肯卖给你。",
		"desc_en": "Only sold once all five fragments are in hand."},

	{"id": "paper", "name": "宣纸", "name_en": "Rice Paper",
		"price": 60, "sell_at": "驿铺", "requires_fragments": 0,
		"grant": "paper_up", "max_own": 1,
		"desc": "换一张更好的纸面。",
		"desc_en": "Upgrades the paper face."},
	{"id": "ink", "name": "松烟墨", "name_en": "Pine Ink",
		"price": 50, "sell_at": "驿铺", "requires_fragments": 0,
		"grant": "ink_up", "max_own": 1,
		"desc": "松烟磨的墨，沉而不发黑。",
		"desc_en": "Pine-soot ink; deep without going black."},
	{"id": "env", "name": "信封", "name_en": "Envelope",
		"price": 40, "sell_at": "驿铺", "requires_fragments": 0,
		"grant": "has_envelope", "max_own": 1,
		"desc": "装起来，才算一封寄不出去的信。",
		"desc_en": "Only once folded can it be called an unsent letter."},

	{"id": "seal", "name": "蜡封", "name_en": "Wax Seal",
		"price": 45, "sell_at": "灯铺", "requires_fragments": 0,
		"grant": "has_seal", "max_own": 1,
		"desc": "封口的蜡，盖一个驿的印。",
		"desc_en": "Wax to seal, stamped with the post's mark."},
	{"id": "lamp", "name": "灯笼", "name_en": "Lantern",
		"price": 90, "sell_at": "灯铺", "requires_fragments": 0,
		"grant": "vision_up", "max_own": 2, "cap": 0.50,
		"desc": "一件 +25% 视野，两件封顶 +50%。",
		"desc_en": "Each lantern restores 25% sight; two cap at 50%."},

	{"id": "sachet", "name": "香囊", "name_en": "Sachet",
		"price": 55, "sell_at": "茶铺", "requires_fragments": 0,
		"grant": "vision_half_penalty", "max_own": 1,
		"desc": "心神每失一分，代价只算一半。",
		"desc_en": "Halves whatever the next lapse of mind costs you."},

	# 茶铺而不是灯铺：灯铺 seen_unlock=6，而收满五块碎片心神就见底了，
	# 放到灯铺等于"要等路况变差才准买解药"。
	{"id": "tea_clear", "name": "清心茶", "name_en": "Clear Heart Tea",
		"price": 40, "sell_at": "茶铺", "requires_fragments": 0,
		"grant": "mood_up", "mood_up": 1, "max_own": 3,
		"desc": "心神回一格。收一块碎片低一格，所以这是条来回的路。",
		"desc_en": "Composure back by one. Each fragment costs one; this is the way back."},
]

## 「无价」栏：渲染出来，不可购买。买得到纸，买不到云。
const NOT_FOR_SALE := ["云", "茶", "琴", "竹", "禽"]

const NOT_FOR_SALE_EN := {
	"云": "Cloud", "茶": "Tea", "琴": "Music", "竹": "Bamboo", "禽": "Bird",
}

## 驿站索引 → 铺名；-1 表示该站没有铺子。
const SHOP_AT_STATION := {
	0: "驿铺",
	2: "茶铺",
	8: "灯铺",
}


static func good_count() -> int:
	return GOODS.size()


static func good(id: String) -> Dictionary:
	for g in GOODS:
		if g.get("id", "") == id:
			return g
	return {}


static func goods_for_shop(shop_name: String) -> Array:
	var out: Array = []
	for g in GOODS:
		if g.get("sell_at", "") == shop_name:
			out.append(g)
	return out


static func shop_at_station(idx: int) -> String:
	return SHOP_AT_STATION.get(idx, "")


static func shop_station_idx(shop_name: String) -> int:
	var s: Dictionary = SHOPS.get(shop_name, {})
	return int(s.get("station_idx", -1))


static func shop_unlock_seen(shop_name: String) -> int:
	var s: Dictionary = SHOPS.get(shop_name, {})
	return int(s.get("seen_unlock", 0))


static func shop_display_name(shop_name: String) -> String:
	var s: Dictionary = SHOPS.get(shop_name, {})
	return s.get("name_en", shop_name) if Localization.is_english() else shop_name


static func good_display_name(g: Dictionary) -> String:
	return g.get("name_en", g.get("name", "")) if Localization.is_english() else g.get("name", "")


static func good_display_desc(g: Dictionary) -> String:
	return g.get("desc_en", g.get("desc", "")) if Localization.is_english() else g.get("desc", "")


static func not_for_sale_display() -> Array:
	if Localization.is_english():
		var out: Array = []
		for f in NOT_FOR_SALE:
			out.append(NOT_FOR_SALE_EN.get(f, f))
		return out
	return NOT_FOR_SALE.duplicate()
