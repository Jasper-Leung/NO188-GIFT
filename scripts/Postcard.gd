extends Control
## Postcard — 终局明信片 (PRD §6.3)
## 上1/3云+佳禽，下2/3茶琴竹禽4画区，底部 No.188 路牌，右下落款
## 挂在 EndCard/Postcard (显示) 和 EndCard/ExportViewport/PostcardExport (导出) 两处
##
## 明信片三层来源（整合方案 §5.3），只有第一层是买的：
##   纸面 = 档位 GameManager.get_postcard_tier()（1 素笺 / 2 上笺 / 3 珍藏笺）+ 散件
##          paper(宣纸) / ink(松烟墨) / seal(蜡封) / env(信封)
##   正面 = _variant，五块碎片；商店里明列「无价」
##   背面 = EndCard 按终局抉择给的文案，本脚本不碰

var _t = 0.0
var _variant: int = 0  # 0-4 评级，由 PostcardVariant.compute_variant() 计算

const CLOUD_COL = Color("B0C4DE")
const TEA_COL = Color("8FB35A")
const QIN_COL = Color("C9A26B")
const BAMBOO_COL = Color("6E9C6B")
const BIRD_COL = Color("E8A04F")

## 五件碎片的颜色，顺序必须死扣 `fragment_%d`：0 云 / 1 茶 / 2 琴 / 3 竹 / 4 禽。
## 画区一律按下标取色，不许再往布局表里手抄一份 —— 上一版正是布局表里
## 手抄的那份整体错位一格，标签对而颜色和图标属于下一件。两个表彼此自洽，
## 缩略图一眼扫过去完全正常，可玩家存走的那张 PNG 一样是错的。
const FRAGMENT_COLS: Array = [CLOUD_COL, TEA_COL, QIN_COL, BAMBOO_COL, BIRD_COL]

const LAND_COL = Color("F4F2EA")
const INK_COL = Color("4A3520")
const ACCENT_COL = Color("C9A26B")
## 素笺比未买套餐的白纸沉一点、带点纸浆色（F4F2EA 是未买套餐那张「还没上过纸」的白）；
## 上笺帘纹细密、压得住墨；珍藏笺暖白托金边
const PAPER_PLAIN = Color("E9E2CE")
const PAPER_FINE = Color("F2EAD8")
const PAPER_RARE = Color("F8F1DE")
const FRAME_PLAIN = Color("8A6E4A")
const FRAME_GOLD = Color("C9A22B")
## 松烟墨比木炭黑更冷、更压帘纹
const INK_PINE = Color("342E35")
const WAX_COL = Color("9C3434")

## ---- 纸面外观：档位 + 散件，_ready() 一次性算好，_draw() 只读 ----
var _tier: int = 0                 # 0=没买套餐 1=素笺 2=上笺 3=珍藏笺
var _paper: Color = LAND_COL
var _ink: Color = INK_COL
var _frame_col: Color = FRAME_PLAIN
var _frame_w: float = 4.0
var _laid_lines: bool = false      # 帘纹：上笺及以上，或买了宣纸
var _fiber: bool = false           # 宣纸纤维
var _has_wax: bool = false         # 蜡封
var _has_env: bool = false         # 信封

## [slot_idx, is_placeholder]
## slot_idx=-1 表示占位灰块；slot_idx>=0 表示真实碎片，颜色走 FRAGMENT_COLS[slot_idx]
const VARIANT_LAYOUTS: Array = [
	# 0 初旅
	[[0, false], [-1, true], [-1, true], [-1, true]],
	# 1 探索者
	[[0, false], [1, false], [-1, true], [-1, true]],
	# 2 朝圣者
	[[0, false], [1, false], [2, false], [-1, true]],
	# 3 大师
	# 第 5 格必须是占位：集了 4 块碎片就走的「未竟」，正面得看得出还缺一件，
	# 只画 4 格的话缺的那件无处体现，未竟和满配的区别就只剩背面留白。
	[[0, false], [1, false], [2, false], [3, false], [-1, true]],
	# 4 完满
	# 第 5 格必须是 false：它是真碎片（禽），标记成占位会画成灰底「?」——
	# 玩家集齐五件却看到一格问号，正好戳破「无价」那层承诺。
	[[0, false], [1, false], [2, false], [3, false], [4, false]],
]


