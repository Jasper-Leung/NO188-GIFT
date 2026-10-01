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
  verify_mini_game.gd    5 个小游戏注入链路（size/焦点/结果码契约 + **五个都接 ESC 取消**
						+ **屏幕上的字不许和代码互相拆台**：先量机制（茶松手退零不判失败、
						竹引导期提前按算数、禽的读数真的在变），文案只拿来对答案
						+ **云影台的完成度必须真的来自"描过"**：同一段上晃 60 次只记 13%、
						不许越过 75% 及格线，而顺次描完 / 一甩到底都得能描完
						+ **禽的四只鸟是四个形状**：BIRD_SHAPES 的几何两两不同、
						且每行多边形都能展开成有限坐标）
  verify_interact_latch.gd 交互闩锁 / 对白抢占回归（郑铎在播时按空格不许开打卡、
						setup() 顶掉一轮对白必须放出旧等待者、被顶掉的郑铎戏自己清
						_villain_playing、回访不再重播小游戏/谎报碎片、
						**反派戏期间脚下的圈不许还在推销打卡**、铺子仍能开；
						第 6 节靠注入真空格驱动对白推进，走 `Node._input()`，带不带 --headless 都跑得过）
  verify_bamboo_world.gd 真实 World3D 端到端：打卡→小游戏→空格不泄漏成驿站交互
  verify_mini_game_keys.gd 竹/琴/茶/禽/云在"只有 physical_keycode"的键盘事件下仍可玩（**不能加 --headless**）
  verify_bamboo_done.gd 竹子砍完第 5 根后有成功画面停留、不会凭空消失（**不能加 --headless**）
  verify_mini_game_fail.gd 小游戏失败有交代 + 失败后驿站还能再玩（headless 可跑）
  verify_checkin_all5.gd  5 个碎片驿站完整成功链路 + 收尾后重打卡（**不能加 --headless**）
  verify_panel_keyboard.gd 纯键盘从冷启动走到第一次踩上踏板：操作说明有焦点、
						空格/回车收得了面板（**两种按键事件形状各测一遍**）、
						序章推得完、驿铺买得到东西且焦点不会落在已买断的按钮上
						（**不能加 --headless**：headless 不做焦点路由）
  verify_stations.gd      16 驿站 → GLB 配置一致性（model_idx 映射、GLB 存在、
						名字/color/event 完整、碎片顺序、无占位路标名）
  verify_story.gd         故事层三副本对拍：Localization.STRINGS 中英 key 集合逐字相同
						（不许只在一侧存在 / 不许空串 / 不许中英同字）、反派台词 key 中英都齐、
						五座碎片站身份与顺序、`Postcard.FRAGMENT_COLS` 与
						`FragmentBar.FRAGMENT_COLORS` 逐值相同，
						**以及 `3D_RIDE_DESIGN.md` 不许说谎**（站名/乐事逐字、km 不许说成
						玩家可见单位、相机 `target_pos` 那一行逐字）
  verify_station_roof.gd  驿站屋顶暖中性色回归（7 个手工模型命中 <站名>_roof 后缀、
						材质已 duplicate、屋顶确实比墙暗且没暗成洞、贴图模型 station_0..4
						结构上不被动、导入缓存没被写脏）
  verify_mood_mask.gd     心神遮罩 + 顶部经济栏回归（遮罩层级/两档透明度、骑行档
						永远可读、遮罩只随心神不走灯笼、系数传到草皮与行道树、
						入账 toast 不重排顶栏、叙事脉冲冲上/退回）
  verify_minimap.gd       小地图碎片站回归（**沿途 321 个采样点上小地图高亮的
						必须就是顶栏「下一处」报的那颗**；判据统一走
						GameManager.fragment_station_needs_visit()、**收过 ≠ 不用再去**
						（还欠到访就仍然指人）、五座全刷满才真的不指人、
						普通驿站不冒充目标、顶栏那份 MAX_VISITS 副本不许漂；
						第 9/10 节走真实 check_in()：**集齐是中局不是终局**，
						集齐后整圈三处指示器仍一致且顶栏不空、站到每座碎片站前
						顶栏与脚下的圈报同一个"还差 N 次"、刷满了才 _all_done）
  verify_far_ridge.gd     远景山线材质回归（三层都 disable_fog、半径都在地形之外、
						颜色按距离递淡）—— 颜色本身只有 lookdev_horizon.gd 能判
  lookdev_horizon.gd      远景山线四张定妆照：路面视角 / 地形高点 / 逆光 / 高空
						（**不能加 --headless**、**不能加 --quit-after**）
  verify_day_cycle.gd     昼夜切换回归（第三圈门槛、太阳**方向**跟着降、
						ProceduralSky 天色真的走了、白昼档没被顺手改掉、
						dusk_began 只发一次；顺带断言"场景自带的天空是空的"）
  lookdev_journey.gd      玩家视角 21 屏流程实拍（标题→操作说明→序章→骑行→打卡提示
						→**贴脸 1.2m（提示文字最容易掉出屏外）**→**回访「再访 · 还差 N 次」**
						→**路过风景驿浮的那一句**→驿站对白→5 个小游戏→驿铺→
						**正午/黄昏同机位两张**→集齐
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
  web_smoke.gd + .tscn     **Web 导出实测用，不是产品的一部分**。设成主场景导出 Web，
						在浏览器里打开两遍：第一遍走真实 `check_in()` 写盘 + 导 PNG，
						第二遍读回。量的是三件桌面回归永远量不到的事——
						IDBFS 落盘后**重开页面**还读不读得回、`JavaScriptBridge`
						导 PNG 那条 Web 专用分支下载得到下载不到、控制台有没有 Web 报错。
						跑完记得把主场景改回 `res://scenes/GiftBox.tscn`
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

# 交互闩锁 / 对白抢占回归（约 30 秒；自己清理 user:// 存档）
# 改 DialoguePopup.setup()、World3D._can_start_check_in()/_do_check_in()/_play_villain_scene()
# 或 CheckInPrompt._label()/_prompt_target() 之后跑这个
# 第 6 节靠注入真空格驱动对白推进，走的是 Node._input()，所以带不带 --headless 都跑得过
"$GODOT" --headless --path . --script tools/verify_interact_latch.gd --quit-after 40000

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

# 纯键盘通路：操作说明有焦点 → 空格收面板 → 序章推完 → 驿铺买得到东西
# 两种按键事件形状各测一遍（只带 physical_keycode = Web 的形状 / 完整 = 桌面）
# 同样不能加 --headless（headless 的 dummy display server 不做焦点路由）
"$GODOT" --path . --script tools/verify_panel_keyboard.gd --quit-after 60000

# 16 驿站 → GLB 配置一致性（model_idx 映射、GLB 文件存在、名字/color/event 完整、碎片顺序、无占位路标名）
"$GODOT" --headless --path . --script tools/verify_stations.gd

# 故事层一致性：中英 key 对齐 + 反派台词 key + 碎片身份 + 文档不许说谎（秒级）
"$GODOT" --headless --path . --script tools/verify_story.gd

# 驿站屋顶暖中性色（材质按后缀命中、必须 duplicate、屋顶 vs 墙的亮度比、贴图模型不受影响）
"$GODOT" --headless --path . --script tools/verify_station_roof.gd

