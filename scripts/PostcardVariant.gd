extends RefCounted
class_name PostcardVariant
## 根据玩家收集状态计算明信片评级 (0-4)
## 0=初旅(1站) 1=探索者(2-3站) 2=朝圣者(4站) 3=大师(5站) 4=完满(任一驿站≥3次)

static func compute_variant() -> int:
	var visit_count := 0
	var max_visits := 0
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		var cnt: int = int(GameManager.collected.get(st_idx, 0))
		if cnt > 0:
			visit_count += 1
		if cnt > max_visits:
			max_visits = cnt
	# 完满: 任意驿站访问 ≥3 次
	if max_visits >= 3:
		return 4
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