func _ready() -> void:
	_variant = PostcardVariant.compute_variant()
	_apply_paper_style()


## 档位决定纸与框，散件各管自己那一笔，互不覆盖：
## 上笺给帘纹，宣纸再叠一层纤维，松烟墨只换墨色，蜡封与信封各画各的角。
func _apply_paper_style() -> void:
	_tier = clampi(GameManager.get_postcard_tier(), 0, 3)
	match _tier:
		1:
			_paper = PAPER_PLAIN
		2:
			_paper = PAPER_FINE
		3:
			_paper = PAPER_RARE
			_frame_col = FRAME_GOLD
			_frame_w = 6.0
	_fiber = GameManager.has_item("paper")
	_laid_lines = _tier >= 2 or _fiber
	if GameManager.has_item("ink"):
		_ink = INK_PINE
	_has_wax = GameManager.has_item("seal")
	_has_env = GameManager.has_item("env")


## 纸面档位名。0 = 没买套餐：明信片照样产出，只是不打纸名（只剩落款）。
func tier_name() -> String:
	match _tier:
		1:
			return Localization.t("tier_plain")
		2:
			return Localization.t("tier_fine")
		3:
			return Localization.t("tier_rare")
	return ""


## 封口的蜡是不是裂开的。终局选【放手】就是裂的 —— 蜡封本来就是"把信按住了"，
## 放手自然要把封口掰开。这是 keep / break 之间唯一**画在正面**的差别，
## 而正面才是玩家真正带走的那张 PNG；背面那句预填文案玩家随时能改，改不了。
func seal_broken() -> bool:
	return GameManager.ending_id == "break"


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y

	# 底色 + 纸面纹理 + 外框 + 内框
	draw_rect(Rect2(0, 0, w, h), _paper)
	_draw_paper_texture(w, h)
	draw_rect(Rect2(0, 0, w, h), _frame_col, false, _frame_w)
	draw_rect(Rect2(8, 8, w - 16, h - 16), _ink, false, 1)

	# 上1/3 云层 + 佳禽
	var cloud_h = h * 0.3
	_draw_cloud_sky(w, cloud_h)

	# 下2/3 画区（根据 variant 决定哪些是真实、哪些是占位灰）
	var sect_y = cloud_h
	var sect_h = h * 0.55
	var layout: Array = VARIANT_LAYOUTS[_variant]
	var sect_count: int = layout.size()
	var sect_w: float = w / float(max(sect_count, 1))
	for i in range(sect_count):
		var entry: Array = layout[i]
		var slot_idx: int = entry[0]
		var is_placeholder: bool = entry[1]
		var base_col: Color = Color.GRAY if is_placeholder else FRAGMENT_COLS[slot_idx]
		var rx: float = i * sect_w
		var shimmer: float = sin(_t * 1.5 + i * 1.2) * 0.04
		var fill_col: Color = base_col.darkened(0.18 + shimmer) if not is_placeholder else Color.GRAY.darkened(0.3)
		var panel := Rect2(rx, sect_y, sect_w, sect_h)
		draw_rect(panel, fill_col)
		if not is_placeholder:
			_draw_panel_wash(panel, i)
		draw_rect(panel, Color(1, 1, 1, 0.08), false, 1)
		var ctr = Vector2(rx + sect_w * 0.5, sect_y + sect_h * 0.5)
		# 图标要撑满画区才读得出来。旧值 /180 在 150px 宽的格子里只画出 40px，
		# 五个图标全缩在格子中央一小团 —— 导出成 1920 宽的 PNG 之后更看不清。
		# 分母 82 是被最宽的琴（±38）压住的，再大就顶格。
		var sc: float = minf(sect_w / 82.0, sect_h / 210.0)
		if not is_placeholder and slot_idx >= 0:
			# 图标走墨色而不是底色的浅色调。旧版拿 base_col.lightened(0.25) 压在
			# base_col.darkened(0.18) 的格子上，两者只差一档，读出来是"颜色深一点
			# 的方块"；换墨色之后才是一个剪影。
			_draw_fragment_icon(slot_idx, ctr, _ink, 1.0, sc)
			var label_key: String = "fragment_%d" % slot_idx
			var lpos := Vector2(rx + sect_w * 0.5, sect_y + sect_h - 20.0)
			# 底下垫一条纸色的带：格子的底色每件都不一样，字要是不垫底
			# 就跟着那一件变深变浅，云那一格尤其读不出来。
			draw_rect(Rect2(lpos.x - sect_w * 0.5, lpos.y - 26.0, sect_w, 32.0),
				Color(1, 1, 1, 0.30))
			draw_string(ThemeDB.fallback_font, lpos - Vector2(0, 6),
				Localization.t(label_key), HORIZONTAL_ALIGNMENT_CENTER, -1, 28, _ink)
		else:
			# 占位灰块显示 "?"
			draw_string(ThemeDB.fallback_font, Vector2(rx + sect_w * 0.5 - 14, sect_y + sect_h * 0.5 + 10),
				"?", HORIZONTAL_ALIGNMENT_CENTER, -1, 48, Color.GRAY)

	# 完满评级金印
	if _variant == 4:
		var seal_x: float = w - 90
		var seal_y: float = 20.0
		var seal_col: Color = Color("D4AF37").darkened(0.1)
		draw_circle(Vector2(seal_x, seal_y), 32, seal_col)
		draw_string(ThemeDB.fallback_font, Vector2(seal_x - 26, seal_y + 10),
			Localization.t("postcard_seal"), HORIZONTAL_ALIGNMENT_CENTER, 52, 28, LAND_COL)

	# 封口位：珍藏笺自带一圈金框当「蜡封位」；真把口封上要灯铺那块蜡。
	# 选【放手】时这一块永远要画 —— 抉择在正面留下的唯一痕迹。
	if _tier >= 3 or _has_wax or seal_broken():
		_draw_seal_mark(w, h)

	# 信封：左上角压一道折角，像还没从信封里抽出来
	if _has_env:
		_draw_envelope(w, h)

	# 底部路牌
	_draw_road_sign(w, h)

	# 飘叶粒子
	_draw_floating_leaves(w, h)

	# 落款；买过纸套餐的在旁边标一档纸名
	var fs := 15
	draw_string(ThemeDB.fallback_font, Vector2(w - 380, h - 18),
		Localization.t("postcard_signature"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _ink)
	var tname := tier_name()
	if tname != "":
		var tw := ThemeDB.fallback_font.get_string_size(
			tname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(ThemeDB.fallback_font, Vector2(w - 380 - tw - 14, h - 18),
			tname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _frame_col)


func _draw_cloud_sky(w: float, h: float) -> void:
	# 渐变天空
	var steps = int(h)
	for y in range(steps):
		var t = float(y) / max(1.0, h - 1.0)
		var col = CLOUD_COL.darkened(0.18 + t * 0.08)
		draw_line(Vector2(0, y), Vector2(w, y), col, 1)

	# 多层云
	for i in range(7):
		var cx = (i + 0.3) * w / 7.0 + sin(_t * 0.3 + i * 0.8) * 18
		var cy = h * 0.45 + sin(i * 1.3) * 22 + cos(_t * 0.5 + i) * 6
		var r = 25 + i * 4
		var alpha = 0.32 + sin(_t + i) * 0.06
		draw_circle(Vector2(cx, cy), r, Color(1, 1, 1, alpha))
		draw_circle(Vector2(cx + 18, cy - 5), r - 5, Color(1, 1, 1, alpha * 0.8))
		draw_circle(Vector2(cx - 18, cy - 2), r - 7, Color(1, 1, 1, alpha * 0.7))

	# 右上 佳禽
	var bird_x = w * 0.82 + sin(_t * 0.7) * 12
	var bird_y = h * 0.32 + cos(_t * 0.9) * 5
	_draw_bird(Vector2(bird_x, bird_y), BIRD_COL, 1.0, 1.4)

	# "云"字
	draw_string(ThemeDB.fallback_font, Vector2(w * 0.5 - 20, 38),
		Localization.t("fragment_0"), HORIZONTAL_ALIGNMENT_CENTER, -1, 36, _ink)


## 画区里的纸感。五个画区原来是五块**平涂**的色卡，远看就是一份色板，
## 而玩家带走的是一张纪念。补三层：顶部受光的竖向渐变、底部一道水色
## 积聚的暗边、几根纸纤维。色块有了厚度，才不像 UI 的取色器。
func _draw_panel_wash(r: Rect2, seed_i: int) -> void:
	const BANDS := 5
	for i in BANDS:
		var t0 := float(i) / float(BANDS)
		var y0 := r.position.y + r.size.y * t0
		var hh := r.size.y * (float(i + 1) / float(BANDS) - t0) + 1.0
		draw_rect(Rect2(r.position.x, y0, r.size.x, hh), Color(1, 1, 1, 0.11 * (1.0 - t0)))
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.86, r.size.x, r.size.y * 0.14),
			Color(0.20, 0.16, 0.12, 0.10))
	for i in 5:
		var fx := r.position.x + fmod(float(seed_i * 7 + i * 53), r.size.x)
		var fy := r.position.y + fmod(float(seed_i * 11 + i * 31), r.size.y * 0.92)
		draw_line(Vector2(fx, fy), Vector2(fx + 5.0, fy - 1.0), Color(0.25, 0.20, 0.15, 0.10), 1)


