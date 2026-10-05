# CLAUDE.md — 188号礼物 项目档案

## 项目概览

《188号礼物》是一款 3D 骑行 demo：沿一条由贝塞尔参数曲线自行构造的 8 字 lemniscate 环形路线，玩家骑着自行车穿越 5 个有碎片的东坡赏心乐事驿站，集齐"云/茶/琴/竹/禽"五个字合成一份礼物。

> **本作是纯虚构作品**：路线为几何图案自行构造，不参考、不还原任何现实公路走向；驿站名全部是虚构雅称；题材取自公有领域的东坡诗文。详见 README 的 Legal 说明。

- **引擎**: Godot 4.6.2 (Forward+)
- **主场景**: `res://scenes/GiftBox.tscn` → `res://scenes/World3D.tscn` → `res://scenes/EndCard.tscn`
- **Autoload**: `GameManager`（存档）、`AudioManager`（音效）、`Localization`（中/英双语）、`QualitySettings`（画质档位）
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
  FragmentBar.tscn 底部碎片栏（五格）。**未收的那一格原来画的是
					「灰圆盘 + 同一个灰的图标 + 一个盖在图标上的灰问号」**——
					于是图上是五个一模一样的灰方块，玩家只知道"还差 5 个"，
					不知道那 5 个是什么、哪一格是下一处要去的那件。屏上当时还有
					**两个**问号：`.tscn` 里每个 Slot 底下挂着一个写着全角问号的
					占位 Label（收过之后才被 `_process` 换成碎片名），画笔又画了
					一个。现在：外圈 5px 的**实心色盘**（`RIM_W`，用它自己那件的颜色）
					+ 不透明中性盘 + 自己那件的彩色图标 + 问号缩成右下角角标。
					**色盘画在盘外而不是盘内一道细环**，是量图上的硬理由：
					云是实心多边形、竹的梢伸到半径 25，都压得进盘内 19~21 那一圈，
					于是定妆照量到的是图标而不是环，把环退回灰色它照样报"五格分得开"
  EditorHUD.tscn  编辑模式侧栏（仅编辑时挂载）

scripts/          GDScript 脚本
  GameManager.gd        全局存档 + 状态机。存档是**原子写**的：临时文件 → 把正本
						复制成 `.bak` → 换名盖掉（顺序不能挪，换名会擦掉目标）。
						读档走 `正本 → 备份 → 当作没有`，而**不看 `ConfigFile.load()`
						的返回值**——实测它对截断、纯垃圾、空文件一律返回 OK。
						落盘的值一律过 `_sanitise_*`：一份坏存档不许让玩家赢不了
						（到访次数 > `MAX_VISITS_PER_STATION` ⇒ 那一座永久打不了卡，
						顶栏「下一处」还指着它）或白赢（`postcard_tier` 直接就是档位）。
						`Localization` 的语言档与 `QualitySettings` 的画质档**故意没**
						跟着改：同样是单文件非原子写，可丢的只是一个默认值，不是这一趟
  World3D.gd            3D 场景主控
  RoadBuilder.gd        沥青双车道 mesh 生成
  RoadVerge.gd          路肩之外那道**看得见**的软边界：6.5m（沥青外沿）到
						14.5m 铺一条压实的碎石路肩，在**恰好 `World3D.SOFT_BOUND`
						那个距离上**刷亮成一道粉线，再淡回地形自己的草色。
						**中间三档是低饱和的灰砾石**（`GRAVEL`/`PACKED`/`LINE`
						通道差 ≤0.06）——这一带原来是一条**土径**，而那正是这一轮
						清掉的东西：沿整条环路两侧读成两条泥带。`verify_road_verge.gd`
						第 ④ 节钉着"不许调回土"，配一条用 `GRASS` 当尺子的正对照。
						只铺主环路（支线不参与那道推力）。零纹理，纯顶点色。
						`SOFT_BOUND` 是 `build()` 的**参数**、`World3D` 从自己那个
						常量传进来的，不是两边各抄一个 12.0——画出来的那道线与
						推你回来的那道力必须引同一个数
  TerrainBuilder.gd     程序化地形 mesh + 高度查询
  VegBuilder.gd         流式植被（MultiMesh + 16 chunks）
  GrassScatter.gd       玩家周围的实例化草皮（MultiMesh 池 + 逐格流式 + 叠加同心环，
						桌面 200m / Web·移动端 100m；驻留期间零重建零隐藏）
  TreeScatter.gd        路两侧行道树（沿中心线按弧长等间距 25m，每格一个 MultiMesh +
						visibility_range 淡出；桌面 150m / Web·移动端 100m；驻留零重建）
  FarRidge.gd           远景山线：三层环形山脊（800/1350/1900m，纯几何零贴图，
						顶点色烘空气透视），补地形边界之外什么都没有的平地平线
  RoadSteles.gd         路边四块碑：前三块刻着「188」，第四块的字被人凿平了
						（就是郑铎 villain_2_1 点名的"刻字的石头"）。CSG 图元 +
						Label3D，零新 GLB 零纹理。落点离路心线 9m，避开驿站和
						**行道树的视线**；碑面朝向由最近那段中心线算，不是世界原点
  CrossingMark.gd       8 字自交点那块「路自此复」的碑。碑面上刻的不是字，是
						**这条路自己的形状**——刻线由 `RoadData.points` 生成，
						和 RoadBuilder 建沥青同一份数据，所以这张图不可能说谎。
						**面只后仰 14°**（原来 40°，理由写的是"低头就正对着脸"，
						可低头读得清的那一档恰恰是最躺的一档，见已知陷阱）；
						`face_lift()` 是 **static 且算出来的**，写死高度会让题字
						悄悄埋进石台
  HomeBase.gd          主角的家（叙事锚点 + 真据点）。选址**沿弧长比例走**
						（`HOME_AT`）并往外推 `HOME_OFFSET` 15m，让开自交点广场
						与 16 座驿站、避开水与陡坡。`road_pt` 是房子正对的那**一个**
						中心线点——朝向、小地图钉在哪一侧都由它定，**别拿"离落点
						最近的那个中心线点"代替**（8 字两瓣靠得近，全局最近点会落到
						另一瓣上，见陷阱清单里"取样点自己得先问落在什么东西上"）。
						房子是 CSG + Label3D，零新资产。**挡车走硬推出**（`_home
						.keepout_radius()` + `damp_speed`），同驿站那一套，但多一条
						驿站没有的约束：推出点必须仍在 `HOME_PASS_RADIUS` 里，
						否则玩家被墙挡在圈外、永远到不了家。行道树让位复用
						`STATION_CLEAR`（10m 已大过房子半对角线 5.0m）
  RevisitNote.gd         回访那一屏**说什么话**。四句而不是一句：原来只有一句
						`revisit_note`，而它在第 2 次和第 3 次到访上**逐字出现两遍**，
						而完满评级要的正是三次到访——玩家在最该被说服"再骑一趟"
						的那两趟里读到的是同一段话。`key(visit, lap)` 按
						（第几次 × **绕没绕完一整圈**）选，`lap` 走
						`World3D._lap_index()`（从 `_odometer_units` 算，本工程
						压根没有圈数计数器）。照 MiniGamePicker 的老办法：
						preload，**不要 class_name**
  water_data.gd         三处水的唯一出处：`plan()` 按**真实自然地形**把三只碗
						定下来（碗心 = 碗底足迹平均高程最低处，不是最低的那一点），
						`depth_at()` 供 TerrainBuilder 挖碗。全场统一水位 -3.4，
						压在 `_height()` 的高程下限 -3.0 之下——关得住水靠的是这条
  Water.gd              三片水面。岸线是逐角度在**建出来的地形网格**上步进求交
						（2m 步进 + 6 次二分），不是以碗心画圆；碗是椭圆，所以每个
						角度的搜索上限是"沿这个方向到盆沿还有多远"而不是 radius
  road_data.gd          48 点 lemniscate 路径 + 16 驿站数据
  LayoutData.gd         res://layout.json 读写（编辑模式产物）
  LayoutEditor.gd       编辑模式主控制器
  EditorHUD.gd          编辑模式 UI
  Player3D.gd / HUD3D.gd / MiniMap.gd / CheckInPrompt.gd ...
  SettingsPanel.gd      设置面板：音量滑杆 ×2 / 画面三档 / 操作说明。顶栏右上角那个
						「?」与暂停菜单里那一行「设置」进的是**同一个实例**
						（`World3D/SettingsPanel`，`HUD3D._settings_panel()` 按
						`get_parent()` 找它）。**它原来不存在**——那个位置的按钮指着
						一块**从没被打开过**的 `HUD3D/HelpOverlay`（`show_help()` 零
						调用者、`.tscn` 里也没有 `[connection]` 段），而那块面板是
						键位表的**第四份实现**、写死中文。玩家中途想再看一眼操作说明
						没有任何办法。现在键位表只有 `GameManager.PLAYER_ACTIONS`
						一个出处：注册走它的循环、冷启动引导走
						`player_control_rows()`、设置面板走同一个。
						**打开面板时滑杆读的是当前真音量**（`set_value_no_signal(
						AudioManager.bgm_volume())`），不是建面板那一刻的值——
						在骑行中改过音量再打开面板，滑杆必须跟着走
  MiniGameBar.gd       云/茶/竹三个小游戏共用的进度条。**门槛要画在条上**：原来三处
						都把门槛写在了字里（"到 75% 算过" / "3 秒后完成" / "进度 0/5"），
						却没有一处给它一个位置——玩家盯着一条填到头就赢的槽，看不出
						还差多远，而那个差距正是这一屏的全部张力。刻痕跨在条**外**
						（画在条里就成了"条上的一道纹"，和边框、分隔线分不开），
						门槛之后那一截底色提亮；竹是**分格**而不是连续条——进度是
						五件互相独立的事，一根填到 60% 的条读成"有一根被砍掉了 60%"，
						实际是三根倒了、两根还立着，当前那格描金边。几何全是纯函数
  MiniGameChrome.gd     五个小游戏共用的「取消」按钮。**它不穿警报红**：原来
						云/茶/琴三处各画一份 `fill(0.4,0.3,0.3) + border(0.8,0.3,0.3)`，
						而全工程真正在报警的红是 `HUD3D.set_boundary_intensity()` 那圈
						边界警告和竹子的砍伐窗口倒计时——玩家学会「红 = 出事了」之后，
						再在角落里看见一块红，读出来的是「取消要付代价」，而它不要付
						（ESC 也能按，驿站还能再来一次）。现在是一块**不透明**的中性
						深灰小片 + 暖灰边 + 米白字：不透明是刻意的，五个小游戏背景
						亮度差得远，半透明底板的对比度随背景漂。禽原来**留了热区却
						没画**，右下角是一块点得着、读不出是什么的地方；**竹连按钮
						都没有**，缺席理由写的是"左键在这一屏是砍，画按钮得判点击落在
						哪、怕误砍"——那条只解释了难做、没解释不做：ESC 在这一屏是
						隐藏的，于是鼠标玩家看见的是一个点哪都能砍、哪也退不出去的
						黑幕。误砍的代价是零（1.2 秒窗口自己会过），而"点取消挨一刀"
						不是——所以**竹的热区判在"当成砍"之前**，判在后面就反了
  SynthesisPanel.gd     集齐时的二选一面板：「收下明信片 · 结束这一趟」/「再骑一圈 ·
						刷到完满」。量出来的下限是 3.1 分钟（`tools/play_newcomer.gd`，
						五个小游戏的答案注入成功，所以那是**下限**不是全程），画面由
						`HUDLayer/SynthesisPanel`
						这个静态节点承载，面板自己只管显隐与回调。ESC 收它（走 `pause`
						不是 `ui_cancel`，本工程 InputMap 里没有后者）。**收面板的责任在
						`World3D._on_synthesis_choice()` 那一处**，不是散在按钮回调里——
						`synthesis_choice` 是公开信号，定妆照脚本和以后的自动导览都走不到按钮
  QualitySettings.gd    画质档位（autoload）：低 / 中 / 高，玩家在暂停面板里自己挑。
						**桌面默认 high**——全部回归脚本量的都是那一档，低档等于让三十多条
						回归在不知情的情况下量一个缩水的世界；Web / 移动端默认 low。
						三档动的只有两样：太阳 `shadow_enabled` 与草皮/行道树的加载半径。
						三档都**不动 3D 渲染分辨率**（实测 Compatibility 下
						`scaling_3d_scale` 反而更慢，多一条全屏 blit 通道）。
						高档那两个半径写的是 -1 = 不动、沿用 `target_radius()`，而
						`apply_to_world()` 把 -1 落成 **0**（不是"不写"）——不写的话
						override 是**粘的**，玩家在低档下把世界建起来再切回高档，
						按钮写着「高」而下一趟的草皮还是 70m。
						**故意没搬**（REF 原型里有）：帧率触发的自动降档，和
						`Engine.max_physics_steps_per_frame = 4`——后者是用来压一条**至今
						没定位**的间歇性段错误的，而它本身会改 `_process` 与
						`_physics_process` 的相对频率。理由写在文件头里
  PausePanel.gd        暂停面板。**「结束这一趟 · 收下明信片」下面那一行**
						（`_make_tier_label()` / `_refresh_tier_label()`）报的是
						**此刻按下去会拿到哪一档、离完满还差几次到访**——
						这一行原来压根不存在，屏上只有一个按钮，玩家在按下去之前
						无从知道按下去会拿到什么，而 `PostcardVariant` 的前四档
						（初旅/探索者/朝圣者/大师）全成了走不到的死代码。
						**它跟着 `_finish_btn.visible` 显隐**（零碎片时那张卡
						什么都没有可写），而**跟着语言走**（`_apply_language()`
						末尾重算一次；档名是五个玩家看得见的词，停在中文那一侧
						等于英文界面里这一行还是半个中文）。
						`custom_minimum_size.x` 是必须的、不是排版洁癖
  PostcardVariant.gd   明信片五档：`TIER_KEYS` / `tier_count()` /
						`tier_name_key()` / `visits_to_full()`。**完满是唯一按
						次数分的那一档**（五站各 `MAX_VISITS_PER_STATION` 次），
						`visits_to_full()` 现算自存档、不许是另一个手抄的数
  Localization.gd       i18n。**`tier_0..tier_4` 五个档名中英各一份，
						而"五档"这件事原来只活在代码注释里**——玩家在游戏里
						一次也读不到自己拿到的是哪一档，README 还写着"分四档"

