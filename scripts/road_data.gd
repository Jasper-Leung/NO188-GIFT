class_name RoadData
## 8 字环形路线 —— 由贝塞尔（lemniscate 参数方程）自行构造,非任何现实道路的复制。
## 路径天然闭合:索引 48 回到索引 0 (中心交叉)。
## 玩家从索引 1（站点 1,刚过中心下行）骑到索引 47（站点 16,接近中心第二次交叉）。
## 16 驿站按语义映射到特定 lemniscate 索引,保证站点落在曲线上。
## 本作路线为纯虚构的几何图案,不参考、不还原任何现实公路走向。
## 参数化坐标 -> 3D世界: x=(px-400)*0.5, z=(py-714)*0.5
## 完整的 188km 里程由 TOTAL_ROUTE_KM 与玩家实际骑行弧长比例换算,与几何尺度解耦。

const SCALE := 0.5
const CX := 400.0
const CY := 714.0

## 49 点 lemniscate（局部参数坐标,由中心向外按解析式采样,再旋转 60°/缩放/平移）。
## 索引 0 = (0, 0) 中心,索引 48 = 回到 (0, 0)。
## 旋转 60° + 缩放 350 + 平移 (400, 800) 后是画布坐标。
const LEMNISCATE_LOCAL: Array[Vector2] = [
	Vector2(0.0, 0.0),         # [0]  中心 (M)
	Vector2(0.1305, 0.1682),   # [1]  右环下行第 1 段
	Vector2(0.2588, 0.325),    # [2]
	Vector2(0.3827, 0.4596),   # [3]
	Vector2(0.5, 0.5629),      # [4]  右环下行第 2 段
	Vector2(0.6088, 0.6279),   # [5]
	Vector2(0.7071, 0.65),     # [6]  右环下行峰
	Vector2(0.7934, 0.6279),   # [7]
	Vector2(0.866, 0.5629),    # [8]
	Vector2(0.9239, 0.4596),   # [9]  右环右下沿
	Vector2(0.9659, 0.325),    # [10]
	Vector2(0.9914, 0.1682),   # [11] 右环右沿下行
	Vector2(1.0, 0.0),         # [12] 右环最右端
	Vector2(0.9914, -0.1682),  # [13]
	Vector2(0.9659, -0.325),   # [14] 右环上行第 1 段
	Vector2(0.9239, -0.4596),  # [15]
	Vector2(0.866, -0.5629),   # [16]
	Vector2(0.7934, -0.6279),  # [17]
	Vector2(0.7071, -0.65),    # [18] 右环上行峰
	Vector2(0.6088, -0.6279),  # [19] 右环左上沿
	Vector2(0.5, -0.5629),     # [20]
	Vector2(0.3827, -0.4596),  # [21]
	Vector2(0.2588, -0.325),   # [22]
	Vector2(0.1305, -0.1682),  # [23]
	Vector2(0.0, 0.0),         # [24] 中心交叉 1 (SVG 路径回到中心)
	Vector2(-0.1305, 0.1682),  # [25] 左环上行第 2 段(实际是从中心下行)
	Vector2(-0.2588, 0.325),   # [26]
	Vector2(-0.3827, 0.4596),  # [27] 左环下行第 1 段
	Vector2(-0.5, 0.5629),     # [28]
	Vector2(-0.6088, 0.6279),  # [29]
	Vector2(-0.7071, 0.65),    # [30] 左环左沿下行(峰值)
	Vector2(-0.7934, 0.6279),  # [31]
	Vector2(-0.866, 0.5629),   # [32]
	Vector2(-0.9239, 0.4596),  # [33]
	Vector2(-0.9659, 0.325),   # [34]
	Vector2(-0.9914, 0.1682),  # [35]
	Vector2(-1.0, 0.0),        # [36] 左环最左端
	Vector2(-0.9914, -0.1682), # [37]
	Vector2(-0.9659, -0.325),  # [38] 左环左上沿
	Vector2(-0.9239, -0.4596), # [39]
	Vector2(-0.866, -0.5629),  # [40]
	Vector2(-0.7934, -0.6279), # [41]
	Vector2(-0.7071, -0.65),   # [42] 左环最高点(峰值)
	Vector2(-0.6088, -0.6279), # [43]
	Vector2(-0.5, -0.5629),    # [44] 左环右下沿
	Vector2(-0.3827, -0.4596), # [45]
	Vector2(-0.2588, -0.325),  # [46]
	Vector2(-0.1305, -0.1682), # [47]
	Vector2(0.0, 0.0),         # [48] 中心 (Z 闭合)
]

