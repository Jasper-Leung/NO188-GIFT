extends Node
## 画面设置 —— 画质三档（低 / 中 / 高）+ 窗口尺寸 / 全屏 / VSync，玩家自己挑。
## autoload 名沿用旧名 `QualitySettings`：改名要动 autoload 注册、场景引用和
## 三十多条回归里的每一处，收益不值，而这一层现在确实管的是"画面"。
##
## 三档的含义不是"好看 / 更好看 / 最好看"，是**同一套程序化画面在不同档硬件上的
## 取舍**：本作零贴图、满屏草皮和行道树，而草皮最贵（一格 ring 0 约 10ms，见
## `GrassScatter` 的建格预算）——"这台机器铺 200m 铺不动"这件事只有跑过一次才知道，
## 而顶栏、按钮、驿站全都不给玩家任何办法降档。于是开这一层。
##
##   低 —— 关太阳阴影、草皮/行道树半径砍到 70m。核显 / 老机器 / 浏览器 / 手机。
##   中 —— 阴影收到 90m、草皮 110m、行道树 90m。
##   高 —— 全开，阴影与植被半径都走 World3D.tscn 里那组数（200 / 200 / 150）。
##          **桌面默认必须是 high**：全部回归脚本量的都是那一档，低档等于让三十多条
##          回归在不知情的情况下量一个缩水的世界。
##
## 三档都**不动 3D 渲染分辨率**（`viewport.scaling_3d_scale`）。本工程实测里它
## 在 Compatibility 下更慢（多一条全屏 blit 通道，省下的像素钱抵不过多出来的 pass），
## 而桌面是 Forward+——所以"想要更多帧"只有两条路：关阴影、把植被半径收进来。
##
## **窗口尺寸/全屏/VSync 是另外三档，与上面那个不是一回事**：`scaling_3d_scale`
## 是同一块画布上少算几个像素（全屏 blit 那笔开销），而窗口尺寸是**窗口本身**，
## 它省下来的是填充率和光栅化，不是靠改一个视口比例。这三项在这一层，
## 和画质档位存在同一份文件的同一节里 —— 见 `RESOLUTIONS` / `apply_video()`。
##
## 桌面走 Forward+、Web/移动端被引擎静默降到 Compatibility（见 CLAUDE.md 已知陷阱
## 那条"Web 上引擎会静默掉渲染器"），所以**默认档按平台分**，不按渲染器分。
##
## **两样东西故意没搬**（从 NO188-GIFT-REF 那条线拿过来的原型里有，这里不做）：
##   · **自动降档**（帧率低于 20 FPS 连续 8 秒就降一档）。原型那边因为一条**至今
##     没定位**的间歇性段错误才加了 `Engine.max_physics_steps_per_frame = 4` 来压着，
##     而那道闸本身会改 `_process` 与 `_physics_process` 的相对频率——拿一个未定位的
##     崩溃的补丁当性能策略，等于把另一个未定位的崩溃请进家门。而且静默降档会让
##     玩家在没改任何设置的情况下看到画面变了。先让玩家自己挑。
##   · 那个 `max_physics_steps_per_frame`。见上。

signal quality_changed(tier: int)

const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2
const TIER_COUNT := 3

const SAVE_PATH_CFG := "user://settings.cfg"
const SAVE_KEY := "quality_tier"