# 心神遮罩 + 顶部经济栏（两档透明度、骑行档可读上限、toast 不重排顶栏、叙事脉冲）
# 注意 --quit-after 单位是帧不是秒，本机 280+FPS，给小了会把脚本掐死在场景加载处
"$GODOT" --headless --path . --script tools/verify_mood_mask.gd --quit-after 30000

# 小地图未收碎片站（沿途逐点核对小地图 == 顶栏「下一处」）
"$GODOT" --headless --path . --script tools/verify_minimap.gd --quit-after 30000

# 远景山线材质（三层都关了雾、半径在地形之外、颜色按距离递淡）
"$GODOT" --headless --path . --script tools/verify_far_ridge.gd

# 昼夜切换（骑满两圈之后天色走到黄昏；含"场景自带的天空是空的"这条前提断言）
"$GODOT" --headless --path . --script tools/verify_day_cycle.gd --quit-after 30000

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
- 往 `Localization.gd` 加/删 key、改中英任何一侧的文案、改 `road_data.stations` 的站名或
  `event`、动 `Postcard.FRAGMENT_COLS` / `FragmentBar.FRAGMENT_COLORS` / `World3D` 的反派台词前
  跑 `verify_story.gd`。它守的是**三处互相对不上的副本**：`Localization.STRINGS`（玩家读到的字）、
  `road_data` / `Postcard`（碎片身份）、`3D_RIDE_DESIGN.md`（下一个人的唯一入口）。
  改 `3D_RIDE_DESIGN.md` 本身也要跑——这一族里只有它会把文档钉在代码上，
  而文档错了没有任何运行时后果，只有下一趟踩
- 修改 `scripts/road_data.gd` 的 stations 数组（名字 / model_idx / fragment）前先在 headless 跑 `verify_stations.gd` + `verify_8_shape.gd`（stations 数组同时是 lemniscate 驿站映射）
- 修改 `scripts/VegBuilder.gd` 前先跑 `verify_vegetation.gd` + `verify_pavilion_bushes.gd` + `verify_vegetation_grounding.gd`
- 修改 `scripts/GrassScatter.gd` 前先跑 `verify_grass_scatter.gd`
- 修改 `scripts/TreeScatter.gd` 前先跑 `verify_tree_scatter.gd`；改间距/离路/淡出参数后还要跑 `lookdev_trees.gd` 看图（`CELL` 必须和 `GrassScatter.CELL` 一致，两套流式共用同一张格子）
- 修改 `assets/shaders/grass.gdshader` 前先跑 `lookdev_grass.gd` 看图（`--headless` 的 dummy renderer **不编译着色器**，语法错在无头下会静默通过）
- 修改 `scripts/mini_games/*.gd` / 打卡流程前先跑 `verify_mini_game.gd` + `verify_bamboo_world.gd` + `verify_mini_game_keys.gd` + `verify_bamboo_done.gd` + `verify_mini_game_fail.gd` + `verify_checkin_all5.gd`
- 改 `OnboardingGuide` 的 `_build_ui()`（尤其焦点）/ `ShopPanel._button()` / `_grab_first_focus()` / `_refresh()` / `GameManager._bind_ui_accept_to_physical()`，或**任何一个 Button 的键盘可达性**前跑 `verify_panel_keyboard.gd`（**不能加 --headless**）。它量的是"冷启动 → 收掉操作说明 → 推完序章 → 驿铺买成一件"，不是量某一个函数；两种按键事件形状各测一遍，只测一种的话另一半坏了照样全绿
- 改 `MiniGameCloud.PATH_POINTS` / `_update_draw()` / `_next_seg` 前跑 `verify_mini_game.gd` 第 7 节（**完成度只能来自"描过"**：原地晃 60 次只记一段的 13%，够不着 75% 的及格线；顺次描完和一甩到底都得能描完——甩过去的那几段要一起记上，否则光标卡死在没描到的那段上，后面整条云再也描不完）。顺手也跑 `verify_mini_game_keys.gd` 的云那一局：它当初的绿**是靠这个漏洞**刷出来的，修好漏洞后如果它变红，先看它是不是还踩在原地
- 改 `MiniGameCloud._gui_input_key()` 的挪光标 / `KEY_STEP` 前跑 `verify_mini_game_keys.gd`（到达判据必须 ≥ `KEY_STEP`，否则 12px 的整步走会在目标两侧横跳、`_cloud_t` 永远不前进）
- 改 `MiniGameBird.BIRD_SHAPES` / `_draw_bird_silhouette()` / `MiniGameZither.SHOW_DELAY` / `_advance_show()` 前跑 `verify_mini_game.gd` 第 6b/6e/6f 节 + `lookdev_journey.gd` 看那两张 `minigame_禽` / `minigame_琴`（**`--headless` 根本不调 `_draw`**，几何里写错一个构造在无头下永远是绿的，必须靠带窗口的回归和图）；禽的四只鸟要**形状**不同，不能是同一个形状刷四种颜色，画法在 `BIRD_SHAPES` 表里、回归也读同一张表
- 改 `scripts/AudioManager.gd` 或 `scripts/mini_games/*.gd` 里的发声前先跑 `check_all_scripts.gd` + 上面那 6 条；新加了 sfx 还要跑一次 `--headless --editor --quit-after 60` 生成 `.import`
- 改任何一屏玩家可见的东西（HUD / 标题页 / 新手引导 / 商店 / 驿铺 / 明信片 / 结算）前跑 `lookdev_journey.gd` 看图
- 改 `EndCard._export_two_images_web()` / `GameManager.SAVE_PATH` / `_save_game()` / `_load_save()`
  或任何碰 `user://` 的地方后，把 `tools/web_smoke.tscn` 设成主场景、
  `--export-release "Web" ./build_web/188.html`，在浏览器里**开两遍**看
  `result=ROUNDTRIP_OK` 与两张 PNG 落盘，跑完把主场景改回去。
  桌面回归永远量不到这一层：`user://` 在 Web 上是 IDBFS，而落盘是异步的，
  刷新页面会走 beforeunload 的同步路径把问题盖掉