const ROT_DEG := 60.0
const LEMNISCATE_SCALE := 350.0
const LEMNISCATE_CX := 400.0
const LEMNISCATE_CY := 800.0

## 16 驿站 → lemniscate 路径索引（保证驿站落在曲线上,语义位置不变）
const STATION_LEMNISCATE_IDX := [1, 4, 6, 9, 11, 12, 15, 18, 24, 27, 36, 39, 30, 42, 45, 47]

## ---- 驿站离路的横向偏移 ----
## snap 到曲线后驿站正好压在中心线上，亭子就架在车道中间。这里在 _init() 里
## 挑一个方向把整座驿位移到路面外侧，目标是整个模型脚底都落在路肩之外。
##
## canvas→world 是等比缩放（SCALE）+ 平移，方向不变，所以画布空间的单位向量
## 在 world 也是单位向量——「单位向量 × 想要的米数」直接就是 off（米）。
##
## 18m 的取值：RoadBuilder.TOTAL_HALF_WIDTH = 6.5m（4.0 车道半宽 + 2.5 路肩）。
## 驿站 GLB 的脚底半宽实测最大 7.8m（station_岭台.glb @ scale 10），
## 18 - 7.8 = 10.2m > 6.5m，所以最宽的模型也整个落在路肩外。又必须
## < World3D.STATION_PASS_RADIUS = 15 + 路宽，否则骑车在路面上触发不了打卡——
## 18 时玩家在路肩上离驿站 11.5m，够得着。
const STATION_OFFSET := 18.0

## 挑方向时按最宽的模型脚底估一个半宽（实测 GLB 最大 7.8m，取 8 留余量）。
## 只用来给候选方向排序，不改变 STATION_OFFSET；不加载 GLB 是为了让 RoadData
## 在任何 headless 上下文都能 new 出来。
const STATION_FOOT_HALF := 8.0

## 广场盘（RoadBuilder 的 PLAZA_CENTER / PLAZA_RADIUS：圆形沥青环岛，盖住 8 字
## 交叉处两条 ribbon 的重叠区）。本文件不依赖 RoadBuilder，这里重复声明一份，
## 与 TreeScatter / GrassScatter 的做法一致。
const PLAZA_CENTER := Vector2(0.0, 43.0)
const PLAZA_RADIUS := 12.0
## 交叉点那个驿站（索引 24）正落在广场圆心。那里两条 ribbon 夹角只有 ~76°，
## 垂直于任一条的方向几乎平行于另一条，光按 STATION_OFFSET 推会贴着另一条路走，
## 得单独推到广场盘外。广场那个驿站恰好是脚底最窄的模型（半宽 3.4m），
## 推到 16m 时离两条路各 12.6m、减脚底剩 9.2m，仍够玩家从路面 15m 内触发。
const PLAZA_STATION_MARGIN := 4.0

## 挑方向时扫的候选方向数（22.5° 一步）。只给两个法线方向会在交叉点退化：
## 那里的切线本身是两条路的角平分线，法线反而几乎平行于其中一条路。
const _DIR_STEPS := 16

## 相邻 lemniscate 点之间插的等分点数（不含端点本身）。
## 48 段 × 20 = 960 个 3D 点,RoadBuilder 再三次高斯平滑 + 0.5m 重采样。
const _INTERP_PER_SEG := 20


func _local_to_canvas(p: Vector2) -> Vector2:
	var rot := deg_to_rad(ROT_DEG)
	var xr := p.x * cos(rot) - p.y * sin(rot)
	var yr := p.x * sin(rot) + p.y * cos(rot)
	return Vector2(LEMNISCATE_CX + xr * LEMNISCATE_SCALE,
		LEMNISCATE_CY + yr * LEMNISCATE_SCALE)