assets/
  bike.glb       玩家那辆自行车（**在 assets/ 根下，不在 models/ 里**）。
				 World3D._build_bike() 按 BIKE_SCALE=0.012 整体缩放，本地 AABB
				 50.7×114.5×198.1 → 实车 1.37m 高 / 2.38m 长。
				 正后方看它正投影成一根竖条，所以相机必须横向让开——见
				 Player3D.CAM_SIDE 与 tools/verify_camera_bike.gd
  fonts/         LXGWWenKai (中英文 fallback)
  models/        bush.glb / tree.glb / station_*.glb（**没有 bike.glb**）
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
  verify_asphalt_shader.gd  路面着色器回归，**判据全部读源码文本**（`--headless`
						用的是 dummy renderer，**不编译着色器**，所以语法错和观感错在
						无头下都静默通过）。守的是一条已经真实发生过一次的缺陷：
						`edge_line_color` 这个 uniform **声明了整整一个项目、从来没有
						被任何一行读过**——它在着色器里合法、没有任何报错、也没有任何
						回归会红，而 CLAUDE.md 那一节正写着路面有"双黄虚线"，于是
						**文档和代码各说各的，两边都绿**。所以头一条断言是"声明了的
						uniform 被 fragment() **真的读过**"，不是"声明在不在"（那正是
						它本来的样子）。另有：边线贴着沥青外沿内侧且位置从
						`road_half_width` 推（不许写死米数）、它是**实线**（不跟中央线
						的 dash）、`plaza_mode` 下一律不画、两个线的默认色够亮且属
						同一族白、以及**着色器里的宽度默认值 == `RoadBuilder` 的常量表**
						——后者走 `get_script_constant_map()` 读引擎**求值之后**的那份，
						因为 `ROAD_HALF_WIDTH := ROAD_WIDTH * 0.5` 正则会读到那个 `0.5`，
						量的是"除数是不是 0.5"、恒绿
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
						且每行多边形都能展开成有限坐标
						+ **五件乐事各在自己的地方，琴弦顺着琴身长边**：五个小游戏引用的
						主题常量必须是自己那件（抄错下标就串了地方，而 headless 下
						`_draw` 一笔不落、没有任何像素断言能看见）；琴的命中区必须
						宽 > 高，量的是 `_string_rects()` 这个不碰画笔的纯函数
						+ **三次到访轮换五件乐事**：首次到访拿到的还是这座驿站自己的那件
						（拿真实的 road_data 逐格对拍，不许靠抄一份表蒙对）、同一座连着
						三次不重样、15 局里每件正好 3 次）
						+ **第 6g 节三局小游戏的画读不读得出自己的标题**（云的轮廓不是
						多边形：尖角不到顶点数的三分之一、八边形是 8/8，且底边是平的；
						竹身是收分的不是 12px 等宽条、竹节从下往上排、砍倒那截横向
						伸进自己那一列；琴有 13 个徽位、排在中间两根弦的空档里、
						不铺满全长，标题点了名「古琴」）——四处都做过删除突变
						+ **第 6h 节进度条把门槛画出来了**（刻痕跨在条**外**、落在条
						**里**、比条高、字里报的数和条上刻的是同一个、门槛不贴两端；
						茶另报一句还差几秒；竹 5 格不叠且占满整条、格缝按宽度取
						所以换分辨率还是同一个比例；**刻痕那个数字放得下**——
						`get_string_size()` 量的框宽 ≥ 字要的那条）。前三条是**读源码
						文本**的：几何量的是纯函数，量不到画笔有没有真的去调它
						+ **第 6i 节取消按钮不穿警报红**（三档色都读作中性：饱和度
						≤0.25 且红通道比另两路最多高 0.10，而产品里那圈边界警告红
						是 0.84 / 0.50——**拿真警报当尺子**，不是拿"不是那个红"当
						判据；底板不透明；「取消」在**自己那块底板**上 ≥4.5:1、
						边框对底板 ≥3.0；**字形盒**整个在按钮之内；按钮在屏内、不贴
						边、换 1080p 仍贴右下；**五个**画笔都调共用函数、热区没抄
						第二份矩形、**竹的热区判在"当成砍"之前**）。又是五条
						**读源码文本**的
						+ **第 7b 节「回访那一屏说的话」**（`RevisitNote` 四句两两不同：
						「第几次」和「绕没绕圈」是**两件独立的事**，少任一半就塌成
						两句；四句中英都在且不逐字相同；`joy_key` 落到 `fragment_%d`；
						外加**六条读源码文本**——面板正文/底行真的调了那两个纯函数、
						底行报的是 `_last_joy_slot`（这一趟**真玩过**的那一件，不是
						现算的）、`_is_revisit` 判的是「有碎片**且**收过了」而不是
						「到过几次」（后者会把 13 座普通驿站第一次路过也写成回访）、
						`_lap_index` 真的从里程算、**切语言走的是同一对函数**）
  verify_interact_latch.gd 交互闩锁 / 对白抢占回归（郑铎在播时按空格不许开打卡、
						setup() 顶掉一轮对白必须放出旧等待者、被顶掉的郑铎戏自己清
						_villain_playing、回访不再重播小游戏/谎报碎片、
						**反派戏期间脚下的圈不许还在推销打卡**、铺子仍能开、
						**驿站占地不许骑进去**（半径全部小于打卡半径、从站心放开要真
						被摆出去、满速 15m/s 撞 3 秒钻不进去、撞完车要慢下来）、
						**第 9 节反派戏的落点与排队**（贴着碎片站不起播且 armed 留着、
						骑开就放、入场提示带角色名、镜头收束、整场推完三样都还回去、
						阈值一口气冲过时一次只放一场、再骑两站才轮到下一场）、
						**第 10 节集齐二选一面板**（走真实 `check_in()` 推到集齐 →
						面板弹出来且世界冻住、两个按钮都在屏内不叠且都有焦点、
						面板开着时脚下的圈不画、「再骑一圈」把操纵权和相机还回去而
						`_all_done` 仍是 false、回访不重弹、**直接 `emit()` 信号也收得掉
						面板**；末尾另有两条"这一节真的跑完了"的钉子）；
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
						+ **末节「站名牌」**：牌子挂在**量出来的**屋顶上方
						（`World3D.label_y_for()` 是 static，无头回归直接调它）、
						净空 ≥1m、字身在 18m 那一档 ≥12px，
						外加两条**读源码文本**钉住画笔真的调了那个函数 / 字号
						走的是常量而不是又一个字面量（四条都做过删除突变）
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
						入账 toast 不重排顶栏、叙事脉冲冲上/退回、
						**第 9 节顶栏衬底在最坏背景（正午的天）上 ≥4.5:1 且实底段
						盖住整条文字行盒**、
						**第 10 节顶栏不许留死区**（HBox 一直伸到按钮排左边 16px、
						「下一处」和按钮排之间没有空档、塞一串长字进「下一处」
						挪不动旅币/心神也挪不动它自己的右沿））
  verify_minimap.gd       小地图碎片站回归（**沿途 321 个采样点上小地图高亮的
						必须就是顶栏「下一处」报的那颗**；判据统一走
						GameManager.fragment_station_needs_visit()、**收过 ≠ 不用再去**
						（还欠到访就仍然指人）、五座全刷满才真的不指人、
						普通驿站不冒充目标、顶栏那份 MAX_VISITS 副本不许漂；
						第 9/10 节走真实 check_in()：**集齐是中局不是终局**，
						集齐后整圈三处指示器仍一致且顶栏不空、站到每座碎片站前
						顶栏与脚下的圈报同一个"还差 N 次"、刷满了才 _all_done；
						第 10 节末尾另钉**刷满之后顶栏那一行不是空的**，
						报的是 `hud_all_done` 那句收尾）
  verify_far_ridge.gd     远景山线材质回归（三层都 disable_fog、半径都在地形之外、
						颜色按距离递淡）—— 颜色本身只有 lookdev_horizon.gd 能判
  lookdev_horizon.gd      远景山线四张定妆照：路面视角 / 地形高点 / 逆光 / 高空
						（**不能加 --headless**、**不能加 --quit-after**）
  verify_day_cycle.gd     昼夜切换回归（第二圈门槛、太阳**方向**跟着降、
						ProceduralSky 天色真的走了、白昼档没被顺手改掉、
						dusk_began 只发一次；顺带断言"场景自带的天空是空的"）
						**外加"天为什么曾经是一整片"那两条成因断言**：`fog_sky_affect`
						必须为 0（场景雾不许画天），且白昼那档在**线性空间**里的纵向反差
						≥ 0.50（常量是按 sRGB 写的，换算前按 sRGB 算出 0.39，看着
						已经很够，而 AGX 压的是线性那一头，画面上是一片平）
  verify_quality_settings.gd 画质档位回归（六节 48 条）。守六件事：①**三档的代价
						单调**（把高档那个 -1 解析成 `target_radius()` 的生效值再比——
						拿 -1 直接比的话 `低 < 中 < 高` 恒不成立，而那不是产品坏了，
						是这一格故意不落数字）；②桌面默认 high；③**档位真的落到世界上**，
						量的是 **setup() 之后的 `_radius`** 而不是 `radius_override`
						那个字段——字段写了而 setup() 没读、或者被 `target_radius()`
						盖回去，都属于"接线断了而两边各自都绿"；淡出带量的是材质上那个
						`fade_end` 参数（压根没有成员变量，且每帧被 `set_fade_for_camera()`
						按相机高度外扩，所以要先显式调一次 `apply_ground_fade()` 再读）；
						④中途切档只有阴影当场生效、植被半径下一趟，所以面板那行提示必须
						在，且**切回高档时 override 要让位回 0 而不是粘在低档那个数上**；
						⑤**落盘闸**：`persist_enabled=false` 时存档一个字节都不动，
						**外加一条正对照**（闸开着时确实落盘）——只测"闸没开"的话，一个
						从来就不落盘的 `set_tier` 也能让那条绿一辈子；另有一条**读源码
						文本**的判据：`set_tier` 的**参数表里一个 `=` 都没有**（第一版找
						的是 `"persist ="` 这个子串，而带类型的默认值长成
						`persist: bool = true`，中间隔着 `: bool `，那个子串压根不存在，
						于是把默认值写回去照样绿）；⑥面板那一列在 1280×720 / 1280×1080
						**中英各一遍**下装得下（英文那句才是卡边的一份），且画质按钮键盘可达
						（`focus_mode` + 真的在按钮排里）。**四个突变都做过**：世界不推
						档位 → 4 条红 / 参数表加默认值 → 1 条红 / override 改回"只在 >0
						时写" → 2 条红 / 提示行去掉最小宽度 → 4 条红
  verify_settings.gd     设置面板回归（八节 127 条）。守八件事：
						①**静音就是音量 0**（不是另一个布尔），取消静音回到玩家
						自己那一档而不是 100%，顶栏「♪」按钮与滑杆读的是同一个状态；
						②**量的是 `AudioStreamPlayer.volume_db` 而不是 `_bgm_volume`
						那个字段**——字段写了而没人读，两侧各自都绿；顺带钉住
						`PAUSE_DUCK_DB` 是**相对**的（第一版 `set_paused_bgm()`
						写死 -18 dB，玩家把 BGM 拉到 20%（约 -20 dB）时**暂停反而
						变吵**）、音量 0 落成有限的 `SILENT_DB` 而不是 -inf；
						③`user://settings.cfg` 上有**两个主人**（`AudioManager`
						的 `audio` 段与 `QualitySettings` 的 `video` 段），两边都得
						读-改-写，各钉一条"写完另一边还在"**外加一条正对照**
						（`resolution=2` 真的读得回来）——只钉"没被抹掉"的话，
						一个从来不写的 `ConfigFile` 也能让那两条绿一辈子；
						④画面档位是纯函数（`resolution_size()` /
						`resolution_allowed()`），且"至少有一档因为屏幕放不下被拒"
						这条在无头下**不恒真**（`_usable_size()` 固定 1152×648）；
						⑤三道闸读**源码文本**：`persist` 参数表里一个 `=` 都没有
						（不是 `contains("persist =")`，带类型的默认值中间隔着
						`: bool `，那个子串压根不存在）、`window_set_size` 排在
						`window_set_mode` **之后**（反过来 FULLSCREEN 会抹掉刚设的
						尺寸）、`video_available()` 里排除了 web/mobile；
						⑥键位表**只有一个出处**（见下面陷阱清单里这一轮新记的那条
						"文本判据量到的可能是注释"）；⑦设置面板在真实 World3D 里：
						「?」开得动、关得掉、暂停菜单那行进的是**同一个实例**、
						滑杆**对齐当前真音量**且拖得动、暂停菜单里不再有那三个
						静音按钮；⑧关闭按钮整个在屏内（中英各一遍）。
						**十二条突变一个一个撤，全部咬住**
						（`python tools/mutate_settings.py`，它自己会先跑一遍基线，
						基线不干净就直接退出——不然下面每一条都分不清"没咬住"
						和"没跑"）：断「?」接线 / 暂停压低退回绝对值 /
						取消静音退回 100% / 落盘退回覆盖写 / 分辨率排在窗口模式之前 /
						给 persist 加默认值 / 两处键位表退回手抄 / 注册退回逐行手抄 /
						滑杆钉死建面板那一刻的值 / video_available 放行 web / 屏幕放不下
						也照样设窗口
  verify_provenance.gd   资产来源清单回归（16 条）。`PROVENANCE.md` 是一份**决定能不能
						收钱的凭据**，所以它必须有对拍，否则它就是第二个事实来源：
						新增任何一个 `assets/` 下的文件而没在登记表里按**相对路径**逐字
						登记 → 红；登记表上留着一个已经删掉的文件 → 红；表行数与实际文件数
						不等 → 红（**两个方向都要**，只查少的那头会漏掉"清单指着空气"）。
						另一组守的是**内部清单 vs 对外署名文件**：`CREDITS.md` 是随发行物发出去的，
						未核实的项如果只停在 `PROVENANCE.md` 里，对外那份就成了"只字未提"——
						那比写「待核实」糟得多，所以「对外报出的未核实数 ≥2 且不多于内部」两条
						各钉一头。**正对照先摆**：走目录那个函数自己可能一个文件都列不出来，
						所以第一条先断「真的列出了 ≥15 个」。四个突变都做过：删一行登记 → 红 2 /
						把登记表里一个文件改成不存在的名字 → 红 2 / 把 CREDITS 里的「待核实」
						全替换成「已核实」→ 红 1 / 删掉 LICENSE → 红 3。
						**它故意不判断许可条款对不对**——读不了 Tripo 的服务条款，也追不到
						那个 `10489_bicycle` 是谁，剩下的是人的活
  probe_water.gd         一次性探针：逐只碗报自由板 / 水面盖住碗的百分比 /
						各方向水面半径 / 有几个角找不到岸。**改碗的参数先跑它**
  verify_water.gd         三处水回归（水体挂在那三座名字承诺了水的站上、水面
						压在土里、**每个顶点**底下都是湿的、水不压路、
						碗没压到行道树、**水面盖住碗的一半以上**、全场统一水位）
  lookdev_water.gd       三处水定妆照：三处水边平视 + 湖湾俯瞰 + 正午/黄昏同机位
						A/B（**不能加 --headless**、**不能加 --quit-after**）。
						每张拍两遍：一遍把水换成不受光的洋红量几何、一遍真材质量观感
  lookdev_stations.gd     驿站布局定妆照 23 张：5 座代表驿站俯拍 + 全路线高空 +
						骑行视角一张 + **十六座站逐个从骑行视角拍**
						（**不能加 --headless**、**不能加 --quit-after**）。
						第 08 段量的是**每一座站在骑行那一档有没有报出自己的名字**
						——16 座站只有 12 个模型、三对还是同一个 GLB，
						而站心离路心线 18m、`STATION_PASS_RADIUS` 又是 15m，
						所以这一档就是玩家在路上看它们的全部视角。
						取样框**一处都不问 `Label3D` 节点**（见陷阱清单里那一条）
  check_all.sh            **一条命令跑完全部无头回归，打印一张表**（改完东西
							不知道该跑哪几条时跑这个；它认 7 条要开窗口的，不列进
							默认轮次）。判据是「有没有 [FAIL]」加「有没有打出断言」
							两件事，**不信退出码**——抛异常的回归退出码是 0。
							跑之前会把 `res://layout.json` 存一份、跑完原样还回去
							（回归往这个产品文件里写测试数据过一次，见陷阱清单）。
							`--window` / `--lookdev` 两个子模式。
							**红的那一条会复跑一次再定性**：有几族断言量的是墙钟
							（草皮的铺满预算与最慢帧），量的是机器不是代码——
							2026-10-04 实测整轮里 6376ms / 125 tick、空机单跑
							721ms / 42 tick，慢 9 倍，而当轮没有任何一处改动
							碰得到那几行。复跑才过的照记 `PASS~`，**并在摘要里
							单独列出来**（分开之后信息不许丢）；总断言数只累计
							**最后一次**那一遍，头一遍是被噪声污染过的样本
  check_all.ps1            上面那条的 **PowerShell 等价物**，判据逐条照抄。
						存在的理由：Windows 上 `bash` 有两个东西——装了 Git 的
						是 Git Bash（看得见 D: 盘），**没装 Git 的是 WSL**
						（看不见本机磁盘），后者会让上面那几条安静地跑完、
						什么都不输出。.sh 开头现在会当场认出 WSL 并退出（exit 3）
  mutate_honesty.py       诚实性那一族的突变驱动（十二条一个一个撤）。量的是
						**文档不许说谎**（README 报的回归/出图/探针条数、
						`NEEDS_WINDOW` 的长度、两份预算注释里的三个数）+
						**完满必须明示**（暂停面板那一行、`visits_to_full()`、
						五档档名表、中英档名两两不同）。沿用
						`mutate_settings.py` 的两条纪律：**量具的输入必须是这一遍
						的输出**（每条突变都真起一个 Godot 进程、只读它这次的
						stdout）、**基线不干净就当场退出**（不然每一条都分不清
						"没咬住"和"没跑"）。另加一条：那几条回归需要
						`--quit-after`，因为**判据在它自己要抓的那个缺陷上会把自己
						搞崩**（突变把 `_tier_label` 换成 null 之后协程中断、
						`quit()` 走不到），而"挂住"在驱动眼里和"红"不是一回事
  verify_road_verge.gd   路肩软边界回归（21 条）。守三件：①**画出来的那道线就在
						推你回来的那道力所在的那条线上**——剖面里最亮的一列的距离
						必须 == `SOFT_BOUND`，而 `SOFT_BOUND` 是 `build()` 的**参数**
						（外加一条读源码文本的「`build()` 真的接了这个参数、代码里没有
						第二个 12.0」，搜之前先 `_strip_comments()` 剔掉注释行，否则
						红的是本文件开头那句解释本身的散文）；②**那道带子是一道「线」
						而不是一段路的末梢**（最亮的一列 + 两侧各一个台阶），
						**外加两条读源码文本钉住真正的那两个 bug**（`ARRAY_NORMAL`
						与 `vertex_color_is_srgb`）——见下面陷阱清单里
						「反照率对比度不是渲出来的对比度」；③**砾石带两头都不自己造
						硬边**（外沿落在地形自己的取值范围内、内沿接住沥青外沿）；
						④**中间三档不许调回土**（`GRAVEL`/`PACKED`/`LINE` 通道差
						≤0.06，配一条拿 `GRASS`（0.242）当尺子的正对照——
						这一条量的是「有没有调回土色」，而「好不好看」只有定妆照能量到，
						所以它钉的是一个**可复算的通道差**）。
						**这一族量不到「看不看得见」**——无头回归量不了渲染结果，
						那一条在 `lookdev_verge.gd` 的像素里
  lookdev_verge.gd      路肩软边界的定妆照 + **像素判据**（骑行视角 / 路心平拍 /
						斜看 / **正交俯拍逐像素剖面**，存 user://lookdev_verge/）。
						量的是**渲出来的那一列像素**：亮峰必须落在 12.0m（±0.75）、
						不顶到白（≤0.92）也不读不出来（≥0.55）、两侧各有一个台阶、
						外沿与地形之差 ≤0.10、**另一侧同形**（正对照）、
						路面上真的有一道比砾石带亮得多的白标线（正对照）。
						**不能加 --headless、不能加 --quit-after**
  verify_road_steles.gd   路碑回归（四块碑都建出来了、刻的真是 188、落点不压沥青
						也不糊在驿站上、**石板正面朝着路且字在正面那块宽板上**、
						朝向不是按世界原点算的、四句浮字中英都在、
						**骑到路到碑的视线上没有行道树**、路过只浮一次停着不重弹、
						路过碑不发旅币不进 _nearby_* 不画打卡圈）
  verify_crossing_mark.gd 交叉点「路自此复」那块碑的回归（40 条）。落点、题字、
							刻线、**刻线刻的真是这条路**——逐点量**刻出来的**顶点与
							环路重合（不是量数据源，量数据源的话把刻线换成一个圆
							全绿）、**刻出来的是个 8**（两瓣 x 区间交叠、
							z 区间只在交叉点相接）、**石台没有把题字和下瓣吃掉**
							（量的是离**石台顶**多高，不是离地 y=0）、碑面心在人眼
							那一档。四个变异都做过：朝向反 180° / 刻线换成圆 /
							落点挪到沥青上 / 写死旧的那个 face_lift
  verify_home_base.gd    主角的家回归（11 节 53 条）。**落点全部重算，不信
						`HomeBase` 的返回值**（`site`/`road_pt` 拿来做输入，不拿来做
						判据）——否则把 `site` 直接改成一处合法地界，断言照样全绿。
						守十一件：落点合法（离广场 ≥30m / 离驿 ≥20m / 贴地 / 高程
						≥-1m / 四角高差 ≤0.8m / 离中心线 ≈15m / **靠路那一沿在
						`SOFT_BOUND` 之外**——那道粉线不许从屋子里穿过去）、
						13 个子节点一个不缺、门朝着路、三份常量不许漂
						（`HOME_PASS_RADIUS` / `STATION_LABEL_*`）、
						行道树让开、路碑 ≥14m、**推出点仍在圈里（门真的骑得到）**、
						正对照：满油门平衡点约 20.7m、不是第 17 座驿站、小地图钉在
						真落点上、「到家」那一句边沿触发，末尾一条**断言数下限**
						（`HOME_MIN_CK` 34）钉着"整份真的跑完了"
						——缺一节的话那一节会静默不跑而汇总照样全绿。**七个突变
						一个一个撤**（CSG 属性名打错 / 树让位 / 硬推出 / 边沿触发 /
						`HOME_OFFSET` / 门牌字号 / 小地图钉）；其中 `HOME_OFFSET`
						那个突变**第一次是绿的**——原来那条拿实测距离去比
						`HC["HOME_OFFSET"]`，等于拿常量比它自己，改为断**产品后果**
						（近沿必须在 `SOFT_BOUND` 外）之后才咬得住
  lookdev_home.gd        家的五张定妆照：路心线上的骑行视角 / 门牌近景 /
						沿路 30m / 俯视 / 带小地图那一档
						（**不能加 --headless、不能加 --quit-after**——门牌那个
						「家」是 Label3D，headless 不生成字形，无头回归只能量
						`font_size`/`pixel_size`/行宽这些**数字**，量不到"那个字号在
						15m 上还剩几个像素"）。门槛 12px 取的是**站名牌那一档的实测值**
						（家和驿站是玩家一路上并排看到的两块牌子，同一把尺子）；
						实测 29.2px。小地图那枚钉**绝对数与正对照成对写**：把
						`_draw_home()` 删掉之后"钉画出来了"那条一度仍读到 26 个
						米白像素（`NEXT_RING` 那圈白环正好落进同一阈值），
						**取样框收小到钉自己那一块之后撤钉读 0**（实测带钉 73）
  lookdev_crossing.gd     交叉点 9 屏定妆照：200m 俯视 / 50m 斜看合并处 /
							骑进去 / 骑出去 / 垂直俯拍 **+ 碑的四张**（碑前低头 /
							正对碑面 / 骑行眼高 / 高空）
							（**不能加 --headless**、**不能加 --quit-after**——
							刻线是自己拼的 ArrayMesh、题字是 Label3D，
							headless 下两者一笔都不落盘，而"刻出来的是不是个 8"
							和"字画没画出来"只有图能判）
  lookdev_steles.gd       路碑定妆照：三块完好碑的近景 / 被凿平那块 / 隔着路面 / 俯视
						（**不能加 --headless**、**不能加 --quit-after**——
						碑面的「188」是 Label3D，headless 不生成字形，
						"字到底画没画出来"只有这里能判）
  lookdev_journey.gd      玩家视角 25 屏流程实拍（标题→操作说明→序章→骑行→
						**04b 反派戏打断的入场提示与镜头收束**→打卡提示
						→**贴脸 1.2m（提示文字最容易掉出屏外）**→**回访「再访 · 还差 N 次」**
						→**路过风景驿浮的那一句**→驿站对白→5 个小游戏→驿铺→
						**正午/黄昏同机位两张**→集齐→**集齐二选一**→**再骑一圈**
						→**13d 五座都走满之后顶栏**（那一档只活 2.5 秒，
						`_on_all_maxed` 锁死到跳结算页之间，所以必须在这窗口里拍）
						→终局二选一→明信片→背面写字），存 user://lookdev_journey/
						（**不能加 --headless**、**不能加 --quit-after**）
						第 13 节自己上膛第 0 场反派戏——因为整份脚本末尾才把
						`seen_villain` 顶到 3，中间那一段本来一场都拍不到，
						而入场提示是玩家看得见的字，不该只有数字守着
						**12b/12c 之后那五条量的是天带的像素**，而天色是本工程
						最典型的"数字全绿而画面是坏的"：`ProceduralSkyMaterial`
						每个旋钮都设了、`DayCycle` 的常量全对、`verify_day_cycle.gd`
						逐条量过颜色和方向——而天是一整片灰蓝纸。五条各管一件：
						纵向落差（≥12%，量的是"有没有层次"）、正午那行是不是蓝
						（**取样行是 `SKY_HUE_ROW` 而不是 `SKY_ROWS` 的末行**——
						末行落在设计成近白的地平线霾上，量到的是霾不是天）、
						黄昏那行红有没有压过蓝（量的是"换了颜色"而不是"降了曝光"），
						以及衬底底下那一带比 `verify_mood_mask` 第 9 节声明的最坏背景
						暗不暗（跨脚本的一条：那边无头、量不到像素）
						**`04_ride` 之后那两条量的是底栏五格「未收时看不看得见自己在收集
						什么」**，而这一族前两版判据都量错了对象，两次都**安静地报一个
						很小的数而没有红**：①「40×40 框里饱和度 ≥0.10 的像素占几成」
						——槽底板是半透明的、底下就是 3D 场景，量到的是背景，把图标
						整个退回纯灰它照样报 57.9%；②「盘内半径 15px 的平均色两两差
						≥0.05」——图标只有 1~2px 的细线，摊进 700 多个像素里稀释到
						0.004，两两差只剩 0.025，是尺子太粗不是产品坏了。现在取
						**两条通道的并集**：盘外 23~26.5 那一圈**实心色盘**的**颜色**、
						盘内 r≤15 的**墨掩膜形状**。两条都必须是"整片"而不是"平均"
						（一个像素就是一个值，不存在稀释）。取样用 Slot 自己的
						`get_global_rect()`，**不许拿 120px 间距手算**——`HBox` 是
						`alignment = 1` 而 Slot 的 `custom_minimum_size` 才 120，
						实测间距 124、盘心 (392/516/640/764/888, 660)，手算那版
						量到的是隔壁那格。**并集的每一路都要配一条"这一路真的在承重"
						的正对照**（≥3/10 对靠颜色分开），否则环整条退成灰它照样全绿。
						墨掩码有个坑：`lums.sort()` 之后按 k 生成掩码比的是**亮度分布**
						不是形状，报出 0.014 的"形状差"——掩码必须回到空间顺序上填
  verify_economy.gd       旅币/背包/心神/存档回归 + 预算按公式重算 + **里程不许出现在
						任何玩家可见文案里**（含中文「公里」与英式 kilometre）
  verify_save_robustness.gd 存档健壮性回归（7 节 64 条）。第 1 节把**平台前提**钉成
						断言：`ConfigFile.load()` 对截断、纯垃圾、空文件**一律返回 OK**
						（配一条"好存档也 load 得动"的正对照）——旧版 `_load_save()`
						判的就是这个返回值，于是崩在写一半的存档"读档成功"、版本号
						取到 0、走 `_clear_save()` **把玩家整趟行程删掉**。第 3/4 节量
						原子写与崩溃恢复（**恢复判据是"拿到上一份好的"，不是"没炸"**，
						后者靠把回退删掉也照样绿）；第 6 节的夹取判据量的是玩家下一帧
						真的读出来的那几个量（到访次数 / 「已过 n 驿」/ 明信片档位），
						外加一组"合法值不许被误伤"的正对照
						**测试摆弄不许走 `reset()`**：它会 `_clear_save()` 把被测的文件
						删掉，于是"存 → reset → 读"量到的是"存档被自己删了还能读回来"。
						用 `_wipe_memory()`（只清内存不碰盘）
  verify_shop_panel.gd / verify_shop_world.gd  驿铺面板 / 真实 3D 世界里的购买链路
  verify_postcard_ending.gd 明信片纸面分级 + 终局二选一 + **重新开始前的「这一趟」回执**
						（keep/break 的后果必须在**正面**上、**回执每一条都要对着存档逐字核对**）
						+ **第 3c 节正面顶部那张路线图**（16 驿全在框内、五座碎片站不叠点、
						买了信封方框要让开折角、图上那几行字现算自存档）
						+ **第 3d 节抬头右半那列五件乐事**（右沿不留死区 / 不压左列的字 /
						每行放得下——次数是右对齐画的，`draw_string` 的宽度是**裁切宽度**，
						字比列宽整段被切而尺寸断言全绿；中英 × 900/1920 四种组合，
						外加一条读源码文本的「画笔真的调了 `_draw_joys_column`」）
						+ **第 3e 节背面正文**（字号是**按这块纸自动定的**，判据量的是
						「卡片字号 × 预览宽 / 1920 ≥ 12px」这个玩家在编辑器里真的
						读到的高度；另含一条读源码文本的「画笔真的调了
						`_message_font_size`」——把 `var font_size := 36` 写回去，
						几何那十几条全绿而预览里那行字又变回 8px）
						+ **第 4 节那五件乐事底栏**（内容下沿 ≥ 屏高的 78%——**排除 `shade`**
						那层铺满全屏的 ColorRect，骨干子节点数 16、五个图标控件 + 五个名字、
						云茶琴竹禽同序、相邻名字不叠、整排在卡片之下；外加两张卡的
						标题齐平 ≤1px 与行盒等高——齐平那两条**必须摆在点击之前**，
						`_choose_ending()` 把那几个成员全置成 Nil）
  verify_endcard_back_editor.gd 背面写字编辑器体检（三处会各自中断执行的老伤：
						不存在的 `Control.PRESET_CENTER_WIDE` / `Control.bg_color` /
						`TextEdit.max_length`；断**构成**不断总数——遮罩一层、
						动作两个、输入框一个、预览一块；子控件不叠、
						输入真读进 `_back_text`、超长截断到 200 字；
						1280×1280 与 **1280×720 项目真实分辨率**各量一遍）。
						**第四轮 P1-3 补的那一节量的是那两个按钮**（原来两个都是
						裸 `Button.new()`，底 0.1 灰 alpha 0.6、`border_width = 0`，
						合成到 0.05 的遮罩上**1.07:1、一条边都没有**）——
						**病在边界不在字**：默认按钮字色本来就亮（12.9:1），
						所以判据断的是边。四条 + 一条正对照（拿引擎默认那档自己
						算，它 1.07:1）。**「有一条边」与「边线的对比度」必须成对写**：
						把 `_style_back_button()` 两个调用点删掉，那两条对比度
						**照样全绿**——默认 `border_color` 是浅灰而
						`border_width` 是 **0**，边根本没画出来；
						对比度量的是"画出来会有多清楚"，`border_width ≥ 1` 量的
						才是"它在不在屏上"
  lookdev_postcard.gd      明信片 19 张定妆照（四档纸面/满配/背面三态（含**写满 200 字
						那一档字号**）/蜡封三态/未竟缺格/二选一/揭示/**回执中英各一张**）
						（**不能加 --headless**、**不能加 --quit-after**）。
						`10_终局二选一` 后半段多出**三条像素判据**：底栏那一行真的挂着
						五个图标控件 / **每个图标都真的画出了自己那件的颜色**（在图标
						rect 内按 ±0.22 逐通道找 `Postcard.FRAGMENT_COLS[i]`，
						每件 ≥8 像素）/ **没有一件的笔画压到它自己名字那一行**（同色
						像素落在名字 Label 的行盒里必须 **0**）。后两条只有像素量得到：
						`FragmentIcon` 缩放由**框宽**决定而设计坐标到 ±24，于是框一
						开方，竹的梢就压在「竹」那个字上，而**控件几何全绿**
  measure_cold_start.gd    冷启动逐段墙钟：按「开启旅程」→ 世界起来 → 操作说明 → 能动。
						跑两遍：一遍连打（量机器强加的等待）一遍人读节奏（量内容长度）。
						判据钉的是 `GiftBox` 的**常量表**不是墙钟——把过场调慢一秒，
						墙钟那条照样绿。**不能加 --headless**
  play_newcomer.gd        以「完全不了解这个游戏」的玩家身份真玩一遍，量**一趟有多长**：
						从点「开启旅程」到集齐二选一面板弹出来。它跑的是玩家的那条路
						（`StartBtn` → 操作说明 → 序章 → 沿路骑行 → 打卡 → 对白 → 小游戏），
						油门转向全走真按键事件。**不能加 --headless**。
						五条是这套尺子的量法陷阱，见下面「已知陷阱」里那几条；
						五个小游戏的答案是 `FORCE_MINI_GAME_SUCCESS` 注入的成功，
						所以报出来的是这一趟的**下限**（现在 186.6 秒），不是全程
  verify_demo_path.gd      评审那条 90 秒演示路径（**不能加 --headless**：演示走
						`Input.parse_input_event`，dummy display server 不做焦点路由）。
						两节：第1节秒级（`enter_demo` / `fill_finished_run` 摆出来的存档
						必须真的算成完满评级、`reset` 收回演示模式、标题页中英按钮的秒数
						不许和 `DEMO_BUDGET_SEC` 漂）；第 2 节真的点「演示 · 90 秒」，
						真的骑，量累计里程 / 到过几驿 / **小游戏有没有真的弹出来**——
						后一条是唯一能证伪「DemoDirector 一行都没执行」的判据；
						**外加「收工前那一行交代真的打在屏上了」**（见下面陷阱清单
						里「补齐的那些数得说出口」那条，判据量的是 `_pass_label` 的
						正文而不是某个字段为真）。打印行里那串小游戏脚本名是量出来的
						事实（**62 秒只够停两站，最近那座是禽不是茶**），别当装饰删掉
						断言总数钉在 `EXPECTED_CKS`，中途抛错会静默少跑一半而汇总照样全绿
  web_smoke.gd + .tscn     **Web 导出实测用，不是产品的一部分**。设成主场景导出 Web，
						在浏览器里打开两遍：第一遍走真实 `check_in()` 写盘 + 导 PNG，
						第二遍读回。量的是三件桌面回归永远量不到的事——
						IDBFS 落盘后**重开页面**还读不读得回、`JavaScriptBridge`
						导 PNG 那条 Web 专用分支下载得到下载不到、控制台有没有 Web 报错。
						跑完记得把主场景改回 `res://scenes/GiftBox.tscn`
  generate_ui_sfx.py / generate_mini_game_sfx.py / gen_ambient_audio.py 音效合成
```

## 关键约束

1. **零纹理资产（WebGL 友好）**: 路面 asphalt 用 `assets/shaders/asphalt.gdshader` 程序化生成（颗粒、胎痕、路缘起灰、潮斑、路肩碎石、**中央白色虚线 + 两侧白色实边线**——原来是"双黄虚线"，而代码从头到尾只画过一条白虚线，`edge_line_color` 那个 uniform 声明了从没被读过），地形用 `assets/shaders/terrain_grass.gdshader`（低频色块、中频草丛斑驳、高频麻点、随距离淡出的法线扰动），近处草皮用 `assets/shaders/grass.gdshader` 的实例化卡片。植被 mesh 用 `SphereMesh`+`StandardMaterial3D` 程序化或 GLB。
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

# 资产来源清单与 assets/ 目录对拍（新增/删除任何资产后必跑；秒级）
"$GODOT" --headless --path . --script tools/verify_provenance.gd

# 驿站屋顶暖中性色（材质按后缀命中、必须 duplicate、屋顶 vs 墙的亮度比、贴图模型不受影响）
"$GODOT" --headless --path . --script tools/verify_station_roof.gd

# 心神遮罩 + 顶部经济栏（两档透明度、骑行档可读上限、toast 不重排顶栏、叙事脉冲）
# 注意 --quit-after 单位是帧不是秒，本机 280+FPS，给小了会把脚本掐死在场景加载处
"$GODOT" --headless --path . --script tools/verify_mood_mask.gd --quit-after 30000

# 小地图未收碎片站（沿途逐点核对小地图 == 顶栏「下一处」）
"$GODOT" --headless --path . --script tools/verify_minimap.gd --quit-after 30000

# 远景山线材质（三层都关了雾、半径在地形之外、颜色按距离递淡）
"$GODOT" --headless --path . --script tools/verify_far_ridge.gd

# 昼夜切换（骑满一圈之后天色走到黄昏；含"场景自带的天空是空的"这条前提断言）
"$GODOT" --headless --path . --script tools/verify_day_cycle.gd --quit-after 30000

# 远景山线定妆照：路面视角 / 地形高点 / 逆光 / 高空，存到 user://lookdev_horizon/
# 不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_horizon.gd

# 三处水：先跑探针看碗摆得对不对（自由板 / 盖住碗的百分比 / 各方向半径），
# 再跑回归。改 BASIN_SHAPES / WATER_LEVEL / _best_site 之后探针必须先跑
"$GODOT" --headless --path . --script tools/probe_water.gd

# 三处水回归（水压在土里、每个顶点底下都是湿的、不压路、盖住碗的一半以上）
"$GODOT" --headless --path . --script tools/verify_water.gd

# 主角的家：落点 / 挡车 / 门牌 / 小地图钉 / 「到家」那一句（约 5 秒）
"$GODOT" --headless --path . --script tools/verify_home_base.gd

# 存档健壮性：原子写 / 崩在写一半 / 纯垃圾 / 空文件 / 值越界（约 2 秒）。
# 改 GameManager 的 SAVE_* / _save_game() / _load_save() / _sanitise_* 之前必跑，
# 改完再跑 —— 这一族量的是**盘上那三份文件和玩家下一帧读出来的数**
"$GODOT" --headless --path . --script tools/verify_save_robustness.gd

# 家的五张定妆照，存到 user://lookdev_home/
# 门牌那个「家」是 Label3D，headless 不生成字形 —— 不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_home.gd

# 三处水定妆照：三处水边平视 + 湖湾俯瞰 + 正午/黄昏同机位 A/B，
# 存到 user://lookdev_water/。不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_water.gd

# 玩家视角 17 屏流程实拍，存到 user://lookdev_journey/
# 改 HUD / 标题页 / 商店 / 明信片 / 任何一屏的玩家可见文字后跑这个
# 不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_journey.gd

# 明信片纸面分级 + 终局二选一 + 「这一趟」回执（headless 可跑）
"$GODOT" --headless --path . --script tools/verify_postcard_ending.gd

# 明信片 18 张定妆照（四档纸面 / 背面三态 / 蜡封三态 / 未竟缺格 / 二选一 / 揭示 / 回执中英）
# 存到 user://lookdev_postcard/。不能加 --headless、不能加 --quit-after
"$GODOT" --path . --script tools/lookdev_postcard.gd

# ---------------------------------------------------------------- 一条命令全跑完
# 32 条无头回归 + 7 条要开窗口的（不列进默认轮次，因为没跑的必须明写"没跑"）。
# 这两个数是 `tools/` 下 `verify_*.gd` 的总数减去 `check_all.ps1` 里那份
# `$NEEDS_WINDOW`——**别手抄**，`pwsh -File tools/check_all.ps1` 每次都会把
# 真实的条数打进汇总那一行。
# 不确定该跑哪几条时跑这个；它打印一张给评审看的表。
bash tools/check_all.sh
bash tools/check_all.sh verify_water verify_story   # 只跑指定的几条
bash tools/check_all.sh --window                   # 要开窗口的那 7 条
bash tools/check_all.sh --lookdev                  # 出图看观感（同样要开窗口）

# 没装 Git 的 Windows 上 `bash` 是 WSL，看不见本机磁盘，上面那几条会安静地
# 跑完、什么都不输出。用 PowerShell 版（判据与 .sh 完全一致）：
pwsh -File tools/check_all.ps1
pwsh -File tools/check_all.ps1 -Window
pwsh -File tools/check_all.ps1 -Lookdev
pwsh -File tools/check_all.ps1 verify_water verify_story

# 冷启动逐段墙钟（连打一遍 + 人读一遍）。不能加 --headless
"$GODOT" --path . --script tools/measure_cold_start.gd

# 评审那条 90 秒演示路径（约 90 秒，秒级那节 + 真骑一遍）。
# 不能加 --headless：演示走 Input.parse_input_event，dummy display server 不做焦点路由
"$GODOT" --path . --script tools/verify_demo_path.gd
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
- 修改 `assets/shaders/asphalt.gdshader` 前先在 headless 跑 `verify_road_height.gd` + `verify_crossing.gd` + `verify_asphalt_shader.gd`，改完再跑 `lookdev_journey.gd` 看 `04_ride_骑行中` 的路面（**不能加 --headless**：dummy renderer 不编译着色器，语法错在无头下照样全绿）。`verify_asphalt_shader.gd` 守的是**"声明了却被读过"**那一族：路面标线那几行里曾经有一个 `edge_line_color` 声明了从没被读过，而它在着色器里完全合法、不报错、也没有任何回归会红——**症状是另一个人在文档里写下的一句"双黄虚线"，而不是任何一条断言**
- 改 `FragmentIcon.paint_bird` / `bird_parts()` / `FragmentBar._draw_bird` / `Postcard._draw_bird` 前跑 `verify_postcard_ending.gd` **第 3b-2 节** + `lookdev_postcard.gd`。禽这只鸟**画过三遍**（顶栏底栏、单碎片放大图、明信片五格），原来是**三份**画法、其中两份还是**两套不同的**：底栏与放大图是「圆 + 棍」（读成棒棒糖），明信片是「填实的圆 + **同色的**翅」（两块并成一颗疙瘩）。云那一族是三份抄开的**同一个**算法，禽更糟——玩家一路看着它长大，最后带走的那张纸上根本不是同一只东西，所以现在三处都调 `FragmentIcon.paint_bird` 一个出处。第 3b-2 节钉两件事：①**三处调的是同一个出处**（读源码文本，`_draw` 在 headless 下一笔都不落盘，"两处形状一样"量笔法量不出来）；②**那只剪影本身**认不认得出是鸟——`bird_parts()` 是不碰画笔的纯函数，`paint_bird` 只是把它重放一遍，所以量的是剪影：有尾（甩到左下）、喙是往前伸的尖楔且伸出头外、脚下有栖枝、身子是**扁**椭圆、翅是**留白**、整只装得进 `FragmentBar` 那个 22px 的盘。**翅是留白这一条只有像素量得到**（几何全绿而两块并成疙瘩），`lookdev_postcard.gd` 在 `10_终局二选一` 的底栏量它：亮一截取 0.05，禽实测 **93**，翅改回墨色（或退回旧画法）只剩 **10**（那是眼睛），门槛 60 正落中间；相对量而不是绝对的白，因为底板是深色屏、翅是 0.30 白压在橙上，AGX 之后两色被拉近。另四件实测 云40 / 茶10 / 琴110 / 竹0，所以这条**只断禽**，别拿去当"五格谁最亮"的排序。**写完先证明它会红**（突变一个一个撤）：翅改回 `"c": "ink"` → 无头红 1 条、定妆照红 1 条；`Postcard._draw_bird` 退回自己画一颗圆 → 红 1 条；撤掉栖枝那条 line → 红 1 条
- 修改 `scripts/TerrainBuilder.gd` / `assets/shaders/terrain_grass.gdshader` 前先跑 `verify_terrain_shader.gd` + `verify_road_height.gd` + `verify_crossing.gd`
- 修改 `scripts/road_data.gd` / `scripts/RoadBuilder.gd` 前先在 headless 跑 `verify_8_shape.gd`
- 改 `scripts/RoadVerge.gd` 的任何一处（`INNER` / `OUTER` / `LIFT` / `GRAVEL` /
  `PACKED` / `LINE` / `GRASS` / `verge_profile()` / `_face_normals()` /
  `vertex_color_is_srgb`），或 `assets/shaders/asphalt.gdshader` 的 `dirt_color`
  （**那个名字是历史留下来的，它驱动 4.0→6.5m 的路肩与路缘起灰，而它现在已经是
  灰砾石不是土**——名字还叫 dirt，所以下一个人看代码看不出它改过），
  或 `World3D` 里 `_verge.build(..., SOFT_BOUND)` 那一行之前跑
  `verify_road_verge.gd` **+** `verify_asphalt_shader.gd` **+** `lookdev_verge.gd`
  （后者**不能加 --headless**，也不能加 `--quit-after`）。
  **四个颜色是按"渲出来什么样"定的，不是按反照率定的**：
  量法是正交俯拍（`size = 60m`，比例尺 `图高 / 60`）从路心往外每 0.5m 读一行像素。
  改成砾石之后的实测（2026-10-04）：沥青 0.378 → 白边线 **0.959** →
  砾石 0.494 → **粉线峰值 0.798 正在 12.00m**（内侧台阶 62% / 外侧 84%）→
  另一侧 12.0m/0.787（正对照）。改砾石**之前**那一组是土 0.452 / 峰值 0.780 /
  外沿 0.640 对地形 0.680（接缝 0.040）。
  **改任何一个数都要重跑定妆照看峰值位置和台阶**，
  因为无头回归量不到渲染结果——而那一族前两版的判据量的是**反照率**，
  在一片全白的六米宽水泥地面前**全绿**（详见陷阱清单里那条）。
  **写完先证明它会红**（突变一个一个撤）：删掉 `arrays[Mesh.ARRAY_NORMAL]` 那行
  → 无头红 1 条、**定妆照红 7 条**（亮峰跑到 20m、接缝裂到 0.235）；
  删掉 `mat.vertex_color_is_srgb = true` → 无头红 1 条、定妆照红 4 条
  （峰值从 0.780 涨到 **0.944**——所以定妆照那条「不顶到白」的门槛是 **0.92**，
  写 0.95 时它只差 0.006 就被放过）；
  外侧那一列退回 `LINE` → 红 1 条；`PACKED` 调亮过 `LINE` → 红 2 条；
  **`GRAVEL` 调回旧的土色 `(0.300,0.250,0.170)` → 第 ④ 节红 1 条**
  （这是这一轮新加的那条：它守的不是"好不好看"，是"有没有调回土"，
  而"好不好看"只有定妆照量得到，所以那条判据量的是一个**可复算的通道差**）
- 改 `World3D` 的站名牌（`STATION_LABEL_PIXEL_SIZE` / `_FONT_PX` / `_FONT_PX_SMALL` /
  `_CLEAR` / `_INK` / `_HALO` / `_HALO_PX` / `_add_label()` / `label_y_for()`）前跑
  `verify_stations.gd` 末节 + `lookdev_stations.gd` 看那 16 张 `ride_*`。
  **字高是个乘积**（`font_size × pixel_size` 折成米 × 18m 上的每米像素），
  盯住任何一个因子都量不到玩家读到的那行字有多高——`pixel_size` 原来写死
  0.002、48 的字号合起来只有 9.6cm，18m 上 3.3px，而**没有任何一条断言会红**。
  连带两条：牌子高度是 `label_y_for()` 从**量出来的**屋顶顶反解的（写死一个数
  的话，改一次模型尺寸牌子就埋进亭子里），而 `STATION_GLB_CONFIG` 里那个
  `label_y` 现在**一个读者都没有**，别再拿它当高度的出处。
  **写完先证明它会红**：`STATION_LABEL_PIXEL_SIZE` 退回 0.002 →
  `lookdev_stations` 的「牌子上都真的画出了字」当场红（框缩到 12×4px、笔画 0~6 根）。
  **别拿 halo 加粗当突变**——`outline_size` 从字身向外膨胀而墨核永远画在最上层，
  加粗到 60 也一笔不少（详见陷阱清单）
- 往 `Localization.gd` 加/删 key、改中英任何一侧的文案、改 `road_data.stations` 的站名、
  `event` 或 `dialogue` / `dialogue_en`（**中英是两份手抄的数组，句数必须一起改**）、
  动 `Postcard.FRAGMENT_COLS` / `FragmentBar.FRAGMENT_COLORS` / `World3D` 的反派台词前
  跑 `verify_story.gd`。它守的是**三处互相对不上的副本**：`Localization.STRINGS`（玩家读到的字）、
  `road_data` / `Postcard`（碎片身份）、`3D_RIDE_DESIGN.md`（下一个人的唯一入口）。
  改 `3D_RIDE_DESIGN.md` 本身也要跑——这一族里只有它会把文档钉在代码上，
  而文档错了没有任何运行时后果，只有下一趟踩
- 修改 `scripts/road_data.gd` 的 stations 数组（名字 / model_idx / fragment）前先在 headless 跑 `verify_stations.gd` + `verify_8_shape.gd`（stations 数组同时是 lemniscate 驿站映射）
- 修改 `scripts/VegBuilder.gd` 前先跑 `verify_vegetation.gd` + `verify_pavilion_bushes.gd` + `verify_vegetation_grounding.gd`
- 修改 `scripts/GrassScatter.gd` 前先跑 `verify_grass_scatter.gd`
- 修改 `scripts/TreeScatter.gd` 前先跑 `verify_tree_scatter.gd`；改间距/离路/淡出参数后还要跑 `lookdev_trees.gd` 看图（`CELL` 必须和 `GrassScatter.CELL` 一致，两套流式共用同一张格子）
- 修改 `assets/shaders/grass.gdshader` 的 `card_width` / `card_height` / `blade_count` / 循环上限 / `blade_base` / `blade_tip` 前先跑 `verify_grass_scatter.gd` 的"草皮着色器：形状与颜色"一节（它把这些值从**文本**里读出来，卡片高宽比、绝对尺寸、叶数、循环上限 vs `blade_count`、绿-红通道差、纯文本断言），再跑 `lookdev_grass.gd` 看图（`--headless` 的 dummy renderer **不编译着色器**，语法错和观感错在无头下都会静默通过）。看图时记住 `lookdev_grass.gd` 的相机必须站在草环圆心
- 修改 `scripts/mini_games/*.gd` / 打卡流程前先跑 `verify_mini_game.gd` + `verify_bamboo_world.gd` + `verify_mini_game_keys.gd` + `verify_bamboo_done.gd` + `verify_mini_game_fail.gd` + `verify_checkin_all5.gd`
- 改**云/琴/竹的画**（`MiniGameCloud.CLOUD_CIRCLES` / `fit_scale()` / `area_rect()`、
  `MiniGameZither.headgear_poly()` / `head_anchor()` / `foot_polys()` / `foot_anchor()`、
  `MiniGameBamboo.stalk_poly()` / `node_fracs()` / `leaf_poly()` / `LEAVES` / `STALK_W_*` /
  `SPACING` / `FALL_REACH_FRAC`）前跑 `verify_mini_game.gd` **第 6g 节** +
  `lookdev_journey.gd` 看那三张 `minigame_云` / `minigame_琴` / `minigame_竹`
  （**`--headless` 根本不调 `_draw`**，几何里写错一个构造在无头下永远是绿的）。
  两条做法是这一族能测住的原因：①**判据量的是画笔真的摆的那一处**——锚点抽成
  `head_anchor()` / `foot_anchor()`，画和回归调同一个函数；测试里把算式抄一遍的话，
  改画不动测、测会一直绿。②**形状参数是一张表**（`CLOUD_CIRCLES` / `LEAVES`），
  画笔和回归读同一张，而回归量的是**多边形自己的几何**（叶的最大垂直宽度 =
  2×面积 ÷ 最长边）而不是表里那个宽度字段——表对了而画笔没照着画，那一条就该红。
  量「不许越过某条边界」的量要从那条边界反解（竹子砍倒那截的横向伸出按 `SPACING`
  反解），按窗口高度取百分数的话 720p 量着刚好、1080p 就压上去了
- 改 `OnboardingGuide` 的 `_build_ui()`（尤其焦点）/ `ShopPanel._button()` / `_grab_first_focus()` / `_refresh()` / `GameManager._bind_ui_accept_to_physical()`，或**任何一个 Button 的键盘可达性**前跑 `verify_panel_keyboard.gd`（**不能加 --headless**）。它量的是"冷启动 → 收掉操作说明 → 推完序章 → 驿铺买成一件"，不是量某一个函数；两种按键事件形状各测一遍，只测一种的话另一半坏了照样全绿
- 改 `MiniGameCloud.PATH_POINTS` / `_update_draw()` / `_next_seg` 前跑 `verify_mini_game.gd` 第 7 节（**完成度只能来自"描过"**：原地晃 60 次只记一段的 13%，够不着 75% 的及格线；顺次描完和一甩到底都得能描完——甩过去的那几段要一起记上，否则光标卡死在没描到的那段上，后面整条云再也描不完）。顺手也跑 `verify_mini_game_keys.gd` 的云那一局：它当初的绿**是靠这个漏洞**刷出来的，修好漏洞后如果它变红，先看它是不是还踩在原地
- 改 `MiniGameCloud._gui_input_key()` 的挪光标 / `KEY_STEP` 前跑 `verify_mini_game_keys.gd`（到达判据必须 ≥ `KEY_STEP`，否则 12px 的整步走会在目标两侧横跳、`_cloud_t` 永远不前进）
- 改 `MiniGameBird.BIRD_SHAPES` / `_draw_bird_silhouette()` / `MiniGameZither.SHOW_DELAY` / `_advance_show()` 前跑 `verify_mini_game.gd` 第 6b/6e/6f 节 + `lookdev_journey.gd` 看那两张 `minigame_禽` / `minigame_琴`（**`--headless` 根本不调 `_draw`**，几何里写错一个构造在无头下永远是绿的，必须靠带窗口的回归和图）；禽的四只鸟要**形状**不同，不能是同一个形状刷四种颜色，画法在 `BIRD_SHAPES` 表里、回归也读同一张表
- 改 `scripts/mini_games/MiniGamePicker.gd`（`SCRIPTS` 顺序 / `game_for()`）或 `World3D._run_mini_game()` 的轮换那一行前跑 `verify_mini_game.gd` 第 7 节 + `verify_interact_latch.gd` 第 4 节。`SCRIPTS` 是一份和 `RoadData.FRAGMENT_SLOT_STATION_IDX` **对拍的独立副本**，顺序错了第一次到访就配错乐事——回归拿真实的 `road_data.gd` 逐格核，抄一份表蒙是不行的。第 4 节量的是真实 World3D 里"回访确实起了**换过的那件**"（原来它断言"回访不重播小游戏"，那个契约已经作废了）
- 改 `World3D._do_check_in()` 里 `is_first_visit` 的两处分支（对白 / 小游戏）前跑 `verify_interact_latch.gd` 第 4 节 + `verify_checkin_all5.gd`。**对话仍然只在首次到访，乐事每一趟都有**——两者的门不一样：驿站的开场白是自我介绍，回访再念一遍会冲掉顶栏那 3 次的进度感；而完满评级要的正是三次，一次都不给就把最强的重玩钩子空着
- 改 `scripts/mini_games/MiniGameBackdrop.gd`（`THEMES` 配色 / 五个主题常量）或任何一个小游戏里 `MiniGameBackdrop.draw_scene(...)` 那一行前跑 `verify_mini_game.gd` 第 6 节 + `lookdev_journey.gd` 看 5 张 `minigame_*.png`。第 6 节只核对**引对了没有**（读源码文本），景好不好看只有图能判——"五个乐事共用一片黑幕"正是原来的毛病，而它在无头下永远全绿
- 改 `MiniGameZither._board_rect()` / `_string_rects()` / `_draw_string_h()` 前跑 `verify_mini_game.gd` 第 6 节的琴弦那几条 + `lookdev_journey.gd` 看 `minigame_琴`。判据是**命中区宽 > 高**：古琴的弦平行于长轴，旧版把四根弦竖着插在一条又宽又短的琴身上，那不是琴。注意几何必须抽成 `_string_rects()` 这种不碰画笔的纯函数让回归直接调——`_note_rects` 是在 `_draw()` 里填的，headless 读它只会读到空数组
- 改 `MiniGameCloud.CLOUD_CIRCLES` / `cloud_outline()` / `OUTLINE_SAMPLES` / `FLAT_Y` / `MiniGameBamboo.SPACING` / `stalk_poly()` / `node_fracs()` / `fall_len()` / `MiniGameZither.HUI_*` / `headgear_poly()` / `foot_polys()` / `mg_zither_title` / `mg_bamboo_intro` 前跑 `verify_mini_game.gd` **第 6g 节** + `verify_story.gd`（改了文案）+ `lookdev_journey.gd` 看 `minigame_云` / `minigame_竹` / `minigame_琴`。三处都做完了删除突变（轮廓换回八边形 → 尖角/平底两条红；竹身退回等宽 + 砍倒那截改回按高度取长 → 两条红；徽减到 7 个 / 从 0 起排 → 两条红）。**轮廓的采样数不能随手调小**：`OUTLINE_SAMPLES` 决定相邻两点的间距，间距必须 > `KEY_STEP`(12px)，否则键盘光标整步走会在两点之间横跳，而第 6g 节量的是间距、`verify_mini_game_keys.gd` 量的是走不走得完
- 改 `MiniGameBar.gd` 的任何一处（`rect()` / `threshold_x()` / `tick_span()` / `tick_label_rect()` / `TICK_OVERHANG` / `TICK_LABEL_*` / `PIP_GAP_FRAC` / `pip_*`），或 `MiniGameCloud` / `MiniGameTea` / `MiniGameBamboo` 里那三行 `draw_bar(...)` / `draw_pips(...)` 之前跑 `verify_mini_game.gd` **第 6h 节** + `lookdev_journey.gd` 看那三张 `minigame_*.png`。第 6h 节里有**三条是读源码文本**的（和核 `MiniGameBackdrop.<THEME>` 同一个办法）：几何断言量的是那几个纯函数，而**量不到画笔有没有真的去调它们**——把画笔那一行的门槛换成字面量，几何照样全绿
- 同一族里有一条**图先发现的、数值量不到**的坑：`draw_string` 的宽度参数是**裁切宽度**。刻痕下面那个「75%」第一版给了 28px，而 16px 的它实测要 32px——多出来的半个百分号被切掉，图上只剩「75」，而**标签框一直是 28px，量尺寸的任何断言都看不出问题**。所以判据钉的是 `get_string_size()` 给这串字的宽度 ≤ 框宽（改字体、改字号、改标签文案之后这条会自己变红）。同族的第二条：`TICK_LABEL_DY` 必须 > `TICK_OVERHANG`，否则刻痕的下半截从那串字里穿过去
- 改 `MiniGameChrome.gd` 的任何一处（`cancel_rect()` / `label_rect()` / `draw_cancel()` / `FILL` / `BORDER` / `LABEL` / `CANCEL_*` / `BASELINE_UP`），或**五个小游戏里那个取消按钮**的画法与热区之前跑 `verify_mini_game.gd` **第 6i 节** + `lookdev_journey.gd` 看那五张 `minigame_*.png`。三条要记住的：①**判"它不该像警报"要拿真警报当尺子**——产品里 `HUD3D.set_boundary_intensity()` 那圈边界警告红（0.84 / 0.50）就是尺子，写成"不是 `Color(0.8,0.3,0.3)`"是拿自己测自己；②**底板必须不透明**，五个小游戏背景亮度差得远，半透明底的对比度随背景漂，而"五屏上都读得出来"只有底板自己说了算才立得住；③`draw_string` 的 position.y 是**基线**不是行盒顶，所以"基线在按钮高度的 68%"会让 22px 的字身从按钮顶沿探出去——**量行盒量不出来**（框还在按钮里，探出去的是字形），要量就得用字体真实的 ascent/descent 算字形盒，画笔和回归读同一个盒子；④**竹那一屏的热区必须判在"当成砍"之前**——左键在竹子是砍，判在后面就成了点取消挨一刀，而 ESC 在这一屏是隐藏的，鼠标玩家发现不了还能走。**写完先证明它会红**：把 `draw_cancel` 那一行删掉红 2 条、把热区挪到 `_cut_current_bamboo()` 之后红 1 条（突变要一个一个撤）
- 改 `scripts/AudioManager.gd` 或 `scripts/mini_games/*.gd` 里的发声前先跑 `check_all_scripts.gd` + 上面那 6 条；新加了 sfx 还要跑一次 `--headless --editor --quit-after 60` 生成 `.import`
- 改任何一屏玩家可见的东西（HUD / 标题页 / 新手引导 / 商店 / 驿铺 / 明信片 / 结算）前跑 `lookdev_journey.gd` 看图
- 改 `EndCard._export_two_images_web()` / `GameManager.SAVE_PATH` / `_save_game()` / `_load_save()`
  或任何碰 `user://` 的地方后，把 `tools/web_smoke.tscn` 设成主场景、
  `--export-release "Web" ./build_web/188.html`，在浏览器里**开两遍**看
  `result=ROUNDTRIP_OK` 与两张 PNG 落盘，跑完把主场景改回去。
  桌面回归永远量不到这一层：`user://` 在 Web 上是 IDBFS，而落盘是异步的，
  刷新页面会走 beforeunload 的同步路径把问题盖掉
- 改 `scripts/FarRidge.gd` 的层数 / 半径 / 颜色前跑 `lookdev_horizon.gd` 看图（AGX 会把中间调提亮去饱和，填色要反着调，见已知陷阱）
- 改 `scripts/water_data.gd`（`BASIN_SHAPES` / `WATER_LEVEL` / `_best_site` / `_footprint_mean`）、`scripts/Water.gd`（`_shoreline` / `MIN_RADIUS`）或 `TerrainBuilder` 的 `_height()` / 高程 clamp 之前，先跑 `probe_water.gd` 再跑 `verify_water.gd`，改完着色器再跑 `lookdev_water.gd` 看图。`WATER_LEVEL` 一旦高于地形下限 -3.0，"关得住水"这个前提当场失效，而症状是几十度角在两倍盆沿之外还没露出岸——数字全绿、图上一片蓝纸
- 改 `HomeBase.gd` 的任何一处（选址 / 尺寸 / 门牌 / 让位）或 `World3D` 里
  `_push_out_of_home()` / `_check_home()` / 那句 `tree_protect.append(_home.site)` /
  `_minimap.set_home(...)` 之前跑 `verify_home_base.gd` + `lookdev_home.gd`
  （**后者不能加 --headless**）。另加 `verify_interact_latch.gd` 第 8 节
  （推出与回弹的先后）、`verify_minimap.gd`、`verify_road_steles.gd`。
  **改 `HOME_OFFSET` 时先问一句"靠路那一沿还在 `SOFT_BOUND` 之外吗"**：
  越线的话 `RoadVerge` 那道看得见的粉线会从屋子里穿过去，而落点仍然合法、
  仍然 15m 离中心线——**所有"离中心线多远"的判据都照样绿**。
  这正是那条常量自己比自己而恒绿的那次教训的同一族
- 改顶栏 / `scripts/shop_data.gd` 的解锁门 / `World3D.VILLAIN_SCENES` 的触发条件前跑 `verify_economy.gd`（含「里程不许出现在任何玩家可见文案里」扫描）+ `verify_shop_panel.gd` + `verify_shop_world.gd` + `lookdev_journey.gd` 看顶栏
- 改 `HUD3D._next_fragment_target()` / `_arrow_glyph()` 前跑 `lookdev_journey.gd`（它带一条几何断言：车头正对 → ↑、背对 → ↓、正右方 → →，只测 static 那个函数等于拿自己测自己）；方位用 `a(v) = atan2(v.x, -v.z)`，8 字环自闭合、两个方向都到得了全部 5 站，箭头必须真的随车头转
- 改 `HUD3D._update_buttons()` 那三个音频开关的文案 / `Localization` 的
  `bgm_short` / `sfx_short` 前跑 `verify_mood_mask.gd`（它量的是"三个按钮在
  玩家看得见的意义上分得开"，不是"三个字符串不相等"——后者一直是绿的而产品
  一直是坏的）+ `lookdev_journey.gd` 看 `04_ride` 的右上角。
  判据钉的是"区分用的字符是字不是符号"：**只要那个区分落在符号的一根细笔画上，
  在 18px 上就没有区分**，而 `Font.has_char()` 查 cmap 查不出来
- 改 `HUD3D.MOOD_REST_SCALE` / `set_mood_pulse()` / `_setup_mood_mask()` 或 `World3D` 里推 `set_mood_pulse` 的那一行前跑 `verify_mood_mask.gd`（骑行档必须**永远**低于 0.20 可读上限，叙事档才允许冲到 `MOOD_MASK_MAX`）
- 改 `HUD3D.SCRIM_H` / `SCRIM_TOP_ALPHA` / `SCRIM_SOLID_FRAC` / `_make_scrim_image()` 或 `_make_hud_label()` 的字号/颜色前跑 `verify_mood_mask.gd` 第 9 节（纯算术：在**声明的最坏背景**上逐行合成再算 WCAG，文字带从真实 Label 的 rect 换算）+ `lookdev_journey.gd` 看 `04_ride` / `12b_day_正午` / `12c_dusk_黄昏` / `13_collect_集齐合成`。第 9 节能证明"算出来够"，"看起来是不是一条黑带"只有图能判
- 改 `MiniMap._next_frag_idx()` / 未收碎片站的画法前跑 `verify_minimap.gd`（小地图高亮的那颗必须就是顶栏"下一处"报的那颗；这是继 `CheckInPrompt` 之后第三个会说"下一处在哪"的地方，判据一漂移玩家就骑错且无从察觉）
- 改 `scripts/DayCycle.gd` 的任何一档颜色 / 太阳角度 / `FarRidge.set_tint()` 前跑 `verify_day_cycle.gd`（量的是数字）+ `lookdev_journey.gd` 看 `12b_day_正午` 与 `12c_dusk_黄昏` **那两张同机位的 A/B**（量的是观感）。少一张就没法判断"天到底变了没有"——两处只查一个都曾经全部通过而画面纹丝不动
- 改 `DayCycle` 那六个 `DAY_SKY_*` / `DAY_GND_*` 常量、`_apply()` 里那几行 `.srgb_to_linear()`，或 `World3D.tscn` 里 `Env_sky` 的 `fog_sky_affect` 前跑 `verify_day_cycle.gd`（它守着 `fog_sky_affect == 0` 和线性空间的纵向反差 ≥ 0.50，两条都是**成因**而不是结果）+ `lookdev_journey.gd` 那五条天带像素断言。**那六个常量是按 sRGB 写的**，交给 `ProceduralSkyMaterial` 之前必须过一遍 `Color.srgb_to_linear()`——天空色在引擎里是辐照度、直接当线性值用，不像普通材质那样帮你转一遍；写成"看着对"的那一档渲出来是接近纯白的一整片灰蓝纸。`lerp` 也要**在 sRGB 空间做、换算放最后**（`DAY_X.lerp(DUSK_X, t).srgb_to_linear()`），否则那 9 秒交叉淡入在中段塌成一团发灰的泥
- 改 `GameManager.fragment_station_needs_visit()` / `all_fragments_maxed()` / `fragment_slot_visits_left()` / `MAX_VISITS_PER_STATION` / `HUD3D._update_next_label()` / `FragmentBar._draw_visit_pips()` / `CheckInPrompt._label()` 的回访分支前跑 `verify_minimap.gd` + `verify_interact_latch.gd` 第 4 节 + `lookdev_journey.gd` 看 `05d_revisit_回访提示`（完满是全游戏最强的重玩钩子，三处「还差 N 次」必须同数；任一处退回 `is_collected` 就会把已收的站从导航上摘掉）
- 改 `FragmentBar.gd` 的 `RIM_W` / `FRAGMENT_COLORS` / 未收那一支的画法，或 `FragmentBar.tscn` 里五个 Slot 底下那几个 `FragLabel` 的 `text` 占位前跑 `lookdev_journey.gd` 看 `04_ride` 的底栏 + 它那两条像素断言。**`RIM_W` 是画笔和定妆照共用的那个数**（回归取样窗口 23~26.5 是按「圆盘 22 + 5」推的），改它要连两边一起改。**`.tscn` 里那几个占位问号曾经和画笔画的那个同时在屏上**——屏上两个「？」，一个在盘心把图标整个盖住，一个在名字那一行；而占位 Label 是**要留着的**（收过之后 `_process` 把它换成碎片名），清的是 `text` 不是节点。另有一条**量图上的硬理由**：色盘画在**盘外**而不是盘内一道细环——云是实心多边形、竹的梢伸到半径 25，都压得进盘内 19~21 那一圈，于是回归量到的是图标而不是环，**把环整条退回灰色它照样报"五格分得开"**（那次突变就是这么溜过去的）。茶(8FB35A) 与竹(6E9C6B) 本来就是两块很近的绿（环上只差 0.015），靠形状分开是设计不是缺陷，所以判据是并集而不是纯颜色；别为了凑颜色判据去动 `FRAGMENT_COLORS`——它和 `Postcard.FRAGMENT_COLS` 逐值同源，改一边要改 `verify_postcard_ending` §3b 和 `verify_story` §4
- 改 `FarRidge.LAYERS` / `_build_layer()` 的材质前跑 `verify_far_ridge.gd` + `lookdev_horizon.gd` 看图（`disable_fog` 被谁删掉的话三层会塌成一条没有纵深的白带，标志位那关拦得住，颜色那关只有看图）
- 改 `CrossingMark.gd` 的任何一处（`FACE_W` / `FACE_H` / `FACE_TILT_DEG` / `PLINTH_H` / `PLINTH_CLEAR` / `TRACE_BOX` / `TEXT_Y` / `TEXT_PIXEL` / `TRACE_W` / `face_lift()` / `_quad()` 的缠绕顺序）前跑 `verify_crossing_mark.gd` + `lookdev_crossing.gd` 看 `5_mark` 与 `6_face`。**这族回归有三条只靠图才成立的判据**：缠绕方向（发反了整条刻线是背面、正面看一片空白，而带子/法线/包围盒/逐点对拍全绿——回归靠"法线是 +Z"那条兜底，兜不住的是"看起来粗细对不对"）、刻线在石板上**读不读得出是个 8**（数字量得到两个瓣交叠 0.25，量不到"腰上那两个鼓包会不会把交叉糊掉"）、以及**题字画没画出来**（Label3D，headless 一笔不落盘）。而 `TRACE_BOX` 与 `TEXT_Y` 必须**一起动**：两者抢的是同一块石板，只动一个就会有一边被石板边沿或石台吃掉
- 改顶栏的经济标签（`_lvbi_label` / `_lvbi_toast` / `_setup_economy_labels`）前跑 `verify_mood_mask.gd` 第 7 节（它断言入账时余额/心神/"下一处"三个标签的横坐标一个像素都不许动）
- 改 `HUD3D.TOP_RIGHT_W` / `TOP_RIGHT_GAP` / `_setup_economy_labels()` 里那个撑开的弹簧 `_next_gap`（`NextGap`）/ `_update_next_label()` 的空分支 / `Localization` 的 `hud_all_done` 前跑 `verify_mood_mask.gd` **第 10 节** + `verify_minimap.gd` **第 10 节末尾** + `lookdev_journey.gd` 看 `04_ride` / `13c_after_再骑一圈` / `13d_maxed_走满顶栏`。这一族判据量的是**"顶栏右端离按钮排还有多远"**这个玩家读得出的量：`.tscn` 给 `TopBar/HBox` 写死 `offset_right = 480`（468px 宽），而它那五个标签要 ~663px，于是 ~195px 静默溢出（`clip_contents` 默认 false，没有任何回归看得见）——而"顶栏排到哪"从此由**文字有多长**决定，右端因此永远悬在半路，读成一条几百像素的黑带。修法是让容器说实话（`anchor_right = 1.0` / `offset_right = -(TOP_RIGHT_W + TOP_RIGHT_GAP)`）并把长度变化全交给**心神和「下一处」之间那个弹簧**；顶栏右端于是钉死在按钮排左边 16px，无论那行字多长多短。**"刷满"那一档原来写的是空串**——`fragment_station_needs_visit()` 五座都还清就直接返回空字典，而那正是玩家最该看着那一栏的 2.5 秒（`_on_all_maxed` 锁死到跳结算页之间）；现在写 `hud_all_done` 那句收尾。**写完先证明它会红**：`offset_right` 改回 480 时第 10 节那两条红、空分支改回 `""` 时 `verify_minimap` 那两条红
- 改 `World3D._push_mini_game_chrome()` / `_pop_mini_game_chrome()` 前跑 `lookdev_journey.gd` 看 5 张 `minigame_*.png`（遮罩不透明 + 运行时藏 HUD，靠的是这对成对方法，漏掉一头就有一屏写着"两层同时存在"）
- 改 `DialoguePopup.setup()` / `World3D._can_start_check_in()` / `_do_check_in()` / `_play_villain_scene()` / `CheckInPrompt._label()` 前跑 `verify_interact_latch.gd`（这五处任何一个漏了都能把游戏变成"提示圈照画、按键全死、只能重开"）
- 改 `World3D._physics_process()` 里那张"这些状态下一律不算 `_nearby_*`"的早退单、或 `CheckInPrompt._prompt_target()` / `_interact_blocked_reason()` 前跑 `verify_interact_latch.gd` 第 6 节。这张单子上每多一个状态，那个状态下脚下的圈就该同时收掉——`CheckInPrompt._prompt_target()` 只读 `_nearby_*`，它不知道 `_villain_playing`，单子漏一格就是"圈还在推销一个按不出来的交互"。注意 `lookdev_journey.gd` 在这里帮不上：它开头就设 `_gm.seen_villain = 3` 把三场反派戏全跳过去了，所以这一段没有任何定妆照可看，只能量数字）
- 改 `CheckInPrompt._label_pos()` / `_draw()` 里的底板前跑 `verify_interact_latch.gd` 第 5 节 + `lookdev_journey.gd` 看 `05c_prompt_贴脸`（贴着站停下时站点的投影已经压到屏底，提示文字是往圈上方翻的，底下又是全屏最忙的一块——数字对了图上仍可能读不出来）
- 改 `World3D._apply_station_keepout()` / `STATION_KEEPOUT_PAD` / `_measure_station_aabb()` / `Player3D.damp_speed()` 前跑 `verify_interact_latch.gd` 第 8 节 + `lookdev_journey.gd` 看 `05c_prompt_贴脸`。**调 `STATION_KEEPOUT_PAD` 时先问一句"半径还小于 `STATION_PASS_RADIUS` 吗"**：墙一旦比打卡圈大，玩家被挡在圈外，顶栏「下一处 … Nm」永远减不到 0、脚下的圈永远不亮，而这两样在别的回归里全是绿的
- 改 `World3D.VILLAIN_SCENES` / `_try_villain_scene()` / `_too_close_to_target()` / `VILLAIN_MIN_STATION_GAP` / `VILLAIN_MIN_TARGET_DIST` / `_villain_camera_cue()` 或 `HUD3D.show_cue_line()` 前跑 `verify_interact_latch.gd` 第 9 节 + `lookdev_journey.gd` 看 `04b_villain_打断入场`。第 9 节量的三件事各自会红：落点闸（贴着碎片站起播）、排队闸（一次只放一场）、收尾三件套（`_villain_playing` / 相机锁 / `look_at` 都还回去）。**写完先证明它会红**：把两道闸删掉跑一遍，两道都必须变红——闸二第一版删了还是绿的，因为它自己的前提（驿数顶到 12）从来没成立过
- 改 `Player3D.CAM_BACK` / `CAM_UP` / `CAM_SIDE` / `_villain_camera_cue()` 的收束量前跑 `lookdev_journey.gd` 看 `04b_villain_打断入场`（入场那一下镜头只往后 2.2m、往上 3.1m，量小了读成"没发生"，量大了玩家以为游戏卡了——这两个数只有图能判）
- 改 `World3D._physics_process()` 里调 `_apply_*` 的那几行、或任何"每帧推位置"的地方前跑 `verify_interact_latch.gd` 第 8 节（推出和回弹的先后会互相抵消：先回弹后推出的话，车贴着一座站骑的时候会被路边界往里推、被站推出往里推，两股力在同一点上打架）
- 改 `Postcard.FRAGMENT_COLS` / `_draw_fragment_icon()` / `VARIANT_LAYOUTS` 前跑 `verify_postcard_ending.gd` 第 3b 节 + `lookdev_postcard.gd` 看明信片正面（颜色/图标/标签三者同序，且 `Postcard.FRAGMENT_COLS` 与 `FragmentBar.FRAGMENT_COLORS` 逐值相同；缩略图和存档 PNG 是同一份，错了就是玩家带走的那张错了）
- 改 `Postcard.MAP_BAND_FRAC` / `_layout_map()` / `_map_inner()` / `_map_project()` / `_draw_map_caption()` 前跑 `verify_postcard_ending.gd` 第 3c 节 + `lookdev_postcard.gd` 看 `05_tier3_满配`（投影抽成了不碰画笔的纯函数，所以「16 驿有没有被框裁掉」「买了信封方框有没有让开左上角的折角」在 headless 下判得了；折角是 `min(w,h) × 0.16` 的一条等腰直角，方框照旧贴着左边上角放就会被削掉框线和路各一角——**两处都是定妆照先发现的，尺寸断言当时全绿**）
- 改 `Postcard._caption_col_w()` / `_joys_column_rect()` / `_draw_joys_column()` / `Localization` 的 `postcard_joys_title` / `postcard_visit_n` 前跑 `verify_postcard_ending.gd` **第 3d 节** + `lookdev_postcard.gd` 看 `05_tier3_满配` / `09_未竟_三碎片缺格`。第 3d 节量的三件玩家读得出来的事：抬头**右沿不留死区**（这一列真的排到右边去，不许只是换了个地方继续空着）、**不压左边那一列的字**、**每一行放得下**——最后一条是必须的，因为次数是**右对齐**画上去的，而 `draw_string` 的宽度参数是**裁切宽度**，字比列宽就整段被裁掉而尺寸断言照样全绿。中英 × 900/1920 四种组合都过，因为英文那一列长一截。**另有一条是读源码文本的**：`_draw_map_caption` 的函数体里必须真的有 `_draw_joys_column(` —— 几何函数对不对和画笔有没有去调它是两件事，把那一行删掉几何断言全绿而图上重新变成空白的纸（`--headless` 一笔都不落盘，纯函数量不到调用点）。**写完先证明它会红**：删掉画笔里那一行 → 1 条红；右沿退回 `w * 0.62` → 4 条红（4 个组合各一条）；图例那一项不加上两个圆点那 44k → 4 条红
- 改打卡流程的"这站还欠我一块碎片吗"判据前跑 `verify_interact_latch.gd` 第 4 节 + `verify_checkin_all5.gd`（`station_has_fragment(i)` 是站的静态属性、`is_collected(i)` 才是玩家进度；拿前者当前者会让回访重播小游戏并谎报"获得碎片"，而 HUD 的"下一处"早就把这站摘掉了，两边对不上）
- 改 `GameManager` 的 `SAVE_PATH` / `SAVE_TMP` / `SAVE_BAK` / `_save_game()` /
  `_load_save()` / `_try_load_from()` / `_sanitise_*` 之前跑 `verify_save_robustness.gd`，
  改完再跑一次；**顺手确认那 11 份会读档的工具仍然只备份/还原正本**——
  它们各自只写回 `SAVE_PATH` 的话，原子写新留下的 `.bak` / `.tmp` 会留在盘上，
  而下一次读档在正本坏掉时会拿那份测试残留当备份（各工具的还原处现在都先调
  了一次 `_clear_save()`）。**写完先证明它会红**（突变一个一个撤）：
  撤掉备份回退 → 红 6 / `_sanitise_collected` 退化成原样返回 → 红 7 /
  `cfg.save(SAVE_PATH)` 退回非原子写 → 红 9 / `seen_stations` 不校验 → 红 4。
  `_sanitise_seen()` 的上界必须真的从 `RoadData` 的**实例** `stations` 取：
  拿静态那份 `FRAGMENT_SLOT_STATION_IDX`（只有五座）当上界，13 座普通驿站
  到过的记录会全被丢掉，顶栏「已过 n 驿」于是永远 ≤5
- 改 `SettingsPanel.gd` / `AudioManager.gd` 的音量与静音那一族 /
  `QualitySettings.set_resolution|set_window_mode|set_vsync` / `HUD3D._settings_panel()` /
  `_on_help_btn_pressed()` / `GameManager.player_control_rows()` /
  `OnboardingGuide` 的操作说明那一段前跑 `verify_settings.gd`。
  **「静音就是音量 0」是不可退回的**：把 `_bgm_muted` 那个独立布尔捡回来，
  顶栏「♪ 开」与设置面板的滑杆就能同时说两件事，而两个都在屏上。
  改 `PAUSE_DUCK_DB` 时问一句"玩家把 BGM 拉到 20% 时暂停是不是更响"——
  压低必须是**相对**的，绝对值在低音量那一档会翻面。
  另外两处 `user://settings.cfg` 的主人（`AudioManager` 的 `audio` 段、
  `QualitySettings` 的 `video` 段）**都只能读-改-写**，覆盖写会抹掉对方那一档。
  **写完先证明它会红**（`tools/mutate_settings.py`，十二条突变一个一个撤，全部咬住）
- 改 `PausePanel._make_tier_label()` / `_refresh_tier_label()` / `_apply_language()`、
  `PostcardVariant.TIER_KEYS` / `tier_count()` / `tier_name_key()` / `visits_to_full()`、
  `Localization` 的 `tier_0..tier_4` / `tier_now` / `tier_full`、
  `GameManager.gd` 与 `shop_data.gd` 里那三行预算注释（`全清` / `合理全购` / `缺口`）、
  或 **README / README.en.md 里报的那几个条数**之前跑
  `verify_postcard_ending.gd` §3b + `verify_minimap.gd` 第 8b 节 +
  `verify_story.gd` §5.6 + `verify_economy.gd`。
  **只钉能从仓库数出来的那些数**（`verify_*.gd` / `lookdev_*.gd` / `probe_*.gd`
  各有几个、`NEEDS_WINDOW` 几条），而**跑出来的 PASS 数与断言总数一律不许写死**
  ——它们每加一条断言就变，写死过一次，而它下一次跑就假了。
  **正向与反向必须成对写**：只断言 README 里有「11 套出图」的话，
  把另一处那个 11 改成 8 它照样绿（`contains` 量的是"至少有一处是对的"）。
  **写完先证明它会红**（`tools/mutate_honesty.py`，十二条突变一个一个撤，**12/12
  全部咬住**——含"档名表少一档""`visits_to_full()` 恒返回 0""暂停面板不建那一行"
  "中英档名填成同一个词"）。
  连带一条量法上的：**一条量"状态切换"的断言必须自己先把起点摆出来**——
  `Localization` 把语言存进 `user://settings.cfg`，所以上一轮跑完留在英文的话，
  这一轮"切到英文"是空操作，而判据写的是 `t_en != tnow`，于是"开局本来就是英文"
  被报成"切语言没生效"
- **往 `assets/` 里加进或删掉任何一个文件**（模型、贴图、字体、音频、着色器）之前跑
  `verify_provenance.gd`，并同步改 `PROVENANCE.md` 的全量登记表与 `CREDITS.md`。
  判据钉的是**相对 `assets/` 的逐字路径**，所以「登记了但路径打错」和「压根没登记」一起红。
  **反方向也钉**：登记表里留着一个已经删掉的文件同样红——那份清单会让人去找一份
  不存在的授权凭证，而那种错**在发版当天才会被发现**。
  **当前未核实的两项**（**都不再阻塞发行**，2026-10-05 之后）：6 个 Tripo 资产的
  **账号档位、生成日期与当时的条款**未定，而 README 末尾那行
  `*Tripothon S1 · @Tripothon · @TripoAI*` 暗示管着它们的可能是**活动条款**
  而不是通用服务条款；另外 `export_presets.cfg` 的 `package/unique_name`
  还是占位 `com.example.gift188`，上架前必须换。
  `assets/bike.glb` 已是 **CC0 1.0**（取得者 2026-10-05 确认），
  原 `assets/models/station_2.*`（唯一的**图生 3D**）已于同日**退役**——
  它不是被核实掉的，是被自建的 `station_琴台.glb` **换掉**的：
  **图生 3D 的风险按「上传物的权利链」算，而那一条在生成物里查不到、补材料也消不掉。**
  **别把「待核实」改成「已核实」来让发版流程走通**——
  顺带一条已经处理掉的：`tools/subset_font.py` 原来**原地覆盖**字体文件，
  而 OFL §3 要求修改版**不得使用保留字体名**——它产出的任何子集都是违规分发。
  现在默认**另存** + 改写 name 表 ID 3/4/6，原地覆盖要 `--in-place` 加
  `--ofl-reserved-name-cleared` **两个**键（保留字体名写在**上游 LICENSE 文件里、
  不在 TTF 里**，量不出来，所以做成两次显式确认而不是替人判断）。
  **当前整轮不做子集**——发行前字体整个换掉。
- 改 `World3D._tint_station_roofs()` / `STATION_ROOF_TINT` 前跑 `verify_station_roof.gd` + `lookdev_journey.gd` 看 `04_ride`（填色要过 `linear_to_srgb`，写错方向屋顶比墙暗 30 倍，数字还是"暖的"，只有比值看得出来）
- 改 `GameManager.check_in()` 里那两个闩锁 / `all_fragments_maxed()` / `_load_save()` 末尾的补齐 / `World3D._on_all_collected()` / `_on_all_maxed()` / `_spawn_synthesis_animation()` / `PostcardVariant.compute_variant()` 前跑 `verify_minimap.gd` 第 9/10 节 + `verify_postcard_ending.gd` §3b + `verify_interact_latch.gd` 第 4 节 + `verify_checkin_all5.gd`（"集齐"与"走完"是两个时刻，判据只能有一个）
- 改 `SynthesisPanel.gd` 的任何一处 / `World3D._synthesis_choice_open` / `_on_all_collected()` 的尾巴 / `_on_synthesis_choice()` / `HUDLayer/SynthesisPanel` 节点前跑 `verify_interact_latch.gd` **第 10 节** + `verify_minimap.gd` 第 9 节 + `verify_demo_path.gd` 第 1 节 + `lookdev_journey.gd` 看 `13b_synthesis_集齐二选一` 与 `13c_after_再骑一圈`。三件事一条都不能省：**第 10 节量面板本身**（两个按钮都在屏内不叠、都有 `focus_mode`、ESC 收得掉、`_all_done` 没被顺带翻过去）；**`verify_minimap` 第 9 节现在必须先选「再骑一圈」再逐站核对脚下的圈**——它原来直接接着扫，扫的时候面板还开着，`_nearby_*` 早被清成 -1，十条断言一起红，而那个红是**新行为的正确结果**，不是产品坏了；**`verify_demo_path` 第 1 节**守着 90 秒演示不被这个面板打断（`fill_finished_run()` 走直写字段不发信号，而刷满的碎片站被 `is_station_exhausted` 挡在 `_nearby_station_idx` 之外，演示里根本打不了卡）
- 改 `Localization.gd` 里 `touch_revisit_button` / `collecting_message` / `revisit_available` / `synthesis_done_message` / `finish_run` 前跑 `verify_economy.gd`（文案扫描）+ `verify_interact_latch.gd` 第 4 节 + `lookdev_journey.gd` 看 `05d_revisit_回访提示`。前三句曾经一起写着"再歇一脚"——集齐之后唯一还在对玩家说的话是劝他别再跑了
- 改 `RevisitNote.gd` / `World3D._popup_body_text()` / `_popup_foot_text()` / `_is_revisit()` / `_lap_index()` / `_run_mini_game()` 里那行 `_last_joy_slot` / `Localization` 的 `revisit_2nd_*` `revisit_3rd_*` `mg_played` 前跑 `verify_mini_game.gd` **第 7b 节** + `verify_interact_latch.gd` **第 4 节** + `lookdev_journey.gd` 看 `05d_revisit_回访提示`。这一族量的是**回访那一屏写什么**，而三件事曾经各错一处：①`revisit_note` 一句话在第 2/3 次到访上**逐字出现两遍**（`verify_interact_latch` 当时断的是"面板写的是 revisit_note"，那句话对两次都成立，**一个恒真的判据看起来像在守着这件事**）；②轮换出来的乐事**从头到尾没有告诉过玩家**——`_popup_fragment` 那块 Label 在回访时被整个藏掉，于是「三次到访玩的是三件不同的乐事」只活在代码里；③`_apply_language()` 无条件写 `_station_text(idx)`，所以**回访途中切语言会把刚写的那句话刷回驿站的自我介绍**。三条现在都由**同一个** `_popup_body_text()` / `_popup_foot_text()` 收口（面板与切语言共用）。**`verify_interact_latch` 第 4 节先推里程再打卡**（`_odometer_units = _total_arclen`）：不推的话「绕没绕圈」那半边在这一次里恒等于 0，于是**把圈数那一路整个删掉，照样全绿**。**写完先证明它会红**（`python tools/mutate_revisit.py`，11 条突变一个一个撤，全部咬住；它自己会先跑一遍基线，基线不干净就直接退出）
- 改 `PausePanel.gd` / 暂停面板按钮 / `go_to_end_card()` 的触发条件前跑 `verify_minimap.gd` 第 8b 节（出口在不在、零碎片时在不在、收工时评级按走过的算）+ `verify_postcard_ending.gd`（EndCard 得接得住非完满档）
- 改 `QualitySettings.gd` 的任何一处 / `GrassScatter.radius_override` / `TreeScatter.radius_override` / `World3D._ready()` 里那一句 `QualitySettings.apply_to_world(self)` 的**位置** / 暂停面板 `VBox` 的行数或 `separation` / `Localization` 那五个画质 key 前跑 `verify_quality_settings.gd`（**不能加 --headless 之外还要注意 `--quit-after` 给小了**：它要真的起两份 World3D）。这一族守的是"接线"，而接线断掉时**两侧各自都绿**——见下面陷阱清单里那条「写进字段不等于读进世界」。另外两条只有它能量：**面板装不装得下**（多两行之后 VBox 的最小高度超过面板内容区时**不报错**，只把最下面那两行顶出下沿，而"最下面那两行"正好是新加的画质按钮和提示），以及**落盘闸**（`persist` 没有默认值这条靠反射量不到，是读源码文本的）
- 改 `EndCard._show_ending_choice()` / `_seed_back_text()` 前跑 `verify_postcard_ending.gd`（`keep`/`break` 的后果必须落在**正面**：留门=背面写上那句、放手=背面留白且封口的蜡掰开，两张卡片的正文必须**就是**真正会发生的那件事本身，不能另写一段描述——否则又变回"承诺一个差别、实际只改一句话"）
- 改 `EndCard._add_choice_joys()`（`ICON_W` / `ICON_H` / `NAME_DY` / `cell_w` / `cell_gap` / `foot_top`）、`_make_choice_card()` 里那句 `dl.custom_minimum_size.y = two_lines` / `_choice_joys_caption` / `Localization` 的 `ending_joys_caption` 前跑 `verify_postcard_ending.gd` 第 4 节 + `lookdev_postcard.gd` 看 `10_终局二选一`。这一屏原来内容全压在上半屏、**下沿只到屏高的 51%**，而它恰好是全场玩家唯一一次要**比较两个选项**的一屏：①**「空不空」量的是内容下沿到屏幕下沿的距离，不是"有没有加东西"**——而且必须**排除那层 `shade` 遮罩**（它是 `_stretch_full` 的 ColorRect，`get_rect().end.y` 恒等于屏高，"铺满全屏"是它的定义不是它的内容，第一版没排除于是那条恒绿）；②**两张卡的标题必须齐平**：留门那句是单行、放手那句带 `\n` 是两行，而两个 VBox 各自居中，标题就差 12px——差的量是 `get_global_rect().position.y` 而不是 `.position`（`PanelContainer` 延迟排版，排版前两个 Label 都在各自 VBox 的 0 处，差 0px，恒绿）。**"行盒一样高"那一条恒真**（删掉定高后两边都退成 0、仍然相等），它是**指路的不是断的**，所以必须和"齐平"成对写；③这两条断言**必须摆在点击之前**，`_choose_ending()` 把那几个成员全置成 Nil，摆在后面量到的是一堆 null。底部摆的是**五件乐事而不是评级**：评级是 `_show_variant_hint()` 的活儿，提前报就"剧透"了 `11_揭示明信片` 那一屏（`_needs_choice()` 保证五件齐了，所以没有半排状态）。**写完先证明它会红**：删掉 `_add_choice_joys` 3 条红 / 删掉那句定高 1 条红（且只有"齐平"那条红）/ `ICON_*` 退回 56×56 则几何全绿而 `lookdev_postcard` 的像素那条红
- 改 `EndCard._refresh_back_thumb()` / `_grab_back_thumb()` 前跑 `verify_postcard_ending.gd`（SubViewport 回读要等两帧；节流按累计 delta 掐，headless 跑两帧等不到 0.12s，测试里必须等墙钟）+ `lookdev_journey.gd` 看 `16_postcard_back`（要打完字再拍，只拍初始帧看不出缩略图跟不跟得上）
- 改 `EndCard._show_back_editor()` 的布局（输入框高度 / 按钮摆法 / `THUMB_BTN_*`）前跑 `verify_postcard_ending.gd` 第 3 节（量控件几何：两个按钮不叠、都在屏内、缩略图 ≥400px 宽且不遮按钮）+ `lookdev_journey.gd` 的 `16_postcard_back`——那一屏现在带**像素级**断言（暗像素占比 + 落在几条横带上 + 明暗跨度），因为尺寸对了不代表里面真有字，SubViewport 回读到空帧时预览就是一块纯色、尺寸一模一样
- 改 `PostcardBack._message_box()` / `_wrap_text()` / `_message_font_size()` / `_draw_message()` / `_wrap_line()` / `FONT_MIN` / `FONT_MAX` / `LINE_GAP` 前跑 `verify_postcard_ending.gd` **第 3e 节** + `lookdev_postcard.gd` 看 `07_背面_留门_写上了那句` 与 `07b_背面_写满200字`（**成对看**：字号是按这块纸自动定的，字最少和写满是两种排版，只看 07 那一张，"字变大了"看着像只是把默认那句排好看了）+ `lookdev_journey.gd` 的 `16_postcard_back`。第 3e 节量的**不是**字号本身，是**玩家在编辑器那一屏上读到多高的一行字**：卡片在 SubViewport 里按 1920 宽画完再缩到预览上，所以是「卡片字号 × 预览宽 / 1920」这个乘积——卡片上写死 36px 时预览里那行只有 8.5px，而"预览宽 ≥400px"和"字号 = 36"**两条断言当时都是绿的**。三条别的：**每一行都在 `max_w` 之内**（原来的 `_wrap_line` 是"先把字放进去再看超没超"，只在空格处检查的西文会冲出去**一整个词**才收尾，实测一行 1969px vs 框宽 1792px）；**字号是放得下的最大号**（少了这条，把 `LINE_GAP` 或 `FONT_MAX` 调小到"还更空"照样全绿——和第 3d 节那条「`_caption_col_w` 没有算窄」同一个坑）；**读源码文本**钉住画笔真的调了 `_message_font_size`。**写完先证明它会红**：画笔里写死 `36` → 2 条红；`FONT_MAX` 84→40 → 5 条红；`LINE_GAP` 10→30 → 1 条红
- 改 `EndCard._on_restart_pressed()` / `_recap_lines()` / `_recap_worth_showing()` 前跑 `verify_postcard_ending.gd` 第 8 节 + `lookdev_postcard.gd` 看 `12_回执` / `12b_recap_EN`（回执**每一条都要对着存档逐字核对**——编一条玩家没做过的事，第二趟发现根本没有，比不弹更伤；而 `go_to_gift_box()` 会 reset，所以回执只能赶在 reset 之前现算，不许另存快照）
- 改 `World3D` 里那段路过驿站的话（`STATION_PASS_RADIUS` / `_pass_inside` / `HUD3D.show_pass_line`）前跑 `lookdev_journey.gd` 看 `05b_pass`（16 站里有 11 座的 `text` 一直只写在 road_data 里没人读；边沿触发要靠 `_pass_inside`，只判距离会让玩家停在圈里每秒重弹一次）
- 改 `MiniGameTea` / `MiniGameZither` / `MiniGameBamboo` 等五个小游戏里的输入处理前跑 `verify_mini_game.gd` 第 5 节（五个都必须能用 ESC 取消 —— 取消按钮是 `_draw()` 画的假按钮，键盘点不到，茶最糟：既放弃不了又失败不了，键盘玩家唯一出路是干等 30s 超时）。注意 ESC 的插入位置各不相同：琴要放在示范阶段的早退之前、竹要放在 1.6s 成功停留之后（那一下不许跳）
- 改五个小游戏里的**提示文案**或 `MiniGameBird.SHOW_DURATION` / `countdown_fraction()` 前跑 `verify_mini_game.gd` 第 6 节（先量机制、再拿文案对答案）+ `lookdev_journey.gd` 看 5 张 `minigame_*.png`。这一节的判据是"字和代码不许互相拆台"，所以改文案时不能只改文案——先确认代码到底怎么做的
- 改 `GiftBox` 那五个过场常量（`BOX_OUT_SEC` / `ROAD_IN_SEC` / `ROAD_HOLD_SEC` / `ROAD_OUT_SEC` / `SWITCH_DELAY_SEC`）前跑 `verify_story.gd` 第 5 节 + `measure_cold_start.gd`。这五段是冷启动里**唯一**一段纯机器等待，而墙钟判据太粗：把过场调慢一秒，总时长那条（4.6s < 20s）照样绿，只有常量那条会红
- 改 `DemoDirector.gd` 的任何一段（`RAIL_LEAD` / `APPROACH_ARC` / `PRESS_DIST` / `MINIGAME_LINGER_SEC` / `HANDOFF_NOTICE_SEC` / `_steer()` 那一整套）前跑 `verify_demo_path.gd`（**不能加 --headless**）。这一族回归断言的是**演示真的骑了**：累计里程、到过几驿、以及小游戏有没有真的弹出来。只断言「62 秒后到了结算页」的话，`DemoDirector` 一行都不执行、驾驶员在起点站到时间到，照样全绿
- 改 `GameManager.enter_demo()` / `fill_finished_run()` / `demo_mode` 或标题页那个「演示 · 90 秒」按钮前跑 `verify_demo_path.gd` 第 1 节（秒级）。`fill_finished_run()` 走的是**直写字段**而不是 `check_in()`：后者会把 `all_fragments_maxed_reached` 闩锁翻过来，于是 `World3D._on_all_maxed()` 当场锁死操纵权、2.5 秒后自己跳去结算页——而那时候演示还在半路

## 已知陷阱

- **「补齐的那些数」和「说没说它们是补的」是两件事，而后者是玩家的**：
  90 秒演示里 `DemoDirector` 每个小游戏放 4 秒就 ESC 走人，而
  `GameManager.check_in()` 是小游戏做完之后才调的——于是这一趟演示骑行
  **一块碎片也拿不到**（实测收工前采样：700m、2 驿、碎片 0/5），
  而 62 秒时 `fill_finished_run()` 把整趟补成十六驿全到过、五件乐事各三次。
  评审亲手看的是 2 座驿站加一个小游戏弹出来又消失，手里拿到的是一张满卡。
  **试过让它真赢一次**：茶是长按空格三秒，一条通用按键序列就通吃，
  于是写了一整段"按住不放"的逻辑——量出来是**一次都没走到**：62 秒只够停
  两站，起点最近的那座碎片站是**禽**（槽位 4 / 驿站 4）而茶在更远的环上；
  禽要数字键认图、答错立刻判失败，没有通用序列。
  两条教训：**①"能通用按键序列通吃的那一件"在有六个站的世界里是运气，
  而演示的路线不是你能挑的**——量之前先量它到底停在哪；**②补齐不是谎，
  闷声补齐才是**，所以收工改成两拍：先在屏上打一行
  `demo_card_notice`（"演示到这里 —— 下面这张明信片，是走完全程的样子"）
  停 `HANDOFF_NOTICE_SEC` 再换场。空卡教会评审的东西比满卡少得多，
  而**满卡 + 一句交代**教会的东西和满卡 + 沉默一样多，外加一个被拆穿的风险。
  回归钉的是**玩家看得见的那一半**（`HUD3D._pass_label` 的正文），
  而且**只在 `DemoDirector._handed_off` 之后采样**——那一行平时浮的是
  开场提示和十六座驿站的旁白（`road_data` 里 11 座站的 `text` 一直只写在
  数据里没人读，现在由 `_pass_inside` 边沿交给 `show_pass_line`），
  量它们等于没量。删除突变验过：撤掉那句 `show_pass_line` 那条立刻红，
  而报出来的 got 是一条驿站旁白（"编号 188。这条路认得每一个走过的人。"）
  ——这正是"取样窗口取错了一格"长出来的样子

- **「声明了却从没被读过」的 uniform，症状是另一个人在文档里写下的那句话**：
  `asphalt.gdshader` 声明过 `edge_line_color`，**整个项目周期里一次都没被读**
  ——GDScript/shader 都不对未使用的 uniform 报错，也没有任何一条无头回归会红，
  于是"两侧各自都绿"又出现了一次，只不过这次绿的两侧是**代码**和**文档**：
  `CLAUDE.md` 那一行写着路面是「中央白色虚线 + 两侧白色实边线——原来是"双黄虚线"，
  而代码从头到尾只画过一条白虚线」，一句话同时说了现状和历史，而**现状那半句
  一直是假的**。可推广的一条：**"这个东西配了吗"要去搜它的读取点，而不是看它
  的声明**——`.gdshader` 里 `uniform` 的名字和它在 `fragment()` 里的名字长得
  一模一样，只差一次 `grep`；而**文档里那句"原来是 X"更可信**，因为它记录的是
  有人真的以为那里有 X。对策不是改文档了事，是把边线补画出来（断的是那个承诺，
  不是那句话），同时补一条"每个 uniform 都出现在 fragment 源码里"的纯文本回归。
  同族：`--headless` 不编译着色器，所以这一族**没有一条无头回归能量**，
  补画之后只能靠 `lookdev_journey.gd` 看图（`04_ride`）。

- **常量是一条链时，正则抄算式量到的是除数而不是求值结果**：
  `ROAD_HALF_WIDTH := ROAD_WIDTH * 0.5`，拿源码去匹配 `ROAD_HALF_WIDTH`
  读出来的是字符串 `"ROAD_WIDTH * 0.5"`——于是"两侧边线的位置对不对路宽"
  这条断言要么恒绿（比的是字符串里那个 `0.5`）要么恒红，而**两种都不含信息**。
  正解是 `GDScript.get_script_constant_map()`：它返回的是引擎**求值之后**的常量，
  所以那条链读出来是真正的 `3.25`。可推广的一条同族：**拿源码文本量东西时先问
  "这一行会被求值成什么"**——凡是 `:=` 右边带运算的，文本里躺着的就不是玩家
  用的那个数。（和前面「用文本断言钉某条性质之前先确认那个性质真的会在文本里
  留下一个可搜的痕迹」是同一条的两头：一个是搜不到，一个是搜到了却搜错了东西。）

- **同一件东西三处各画一遍，而三份画法不一样时，"修好一处"只改了三分之一**：
  禽这只鸟画过三遍（`FragmentBar._draw_bird` / `FragmentIcon._draw_bird` /
  `Postcard._draw_bird`），云画过三遍（同名三个函数）。区别在于：**云那三份是
  同一个算法的三份抄写**（逐列取最上面的鼓包），所以"抄错了一个数"仍然像云；
  而禽那三份里**有两套不同的算法**——底栏与放大图是「一颗圆 + 一根棍」（读成
  棒棒糖），明信片那份是「一颗填实的圆 + 一片**同色**的翅」（两块并成一颗疙瘩）。
  玩家一路在底栏看着的是一只，进游戏在明信片上拿到的是另一只，而**这正是最贵
  那一屏在拆台**。可推广的一条：**"同一个形状在 N 处出现"时，先确认那 N 处
  是 N 份抄写还是 N 种实现**——前者靠对拍就能发现漂移，后者对拍永远绿，
  因为两份各自自洽。而收成一处之后要量的不是"三处一样"（那是**读源码文本**
  钉得住的），是**"这个形状认得出它是什么"**：禽那一条被拆成尾/喙/栖枝/椭圆身/
  **翅是留白**/装得进 22px 盘六件，前四件几何能量到，**翅是留白只有像素量得到**
  （墨色的翅压在墨色的身上等于没画，而所有几何断言照绿），
  所以 `lookdev_postcard.gd` 那一条的门槛是**量出来的**：翅在 93、翅没画只剩 10，
  门槛取 60；而且"亮一截"取的是**相对量**（比那件自己的颜色亮 0.05）不是绝对白——
  底板是深色屏、翅是 0.30 白压在橙上，AGX 之后两色被拉近，绝对阈值量的是
  tonemap 落在哪一档。