func _draw_road_sign(w: float, h: float) -> void:
	var sign_pos = Vector2(w * 0.5 - 50, h * 0.92)
	draw_rect(Rect2(sign_pos.x, sign_pos.y, 100, 25), _paper, true)
	draw_rect(Rect2(sign_pos.x, sign_pos.y, 100, 25), _ink, false, 1)
	draw_string(ThemeDB.fallback_font, sign_pos + Vector2(20, 18),
		"No.188", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, _ink)


## 纸面纹理：帘纹是纵向细线（间距随宽度走，别让 1920 宽的导出图里挤几百条），
## 宣纸再叠一层短纤维。alpha 都压得很低，只做「摸得着纸」，不抢五个画区的戏。
func _draw_paper_texture(w: float, h: float) -> void:
	if _laid_lines:
		var step := maxf(6.0, w / 240.0)
		var x := 0.0
		while x < w:
			draw_line(Vector2(x, 0), Vector2(x, h), Color(0.42, 0.36, 0.28, 0.045), 1)
			x += step
	if _fiber:
		for i in 42:
			var fx := fmod(float(i) * 173.3, w)
			var fy := fmod(float(i) * 97.7, h)
			var fl := 4.0 + fmod(float(i) * 7.0, 9.0)
			draw_line(Vector2(fx, fy), Vector2(fx + fl, fy - 1.0),
				Color(0.38, 0.33, 0.26, 0.09), 1)


