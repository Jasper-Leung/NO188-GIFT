extends RefCounted
## 五件乐事怎么轮着上。
##
## 原来 `_run_mini_game()` 里是一张「驿站 → 固定小游戏」的表，而且
## `World3D._do_check_in()` 只在 **首次到访** 时才进它。于是完满评级要求的
## 三次到访里，后两次**一件乐事都没有**：玩家第三次骑到云影台，脚下的圈写着
## 「再访 · 还差 1 次」，走进去只有一句「这件已经收过了」。全游戏最强的重玩
## 钩子，十次到访里十次是空的。
##
## 现在每一趟打卡都有一件乐事，按 (碎片槽位 + 第几次到访) 轮换：
##
##   · 第一次到访拿到的**还是**这座驿站自己的那件（云影台仍是描云），
##     所以第一趟的手感和配对关系一个字没变；
##   · 之后两趟依次往后挪，五座驿站串起来正好把五件乐事走一遍；
##   · 5 站 × 3 次 = 15 局，每件乐事正好各出现 3 次，不多不少。
##
## 独立成文件而不是塞进 World3D：这张表和轮换公式是纯逻辑，`--script` 模式下
## 加载 World3D.gd 会把整个场景脚本的依赖拖进来（见 CLAUDE.md 已知陷阱），
## 回归就没法量它了。所以照 MiniGameBackdrop 的老办法——preload，**不要
## class_name**。

## 顺序与碎片槽位 0..4 一致：云 / 茶 / 琴 / 竹 / 禽。
## 这是一条**独立副本**，和 `RoadData.FRAGMENT_SLOT_STATION_IDX` 的顺序必须
## 对得上——它决定"第一趟拿到的还是自己那件"。`verify_mini_game.gd` 第 7 节
## 拿真实的驿站表逐格对拍，抄错一处立刻红。
const SCRIPTS: Array[String] = [
	"res://scripts/mini_games/MiniGameCloud.gd",
	"res://scripts/mini_games/MiniGameTea.gd",
	"res://scripts/mini_games/MiniGameZither.gd",
	"res://scripts/mini_games/MiniGameBamboo.gd",
	"res://scripts/mini_games/MiniGameBird.gd",
]


## 第 `visit` 次到访（**从 0 起**）`slot` 号碎片驿站，该玩第几件。
##
## 纯函数：它只管算，不碰 GameManager 也不碰场景。visit 从 0 起算而不是 1，
## 是为了让「第一次到访 = 自己那件」这件事在公式里看得见——
## `slot + 0` 就是 slot，不用在调用处再补一次特判。
static func game_for(slot: int, visit: int) -> int:
	return (slot + maxi(visit, 0)) % SCRIPTS.size()


static func script_for(slot: int, visit: int) -> String:
	return SCRIPTS[game_for(slot, visit)]


## 15 局的完整排布。给 `lookdev_journey.gd` 和回归用：一行一个 slot，
## 三次到访从左到右。
static func schedule() -> Array:
	var out: Array = []
	for slot in SCRIPTS.size():
		var row: Array = []
		for visit in 3:
			row.append(game_for(slot, visit))
		out.append(row)
	return out