- **「写进字段」不等于「读进世界」，而这一族断掉时两侧各自都绿**：画质档位
  靠一个 `radius_override` 把半径推给 `GrassScatter` / `TreeScatter`。它写在
  世界建起来**之前**，由 `setup()` 读走——所以断言必须量 **setup() 之后的
  `_radius`**，量 `radius_override` 那个字段被写了等于什么都没量：字段写了而
  setup() 没读它（接线断在散落体那一头），或者写了又被 `target_radius()`
  盖回去（接线断在散落体自己那一头），两种都表现为"字段有值"而世界是 200m 那一档。
  **同族的第二个坑是"不写"不等于"清空"**：高档那一档的半径是 -1 = 不动，
  于是 `apply_to_world()` 第一版写成"只在 > 0 时才写"——override 是**粘的**，
  玩家在低档下把世界建起来（override=70）、再切回高档，阴影当场回来了、按钮也
  写着「高」，而**下一趟的草皮还是 70m**。这一条两侧更绿：阴影那侧量的是当场
  生效的开关（确实回来了），半径那侧量的是这一趟建好的 `_radius`（确实还是 70，
  符合"不重建"的预期）。正解是把 -1 落成 **0**（`maxf(..., 0.0)`，0 = 不接管）。
  连带一条**量法上的教训**：这一批断言我是**四个突变一起做**的，结果
  「世界不推档位」那个突变顺手把 override 清成了 0，于是"粘住"那个突变
  **一条红都没报**——掩体是另一个突变提供的。**突变要一个一个撤**，批量做的时候
  一个突变会把另一个的失败路径垫掉，而"全绿"这时候最危险。