- 改 `scripts/FarRidge.gd` 的层数 / 半径 / 颜色前跑 `lookdev_horizon.gd` 看图（AGX 会把中间调提亮去饱和，填色要反着调，见已知陷阱）
- 改顶栏 / `scripts/shop_data.gd` 的解锁门 / `World3D.VILLAIN_SCENES` 的触发条件前跑 `verify_economy.gd`（含「里程不许出现在任何玩家可见文案里」扫描）+ `verify_shop_panel.gd` + `verify_shop_world.gd` + `lookdev_journey.gd` 看顶栏
- 改 `HUD3D._next_fragment_target()` / `_arrow_glyph()` 前跑 `lookdev_journey.gd`（它带一条几何断言：车头正对 → ↑、背对 → ↓、正右方 → →，只测 static 那个函数等于拿自己测自己）；方位用 `a(v) = atan2(v.x, -v.z)`，8 字环自闭合、两个方向都到得了全部 5 站，箭头必须真的随车头转
- 改 `HUD3D.MOOD_REST_SCALE` / `set_mood_pulse()` / `_setup_mood_mask()` 或 `World3D` 里推 `set_mood_pulse` 的那一行前跑 `verify_mood_mask.gd`（骑行档必须**永远**低于 0.20 可读上限，叙事档才允许冲到 `MOOD_MASK_MAX`）
- 改 `MiniMap._next_frag_idx()` / 未收碎片站的画法前跑 `verify_minimap.gd`（小地图高亮的那颗必须就是顶栏"下一处"报的那颗；这是继 `CheckInPrompt` 之后第三个会说"下一处在哪"的地方，判据一漂移玩家就骑错且无从察觉）
- 改 `scripts/DayCycle.gd` 的任何一档颜色 / 太阳角度 / `FarRidge.set_tint()` 前跑 `verify_day_cycle.gd`（量的是数字）+ `lookdev_journey.gd` 看 `12b_day_正午` 与 `12c_dusk_黄昏` **那两张同机位的 A/B**（量的是观感）。少一张就没法判断"天到底变了没有"——两处只查一个都曾经全部通过而画面纹丝不动
- 改 `GameManager.fragment_station_needs_visit()` / `all_fragments_maxed()` / `fragment_slot_visits_left()` / `MAX_VISITS_PER_STATION` / `HUD3D._update_next_label()` / `FragmentBar._draw_visit_pips()` / `CheckInPrompt._label()` 的回访分支前跑 `verify_minimap.gd` + `verify_interact_latch.gd` 第 4 节 + `lookdev_journey.gd` 看 `05d_revisit_回访提示`（完满是全游戏最强的重玩钩子，三处「还差 N 次」必须同数；任一处退回 `is_collected` 就会把已收的站从导航上摘掉）
- 改 `FarRidge.LAYERS` / `_build_layer()` 的材质前跑 `verify_far_ridge.gd` + `lookdev_horizon.gd` 看图（`disable_fog` 被谁删掉的话三层会塌成一条没有纵深的白带，标志位那关拦得住，颜色那关只有看图）
- 改顶栏的经济标签（`_lvbi_label` / `_lvbi_toast` / `_setup_economy_labels`）前跑 `verify_mood_mask.gd` 第 7 节（它断言入账时余额/心神/"下一处"三个标签的横坐标一个像素都不许动）
- 改 `World3D._push_mini_game_chrome()` / `_pop_mini_game_chrome()` 前跑 `lookdev_journey.gd` 看 5 张 `minigame_*.png`（遮罩不透明 + 运行时藏 HUD，靠的是这对成对方法，漏掉一头就有一屏写着"两层同时存在"）
- 改 `DialoguePopup.setup()` / `World3D._can_start_check_in()` / `_do_check_in()` / `_play_villain_scene()` / `CheckInPrompt._label()` 前跑 `verify_interact_latch.gd`（这五处任何一个漏了都能把游戏变成"提示圈照画、按键全死、只能重开"）
- 改 `World3D._physics_process()` 里那张"这些状态下一律不算 `_nearby_*`"的早退单、或 `CheckInPrompt._prompt_target()` / `_interact_blocked_reason()` 前跑 `verify_interact_latch.gd` 第 6 节。这张单子上每多一个状态，那个状态下脚下的圈就该同时收掉——`CheckInPrompt._prompt_target()` 只读 `_nearby_*`，它不知道 `_villain_playing`，单子漏一格就是"圈还在推销一个按不出来的交互"。注意 `lookdev_journey.gd` 在这里帮不上：它开头就设 `_gm.seen_villain = 3` 把三场反派戏全跳过去了，所以这一段没有任何定妆照可看，只能量数字）
- 改 `CheckInPrompt._label_pos()` / `_draw()` 里的底板前跑 `verify_interact_latch.gd` 第 5 节 + `lookdev_journey.gd` 看 `05c_prompt_贴脸`（贴着站停下时站点的投影已经压到屏底，提示文字是往圈上方翻的，底下又是全屏最忙的一块——数字对了图上仍可能读不出来）
- 改 `Postcard.FRAGMENT_COLS` / `_draw_fragment_icon()` / `VARIANT_LAYOUTS` 前跑 `verify_postcard_ending.gd` 第 3b 节 + `lookdev_postcard.gd` 看明信片正面（颜色/图标/标签三者同序，且 `Postcard.FRAGMENT_COLS` 与 `FragmentBar.FRAGMENT_COLORS` 逐值相同；缩略图和存档 PNG 是同一份，错了就是玩家带走的那张错了）
- 改打卡流程的"这站还欠我一块碎片吗"判据前跑 `verify_interact_latch.gd` 第 4 节 + `verify_checkin_all5.gd`（`station_has_fragment(i)` 是站的静态属性、`is_collected(i)` 才是玩家进度；拿前者当前者会让回访重播小游戏并谎报"获得碎片"，而 HUD 的"下一处"早就把这站摘掉了，两边对不上）
- 改 `World3D._tint_station_roofs()` / `STATION_ROOF_TINT` 前跑 `verify_station_roof.gd` + `lookdev_journey.gd` 看 `04_ride`（填色要过 `linear_to_srgb`，写错方向屋顶比墙暗 30 倍，数字还是"暖的"，只有比值看得出来）
- 改 `GameManager.check_in()` 里那两个闩锁 / `all_fragments_maxed()` / `_load_save()` 末尾的补齐 / `World3D._on_all_collected()` / `_on_all_maxed()` / `_spawn_synthesis_animation()` / `PostcardVariant.compute_variant()` 前跑 `verify_minimap.gd` 第 9/10 节 + `verify_postcard_ending.gd` §3b + `verify_interact_latch.gd` 第 4 节 + `verify_checkin_all5.gd`（"集齐"与"走完"是两个时刻，判据只能有一个）
- 改 `Localization.gd` 里 `revisit_note` / `touch_revisit_button` / `collecting_message` / `revisit_available` / `synthesis_done_message` / `finish_run` 前跑 `verify_economy.gd`（文案扫描）+ `verify_interact_latch.gd` 第 4 节 + `lookdev_journey.gd` 看 `05d_revisit_回访提示`。前三句曾经一起写着"再歇一脚"——集齐之后唯一还在对玩家说的话是劝他别再跑了
- 改 `PausePanel.gd` / 暂停面板按钮 / `go_to_end_card()` 的触发条件前跑 `verify_minimap.gd` 第 8b 节（出口在不在、零碎片时在不在、收工时评级按走过的算）+ `verify_postcard_ending.gd`（EndCard 得接得住非完满档）
- 改 `EndCard._show_ending_choice()` / `_seed_back_text()` 前跑 `verify_postcard_ending.gd`（`keep`/`break` 的后果必须落在**正面**：留门=背面写上那句、放手=背面留白且封口的蜡掰开，两张卡片的正文必须**就是**真正会发生的那件事本身，不能另写一段描述——否则又变回"承诺一个差别、实际只改一句话"）
- 改 `EndCard._refresh_back_thumb()` / `_grab_back_thumb()` 前跑 `verify_postcard_ending.gd`（SubViewport 回读要等两帧；节流按累计 delta 掐，headless 跑两帧等不到 0.12s，测试里必须等墙钟）+ `lookdev_journey.gd` 看 `16_postcard_back`（要打完字再拍，只拍初始帧看不出缩略图跟不跟得上）
- 改 `EndCard._show_back_editor()` 的布局（输入框高度 / 按钮摆法 / `THUMB_BTN_*`）前跑 `verify_postcard_ending.gd` 第 3 节（量控件几何：两个按钮不叠、都在屏内、缩略图 ≥400px 宽且不遮按钮）+ `lookdev_journey.gd` 的 `16_postcard_back`——那一屏现在带**像素级**断言（暗像素占比 + 落在几条横带上 + 明暗跨度），因为尺寸对了不代表里面真有字，SubViewport 回读到空帧时预览就是一块纯色、尺寸一模一样
- 改 `EndCard._on_restart_pressed()` / `_recap_lines()` / `_recap_worth_showing()` 前跑 `verify_postcard_ending.gd` 第 8 节 + `lookdev_postcard.gd` 看 `12_回执` / `12b_recap_EN`（回执**每一条都要对着存档逐字核对**——编一条玩家没做过的事，第二趟发现根本没有，比不弹更伤；而 `go_to_gift_box()` 会 reset，所以回执只能赶在 reset 之前现算，不许另存快照）
- 改 `World3D` 里那段路过驿站的话（`STATION_PASS_RADIUS` / `_pass_inside` / `HUD3D.show_pass_line`）前跑 `lookdev_journey.gd` 看 `05b_pass`（16 站里有 11 座的 `text` 一直只写在 road_data 里没人读；边沿触发要靠 `_pass_inside`，只判距离会让玩家停在圈里每秒重弹一次）
- 改 `MiniGameTea` / `MiniGameZither` / `MiniGameBamboo` 等五个小游戏里的输入处理前跑 `verify_mini_game.gd` 第 5 节（五个都必须能用 ESC 取消 —— 取消按钮是 `_draw()` 画的假按钮，键盘点不到，茶最糟：既放弃不了又失败不了，键盘玩家唯一出路是干等 30s 超时）。注意 ESC 的插入位置各不相同：琴要放在示范阶段的早退之前、竹要放在 1.6s 成功停留之后（那一下不许跳）
- 改五个小游戏里的**提示文案**或 `MiniGameBird.SHOW_DURATION` / `countdown_fraction()` 前跑 `verify_mini_game.gd` 第 6 节（先量机制、再拿文案对答案）+ `lookdev_journey.gd` 看 5 张 `minigame_*.png`。这一节的判据是"字和代码不许互相拆台"，所以改文案时不能只改文案——先确认代码到底怎么做的