## 左下角封口位。珍藏笺自带一圈金框当「蜡封位」，真封住要靠灯铺那块蜡。
## 两者互不依赖：有圈没蜡是空位，有蜡没圈照样盖得上。
##
## 选【放手】时这块封口是掰开的：没蜡也画一个开口的圈（否则"没买蜡封"的玩家
## 看不到任何差别，抉择就又只剩背面那一句可改了），有蜡则蜡上带一道裂口、
## 中心的压印方框去掉。留门 / 未竟一律画成完好的。
func _draw_seal_mark(w: float, h: float) -> void:
	var c := Vector2(64.0, h - 64.0)
	var r := 26.0
	var broken := seal_broken()
	if _tier >= 3 or broken:
		draw_arc(c, r + 4.0, 0.0, TAU, 40, FRAME_GOLD, 2)
	if _has_wax:
		draw_circle(c, r, WAX_COL)
		draw_circle(c + Vector2(-3, -4), r - 5, WAX_COL.lightened(0.14))
		if broken:
			# 裂口：从左上缘贯到右下缘的一道折线，中心压印不再画
			draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.92, -r * 0.34),
				c + Vector2(-r * 0.18, r * 0.10),
				c + Vector2(-r * 0.42, r * 0.46),
				c + Vector2(r * 0.10, r * 0.70),
			]), WAX_COL.darkened(0.55), 3.0, true)
		else:
			draw_rect(Rect2(c.x - 9, c.y - 9, 18, 18), WAX_COL.darkened(0.4), false, 2)
	elif broken:
		# 没蜡：开口的圈 —— 一枚盖过又被揭开的封口
		draw_arc(c, r, PI * 0.16, PI * 1.08, 24, WAX_COL, 4.0, true)


