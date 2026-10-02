# 188号礼物 · 3D骑行方案

> 本文是**当前实现**的说明书，不是当初的构想书。
> 文中每一个参数都能在代码里逐字对上，`tools/verify_story.gd` 第 5 节
> 会拿本文和代码对拍——改了代码不同步改这里（或反过来），回归会红。
> 构想过程、放弃的方案与踩过的坑一律不写在这里，那些在 `CLAUDE.md` 的「已知陷阱」里。

## 为什么改3D

2D俯视角的8字路径有几何硬伤：两圆切于一点，waypoint索引在切点处跳变，车经过驿站1/5时偏离路径。
3D骑行用自行构造的贝塞尔 lemniscate 曲线生成路面mesh，路径即路面，所见即所行，彻底消除waypoint跳变问题。

## 路线来源与授权策略

**本作路线是纯虚构的几何图案**，由 lemniscate 参数方程解析采样生成（见 `scripts/road_data.gd` 的 `LEMNISCATE_LOCAL`，49 点），经旋转 60°/缩放/平移后构造成 8 字环形。**不引用任何外部 SVG、GPS 轨迹或现实公路数据**，也不还原任何现实道路的走向。

驿站名全部是虚构雅称，不使用任何真实地理或官方驿驿品牌名称。

本作为虚构叙事 Demo：路线形状、驿站名、场景布局均为艺术化创作，题材取自公有领域的东坡诗文，不声称代表任何现实旅游公路、官方驿站品牌或实际景区运营内容。

## 「188」是编号不是里程

`GameManager.TOTAL_ROUTE_KM = 188` **只作旅币经济口径**（每骑过 1 整公里 +2 旅币），
不出现在任何玩家可见的界面上。真实环路只有 1228.8m，按 15 m/s 满速折算约 2 km/s，
顶栏挂着那个数玩家骑三十秒就能算出 7200 km/h，然后整个数字连同它承载的门槛一起变噪音。

**顶栏走的是驿数口径**：`GameManager.get_seen_station_count()`，写「已过 n/16 驿」。
已从 km 门迁走的：灯铺解锁（`shop_data.gd` 的 `seen_unlock = 6`）和
`World3D.VILLAIN_SCENES` 三场郑铎戏（`seen = 4/8/12`）。
回归：`verify_economy.gd` 的 `_check_km_offscreen()` 扫全部文案里的
`km / 公里 / kilometer / kilometre / K0 / K188`。

## 坐标映射

参数曲线局部坐标 → 3D世界坐标（`road_data.gd`）：

- `world_x = (px - 400) * 0.5`  （`CX = 400`，`SCALE = 0.5`）
- `world_z = (py - 714) * 0.5`  （`CY = 714`）
- `world_y = 地形高度`  （Y轴朝上）
- 旋转 60° + 缩放 350 + 平移 (400, 800) 之后是画布坐标

## 技术架构

`scenes/World3D.tscn` 实际节点（节选，完整树见场景文件）：

```text
World3D (Node3D)
├── WorldEnvironment            # 天空+雾（DayCycle 运行时注入真的 ProceduralSkyMaterial）
├── DirectionalLight3D          # 太阳（DayCycle 改它的高度角/方位角/能量）
├── FillLight3D                 # 补光
├── TerrainBuilder              # 程序化地形
├── RoadBuilder                 # 路面 mesh + 路面高度查询
├── VegBuilder                  # 行道树/灌木的静态布点（编辑模式产物）
├── GrassScatter                # 脚边草皮：MultiMesh 池 + 逐格流式
├── TreeScatter                 # 行道树：按弧长等间距 + 每格一个 MultiMesh
├── Player3D (CharacterBody3D)
│   ├── BikeCollision
│   └── Camera3D                # 第三人称跟随
├── HUDLayer
│   ├── CheckInPopup
│   ├── DialoguePopup
│   ├── FragmentBarLayer / FragmentBar
│   ├── JoystickLayer / VirtualJoystick
│   ├── MiniGameLayer
│   ├── HUD3D (TopBar / HelpOverlay)
│   ├── MiniMap
│   └── CheckInPrompt           # 屏幕空间提示圈 + 触屏「完成乐事」按钮
└── OnboardingGuide / ShopPanel / PausePanel
```

`FarRidge` 与 `DayCycle` 是运行时挂上去的（见 `World3D._ready()`）。