- **带 `autowrap_mode` 的 Label 不给 `custom_minimum_size.x`，它会一个字一行**：
  暂停面板那行画质提示 33 个中文字，实测 `get_combined_minimum_size()` 是
  `(1, 586)`——宽度 1px，于是自动折行按**逐字**断，33 行 × 17.75px。整列最小高度
  从 452px 涨到 1022px，而面板内容区只有 464px（720p）。**VBox 装不下时不报错**，
  只把最下面那两行顶出面板下沿——而最下面那两行正好是新加的按钮和提示，
  于是"面板按钮多了一行"这件事在画面上表现为**新按钮不见了**。
  修法是给一个真实折行宽度（440px，中文一行、英文两行）。
  连带两条同族的：**"多量两遍分辨率"必须真的把窗口改掉**（第一版两次调用量的是
  同一个 rect——headless 下视口是固定的 `project.godot` 窗口大小，于是"720p 和
  1080p 都装得下"实际上只量了一次）；以及**英文往往才是卡边的那一份**
  （108 个字符约 650px，33 个中文字只有 396px），只量中文的话英文界面下溢出。

- **判"某个参数有没有默认值"要找对子串**：`set_tier(t, persist: bool = true)`
  那一行里**不存在** `"persist ="` 这个子串——中间隔着 `: bool `。第一版就写的
  `not sig.contains("persist =")`，于是把默认值写回去之后那条断言**照样绿**，
  它从写下来那天起就是恒绿的。判据改成"**参数表里一个 `=` 都没有**"。
  可推广的一条同族：**用文本断言去钉某条性质之前，先确认那个性质真的会在文本里
  留下一个可搜的痕迹**——搜不到不等于性质成立，只等于判据量的是别的东西。
  顺带一条相邻的：**只测"闸没开"的话，一个从来就不落盘的函数也能让那条绿一辈子**，
  所以落盘闸这一族必须配一条**正对照**（闸开着的时候确实落盘了）

