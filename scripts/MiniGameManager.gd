class_name MiniGameManager
extends RefCounted
## MiniGameManager — 驿站小游戏派发器（备用，非必须）
## World3D._run_mini_game 直接内部处理，此文件保留作扩展接口

## 入口：await 等待结果
static func run(station_idx: int, world: Node) -> int:
	return await world._run_mini_game(station_idx) as int