## 已知陷阱
- **「按钮能按」这件事有三道独立的门，缺一道键盘玩家就卡在那一屏**：一个
  Button 要能被键盘激活，得同时满足 ① 它 `focus_mode != FOCUS_NONE`；
  ② 视口里**确实有**焦点落在某个控件上（`Viewport` 只把按键投给 key focus 的
  控件，视口里一个焦点都没有时空格/回车谁也到不了，连把鼠标悬停上去也不行——
  实测不抓焦点时推 8 秒空格面板纹丝不动）；
  ③ 那个键能被 `ui_accept` 命中。`OnboardingGuide` 原来①过②不过（谁都没调
  `grab_focus()`，全工程只有它忘了：GiftBox 抓 `_start_btn`、EndCard 抓
  `_export_btn`），于是 `gui_get_focus_owner()` 一直是 `<null>`，
  而 `World3D._play_prologue()` 是 `await _onboarding.dismissed`——键盘玩家
  卡死在**第一屏**，连序章都没开始。`ShopPanel` 原来连①都不过
  （`_button()` 一律 `FOCUS_NONE`）：能开铺、能看价、能用 ESC 关，
  却一件也买不了，一块看得见（鼠标）摸不着（键盘）的经济系统。

- **③那条最反直觉：引擎内建的 `ui_accept` 是按 `keycode` 匹配的，而 Web 导出下
  `keycode` 可能填不上**。本项目 InputMap 当年全用 `physical_keycode`，
  正就是为了躲这个——于是同一个陷阱搬了个家：桌面端好好的，Web 上**全工程
  一个按钮都按不动**（实测：焦点确实落在「买」上，按空格 8 秒纹丝不动，
  `postcard_tier` 停在 0）。修法是 `GameManager._bind_ui_accept_to_physical()`
  给 `ui_accept` / `ui_select` 补一份 physical 绑定，**补在那唯一的出处**而不是
  给每个面板加兜底：一个键位表漏一处就是一处新的死路。凡是问"这个键在 Web 上
  认不认"，答案在 InputMap，不在某个 `_gui_input` 里。

- **焦点是**状态**，不是"控件被建出来了"**：买完之后焦点还留在刚刚买下的那个
  按钮上，而它已经 `disabled`——引擎不会因为 disabled 就把焦点踢走，于是玩家
  按第二下空格什么都不会发生，界面上也看不出区别（那件只是变灰了，而变灰正是
  "买到了"该有的反馈）。所以"焦点在某个按钮上"这条断言不够，得加一条
  "焦点不在一个已经买不了的按钮上"。反过来 `grab_focus()` 对 disabled 控件是
  空操作，所以找焦点时要**跳过**买不了的那些，否则又变成"视口里一个焦点都没有"。

- **`_gui_input` 收不到"没人抓焦点"时的按键，别把兜底写在那儿**：`Viewport`
  只把按键投给 key focus 的控件，于是一个没焦点的 Control 连空格都收不到。
  `_unhandled_input` 是 Node 级回调、不走 GUI 路由，才收得到——但它跟按钮走的
  是同一件事（`ui_accept`），两份机制只会有一个真的跑到，写两份只会让人
  以为有两道保险。

- **一条回归自己抛异常时，`--quit-after` 收掉进程的退出码是 0**：
  `verify_panel_keyboard.gd` 第一版在 `add_child()` 之后立刻解引用
  `_world._onboarding`（那是 `_ready()` 里挂的，此刻还不在），抛
  "Invalid access to property 'visible' on Nil" 把整个协程掐断，`quit()` 永远
  走不到——进程被 `--quit-after` 收掉时**退出码是 0**，一行断言都没打过的
  回归看着像跑通了。所以带超时的脚本要么在协程外也保证 `_report()` 被打到，
  要么就别指望退出码，**读输出里有没有那行汇总**。
- **屏幕上的字必须和代码真的那么干**：这一族 bug 每一处单独看都像对的。茶写
  「松开手指即失败」而代码只是把 `_hold_time` 清零；竹标题写「竹子倒下时按」而引导
  明写「现在就可以按」、代码也确实允许引导期提前按——**同一屏上两句话互相拆台**。
  玩家按了没事，于是判定"这游戏假"，而不是"这句写错了"。禽那个更隐蔽：倒计时画的是
  `max(1, int(_show_timer) + 1)`，而 `SHOW_DURATION = 0.8`，`int()` 之后恒为 0、
  `+1` 之后恒为 1——一个宣称自己在倒、其实钉死的数字。0.8 秒也撑不起秒级整数倒计时，
  现在画一条按真实剩余时间收缩的横带，读数抽成 `countdown_fraction()`。
  **`draw_*` 在 headless 下一笔都不落盘**，所以读数只要还是"画出来的"，任何断言都
  抓不到它钉死——必须抽成函数让测试量同一个值。回归验证：`verify_mini_game.gd` 第 6 节
  （量机制本身，文案只拿来对答案：机制变了而字没跟上，两边一定有一边红）。
  同族：虚构地名「十八驿」是旅店的名字，而顶栏写「已过 n/16 驿」——两个数字放在
  同一屏上，玩家只会对着算然后认定一个是 bug，所以 `back_keep` 里它得加引号、
  英文得带 "inn"，读起来像专名而不是序号。

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