- **想量一块 3D `Label3D` 在屏上占多大，两条路都是错的，第三条才对**：
  ①按 `outline_size × pixel_size` 反推——**描边并不按那个算米铺开**，
  手算出来的框比真牌子高出三倍，一头顶进亭子的屋顶、另一头顶进天；
  ②改问节点自己的 `Label3D.get_aabb()`——它给的是一个**立方体**，
  三条边都等于那一行字的**总宽**（"起程驿楼" 4 个字 → 2.30m，
  "花房·禽语湖湾" 7 个字 → 3.66m，y 与 z 和 x 一模一样）；
  ③按 `global_transform` 投 8 个角——可是 **`billboard` 是在顶点着色器里转的，
  节点的 `global_transform` 根本没跟着转**，于是牌子是**侧着**看的，
  同一批四字站量出来的横向宽度有 8px / 27px / 38px / 75px 四种
  （16m 外那栋楼的角度差一点就整块侧过去），竖直方向还被透视拉长近三倍。
  **唯一对的那条**：宽度用 `Font.get_string_size()`、高度用 `Font.get_height()`，
  都按 `pixel_size` 折成米，两根轴取**相机的 right/up**（billboard 永远正对着
  相机），从 `g.global_position` 四周对半开。量出来的尺寸对得上算式
  （4 字 → 74×22px、3 字 → 56×22px、7 字 → 118×22px）才算数。
  另外 `get_font()` 在没显式设过字体时返回 **null**，要退回
  `ThemeDB.fallback_font`——`GameManager._ready()` 已经把它换成项目的 LXGW，
  所以那正是绘制时用的那一份。**三条错路都被同一件事判了死刑**：
  把描边加粗到 60（一个字糊成一坨奶油）时判据照样全绿——量的是
  "这块地方够不够有结构"，不是"这块地方有没有字"。可推广的一条：
  **节点的包围盒不是它画出来的那块面**，凡是要量"玩家看得见的那一块"，
  先想清楚那块面到底由什么定义

- **`outline_size` 改多大都不会盖住字**：它是从字身**向外**膨胀的，而墨核
  （`modulate` 那个颜色）永远画在最上层。实测 22px 的字身配
  `outline_size = 60`，墨核还剩约 2px 宽的一根根竖线，一个字也没糊掉——
  字符图打出来看得很清楚。所以**"把描边加粗"当不了任何判据的突变**，
  它压根不改变"墨够不够多"这件事。想让字真的糊掉得改 `pixel_size`
  （小到字核掉到 1px 以下）或 `modulate` 本身

- **`Input.parse_input_event()` 的按下和松开必须分在两帧里**：挤在同一帧的话，
  `World3D._physics_process` 里那条 `Input.is_action_just_pressed("interact")`
  判定时这一帧已经松手了，于是打卡分支一次都进不去——车停在站前、空格按了
  十几下、世界一点反应都没有，**控制台一行红字都没有**。`DemoDirector._send_space()`
  第一版就是这么写的，62 秒里按了十几次空格、碎片 0 块，看起来像"演示不会打卡"。
  判据：注入的按键要按住若干帧（`DemoDirector` 用 80ms）再松。
  同族的另一头见下一条——`parse_input_event` 和 `root.push_input` **不许同时用**，
  两条路都走会让一次按键被 `_gui_input` 收到两遍

- **16 座站全都摆在离中心线 18m 处，而 `STATION_PASS_RADIUS` 是 15m**：
  也就是说**贴着中心线骑，一座站既"路过"不了也靠不近**——`on_station_pass()`
  和 `_nearby_station_idx` 用的是同一个半径。实测一整圈里离最近一座碎片站的
  最近距离是 21.9m，到过的驿是 1 座、碎片 0 块。打卡是要拐下路、把车骑到亭子
  跟前去的，那正是玩家做的事；任何"沿中心线自动骑"的自动化（`DemoDirector`、
  录制回放、以后的自动导览）都必须显式把站点当目标，否则它会在一条永远
  够不着的路上空跑一整圈

- **`Player3D` 的转向速率按速度缩放，所以"转弯时松油"是个死锁**：
  `turn_factor = clamp(|speed| / 3.0, 0, 1)`，`abs(_speed) <= 0.5` 时直接为 0。
  于是"误差大 → 松油 → 停住 → 更拧不动"——第一版 `DemoDirector` 骑了 0 米。
  只能**降速不能停**：用占空比（拧不过来时 1/2），车永远在动、转向一直有效。
  而占空比的下限是 1/2，试过"误差大就用 1/4"：开局车头歪着（出发点上前视点
  在侧后方 152°），25% 的油门攒不起速度、速度不够就拧不动，62 秒只骑了 8m。
  **对准了就是满油**——占空比是用来拧把的，不是用来巡航的

- **「一个体验问题」和「一把量错的尺子」在日志里长得一模一样**：冷启动曾经被记成
  「65 秒」，然后当成 P0 排进计划。写了 `tools/measure_cold_start.gd` 重量，
  真值是**连打 4.6 秒 / 人读 6.2 秒**——从来没有接近过 65 秒。错在
  `play_newcomer.gd`：空格**只在 `dlg.visible` 时才发**，而操作说明面板不是
  `DialoguePopup`，于是玩家站在面板前的那几秒里一次空格都没发出去，
  `_can_move` 也不可能变真，循环注定跑满 40 秒预算并报「按了 0 次空格、40.0 秒」。
  计时还叠了一层 `t += 0.016`（帧率不等于 60 时低报）。教训：**先问这把尺子
  凭什么能通过**，再问被测的东西有多慢——一个恒等于预算上限的读数根本不是读数。
  新工具走的是玩家真按的那条路（`StartBtn` → `change_scene_to_packed` →
  World3D → 操作说明 → 序章）；旧脚本把 `GiftBox` `queue_free()` 掉、自己
  `instantiate()` 出 World3D，**把整段过场动画绕过去了**，量不到该量的东西。

- **「两个字符在字体里长得不一样」不等于「玩家分得出来」**：顶栏那三个音频开关
  原来用 ♫(BGM) / ♪(音效) 区分，字符串判据（`"♫ 开" != "♪ 开"`）**全绿**——
  它本来就该绿，两个码位不同。而 `Font.has_char(0x266B)` 也报 true，单独放大
  到 64px 渲染，那根横杠画得清清楚楚。问题全在**字号**：顶栏按钮是 18px，
  那根横杠在这个尺寸下是亚像素的，两个按钮读起来是同一个东西。
  第一版把它记成「字体缺字形、回退成 ♪」——**那个诊断是错的**，写进注释里
  差点就成了下一个人的前提。判据是"在实际字号上还剩多少差别"，那只有图能量：
  定妆照 `04_ride` 的右上角裁出来放大 5 倍才看得出差一根线。
  改法是换成词（`bgm_short`「乐」/ `sfx_short`「效」），
  `verify_mood_mask.gd` 的 `_audit_audio_buttons()` 现在多钉一条：
  区分用的那个字符必须是**字**（CJK / 拉丁字母），不是符号。
  做过变异验证（把 ♫/♪ 填回去）：新判据两条红，原来那条字符串判据**照样绿**。
  可推广的一条：**断言要量玩家用的那个量**——"两个值不相等"和
  "这两个值在 18px 上分得开"是两个量，而后者量不到的时候，
  至少要把判据写成后者能被代理的形式（"用字，不用符号"）。

- **界外的草地不是"难走一点"，是一堵压过油门的墙**：`World3D._apply_boundary_force()`
  离路心线 `SOFT_BOUND`(12m) 之外就开始往回推，而 `Player3D.ACCEL` 只有 8.0 m/s²
  ——推力在 **21m 之外就压过自行车自己的加速度**了。推的方向是**位置**的修正，
  不是速度，所以车不会停、只是每帧被往回搬一截。实测一辆满速 15m/s 的车在
  27m 处**正好被钉住**：油门每帧走 0.25m，边界力每帧也搬它 0.25m，两股力
  精确抵消，于是"距目标 132m"三分钟一动不动，闩锁现场每一条都是放行的。
  这个坑量过两次才认出来，而两次的症状都是"车不动"：第一次量到的距离是
  **一条直线**（脚本横穿草地直奔下一站），把"这辆车开不过草地"当成了
  "这辆车坏了"；第二次读数是沿路走的（`_road_waypoints()`），才定位到推力公式。
  真人不会横穿草地——小地图上画的就是路——但这也说明**路外那一圈草地没有任何
  理由让玩家进去**，而它现在不但进得去，还进去就出不来。回归验证：无（这一族
  全靠 `play_newcomer.gd` 那把尺子量出来，几何断言量不到"推力大于加速度"）。
  可推广的一条：**"这辆车怎么不动"要先问它想去哪**——推力、转向、油门三者
  里只要有一个的作用方向和意图相反，症状就长得和"卡住"一模一样。

- **`t += 0.016` 和 `t % 0.3 == 0` 是同一个错误的两种写法**：前者把「一帧」
  当成 1/60 秒（本机带窗口能跑 280+ FPS，只低报不虚报，所以错得不容易发现）；
  后者是浮点累加撞精确等号，**一次都撞不上**，于是「每 0.3 秒按一次空格」实际
  是「一次都没按」。两种都表现为「时间过去了但什么都没发生」，都不报错。
  带 `await process_frame` 的循环里一律用 `Time.get_ticks_msec()`。
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
- **调用一个带 `await` 的函数而不 `await` 它，函数体会静默停在第一个 `await` 上**：
  GDScript 调一个含 `await` 的函数不写 `await` 是**合法**的，函数从头跑到第一个
  `await` 就把控制权还给调用方，剩下的挂在那里等一个**没人等的信号**。所以
  `verify_mini_game.gd` 新加的 `_section_backdrops()` 第一版打成
  `_section_backdrops()`（漏了 `await`）时：标题和前 6 条断言照常打印，
  到第一个 `await process_frame` 静默停住，主协程接着跑完、打出
  `PASS failures=0`、`quit(0)`——**一整节断言一行没跑，报告却全绿**。
  这跟上一条「`await` 挂死」是同一个家族（都表现为"静默"，都不报错），
  但成因不同：那条是**协程内部**的信号永远不来，这条是**调用方**没接。
  判据是"这节的断言数是不是每次都一样"——新增的断言第一次跑就没印出来，
  就不是它绿，是它没跑。两处对策：新加的节要么调用处写 `await`，
  要么干脆别用 `await`：能不挂进场景树就不挂（`MiniGameZither._string_rects()`
  是纯几何函数，`new()` 出来设个 `size` 直接调，连节点都不用加）。
  跑完记得数一遍输出里的 `[OK]`/`[FAIL]` 是不是预期的那个数。
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
  同族：虚构地名「十八驿」是旅店的名字，而顶栏写「已过 n 驿」——两个数字放在
  同一屏上，玩家只会对着算然后认定一个是 bug，所以 `back_keep` 里它得加引号、
  英文得带 "inn"，读起来像专名而不是序号。

- **这个世界的环路只有 1228.8m，「188」是编号不是里程**：8 字路 `LEMNISCATE_SCALE = 350`，
  实测 `total_arclength() = 1228.8`（bbox 329×361m）。而 `GameManager.TOTAL_ROUTE_KM = 188`
  把它摊开，按 15 m/s 满速折算是 **2 km/s ≈ 7200 km/h**，跑满一整圈只要 82 秒。
  玩家骑三十秒就能心算出这个数，然后「188」这个题眼连同它承载的一切门槛一起变噪音。
  所以顶栏、所有文案、所有解锁门都已改成**驿数**口径（`GameManager.get_seen_station_count()`，
  顶栏写「已过 n 驿」），里程只在内部作旅币经济口径。已从 km 门迁走的：
  灯铺解锁（`seen_unlock = 6`）和 `World3D.VILLAIN_SCENES` 三场郑铎戏（`seen = 4/8/12`，
  原来是 50/100/150km，也就是开局第 25/50/75 秒把整条反派线灌完）。
  `verify_economy.gd` 的 `_check_km_offscreen()` 会扫全部文案里的
  `km / 公里 / kilometer / kilometre / K0 / K188`——**关键词要查全**，只查 "km" 会漏掉
  中文的「公里」（第一版就漏了 `onboarding_subtitle` 的「沿188公里环形路线」）；
  英式拼法 "kilometre" 也不是 "kilometer" 的子串（e 和 r 换了位置），得单独列一条。

- **「这处该用项目的字体，可它写的是 `ThemeDB.fallback_font`」是个看着成立、
  其实不成立的缺陷**：`GameManager._ready()` 第 111~112 行就把
  `ThemeDB.fallback_font` 整个换成了 `res://assets/fonts/LXGWWenKai-Regular.ttf`，
  所以全工程任何一处 `ThemeDB.fallback_font` 在运行时**就是** LXGW。
  评审意见里那条「提示文字用的不是项目字体」就是这么来的：只读
  `CheckInPrompt._draw()` 那一行，看到 `ThemeDB.fallback_font` 就判了不一致，
  而看不到另一个文件里的那一行替换。
  **凡是「A 处的默认值被别处覆盖了」这类判断，先跑一行代码把运行时的值读出来**
  （`print(ThemeDB.fallback_font.resource_path)`），再决定要不要改。
  同族：`Localization` / `Postcard` 那些「值和别处对不上」的怀疑，也要先确认
  那个值到底是不是真的被谁在运行时改掉了。判据是**跑出来的**，不是读出来的。

- **驿站占地是从模型量出来的，不是手填的一张表**：`MeshInstance3D.get_aabb()`
  读的是网格自己的局部盒，**既不含节点上的缩放也不含旋转**——驿站统一乘
  10~14 倍，直接拿它当占地，半径会小一个 `scale`（最大那座差 7 倍）。
  `_measure_station_aabb()` 把「站 → model → 网格」这一串变换逐级乘起来才量，
  而量出来的 16 个半径是 3.43~9.40m，随模型改而改。
  **别为了"省事"把它抄成 `STATION_GLB_CONFIG` 里的一个字段**：那是 16 个数里
  迟早有一个跟模型对不上的那种表，而对不上的时候玩家骑进亭子里、没有任何回归会红。
  同族的教训：**这一圈墙必须在半径小于 `STATION_PASS_RADIUS`(15m) 的前提下成立**，
  所以任何"把余量调大一点"的改动都要先看那条断言。

- **`Player3D` 没有碰撞求解器，所以世界的墙只能是硬推出**：
  它每帧 `position += forward * _speed * delta`，不走 `move_and_slide`。
  15m/s 下一帧 0.25m，任何"软力推开"都拦不住——`_apply_boundary_force()`
  用软力是因为路边界在草地外面，推不推玩家都无所谓；
  而亭子是实心的，推不动就意味着车在里面、相机在里面。
  所以 `_apply_station_keepout()` 是**直接把位置摆回边界**，
  并且必须配一道 `damp_speed()`：位置摆回去了而 `_speed` 还在，
  车每帧被推出去又每帧往里冲，玩家看着像卡在墙里抖。

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

