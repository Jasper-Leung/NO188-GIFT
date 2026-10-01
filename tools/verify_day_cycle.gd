extends SceneTree
## 昼夜切换回归 —— 骑满两圈之后天色要真的走到黄昏，而且不能伤到任何别的东西。
##
## 这条回归守四件事，前三件是"改对了没有"，第四件是"会不会顺手弄坏别人"：
##   1. 门槛在第三圈（骑满两整圈），不是第一圈也不是第五圈。
##   2. 太阳的**方向**跟着降下来了。只改颜色的话影子长度和方向没变，
##      那不是黄昏，那是有人给太阳换了灯泡 —— 而数字（energy/color）看着都对。
##   3. 天**真的**跟着变了。这一条量的是 `ProceduralSkyMaterial` 而不是
##      `background_color`：场景是 `BG_SKY` + `AMBIENT_SOURCE_SKY`，
##      而它那份 ProceduralSky 是 Godot 3 的老数据、4.6 载入时静默丢掉了。
##      于是在这个场景里 background_color 和 ambient_light_color 都不参与
##      渲染 —— 只改它们的话天和暗部一个像素都不动，所有断言都还是绿的，
##      玩家看到的还是一片白天的天。
##   4. **不许顺手把白天的档位改了**。白昼那一档全部在 setup() 里从场景读，
##      不在本文件里再抄一份；抄一份的话谁改了 World3D.tscn，转场第一帧就跳。
##      只有把场景**重新实例化一份**去对，才量得出原始值还在不在。
##      （天空是唯一的例外，理由见 DayCycle.gd 里 DAY_SKY_* 那段注释。）
##
## 用法： godot --headless --path . --script tools/verify_day_cycle.gd --quit-after 30000
## 注意 --quit-after 单位是帧不是秒。

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _dc: Node = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _ridge: Node = null
var _dusk_count := 0

## 场景文件里那盏灯的原始姿态。DayCycle 必须在 t=0 时**原样**交还它，
## 否则玩家开局第一帧就会看到太阳跳一下。
var _day_basis := Basis.IDENTITY
var _day_elev := 0.0
var _day_azim := 0.0
## 白昼档由 DayCycle 从场景读，测试这边只转述 —— 别自己抄一份，
## 抄了就变成"拿测试的副本量测试的副本"。
func _dv(k: String) -> Variant:
	return _dc.day_value(k)