- **`--headless` 根本不调 `Control._draw()`，所以画出来的东西既测不到、
  连写错了都不会炸**：`_draw` 里的 `draw_*` 一笔不落盘，所以"倒计时到底在不在动"
  这类断言必须先把读数抽成函数；而更狠的是**函数体本身也没被执行**——
  禽的剪影我把本地坐标写成了 `Vector2(p)`（GDScript 的 `Vector2` **没有**
  单参数构造，只有 `Vector2()` / `Vector2(from)` / `Vector2(x, y)`），
  无头回归全绿，`--headless --script tools/verify_mini_game.gd` 一路 OK，
  带窗口跑 `verify_mini_game_keys.gd` 才一进选项页就满屏
  `SCRIPT ERROR: Nonexistent 'Vector2' constructor`——而五局里唯独禽是在
  **第二屏**才画多边形，实机截图也未必当场看见。
  两条对策：把几何换算抽成不碰画笔的纯函数（`_poly` / `_oval`），
  回归**直接调它**；以及凡是改了 `_draw` 里的几何，一律补一条带窗口的回归。

- **一条回归在绿，可能是因为它自己踩在它要守的那个漏洞上**：`verify_mini_game_keys.gd`
  的云那一局一直绿着，可它的光标其实**卡死**了——判据写的是"离下一个轨迹点 6px 以内"
  才换目标，而 `KEY_STEP` 是 12px，整步走必然从目标两侧来回跳，距离永远 >6px，
  于是 `_cloud_t` 永远不前进。它绿是因为旧版完成度是"每调一次 `_update_draw`
  记 `段长 × 0.1`"：这个压根没描边的死循环自己把进度刷满了。
  把漏洞修掉之后它立刻变红——**这才是它本来的颜色**。
  判断一条回归可不可信，要问的不是"它断言了什么"，而是"它凭什么能通过"：
  修好被测的漏洞时如果它变红，先怀疑它当初是踩着漏洞在跑。

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

- **同一个键在同一帧里干两件事时，所有"我按了会怎样"的提示都得一起闭嘴**：
  郑铎戏靠 `ui_accept` 推进对白，而 `interact` 也是空格，于是"推进对白的那一下空格"
  照样会走一遍 `_physics_process` 的 interact 分支。打卡那一半早就被
  `_can_start_check_in()` 里的 `if _villain_playing` 挡住了（所以"反派戏吞掉打卡"
  这件事实测并没有发生），可另外两半没人管：`CheckInPrompt._prompt_target()` 只读
  `_nearby_station_idx`，而 `_physics_process` 那张早退单子上**没有** `_villain_playing`，
  于是圈照画——圈上写着「空格 · 完成乐事」，玩家按下去推进的却是对白，
  `_on_interact_blocked()` 还顺手把圈变灰成「这里现在进不去」。玩家看着对白在推进，
  脚下的圈在同时说他按错了，两个提示都在撒谎。
  修法是往那张早退单子里加一格（`_nearby_*` 清 -1）：圈不画了，
  `_interact_blocked_reason()` 也跟着返回空串，那句话自动一起收掉——
  **不必**为"正在过场"单造一句文案，诚实的说法是"这里现在没有可交互的东西"。
  教训是可推广的：那张单子是"这些状态下 `_nearby_*` 不作数"的唯一出处，
  **每往里加一个状态，就得确认 `CheckInPrompt` 和 `_interact_blocked_reason()`
  这两个只读 `_nearby_*` 的下游自动跟着收**——它们各自都不知道那个状态存在。
  回归验证：`verify_interact_latch.gd` 第 6 节。
  顺带两条写断言时踩到的：**打字机没走完时按空格只是把这一行补全**
  （`DialoguePopup._on_next_pressed()` 的第一个分支），不换行——想量"空格推进了一行"
  必须先等 `_typewriter_done`；而 `_try_villain_scene()` 是在 `_physics_process`
  **末尾**置上 `_villain_playing`、清 `_nearby_*` 的早退单子在**开头**，
  所以起播那一帧之后还差一帧才清完，断言必须再等两个 `process_frame`——
  不等的话同一份代码带窗口跑绿、带 headless 跑红，结论正好相反。

- **顶栏 HBox 里任何一个 Label 改字都会把整排标签横向推走**：
  HBox 按子节点的最小宽度排布，`_lvbi_label` 的 text 从"旅币 120"变成"+20 旅币"
  时宽度一变，心神和"下一处"整排横着跳一下——玩家正在读"下一处 358m"的时候
  被推走。所以入账提示走独立的 `_lvbi_toast`（挂在 HUD3D 上、绝对定位、不进
  HBox），余额标签一个字都不动。别图省事把它改回去。回归验证：`verify_mood_mask.gd`
  第 7 节直接量三个标签的 `get_global_rect().position.x`。

- **"下一处在哪"现在有三个地方在说，判据必须逐字一致**：
  顶栏 `HUD3D._next_fragment_target()`、小地图 `MiniMap._next_frag_idx()`、
  屏幕提示圈 `CheckInPrompt._label()`。三个都是"最近的、**还欠一次到访**的碎片站"，
  判据本身在 `GameManager.fragment_station_needs_visit()`，三处只许调它，
  不许自己抄一遍。任何一处漂移（比如抄成"第一个未收站"，或拿
  `station_has_fragment()` 静态属性当前者），玩家就会看到顶栏报 A、小地图亮 B、
  脚下圈亮 C——三处都看着像真的，没有任何一处会告诉他错了。
  改其中一处必须同步另两处，跑 `verify_minimap.gd`（沿途逐点核对）与
  `verify_interact_latch.gd` 第 4 节。

- **"已经收过"从来不等于"不用再去"**：完满评级要求五座碎片驿站各去过
  `MAX_VISITS_PER_STATION`(3) 次，所以第一次拿到碎片之后这站还剩两次。
  旧口径在 `is_collected()` 上就把这站从"下一处"里摘掉了，等于把全游戏最强的
  重玩钩子从导航上抹了，而脚下的圈照亮 2 次——顶栏和圈互相打架。
  连带三处文案都必须跟着改：顶栏 `hud_revisit_target`（"再访 … · 还差 N 次"）、
  脚下圈 `desktop_revisit_prompt`（原来写"歇一脚"，那是在劝退）、
  底栏 `FragmentBar._draw_visit_pips()`（收过之后三次必须长得不一样）。
  全满的判据是 `GameManager.all_fragments_maxed()`，不是"五块都收了"。
  `HUD3D.MAX_VISITS_PER_STATION` 是 `GameManager` 那份的副本（static const 读不到
  autoload），两份必须相等，`verify_minimap.gd` 第 4 节量这条。

