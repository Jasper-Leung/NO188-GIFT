extends RefCounted
class_name PostcardVariant
## 根据玩家收集状态计算明信片评级 (0-4)
## 0=初旅(1站) 1=探索者(2-3站) 2=朝圣者(3站) 3=大师(4-5站) 4=完满(五站各刷满)

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