## 窗口尺寸档。第一个是"跟随窗口"（不写 `window_set_size`，用玩家自己拖出来的那个），
## 后面是三档常见的 16:9。**列出来的每一档都必须 ≤ 玩家屏幕的可用区**，
## 否则在 1366×768 的笔记本上选 1080p 会得到一个比屏幕还大的窗口。
const RESOLUTION_AUTO := 0
const RESOLUTIONS := [
	RESOLUTION_AUTO,
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

const WM_WINDOWED := 0
const WM_BORDERLESS := 1
const WM_EXCLUSIVE := 2
const WINDOW_MODE_NAMES := ["wm_windowed", "wm_borderless", "wm_exclusive"]

## 开 / 关 / 自适应。默认**开**：本工程全部定妆照量的都是开着 VSync 那一档，
## 关掉之后 3D 画面的时序（`Input.parse_input_event` 注入的那些按键帧）会变。
const VSYNC_DISABLED := 0
const VSYNC_ENABLED := 1
const VSYNC_ADAPTIVE := 2
const VSYNC_NAMES := ["vsync_off", "vsync_on", "vsync_adaptive"]
const DEFAULT_VSYNC := VSYNC_ENABLED

## 每档参数。`shadow_max_distance` / `grass_radius` / `tree_radius` 三个字段：
## 0 或 -1 = **不动**，沿用 World3D.tscn / `target_radius()` 那一档。
##
## 为什么低档是"关阴影"而不是"把阴影收近"：影子要整场景重画一遍深度图
## （树、草皮、驿站、车全进），收近只是少画远处那一部分，而阴影**开关**是这台机器
## 上最干净的一刀。
const PARAMS := [
	# low —— 浏览器 / 手机 / 核显
	{
		"shadows": false,
		"shadow_max_distance": 0.0,
		"grass_radius": 70.0,
		"tree_radius": 70.0,
	},
	# medium
	{
		"shadows": true,
		"shadow_max_distance": 90.0,
		"grass_radius": 110.0,
		"tree_radius": 90.0,
	},
	# high —— 与 World3D.tscn 里的桌面档逐值一致
	{
		"shadows": true,
		"shadow_max_distance": 0.0,
		"grass_radius": -1.0,
		"tree_radius": -1.0,
	},
]

const TIER_NAME_KEYS := ["quality_low", "quality_medium", "quality_high"]

var tier: int = QUALITY_HIGH
var resolution_idx: int = RESOLUTION_AUTO
var window_mode: int = WM_WINDOWED
var vsync_mode: int = DEFAULT_VSYNC
## 只动内存、绝不碰 user://settings.cfg。回归探针必须开着它。
var persist_enabled := true


func _ready() -> void:
	tier = _load_tier()
	resolution_idx = _load_int("resolution", RESOLUTIONS.size(), RESOLUTION_AUTO)
	window_mode = _load_int("window_mode", WINDOW_MODE_NAMES.size(), WM_WINDOWED)
	vsync_mode = _load_int("vsync", VSYNC_NAMES.size(), DEFAULT_VSYNC)
	# 落盘的那三项要在**启动时**就推上去，否则玩家挑了 1080p，
	# 下一次开出来还是上一个窗口的尺寸，而面板上写着「1920×1080」。
	apply_video()


## 桌面默认 high（全部回归量的那一档），Web / 移动端默认 low。
func _load_tier() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH_CFG) == OK:
		var t := int(cfg.get_value("video", SAVE_KEY, -1))
		if t >= 0 and t < TIER_COUNT:
			return t
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return QUALITY_LOW
	return QUALITY_HIGH


func _load_int(key: String, count: int, fallback: int) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH_CFG) != OK:
		return fallback
	var v := int(cfg.get_value("video", key, -1))
	return v if v >= 0 and v < count else fallback


## 分辨率档位落成**实际像素**。`RESOLUTION_AUTO` 返回零向量，意思是
## "不接管"——`apply_video()` 那一路压根不调 `window_set_size`。
##
## 纯函数，不碰 DisplayServer：headless 下 DisplayServer 是空驱动，
## 那里量不到任何东西，而"选 1920×1080 是不是真的落成 1920×1080"
## 是这一族唯一能量到的判据。
static func resolution_size(idx: int) -> Vector2i:
	if idx <= RESOLUTION_AUTO or idx >= RESOLUTIONS.size():
		return Vector2i.ZERO
	return RESOLUTIONS[idx]


## 该不该由 `apply_video()` 真的去改窗口尺寸。**屏幕比目标还小的时候不设**——
## 设一个比屏幕大的窗口，玩家看到的是四条黑边外加一个够不着的标题栏，
## 而面板上那个按钮明明白白写着「1920×1080」。
static func resolution_allowed(idx: int) -> bool:
	var want := resolution_size(idx)
	if want == Vector2i.ZERO:
		return false
	return want.x <= _usable_size().x and want.y <= _usable_size().y


static func _usable_size() -> Vector2i:
	if not video_available():
		return Vector2i(1152, 648)     # 无头回归里"屏幕"取一个保守值
	return DisplayServer.screen_get_usable_rect(
			DisplayServer.window_get_current_screen()).size


## 这一族唯一能推真窗口的平台。**Web 不算**：浏览器的画布尺寸由页面和
## 导出设置决定，`window_set_size()` 调下去不报错、也什么都不发生——
## 和 CLAUDE.md 里"Web 上引擎静默从 Forward+ 掉到 Compatibility"是同一族的
## "没有警告的静默"，所以这里直接按平台排除，而不是调完发现没反应再回头查。
static func video_available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return false
	return true


## 切档。**`persist` 没有默认值**——这是故意的：任何一处只想改内存的调用
## （回归探针里"跑完还原"那一句、画质面板自己的预览）都会顺手改掉玩家存档，
## 而低档会关阴影、砍植被半径，于是后面一串回归量的是一个和平时不同的世界。
## 现在每个调用点都必须自己说清要不要落盘。
func set_tier(t: int, persist: bool) -> void:
	var nt := clampi(t, 0, TIER_COUNT - 1)
	if nt == tier:
		return
	tier = nt
	if persist and persist_enabled:
		_save_int(SAVE_KEY, tier)
	quality_changed.emit(tier)