## 信封：左上角折角。卡片占满控制器矩形、画不到矩形之外，
## 所以只能在这道折角上暗示「还没取出来」，别试图画一个信封外框。
func _draw_envelope(w: float, h: float) -> void:
	var d := minf(w, h) * 0.16
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(d, 0), Vector2(0, d),
	]), Color(0.46, 0.38, 0.28, 0.22))
	draw_colored_polygon(PackedVector2Array([
		Vector2(d, 0), Vector2(d, d), Vector2(0, d),
	]), _paper.darkened(0.08))
	draw_line(Vector2(d, 0), Vector2(d, d), _ink, 2)
	draw_line(Vector2(d, d), Vector2(0, d), _ink, 2)


func _draw_floating_leaves(w: float, h: float) -> void:
	for i in range(8):
		var phase = i * 0.7 + _t * 0.4
		var lx = (i * 137.0) - int(_t * 30 + i * 50) % int(w + 100)
		lx = fmod(lx + w + 100, w + 100) - 50
		var ly = h * 0.3 + sin(phase) * 40 + fmod(_t * 8 + i * 60, h * 0.5)
		ly = fmod(ly, h * 0.6) + h * 0.3
		var col = Color(0.55, 0.45, 0.25, 0.45 + sin(phase) * 0.15)
		var s = 5.0 + sin(phase * 2) * 1.5
		draw_rect(Rect2(lx, ly, s, s), col, true)


# --- 碎片图标（与 FragmentBar 同源，加了 scale 参数适配大画区）---

## 碎片下标 → 图标的唯一出口。颜色走 FRAGMENT_COLS[slot_idx]、标签走
## fragment_%d，三者必须同序；上一版颜色表和这里的 match 各错位一格而
## 标签是对的，所以每处单看都成立、合起来全错。把 dispatch 收成一个函数
## 就是为了让「slot 0 是云」这件事只写一次。
func _draw_fragment_icon(slot_idx: int, c: Vector2, col: Color, a: float, sc: float) -> void:
	match slot_idx:
		0: _draw_cloud(c, col, a, sc)
		1: _draw_teacup(c, col, a, sc)
		2: _draw_guqin(c, col, a, sc)
		3: _draw_bamboo(c, col, a, sc)
		4: _draw_bird(c, col, a, sc)


