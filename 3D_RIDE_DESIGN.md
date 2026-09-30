# 188号礼物 · 3D骑行方案

## 为什么改3D

2D俯视角的8字路径有几何硬伤：两圆切于一点，waypoint索引在切点处跳变，车经过驿站1/5时偏离路径。
3D骑行用自行构造的贝塞尔 lemniscate 曲线生成路面mesh，路径即路面，所见即所行，彻底消除waypoint跳变问题。

## 路线来源与授权策略

**本作路线是纯虚构的几何图案**，由 lemniscate 参数方程解析采样生成（见 `scripts/road_data.gd` 的 `LEMNISCATE_LOCAL`），经旋转 60°/缩放/平移后构造成 8 字环形。**不引用任何外部 SVG、GPS 轨迹或现实公路数据**，也不还原任何现实道路的走向。

里程显示使用 `GameManager.TOTAL_ROUTE_KM = 188`，是创意数值，与几何尺度解耦（玩家骑行弧长按比例换算为该里程数）。

本作为虚构叙事 Demo：路线形状、驿站名、场景布局均为艺术化创作，题材取自公有领域的东坡诗文，不声称代表任何现实旅游公路、官方驿站品牌或实际景区运营内容。

5个游戏碎片驿站（虚构雅称）与曲线位置：

- S1 云影台 / Cloudshadow Terrace — 云
- S2 茶烟小筑 / Tea Smoke Cottage — 茶
- S3 琴音林 / Zither Grove — 琴
- S4 竹雨庭 / Bamboo Rain Courtyard — 竹
- S5 禽语湖湾 / Birdsong Cove — 禽

## 坐标映射

参数曲线局部坐标 → 3D世界坐标：

- `world_x = (canvas_x - 400) * scale`  （居中）
- `world_z = (canvas_y - 714) * scale`  （居中）
- `world_y = 地形高度`  （Y轴朝上）
- `scale = 0.5`

## 技术架构

```text
World3D.tscn (Node3D)
├── DirectionalLight3D        # 太阳光
├── WorldEnvironment          # 天空+雾
├── Terrain (StaticBody3D)   # 低多边形地面
├── RoadMesh (MeshInstance3D) # 由路网点生成的路面mesh
├── Stations (Node3D)
│   ├── Station1 ~ Station16  # 5个碎片驿站 + 11个装饰路标
├── Player3D (CharacterBody3D)
│   ├── BikeModel (MeshInstance3D)  # 自行车模型
│   ├── Camera3D (Camera3D)         # 第三人称跟随
│   └── CollisionShape3D
├── HUDLayer (CanvasLayer)    # HUD / FragmentBar / CheckInPopup
└── JoystickLayer (CanvasLayer)  # 移动端摇杆
```

当前关键模块：

- `World3D.gd`：3D主世界、玩家、驿站、打卡、相机、边界、小地图连接
- `TerrainBuilder.gd`：程序化3D地形
- `RoadBuilder.gd`：道路mesh、中心线、路面高度查询
- `VegBuilder.gd`：树、灌木、道路/驿站保护半径
- `Player3D.gd`：骑行控制
- `VirtualJoystick.gd`：移动端虚拟摇杆
- `CheckInPrompt.gd`：屏幕空间打卡提示圈与触屏“完成乐事”按钮
- `Localization.gd`：中英文案与语言持久化

## 自行车控制方案

**不用VehicleBody3D**（太重，需调参），改用 **CharacterBody3D + 路网跟随**：

| 输入 | 行为 |
|---|---|
| W / 摇杆上 | 沿路网前进方向加速 |
| S / 摇杆下 | 减速/倒退 |
| A / 摇杆左 | 左转 |
| D / 摇杆右 | 右转 |
| Space / Enter / 触屏“完成乐事” | 靠近驿站时打卡 |
| Esc | 暂停 |
| M | 全局静音 |

实际实现：

- 预计算路网所有点（49 点解析采样 → 48×20 = 960 点，RoadBuilder 再平滑重采样）
- 玩家在路网上有 `_road_index`（浮点数）和 `_road_progress`
- W加速 = `_road_speed` 增大
- 每帧 `_road_index += _road_speed * delta`
- 位置 = 路网点[int(_road_index)] 与下一点的lerp
- 朝向 = look_at 下一个路网点
- 相机 = 车后方偏移 + smooth follow