- **"五块碎片都拿齐了"是**中局**不是终局——结束条件只有一个判据**：
  `GameManager.all_fragments_maxed_reached`（= `all_fragments_maxed()`，
  五座碎片驿站各刷满 `MAX_VISITS_PER_STATION` 次）。
  原来 `World3D` 直接拿 `all_fragments_collected`（五站各收过**一次**）当结束条件：
  集齐 → 锁死 2.5 秒 → 弹去结算页。而 `all_fragments_maxed()` 这个判据**一直写在那里、
  零调用者**。后果是顶栏从第一屏起就写的「再访 · 还差 N 次」一句都兑现不了，
  三处"下一处"指示器在玩家最需要它们的那一刻一起消失。
  现在两个信号分工：`all_fragments_collected` 只放动画不放人
  （`_on_all_collected` 末尾浮一句"顶栏的圆点还是空的"），
  `_on_all_maxed` 才锁死并 `go_to_end_card()`。
  两者都是**状态翻转**事件，所以 `check_in()` 里必须带 `_collected_fired` /
  `_maxed_fired` 闩锁，`_load_save()` 末尾按存档现状补齐——读档回来它们不该重发，
  否则一个五站全收的存档第一次回访就会重放合成动画并把玩家弹去结算页。
  `_spawn_synthesis_animation()` 一趟会被调两次，而 `FragmentFlying` 是
  `auto_free_on_complete = false`，所以它开头必须先清掉上一层的 `SynthesisLayer`。
  回归验证：`verify_minimap.gd` 第 9/10 节（集齐后整圈逐点对三处指示器 + 站到每座
  碎片站前核对"还差 N 次"两处同数 + 刷满才 `_all_done`）。

- **拿掉一条结束路径，就得补一条出口**："集齐即结算"换成"刷满才结算"之后，
  这一趟**原本没有任何玩家可主动喊停的出口**——暂停面板里只有「重新开始」，
  而它走 `go_to_gift_box()` → `reset()`，把 `collected` 一起清掉。后果是
  `PostcardVariant` 的前四档（初旅/探索者/朝圣者/大师）全成了走不到的死代码，
  玩家只剩从头再骑一遍。修法是在 `PausePanel` 里加「结束这一趟 · 收下明信片」，
  零碎片时不出现（那时候做出来的是空卡，EndCard 上没有任何说法）。
  **凡是删掉"到某个状态自动结束"的地方，都要回头问一句：那件事现在还能不能做完？**

- **`.tscn` 里没有 `[connection]` 段的信号 = 从来没连过**：`PausePanel._on_visibility_changed()`
  写了三年（`World3D.tscn` 的 PausePanel 节点上并没有对应的 `[connection]`），
  一直没人调用——静音按钮的开场状态也就永远不刷新。这跟"函数存在就是接线好了"
  是两回事。连信号要在 `_ready()` 里做，别指望场景文件。

- **新增断言要先证明它会红**：一段新写的断言第一次跑就全绿，多半是它**什么都没量**。
  这不是理论——`verify_minimap.gd` 第 9 节写完第一次跑就是 OK 62 / FAIL 0，
  看着像立刻写对了。往 `_on_all_collected()` 里塞一行 `_all_done = true` 再跑一次，
  立刻 11 条红（"这一趟没有结束"、"圈指的就是它"、"脚下的圈说还差 2 次"……），
  撤掉才恢复全绿。改完断言就照这个流程走一遍：故意弄坏 → 看它红 → 撤掉。
  同族陷阱：**别把断言的极性写反**。`postcard_variant_hint` 那一行是"**没到**完满
  才提示第五格"，所以"只把一站刷满"仍然是大师、那行**必须还在**——
  我第一版写成"不包含"就红了。断言失败时先确认自己要断的是哪一边。

- **测试里的存档摆弄必须走真实入口**：`verify_minimap.gd` 第 9 节量的是
  "集齐不再结束这一趟"，而直接写 `GameManager.collected[i] = 1` 根本不会发信号，
  那一节量的是一个不存在的世界。它走的是真的 `GameManager.check_in(i)`。
  同理要等 `_on_all_collected` 的 2.5 秒动画放人（`create_timer(3.2)`），
  而第 10 节（刷满 → `go_to_end_card()` 换场景）必须放在整个测试的**最后**。

- **五件碎片的颜色/图标/标签必须同序，且只许有一个出口**：
  `Postcard.gd` 原来在 `VARIANT_LAYOUTS` 里把颜色和 slot 下标一起手抄了一份，
  整份错位一格——标签走 `fragment_%d` 是对的，颜色和图标属于下一件。
  两个表彼此自洽，缩略图一眼扫过去完全正常，而玩家存走的那张 PNG 一样是错的。
  现在颜色一律走 `FRAGMENT_COLS[slot_idx]`、图标一律走
  `_draw_fragment_icon(slot_idx, …)`、标签一律走 `"fragment_%d" % slot_idx`，
  「slot 0 是云」这件事只写一次。`verify_postcard_ending.gd` 第 3b 节
  （`_audit_panel_identity()`）把三者同序这件事钉住，并且要求
  `Postcard.FRAGMENT_COLS` 与 `FragmentBar.FRAGMENT_COLORS` 逐值相同。

- **屏幕空间的提示文字必须自己收进屏内**：`CheckInPrompt._draw()` 原来把
  "空格 · 完成乐事"直接放在 `screen + (0, r+32)`，没有任何夹取。可玩家越骑越近，
  站点的投影就越往画面下方跑——贴着站停下时 `screen.y` 已经逼近 720，那行字整个
  在屏外，而那恰恰是玩家最该读到按键提示的一刻。现在走 `_label_pos()`：
  下方放得下就放下方，放不下就翻到圈的上方，横向也夹。翻上去之后底下是底栏碎片格
  和驿站的木架（全屏最忙的一块），描边救不回来，所以还要先铺一层半透明深色底板。
  回归验证：`verify_interact_latch.gd` 第 5 节（真相机 1.2m + 全屏 63 点网格扫），
  定妆照 `lookdev_journey.gd` 的 `05c_prompt_贴脸` 与 `05d_revisit_回访提示`。

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

- **掐掉后台任务不会掐掉它启动的 Godot，于是下一次测量全是被污染的**：
  用后台 shell 跑回归，中途发现有问题就用 TaskStop 收掉——**收掉的只是那层 bash，
  Godot.exe 本身还活着**（`tasklist` 里躺着一个吃 376MB 的）。它的 CPU 占用会把
  后面每一次跑的最慢帧抬高一大截：同一份代码最慢帧在 19/23/20/34/49/55ms 之间乱跳，
  而**单帧均值稳得像块石头**（0.60~0.64ms）。于是先后量出"改完更慢了"、
  "改完快了"，两次结论都是噪声。判断办法就一条：**均值稳而最大值乱跳，就是外部噪声，
  不是代码**——改性能之前先 `tasklist //FI "IMAGENAME eq Godot_v4.6.2-stable_win64.exe"`。
  同族的自伤：**别在热路径里留 `print`**。`GrassScatter._build_cell_into()` 里
  为了分段计时加了一行 print，一格打一行、开局 260 格，直接把被测的帧预算吃掉了，
  量出来的"建格多贵"里有一大截是 print 自己的钱。分段计时要么只加在被测循环**外面**，
  要么就别加。