func _build_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n = LEMNISCATE_LOCAL.size()
	for i in range(n - 1):
		var a: Vector2 = _local_to_canvas(LEMNISCATE_LOCAL[i])
		var b: Vector2 = _local_to_canvas(LEMNISCATE_LOCAL[i + 1])
		for k in range(_INTERP_PER_SEG):
			var t := float(k) / float(_INTERP_PER_SEG)
			var sx = lerpf(a.x, b.x, t)
			var sy = lerpf(a.y, b.y, t)
			out.append(Vector3((sx - CX) * SCALE, 0.0, (sy - CY) * SCALE))
	# 最后一段：从 index 47 → index 48（中心二次交叉）
	var a2: Vector2 = _local_to_canvas(LEMNISCATE_LOCAL[n - 2])
	var b2: Vector2 = _local_to_canvas(LEMNISCATE_LOCAL[n - 1])
	var t_last := 1.0
	var sx_last = lerpf(a2.x, b2.x, t_last)
	var sy_last = lerpf(a2.y, b2.y, t_last)
	out.append(Vector3((sx_last - CX) * SCALE, 0.0, (sy_last - CY) * SCALE))
	return out

var points: Array[Vector3] = _build_points()

## 8 字路线无支路。RoadBuilder / MiniMap 会空跑 branch 循环。
var branch_points: Array = []

## 16 个驿站（按节点顺序索引,与 lemniscate 索引一一对应）。
## model_idx 指向 World3D.STATION_GLB_CONFIG；-1 表示仅渲染 label + glow,无 GLB 模型。
## 5 个有碎片的驿站 fragment 顺序：云/茶/琴/竹/禽,与 Postcard.gd fragment_0..fragment_4 对齐。
## 索引 4 / 7 / 10 / 13 / 14 保留为碎片站,GameManager.collected[] 不变。

