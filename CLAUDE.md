# CLAUDE.md — 188号礼物 项目档案

## 项目概览

《188号礼物》是一款 3D 骑行 demo：沿一条由贝塞尔参数曲线自行构造的 8 字 lemniscate 环形路线，玩家骑着自行车穿越 5 个有碎片的东坡赏心乐事驿站，集齐"云/茶/琴/竹/禽"五个字合成一份礼物。

> **本作是纯虚构作品**：路线为几何图案自行构造，不参考、不还原任何现实公路走向；驿站名全部是虚构雅称；题材取自公有领域的东坡诗文。详见 README 的 Legal 说明。

- **引擎**: Godot 4.6.2 (Forward+)
- **主场景**: `res://scenes/GiftBox.tscn` → `res://scenes/World3D.tscn` → `res://scenes/EndCard.tscn`
- **Autoload**: `GameManager`（存档）、`AudioManager`（音效）、`Localization`（中/英双语）
- **导出目标**: Windows .exe, Web (HTML5 + WebAssembly), Android

## Godot 可执行文件路径

```
D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe
```

（路径含目录名 `Godot_v4.6.2-stable_win64.exe` 与同名 exe，是历史遗留布局，调用时需两层转义。）

## 目录结构

```
scenes/           场景文件 (.tscn)
  GiftBox.tscn    开始界面
  World3D.tscn    3D 骑行主场景
  EndCard.tscn    收集完成
  Bike.tscn       自行车模型
  FragmentBar.tscn 顶部碎片栏
  EditorHUD.tscn  编辑模式侧栏（仅编辑时挂载）

scripts/          GDScript 脚本
  GameManager.gd        全局存档 + 状态机
  World3D.gd            3D 场景主控
  RoadBuilder.gd        沥青双车道 mesh 生成
  TerrainBuilder.gd     程序化地形 mesh + 高度查询
  VegBuilder.gd         流式植被（MultiMesh + 16 chunks）
  GrassScatter.gd       玩家周围的实例化草皮（MultiMesh 池 + 逐格流式 + 叠加同心环，
						桌面 200m / Web·移动端 100m；驻留期间零重建零隐藏）
  TreeScatter.gd        路两侧行道树（沿中心线按弧长等间距 25m，每格一个 MultiMesh +
						visibility_range 淡出；桌面 150m / Web·移动端 100m；驻留零重建）
  FarRidge.gd           远景山线：三层环形山脊（800/1350/1900m，纯几何零贴图，
						顶点色烘空气透视），补地形边界之外什么都没有的平地平线
  road_data.gd          48 点 lemniscate 路径 + 16 驿站数据
  LayoutData.gd         res://layout.json 读写（编辑模式产物）
  LayoutEditor.gd       编辑模式主控制器
  EditorHUD.gd          编辑模式 UI
  Player3D.gd / Bike.gd / HUD3D.gd / MiniMap.gd / CheckInPrompt.gd ...
  Localization.gd       i18n

assets/
  fonts/         LXGWWenKai (中英文 fallback)
  models/        bush.glb / tree.glb / station_*.glb / bike.glb
  shaders/       asphalt.gdshader (路面全程序化,零贴图)
				 terrain_grass.gdshader (地形草地质感,零贴图)
				 grass.gdshader (实例化草皮卡片,零贴图)

tools/            Python 字体子集化 / 音频生成 + GDScript 无头验证脚本
  verify_8_shape.gd      8 字路径形状无头验证
  verify_crossing.gd     交叉点高度查询无头验证
  verify_road_height.gd  路面高度无头验证
  verify_vegetation.gd   植被覆盖范围无头验证
  verify_vegetation_grounding.gd 每株植物都站在地上（Transform3D.scaled 缩放 origin 的回归）
  verify_pavilion_bushes.gd 驿站周围灌木清除验证
  verify_terrain_shader.gd  地形草地质感 shader 回归（材质/剔除pragma/顶点色）
  verify_grass_scatter.gd  草皮放置/确定性/流式回归（贴地、离路、让位、各环嵌套、
						驻留环、池预算、骑行中零重建零隐藏、单帧 CPU 预算）
  lookdev_grass.gd        草皮五张定妆照 4/15/45/100/190m（**不能加 --headless**、**不能加 --quit-after**）
  verify_tree_scatter.gd 行道树放置/流式回归（贴地、离路净空、弧长等间距、避让广场驿站、
						驻留集合、每格只建一次、实例容量对账、三角面预算）
  lookdev_trees.gd        行道树定妆照 14/55/100/135m + 淡出带特写 + 树排 + 高空俯视
						（**不能加 --headless**、**不能加 --quit-after**）
  verify_mini_game.gd    5 个小游戏注入链路（size/焦点/结果码契约 + **五个都接 ESC 取消**）
  verify_interact_latch.gd 交互闩锁 / 对白抢占回归（郑铎在播时按空格不许开打卡、
						setup() 顶掉一轮对白必须放出旧等待者、被顶掉的郑铎戏自己清
						_villain_playing、回访不再重播小游戏/谎报碎片、铺子仍能开）
  verify_bamboo_world.gd 真实 World3D 端到端：打卡→小游戏→空格不泄漏成驿站交互
  verify_mini_game_keys.gd 竹/琴/茶在"只有 physical_keycode"的键盘事件下仍可玩（**不能加 --headless**）
  verify_bamboo_done.gd 竹子砍完第 5 根后有成功画面停留、不会凭空消失（**不能加 --headless**）
  verify_mini_game_fail.gd 小游戏失败有交代 + 失败后驿站还能再玩（headless 可跑）
  verify_checkin_all5.gd  5 个碎片驿站完整成功链路 + 收尾后重打卡（**不能加 --headless**）
  verify_stations.gd      16 驿站 → GLB 配置一致性（model_idx 映射、GLB 存在、
						名字/color/event 完整、碎片顺序、无占位路标名）
  verify_station_roof.gd  驿站屋顶暖中性色回归（7 个手工模型命中 <站名>_roof 后缀、
						材质已 duplicate、屋顶确实比墙暗且没暗成洞、贴图模型 station_0..4
						结构上不被动、导入缓存没被写脏）
  verify_mood_mask.gd     心神遮罩 + 顶部经济栏回归（遮罩层级/两档透明度、骑行档
						永远可读、遮罩只随心神不走灯笼、系数传到草皮与行道树、
						入账 toast 不重排顶栏、叙事脉冲冲上/退回）
  verify_minimap.gd       小地图未收碎片站回归（**沿途 321 个采样点上小地图高亮的
						必须就是顶栏「下一处」报的那颗**；收过的跳过、五块齐了不指人、
						普通驿站不冒充目标）
  verify_far_ridge.gd     远景山线材质回归（三层都 disable_fog、半径都在地形之外、
						颜色按距离递淡）—— 颜色本身只有 lookdev_horizon.gd 能判
  lookdev_horizon.gd      远景山线四张定妆照：路面视角 / 地形高点 / 逆光 / 高空
						（**不能加 --headless**、**不能加 --quit-after**）
  lookdev_journey.gd      玩家视角 17 屏流程实拍（标题→操作说明→序章→骑行→打卡提示
						→**路过风景驿浮的那一句**→驿站对白→5 个小游戏→驿铺→集齐
						→终局二选一→明信片→背面写字），存 user://lookdev_journey/
						（**不能加 --headless**、**不能加 --quit-after**）
  verify_economy.gd       旅币/背包/心神/存档回归 + 预算按公式重算 + **里程不许出现在
						任何玩家可见文案里**（含中文「公里」与英式 kilometre）
  verify_shop_panel.gd / verify_shop_world.gd  驿铺面板 / 真实 3D 世界里的购买链路
  verify_postcard_ending.gd 明信片纸面分级 + 终局二选一 + **重新开始前的「这一趟」回执**
						（keep/break 的后果必须在**正面**上、**回执每一条都要对着存档逐字核对**）
  lookdev_postcard.gd      明信片 18 张定妆照（四档纸面/满配/背面三态/蜡封三态/未竟缺格
						/二选一/揭示/**回执中英各一张**）
						（**不能加 --headless**、**不能加 --quit-after**）
  generate_ui_sfx.py / generate_mini_game_sfx.py / gen_ambient_audio.py 音效合成
```