## 下面三个也是 `persist` **没有默认值**，理由和 `set_tier` 同一条：
## 每一处都得自己说清要不要落盘，否则回归探针"改完还原"那一句会顺手
## 改掉玩家挑的分辨率。判据在 `verify_settings.gd` 里读源码文本量参数表。
func set_resolution(idx: int, persist: bool) -> void:
	resolution_idx = clampi(idx, 0, RESOLUTIONS.size() - 1)
	if persist and persist_enabled:
		_save_int("resolution", resolution_idx)
	apply_video()


func set_window_mode(m: int, persist: bool) -> void:
	window_mode = clampi(m, 0, WINDOW_MODE_NAMES.size() - 1)
	if persist and persist_enabled:
		_save_int("window_mode", window_mode)
	apply_video()


func set_vsync(v: int, persist: bool) -> void:
	vsync_mode = clampi(v, 0, VSYNC_NAMES.size() - 1)
	if persist and persist_enabled:
		_save_int("vsync", vsync_mode)
	apply_video()


func resolution_name_key() -> String:
	if resolution_idx == RESOLUTION_AUTO:
		return "resolution_auto"
	return "resolution_n" % int(RESOLUTIONS[resolution_idx].y)


func window_mode_name_key() -> String:
	return str(WINDOW_MODE_NAMES[window_mode])


func vsync_name_key() -> String:
	return str(VSYNC_NAMES[vsync_mode])


func _save_int(key: String, value: int) -> void:
	# 读-改-写：`AudioManager` 的音量存在同一份文件的 "audio" 一节，
	# 直接 `ConfigFile.save()` 会把玩家挑的音量抹回默认值。
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH_CFG)
	cfg.set_value("video", key, value)
	cfg.save(SAVE_PATH_CFG)


## 画面三项推到真的窗口上。**无头一律跳过**：`--headless` 用的是空
## DisplayServer 驱动，调 `window_set_mode()` 在那里既量不到也不该做。
func apply_video() -> void:
	if not video_available():
		return
	match window_mode:
		WM_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		WM_BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WM_EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	# 分辨率排在窗口模式**之后**：反过来写的话，`WINDOW_MODE_FULLSCREEN`
	# 会把刚设的尺寸抹掉，而顺序反了这个 bug 两侧各自都绿（按钮上的字变了、
	# 窗口尺寸没变，没有任何断言量的是真窗口）。
	if resolution_allowed(resolution_idx):
		DisplayServer.window_set_size(resolution_size(resolution_idx))
	match vsync_mode:
		VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSYNC_ENABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		VSYNC_ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)


func tier_name_key() -> String:
	return str(TIER_NAME_KEYS[tier])


func param(key: String) -> Variant:
	return PARAMS[tier].get(key)


## 把当前档位应用到真实世界。`World3D._ready()` 在 setup 各系统**之前**调它，
## 这样草皮/树按目标半径一次性建池，不用重建。画质面板切档时**再调一遍**——
## 所以这个函数要能在世界已经建好之后重入。
##
## **只有阴影是当场生效的**：植被半径是 `setup()` 里读 `radius_override` 的
## （`GrassScatter` / `TreeScatter` 的池、环数、淡出带全在那一刻定死），
## 所以中途换档要下次进入这一趟才看得见——面板上那一行提示就是在说这件事。
## 当场重建整片草皮不是做不到，是它比"关掉阴影"那点收益贵得多。
func apply_to_world(world: Node) -> void:
	if world == null:
		return
	var p: Dictionary = PARAMS[tier]

	var sun: DirectionalLight3D = world.get_node_or_null("DirectionalLight3D")
	if sun != null:
		sun.shadow_enabled = bool(p["shadows"])
		var smd: float = float(p["shadow_max_distance"])
		if smd > 0.0:
			sun.directional_shadow_max_distance = smd

	# **两个 override 都要写，负数要写成 0**（0 = 不接管，走 `target_radius()`）。
	# 只在 >0 时写的话 override 是**粘的**：玩家在低档下把世界建起来（override=70），
	# 再切到高档，那一档的 -1 什么也不做，于是 override 留在 70——阴影当场回来了、
	# 按钮也写着「高」，而**下一趟进这一趟的草皮还是 70m**。这个 bug 两侧各自
	# 都绿：阴影那侧量的是当场生效的开关，半径那侧量的是这一趟建好的 `_radius`
	# （它确实还是 70，符合"不重建"的预期）。回归见 `verify_quality_settings.gd`
	# 第 4 节末尾那两条。
	var g: Node = world.get_node_or_null("GrassScatter")
	if g != null:
		g.set("radius_override", maxf(float(p["grass_radius"]), 0.0))
	var tr: Node = world.get_node_or_null("TreeScatter")
	if tr != null:
		tr.set("radius_override", maxf(float(p["tree_radius"]), 0.0))