## 关键模块

| 脚本 | 职责 |
|---|---|
| `GameManager.gd` | 存档（v3）、旅币经济、心神、驿数进度、结束条件的两个闩锁 |
| `World3D.gd` | 3D主世界、打卡流程、相机过场、反派三场、边界、小地图连接 |
| `Player3D.gd` | 骑行控制与相机跟随 |
| `RoadBuilder.gd` | 路面mesh、中心线、`get_road_ribbon_height()` 三角形质心插值 |
| `TerrainBuilder.gd` | 程序化3D地形与高度查询 |
| `VegBuilder.gd` / `GrassScatter.gd` / `TreeScatter.gd` | 植被三层：静态布点 / 脚边草皮 / 行道树 |
| `FarRidge.gd` | 远景山线（三层环形，纯几何零贴图，顶点色烘空气透视） |
| `DayCycle.gd` | 骑满两圈后天色走到黄昏；太阳方向、光强、天空一起走 |
| `CheckInPrompt.gd` | 屏幕空间打卡提示圈与触屏按钮 |
| `Localization.gd` | 中英文案与语言持久化 |
| `shop_data.gd` / `ShopPanel.gd` | 三铺数据与采购面板 |
| `Postcard.gd` / `PostcardVariant.gd` / `EndCard.gd` | 明信片分级、导出 PNG、终局二选一 |

## 自行车控制方案

**不用 VehicleBody3D**（太重，需调参），改用 **CharacterBody3D 自由 3D 移动**：

| 输入 | 行为 |
|---|---|
| W / 摇杆上 | 沿车头方向加速（`ACCEL = 8.0`，上限 `MAX_SPEED = 15.0` m/s） |
| S / 摇杆下 | 减速 / 倒退（`REVERSE_SPEED = 5.0`） |
| A / 摇杆左 | 左转（`TURN_SPEED = 1.8` rad/s） |
| D / 摇杆右 | 右转 |
| Space / Enter / 触屏「完成乐事」 | 靠近驿站时打卡 |
| Esc | 暂停 |
| M | 全局静音 |

实际实现（`Player3D.gd`）：

- 玩家**不**吸附在路网上。世界是自由 3D 的，路只是画在地面上的一片 mesh
- 每帧 `position += forward * _speed * delta`，`forward = -basis.z`
- 转向速率按速度缩放：`turn_factor = clamp(|speed| / 3.0, 0, 1)`，站着不动时转不动车
- Y 由 `World3D._physics_process` 按地形高度设置，`Player3D` 不覆盖
- 边界由 `World3D._apply_boundary_force()` 软回弹处理，不做硬 clamp

## 相机方案

第三人称跟随（车后方斜上方**偏侧**），`Player3D._update_camera()`：

```gdscript
var forward = -global_transform.basis.z
var right = global_transform.basis.x
var target_pos = global_position - forward * CAM_BACK + right * CAM_SIDE + Vector3(0, CAM_UP, 0)
_cam.global_position = _cam.global_position.lerp(target_pos, 0.12)
_cam.look_at(global_position + forward * CAM_LOOK_AHEAD + Vector3(0, CAM_LOOK_UP, 0), Vector3.UP)
```

`CAM_SIDE` 不是构图口味，是**可读性**：正后方 0 横向偏移时，一辆车在这个距离上
正投影成一根竖条——车架三角、两个轮子全部侧对镜头，认不出是自行车。
横向让开 1.15m 是唯一能把车读成"车"的自由度（`tools/verify_panel_keyboard.gd`
之外的 `tools/verify_camera_bike.gd` 钉这条：屏幕上车的投影宽高比）。

`set_camera_locked(true)` 期间相机冻结——打卡时的运镜由 `World3D._do_check_in()`
用另一条 tween 接管（1.0s 移到站点旁的机位，再定格 1.5s）。

## 路面Mesh生成

`RoadBuilder.gd` 用 `SurfaceTool` 生成：

1. 取 lemniscate 采样点（49 点解析采样），重采样到约 0.5m
2. 每个点计算路宽方向（垂直于切线）
3. 生成左右边带顶点
4. 三角带连接相邻段
5. 路面细节由 `assets/shaders/asphalt.gdshader` 程序化补充：颗粒、胎痕、路缘起灰、潮斑、路肩泥土、双黄虚线