## 云：一朵**有平底**的积云 —— 四团大小不一的鼓包沿一条平底线闭合成轮廓。
## 旧版是三个同半径的圆叠出来的 B0C4DE 色团子，在画区里读成"三个点"，
## 而叠圆按定义接不出平底 —— 平底正是云和烟唯一的区别。
func _draw_cloud(c: Vector2, col: Color, a: float, sc: float = 1.0) -> void:
	var bumps := [
		[Vector2(-26.0, 5.0), 13.0],   # 左肩，最矮
		[Vector2(-9.0, -6.0), 19.0],   # 主体，最高
		[Vector2(10.0, -2.0), 15.0],   # 右肩
		[Vector2(24.0, 6.0), 9.0],     # 尾巴，最矮
	]
	# base_y 必须是**绝对**坐标。这几个鼓包的表面算出来是 c.y + …（三百多），
	# 而 base_y 原来只是 13*sc（二十几），minf 一次都选不中鼓包，
	# 九十九个点全部塌在同一条水平线上 —— 三角化照样出 97 个三角形，
	# 面积是 0，图上就只剩那根线。
	var base_y := c.y + 13.0 * sc
	var x0 := c.x - 38.0 * sc
	var x1 := c.x + 32.0 * sc
	# 逐列取**最上面**那个鼓包的表面，拼出一条不自交的轮廓。
	# 千万别改成「每团各画一段上半圆、再首尾相连」：相邻两团的半径和大于圆心距
	# （19+13 > 17），后一团的起点会落在前一团终点的左边，连出来的是一条自己
	# 压自己的线，三角化直接失败——第一版就是这么画成一根线的，而且不报任何错。
	const STEPS := 96
	var poly := PackedVector2Array()
	for i in range(STEPS + 1):
		var x := lerpf(x0, x1, float(i) / float(STEPS))
		var top := base_y
		for b in bumps:
			var o := c.x + float(b[0].x) * sc
			var r := float(b[1]) * sc
			var dx := x - o
			if absf(dx) < r:
				top = minf(top, c.y + float(b[0].y) * sc - sqrt(r * r - dx * dx))
		poly.append(Vector2(x, top))
	poly.append(Vector2(x1, base_y))
	poly.append(Vector2(x0, base_y))
	draw_colored_polygon(poly, Color(col.r, col.g, col.b, a))
	# 平底上压一道更重的墨，底边才立得住（云的影子就在脚下）
	draw_line(Vector2(x0, base_y), Vector2(x1, base_y), Color(col.r, col.g, col.b, a), 2.0 * sc)
	# 主体左上一道留白，跟另外几个线描图标的高光笔触一致
	draw_arc(c + Vector2(-9.0 * sc, -6.0 * sc), 12.0 * sc, PI * 1.12, PI * 1.62, 12,
			Color(1, 1, 1, a * 0.55), 2.0 * sc)


func _draw_teacup(c: Vector2, col: Color, a: float, sc: float = 1.0) -> void:
	var r = 22.0 * sc
	var ink := Color(col.r, col.g, col.b, a)
	# 线宽跟着 sc 走：这五个图标原来在 180 的分母下画，线宽是写死的 3px；
	# 画区放大两倍多之后 3px 的杯壁只剩一根发丝，缩略图上整个杯子就没了。
	var lw := 3.0 * sc
	draw_arc(c + Vector2(0, 4 * sc), r, 0, PI, 24, ink, lw)
	draw_line(c + Vector2(-r, 4 * sc), c + Vector2(-r, -8 * sc), ink, lw)
	draw_line(c + Vector2(r, 4 * sc), c + Vector2(r, -8 * sc), ink, lw)
	draw_arc(c + Vector2(0, -8 * sc), r, PI, TAU, 24, ink, lw)
	# 杯底一条，免得下半圆看着像悬空的碗
	draw_line(c + Vector2(-r * 0.86, 4 * sc), c + Vector2(r * 0.86, 4 * sc), ink, lw * 0.7)
	draw_arc(c + Vector2(-30 * sc, -4 * sc), 8 * sc, -PI * 0.3, PI * 0.3, 12, ink, lw * 0.7)
	draw_arc(c + Vector2(-6 * sc, -22 * sc), 6 * sc, PI, TAU, 12, Color(1, 1, 1, a * 0.5), lw * 0.5)