- **「最慢的一帧」这类极值断言量的是机器不是代码，除非均值也跟着动**：
  `verify_grass_scatter.gd` 的 `< 20ms` 在干净机器上是稳定的 19.00ms（三跑三过），
  它守的是"ring 0 一格建不完就整帧丢出去"这一类真回归，确实该留；但它留不住
  亚毫秒级的优化——**开局铺满从 44 tick 涨到 55 tick、均值从 0.606 涨到 0.640，
  最慢帧纹丝不动还是 19.00**，断言一片绿。所以给性能项定验收线要同时看三个数：
  铺满 tick 数、单帧均值、最慢帧，只动其中一个多半是噪声。
  由此也否掉过一次"改进"：想给 `tick()` 的建格预算加余量（按"预计总量"掐而不是
  "已用量"掐，想把最坏一 tick 从「预算 + 一整格」压到「一整格」），测下来反而
  铺满 44→55 tick、最慢帧 19→23ms **而且开始飘**（三跑 19/23/20，挂了两回）。
  原因是掐"预计总量"把每 tick 能开的格数压到 1，开局铺不满；而那一格本来
  就占掉整个 tick，**最慢帧压根不受预算控制**——预算只能管"第二格往后的总和"。
  同一次还否掉了第二个猜想：以为建格贵在"5120 个候选逐个扫 16 座驿站 + 1 个盘"，
  改成外接框先否（实测均值 0.606→0.640、铺满 44→46.5 tick，**更慢**，也回滚了）；
  而真正的大头是 `generate_cell()` 而不是 MultiMesh 写入（实测分段计时
  write 只有 0.3~0.9ms，gen 有 10~26ms，且**与成活丛数无关**——5120 候选里
  只活 1771 的那一格和活满 5120 的那一格一样贵）。两项改进都已回滚，
  `GrassScatter.gd` 现在的最差帧就是 19.00ms，**达标线之上没有余量可挤**；
  要真降只能把一格拆到两个 tick 去建。
- **小游戏收尾要给玩家一屏确认**：砍完最后一根就 `_on_mini_game_done(SUCCESS) + queue_free()`，遮罩同一帧消失，玩家分不清是砍赢了还是被踢出去，报上来的现象就是"按空格退出游戏"。要有成功画面 + 停留（`MiniGameBamboo.SUCCESS_HOLD_SEC`），停留期间狂按按键也不能提前结算。回归验证：`verify_bamboo_done.gd`。

- **子节点永远画在父节点的 `_draw()` 之上**：`GiftBox` 原来在场景里放了一个全屏 `ColorRect` 当底色，而它自己的 `_draw()`（礼物盒 + 路网底纹）被那张 ColorRect 全盖住了，标题页一直是一块纯黑，"按开始"时那套缩放淡出动画其实谁也看不见——图看起来"代码里有、画面上没有"。要在 Control 自己身上画东西当背景，背景也得由它自己画，别指望子节点能待在它下面。

- **`ProceduralSkyMaterial` 在 4.6 上没有 `sun_energy` / `sun_latitude` / `sun_longitude` / `sun_angle_min`**：`World3D.tscn` 里那份**旧的** `ProceduralSky` 资源还带着这几个键，把它们照抄进脚本会抛 `Invalid assignment`。更要命的是这行抛在 `--script` 的 SceneTree 流程里，`quit()` 永远走不到，定妆照脚本会一路挂到超时、只吐一行红字。太阳位置和强度归 `DirectionalLight3D` 管，天空这边不用设。

- **`World3D.tscn` 那份 ProceduralSky 在 4.6 上是空的，于是 `background_color` 和 `ambient_light_color` 都是死代码**：
  场景里是 `background_mode = 2`（BG_SKY）配 `ambient_light_source = 3`（AMBIENT_SOURCE_SKY），
  而那份 `ProceduralSky` 是 Godot 3 的老数据（`sky_horizon` / `sky_energy`），
  4.6 载入时静默丢掉整个 sub_resource，运行时读出来 `env.sky.sky_material == null`。
  配一个空 material 渲出来是引擎自带的兜底渐变。于是：
  · `background_mode = BG_SKY` 下 **`background_color` 一个像素都不画**；
  · `AMBIENT_SOURCE_SKY` 下 **只认 `ambient_light_energy`**，`ambient_light_color` 不参与。
  `DayCycle` 第一版正是照着"天是一整片平涂的背景色"这个假设写的，只改
  `background_color` / `ambient_light_color`——结果整段转场里**天和暗部一个像素都没动**，
  地面亮度纹丝不动，回归全绿而画面还是一片白天的天。修法是自己建一个真的
  `ProceduralSkyMaterial`（`DayCycle.setup()` 里），建好之后环境光自动跟着天空走。
  **教训：改天色之前先探一下 `env.sky.sky_material` 是不是 null，别照着 .tscn 里的
  键名推断那个资源还在**——`verify_day_cycle.gd` 现在把"场景自带的天空是空的"
  当成一条前提断言守着，正是因为这个前提一旦悄悄变回非空，上面整套推理就全错了。

- **压低太阳不等于天要暗，光强也得降**：黄昏那档只把仰角从 38° 压到 9°、能量从
  1.1 降到 1.05，渲出来是一片亮黄油的草配一层灰粉的天，读成"下午起了雾"。
  草皮是一张张**竖着的**卡片，侧面朝着方位角，太阳压低反而打得更正对，卡片比地面
  本身亮得多，仰角变化对它们的直接贡献远小于能量。降能量之后（0.70）同一机位
  的近处草从 (49,63,45) 掉到 (22,26,19)，黄昏才立得住。这条只有看图能量出来——
  `lookdev_journey.gd` 的 `12b_day_正午` / `12c_dusk_黄昏` 两张**必须同机位**，
  否则两帧之间混进了机位差，看的人分不清哪些变化是天色给的。

- **`.tscn` 里手存的方向光 basis 不一定是正交阵**：`World3D.tscn` 那盏灯的 basis
  三列长度是 0.997/0.99/0.812，`Basis.slerp()` 每帧刷一串
  "must be normalized in order to be casted to a Quaternion"。而
  `orthonormalized()` 走 Gram-Schmidt，会连 Z 一起挪（实测太阳仰角 38° → 39.85°），
  等于顺手改掉了白天的影子。方向光只用 -Z，所以按 `(仰角, 方位角)` 重搭一套正的、
  Z 逐分量对齐的 basis 才是真的"没动过"；回归也只比**光轴**（`.basis.z.normalized()`），
  比整副 basis 会因为编辑器存下来的缩放而误报。

- **`Environment` 和 `Sky` 是 `.tscn` 的 sub_resource，所有场景实例共用同一份**：
  直接改等于把 `World3D.tscn` 改了——这一趟骑完回主菜单再进来，新的 `World3D`
  开局就是黄昏，而 t=0 会去 lerp 一个已经被写成黄昏的"白昼档"，天色永远回不到白天。
  `DayCycle.setup()` 里 `duplicate()` 之后还要**把 `Sky` 整个换掉**（Sky 同样是
  sub_resource），只换 Environment 不够。对照：`DirectionalLight3D` 的颜色挂在**节点**
  上所以没事，别拿"灯没中招"推断"环境也不会"。回归验证：`verify_day_cycle.gd` 第 10 节
  重新实例化一份场景去对。

- **新的 `class_name` 要先过一次编辑器导入**：`godot --headless --editor --quit-after 60` 才会写 `.godot/global_script_class_cache.cfg`。在跑之前别的脚本按类名引它会报 `Identifier not declared in the current scope`——而 `check_all_scripts.gd` 会把它算成 FAIL，看着像真编译错误。

