extends RefCounted
class_name PostcardVariant
## 根据玩家收集状态计算明信片评级 (0-4)
## 0=初旅(1站) 1=探索者(2站) 2=朝圣者(3站) 3=大师(4-5站) 4=完满(五站各刷满)
## （这一行原来写的是"探索者(2-3站)"，而下面的 `match` 里 2 和 3 是两档。
## 注释和它自己下一行的代码对不上——所以玩家的、README 的、代码注释的
## 三份档位说明各自都是一份事实来源。）

## 五档的名字。**这一段以前只存在于本文件的注释里**：`Localization` 一个字都没有，
## 玩家全程读不到自己拿到的是哪一档——README 那边还写的是「分**四**档」，把
## 完满（唯一有玩法含义的那一档）整个漏在外面。名字收在这里是因为档位表已经
## 有三个主人了（这里的 `compute_variant()` / `Postcard.VARIANT_LAYOUTS` /
## README），再加一份手抄就是第四个。
const TIER_KEYS: Array[String] = [
	"tier_0",  # 0 初旅
	"tier_1",  # 1 探索者
	"tier_2",  # 2 朝圣者
	"tier_3",  # 3 大师
	"tier_4",  # 4 完满
]


## 某一档叫什么（返回 key，由调用方过 `Localization.t()`）。越界夹回 0..4，
## 因为存档被裁剪过、评级算出来越界的话不该在屏上炸一个不存在的 key。
static func tier_name_key(v: int) -> String:
	return TIER_KEYS[clampi(v, 0, TIER_KEYS.size() - 1)]


## 一共几档。写出来是为了让"第 3 档 / 共 5 档"那句话的分母**由这份表出**，
## 而不是某个 Label 里又抄一个 5。
static func tier_count() -> int:
	return TIER_KEYS.size()


## 离「完满」还差多少次到访。玩家在暂停面板上盯着「结束这一趟」做决定时
## 问的就是这个，而此前那一屏只说"想刷完满还能再去两次"——那是集齐面板的
## 一句提示，不在他做决定的那一屏上。
static func visits_to_full() -> int:
	var left := 0
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		left += maxi(0, int(GameManager.MAX_VISITS_PER_STATION) - GameManager.get_station_count(st_idx))
	return left


static func compute_variant() -> int:
	# 完满只认 GameManager.all_fragments_maxed() 一个判据 —— 就是"HUD 的下一处
	# 消失"的那一刻，也是 World3D 结束这一趟的那一刻。
	# 原来这里自己算了一遍"任意一站到访 ≥3 次"，和那个判据不是一回事：
	# 玩家只把云影台刷满三次、另外四站只去过一次，评级就已经是"完满"了，
	# 而导航还在指另外四站。两张互相打架的指示牌。
	if GameManager.all_fragments_maxed():
		return 4
	var visit_count := 0
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if int(GameManager.collected.get(st_idx, 0)) > 0:
			visit_count += 1
	match visit_count:
		1: return 0  # 初旅
		2: return 1  # 探索者
		3: return 2  # 朝圣者
		4, 5: return 3  # 大师
	return 0


## 获取当前有效驿站列表(slot idx)，按站点顺序排列
static func get_visited_slots() -> Array[int]:
	var result: Array[int] = []
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if GameManager.collected.get(st_idx, 0) > 0:
			var slot: int = RoadData.FRAGMENT_STATION_TO_SLOT.get(st_idx, -1)
			if slot >= 0:
				result.append(slot)
	return result