## 路面Mesh生成

用Godot的 `SurfaceTool` 或 `ImmediateMesh`：

1. 取处理后的路网点（三次高斯平滑 + 0.5m 重采样）
2. 每个点计算路宽方向（垂直于切线）
3. 生成左右边带顶点
4. 三角带连接相邻段
5. 道路细节由程序化shader补充：颗粒、胎痕、路缘起灰、双黄虚线

## 地形

低多边形地形：

- 一个大的 `PlaneMesh`（细分20×20）
- 用 `FastNoiseLite` 生成高度噪声
- 山体区域高度更高
- 水边驿站区域高度更低，用于湖面/水岸关系

## 驿站3D占位

5个碎片驿站各用3D地标表现，走近时加载GLB：

- S1 云影台：观景亭/台阶，表达雨后看云
- S2 茶烟小筑：茶屋，表达客至煮茶
- S3 琴音林：古林林地，表达风穿树叶如琴音
- S4 竹雨庭：竹窗/水岸灯火，表达夜雨敲竹
- S5 禽语湖湾：湖湾花房，表达飞鸟替湖回答

另外11个装饰路标只补足8字路线与里程感，不承担核心收集目标。

## 相机方案

第三人称跟随（车后方斜上方）：

```gdscript
相机位置 = 车位置 + 车朝向的逆方向 * 8 + Vector3(0, 5, 0)
相机look_at = 车位置 + 车朝向 * 3
smooth = 0.15 # lerp因子
```

## 复用与改造资产

| 2D模块 | 3D中复用/改造方式 |
|---|---|
| GameManager.gd | 保留状态机、碎片逻辑，增加3D里程/存档/场景切换 |
| AudioManager.gd | 保留BGM+SFX，增加环境音与分别静音 |
| HUD | 改造为HUD3D，显示里程、碎片、暂停、声音、帮助 |
| FragmentBar | CanvasLayer直接挂到3D场景 |
| CheckInPopup | 改造为3D驿站打卡弹窗 |
| EndCard | 保留合成/导出逻辑，支持中英文与PNG下载 |
| GiftBox.tscn | 标题页进入World3D，增加语言切换 |
| 字体/音频 | 路径保留，字体子集化、音频OGG化 |

## 开发排期

| 步骤 | 产出 |
|---|---|
| 1. 写方案 | 本文档 |
| 2. project.godot改3D | 渲染器Forward+，视口1280×720 |
| 3. 构造路线数据 | `scripts/road_data.gd` — lemniscate 采样点 + 16 站点坐标 |
| 4. World3D.tscn骨架 | 地形+光照+天空 |
| 5. 路面mesh生成 | `scripts/RoadBuilder.gd` |
| 6. Player3D | `scripts/Player3D.gd` — 路网跟随+相机 |
| 7. 驿站占位 | 5个碎片地标 + 11个装饰路标 |
| 8. HUD挂载 | HUD3D / FragmentBar / CheckInPopup |
| 9. GiftBox跳转 | 标题页跳转World3D |
| 10. 测试运行 | F5，车沿路面骑行；回归道路/植被/交叉点 |

## 后续验收重点

- Web浏览器可打开并运行
- 桌面Space可完成5个碎片打卡
- 手机“完成乐事”按钮可完成5个碎片打卡
- 明信片可导出PNG
- 中英文切换后首页、HUD、暂停、打卡、结局文案正常
- 8字交叉处无明显高度跳变或颠簸
- 自行车无长时间穿模、陷路、浮空
- 灌木或树木不生成在路面中央或核心驿站内部
- 游戏内不展示现实16个官方驿站原名

## 优势对比

| | 2D原方案 | 3D骑行 |
|---|---|---|
| 路径 | 隐形waypoint，8字几何有bug | 贝塞尔lemniscate生成的路面mesh，所见即所行 |
| 控制 | WASD抽象映射路径方向 | W加速/S刹车/A/D转向，直觉操作 |
| 视觉 | draw_circle/draw_rect | 3D低多边形，沉浸感强 |
| 路径问题 | 需数学修正waypoint | 路面即路径，交叉处需回归验证 |
| 比赛 | 2D偏弱 | 3D世界构建更契合“世界构建”主题 |