- **草皮的"卡片"不是草：一片 0.34×0.15m 的卡片上只画 7 片叶，图上是一堵墙**：
  玩家相机离地 1.6m，而一丛草占掉半米见方、7 片叶又宽又大，近景整片读成
  **龙舌兰**而不是草——`lookdev_grass.gd` 的 4m 那张就是这么翻车的，
  路面被草挡掉一半，顶栏那条"下一处"的引导也就断了。真实路肩草是**矮而密**：
  靠丛数不靠每丛的尺寸，所以正确的方向是卡片收到 0.24×0.085m、而
  `blade_count` 从 7 提到 10 来补覆盖度（收到 4m 那张才站得住）。
  连带两条：`fragment` 里那个 `for (int i = 0; i < 8; i++)` 的上限是**硬编码**的，
  把它调到 10 而循环还写 8 会被静默截断成 8 片——**看着像**"我调密了"，
  一片叶子都没多；`hint_range(1.0, 8.0)` 的上界也是 8，两处必须一起改。
  回归验证：`verify_grass_scatter.gd` 末节（从**文本**里读这几个值，
  因为 headless 不编译着色器）+ `lookdev_grass.gd` 看图。

- **草皮读成"一地麦子"是明暗反了，而已有的两条判据只管纯度**：卡片收小之后
  4m 那张放大 4 倍量到的仍然是"一地深色的秆插在亮的地上"——`blade_base`
  (0.29,0.34,0.23) 比它自己的 `ground_color` (0.38,0.48,0.29) 暗一大截，
  190m 那张则整圈读成地平线上一条又暗又冷的带。**眼睛先读明度再读色相**，
  而"退饱和（绿红差 ≤ 0.10）"那两条量的是纯度，于是两版颜色都过。
  三条连着的教训：
  ①**逐通道的判据不是"更严"，是量错了量**。第一版按"三个通道各自 ≥ 地色"写，
  于是唯一效果是把蓝通道顶上去——而草叶卡片是**竖着**的、吃天空环境光（蓝），
  地面是横的、吃太阳，渲出来草叶 (84,113,107) b/g=0.95 对地 (71,114,77)
  b/g=0.68，一丛**青灰色的秆**插在绿草地上，比原来那版还难看。正解是判
  **相对亮度**（`_luma`）和**绿红比**，蓝留给环境光去染。
  ②**取阈值要看玩家实际看到的那一侧**。同一族的第一个版本拿
  `min(ground_color, ground_dark)` 当地板（暗的那档），而 blade_base 恰好比暗地
  亮一点点——于是那条断言从写下来那天起就**恒绿**，它量的是"草比最暗的土亮吗"。
  ③**明暗两版之间要留余量**，判等的话渲染管线一动就翻面。
  判据量的是 albedo、`--headless` 编译不了着色器，所以**"渲出来到底绿不绿"
  只有图能量**：定妆照 4m 那张放大 4 倍 + 按饱和度把像素分成草/地两组取均值。
  回归验证：`verify_grass_scatter.gd` 末节"比脚下的地亮"+"绿红比"四条，
  `lookdev_grass.gd` 看 4m / 45m / 190m。

- **`ROAD_CLEAR` 量的是到路**中心线**的距离，不是到沥青外沿**：
  写的是 `TOTAL_HALF_WIDTH(6.5) + 1.5 路肩` = 8.0，而"调到 6.2 让草长到路肩上"
  这个想法会把草种到沥青上——中心线到沥青边才 6.5m，6.2 < 6.5。
  顺带记一条免得下次白忙：**挡视线的是草高不是密度**。把卡片从 0.15m 降到
  0.085m 之后，路自己就露出来了，不需要为视线另开一条走廊、也不该动密度。

- **改完着色器别把一次 7ms → 16ms 的跳变算到自己头上**：那次跳变是在一次
  **只改颜色**的编辑之后出现的，而颜色不花片元预算。把 `blade_count` 退回 7
  再跑，单帧一模一样还是 16.20ms——**那就不是它的账**。同族的判据就是本文件
  已有的那条：先 `tasklist` 查有没有上次掐掉的 Godot 还在吃 CPU，
  再把可疑的那一项单独退回原值跑一遍，两边都动不了才轮到怀疑自己。

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
  **同一条陷阱还有一个没被绕过的后果**：正因为不能碰 HBox 里任何一个 Label 的
  最小宽度，"给『下一处』单独加一块深色底板"这条路是**堵死的**——`StyleBoxFlat`
  会把 Label 的最小尺寸撑大，于是它右边什么都没有了也会把整排标签推走。
  要单独垫底只能走绝对定位的兄弟节点（`_lvbi_toast` 那种），代价是那个底板
  不会跟着 HBox 排布移动。顶栏对比度最后是靠**抬高整条衬底的实底段**解决的，
  不是靠给单条标签垫板。

- **容器"排到哪"由它自己声明的 rect 决定，而子节点溢出它时没有任何人会吭声**：
  `World3D.tscn` 里 `TopBar/HBox` 写的是 `offset_right = 480`（468px 宽），
  而它那五个标签要 ~663px——于是 **~195px 静默溢出**（`Control.clip_contents`
  默认 false，没有任何报错、没有一条回归看得见），顶栏排到哪里从此由**那行字此刻有多长**
  决定，右端永远悬在半路，衬底比字宽出几百像素，图上读成一条黑带。
  可推广的一条：**量"排版占满了没有"要量容器自己的右沿和最后一个子节点的右沿之差**，
  别只量子节点互相不叠——**互不叠和没留死区是两件事**，而后者才是玩家读得出来的那个。
  而宽度会变的顶栏，正确做法是让容器说实话（`anchor_right = 1.0`，
  `offset_right = -(TOP_RIGHT_W + TOP_RIGHT_GAP)`）并把长度变化全交给
  **心神和「下一处」之间那个 `SIZE_EXPAND_FILL` 弹簧**（`custom_minimum_size.x = 0`），
  于是顶栏右端钉死在按钮排左边 16px，无论那行字多长多短。
  同族的第二个坑：**「没有目标」不等于「没有话说」**。`fragment_station_needs_visit()`
  五座都还清就返回空字典，`_update_next_label()` 那个空分支原来写的是 `text = ""`，
  于是刷满之后（也就是玩家最该看着那一栏的 2.5 秒）整条空掉；数字上没有任何回归
  看得出问题，因为"空串"和"该有话"在断言里长得一模一样。现在写 `hud_all_done`。
  回归验证：`verify_mood_mask.gd` 第 10 节（三条判据：容器不许溢出自己的右沿 /
  一直伸到按钮排左边 /「下一处」和按钮排之间没有空档）+ `verify_minimap.gd`
  第 10 节末尾（刷满后那一行不是空的、且报的是那句收尾）。两处都做过删除突变，
  改回去分别红 2 条