## 关键约束

1. **零纹理资产（WebGL 友好）**: 路面 asphalt 用 `assets/shaders/asphalt.gdshader` 程序化生成（颗粒、胎痕、路缘起灰、潮斑、路肩泥土、双黄虚线），地形用 `assets/shaders/terrain_grass.gdshader`（低频色块、中频草丛斑驳、高频麻点、随距离淡出的法线扰动），近处草皮用 `assets/shaders/grass.gdshader` 的实例化卡片。植被 mesh 用 `SphereMesh`+`StandardMaterial3D` 程序化或 GLB。
2. **路线是自行构造的贝塞尔 8 字图案**: `scripts/road_data.gd` 的 `LEMNISCATE_LOCAL` 是解析式采样的 49 点 lemniscate，经旋转/缩放后生成 3D 路网。**不引用任何外部 SVG 或现实道路数据**。任何"几何简化"或"手调节点"都只影响游戏内观感，不涉及外部数据一致性。
3. **8 字交叉点高度查询**: 玩家 Y 必须用 `RoadBuilder.get_road_ribbon_height(x, z)`（三角形质心插值 + max 聚合），不能用 `get_road_height_at_xy`（会跳变 0.143m）。
4. **MiniMap 是 3D 在线组件**: `MiniMap.gd` 在 `World3D.gd` 启动时初始化，**不能删**（过去差点被误删）。

## 开发工作流

### Headless 验证

```bash
# 路径短别名
GODOT="D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"

# 编译校验(无窗口跑 5 秒)
"$GODOT" --headless --path . --quit-after 5

# 8 字路径形状无头验证
"$GODOT" --headless --path . --script tools/verify_8_shape.gd --quit-after 10

# 路面高度无头验证
"$GODOT" --headless --path . --script tools/verify_road_height.gd --quit-after 10

# 地形草地质感着色器回归（材质类型/剔除pragma/顶点色值域与确定性）
"$GODOT" --headless --path . --script tools/verify_terrain_shader.gd

# 植被覆盖验证
"$GODOT" --headless --path . --script tools/verify_vegetation.gd --quit-after 15

# 植被贴地回归（origin.y 必须等于该 XZ 的地面高度）
"$GODOT" --headless --path . --script tools/verify_vegetation_grounding.gd

# 草皮放置/流式回归（贴地、离路、让位、逐格确定性、驻留环、骑行中零重建、单帧 CPU 预算）
"$GODOT" --headless --path . --script tools/verify_grass_scatter.gd

# 草皮定妆照：4/15/45/100/190m 五张存到 user://lookdev_grass/
# 注意：不能加 --headless（dummy renderer 不编译着色器），也不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_grass.gd

# 行道树放置/流式回归（贴地、离路净空、弧长等间距、避让广场驿站、驻留集合、三角面预算）
"$GODOT" --headless --path . --script tools/verify_tree_scatter.gd

# 行道树定妆照：14/55/100/135m + 淡出带特写 + 树排 + 高空俯视，存到 user://lookdev_trees/
# 注意：不能加 --headless（visibility_range 的淡出只有真渲染器才生效），也不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_trees.gd

# 小游戏注入链路验证
"$GODOT" --headless --path . --script tools/verify_mini_game.gd --quit-after 30

# 交互闩锁 / 对白抢占回归（约 15 秒；自己清理 user:// 存档）
# 改 DialoguePopup.setup()、World3D._can_start_check_in()/_do_check_in()/_play_villain_scene()
# 或 CheckInPrompt._label() 之后跑这个
"$GODOT" --headless --path . --script tools/verify_interact_latch.gd

# 打卡/小游戏空格泄漏端到端验证（真实 World3D，约 20 秒；自己清理 user:// 存档）
# 注意：不能带 --quit-after，会在中途把进程掐掉导致静默失败
"$GODOT" --headless --path . --script tools/verify_bamboo_world.gd

# 键盘事件识别验证（竹/琴/茶，约 2 分钟；自己清理 user:// 存档）
# 注意：不能加 --headless。headless 用的是 dummy display server，不做真焦点路由，
# 小游戏收不到 _gui_input，测出来的"通过"是假的。
"$GODOT" --path . --script tools/verify_mini_game_keys.gd --quit-after 40000

# 竹子砍完第 5 根的收尾验证（约 10 秒；自己清理 user:// 存档）
# 同样不能加 --headless。
"$GODOT" --path . --script tools/verify_bamboo_done.gd --quit-after 900

# 小游戏失败路径（面板交代 + 失败后还能再玩），约 40 秒；自己清理 user:// 存档
"$GODOT" --headless --path . --script tools/verify_mini_game_fail.gd

# 5 个碎片驿站完整链路（**不能加 --headless**：要靠真焦点路由点掉对白弹窗）
"$GODOT" --path . --script tools/verify_checkin_all5.gd

# 16 驿站 → GLB 配置一致性（model_idx 映射、GLB 文件存在、名字/color/event 完整、碎片顺序、无占位路标名）
"$GODOT" --headless --path . --script tools/verify_stations.gd

# 驿站屋顶暖中性色（材质按后缀命中、必须 duplicate、屋顶 vs 墙的亮度比、贴图模型不受影响）
"$GODOT" --headless --path . --script tools/verify_station_roof.gd

# 心神遮罩 + 顶部经济栏（两档透明度、骑行档可读上限、toast 不重排顶栏、叙事脉冲）
# 注意 --quit-after 单位是帧不是秒，本机 280+FPS，给小了会把脚本掐死在场景加载处
"$GODOT" --headless --path . --script tools/verify_mood_mask.gd --quit-after 30000

# 小地图未收碎片站（沿途逐点核对小地图 == 顶栏「下一处」）
"$GODOT" --headless --path . --script tools/verify_minimap.gd --quit-after 30000

# 远景山线材质（三层都关了雾、半径在地形之外、颜色按距离递淡）
"$GODOT" --headless --path . --script tools/verify_far_ridge.gd

# 远景山线定妆照：路面视角 / 地形高点 / 逆光 / 高空，存到 user://lookdev_horizon/
# 不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_horizon.gd

# 玩家视角 17 屏流程实拍，存到 user://lookdev_journey/
# 改 HUD / 标题页 / 商店 / 明信片 / 任何一屏的玩家可见文字后跑这个
# 不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_journey.gd

# 明信片纸面分级 + 终局二选一 + 「这一趟」回执（headless 可跑）
"$GODOT" --headless --path . --script tools/verify_postcard_ending.gd

# 明信片 18 张定妆照（四档纸面 / 背面三态 / 蜡封三态 / 未竟缺格 / 二选一 / 揭示 / 回执中英）
# 存到 user://lookdev_postcard/。不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_postcard.gd
```