**交叉点高度必须用 `RoadBuilder.get_road_ribbon_height(x, z)`**
（三角形质心插值 + max 聚合），不能用 `get_road_height_at_xy`——后者会跳变 0.143m。

## 地形与植被

- 地形：`TerrainBuilder.gd` + `assets/shaders/terrain_grass.gdshader`（低频色块 + 中频斑驳 + 高频麻点 + 随距离淡出的法线扰动）
- 草皮：`GrassScatter.gd`，脚边同心环（桌面 200m / Web·移动端 100m），驻留期间零重建零隐藏
- 行道树：`TreeScatter.gd`，沿中心线按弧长每 25m 一株，每格一个 MultiMesh，`visibility_range` 淡出
- 三层的流式**共用同一张格子**：`CELL` 必须一致（`CLAUDE.md` 有专门的回归钉这条）
- 远景：`FarRidge.gd` 三层环形山线（800/1350/1900m），材质必须 `disable_fog = true`
  ——`LAYERS` 里的颜色是照着最终观感调的，场景雾再洗一次就是同一份雾算两次

## 驿站与五件乐事

16 座驿站中 5 座有碎片，对应《东坡赏心十六乐事》（公版诗词）里的第 1、2、12、13、16 件：

| slot | 驿站 | English | 乐事 | 碎片 |
|---|---|---|---|---|
| 0 | 云影台 | Cloudshadow Terrace | 雨后台阶看云 | 云 |
| 1 | 茶烟小筑 | Tea Smoke Cottage | 朋友来了先煮茶 | 茶 |
| 2 | 琴音林 | Zither Grove | 把风声听成琴音 | 琴 |
| 3 | 竹雨庭 | Bamboo Rain Courtyard | 夜雨敲竹 | 竹 |
| 4 | 花房·禽语湖湾 | Birdsong Cove Flower House | 一只鸟替湖回答 | 禽 |

在环上的下标：`road_data.FRAGMENT_SLOT_STATION_IDX = [7, 10, 13, 14, 4]`
（`road_data.stations` 的数组下标，与曲线上的采样点无关）。

另有 11 座非碎片驿站（`起程驿楼` / `东岭驿楼` / `南溪茶寮` / `右岭岭台` / `岭口凉亭` /
`西湾神苑` / `灯影亭` / `北岭凉亭` / `左弯廊` / `西谷岭台` / `榕树下`），它们不承担收集目标，
但每一座都有一句在**进圈那一帧**浮出来的话（`STATION_PASS_RADIUS = 15.0`，
边沿触发，不是每帧判距离——否则停在圈里每秒重弹一次）。

`驿铺 / 茶铺 / 灯铺` 三家开在其中三座上，价格与解锁条件全在 `shop_data.gd`。

## 收集目标：集齐 ≠ 走完

`MAX_VISITS_PER_STATION = 3`，五座碎片驿站**各**去过 3 次才算走完这一趟：

- `all_fragments_collected`（各去过 1 次）只放动画不放人
- `all_fragments_maxed_reached`（各刷满 3 次）才锁死并 `go_to_end_card()`

顶栏 / 小地图 / 脚下提示圈这三处「下一处在哪」判据统一走
`GameManager.fragment_station_needs_visit()`，三处只许调它，不许自己抄一遍。

## 开发流程

改动前先看 `CLAUDE.md` 的「提交规范」一节——每一条入口改动都指定了必须先跑的回归。
`tools/` 下 30+ 条无头/带窗口回归覆盖路径形状、路面高度、植被、草皮、昼夜、
经济、商店、结局、键盘通路与故事一致性。

## 验收重点

- 桌面 Space 可完成 5 个碎片驿站的首次打卡与回访
- 手机「完成乐事」按钮可完成同样的流程
- 纯键盘可从冷启动走到第一次踩上踏板（`verify_panel_keyboard.gd`，带窗口）
- 明信片可导出 PNG，二选一的两种结局在**正面**上真的不同
- 中英文切换后首页、HUD、暂停、打卡、结局文案正常
- 8字交叉处无明显高度跳变或颠簸
- 自行车无长时间穿模、陷路、浮空
- 灌木或树木不生成在路面中央或核心驿站内部
- 游戏内不展示现实道路的官方驿站原名
- 顶栏不出现任何里程数字（P0-4）