- **顶栏背后最亮的是正午的天，而它比那行金字本身还亮**：
  实测 `12b_day_正午.png` 里衬底之外的天 ≈ sRGB(198,210,237)、相对亮度 0.642，
  而顶栏米金 ≈ (245,200,126)、0.621。所以「把衬底调暗一点」这个直觉**没有出路**
  ——衬底本来就是接近黑的 (#07080C)，再调暗它也压不住一个更亮的背景。
  唯一能动的是 alpha：合成亮度 = a·0.0069 + (1-a)·0.642 ≤ 0.099 才够 AA 的
  4.5:1，解出来 **a ≥ 0.855**，所以 `SCRIM_TOP_ALPHA` 是 0.90。
  旧版 0.46 的纯 pow 渐变实测只有 **1.22~1.36:1**，字在天上等于没写——
  而 `verify_mood_mask.gd` 当时全绿，因为它只断言"两层 alpha 有先后"，
  从没量过合成之后到底看不看得见。
  连带一条：**实底段必须盖住整条文字行盒，不只是字形**。18px 的字在
  `SCRIM_H`(62px) 里占到 t≈0.23~0.61，行盒比字形高、下面一截是降部留白；
  按字形量出来是 0.23~0.52，按行盒量出来是 0.23~0.61，而 `SCRIM_SOLID_FRAC`
  要按后者取（现在 0.68）。回归验证：`verify_mood_mask.gd` 第 9 节。

- **算 WCAG 对比度时"谁除以谁"必须取 max/min，不能假定合成后一定更暗**：
  第一版把比值写死成 `(合成+0.05)/(字+0.05)`，而合成是暗的、字是亮的，
  于是每个比值都小于 1，最差那行报出 **0.18:1**——看着像灾难，
  真值是 1/0.18 = 5.6:1，方向反了而已。
  教训是可推广的：**归一化对称的量才会出现这种"红得没有道理"的失败**，
  所以判据要写成单边的「≥ 4.5」而不是「比某个值小」，
  并且失败时先确认自己要断的是哪一边（同 `verify_minimap.gd` 那条"别把极性写反"）。

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

- **"空着的一块"和"被排满的一块"是同一个量，量排版要量到边缘去**：
  明信片抬头的右三分之一约 880×410px 一直是空白的纸——五个到访次数挤在
  「已过 n 驿」底下那一行，剩下什么也没有，而这是玩家**唯一带走**的那张卡的抬头。
  挪成右半一列五行之后那一带才排满，连带「每处去过三次、于是五件乐事轮换着来」
  这件玩法上最要紧的事第一次在卡上读得出来。
  可推广的一条：**凡是"一块该有东西的地方现在是空的"，先量"这一块的右沿到
  版面右沿还有多远"，再想内容**；只量"东西之间有没有互相压到"的话，
  一整块空白是"排得很整齐"的满分答案。
  同一族的第二条：**右对齐的 `draw_string` 那个宽度是**裁切**宽度**，
  字比它宽就整段被切掉——所以"排得下"必须量 `get_string_size()` 而不是量列宽。
  第三条：**几何纯函数对不对，和画笔有没有去调它，是两件事**。
  把 `_draw_map_caption()` 里那行 `_draw_joys_column(...)` 删掉，
  第 3d 节那三十几条几何断言**全绿**（`--headless` 一笔都不落盘），
  而图上重新变成空白的纸——所以这一族照 `verify_mini_game.gd` 第 6g 节的读法，
  另加一条**读源码文本**的判据钉住调用点。回归验证：`verify_postcard_ending.gd`
  第 3d 节（中英 × 900/1920 四种组合 + 那条读文本的）。三条突变都做过：
  删掉画笔里那一行红 1 条、右沿退回 `w*0.62` 红 4 条、图例那项不加算那 44k 红 4 条。
  顺带记一条**做突变时才发现的**：把左列的宽度按**这一趟的实际驿数**算而不是
  按最宽情形算，**没有一条断言会红**——因为图例那一行本来就比驿数那行宽。
  这不是断言漏了，是那个改动在当前字号下确实无害；而它也说明
  「拿同一个 helper 自己的输出去断它算得对不对」是**恒真**的，
  判据必须在测试里**把那几行字各自量一遍**

- **拿掉一条结束路径，就得补一条出口**："集齐即结算"换成"刷满才结算"之后，
  这一趟**原本没有任何玩家可主动喊停的出口**——暂停面板里只有「重新开始」，
  而它走 `go_to_gift_box()` → `reset()`，把 `collected` 一起清掉。后果是
  `PostcardVariant` 的前四档（初旅/探索者/朝圣者/大师）全成了走不到的死代码，
  玩家只剩从头再骑一遍。修法是在 `PausePanel` 里加「结束这一趟 · 收下明信片」，
  零碎片时不出现（那时候做出来的是空卡，EndCard 上没有任何说法）。
  **凡是删掉"到某个状态自动结束"的地方，都要回头问一句：那件事现在还能不能做完？**

- **只减不增的资源是一条单向的下水道，而"上限"不写出来玩家就不知道自己掉到哪了**：
  心神原来满工程只有 `cost_mood()` 一个写点、**零个**恢复点（grep `restore_mood|
  mood +=|refund_mood` 只找得到扣的）。收满五块碎片正好把初始的 4 打到 1，
  而 1 是 `MOOD_MASK_MAX` 那一档 —— 于是**玩家最需要看清世界的那一刻
  （集齐二选一那面面板）恰恰是全场最暗的**。三处一起改：
  ①顶栏 `mood_label` 从「心神 %d」写成「心神 %d/%d」——不写上限的话，
  玩家永远分不清「掉到 1/5」和「掉到 3/5」，而这两个读起来一样；
  ②补 `restore_mood()` + 茶铺的「清心茶」（`grant: "mood_up"`，满心神时
  `can_buy()` 真的挡住 —— 灰按钮只是画给人看的，绕过 disabled 的程序化触发
  照样能把钱花掉）；③`MOOD_MASK_MAX` 0.52 → 0.34。**降遮罩的前提是有上行口**，
  没有它的话玩家只剩一条下水道。顺带两条：
  **拿一个已有的数字和"同一张表里的另一个数"比，是很自然的**，而新的商品会
  把整张预算表挪走（合理全购 890→1010、缺口 91→211、商品数 9→10），
  `shop_data.gd` / `GameManager.gd` / `verify_economy.gd` 三处的注释都抄着
  这个数，**三处都要一起改**，少改一处下一个人就照着旧数算预算。
  回归验证：`verify_shop_panel.gd` 第 6b 节（真的涨回来了、满时买不掉、
  封顶 3 杯）+ `verify_mood_mask.gd`（顶栏上真的看得见分母，这条单独写：
  原来那条是拿标签去比**同一个 key 渲染出来的句子**，key 里的 `%d` 掉了几个
  它照样全绿）。

- **"离地多高"和"看得见"是两件事，而碑面下沿的地面不是 y=0，是石台顶**：
  交叉点那块碑原来石台 0.95m、石板下沿落在 0.16m，于是 0.79m 的石板和
  整行题字**埋在石头里面**。图上是一个闭环加一条尾巴（下瓣被石台沿齐刷刷切掉）、
  题字一个字没有，而包围盒、刻线逐点对拍、面朝向、段数**四十条里三十几条全绿**——
  4.1 那条断言写的是"离地 y=0 超过 0.05m"，量的是土，从来没量过石台。
  可推广的一条：**判"这个东西玩家看得见吗"，要量的是它和最近的遮挡物之间的距离**，
  不是它和坐标原点的距离；而碑、房子、箱子这类东西，脚下往往有一块**比地面高**
  的基座，那块基座才是遮挡的下沿。对策两条：把"抬多高"写成 `static func face_lift()`
  从基座高度**算出来**（写死 `PLINTH_H + 0.20` 就是一个雷：碑面高矮一动，
  题字就悄悄埋进去），以及回归里补一条**离基座顶**的判据。
  变异验证：把 `face_lift()` 换回旧的那个写死值，4 条立刻变红。

- **"低头才看得清的那一档，恰恰是最躺的一档"**——这两条要求在一块石头上
  是打架的，而当时没有人发现，因为两边各自都成立。那块碑原来后仰 40°，
  理由写着"站着低头就正对着脸"；量过之后：1.94m 的面后仰 40° 竖直跨度只剩
  1.49m，为了让下沿不埋进石台就得整体抬高 1m 多，碑顶顶到 2.9m——于是
  玩家得**仰头**，而仰头那一刻正好看到石板的一条窄边。两条要求各自都能找到
  数字支持，合起来是一个谁也读不到的东西。可推广的一条：
  **量"可读性"要量玩家的眼睛到目标的连线（目标心离地 vs 眼高 1.6m、
  目标顶 vs 仰头阈值），不是量一个描述设计意图的角度**；
  凡是"为了让 X 更 Y"而设的旋钮，先问一句"这个旋钮是让 X 更 Y，还是让 X 更不像 X"。
  顺带一条关于断言：把 "tilt ∈ (20°, 60°)" 换成 "tilt ∈ (5°, 25°)" 时，
  那条断言守的东西整个变了（从"要仪式感"变成"要能读"）——**改断言的极性
  要连理由一起改**，否则下一个读代码的人会以为那条守着的是原来那个意思。

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

- **一条闸的断言可能因为"它自己的前提从没成立"而恒绿，删掉闸也拦不住**：
  `verify_interact_latch.gd` 第 9 节的场次间隔闸（`VILLAIN_MIN_STATION_GAP`）
  第一版删掉闸之后照样全绿——量的是"第 3 场没排上"，而那一版测试只把
  `seen` 顶到 11，`VILLAIN_SCENES[2]["seen"]` 是 12，所以第 3 场**压根没武装**，
  无论闸在不在它都不会排上。断言绿是因为它量了一个不存在的东西。
  同一条测试里还叠了第二个坑：`while _world._villain_playing` 是在
  `_villain_playing` 变 false 的**那一帧**退出的，下一场要等下一个
  `_physics_process` 才起播，不等的话量到的是"还没轮到它"而不是"被闸挡住了"。
  对策两条：断言前先钉一条**只钉前提数量**的断言（驿数 ≥ 第 3 场自己的阈值），
  而且**不要把 `armed` 写进前提**——它此刻为 true（被闸挡住）或 false（已经起播）
  两种都是对的；以及推完场之后 `await create_timer(0.5)`。
  回归验证：`verify_interact_latch.gd` 第 9 节（两道闸都做过删除突变，删任一道都必须红）。

- **`lookdev_journey.gd` 看不见反派戏，所以新增的入场提示差点只有数字守着**：
  这份脚本为了拍后面的集齐屏，末尾会把 `_gm.seen_villain` 顶到 3——于是
  中间整段流程里三场反派戏一次都触发不了，而"手机响了。"这行字是压在
  玩家正看着的骑行画面上的新东西。第 13 节现在自己上膛第 0 场
  （补足 4 座驿 → `_villain_armed` 全开 → `_teleport_open_road()`）再拍 `04b`。
  两个连带要求：**瞬移完不能同一帧就断言 `_villain_playing`**（判定在
  `_physics_process` 末尾），以及**拍完必须把整场推完**——不还相机的话
  后面每一张都停在被冻住的镜头上。

- **一次只排一场的闸，值记的是"上一场开演时的驿数"而不是"上一场结束时"**：
  `_villain_last_play_seen` 在 `_play_villain_scene()` **开头**就写，而闸在
  `_try_villain_scene()` 里比的是 `seen < _villain_last_play_seen + GAP`。
  写"结束时"看起来更对称，其实会把对话时长算进间隔里——玩家读三场对白
  花了十几秒，闸却以为他一秒没停，于是刚读完第三场就又开第四场。

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
  **它的下游还有一条**：天色一旦真的建出来了，`verify_mood_mask.gd` 第 9 节
  声明的「顶栏衬底的最坏背景」就不再等于正午那档天实测出来的颜色了
  （它那个数是按"天是一整片 sRGB(198,210,237)"量的，而换成渐变之后衬底底下
  那一行只有 0.16 的相对亮度）。那条数**不许因为"实测值变好看了"就往下调**——
  `SCRIM_TOP_ALPHA` 取 0.90 的唯一理由就是它；`lookdev_journey.gd` 里那条
  跨脚本断言（衬底底下那一带比声明值暗）就是防这个的。

- **"我照着显示器调了个颜色，结果渲出来不是那个颜色"——先问它是不是要自己转色彩空间**：
  `ProceduralSkyMaterial` 的天空色在引擎里是**辐照度**、直接当线性值送进着色器，
  不像普通材质那样帮你从 sRGB 转一遍。而 `DayCycle` 那六个 `DAY_SKY_*` /
  `DAY_GND_*` 常量是照着显示器写的 **sRGB**。于是 `DAY_SKY_HORIZON`
  =(0.72,0.85,0.97) 这个"看着是淡青白"的数，渲出来是 sRGB(0.87,0.94,0.99)、
  **几乎就是白的**；天上最亮的那一片进到 AGX 的高光肩之后又被去一次饱和，
  于是整片天读成**一张一整片的灰蓝纸**：骑行视角下（仰角 0~22.5°）
  从天顶到地平线只有 **8%** 的亮度差。
  **第二个成因是场景的雾画天**：`fog_sky_affect` 原来 0.3，而雾色是
  (0.88,0.92,0.98) 那一档近白，于是材质自己的蓝先被雾洗掉一层。改成 0 之后
  同样那六个常量渲出来的带内落差从 8% 涨到 15%。
  两处都改（常量走 `srgb_to_linear()` + `fog_sky_affect = 0`）之后是 **37%**，
  而正午那行渲出来 sRGB(92,114,205)、黄昏那行 sRGB(118,5,8)。
  连带两条：① **`lerp` 要在 sRGB 空间做、换算放最后**
  （`DAY_SKY_TOP.lerp(DUSK_SKY_TOP, t).srgb_to_linear()`）——在线性里插那 9 秒的
  交叉淡入中段会塌成一团发灰的泥；②**断言要问"线性空间里的反差"而不是
  常量自己的反差**：按未换算的 sRGB 数值算出来是 0.39，看着已经很够，
  而画面上一片平，因为 AGX 压的是线性那一头。这就是"量玩家用的那个量"的又一处。
  回归验证：`verify_day_cycle.gd` 第 2b 节（成因：`fog_sky_affect == 0`
  与白昼档线性反差 ≥ 0.50）+ `lookdev_journey.gd` 那五条天带像素断言（结果）。
  同族已经栽过两次：`FarRidge` 的顶点色（AGX 那条）、GLB 的 `baseColorFactor`
  到 `albedo_color` 是过 `linear_to_srgb()` 的——**三个方向的换算都发生过，
  而它们各自只在自己的文件里写着**。
  第三条同族教训，写在这次上：**同一个取样框上的两个判据不一定量的是同一件事**。
  判"天有没有层次"量的是两端之差（0.10 与 0.22 两行，第一版一次就量对了），
  判"天是不是蓝"量的是单行色相——而第一版让两条共用同一行，取到的是**设计成
  近白的地平线霾**，于是"天蓝不蓝"恒红而"天有没有层次"恒绿。取样框对了不代表
  每条判据都对，这两条得分开取样（`SKY_HUE_ROW` vs `SKY_ROWS`）。

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
  **这一条的前半段（宽度）修完之后，字号还是那个病**：卡片上 `font_size := 36`
  写死，预览从 200 加到 452 之后那行字也只有 `36 × 452 / 1920 = 8.5px`——
  "预览 ≥400px 宽"和"字号 = 36"**两条断言当时都是绿的**。可推广的一条：
  **凡是"原尺寸画完再缩下来"的那一族，可读性是个乘积（源上的字号 × 缩放比），
  量任何一个因子都量不到它**，两个都得量。而缩放比里那个宽度上限
  （`minf(vw * 0.36, 460)`）在 720p 上**根本不生效**——高度那道约束先卡住，
  于是"把上限调大"对多数玩家是零效果，而 headless 量到的偏偏是上限那一档。
  同族：**"纸上还空着"要当病治**。写死的 36 让 200 字只占框高的三分之一，
  剩下的空不是留白而是没人用；改成从 `FONT_MAX` 往下找第一个放得下的号之后，
  短句顶到 84px、写满 200 字落到 60px，两头都填满框。判据里必须有"最大号"那一条，
  否则把 `LINE_GAP` 或 `FONT_MAX` 调小到"还更空"也照样全绿。

- **断行必须"先试着放，放不下再收尾"，不能"先放进去再看超没超"**：
  后者只在**断行点**（空格 / 逐字的 CJK）上检查，于是西文那一行会冲出去
  **一整个词**才收尾——实测一行 1969px 而框只有 1792px，右端那一截被框沿吃掉。
  中文不受影响（逐字都是断行点），所以**只拿中文当样本的话这条永远是绿的**。
  对应的断言要写成 `每一行 ≤ max_w`（量成品），而不是"断行函数被调过"（量过程）。

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

- **"水关得住"靠的是地形高程被 clamp 在 [-3, 6] 这件事，不是靠把岸修陡**：
  `TerrainBuilder.natural_height_at()` 把自然高程夹在 **-3.0**，而全场 31% 的采样点
  正好压在这个下限上（一片望无际的平地）。所以水位放到 -3.0 以下之后，
  全场低于水位的就只剩挖出来的三只碗——碗沿处碗深归零、高度回到自然地形，
  必然高于水位。于是"水会不会漫出去"不再取决于地形坡度，而恒等于否。
  第一版按"碗心实挖高程 + FILL×碗深"逐碗定水位，实测**每一处都有几十度角在两倍盆沿
  之外还没露出岸**：这条路的地形在几十米尺度上就有几米落差，水位按碗心定，
  顺坡的一侧永远追不上岸，水面在半空中被切断——天上飘着一片蓝。
  别把 `WATER_LEVEL` 调回 -3.0 以上；调回去之后所有几何断言照样绿，症状只在图上。

- **碗心要挑"碗底足迹平均高程最低"的那处，不是"最低的那一点"**：
  水面盖住的是"自然地形减去碗深之后低于水位"的那一圈，所以好不好看取决于
  **整片碗底的自然高程平不平**。只挑最低的点会挑到陡坡的下缘：湖顺着下坡摊开、
  上坡一侧露成一大片干土，水面半径从 7m 拉到 29m 的月牙。第一版正是这么写的，
  而上面每一条几何断言都照过——分不出"湖"和"土坑围着的一小滩蓝"。
  真正的判据是**水面盖住碗的百分比**（现在门槛 55%，实测 58/66/66）：
  门槛第一版取 45%，而退回到"沿 away 推固定距离"之后量到 42/46/50——
  45% 只拦得住最差的那一处，**三处里两处照绿，等于门槛定在了噪声里**。
  同族的一条：量这个百分比只准扫**这只碗自己的**水面顶点，拿全部水体一起扫的话
  别处的顶点偶然落在这条射线上就会算进来。

- **碗是椭圆，岸线的搜索上限就不能是 `radius`**：`Water._shoreline()` 第一版拿
  `radius` 当每个方向的搜索上限，于是 `squash = 3.2` 的溪在 22m 处被齐腰剪断——
  碗其实一直伸到 70m，水面边缘成了一条**悬在半空里的直线**。正确的上限是
  "沿这个方向走到盆沿还有多远" = `r / |(dir·along)/squash, dir·away|`。
  这条是 `probe_water.gd` 报的"有几个角找不到岸"从 22 降到 0 才发现的，
  而那 22 个角当时没有任何一条断言在管。

- **`ripple_amp` 是法线的**倾角**，不是波高**：`wave()` 三个正弦加起来归一到 ±1，
  在 `e = 0.4m` 那一步上 |Δh| 的上限约 0.82，所以 amp 就是法线偏离竖直方向的角度。
  原来的 `7.0` → 约 80°，渲出来是一片**锡纸**：满屏高光白斑、倒影全碎、
  水面读成泳池底，掠射角下"这是水"那个最强的信号反而被自己毁了。0.60 → 约 26°，
  平静的湖面，而"水面一直在动"这个信号在 26° 上已经足够。
  **没有任何无头回归能量到它**（不编译着色器），只有 `lookdev_water.gd` 的图能。

- **判"哪些像素是水"不许靠颜色猜**：第一版判据是"偏蓝且不亮"，当场废了两次——
  只判偏蓝时**整片天都算成水**（天本身就是亮的青蓝），"水跑到天上去了"那条永远红
  而真正该量的量不到；补上"不亮"之后天顶那片深蓝的亮度又掉进阈值里。
  靠颜色猜"这是水"，量到的是**天空长什么样**。现在每张拍两遍：第一遍把三片水换成
  一片不受光的洋红量它遮住哪些像素（纯几何，谁也不用猜颜色），第二遍换回真材质量观感。
  而**掩膜的判据要比通道之间的差距而不是绝对值**（`r > g + 0.18 且 b > g + 0.12`）：
  绝对阈值量的是那个色号在 AGX + 雾之后落到哪一档，而那正是被 tonemap 挪动的那几档——
  第一版的 `r > 0.45 and b > 0.45 and g < 0.35` 配着没关雾的材质，四张图全部量到
  **0 个像素**而三条断言照样打印 PASS。掩膜材质还要 `disable_fog = true`，
  场景那层雾的 `fog_light_color` 几乎是白的。
  同族提醒：掩膜空的时候"水没跑到天上"那条会**空过**（没有像素就没有违规），
  它是被同一张图里"看得见水"那条兜住的——两条必须成对写。
- **回归把测试数据写进 `res://layout.json`，污染的是**整个世界**：这个文件不是测试夹具，
  是关卡编辑用 Ctrl+S 存下来的成果，而 `World3D._setup_stations()` / `VegBuilder.setup()`
  启动时真的会读它。第一版 `verify_layout_editor` 往上面写了自己的样例数据
  （两座驿站摆到 `(1,2,3)` 和 `(-2,0.5,4)`，相隔 3.2m）然后 `clear()`，一个断言都不打。
  它留在盘上之后**每一次**跑回归，世界都被摆歪：路过那一带一次发两份旅币
  （`on_station_pass` 只按站号去重，两座站都在 15m 圈内就各发一次），
  "到过 N 驿"一次涨 2，于是郑铎三场在"才 3 驿"时就开演。
  症状全在 `verify_shop_world` 上（两条红），而根因在一条没人跑过的、
  已经删除自己的回归里——**报错的文件和出问题的文件不是同一个**。
  现在两道防线：`verify_layout_editor` 自己备份/还原，
  `check_all.sh` 在整轮跑之前再存一份、跑完还回来；本来没有就还它没有。
  顺带一条判据：凡是有回归会写**产品输入**（存档、layout.json、导入缓存），
  跑完之后必须回到跑之前的状态，而"跑完检查一下"不算——脚本中途抛异常就还原不了。

- **`road_data` 的 `dialogue` 和 `dialogue_en` 是两份手抄的数组，不是同一份数据的两种语言**：
  原来 `verify_story.gd` 只查"两边都非空"，于是中文加到 3 句、英文忘了加（或者反过来）
  时**没有任何一条回归会红**——少的那句是个合法的非空数组，
  中英 key 集合照样逐字相同（那两项查的是 `Localization.STRINGS`，不碰 `road_data`），
  而英文玩家在首访对白里就少读一句。这一族的判据是"两份副本的**形状**要对上"，
  不是"它们都在"。现在钉的是句数一一对应 + 逐句不重复（相同即漏译）。
  两条断言都做过变异验证：删掉一整句英文 → 红；把一句英文原样填成中文 → 红。
  顺带：删掉一句英文里的**半句**两条都抓不到（句数没变、也不重复）——
  翻译质量本来就不是自动断言的活儿，那只能靠 `lookdev_journey.gd` 看图。

- **"操纵权还回去了"和"模态收掉了"是两个量，而信号只承诺了其中一个**：
  集齐二选一面板第一版把 `visible = false` 写在面板自己的 `_emit()` 里，
  于是**点按钮**这条路收得掉，而 `synthesis_choice` 是个公开信号——
  定妆照脚本、以后的自动导览、任何 `emit()` 都走不到那一行。后果是
  `_synthesis_choice_open` 已经归零（操纵权还回去了、圈也画出来了）而模态还亮着，
  玩家站在一个等他按键的屏底下重新握住把手。**当时全部断言是绿的**：
  `verify_interact_latch` 第 10 节量的是操纵权，量得对；`lookdev_journey` 的
  `13c_after_再骑一圈` 量的是屏幕，于是拍出一张和 `13b` 一模一样的图——
  看图的人只会觉得"这张和上一张重复了"，读代码的人只会觉得"操纵权还回去了，没问题"。
  两个提示在同一刻互相拆台。修法是**收面板的责任归一**：
  `World3D._on_synthesis_choice()` 收到信号就 `_synthesis_panel.close()`，
  按钮那条路经由同一个 `close()`，于是所有入口收敛到一处。
  回归要补的那一条断言是"**直接 `emit()` 信号也收得掉面板**"——
  写完照例做一次删除突变（删掉那行 `close()`，两条断言变红）才认。
  可推广的一条：**任何一个模态的收尾，责任要放在"谁决定结束"的那一处，
  而不是放在"某条触发路径"上**；而**断言要量玩家看得见的那一半**，
  状态那一半对了不代表画面那一半也对了

- **一条回归在新的模态面前要跟着做玩家会做的动作，否则它量的不是产品**：
  `verify_minimap.gd` 第 9 节推完 5 次真实 `check_in()` 之后，本来是直接接着
  逐站核对脚下的圈——集齐那 2.5 秒的合成动画演完之后面板弹出来了，
  而 `_synthesis_choice_open` 在 `_physics_process` 那张早退单子里，
  `_nearby_*` 被清成 -1，于是十条断言一起红（"圈指的就是它"got=-1）。
  **那个红是新行为的正确结果**：模态开着的时候圈本来就该收掉。
  修法不是把断言改松，而是让测试**先选「再骑一圈」**——和玩家一样。
  顺带钉了三条前提（面板真的弹出来了 / 面板开着时世界真的冻着 / 选完之后真的解冻），
  否则将来那 2.5 秒一变长，这段就悄悄不干活而断言数一条不少

- **「这一屏在讲什么」和「这一屏画的是什么」是两件事，而回归只量过一件**：
  琴那屏的标题写着「记住音符顺序并重复」，通篇不提琴，而屏上是一块收分的
  木色多边形加四根横线——**一块有四根线的板子**；竹那五根是
  `draw_rect(..., 12, ...)` 的等宽竖条，竹节那四条线也才 12px 宽，
  画在一条 12px 的条上等于没有，于是标题写"竹子一冒头就按空格"而屏上没有竹子；
  云最荒唐：背景那五片云是三个圆叠出来的，而**要描的那条轨迹是一串手抄的
  八边形顶点**——同一屏上同一件事两套画法，`MiniGameBackdrop._clouds()` 和
  `PATH_POINTS` 各画各的。
  为什么全绿：`verify_mini_game.gd` 一直量的是**机制**（松手退不退出、
  描边能不能刷分），`lookdev_journey.gd` 出图但那五张 `minigame_*.png`
  是拍下来没人逐张看的。可推广的一条：**一屏的文案里出现了某个名词，
  就得有一处断言去量"屏上有没有那个东西"**——量不到就说明判据挂错了地方。
  判据钉的是纯函数（`cloud_outline()` / `stalk_poly()` / `hui_positions()`），
  不是像素；而"是不是多边形"钉成**尖角占顶点的比例**而不是"有没有尖角"
  （一朵云本来就有几处圆与圆交接的棱，真正的判据是"多边形的每个顶点都是尖角"：
  旧的八边形是 8/8，现在是 9/40）

- **按"窗口高度的百分比"取的尺寸，在别的分辨率上必然越界**：
  砍倒的竹子那段上半身原来写死 `h * 0.30`，在 720p 上量着伸出 106px、
  刚好在 152px 的列距之内，看着没事；无头视口是 1280 高，同一段伸到 **177px**，
  已经压到右边那根还立着的竹子上了——而**当时所有断言都是绿的**，因为没有一条
  量的就是这个。可推广的一条：**任何"不许越过某条边界"的量，它的基准必须是
  那条边界本身，不是另一个会变的量**。修法是从边界反解尺寸
  （`fall_len(spacing) = spacing * FRAC / sin(FALL_DEG)`），
  回归就也钉在同一条边界上，于是任何分辨率下量到的都是同一个比值

- **「这一屏空不空」量的是内容下沿离屏幕下沿还有多远，而量的时候必须先把
  那层铺满全屏的遮罩排除掉**：抉择屏原来内容全压在上半屏，**下沿只到屏高的 51%**
  （720p 下从卡片下沿到屏幕下沿空着 277px，占 38%）——而它恰好是全场玩家唯一一次
  要**比较两个选项**的一屏。可第一版的判据写成 `max(子节点 get_rect().end.y)`，
  于是它恒绿：那个 `shade` 是 `_stretch_full` 铺满全屏的 ColorRect，
  它的下沿恒等于屏高，而"铺满全屏"是它的**定义**不是它的**内容**——
  拿它当"内容排到哪了"的证据，等于拿背景证明背景在。可推广的一条：
  **凡是"某块版面排满了没有"这类判据，要先把装饰层和内容层分开**，
  判据要问内容层自己最下边那个东西到边沿还差多少。
  同族的一条紧挨着它：**判"两个东西齐不齐平"要量 `get_global_rect()`，不能量
  `.position`**——`PanelContainer` 是延迟排版的子节点（`_sort_children` 排在通知里），
  那一刻两个 Label 都在各自 VBox 的 0 处，量出来差 0px，于是**"两张卡的标题差 12px"
  那条判据恒绿**。而"行盒一样高"那条同样恒真却**不是**同一个病：删掉那句定高之后
  两边一起退成 0，仍然相等——它是**指路的，不是断的**，所以必须和"齐平"成对写，
  否则一条恒绿会把另一条真的红掩盖掉（这两条"恒绿"长得一模一样，成因完全不同）

- **图标控件按 `size.x` 缩放、而设计坐标早就出了 ±16 的，开正方形的框一定装不下**：
  `FragmentIcon._draw()` 做的是 `draw_set_transform(size / 2.0, 0, Vector2(s, s))`
  而 `s = size.x / 32.0`——**缩放比只由宽决定**，于是框开成正方形等于一分余量都没给。
  而五件的设计范围并不是对称的 ±16：竹到 y −24..+20、禽到 x +21、云到 x ±17。
  后果是第一版那个 56×56 的方框里，**竹的梢探出框底 7px、禽的嘴探出框右 9px**，
  而竹那 7px 正好压在「竹」那个字上——**而当时所有几何断言全绿**（控件不叠、
  都在屏内、五件的顺序也对），因为"墨有没有落进名字行"不是几何量。
  修法是框改成**竖长条** 48×92（缩放比仍是 1.5，中心落在 y=46，于是竹落在 10..76），
  禽横向仍溢出 7px，而那一侧是空白、不是笔画打架。
  判据因此必须落在**像素**上：按 ±0.22 逐通道找 `Postcard.FRAGMENT_COLS[i]`，
  在图标 rect 内量"这件的颜色真画出来了吗"，在名字 Label 的行盒里量
  "同色像素是不是 **0**"（`lookdev_postcard.gd` 那两条）。
  可推广的一条：**凡是一个"自己画自己"的控件，先读它 `_draw()` 里那句
  `draw_set_transform` / `draw_rect` 的缩放是怎么取出来的**——按宽取还是按高取，
  决定了它的框能不能开成正方形；而**设计坐标的极值**要在摆框之前量出来，
  摆在之后永远量不到（那时你量的是框，不是墨）

---

## 这一轮新记的三条（2026-10-03，评审整改）

### ① 草皮挡世界的机制是**覆盖率**，不是高度——而量高度永远量不到它

现象：骑行视角里草从路肩长到超过车把，8m 以外糊成一堵不透明的绿墙，
地形起伏、远山、站点地基全看不见。第一反应都是"草太高"，
`lookdev_grass/04m.png` 也能"量"出 0.5m 上下——**但那个数是错的**：
相机站在 `EYE_H=1.6`，画面下缘那些巨大的叶片离相机只有 0.3~0.5m，
拿它当 4m 处的草去反解高度，等于把透视当成了尺寸。
真去算产品常量：`card_height=0.085`，ring 0/1 的最坏渲染高度是
`0.085 × 1.35 × 1.25 ≈ 0.14m`——**踝高，够不上"齐腰"**。

真凶是 `DENSITY = 5.0` 丛/m² 配每丛 10 片叶 ≈ 50 叶/m²：
低视角下一张 0.24m 宽的竖立牌挡住的是它身后一整条街，丛数一乘，
脚边到 30m 环沿**一寸土都不露**，整片读成一块均匀的绿，地形的形状被吃光。
把它改成 2.2 之后，同一张 4m 图里地形、路面、米斑、天空渐变全回来了。

**可推广的一条**：一个"看起来太大了/太高了"的观感问题，先去把**渲染出来
的那个量**算一遍，别在观感上做三角测量。低视角 + 密集 billboard 的组合下，
"近处的物体显得大"和"东西真的大"在图上长得一模一样。

### ② 判据量的是**原因**时，绿着不代表产品对

`verify_grass_scatter.gd` 原来把 `card_height ≤ 0.10` 读源码文本当护栏，
而渲染高度还要再乘 `RING_SCALE`（最外圈 3.2）、实例缩放（≤1.35）和高度抖动（≤1.25）。
它还有一条 `smax < 0.72 * RING_SCALE[r]`——那是个**下界**，验的是"远处的卡片
确实变大了"，从头到尾**没有乘过 `card_height`**，也没有上界。
于是源码绿、回归绿、画面是一地麦子。这和 `edge_line_color` 那条同族：
**判据守的是它自己写下来的那个原因，不是玩家看见的那个结果。**

修法不是把阈值调紧，是**换一把尺子**：`lookdev_grass.gd` 现在量 4m 那张图
**画面最下缘**（脚下那段地面）的竖直梯度占比——
草是竖的结构、地面是平滑的米斑，`|d(亮度)/dy|` 超阈的像素占比就是"草占掉了多少地"。
界 0.10 是量出来的：`DENSITY=2.2` 时 0.069，`DENSITY=5.0` 时 0.135。
配一条**同一张图内**的正对照（稠密带 0.188 必须明显高于开阔带 0.069），
否则"草全没了"的世界里 `≤0.10` 照样绿。

写这条尺子时踩了一个和 CLAUDE.md 里 `ALPHA_SCISSOR_THRESHOLD` 同源的坑：
用 `absi()` 取亮度差的绝对值。`absi` 是**整数**函数，0.1 截成 0，
于是占比恒为 `0.000`、恒绿、且看不出来。**量像素的代码里出现
`absi`/`absf` 选错，等于把尺子自己折断了。**

### ③ 手抄的常量副本会自己长出一套预算曲线

把 `DENSITY` 从 5.0 降到 2.2 之后，`verify_grass_scatter.gd` 报的红是
「环号越大产量越少」——根因**不在那条判据量的地方**：
回归里手抄的 `RING_DENSITY = [DENSITY, 2.5, 1.0, 0.35]` 里，ring 1 的 2.5
比产品里新的 ring 0（2.2）还密，于是"越远越疏"被自己打破了，而它量的是副本。
现在回归开头有一节当场从 `get_script_constant_map()` 读**产品求值后**的常量对拍。

**一般化**：回归里凡是"手抄一份产品的常量表"，就要同时有一条
"这份副本 == 产品里那份"的对拍，否则副本会安静地变成第二个事实来源。

## 这一轮新记的四条（2026-10-04，P1-2 路肩软边界）

### ① 相机摆好了不等于**在拍**——`Camera3D.make_current()` 漏掉时三张图逐字节相同

为了量路外那道软边界，前后做了三版一次性探针，每一版都"发现"带子看不见，
每一版的结论都不成立。真正的根因在**摆机位和取像素之间那一段**：
`root.get_texture()` 渲的是**当前那台**相机，而 `World3D` 自己那台玩家相机是
`current`。探针各自 `add_child()` 了一台 `Camera3D`、改了 `fov`、甚至改成了
正交，然后从**游戏自己的追尾视角**上取像素——于是量到的那个"扫描线"从来
就不是我摆的那条，米数标签、对比度、"带子看不见"这个结论全都建立在
一张不是我拍的图上。**诊断它的不是看代码，是看像素**：三套完全不同的机位
输出**逐字节相同**，当场就知道有一台相机压根没被用。

可推广的一条：**摆好机位之后要有一句"我确实在用它"的正证据**，
而不是假定 `add_child()` 就等于在拍。现在 `lookdev_verge.gd` 里那条
「渲出来的亮峰落在 12.0m」同时就是正证据——拍错相机的话那是一张追尾视角，
压根不存在"离路心线 12m"这个读数。（和 CLAUDE.md 里「画笔真的调了吗」
是同一族：接线没通，两侧各自都绿。）

顺带两条同一段里的坑：**正交 + `size`** 而不是「透视 + 手算 fov」——
`keep_aspect` 默认 `KEEP_HEIGHT`，`fov` 说的是**竖直**那一档，第一版把竖直
当成水平，米数整整大了 16/9 倍；第二版改正了换算，却因为手搭的 `Basis`
不正交（y 轴给了水平的切线、z 轴给了竖直），相机压根没朝下看。正交投影把
这一整类错误一次消掉：`size` 就是画面竖直方向的总米数。还有取样点要取
`RoadBuilder.get_centerline()`（平滑三次 + 0.5m 重采样过的那份）而不是
`road_data.points` 的原始控制点，并且**躲开 8 字自交点**——那个位置路面被
`plaza_mode` 扩成一大块圆盘，扫过去的整行都是沥青，"带子在不在"无从谈起。

### ② `vertex_color_is_srgb` 默认 **false**——顶点色被当**线性**反照率用

`BaseMaterial3D.vertex_color_is_srgb` 不设就是 `false`，也就是引擎把
`PackedColorArray` 里那个数当成**线性**反照率。`RoadVerge` 的外沿写的是
`Color(0.292, 0.422, 0.180)`，按 sRGB 理解它是 sRGB 0.42 的暗草色，
按线性理解它其实是 **sRGB 0.55**——整条带子凭空亮一档半，14.5m 的外沿
渲成 0.71 而旁边的地形是 0.40，于是土径尽头多出一圈比周围亮的环。

**可推广的一条**：全工程只要是"往 `PackedColorArray` 里填一个数、
指望它在屏上是那个数"的地方，就得先问一句这个标志设了没有。本工程其余
的颜色（GLB 的 `linear_to_srgb()`、`DayCycle` 那些过 `srgb_to_linear()`
的常量、地形着色器的 `source_color`）一律按 sRGB 写，
**`vertex_color_is_srgb` 是这一族唯一一处默认值和约定相反的地方**——
因为别的路（`source_color` / GLB）引擎会替你转，只有裸顶点色不会。

### ③ 反照率对比度**不是**渲出来的对比度，而这一族的判据量了整整三轮反照率

`RoadVerge` 第一版的判据是 WCAG **反照率**对比度：`LINE` 对地形
`ground_color` ≥ 2.2:1，实测 **2.58，一直全绿**。而正交俯拍逐像素量到，
那六米渲出来是 sRGB(0.73 … 0.93 … 0.99) 的**一整条白**——"一道线"根本
不存在，读出来是一圈水泥地。中间隔着**法线、太阳角、AGX 与雾**，一层都没
量到。

真正让那六米顶到白的是两个**结构**缺陷，各有自己的判据：
① 网格压根没写 `arrays[Mesh.ARRAY_NORMAL]`，着色器拿到零法线，
`N·L` 恒为 0，那圈本该**苍白**的标记带只吃到天光环境光，渲出来是
sRGB(0.16,0.29,0.54) 的**深蓝**，比两边的草地还暗两档；② 上面那条
`vertex_color_is_srgb`（②节）。两者**都不会让任何一条反照率判据变红**——
而剖面里那个 `LINE` 确实一格不差地是 0.84/0.82/0.70。

所以现在分工是写死的：`verify_road_verge.gd`（无头）量**剖面的结构**
（最亮的一列 + 两侧台阶 + 两头不造硬边）加**两条读源码文本**钉住上面那
两个缺陷；`lookdev_verge.gd`（带窗口）量**渲出来的像素**（峰值在 12.0m、
不顶到白也不读不出来、两侧台阶、接缝、另一侧同形）。
**「看不看得见」只有后者能量，无头回归量不到渲染结果——量不到就别假装量得到。**

同族的一条：**判据的取样点自己得先问一句落在什么东西上**。定妆照里那条
「内沿的土比沥青亮」第一版取 4.0m 当"沥青"，而 `asphalt.gdshader` 的白色
实边线正落在 4.0m 那一档（读到 **0.959**），于是判据变成"土径要比白漆
亮"，永远红；改成 1.5m 之后它又变成"土径要比裸沥青暗"——而一条踩出来的
土径**本来就应该比深色沥青亮**，这条从来不是设计目标，是我自己编的。
现在的正对照取「0.5~6m 里**最亮**的那一格」而不是写死它在几米处：
**它在哪儿本身就是待测的**。写判据时更得先问一句"这一条到底想证明什么"
——不是实现看起来差得不一样就顺手加一条。

### ④ 评审要的判据和评审要的修法**互相拆台**时，明写"没装这条"比装上更好

第四轮 P1-2 建议补一条断言：「骑向站点的最后 20m，平均速度 ≥ 8m/s」，
并给出实测「顶了 30 秒，离目标从 27m 只走到 18m，平均 0.3m/s」。
它同时说"不要削弱推力，正解是在 `SOFT_BOUND` 边缘画一道**看得见的**软边界"。
这两条放在一起是**执行不下去**的，理由有两条：

① **那把尺子量不到被测的东西。** `play_newcomer` 是个只发按键、
**不看像素**的脚本驾驶员，而这一轮的修法一个字都没落在推力公式上——
所以它的骑乘日志在修法前后**必然一模一样**。那条判据要么一直红
（正确的修法被红着），要么只能靠把墙变矮才绿（那正是评审明确不要的）。

② **那个 0.3m/s 本身也是一把旧尺子量出来的。** `play_newcomer` 早就改成
**沿路点骑**（`_road_waypoints()`）并停在离路心线 8m 的**路边那一点**、
而不是站心——理由就写在它文件头里，和陷阱清单里「这辆车怎么不动」
那条是同一件事（"径直骑向站心"是一次永远赢不了的对拉）。2026-10-04 重跑一遍：
**168.3 秒、已过 6 驿、碎片 5/5**，五座碎片站全部骑到。所以评审引的那个数
是**在脚本还横穿草地时**的读数，而它读起来和"关于产品的事实"一模一样。

**所以这里没装那条判据，而在 `verify_road_verge.gd` 的文件头把理由写下来。**
可推广的一条：**当一条建议的判据和它自己建议的修法互相拆台时，
正确的产品决策是照修法走 + 把"这条判据没装、为什么"写进档案**，
而不是挑一个能绿的判据装上去——后者会让下一个人以为这个性质有回归守着，
而它其实没有。（和「判据的极性要连理由一起改」是同一条的两头。）

另一个数字要记牢：**`SOFT_BOUND`(12m) 之外推力在 21m 处就压过
`Player3D.ACCEL = 8.0`，一辆满速 15m/s 的车在 27m 处正好被钉住**。
这一条本身没变，变的是现在 `SOFT_BOUND` 那一档**看得见了**——
玩家骑出 12m 就有一条漂白带告诉他"往回骑"，而不是在 27m 处撞上一堵
**没有理由的墙**。

## 这一轮新记的三条（2026-10-04，第五轮 P0-1 路面蓝紫霉斑）

### ① 拆光源之前先确认这个世界里到底有几盏灯——`grep` 只找得到手放的那两盏

正午路面读成**靛蓝迷彩布**（中位 `b−r` = +29、饱和度 0.252），
而这块沥青的反照率当时是 `(0.355, 0.350, 0.340)`——**通道差 0.015，
一块纯中性灰**。于是按"面朝天、中性、又是全场唯一大面积水平面"
的直觉，真凶应该在环境光那一路。四个假设逐个做了对照实验，
**每一个都被自己的实验证伪**（`tools/probe_road_hue.gd`，一个进程只动一个旋钮）：

| 动的旋钮 | 路面 `b−r` | 结论 |
|---|---|---|
| 基线 | **+29** | — |
| `ambient_light_energy = 0` | **+29**（一格没动） | 证伪 |
| `SPECULAR = 0.0` | +26 | 证伪 |
| `EMISSION = vec3(0)` | +29 | 证伪 |
| 四个天空滤镜全拉黑（`--nosky`） | **+29** | 证伪（整改计划的方案 B 因此也废了） |
| **`sdfgi_enabled = false`** | **+21** | **真凶** |

**SDFGI 是从天空反推出来的间接反弹光**：它既不乘
`DirectionalLight3D.light_color`，也不是 `ambient_light_energy` 那一路。
所以"把太阳换成纯红它还是蓝""把天拉黑它一点不变""三盏灯全灭它还亮着"
**三件事同时成立**——而这三件事当时被读成三个互不相干的谜。
决定性的对照是 `black`（三盏灯全关）与 `black_nosdfgi`：
前者是 sRGB(6,17,70) 的**亮蓝**，后者是 sRGB(0,0,0) 的**纯黑**。

**可推广的一条**：`grep DirectionalLight3D` 找得到场景里手放的那两盏灯，
而 SDFGI 是 `Environment` sub_resource 里的**一个布尔量**，没有任何一条
`grep` 会命中它。凡是"这块面为什么是蓝的"而逐个关灯都关不掉，
先查 `Environment` 上那几个间接光开关（`sdfgi_enabled` /
`ssao_enabled` / `glow_enabled` / `fog_enabled`），再回来查材质。
连带一条量法上的：**别在一个进程里反复开关 SDFGI 去量它**
——关掉再打开，级联不会在 12 帧内重建，于是后面那几档量到的是
**半重建状态**（实测 `all_on` 在同一个进程里读 +8，而单独跑读 +29）。
单旋钮对照实验必须**一个旋钮一个进程**。

### ② 材质偏色只能抵消**一部分**辐照度，所以修法是两头一起上

SDFGI 关掉之后 `b−r` 是 +21，而评审的门槛是 **±12**——还差一截。
而这一截只能在材质这一侧补：`asphalt_color` 原来通道差 0.015
（纯中性灰），改成 `vec4(0.430, 0.400, 0.330)` 之后通道差 0.100，
实测 `b−r` **−3**、饱和度 0.092，两条都过。
`grain_dark_color` 按**同一比例**跟着走（它按 `grain * 0.45` 混进来，
留着中性只会把暖意稀释掉四成）——`verify_asphalt_shader.gd` 有一条
专门钉这个"同向偏"。

选 0.430 而不是更亮那一档是**算过的**：相对亮度 0.145 的碎石路肩
必须比相对亮度 0.107 的沥青**亮**（`RoadVerge.gd` 的注释写着"路肩是从路面上
退下去的一层"），把沥青调亮到 0.43 以上就把这个关系翻过来了。
**改观感之前先量那条"谁比谁亮"的关系还成不成立**——它比"看着够不够好"
值钱，而且有回归钉着（`verify_road_verge.gd`）。

### ③ 查一个量为什么是那个值时，先问"这个旋钮到底走的是哪条路"

`ambient_light_source = 3`（`AMBIENT_SOURCE_SKY`）下
**`ambient_light_color` 一个像素都不参与**，只认 `ambient_light_energy`；
而 `ProceduralSkyMaterial` 那四个颜色是**滤色片**、乘在散射结果上，
不是天自己的颜色——所以"把天调暖一点"这条路对漫反射几乎无贡献
（实测环境光关掉，路面读数一格不动）。
可推广的一条同族：**引擎里有若干条互相独立的光照路径**
（直接光 / 环境光 / SDFGI 间接反弹 / 天空的漫反射贡献 / fog），
它们各乘各的、各自被各自的旋钮控制，而**关掉"看起来像那一路"的那个
旋钮不等于关掉了那一路**。所以拆光源的实验必须**一次只关一个旋钮、
一个进程量一次**，而"这一路归哪个旋钮管"要查文档而不是查直觉。


## 这一轮新记的两条（2026-10-04，第六轮 P0-2 主角的家）

### ① 取样点自己得先问"落在什么东西上"——**离落点最近的那个中心线点**在 8 字上是另一瓣

给家定机位时，第一版拿"离落点最近的那个 `get_centerline()` 采样点"当
"房子正对的那一段路"。而 8 字的两瓣靠得近、家又在瓣外 15m——**全局最近点
落在另一瓣上**。于是同一次运行里两条断言一起红，而且红得极像产品坏了：

| 量 | 错尺子 | 对尺子（`HomeBase.road_pt`） |
|---|---|---|
| 门与路的夹角 dot | **0.354**（偏 69°） | 0.99+ |
| 骑行机位到门牌的距离 | 几百米 | 15m |
| 门牌字身在屏上的高度 | **4.2px**（读不出） | 29.2px（读得出） |

**两条红是同一把尺子的毛病**——而 `verify_home_base.gd` §3 量的是同一个性质、
用的是同一个 `road_pt`，它一直绿着。所以"回归绿、图红"这一次的成因不在
判据松，而在**定妆照自己另抄了一份"什么算正对着路"**。

可推广的一条：**8 字这种"同一条线走到自己旁边"的图形上，"最近"这个词
没有唯一解**，凡是拿最近点当参照的机位/朝向判据，都要问一句"近的是哪一段"。
正解不是"限定一个搜索半径"（那还是猜），而是**用产品自己存下来的那个参照**
——`HomeBase.road_pt` 存在就是为了这件事，它是"房子正对的那一段"的唯一定义。

### ② 「数一数有多少个像素」量的是**那一块地方**，不是**那件东西**

小地图那枚"家"的钉，第一版判据是"小地图里米白像素 > 8"。突变验证时把
`_draw_home()` 整个删掉，那条**照样绿**——删钉之后仍读到 **26** 个米白像素，
因为 `NEXT_RING`(1,1,1) 套在下一处碎片站外面那圈白环**正好落进同一个阈值**，
而它就在同一个控件里。

这不是"阈值定松了"，是**取样框比被测的东西大**：框里本来就有的东西
（白环、玩家三角、站点的金色）全部被算成了这枚钉的账。收小到**钉自己
那一块**（`_w2m(home_site)` 周围 ±14px）之后，带钉 **73**、撤钉 **0**，
而那条白环根本不在框里。

连带两条已经在用的规矩：
① **绝对数与正对照成对写**——「撤掉它再数一遍，差值才是它的账」这条在
收小框之后仍然留着，它证明"框里那些像素真是这枚钉的"，而不只是"框里碰巧
有东西"（和 CLAUDE.md 里"落盘闸必须配正对照"、"并集每一路都要配承重的
正对照"是同一条）。
② **门槛要量出来再定**：73 / 0 两条都拿到手之后才敢写 30；第一版凭感觉
写的 8 和第二版被 5 逼出来的 6 都是在猜，而 6 那次离满分只差 1 个像素——
**一个靠猜定出来的门槛会在换一台机器时变成恒红或恒绿**。

## 这一轮新记的两条（2026-10-04，第七轮 P1 存档健壮性）

### ① `ConfigFile.load()` 对坏文件一律返回 OK，而"读档没报错"正是旧版唯一的判据

写存档之前先探了一把平台行为，探出来的东西比预想的严重：

| 喂给 `ConfigFile.load()` 的文件 | 返回值 |
|---|---|
| 崩在写一半的半份（`[game]\n\nversion=3\ncollected="7:2"\nprog`） | **OK** |
| 纯垃圾（`<<< not a config >>>`） | **OK** |
| 空文件 | **OK** |

于是旧版 `_load_save()` 的第一句 `if cfg.load(SAVE_PATH) != OK: return` 对上面
三种**一个都拦不住**。崩溃/断电/Web 上关标签页把正本截成半份之后：
读档"成功" → 版本号取默认值 `0` ≠ `SAVE_VERSION` → `_clear_save()`
→ **玩家这一趟被删掉**，而且盘上那份坏存档也被一起删干净，下一次启动连线索都没有。
症状是"玩了两小时，退出重进回到第一屏"。

可推广的一条同族（和 `edge_line_color`、`_draw` 不落盘并排）：
**"读成功"和"这份文件是我要的那份"是两件事，而解析器的返回值只答第一问。**
凡是拿解析/反序列化的返回码当"数据可用"的判据，都要再问一句"它是不是把
一个空结果也当成成功"。而这一条**量不出来就一定想不到**——它写在 API 文档的
"错误码"一栏之外，读者默认 `load()` 失败就意味着文件坏了。

修法是三段而不是一段：`临时文件 → 复制正本成 .bak → 换名盖掉`（顺序不能挪，
换名在 Windows 上直接擦掉目标，所以备份必须抢在它前面），读档走
`正本 → 备份 → 当作没有`。第 2 节那条**平台前提被钉成断言**，哪天引擎改了
行为它会红——它是这一族里唯一"改产品代码也不会红"的一节，而这正是它该有的样子。

### ② 恢复的判据必须量"玩家保住了什么"，而"没崩"是恒真的那一半

第一版的第 4 节只断「截断的存档读档不抛错」。这条把 `_load_save()` 整个换成
`return` 也是绿的——玩家回到全零，不抛错，一样绿。于是真正的判据是
**「读档之后拿到的旅币是上一份的 111，不是 0」**，正对照是
**「这一趟新挣的那部分确实只存在于被截断的那一份里」**（不然后一条也会在
"全部退回"时被满足）。

同族的第三处是**测试摆弄自己踩在它要守的漏洞上**：第一版的流程是
「存 → `_gm.reset()` → 读」，而 `reset()` 走 `_clear_save()`——**它把被测的
文件删掉了**。于是量到的是"存档被自己删了还能读回来"，恒绿，且与被测的代码
毫无关系。正解是分两个：`_wipe_memory()` 只清内存（玩家真实的流程是
「存 → 退进程 → 开机读」，中间没有任何一步会删文件），`_gm.reset()` 只用来在
每节开头清场。这一条和 `verify_minimap.gd` 第 9 节那个"游戏里根本走不到的存档"
是同一族，写法都是**先把玩家会做的那串动作摆出来，再断言**。

顺带一条量法上的：`_sanitise_seen()` 的上界必须从 `RoadData` 的**实例**
`stations` 取（16 座）。拿静态那份 `FRAGMENT_SLOT_STATION_IDX`（5 座）当上界，
13 座普通驿站到过的记录会全被丢掉，顶栏「已过 n 驿」于是永远 ≤5——而这一条
**不会报任何错**，玩家只是莫名其妙发现自己像是从没路过任何驿站。

## 这一轮新记的两条（2026-10-04，第七轮 P0-3 设置面板）

### ① 文本判据量到的可能是**注释**，而注释往往就写在你正在改的那件事上

`verify_settings.gd` 有三条"这个键位表不许是第二份手抄"的源码文本判据，
三条都是 `src.contains("GameManager.player_control_rows()")`。
突变验证（把真的调用换成手抄数组）之后，**三条一条都没红**。原因不是判据松，
是**这个字符串在注释里也出现过**——而那行注释恰好就是解释这件事的那句：

```gdscript
	# 所以它们调 `GameManager.player_control_rows()` 这一个出处。
	_add_control_rows(vbox, GameManager.player_control_rows())
```

把第二行换掉，第一行还在。`QualitySettings.video_available()` 那条更绕一层：
文件里**另有一处**一模一样的 `OS.has_feature("web")`（默认画质档那档），
扫整个文件的话把 `video_available()` 改成 `return true` 之后它匹配到的是
**那一处**。正解两刀一起下：先 `_strip_comments()`，再 `_func_body()`
限死在那个函数的函数体里（`_func_body` 还得认 `static func`，
只找 `"\nfunc "` 的话 static 后面跟 static 会一路取到文件末尾）。

这和 `edge_line_color`（声明了从没被读）、`HUD3D/HelpOverlay`（那句注释描述的
面板从来没被打开过）是**同一个家族**，只是这次更坏一档：前两者的症状是
**文档和代码各说各话**，而这一条的症状是**断言和注释各说各话**——
文档、代码、断言三方全绿，被测的行为一个字都没发生。
可推广的一条：**文本判据搜的是"这个字符串出现过"，不是"这句话在执行"，
所以凡是那个字符串可能出现在注释里的地方，判据必须先剔注释；
凡是同一个字符串可能在文件别处也出现的，判据必须先限函数体。**
判据自己写下来的注释越详细，它越容易替自己挡枪。

### ② 突变驱动读的那份数据必须是**这一遍产出的那一份**

`tools/mutate_settings.py` 第一版的 `run()` 是 `subprocess.run(..., capture_output=True)`
**然后去读 `tools/_run.log`** ——而那份 log 是上一次 `check_all` / `_run.ps1`
跑完留下的**绿**日志。十二条突变于是全部报"没红"，而真相是回归根本没被读。
而"没红"这个读数**长得和"判据写错了"一模一样**：12 条一起不对，
人第一反应是自己量错了，而不是量具读了一份上一次的残留。

连带两条：①`fails()` 里 `"[FAIL] "` 按 **8** 个字符切（`[8:]`），实际是 **7** 个，
于是每一条断言的名字都被啃掉第一个字——`"按「?」之后…"` 变成 `"「?」之后…"`，
9 条真的红了的突变全被判成 `WRONG-RED`。**量具自己歪一格的时候，
被量的东西全错，而它报出来的样子和判据有问题一模一样**；
②"0 条 FAIL"有两种完全不同的病（没红 / 没跑），所以驱动现在**先跑一遍未突变的
当基线**，且 0 条 FAIL 时把输出末尾抄进报告——一条 FAIL 都没有时，
最常见的原因是突变把脚本编译搞挂了。锚点找不到也是另一种（`ANCHOR-MISSING`
单独标出来，不和"没红"混在一起）。

**突变一个一个撤**这条纪律本身是对的，但它有个前提：**驱动自己的输出
得真的是被测物产出的**。CLAUDE.md 里已经写着"掩体是另一个突变提供的"
（四个突变一起做的时候互相垫掉失败路径），这一条是它的另一半——
**量具的输入不是这一遍的输出时，整轮结论都是上一轮的**。

## 这一轮新记的两条（2026-10-04，第八轮 #19 回访那一屏）

### ① 一个判据恒真的原因是**它量的是那个值恰好没变过**

`revisit_note` 是一个 key，而 `Localization.t()` 返回的是**那一句字符串**。
旧版 `verify_interact_latch.gd` 第 4 节断的是"面板说的是 `revisit_note`"——
它对第 2 次到访和对第 3 次到访**逐字成立**，因为产品本来就只有那一句。
于是"三次到访有三句不同的话"这件事**从来没有一条断言守着**，
而完满评级要的恰恰是三次：全游戏最强的重玩钩子，
玩家在最该被说服"再骑一趟"的那两趟里，读到的是同一段话。

**可推广的一条**：判据写成"输出 == 某个常量"时，要先问一句
**"这个值在所有要区分的情形下真的不同吗"**——两趟读同一句话，
和"两趟说的话不一样"这两件事在断言里长得一模一样。
凡是把**一个值**当期望值钉死的判据，都得配一条
**"另一个该不同的情形下它确实不同"**的对照（本轮是四句两两不同 +
`第 2 次 ≠ 第 3 次` + `没过圈 ≠ 过了圈`，而这三样是两个**独立**的轴）。

连带一条是本轮当场抓到的产品 bug：`_popup_body_text()` 第一版只按
"是不是首次"分叉，忘了保留 `station_has_fragment` 那一半，
于是 13 座普通驿站第一次路过也会读到"绕了一整圈又回到这儿"。
**回访的判据必须是"有碎片 **且** 收过了"**，不是"到过几次"——
而这两条在 13 座普通驿站上给出的答案正好相反。
现在有两条**读源码文本**的判据钉着 `_is_revisit` 的函数体里
`station_has_fragment(` 与 `is_collected(` **两个都在**：
纯函数测不到"判据写成什么了"，把整个函数换成
`return get_station_count(idx) > 0` 十几条几何断言照样全绿。

### ② 第三次：**量具**自己出错，而它报出来的样子和"判据写错了"一样

`tools/mutate_revisit.py` 第一版把**正对照**和"该红"塞进同一张表、
用同一个 AND 去判，于是第 10 条突变（让 `revisit_3rd_round` 的中英逐字相同）
明明报出了 `RED ... 中英不逐字相同`，驱动却判它 NOT-RED——
**"量具把'判据对了'读成'判据坏了'"**。改正之后第二轮又栽在下一格：
正对照是去 `[FAIL]` 列表里找的，而**一条绿着的断言压根不往失败列表里写**，
于是 11 条里 9 条全报 `CTRL-GONE`，尽管每一遍都只有该红的那一条红。

这是本项目里第三次犯同一类的错（前两次：突变驱动读的是**上一轮**留下的
绿日志；`fails()` 里 `"[FAIL] "` 按 8 字符切而实际是 7，把每条断言的
名字啃掉第一个字）。三次的共同形状是：**读数是绿的或"没咬住"，
而真相在完全另一层**。可推广的一条：**任何一层"从产物里读判据"的地方，
都要能说出"我这一遍读的是这一遍的输出吗"**——
突变驱动读文件、断言名切片长度、正对照去哪个列表找，三处都是同一个位置。
正对照**只从 `[OK]` 那几行里找**，它不参与"有没有咬住"的判定，
它只用来确认这一次红得**只该红那一条**。

## 这一轮新记的三条（2026-10-04，第九轮 P1-4 诚实性：完满明示 / 旅币 / 文档）

### ① 「收工」这个决定发生的那一屏上，屏上却只有一个按钮

「结束这一趟」是玩家**唯一能自己喊停**的出口（`CLAUDE.md` 里记着
"拿掉一条结束路径，就得补一条出口"那一条）。而按下它会做出哪一档明信片、
离完满还差几次，这个数以前**只活在集齐面板的一句话里**——另一个时刻、
另一块板子。于是玩家在暂停面板上决定"现在停还是再骑一趟"，
手上只有"按下去会收工"这一个信息。

`PausePanel` 现在在按钮下面常驻一行（代码里建，跟按钮一起显隐）：
`此刻的明信片：探索者（第 2 档 / 共 5 档）· 完满还差 13 次`。
档名是**五个玩家看得见的词**（`PostcardVariant.TIER_KEYS` → `Localization`
的 `tier_0..tier_4`），而它们此前一个都读不到——README 还把它写成"分四档"，
把唯一有玩法含义的完满整个漏在外面。

连带一条排版上的硬理由：`custom_minimum_size.x` 是必须的，不是排版洁癖。
带 `autowrap_mode` 的 Label 不给这个数，最小宽度是 1px，自动折行会**逐字**
断成十几行（文件头那条陷阱已经记过一次）。

回归：`verify_minimap.gd` 第 8b 节（按钮显隐跟着碎片数、报的是当前档、
报的是存档真值、切语言跟着走）+ `verify_postcard_ending.gd` 第 3b 节
`（五档齐全、键名是 `tier_%d`、中英都不是 key 自己、中英两两不同、
越界夹取、`visits_to_full()` 与 `compute_variant()` 对得上）。

### ② 判"没报 X"不能断**那个词**，要断**那一句**——而红得极像产品算错了

`verify_minimap.gd` 里那条"没刷满时不许报完满"第一版写的是
`not tnow.contains(_loc.t("tier_4"))`，也就是句子里不许出现「完满」两个字。
而正确的产品输出是「…· 完满还差 13 次」——**它本来就有"完满"**。
于是这条在**完全正确的代码上当场红**，报出来是
`（此刻的明信片：探索者（第 2 档 / 共 5 档）· 完满还差 13 次）`，
读起来像"档位算错了"。

可推广的一条：**判"它没有说 Y"要断说 Y 的那一句/那个状态，
不是断 Y 这几个字**——凡是那个词在别的句式里也会合法出现的时候。
判据问的是"它是不是在宣称 Y"，不是"句子里有没有 Y 的字"。
（同族还有 CLAUDE.md 里"判'哪些像素是水'不许靠颜色猜"那条：
那条的正解是量**掩膜**，不是加严颜色阈值。）

### ③ 文档里"数得出来的那几个数"从来没被钉过，而它已经错了两轮

README 开头「这个项目有 42 条回归 + 8 套出图 + 2 条探针」这句话，
到本轮为止**没有任何东西钉它**。实测：出图 **11** 套、探针 **4** 条。
症状和 `edge_line_color` 完全一样——**两边各自都绿**，
因为"文档里的数"和"仓库里的数"之间没有任何对拍。

`verify_story.gd` 第 5.6 节现在把**数得出来的**那几个钉在仓库上：
`verify_*.gd` / `lookdev_*.gd` / `probe_*.gd` 的条数（`DirAccess` 现场列），
以及 `check_all.sh` 与 `check_all.ps1` 两份 `NEEDS_WINDOW` 的条数。
**跑一次才知道的那些不钉**：PASS 几条、断言几千条每加一条断言就变，
钉住的当天就开始说谎——所以那两个数从 README 里**删掉**了，
连同"以你自己那一次的输出为准"一起留着。

钉哪几个数是**选出来的**，不是"能钉的都钉"。这一族里有三条量法上的坑，
每一条都先红过一次：

1. **`contains` 量的是"某一处写对了"，而同一件事在文档里写了两遍**
   （开头的总述 + 下面那一节）。第一版只钉正向，突变把其中一处的 11 改回 8，
   **一条都没红**。所以正向（"得有 11"）与反向（"不许还留着 8"）**成对写**——
   和"落盘闸必须配正对照"、"并集每一路都要配承重的正对照"是同一条。
2. **只读 `NEEDS_WINDOW` 所在的那一行不够**：`.ps1` 那份名单是折成两行写的，
   于是数出来 0，而"0"和"这份 runner 没写名单"长得一模一样。
   判据跨行收，**且先断一条"列得出来"的正对照**。
3. **GDScript 里三元的优先级比 `%` 高**：`"%d 条回归" % n if c else "%d regressions" % n`
   求值成 `("%d 条回归" if c else "%d regressions") % n`——拿两种语言的后缀
   去当格式化参数，六个断言全红而读起来"哪都对"。**必须显式加括号。**
   （和 `ROAD_HALF_WIDTH := ROAD_WIDTH * 0.5` 那条同族：
   你以为谁先算，写出来才知道。）

连带一条**断言数下限**（`_checks >= 80`）钉着"整份真的跑完了"。
加这一节的时候它当场抓到了一个真的：写 `for pair in {...}` 之后
`pair[path]` 抛异常，从中间掐断了后半截 8 条断言，而**汇总照样打 PASS**——
那是"抛异常的回归退出码是 0"那条的现场版。
（同一个坑还有一个：把新函数插在 `_run()` **中间**，后面 200 行全部脱出了作用域，
parse 报的是"Identifier b not declared"，指着一个根本没坏的地方。）

**写完先证明它会红**（`tools/mutate_honesty.py`，**十二个突变一个一个撤**，
驱动自己先跑一遍基线、基线不干净就退出——不然每一条都分不清"没咬住"和"没跑"）：
README 出图套数退回 8（中英各一次）/ 探针退回 2 / `.ps1` 少写一条 /
两份预算注释各改一个数 / 删掉预算注释的锚点 /
暂停面板不建那一行 / `visits_to_full()` 恒返回 0 / 档名表少一档 /
中英档名填成同一个词。**十二条全部咬住**。

### 顺带记一笔：旅币经济经得起复算，别再去怀疑它

本轮怀疑过"三圈下来应该有一千五、现在这套预算偏紧"，自己算了一遍之后
**证伪了**：`GameManager.earn_km()` 里 `clampf(new_km, 0.0, TOTAL_ROUTE_KM)`
把里程收入封在**一整圈**（188 × 2 = 376），而按 15 m/s 满速跑三圈只多赚
`路过 48 + 首次打卡 75 + 重复打卡 50 + 小游戏 100 + 碎片 150 = 423`。
所以"里程占大头"是拿 188 那个**虚构数字**当里程算出来的，
而它在产品里只付一次。`verify_economy.gd` 一直钉着"只骑全程 = 424"，
数字是对的。可推广的一条：**对经济数字起疑时先读那个数字的结算函数**，
别在常数表上做三角测量——和"这块面为什么是蓝的，先确认世界里有几盏灯"同族。

### ④ "两两不同"只查了一列，而那一列的漏洞正好是玩家读得见的

`verify_postcard_ending.gd` §3b 有一条「档名两两不同」——**只把中文那一列
`append` 进了 `names`**，英文那列算完用完就丢。于是把英文 `tier_1` 填成
`"Master"`（和 `tier_3` 撞了）**一条红都不报**：五档在英文界面里读起来是
First Ride / **Master** / Pilgrim / **Master** / Full——第 2 档和第 4 档同一个词，
而"这一行报的是我这一档"正是暂停面板上那行字存在的全部理由。
可推广的一条：**成对的东西要成对地查**。中英两侧、每一帧与下一帧、写入端与
读取端，只查一半的判据在另一半坏掉时恒绿，而且**恒绿的那一半往往正是
玩家会看到的那一半**。

### ⑤ 判据量的是"状态切换"时，**上一轮留下的持久化状态会顶替被测的缺陷**

`verify_minimap.gd` §8b 有一条「切到英文后那一行跟着换」，写法是
`t_en != tnow and t_en.contains(...)`。而 `Localization.set_language()`
把语言写进 `user://settings.cfg`——于是**上一轮跑完留在英文，这一轮开局就是
英文**，"切到英文"那一步是个空操作，`t_en == tnow` 恒真，那条永远红。
报出来的样子是"切语言没生效"，而真相是"根本没切"。
正解是**在量切换之前把起点摆出来**：`_loc.set_language("zh")` +
`_apply_language()`，再配一条正对照断言开局那句确实在中文那一侧。
可推广的一条：**凡是量"从 A 到 B"的断言，A 必须是这一遍自己设的**——
持久化设置（语言、画质档、窗口模式）、盘上残留的存档、上一轮留在
`user://` 的任何东西，都是"量具的输入不是这一遍的输出"那一族的新成员。
（同族已记的两条：`mutate_settings.py` 读上一次跑剩下的绿日志；
`check_all.sh` 跑之前要把 `layout.json` 存一份、跑完还回去。）

## 这一轮新记的一条（2026-10-05，第十轮 P0-2 琴台）

### 一个转过角度的物体，它的 AABB 里有一个**不存在的角**

「驿站脚底离路面还剩多少净空」这条断言在 `verify_stations.gd` 里
量错了**三把尺子**，而**每一把都全绿过**——三把量出来的数还各不相同：

| 尺子 | 琴台净空 | 咬不咬得住 |
| :--- | :--- | :--- |
| ① 旋转后的**世界 AABB** 的 4 个角 | 5.82m | 红（但这是错的红，见下） |
| ② 本地 AABB 的 8 个角变换后的最小值 | 13.34m | **绿，可它把 `scale` 翻到 20 也照样绿**（量到 9.67m） |
| ③ 世界 AABB 里的**精确点到盒**距离 | 4.08m | 红（同样是错的） |
| ④ **精确点到旋转盒**（转回本地系再算） | 11.70m | 对，且两个突变都咬住 |

根因是**旋转后的 AABB 有一半是空的**：琴台转 120° 之后，世界盒子的那个
「空的角」落在离模型本体 13.9m 的空中，而它正是①和③量到的东西——
**那个角从来没有任何几何在那里**。②反过来太松，因为本地盒的 8 个角
在旋转之后离中心线更远了。

正解是把采样点**转回模型的本地坐标系**，盒子自然就轴对齐了，三段式的
点到 AABB 公式直接可用（`Basis(Vector3.UP, -rot) * (p - center) / scale`）。
可推广的一条：**凡是"这个转过的物体离某条线多远"，先把点转回它的本地系
再量，不要量它的世界 AABB**——世界 AABB 对旋转物体是一个**上界**，
而它恰好在"角"那个方向上松得最多。

连着一条更要紧的：**`verify_stations.gd` 自己手抄了一份
`World3D.STATION_GLB_CONFIG`**，而那份副本**没有 `rot_y`**。
于是产品把琴台转了 120°、副本按 0° 量，测出来的 7.27m 冻结在那里，
改 `scale` 都不动。正解是 `GDScript.get_script_constant_map()` 现场读产品那份
（`World3D.gd` 的常量全是字面量，所以读得到），**跑之前先钉一条正对照
「真的读到 14 条」**，读不到就当场 `[ABORT]` 而不是继续跑一个空表。
这就是 CLAUDE.md 里「手抄的常量副本会自己长出一套预算曲线」的第三次，
前两次是草皮的 `RING_DENSITY` 和预算注释里那三个数。

第三条同族，也是这一轮最贵的教训：**突变用 `sed` 在这些源文件上不咬合**。
`sed -i 's|station_琴台.glb", "scale": 10.0|...|'` 因为文件里的中文/UTF-8
匹配不上而**静默空转**，改完跑一遍还是 PASS——而"突变没咬住"和
"判据写对了"在输出里长得一模一样。改用
`python -c` + `io.open(..., encoding='utf-8')` + `assert s.count(old) == 1`，
计数不为 1 直接炸。**凡是要靠突变证明判据会红的编辑，先确认那个编辑真的落地了。**
（同族的另一半：`mutate_*.py` 读上一次跑剩下的绿日志、
`fails()` 按 8 字符切而 `[FAIL] ` 是 7。）


## 这一轮新记的一条（2026-10-05，第十一轮 P1-1 地平线：云为什么没加）

### 引擎里没有那个旋钮，而"另铺一层"量到的只有代价

P1-1 三件事里山线层次早就做完了（`FarRidge.LAYERS` 是照着 `lookdev_journey`
§12f 一档一档调出来的，**不许顺手取整**），剩下「云」与「地标」。
云这一件先量引擎再量取景，两头都堵着：

**① 引擎侧**：Godot 4.6 的 `ProceduralSkyMaterial` **没有任何云属性**。
把实例的 `get_property_list()` 全倒出来是 25 条——
`sky_top_color` / `sky_horizon_color` / `sky_curve` / `ground_horizon_color` /
`ground_bottom_color` / `ground_curve` / `sun_angle_max` / `sun_curve` /
`sky_cover` / `sky_cover_modulate` / `sky_energy_multiplier` /
`ground_energy_multiplier` / `use_debanding` / `render_priority` ——
没有 `cloud_*`，没有 `coverage`。所以"给天加几朵云"在本引擎上不是旋钮，
要做只能是另铺一层自己的网格。
（顺带一条：`get_python_api_docs` 那套查的是 **Blender** 的 API，
`bpy.types.ShaderNodeTexSky` 返回的是 `sky_type` / `sun_disc` / `sun_elevation`
那一族 Blender 旋钮。查 Godot 的类要起一个 Godot 进程去
`ClassDB.class_get_property_list()` 现场读，别拿错引擎的文档当依据。）

**② 取景侧**：骑行视角 `12b_day_正午.png` 里**看得见的天只有 fy 0.086~0.15
一条**——上面压着顶栏衬底（fy 0.086 以下），下面 `FarRidge` 三层的轮廓顶
实测落在 fy 0.15~0.28——也就是**屏高的 6%**。而 `lookdev_journey.gd` 的
`SKY_HUE_ROW = 0.12` 量的是**同一条带**，`day_row.r < day_row.b * 0.75`
（现在 r/b = 0.45）和黄昏那两条色相方向全靠它；更要命的是 `_sky_row()`
取的是 **5 列的均值不是中位数**，一朵跨住两列的白云就足以把 r 推过那条线。
那会红，而**那个红的意思是"云画对了"**，不是产品坏了。

所以**没加云，也没放宽那两条判据**（它们当初是因为评审那条红滤片带才加的）。
真要加，量法得先换：不是改 `SKY_HUE_ROW`，而是让判据**跳过云**——
比如按"这像素比同行的中位色亮多少"把云剔掉再取色相。
可推广的一条：**"看得见的天"有多宽，是加任何东西之前该先量的那个数**——
它同时决定了新东西放不放得下、和现有取样框会不会被砸中。