### 编辑模式（关卡布局工具）

激活方式（任一）：

```bash
# 1. 命令行参数 (不能用 --editor,会与 Godot 内置标志冲突)
"$GODOT" --path . --gift-editor

# 2. 环境变量
set GIFT188_EDITOR=1
"$GODOT" --path .

# 3. 标记文件 (.editor_mode 已加入 .gitignore,本机兜底用)
echo. > .editor_mode
"$GODOT" --path .
```

操作：

| 键 | 功能 |
|---|---|
| WASD | 相机水平移动（Shift 加速 3x） |
| R / F | 相机上升 / 下降（独立键，避免与旋转冲突） |
| 右键拖拽 | 相机旋转视角 |
| 鼠标左键 | 拾取最近的驿站 / 植物；点击同一对象或空白 → 取消选中 |
| 方向键 | 平移当前选中（按住连续 3m/s，Shift 加速到 15m/s） |
| Q / E | 绕 Y 旋转选中 ±5°（**专属旋转键，不动相机**） |
| [ / ] | 植物 uniform 缩放 |
| Backspace | 重置当前选中 |
| X 或工具栏"取消选中" | 退出选择，把 WASD 还给相机 |
| Ctrl+S | 保存到 `res://layout.json` |
| Esc | 退出（回到 GiftBox） |

**重要**：选中对象时方向键只移动对象、不动相机；Q/E 只旋转、不动相机升降。Q/E 不再绑相机升降（R/F 接管），避免"按旋转就视角乱飞"。**X 键**（或工具栏按钮、点击同一对象/空白）可退出选择，避免选中后 WASD 被劫持。

编辑后保存的 `res://layout.json` 会被提交到 git；普通玩家启动时由 `World3D._setup_stations()` 与 `VegBuilder.setup()` 自动消费。

### 玩家存档