- **AGX 会把中间调显著提亮并去饱和**：给 unshaded 材质 / 顶点色填色时别照着"看起来该是什么颜色"填。`FarRidge` 的远山第一版按 (0.42,0.53,0.48) 这种"深青灰"填，三层渲出来全是一线白、完全没有纵深；反着调到 0.13~0.52 那一档才出得来空气透视。改颜色必须 `lookdev_horizon.gd` 看图，不能靠数字判断。
  **但"反着调"有个上限：跨度太宽时远的两层会一起被推到白。** 0.13/0.30/0.52
  这一档虽然每层都比天暗，渲出来中、远两层却糊成一道白痕贴在天上，图上
  只剩近层那条暗绿读得出来——`verify_far_ridge.gd` 的"逐层变淡"照过、
  lookdev 的"地平线上有山带"也照过，**两条断言都是绿的而纵深根本不存在**，
  horizon 看着就是三条平色带。所以跨度要压住：现在近/中/远是
  0.17/0.27/0.42（近层抬一点免得贴成纯暗的墙、中远压下来免得顶到白），
  三层才各自站得住。同族的一条教训：**"这层比那层淡"是**逐层**的判据，
  它对"两层一起淡成一样白"完全免疫**——凡是靠"依次递淡"当回归的性能/
  观感项，都得再补一条"最远那层离天空还得有对比"才拦得住。

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

- **「所见即导出」的预览会小到读不出字，而尺寸断言照样全绿**：
  背面缩略图用的是导出同一个 SubViewport 的纹理，卡片在视口里按原尺寸画完
  再缩到预览上。原来的预览固定 200px 宽，于是预览里一行字只剩七来个像素高，
  放大三倍也认不出是哪个字——"所见即导出"只剩一句空话。
  而任何只量控件尺寸的断言（"缩略图不出屏""不遮按钮"）在 200px 和 452px 上
  **都通过**。所以尺寸和像素得分别量：尺寸量"≥400px 宽"，
  像素量暗像素占比 + 墨落在几条横带上（空卡是 0 条，一道划痕也能凑够总量）。
  另外这一屏的空间是**抢出来的**：输入框从 `h*0.32` 收到 `h*0.24`，
  两个按钮从叠着改并排——叠着的时候每个各吃一行，全从预览的份额里扣。
  预览的高度是从按钮下沿反推的（`THUMB_BTN_Y_FRAC` / `THUMB_BTN_H` 是文件级
  常量，摆按钮和摆预览两处各写一份必然漂）。回归验证：
  `verify_postcard_ending.gd` 第 3 节 + `lookdev_journey.gd` 的 `16_postcard_back`。

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

- **`Localization.t()` 查不到 key 时返回 key 自己，不报错也不返回空串**：
  于是一个字打错，屏幕上出现的是 `"villain_1_1"` 这么一串英文下划线，
  而全工程没有任何一处会因此变红——中英两套 `STRINGS` 是各写各的，
  加了中文忘了英文（或反过来）时中文界面一路正常，只有切到英文的那一屏露 key。
  这不是理论：`EndCard` 原来把一句文案存成 `share_text_zh` / `share_text_en`
  **两个** key，看着更直白，实际是在表里埋雷——中文表里没有 `share_text_en`、
  英文表里躺着一份没人读的 `share_text_zh`，两边的 key 集合永远对不上，
  而读代码的人只看得到 `t("share_text_en")` 这一行，看不出中文侧会露 key。
  现在一个字两边各存一份，key 名不许带语言后缀。
  回归验证：`verify_story.gd` 第 1/2 节。
  同族：**"中英同一个 key 不许是同一句话"**这条断言得给纯格式化 key 留出口
  （`visits_left_n` 的值就是 `"%d"`，它不带语言，判据写成"把 `%d`/`%s`/`%f`
  全去掉之后还剩不下字"而不是列一张白名单——白名单每加一个键就多一个可以
  忘更新的地方）。

- **写给下一个人的说明书没人跑，所以它一定会撒谎**：`3D_RIDE_DESIGN.md` 里的
  驿站名、相机参数、单位口径全是手抄的——`road_data` 里禽语湖湾早改叫
  「花房·禽语湖湾 / Birdsong Cove Flower House」而文档还写着旧的，
  相机早从 `* 8 + (0,5,0)` 改成 `* 6.0 + (0,4,0)` 而文档还写着 8 和 5。
  每一处各自自洽，翻两页看不出来错。`verify_story.gd` 第 5 节把文档钉在代码上，
  判据要**整句抠**而不是手拼 needle：手工拼一个 `-forward * 6.0` 去找，
  代码写的是 `global_position - forward * 6.0`，减号两边有空格——
  少写一个空格就永远匹配不上，而"永远匹配不上"和"文档写错了"在这一行上
  长得一模一样（第一版就是这么把自己坑了一轮）。所以改成拿正则从
  `Player3D.gd` 里把 `var target_pos = ...` 整行抓出来，要求文档逐字含有它。
  凡是"文档与代码不许对不上"的断言都按这个写法。

- **Web 上引擎会静默从 Forward+ 掉到 Compatibility 渲染器**：`project.godot`
  没写 `renderer/rendering_method`（默认 Forward+），而 WebGL2 拿不到 Vulkan，
  于是导出物在浏览器里跑的是 **Compatibility**——控制台那行
  `OpenGL API ... Compatibility` 就是唯一的证据，它不会警告你。
  实测（2026-10-01，Chrome headless + SwiftShader，`build_web/`）：
  三层程序化着色器在 Compatibility 下**全部照常出图**——asphalt 的颗粒、
  terrain_grass 的色块、grass.gdshader 的卡片，行道树的 `visibility_range`
  淡出也在。所以现在不用改；可要是哪天在 Web 上看到"东西该有颜色却是一片白"，
  先想到这一层，而不是去查 shader。**这条只有真跑一次浏览器才知道**，
  `--headless` 连 renderer 名字都不告诉你。

- **Web 存档与 PNG 导出实测通过（2026-10-01）**，用 `tools/web_smoke.gd` 量的，
  结论是三条经典失败模式在本项目上**都不成立**：
  · **IDBFS 存档**：`/userfs` 库建得起来，真实 `check_in()` 写进去之后，
	**换一个页面**（不是刷新——刷新走 beforeunload 的同步路径，量不到落盘）
	在同一 profile 里读回来，`collected[7]` 与旅币都在。
  · **PNG 下载**：`EndCard._export_two_images_web()` 走
	`JavaScriptBridge.eval` → `fetch(data:)` → `r.blob()` → `a.click()`，
	正面背面两张都真的落盘（29KB / 29KB 的 1920×1080，图里有字有画不是空白）。
	`fetch` 是异步的、已经不在用户手势里了，Chrome 照样放行——但这是量出来的，
	不是推出来的。
  · **首次点击解锁音频**：headless Chrome 的 AudioContext 一上来就是
	`running`，所以**这一条没量到**，别当成已验证。
  · 附带：全程只用键盘（空格）就能从标题走到骑行——`ui_accept` 在 Web 上是通的，
	`_bind_ui_accept_to_physical()` 那个修法确实管用。