var _day_fog := Color(0, 0, 0, 1)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_ck(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _initialize() -> void:
	call_deferred("_run")


func _angles(b: Basis) -> Array:
	var z := b.z.normalized()
	return [asin(clampf(z.y, -1.0, 1.0)), atan2(z.x, -z.z)]


## 这台机器窗口模式能跑 280+ FPS，拿"帧数 ÷ 60"当秒数的断言全是错的。
func _step(world: Node, laps: float, seconds: float) -> void:
	world._odometer_units = float(world._total_arclen) * laps
	var frames: int = int(seconds * 60.0)
	for i in frames:
		await physics_frame


func _run() -> void:
	print("=== 昼夜切换回归 ===")

	_gm = root.get_node_or_null("GameManager")
	_loc = root.get_node_or_null("Localization")
	if _gm == null or _loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return

	# 原样再实例化一份场景（不 add_child，所以不会跑 _ready）
	# —— 用来量"World3D.tscn 里的原始白昼档还在不在"
	var fresh = load("res://scenes/World3D.tscn").instantiate()
	var fresh_sun: DirectionalLight3D = fresh.get_node("DirectionalLight3D")
	var fresh_env: Environment = fresh.get_node("WorldEnvironment").environment
	_day_basis = fresh_sun.basis
	var da := _angles(_day_basis)
	_day_elev = da[0]
	_day_azim = da[1]
	_day_fog = fresh_env.fog_light_color
	fresh.free()

	_gm.reset()
	_gm.onboarding_shown = true
	_gm.headless_mode = true

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout

	_sun = _world.get_node("DirectionalLight3D")
	_fill = _world.get_node("FillLight3D")
	_env = _world.get_node("WorldEnvironment").environment
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_ridge = _world.get_node_or_null("FarRidge")

	# ---- 1. 接线 ----
	_dc = _world.get_node_or_null("DayCycle")
	_ck("DayCycle 挂在场景里", _dc != null)
	_ck("远景山线在场景里", _ridge != null)
	if _dc == null or _ridge == null:
		_finish()
		return
	_ck("DayCycle 真的 setup 过（t 读得到）", _dc.get_t() >= 0.0)
	_dc.dusk_began.connect(func(): _dusk_count += 1)
	# 天必须真的有 material。整个昼夜切换的天色全靠它 —— 场景里那份是 Godot 3
	# 的老数据，4.6 静默丢掉了，`background_mode = BG_SKY` 配一个空 material
	# 渲出来是引擎兜底渐变，而 **background_color 在这个模式下压根不画**。
	# 所以"天没变"这种失败在这里量得出来，"天变了"在别处量不出来。
	_ck("场景自带的天空是空的（所以 DayCycle 必须自己建一个）",
			load("res://scenes/World3D.tscn").instantiate().get_node(
					"WorldEnvironment").environment.sky.sky_material == null)
	_ck("DayCycle 建出了真的 ProceduralSkyMaterial", _sky != null)
	if _sky == null:
		_finish()
		return

	# ---- 2. t=0 必须原封不动 ----
	_eq("开局还是白昼", float(_dc.get_t()), 0.0)
	# 比的是**光轴**（方向光只用 -Z），不是整副 basis：场景里那盏灯的 basis
	# 三列长度不等（编辑器存下来的缩放），DayCycle 把它重搭成正交阵，X/Y 的
	# 滚转变了但光照方向必须逐分量一致 —— 光轴变了就等于偷偷改了白天的影子。
	_ck("开局那盏灯的光轴和场景文件里分毫不差",
			_sun.basis.z.normalized().is_equal_approx(_day_basis.z.normalized()),
			"got=%s want=%s" % [str(_sun.basis.z.normalized()),
			str(_day_basis.z.normalized())])
	_ck("开局主光色 == 场景里的白昼档",
			_sun.light_color.is_equal_approx(_dv("sun_col")),
			str(_sun.light_color))
	_ck("开局雾色 == 场景里的白昼档",
			_env.fog_light_color.is_equal_approx(_day_fog), str(_env.fog_light_color))
	_ck("开局天顶色 == 白昼档", _sky.sky_top_color.is_equal_approx(_dc.DAY_SKY_TOP),
			str(_sky.sky_top_color))
	_ck("开局地平线色 == 白昼档",
			_sky.sky_horizon_color.is_equal_approx(_dc.DAY_SKY_HORIZON),
			str(_sky.sky_horizon_color))
	_ck("开局山线没有上色", _ridge._mats[0].albedo_color.is_equal_approx(Color.WHITE),
			str(_ridge._mats[0].albedo_color))

	# ---- 3. 门槛：前两圈不动，第三圈才转 ----
	await _step(_world, 0.0, 0.5)
	_eq("第 0.5 圈：还是白昼", float(_dc.get_t()), 0.0)
	await _step(_world, 1.4, 1.0)
	_eq("第 1.4 圈：还是白昼", float(_dc.get_t()), 0.0)
	await _step(_world, 1.99, 1.0)
	_eq("第 1.99 圈：还是白昼（门槛没提前）", float(_dc.get_t()), 0.0)
	await _step(_world, 2.0, 0.5)
	var t_early: float = _dc.get_t()
	_ck("刚过两圈：天开始暗但没暗完", t_early > 0.0 and t_early < 1.0,
			"t=%f" % t_early)

	# ---- 4. 转场途中：逐帧都在中间，不能跳 ----
	var last_t: float = t_early
	var pop := false
	for i in 30:
		await physics_frame
		var cur: float = _dc.get_t()
		if cur < last_t - 0.0001 or cur >= 1.0:
			pop = true
		last_t = cur
	_ck("转场是连续推进的（30 帧内没有倒退也没有一步到位）", not pop,
			"last t=%f" % last_t)
	var mid_t: float = _dc.get_t()
	var mid_a := _angles(_sun.basis)
	_ck("转场途中太阳已经比正午低", mid_a[0] < _day_elev,
			"elev %.3f → %.3f" % [_day_elev, mid_a[0]])
	_ck("转场途中太阳已经比正午高（还没到地平线以下）", mid_a[0] > 0.0,
			"elev=%.3f" % mid_a[0])
	_ck("转场途中主光色是插值出来的中间色（没一步到位）",
			_sun.light_color.g > _dc.DUSK_SUN_COL.g
			and _sun.light_color.g < (_dv("sun_col") as Color).g,
			str(_sun.light_color))

	# ---- 5. 转场跑完 ----
	await _step(_world, 3.0, float(_dc.FADE_SEC) + 1.5)
	_eq("转场跑完", float(_dc.get_t()), 1.0)
	_ck("黄昏主光色", _sun.light_color.is_equal_approx(_dc.DUSK_SUN_COL),
			str(_sun.light_color))
	_ck("黄昏辅助光色", _fill.light_color.is_equal_approx(_dc.DUSK_FILL_COL),
			str(_fill.light_color))
	_ck("黄昏环境光能量", is_equal_approx(_env.ambient_light_energy, _dc.DUSK_AMB_ENERGY),
			str(_env.ambient_light_energy))
	_ck("黄昏雾色", _env.fog_light_color.is_equal_approx(_dc.DUSK_FOG_COL),
			str(_env.fog_light_color))
	_ck("黄昏天顶色", _sky.sky_top_color.is_equal_approx(_dc.DUSK_SKY_TOP),
			str(_sky.sky_top_color))
	_ck("黄昏地平线色", _sky.sky_horizon_color.is_equal_approx(_dc.DUSK_SKY_HORIZON),
			str(_sky.sky_horizon_color))
	# 天色的判据全写成"比白昼那一档"：黄昏档是照着渲出来的图调的，绝对值
	# 单独写一份在这里等于又抄了一份基准，抄错了自己看不出来。
	_ck("黄昏的天顶比白昼暗",
			_sky.sky_top_color.get_luminance() < _dc.DAY_SKY_TOP.get_luminance(),
			"dusk=%.3f day=%.3f" % [_sky.sky_top_color.get_luminance(),
			_dc.DAY_SKY_TOP.get_luminance()])
	_ck("黄昏的天是上暗下亮（渐变方向反了就是一张滤色片）",
			_sky.sky_top_color.get_luminance() < _sky.sky_horizon_color.get_luminance(),
			"top=%.3f horizon=%.3f" % [_sky.sky_top_color.get_luminance(),
			_sky.sky_horizon_color.get_luminance()])
	_ck("白昼那档是上亮下…（正午的天顶比地平线深，这是天该有的样子）",
			_sky.sky_horizon_color.get_luminance() > _dc.DAY_SKY_TOP.get_luminance(),
			"top=%.3f horizon=%.3f" % [_dc.DAY_SKY_TOP.get_luminance(),
			_dc.DAY_SKY_HORIZON.get_luminance()])
	_ck("黄昏的地平线是烧红的（红压过蓝）",
			_sky.sky_horizon_color.r > _sky.sky_horizon_color.b,
			str(_sky.sky_horizon_color))
	_ck("黄昏的雾是暖的（白昼那档是青白的）",
			_env.fog_light_color.r > _env.fog_light_color.b,
			str(_env.fog_light_color))

	# ---- 6. 太阳的方向：这一条是"只改颜色"过不去的 ----
	var dusk_a := _angles(_sun.basis)
	_ck("黄昏太阳压到了地平线附近",
			absf(dusk_a[0] - deg_to_rad(_dc.DUSK_ELEV_DEG)) < 0.02,
			"elev=%.4f want=%.4f" % [dusk_a[0], deg_to_rad(_dc.DUSK_ELEV_DEG)])
	_ck("黄昏太阳比正午低得多（影子会拉长）",
			dusk_a[0] < _day_elev - deg_to_rad(15.0),
			"%.1f° → %.1f°" % [rad_to_deg(_day_elev), rad_to_deg(dusk_a[0])])
	var swung: float = absf(wrapf(dusk_a[1] - _day_azim, -PI, PI))
	_ck("黄昏太阳的方位角转过了（影子方向也变了）",
			absf(swung - deg_to_rad(_dc.DUSK_AZIM_SWING_DEG)) < 0.02,
			"swing=%.1f°" % rad_to_deg(swung))

	# ---- 7. 山线跟着上色 ----
	_ck("山线三层都上了黄昏色",
			_ridge._mats.size() == 3 and _ridge._mats[0].albedo_color.is_equal_approx(_dc.DUSK_RIDGE_TINT),
			"n=%d tint=%s" % [_ridge._mats.size(), str(_ridge._mats[0].albedo_color)])
	_ck("山线确实变暗了（否则三层会亮过黄昏的天空）",
			_ridge._mats[0].albedo_color.get_luminance() < 0.95,
			str(_ridge._mats[0].albedo_color))

	# ---- 8. 浮了一行字 ----
	# 断**信号发了几次**，别断标签上还有没有字：show_pass_line 会挂 3.2 秒，
	# 0.5 秒后再去看它当然还在字——那是它该有的行为，不是"又浮了一遍"。
	_ck("转场完成时恰好发了一次 dusk_began", _dusk_count == 1, "发了 %d 次" % _dusk_count)
	_ck("转场完成时浮出了那一行（不浮的话玩家只会以为显卡掉了）",
			str(_world._hud3d._pass_label.text) == str(_loc.t("dusk_began")),
			"浮的是：%s" % str(_world._hud3d._pass_label.text))

	# ---- 9. 单调：已经在黄昏了就别因为里程读数抖一下而闪回白天 ----
	await _step(_world, 2.02, 0.5)
	_ck("里程读数在门槛附近抖动不会把天色拉回白天",
			float(_dc.get_t()) == 1.0, "t=%f" % float(_dc.get_t()))
	_ck("dusk_began 不会因为里程读数抖动而反复发", _dusk_count == 1,
			"发了 %d 次" % _dusk_count)

	# ---- 10. 场景文件里的白昼档没被动过 ----
	# 颜色都挂在 World3D.tscn 的节点属性上，改的是实例；重新实例化一份场景
	# 对一遍，量得出"白档是不是原样"。只量 t=0 的话只能证明 DayCycle 自己
	# 记下了原始值，证明不了它没顺手把场景也改了。
	var fresh2 = load("res://scenes/World3D.tscn").instantiate()
	var f2env: Environment = fresh2.get_node("WorldEnvironment").environment
	var f2sun: DirectionalLight3D = fresh2.get_node("DirectionalLight3D")
	_ck("场景文件里的雾色还是白昼", f2env.fog_light_color.is_equal_approx(_day_fog),
			str(f2env.fog_light_color))
	_ck("场景文件里的环境光能量还是白昼",
			f2env.ambient_light_energy == _dv("amb_energy"),
			str(f2env.ambient_light_energy))
	_ck("场景文件里的主光还是白昼",
			f2sun.light_color.is_equal_approx(_dv("sun_col") as Color),
			str(f2sun.light_color))
	_ck("场景文件里那盏灯的朝向没被动过",
			f2sun.basis.is_equal_approx(_day_basis), str(f2sun.basis))
	fresh2.free()

	_finish()


func _finish() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_gm._clear_save()
	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)