- 存档路径：`user://gift188.cfg`（Windows: `%APPDATA%\Godot\app_userdata\188号礼物\`）
- 自动写入：每次打卡成功（`GameManager.check_in()`）
- 自动读入：游戏启动（`GameManager._ready()` → `_load_save()`）
- 显式重置：`GameManager.go_to_gift_box()` 走 `reset()` 路径（"重新开始"按钮）

## 提交规范

- 一类改动一个 commit；commit message 用动词开头（如 `fix:`, `feat:`, `refactor:`, `docs:`）
- 中文 commit subject 可，body 用中文或英文均可
- 修改 `assets/shaders/asphalt.gdshader` 前先在 headless 跑 `verify_road_height.gd` + `verify_crossing.gd`
- 修改 `scripts/TerrainBuilder.gd` / `assets/shaders/terrain_grass.gdshader` 前先跑 `verify_terrain_shader.gd` + `verify_road_height.gd` + `verify_crossing.gd`
- 修改 `scripts/road_data.gd` / `scripts/RoadBuilder.gd` 前先在 headless 跑 `verify_8_shape.gd`
- 修改 `scripts/road_data.gd` 的 stations 数组（名字 / model_idx / fragment）前先在 headless 跑 `verify_stations.gd` + `verify_8_shape.gd`（stations 数组同时是 lemniscate 驿站映射）
- 修改 `scripts/VegBuilder.gd` 前先跑 `verify_vegetation.gd` + `verify_pavilion_bushes.gd` + `verify_vegetation_grounding.gd`
- 修改 `scripts/GrassScatter.gd` 前先跑 `verify_grass_scatter.gd`
- 修改 `scripts/TreeScatter.gd` 前先跑 `verify_tree_scatter.gd`；改间距/离路/淡出参数后还要跑 `lookdev_trees.gd` 看图（`CELL` 必须和 `GrassScatter.CELL` 一致，两套流式共用同一张格子）
- 修改 `assets/shaders/grass.gdshader` 前先跑 `lookdev_grass.gd` 看图（`--headless` 的 dummy renderer **不编译着色器**，语法错在无头下会静默通过）
- 修改 `scripts/mini_games/*.gd` / 打卡流程前先跑 `verify_mini_game.gd` + `verify_bamboo_world.gd` + `verify_mini_game_keys.gd` + `verify_bamboo_done.gd` + `verify_mini_game_fail.gd` + `verify_checkin_all5.gd`
- 改 `scripts/AudioManager.gd` 或 `scripts/mini_games/*.gd` 里的发声前先跑 `check_all_scripts.gd` + 上面那 6 条；新加了 sfx 还要跑一次 `--headless --editor --quit-after 60` 生成 `.import`
- 改任何一屏玩家可见的东西（HUD / 标题页 / 新手引导 / 商店 / 驿铺 / 明信片 / 结算）前跑 `lookdev_journey.gd` 看图
- 改 `scripts/FarRidge.gd` 的层数 / 半径 / 颜色前跑 `lookdev_horizon.gd` 看图（AGX 会把中间调提亮去饱和，填色要反着调，见已知陷阱）
- 改顶栏 / `scripts/shop_data.gd` 的解锁门 / `World3D.VILLAIN_SCENES` 的触发条件前跑 `verify_economy.gd`（含「里程不许出现在任何玩家可见文案里」扫描）+ `verify_shop_panel.gd` + `verify_shop_world.gd` + `lookdev_journey.gd` 看顶栏
- 改 `HUD3D._next_fragment_target()` / `_arrow_glyph()` 前跑 `lookdev_journey.gd`（它带一条几何断言：车头正对 → ↑、背对 → ↓、正右方 → →，只测 static 那个函数等于拿自己测自己）；方位用 `a(v) = atan2(v.x, -v.z)`，8 字环自闭合、两个方向都到得了全部 5 站，箭头必须真的随车头转
- 改 `HUD3D.MOOD_REST_SCALE` / `set_mood_pulse()` / `_setup_mood_mask()` 或 `World3D` 里推 `set_mood_pulse` 的那一行前跑 `verify_mood_mask.gd`（骑行档必须**永远**低于 0.20 可读上限，叙事档才允许冲到 `MOOD_MASK_MAX`）
- 改 `MiniMap._next_frag_idx()` / 未收碎片站的画法前跑 `verify_minimap.gd`（小地图高亮的那颗必须就是顶栏"下一处"报的那颗；这是继 `CheckInPrompt` 之后第三个会说"下一处在哪"的地方，判据一漂移玩家就骑错且无从察觉）
- 改 `FarRidge.LAYERS` / `_build_layer()` 的材质前跑 `verify_far_ridge.gd` + `lookdev_horizon.gd` 看图（`disable_fog` 被谁删掉的话三层会塌成一条没有纵深的白带，标志位那关拦得住，颜色那关只有看图）
- 改顶栏的经济标签（`_lvbi_label` / `_lvbi_toast` / `_setup_economy_labels`）前跑 `verify_mood_mask.gd` 第 7 节（它断言入账时余额/心神/"下一处"三个标签的横坐标一个像素都不许动）
- 改 `World3D._push_mini_game_chrome()` / `_pop_mini_game_chrome()` 前跑 `lookdev_journey.gd` 看 5 张 `minigame_*.png`（遮罩不透明 + 运行时藏 HUD，靠的是这对成对方法，漏掉一头就有一屏写着"两层同时存在"）
- 改 `DialoguePopup.setup()` / `World3D._can_start_check_in()` / `_do_check_in()` / `_play_villain_scene()` / `CheckInPrompt._label()` 前跑 `verify_interact_latch.gd`（这五处任何一个漏了都能把游戏变成"提示圈照画、按键全死、只能重开"）
- 改打卡流程的"这站还欠我一块碎片吗"判据前跑 `verify_interact_latch.gd` 第 4 节 + `verify_checkin_all5.gd`（`station_has_fragment(i)` 是站的静态属性、`is_collected(i)` 才是玩家进度；拿前者当前者会让回访重播小游戏并谎报"获得碎片"，而 HUD 的"下一处"早就把这站摘掉了，两边对不上）
- 改 `World3D._tint_station_roofs()` / `STATION_ROOF_TINT` 前跑 `verify_station_roof.gd` + `lookdev_journey.gd` 看 `04_ride`（填色要过 `linear_to_srgb`，写错方向屋顶比墙暗 30 倍，数字还是"暖的"，只有比值看得出来）
- 改 `EndCard._show_ending_choice()` / `_seed_back_text()` 前跑 `verify_postcard_ending.gd`（`keep`/`break` 的后果必须落在**正面**：留门=背面写上那句、放手=背面留白且封口的蜡掰开，两张卡片的正文必须**就是**真正会发生的那件事本身，不能另写一段描述——否则又变回"承诺一个差别、实际只改一句话"）
- 改 `EndCard._refresh_back_thumb()` / `_grab_back_thumb()` 前跑 `verify_postcard_ending.gd`（SubViewport 回读要等两帧；节流按累计 delta 掐，headless 跑两帧等不到 0.12s，测试里必须等墙钟）+ `lookdev_journey.gd` 看 `16_postcard_back`（要打完字再拍，只拍初始帧看不出缩略图跟不跟得上）
- 改 `EndCard._on_restart_pressed()` / `_recap_lines()` / `_recap_worth_showing()` 前跑 `verify_postcard_ending.gd` 第 8 节 + `lookdev_postcard.gd` 看 `12_回执` / `12b_recap_EN`（回执**每一条都要对着存档逐字核对**——编一条玩家没做过的事，第二趟发现根本没有，比不弹更伤；而 `go_to_gift_box()` 会 reset，所以回执只能赶在 reset 之前现算，不许另存快照）
- 改 `World3D` 里那段路过驿站的话（`STATION_PASS_RADIUS` / `_pass_inside` / `HUD3D.show_pass_line`）前跑 `lookdev_journey.gd` 看 `05b_pass`（16 站里有 11 座的 `text` 一直只写在 road_data 里没人读；边沿触发要靠 `_pass_inside`，只判距离会让玩家停在圈里每秒重弹一次）
- 改 `MiniGameTea` / `MiniGameZither` / `MiniGameBamboo` 等五个小游戏里的输入处理前跑 `verify_mini_game.gd` 第 5 节（五个都必须能用 ESC 取消 —— 取消按钮是 `_draw()` 画的假按钮，键盘点不到，茶最糟：既放弃不了又失败不了，键盘玩家唯一出路是干等 30s 超时）。注意 ESC 的插入位置各不相同：琴要放在示范阶段的早退之前、竹要放在 1.6s 成功停留之后（那一下不许跳）

## 已知陷阱
- **这个世界的环路只有 1228.8m，「188」是编号不是里程**：8 字路 `LEMNISCATE_SCALE = 350`，
  实测 `total_arclength() = 1228.8`（bbox 329×361m）。而 `GameManager.TOTAL_ROUTE_KM = 188`
  把它摊开，按 15 m/s 满速折算是 **2 km/s ≈ 7200 km/h**，跑满一整圈只要 82 秒。
  玩家骑三十秒就能心算出这个数，然后「188」这个题眼连同它承载的一切门槛一起变噪音。
  所以顶栏、所有文案、所有解锁门都已改成**驿数**口径（`GameManager.get_seen_station_count()`，
  顶栏写「已过 n/16 驿」），里程只在内部作旅币经济口径。已从 km 门迁走的：
  灯铺解锁（`seen_unlock = 6`）和 `World3D.VILLAIN_SCENES` 三场郑铎戏（`seen = 4/8/12`，
  原来是 50/100/150km，也就是开局第 25/50/75 秒把整条反派线灌完）。
  `verify_economy.gd` 的 `_check_km_offscreen()` 会扫全部文案里的
  `km / 公里 / kilometer / kilometre / K0 / K188`——**关键词要查全**，只查 "km" 会漏掉
  中文的「公里」（第一版就漏了 `onboarding_subtitle` 的「沿188公里环形路线」）；
  英式拼法 "kilometre" 也不是 "kilometer" 的子串（e 和 r 换了位置），得单独列一条。

- **`Transform3D.scaled()` 会把 origin 一起缩放**：它不是"只缩 basis"，
  `Transform3D(basis, pos).scaled(Vector3(s,s,s))` 的 origin 会变成 `pos * s`。
  植被实例变换曾因此让每株植物落在"地面高度 × 缩放"上（灌木平均浮 0.74m、
  树平均浮 7.79m、最多 102m），表现就是大片灌木浮在空中。必须写
  `Transform3D(basis.scaled(s), pos)`。统一走 `VegBuilder.instance_transform()`
  这个 static 函数。回归验证：`verify_vegetation_grounding.gd`。

- **`ALPHA_SCISSOR_THRESHOLD` 判的是 `ALPHA`，而 `ALPHA` 默认是 1.0**：
  只设 `ALPHA_SCISSOR_THRESHOLD` 不写 `ALPHA`，scissor 什么都不剔，整张卡片
  全不透明——草皮会渲染成一地绿色多边形。同时写 `ALPHA` 并不会掉进排序透明
  管线（引擎在 `ALPHA_SCISSOR_THRESHOLD` 也被赋值时按不透明材质处理，深度
  写入、正确排序、阴影投射都还在）。这坑是看截图发现的：headless 下不编译
  着色器，`verify_grass_scatter.gd` 全绿也照样错。

- **`MultiMesh.use_custom_data` 只能在 `instance_count == 0` 时设置**：
  引擎规定 `transform_format` → `mesh` → `use_custom_data` → `instance_count`
  → 写入这个顺序，顺序错了报 `ERROR: Condition "instance_count > 0" is true`
  并且**标志被静默丢弃**（`INSTANCE_CUSTOM` 读出来全是 0）。

- **`--headless` 既不编译着色器，也不回读 `MultiMesh`**：dummy renderer 下
  `MultiMesh.get_instance_transform()` 一律返回单位矩阵，从 GPU 侧验证实例
  变换得到的数全是假的。MultiMesh 状态只能走 CPU 侧的 `generate_cell()` 和
  共享的 static 辅助函数来测，着色器语法只能靠带窗口的 `lookdev_grass.gd`。

- **草皮的离路判定必须只查本索引格，不能扫邻域**：登记时每段路都进了它 AABB
  外扩 `ROAD_CLEAR` 的所有格子，所以"离 p 不超过 radius"的段一定在 p 本格里，
  单格查询对让位判定是**精确**的。实测这一处从 64.6µs/次（3×3 邻域）降到
  ~0.6µs/次，`generate_cell` 从 13.0ms/格降到 1.68ms/格——这是草皮能不能上
  Web 的关键。`distance_to_road()` 扫 3×3 只留给工具/回归取一个精确的距离
  **数值**，别把它放回热路径。

- **草皮的距离分层必须是"叠加的同心环"，不能是"每格一个会变的档位"**：
  这是脚边草消失又冒出来的根因。旧实现每格只记一个当前档位，跨过档位边界
  就要拆槽、`visible_instance_count` 归零、进队列排队；15m/s 骑过 32m 一格
  就有约五十个格换档排队，离玩家最近的那几个排在几十名之后，空掉一秒多。
  现在第 r 环的驻留判据是"格心距 <= RING_DIST[r] + CELL/√2"**整个圆盘**，
  层层包含，同一格在它落进的每一层里各有一份 MultiMesh，只有最小的
  （包含它的）那层可见。于是每格一生只建 `RING_COUNT` 次，每次都发生在它刚
  跨进某层盘的外沿、还很远的时候；切环是一次纯显示/隐藏切换
  （`_refresh_visible`，且只在目标那份已建好时才切，所以不会闪空帧）。
  回归验证：`verify_grass_scatter.gd` 第 8 节——300m 骑行后所有驻留
  `(格,环)` 份的累计构建次数都必须是 1。

- **草皮的建格预算只能是墙钟，不能是丛数**：一格的成本按环差 14 倍
  （ring 0 的 5120 丛约 10ms，ring 3 的 358 丛约 0.5ms），丛数预算兜不住
  两端。`tick()` 里用 `Time.get_ticks_msec()` 掐 `BUILD_MS_STREAM` /
  `BUILD_MS_BULK`，而且要掐在**建之前**——格子的原子性决定最坏一 tick 是
  "预算 + 一整格"，掐在建之后会多算一格。

- **大预算只能给"reset 之后第一次铺满"，别拿队列长度当开关**：15m/s 骑过一格
  （32m）本来就会让几十个格进环、几百个 `(格,环)` 份入队，队列长度和开局一个
  量级。曾经用 `_pending.size() >= BULK_QUEUE` 判"是不是在铺满"，结果骑行途中
  一直走 16ms 大预算，最慢一帧顶到 25ms。现在用 `_bulk` 标志，`reset()` 置位、
  队列排干时清零。

- **草皮的池子必须每层环各按自己的盘面积开**：`instance_count` 是槽位建好时
  定死的，319 个槽全按 5120 开就是 100MB buffer，Web 上直接爆。ring 0 的盘
  只有 52.6m（约 15 格）但每格要 `RING_CAP[0]`=5120 丛，ring 3 的盘有 222.6m
  （约 180 槽）但每格只要 358 丛——按 `π·reach²/CELL² × 1.15 + 6` 逐层算，
  总共约 19.7MB。提前量 `CELL/√2` 必须算进 reach：按 `RADIUS` 算会低估 20%
  然后表现为"驻留集合少十几格"。另外小半径下最外环是空的（Web 的 100m 没有
  ring 3），`_compute_rings()` 会把 `ring_count` 收窄，别按 `RING_COUNT`
  无脑建槽。

- **槽位抢不到要能重试**：`tick()` 里除焦点跨格外还要看 `_starved`——上一轮
  `_retarget` 有格没抢到槽位时置位，焦点停在原地时不会跨格，光靠跨格触发就会
  把那几格永远漏掉，环上留一个洞。

- **草皮淡出带量的是"到相机的距离"，不是"到焦点的距离"**：游戏里相机贴地
  （离焦点 1.6m），两者近似相等；编辑模式俯视相机在 100m 高空，这个等式
  就断了，整圈草会全淡成 0。修法是 `World3D._stream_focus_pos()` 里每帧调
  `set_fade_for_camera(cam)` 把淡出带外扩，不是 `set_fade_range` 写死两个数
  ——相机一直在动，写死的值换个机位就又不对了。草和树各调各的（`_tree_scatter`
  与 `_grass_scatter` 分开调），因为两者的 `RADIUS` / 淡出带不一样。

- **`lookdev_grass.gd` 的相机必须站在草环的圆心**：shader 的淡出带按到相机的
  距离算，把相机搬到 190m 外去拍远景，等于站进 ring 3 的草里，量到的是
  "草贴脸"而不是玩家看见的"远处一层草"。之前那版 4/15/28/45m 的拍法在
  半径 30m 时凑巧能用（45m 已在环外），半径放大到 200m 后必须改成从圆心往外看。

- **`visibility_range` 量的是"相机到 MultiMeshInstance3D 节点原点"，不是到实例**：
  整格共用一个淡出系数。节点原点放在格心、`range_end` 再补 `BUILD_LEAD`（半格
  对角线 22.6m），才能保证"加载半径内的树其格心都不越界"——不补的话格边上那棵
  会还没淡完就被整格掐掉，看着像"还有二十米树突然没了"。代价是**按树的距离**看
  淡出带被拉宽成 `[RADIUS - BUILD_LEAD, RADIUS + FADE_BAND + BUILD_LEAD]`
  （桌面 = [127.4, 192.9]m），树排的远端边缘在格心之间会参差 ±22.6m；但每棵树
  自己仍然连续淡出，不会 pop。测这条只能靠像素，别靠"相机到树"的距离去挑目标：
  按树距挑"淡出带中间"，很可能捞到一棵格心已越界、早就淡完的（`lookdev_trees.gd`
  第一次跑就是这样——160m 那张图里压根没有树，人眼还看不出问题）。回归验证：
  `verify_tree_scatter.gd` 第 8b 节的 `bad_cull == 0` 不变式。

- **驻留集合的期望集合必须只枚举"有节点的格"，不能枚举邻域格子**：没有树的格从不
  建节点，按"焦点附近的整个圆盘"去逐个比 `visible` 会把每个空格都误记成"少一格"。
  正确做法是先从 `get_children()` 收集实际存在的 `(格心, 节点)`，再逐格独立复算
  驻留判据。`TreeScatter._refresh()` 反过来必须**遍历全部格**——上一次驻留、这次
  出环的格要在那里被关掉，只扫焦点附近会让旧位置残留 visible=true 的树。这两个
  方向容易搞反，`verify_tree_scatter.gd` 第 8 / 9 节各拦一边。

- **不要让 `_ready()` 强制 reset 进度**：旧版 `_ready()` 在 2026-09-21 修复前会无条件重置 `collected[]`，导致 `_load_save()` 写进磁盘但读不回。
- **不要复用 `move_*` 输入动作给编辑器**：玩家与编辑器的 WASD 必须隔离，否则方向冲突会让玩家在编辑器里乱跑。
- **.editor_mode 是本机文件**：误提交会让所有开发者进入编辑模式。已在 `.gitignore` 加入 `/`。
- **不要用 `--editor` 标志**：会启动 Godot 编辑器 UI 而不是游戏。必须用 `--gift-editor`。
- **植物 pos.y 不可信**：编辑器保存的 Y 仅作参考，运行时 `VegBuilder._prepare_plant()` 会重新贴地形高度。
- **小游戏的按键拦不住全局 `interact`**：空格同时是 `interact` 动作。`_gui_input` 里 `get_viewport().set_input_as_handled()` 只阻断事件传播，`Input.is_action_just_pressed("interact")` 由 OS 输入管线在 GUI 处理之前就写进 Input 单例，照样为 true。所以打卡/小游戏期间必须在 `World3D` 侧加门控（`_check_in_in_progress` / `_mini_game_state == MG_RUNNING`），收尾还要给 `_interact_cooldown` 一段静默期——否则竹子这类按空格小游戏一结束，玩家手上还在按的空格会立刻再触发一次驿站打卡。回归验证：`verify_bamboo_world.gd`。
- **小游戏里判按键要同时认 `keycode` 和 `physical_keycode`**：本项目 InputMap 用 `physical_keycode` 注册动作（`GameManager._add_action`），而 Web 导出下 `event.keycode` 可能填不上。只判 `keycode` 的话按键既不生效、也不被吃掉，窗口/超时一到就判 `CANCELLED`，`_finish_check_in()` 把玩家踢出打卡——玩家看到的就是"按空格会退出游戏"。回归验证：`verify_mini_game_keys.gd`。

- **一个 `await` 挂死了不会自己报错，只会把一个布尔闩锁永久留在 true 上**：
  对白弹窗全世界只有一份，`World3D` 里有好几条协程会 `await _dialogue_popup.dialogue_done`
  （驿站对白、序章、郑铎三场）。而 `interact` 和 `ui_accept` **是同一个键**（都是空格/回车），
  `DialoguePopup.set_input_as_handled()` 只挡事件传播，拦不住 `Input.is_action_just_pressed()`
  ——于是"推进对白的那一下空格"会顺手开一场打卡，打卡那边的 `setup()` 把郑铎正在播的
  那一轮顶掉，郑铎的协程就永远等不到信号。修法是 `DialoguePopup._chain_open`：新一轮
  `setup()` 发现上一轮没收尾，主动发一个 `was_stolen` 把旧等待者放出去。
  真正致命的是后果不对称：`_villain_playing` 只挡 `_can_open_shop`，而 `_physics_process`
  那个早退列表里**没有**它，所以 `_nearby_shop_idx` 照算、提示圈照画。玩家看到的是
  "圈在那儿、怎么按都没反应"，唯一的解法是重开游戏——而且**控制台一行红字都没有**。
  所以任何提前 `return` 的分支都必须先清自己的闩锁。回归验证：`verify_interact_latch.gd`。

- **顶栏 HBox 里任何一个 Label 改字都会把整排标签横向推走**：
  HBox 按子节点的最小宽度排布，`_lvbi_label` 的 text 从"旅币 120"变成"+20 旅币"
  时宽度一变，心神和"下一处"整排横着跳一下——玩家正在读"下一处 358m"的时候
  被推走。所以入账提示走独立的 `_lvbi_toast`（挂在 HUD3D 上、绝对定位、不进
  HBox），余额标签一个字都不动。别图省事把它改回去。回归验证：`verify_mood_mask.gd`
  第 7 节直接量三个标签的 `get_global_rect().position.x`。

- **"下一处在哪"现在有三个地方在说，判据必须逐字一致**：
  顶栏 `HUD3D._next_fragment_target()`、小地图 `MiniMap._next_frag_idx()`、
  屏幕提示圈 `CheckInPrompt._label()`。三个都是"最近的、还没收的碎片站"。
  任何一处漂移（比如抄成"第一个未收站"，或拿 `station_has_fragment()` 静态属性
  当前者），玩家就会看到顶栏报 A、小地图亮 B、脚下圈亮 C——三处都看着像真的，
  没有任何一处会告诉他错了。改其中一处必须同步另两处，跑 `verify_minimap.gd`
  （沿途逐点核对）与 `verify_interact_latch.gd` 第 4 节。

- **`FarRidge` 的空气透视已经烘在顶点色里，场景雾不能再叠一遍**：
  `LAYERS` 里的颜色是照着最终观感调的，`fog_density=0.0003` 再洗一次就是
  同一份雾算两次——1900m 那层透射率只剩 0.566，三层因此全线偏白、没有纵深，
  近层和中层明度几乎一样，远景塌成一条带子。看着像"AGX 把中间调提亮了"，
  根角却在雾被算了两次。所以山脊材质必须 `disable_fog = true`。
  代价是山脚会和被雾洗过的地形之间露接缝，靠 `foot = col.darkened(0.30)` 盖住，
  改完只能靠 `lookdev_horizon.gd` 看图确认。回归验证：`verify_far_ridge.gd`。

- **`station_has_fragment(i)` 不是"玩家还没收过"**：它是站的静态属性（16 站里固定 5 站），
  玩家进度在 `GameManager.is_collected(i)`。拿前者当前者用，后果是两套 UI 互相打脸：
  顶栏的"下一处"按 `is_collected` 算、第一次到访后就把这站摘掉了，而世界里的提示圈
  按 `is_station_exhausted`（`MAX_VISITS_PER_STATION = 3`）算、还亮着 2 次；玩家按空格
  还会被拖回整段对白 + 小游戏，并再听一遍"获得碎片：云"。回访现在走 `is_first_visit`，
  提示文案也分开（`desktop_checkin_prompt` vs `desktop_revisit_prompt`）。
  回归验证：`verify_interact_latch.gd` 第 4 节。
- **headless 测不出小游戏的按键**：`--headless` 用 dummy display server，不做真焦点路由，小游戏收不到 `_gui_input`，跑出来的 PASS 是假的。`verify_mini_game_keys.gd` / `verify_bamboo_done.gd` 必须带窗口跑。另外用它注入按键时只用 `Input.parse_input_event()`，不要再叠 `root.push_input()`——parse 自己已经投递进 GUI 了，两条路都走会让一次按键被 `_gui_input` 收到两遍。
- **带窗口跑不等于 60 FPS**：这台机器窗口模式下能跑到 280+ FPS。验证脚本里凡是拿"帧数 ÷ 60"当秒数的断言都是错的（1.6 秒会算成 7 秒），一律用 `Time.get_ticks_msec()` 比墙钟。同理 `--quit-after` 要按墙钟折算，给小了会在中途被掐掉、只剩一串 warning 看着像通过。
- **小游戏收尾要给玩家一屏确认**：砍完最后一根就 `_on_mini_game_done(SUCCESS) + queue_free()`，遮罩同一帧消失，玩家分不清是砍赢了还是被踢出去，报上来的现象就是"按空格退出游戏"。要有成功画面 + 停留（`MiniGameBamboo.SUCCESS_HOLD_SEC`），停留期间狂按按键也不能提前结算。回归验证：`verify_bamboo_done.gd`。

- **子节点永远画在父节点的 `_draw()` 之上**：`GiftBox` 原来在场景里放了一个全屏 `ColorRect` 当底色，而它自己的 `_draw()`（礼物盒 + 路网底纹）被那张 ColorRect 全盖住了，标题页一直是一块纯黑，"按开始"时那套缩放淡出动画其实谁也看不见——图看起来"代码里有、画面上没有"。要在 Control 自己身上画东西当背景，背景也得由它自己画，别指望子节点能待在它下面。

- **`ProceduralSkyMaterial` 在 4.6 上没有 `sun_energy` / `sun_latitude` / `sun_longitude` / `sun_angle_min`**：`World3D.tscn` 里那份**旧的** `ProceduralSky` 资源还带着这几个键，把它们照抄进脚本会抛 `Invalid assignment`。更要命的是这行抛在 `--script` 的 SceneTree 流程里，`quit()` 永远走不到，定妆照脚本会一路挂到超时、只吐一行红字。太阳位置和强度归 `DirectionalLight3D` 管，天空这边不用设。

- **新的 `class_name` 要先过一次编辑器导入**：`godot --headless --editor --quit-after 60` 才会写 `.godot/global_script_class_cache.cfg`。在跑之前别的脚本按类名引它会报 `Identifier not declared in the current scope`——而 `check_all_scripts.gd` 会把它算成 FAIL，看着像真编译错误。

- **AGX 会把中间调显著提亮并去饱和**：给 unshaded 材质 / 顶点色填色时别照着"看起来该是什么颜色"填。`FarRidge` 的远山第一版按 (0.42,0.53,0.48) 这种"深青灰"填，三层渲出来全是一线白、完全没有纵深；反着调到 0.13~0.52 那一档才出得来空气透视。改颜色必须 `lookdev_horizon.gd` 看图，不能靠数字判断。

- **别拿合成器的 `damping` 参数的字面意思去写 Karplus-Strong**：延迟线每走一圈才乘一次增益，一圈是 `1/freq` 秒，330Hz 上是 294 圈/秒。`damping = 0.5` 意味着每 3.4ms 掉一半增益，音 50ms 就没了。调高到 0.99 让它响满一秒半之后，梳状响应的各泛音回路增益几乎一样高，谱峰会随机落到 1/2/3 次泛音上——实测四个琴音里有一个跑到 2 次泛音。要"基音最强"就用加法合成（泛音列 1/n^1.5 + 拨弦点陷波）。
- **失败也要给一屏，并且失败后驿站必须还能再玩**：5 个小游戏失败时都是 `_on_mini_game_done(CANCELLED) + queue_free()` 同帧收工，遮罩一没了玩家就被扔回 3D 世界。收尾面板统一在 `World3D._show_failed_panel()` 补，别在 5 个小游戏里各写一遍。另外"必须骑开才允许再打卡"这道门要用**闩锁**（`_recheck_armed`）而不是每帧比距离：折回同一个点距离又变回 0，驿站会永久卡死。回归验证：`verify_mini_game_fail.gd`。
- **fragment 名字要中英文都认**：`_station_fragment()` 在英文界面下返回 `fragment_en`，凡是拿它去查中文常量表的地方（如 `_fragment_slot_idx()`）都要一并认英文，否则英文界面每张碎片都收不到飞行动画。
- **小游戏超时别用帧数计**：`_run_mini_game` 旧版 `for i in range(600)` 在 60FPS 下只有 10 秒，而竹子小游戏满负荷要 ~8.8 秒（0.8s 引导 + 5×(1.2s 窗口 + 0.4s 间隔)），余量只有 1.2 秒。已改为按墙钟的 `MINI_GAME_TIMEOUT_SEC`。
- **`--script` 模式下的 class_name 类型注解会触发编译期拉依赖**：
  `var rd: RoadData = RoadData.new()` 会在编译期解析 `RoadData` 类名 →
  加载 `road_data.gd` → 里面引用了 `Localization` autoload。headless
  `--script` 模式下虽然 `project.godot` 里注册了 autoload，但 GDScript
  analyzer 对 autoload 的解析不可靠，直接报
  `Identifier not found: Localization`，然后 SceneTree 卡在等待状态、
  脚本永不执行、进程永不退出（表现是脚本运行 30s+ 无任何输出）。
  绕法：用运行时 `load(...).new()` 而不用类型注解——
  `var s = load("res://scripts/road_data.gd"); var rd = s.new(); var a = rd.get("stations")`。
  没有注解就不做编译期解析，autoload 引用只在运行时才会被求值。
  诊断办法：`--check-only --script tools/foo.gd` 会打印所有编译错误，
  包括"依赖脚本编译失败"，比 `--script` 直接跑（只静默挂死）好得多。
  回归验证：`verify_stations.gd` 用了这个模式加载 RoadData。

- **GLB 的 `baseColorFactor` 到 Godot 的 `albedo_color` 是过 `linear_to_srgb` 的**：
  glTF 里写 0.14，Godot 侧 `mat.albedo_color` 读出来是 0.41（`linear_to_srgb(0.14)=0.41`
  逐通道都对得上）。所以运行时改色必须写 `c.linear_to_srgb()`。写成 `srgb_to_linear()`
  方向就反了：填 0.175 会得到 0.026，比同模型的墙暗 30 倍——驿站屋顶的背光面直接
  渲成纯黑，整栋楼少一半轮廓，比原来那片冷灰更糟。回归验证：
  `verify_station_roof.gd`（里面有一条「屋顶/墙」亮度比专门拦这个）。

- **GLB 材质要 duplicate 才能改**：`_tint_station_roofs()` 里直接写
  `mat.albedo_color` 会改掉导入缓存里那个共享资源，别的站跟着一起变。必须
  `mat.duplicate()` 再 `set_surface_override_material()`。

- **驿站屋顶的色是运行时定的，不在 GLB 里**：7 个手工模型的屋顶材质名统一是
  `<站名>_roof` / `<站名>_roof_2`，`World3D._tint_station_roofs()` 按后缀认，
  色值在 `World3D.STATION_ROOF_TINT`（sRGB 口径，和当初 Blender 里填的一致）。
  贴图模型 `station_0..4` 整个模型只有一个烘了 basecolor 的材质，匹配不上，
  天然不受影响——**别去给它们乘色**，那 5 个模型的差别是照片。

- **从 SubViewport 回读画面必须先等两帧**：`set_back_text()` 只发 `queue_redraw()`，
  SubViewport 要到下一帧才真的画出来。在 `_process` 里当场 `get_image()` 拿到的是
  改之前那张，而且因为那一次已经"刷新过"了，dirty 被清掉后再没人补——缩略图会
  永远停在没字的卡上（`_on_back_confirmed()` 末尾等两帧是同一个道理）。
  `EndCard._grab_back_thumb()` 就是照这个写的。

- **dummy renderer 下 `SubViewport.get_texture()` 返回 null**：链上去 `get_image()`
  会抛 `Parameter "t" is null`，把整个函数从中间掐断，后面的清理代码跑不到。
  判 texture 而不是判 image。

- **程序化赋 `TextEdit.text` 不发 `text_changed`**：要模拟"玩家敲了一个键"，
  得自己 `emit()`。`EndCard._on_back_confirmed()` 也正因为这个才在确认时回头
  再读一次 TextEdit。

- **小游戏那一屏的背板和藏顶栏是 `World3D` 的一对方法**：
  `_push_mini_game_chrome()` / `_pop_mini_game_chrome()`。`lookdev_journey.gd`
  绕过 `_run_mini_game()` 直接把小游戏塞进 layer，所以必须调这两个方法，
  别在测试里重演一遍——重演的话定妆照拍到的是旧版，看图的人以为游戏本来就这样。

- **「下一处」的方向箭头是相对车头的，不是罗盘北**：8 字环自闭合，两个方向都能到
  全部 5 座碎片驿站，只给距离不给方向的话，骑反了距离会一直不变，玩家在交叉点上
  完全看不出来。约定 `a(v) = atan2(v.x, -v.z)`，正前方（-Z）是 0、正右方（+X）是
  +π/2，相减取负向即"目标相对车头偏了几度"，顺时针分成 8 档。
  `lookdev_journey.gd` 的 `_check_next_target_arrow()` 把真玩家掰成正对/背对/正右
  三种姿态读真 HUD 标签，只测 `HUD3D._arrow_glyph()` 那个 static 等于拿自己测自己。

- **新 GLB 必须先在 Godot 编辑器里跑一次导入**：光把 .glb 放进
  `assets/models/` 不够，headless 下 `load("res://...glb")` 会报
  `No loader found for resource`——因为 `.import` sidecar 还没生成。
  跑一次 `"$GODOT" --headless --editor --quit-after 30` 会扫全工程
  生成所有缺的 `.import` 文件，之后 headless `load()` 才认得。
  新增资产记得跑这一步，否则 `verify_stations.gd` 的 GLB 存在性检查
  会 FAIL（但 `ResourceLoader.exists()` 只看文件、不看导入状态）。

- **`road_data.gd` 里 11 座非碎片驿站的 `text` 曾经是死数据**：
  那 11 行字一直写在 stations 数组里，但唯一的读者是打卡弹窗，而非碎片站
  根本不能打卡——16 站里有 11 站的文案玩家一次也读不到。现在由
  `World3D` 在**进圈那一帧**（`_pass_inside` 边沿，不是每帧判距离）把它
  交给 `HUD3D.show_pass_line()` 浮出来。停在圈里不动不能每秒重弹一次，
  而 `lookdev_journey.gd` 的 `05b_pass` 会同时断言"浮出来了"和"3.2 秒后收走了"。
  另注：底板必须挂在 `CenterContainer` 上而不是 Label 身上——铺满屏宽的 Label
  套一个 `StyleBoxFlat` 会铺满全屏，看着像顶栏多了一行暗带。

- **五个小游戏的取消按钮是 `_draw()` 画的假按钮，键盘点不到**：
  所以每个都必须另外接 ESC。而 ESC 该插在哪一步**三个各不相同**：
  琴要插在示范阶段的早退 `return` 之前（不然示范那 20s 完全出不去），
  竹要插在 1.6s 成功停留之后（那一下是给玩家的确认，不许跳过），
  茶最糟——原来既放弃不了又失败不了（长按 3 秒必然成功），键盘玩家唯一的
  出路是干等 `World3D` 的 30s 超时。回归验证：`verify_mini_game.gd` 第 5 节。

- **给 Label 设 `StyleBoxFlat` 的 `normal` 覆盖会铺满它的整个 rect**：
  拉满屏宽的 Label 配上它就成了一条横贯全屏的暗带。要让底板只包住文字，
  得套一层 `CenterContainer`（`PanelContainer` → `Label`），
  并把淡入淡出挂在 **holder** 上而不是 Label 上——两处都 modulate 的话
  相乘成 0，文字直接看不见，而这条没有任何断言能拦住，只能看图。

- **「抉择有后果」这件事要落在玩家真正带走的那张 PNG 上**：
  明信片正面才是产物（`_postcard_export` 才是导出的那张），背面那句预填
  文案玩家随时能改。所以 `Postcard.seal_broken()` 让【放手】把封口的蜡
  掰开——那是正面上 keep / break 唯一的差别，`verify_postcard_ending.gd`
  第 4/5/7 节分别断言显示卡、背面卡、导出卡三处一致。

- **「这一趟还剩什么」的回执只能现算，不能另存快照**：
  `EndCard._on_restart_pressed()` 走的是 `go_to_gift_box()` → `reset()`，
  而 `reset()` 把 `seen_stations` / `collected` / `earned_tags` / `ending_id`
  一起清掉。回执必须赶在那之前弹，一存档就再也答不出"这一趟漏了什么"了。
  还有：回执**永远有内容**——keep/break 一次只选一个、存档又随重开清零，
  所以另一边的结局必然空着。别写"全都走到了"那种分支去糊住这个空。

- **测试里拿 key 里的 `%s` 去 `contains()` 渲染后的句子，永远匹配不上**：
  写断言要拿**渲染后的整句**去比（`_loc.t("recap_mini_lost") % _join(names)`
  然后 `lines.has(...)`），别去找 key 本身。同理，中间那几行为了改状态做的
  临时摆弄必须**完整还原**（五个碎片驿站全摆回去，不是只还原改过的那一个），
  否则后面量到的数和开头那份基线对不上，报出来的失败跟被测的代码无关。