func _draw_guqin(c: Vector2, col: Color, a: float, sc: float = 1.0) -> void:
	var pts = PackedVector2Array([
		c + Vector2(-38 * sc, 6 * sc), c + Vector2(-22 * sc, -10 * sc),
		c + Vector2(0, -14 * sc), c + Vector2(22 * sc, -10 * sc),
		c + Vector2(38 * sc, 6 * sc)
	])
	# 先把琴身填实，再压七根弦。旧版只画一圈描边、弦是白的：图标换成墨色之后
	# 白弦落在浅色格子上等于没画。填实 + 亮弦才像一件漆黑的琴。
	draw_colored_polygon(PackedVector2Array([
		pts[0], pts[1], pts[2], pts[3], pts[4],
		c + Vector2(30 * sc, 12 * sc), c + Vector2(-30 * sc, 12 * sc),
	]), Color(col.r, col.g, col.b, a))
	for j in range(7):
		var y := -9.0 * sc + j * 3.6 * sc
		var half := 30.0 * sc * (1.0 - 0.04 * float(j))
		draw_line(c + Vector2(-half, y), c + Vector2(half, y),
				Color(1, 1, 1, a * 0.55), 1.2 * sc)
	# 两枚岳山和一枚雁足，认得出是琴而不只是一块梯形
	draw_line(c + Vector2(-30 * sc, 10 * sc), c + Vector2(-24 * sc, 14 * sc),
			Color(col.r, col.g, col.b, a), 3 * sc)
	draw_line(c + Vector2(30 * sc, 10 * sc), c + Vector2(24 * sc, 14 * sc),
			Color(col.r, col.g, col.b, a), 3 * sc)


func _draw_bamboo(c: Vector2, col: Color, a: float, sc: float = 1.0) -> void:
	var ink := Color(col.r, col.g, col.b, a)
	for s in range(-1, 2):
		var bx = c.x + s * 18 * sc
		for n in range(4):
			var by = c.y - 28 * sc + n * 20 * sc
			draw_line(Vector2(bx, by - 20 * sc), Vector2(bx, by + 8 * sc), ink, 4.0 * sc)
			# 竹节：节间要略窄一点，才看得出是一节一节长的
			draw_line(Vector2(bx - 8 * sc, by), Vector2(bx + 8 * sc, by), ink, 2.5 * sc)
		# 竹叶两片，认得出是竹而不只是一排竖条
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx + 2 * sc, c.y - 48 * sc),
			Vector2(bx + 22 * sc, c.y - 58 * sc),
			Vector2(bx + 5 * sc, c.y - 36 * sc),
		]), ink)
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx - 2 * sc, c.y - 34 * sc),
			Vector2(bx - 22 * sc, c.y - 44 * sc),
			Vector2(bx - 5 * sc, c.y - 22 * sc),
		]), ink)


func _draw_bird(c: Vector2, col: Color, a: float, sc: float = 1.0) -> void:
	var r = 18.0 * sc
	var ink := Color(col.r, col.g, col.b, a)
	draw_circle(c + Vector2(0, 4 * sc), r, ink)
	# 翅膀（三角翼）
	var wing_pts = PackedVector2Array([
		c + Vector2(-2 * sc, -4 * sc),
		c + Vector2(-22 * sc, -16 * sc),
		c + Vector2(-12 * sc, 2 * sc),
	])
	draw_colored_polygon(wing_pts, ink)
	# 头 + 喙
	draw_circle(c + Vector2(r - 2 * sc, -2 * sc), 5 * sc, ink)
	draw_line(c + Vector2(r + 2 * sc, -2 * sc), c + Vector2(r + 12 * sc, 0), ink, 2.0 * sc)
	# 尾
	var tail_pts = PackedVector2Array([
		c + Vector2(-r + 2 * sc, 0),
		c + Vector2(-r - 10 * sc, -6 * sc),
		c + Vector2(-r - 10 * sc, 6 * sc),
	])
	draw_colored_polygon(tail_pts, ink)
	# 眼睛：墨色身子上一颗留白，认得出是鸟而不只是一颗圆
	draw_circle(c + Vector2(r - 2 * sc, -3 * sc), 1.8 * sc, Color(1, 1, 1, a * 0.9))
