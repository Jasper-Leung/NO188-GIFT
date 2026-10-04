extends RefCounted
## 回访那一屏说什么话。
##
## 原来只有一句 `revisit_note`，而它在**第 2 次和第 3 次到访上逐字出现两遍**
## ——而完满评级要的正是三次到访。于是全游戏最强的重玩钩子，玩家在最该被
## 说服"再骑一趟"的那两趟里，读到的是同一段话；两句话不分先后，也分不出
## 哪一趟是最后一次。`verify_interact_latch.gd` 当时只断"面板说的是
## revisit_note"，那句话对两次到访都成立，**于是一个恒真的判据看起来像在守
## 这件事**。
##
## 现在按 (第几次到访 × 是不是已经绕完一整圈) 分四句。跨圈那一句承认
## "这是你第二次绕这条路"——里程是真骑出来的（`World3D._lap_index()` 从
## `_odometer_units` 算，本工程压根没有"圈数计数器"这个东西）。
##
## 独立成文件而不是塞进 World3D：照 MiniGamePicker 的老办法——preload，
## **不要 class_name**。`--script` 模式下加载 World3D.gd 会把整个场景脚本的
## 依赖拖进来，回归就量不到它（见 CLAUDE.md 已知陷阱）。

## 四个 key：索引 = (第几次到访 - 2) × 2 + (0 没过圈 / 1 已过圈)。
const KEYS: Array[String] = [
	"revisit_2nd_here",     # 0 第 2 次 · 还在第一圈
	"revisit_2nd_round",    # 1 第 2 次 · 已经绕完一圈
	"revisit_3rd_here",     # 2 第 3 次 · 还在第一圈
	"revisit_3rd_round",    # 3 第 3 次 · 已经绕完一圈
]


## `visit` 是**到这一次之前**已经来过几次（0 = 首次到访，1 = 第二次，
## 2 = 第三次，与 `GameManager.get_station_count()` 同一个口径）；
## `lap` 是骑过的整圈数（从 0 起）。
##
## 首次到访不归它管——那一趟有开场对白和「获得碎片」，走的是另一条分支。
static func key(visit: int, lap: int) -> String:
	var v: int = 0 if visit <= 1 else 1
	var l: int = 1 if lap >= 1 else 0
	return KEYS[v * 2 + l]


## 轮换到的那一件乐事叫什么。五件乐事和五块碎片是同一批东西（云/茶/琴/竹/禽），
## 名字在 `fragment_%d` 那五个 key 里，所以这里只做下标到 key 的翻译。
static func joy_key(joy_slot: int) -> String:
	return "fragment_%d" % joy_slot