## FragmentBar / FragmentFlying / GameManager 用 0..4 的 slot idx（云/茶/琴/竹/禽）,
## 但 GameManager.collected[] 是 16 项驿站 idx。这里做双向映射:
##   slot i  → 驿站 idx(含碎片的驿站,按 slot 顺序)
##   驿站 idx → slot i(给驿站反查它对应哪个 slot;非碎片站返回 -1)
const FRAGMENT_SLOT_STATION_IDX: Array[int] = [7, 10, 13, 14, 4]
const FRAGMENT_STATION_TO_SLOT: Dictionary = {
	7: 0,	# 云影台   → slot 0 (云)
	10: 1,	# 茶烟小筑 → slot 1 (茶)
	13: 2,	# 琴音林   → slot 2 (琴)
	14: 3,	# 竹雨庭   → slot 3 (竹)
	4: 4,	# 禽语湖湾 → slot 4 (禽)
}
const FRAGMENT_COUNT := 5
var stations: Array = [
	{"name": "起程驿楼", "name_en": "Trailhead Pavilion", "event": "启程", "event_en": "Depart", "fragment": "", "fragment_en": "", "color": Color(0.55, 0.35, 0.25, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "shop": "驿铺", "text": "出门时天还早,风把名字叫得轻。", "text_en": "It is still early on departure day; the wind calls your name lightly.", "model_idx": 6},
	{"name": "东岭驿楼", "name_en": "East Ridge Pavilion", "event": "歇脚", "event_en": "Rest", "fragment": "", "fragment_en": "", "color": Color(0.72, 0.42, 0.22, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "歇脚的地方不赶人,坐多久都算数。", "text_en": "A place of rest never hurries anyone; however long you sit still counts.", "model_idx": 6},
	{"name": "南溪茶寮", "name_en": "South Creek Tea Pavilion", "event": "临水", "event_en": "Water", "fragment": "", "fragment_en": "", "color": Color(0.25, 0.6, 0.75, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "shop": "茶铺", "text": "溪水不回答任何问题,只是把你的倒影还给你。", "text_en": "The creek answers nothing; it only returns your reflection.", "model_idx": 7},
	{"name": "右岭岭台", "name_en": "Right Ridge Lookout", "event": "眺山", "event_en": "Ridge View", "fragment": "", "fragment_en": "", "color": Color(0.45, 0.65, 0.4, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "站在岭台上,山把自己让给你看。", "text_en": "From the ridge, the mountains give themselves to be looked at.", "model_idx": 8},
	{"name": "花房·禽语湖湾", "name_en": "Birdsong Cove Flower House", "event": "一只鸟替湖回答", "event_en": "A bird answers for the lake", "fragment": "禽", "fragment_en": "Bird", "color": Color(0.3, 0.6, 0.8, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "湖没有说话,一只鸟掠过水面,像替它回答了。", "text_en": "The lake says nothing; a bird skims the surface as if answering for it.", "dialogue": ["湖没有说话，一只鸟掠过水面，像替它回答了。", "你听见那声音时，风刚好也停了。", "她最后一次来，是坐着听的。听完就往南边去了。"], "dialogue_en": ["The lake says nothing; a bird skims the surface as if answering for it.", "By the time you hear it, the wind has just stopped.", "The last time she came, she sat and listened. Afterwards she went south."], "model_idx": 4},
	{"name": "岭口凉亭", "name_en": "Ridge Gate Pavilion", "event": "歇脚", "event_en": "Rest", "fragment": "", "fragment_en": "", "color": Color(0.6, 0.7, 0.35, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "凉亭的柱子凉一阵,人就坐得久一阵。", "text_en": "The pavilion's pillars stay cool a while, and so does whoever sits in them.", "model_idx": 10},
	{"name": "西湾神苑", "name_en": "West Cove Shrine", "event": "临水", "event_en": "Water", "fragment": "", "fragment_en": "", "color": Color(0.62, 0.3, 0.55, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "西湾的水上浮着一层薄雾,像神还没起床。", "text_en": "A thin mist floats on the west cove, as if the old gods have not woken yet.", "model_idx": 9},
	{"name": "云影台", "name_en": "Cloudshadow Terrace", "event": "雨后台阶看云", "event_en": "Watching clouds after rain", "fragment": "云", "fragment_en": "Cloud", "color": Color(0.5, 0.8, 0.9, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "雨刚停,云影落在台阶上,像一封没有署名的信。", "text_en": "After the rain, cloud shadows rest on the steps like an unsigned letter.", "dialogue": ["雨刚停，云影落在台阶上，像一封没有署名的信。", "在这封信里，你找到了自己的影子。", "你母亲也在这片云影里站过。她没留名，只留下一道比影子还浅的印。"], "dialogue_en": ["After the rain, cloud shadows rest on the steps like an unsigned letter.", "Within it, you find your own reflection.", "Your mother stood in this same cloud-shadow. She left no name, only a mark fainter than a shadow."], "model_idx": 0},
	{"name": "灯影亭", "name_en": "Lantern Pavilion", "event": "过灯", "event_en": "Lantern", "fragment": "", "fragment_en": "", "color": Color(0.9, 0.55, 0.2, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "shop": "灯铺", "text": "过灯。灯不认人,只认走夜路的人。", "text_en": "Past the lanterns. They know no one, only those who walk the night road.", "model_idx": 12},
	{"name": "北岭凉亭", "name_en": "North Ridge Pavilion", "event": "歇脚", "event_en": "Rest", "fragment": "", "fragment_en": "", "color": Color(0.55, 0.6, 0.7, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "北岭的风很直,在这里说话要慢一点。", "text_en": "The north wind blows straight; whoever speaks here must speak slowly.", "model_idx": 10},
	{"name": "茶烟小筑", "name_en": "Tea Smoke Cottage", "event": "朋友来了先煮茶", "event_en": "Tea for an arriving friend", "fragment": "茶", "fragment_en": "Tea", "color": Color(0.5, 0.7, 0.3, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "朋友来了,先煮一壶茶。水汽升起来,话就慢了。", "text_en": "When a friend arrives, brew tea first. As steam rises, conversation slows down.", "dialogue": ["朋友来了，先煮一壶茶。水汽升起来，话就慢了。", "等茶香散尽，有些东西已经说清楚了。", "她也在这里坐过一壶茶，没等谁开口，就先走了。"], "dialogue_en": ["When a friend arrives, brew tea first. As steam rises, conversation slows down.", "When the tea fragrance fades, some things have already been understood.", "She sat over a pot of tea here too, and left before anyone had to say anything."], "model_idx": 1},
	{"name": "左弯廊", "name_en": "Left Bend Corridor", "event": "歇脚", "event_en": "Rest", "fragment": "", "fragment_en": "", "color": Color(0.45, 0.35, 0.5, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "廊子很长,影子也跟着很长。", "text_en": "The corridor is long, and so are the shadows in it.", "model_idx": 11},
	{"name": "西谷岭台", "name_en": "West Valley Lookout", "event": "眺山", "event_en": "Ridge View", "fragment": "", "fragment_en": "", "color": Color(0.5, 0.6, 0.35, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "从西谷望出去,路都通向同一种云。", "text_en": "From the west valley, all the roads lead to the same clouds.", "model_idx": 8},
	{"name": "琴音林", "name_en": "Zither Grove", "event": "把风声听成琴音", "event_en": "Hearing wind as zither music", "fragment": "琴", "fragment_en": "Music", "color": Color(0.2, 0.4, 0.2, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "林子里没有舞台,风一经过,树影就开始合奏。", "text_en": "There is no stage in the grove; when wind passes, the tree shadows begin to play together.", "dialogue": ["林子里没有舞台，风一经过，树影就开始合奏。", "你坐下来，它们就停了下来——等你的节拍。", "她把这片林子当成练习曲的地方。风停的时候，她也不出声。"], "dialogue_en": ["There is no stage in the grove; when wind passes, the tree shadows begin to play together.", "You sit down and they pause — waiting for your beat.", "She used this grove for practice. When the wind stopped, she went quiet as well."], "model_idx": 13},
	{"name": "竹雨庭", "name_en": "Bamboo Rain Courtyard", "event": "夜雨敲竹", "event_en": "Night rain on bamboo", "fragment": "竹", "fragment_en": "Bamboo", "color": Color(0.3, 0.5, 0.3, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "夜雨敲竹,窗内的人把一盏灯守到天明。", "text_en": "Night rain taps the bamboo while someone keeps a lamp burning until morning.", "dialogue": ["夜雨敲竹，窗内的人把一盏灯守到天明。", "第二天早上，雨停了，竹叶上还留着水珠。", "这盏灯她也守过一整夜。第二天早上，她没有来关灯。"], "dialogue_en": ["Night rain taps the bamboo while someone keeps a lamp burning until morning.", "By morning the rain has stopped, and water droplets still cling to the bamboo leaves.", "She kept this same lamp burning for one whole night. In the morning she did not come to put it out."], "model_idx": 3},
	{"name": "榕树下", "name_en": "Banyan Tree", "event": "老树", "event_en": "Old tree", "fragment": "", "fragment_en": "", "color": Color(0.25, 0.45, 0.25, 1), "canvas": Vector2(0.0, 0.0), "off": Vector2(0, 0), "text": "榕树的气根落成帘子,坐在下面,听见自己的呼吸。", "text_en": "The banyan's aerial roots form a curtain; sitting beneath, you hear your own breath.", "model_idx": 5},
]

func _init() -> void:
	# 把 16 个驿站 snap 到 lemniscate 路径上对应的语义位置，
	# 再沿路面法线推到路肩外侧，避免亭子架在车道中间。
	for i in range(stations.size()):
		var idx: int = STATION_LEMNISCATE_IDX[i]
		stations[i]["canvas"] = _local_to_canvas(LEMNISCATE_LOCAL[idx])
		stations[i]["off"] = _station_off(idx)


## 以本点切线为基准转一圈（_DIR_STEPS 步），取离路面最远的那个方向。
## 用一整圈而不是只给两个法线方向，是因为交叉点的「切线」其实是两条路的
## 角平分线——法线反而几乎平行于其中一条路，会把驿站贴着路面推出去。
func _station_off(lm_idx: int) -> Vector2:
	var p2 := _canvas_to_world2(_local_to_canvas(LEMNISCATE_LOCAL[lm_idx]))
	var dist := STATION_OFFSET
	# 广场盘那个驿站要越界到盘外：那里两条 ribbon 夹角只有 ~76°，按
	# STATION_OFFSET 推过去仍然落在盘内、压在另一条路的沥青上。
	if p2.distance_to(PLAZA_CENTER) < PLAZA_RADIUS:
		dist = PLAZA_RADIUS + PLAZA_STATION_MARGIN
	var base := _canvas_tangent(lm_idx)
	if base.length_squared() < 1e-9:
		base = Vector2.RIGHT
	base = base.normalized()
	var a0 := base.angle()
	var best := Vector2.ZERO
	var best_d := -INF
	for k in range(_DIR_STEPS):
		var off := Vector2.from_angle(a0 + float(k) * (TAU / float(_DIR_STEPS))) * dist
		var d := _clearance(p2 + off)
		if d > best_d:
			best_d = d
			best = off
	return best


func _canvas_to_world2(c: Vector2) -> Vector2:
	return Vector2((c.x - CX) * SCALE, (c.y - CY) * SCALE)


## 画布空间切线。0.5 的等比缩放不改变方向，所以这里的单位向量在 world 里也是。
func _canvas_tangent(lm_idx: int) -> Vector2:
	var n := LEMNISCATE_LOCAL.size()
	return _local_to_canvas(LEMNISCATE_LOCAL[(lm_idx + 1) % n]) - \
		_local_to_canvas(LEMNISCATE_LOCAL[(lm_idx - 1 + n) % n])


## 放好驿站后，模型脚底离中心线还剩多少米。脚底按 STATION_FOOT_HALF 的方框
## 估，保守但不依赖 GLB。
func _clearance(c: Vector2) -> float:
	return _dist_to_road(c) - STATION_FOOT_HALF


## 到整条中心线（points）的最近距离。必须扫全路径——8 字的两条环会绕回来
## 贴着交叉点，只看驿站附近这一段会漏掉真正的最近段（广场那个驿站就靠这段
## 判的方向）。只用于本文件 _init() 里给驿站挑方向，不进任何热路径。
func _dist_to_road(p: Vector2) -> float:
	var best := INF
	for i in range(points.size() - 1):
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 < 1e-9:
			best = minf(best, p.distance_to(a))
			continue
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best



func station_display_name(idx: int) -> String:
	var s = stations[idx]
	return s.get("name_en", s.get("name", "")) if Localization.is_english() else s.get("name", "")


func station_display_event(idx: int) -> String:
	var s = stations[idx]
	return s.get("event_en", s.get("event", "")) if Localization.is_english() else s.get("event", "")


func station_display_text(idx: int) -> String:
	var s = stations[idx]
	return s.get("text_en", s.get("text", "")) if Localization.is_english() else s.get("text", "")


func station_display_fragment(idx: int) -> String:
	var s = stations[idx]
	return s.get("fragment_en", s.get("fragment", "")) if Localization.is_english() else s.get("fragment", "")


func station_dialogue(idx: int) -> Array:
	var s = stations[idx]
	if Localization.is_english():
		return s.get("dialogue_en", [])
	return s.get("dialogue", [])


func get_station_world_pos(idx: int) -> Vector3:
	var s = stations[idx]
	# off = 沿路面法线方向的偏移（世界单位）,把带模型的驿站挪出路肩,canvas 仍是地图原位
	var o: Vector2 = s.get("off", Vector2.ZERO)
	return Vector3((s["canvas"].x - CX) * SCALE + o.x, 0.0, (s["canvas"].y - CY) * SCALE + o.y)


func station_has_fragment(idx: int) -> bool:
	if idx < 0 or idx >= stations.size():
		return false
	var frag = stations[idx].get("fragment", "")
	return frag != "" and frag != null


func station_model_idx(idx: int) -> int:
	if idx < 0 or idx >= stations.size():
		return -1
	return stations[idx].get("model_idx", -1)


func get_road_length() -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total

var _cum_arclen: Array[float] = []

func compute_cumulative_arclength() -> Array[float]:
	if not _cum_arclen.is_empty():
		return _cum_arclen
	_cum_arclen.resize(points.size())
	_cum_arclen[0] = 0.0
	for i in range(1, points.size()):
		_cum_arclen[i] = _cum_arclen[i - 1] + points[i - 1].distance_to(points[i])
	return _cum_arclen


func total_arclength() -> float:
	compute_cumulative_arclength()
	if _cum_arclen.is_empty():
		return 0.0
	return _cum_arclen[_cum_arclen.size() - 1]


func nearest_point_idx(pos: Vector3) -> int:
	var best_i := 0
	var best_d := INF
	for i in range(points.size()):
		var d = pos.distance_squared_to(points[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i