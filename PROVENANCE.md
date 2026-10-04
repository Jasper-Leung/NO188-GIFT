# 资产来源清单（PROVENANCE）

> 这份文件回答一个问题：**仓库里每一个不是本工程写出来的文件，它从哪来、能不能商用、还差什么。**
> 商用发行前每一行的「核实」列都必须变成 ✅。带 ❌ 的行**阻塞发行**。
>
> 维护方式：`tools/verify_provenance.gd` 会把 `assets/` 下每一个受管文件与本表对拍，
> **新加一个文件而没在本表登记，那条断言会红**。理由见 CLAUDE.md
> 「手抄的常量副本会自己长出一套预算曲线」——一份没人对拍的清单就是第二个事实来源。
>
> 最近一次扫描：2026-10-04（`main`）

---

## 一、总览

| 类别 | 文件数 | 商用风险 |
| :--- | :--: | :--- |
| 本工程原创（几何 / 着色器 / UI / 文本 / 音频） | 全部非下列项 | 无 |
| 字体（LXGW WenKai） | 1 | 低（OFL 1.1，附署名与 OFL 正文即可） |
| Tripo AI 生成模型 + 贴图 | 14 | **中**（取决于生成时的账号档位与当时的条款） |
| 自行车模型 + 贴图 | 2 | **高 · 来源不明** ❌ |

**当前状态：有 2 个文件阻塞商用发行。**

---

## 二、逐项

### 2.1 ❌ 阻塞 · `assets/bike.glb` + `assets/bike_10489_bicycle_diffuse.jpg`

| 字段 | 内容 |
| :--- | :--- |
| 文件 | `assets/bike.glb`（1.9 MB）、`assets/bike_10489_bicycle_diffuse.jpg`（665 KB） |
| GLB 元数据 | `asset.generator = "Khronos glTF Blender I/O v4.1.63"` |
| 内部命名 | mesh `10489_bicycle_L2`、image `10489_bicycle_diffuse` |
| 来源 | **未知** |
| 许可 | **未知** |
| 核实 | ❌ 未完成 |

**线索链**：`10489_bicycle` 这个 `<数字>_<名字>` 前缀是**从某个编号目录下载**下来的资产
的指纹，不是本工程命名（本工程的模型要么是 Tripo 的 UUID 名，要么是站名）。
Blender 导出 glTF 时**原样保留上游节点名**，所以这个名字一路从下载源跟到了 mesh 上——
这正是还能追到源头的原因。

**⚠️ 我没有把它认成某个具体来源。** 检索 `"10489"` 命中的是 Sketchfab 上一个
同名的作品（uid `a3046c5b…`，CC-BY），但那是个 51k 面的模型、不是自行车，
所以**不能据此认定**。写一个错的来源比留空更糟。

**需要做的（只有资产取得者能做）**：
1. 翻浏览器下载记录 / 素材站的「我的下载」/ 当时那条消息或网页书签，
   找 2026-09-14 前后下载 `.glb` 或 `.zip` 的记录；
2. 若来自 Sketchfab：模型页 URL 的 **uid** 与**下载窗口里那段署名文本**，
   以及当时的 **Licence 标签**（CC-BY / CC0 / CC-BY-NC …）；
   `CC-BY-NC` 商用直接出局，必须换模型。
3. 若来自付费站（CGTrader / Unity Asset Store / Fab）：需要**订单号**与该站当时的
   EULA 里「允许随游戏再分发」的那一条。
4. 换模型的成本**远低于**发出去之后被下架，所以这一步卡住就换掉，
   `World3D._build_bike()` 只用到它正投影成一根竖条这一条性质
   （回归 `verify_camera_bike.gd`），换件自行车不影响任何一条既有判据。

**在核实完成之前**：`CREDITS.md` 里这一项写的是「来源待核实」，**不是**一句免责。

---

### 2.2 ⚠️ 中风险 · Tripo AI 生成模型（7 个 GLB + 7 张 basecolor）

| 文件 | 模型名 | 内部 mesh |
| :--- | :--- | :--- |
| `assets/models/bush.glb` | round_shrub | `tripo_mesh_fbc72875-…` |
| `assets/models/tree.glb` | pine_tree | `tripo_mesh_a7d0729d-…` |
| `assets/models/station_0.glb` | traditional_chinese_pavilion | `tripo_mesh_6d3cc7fc-…` |
| `assets/models/station_1.glb` | wooden_tea_house | （UUID） |
| `assets/models/station_2.glb` | （**图生图**：`tripo_image_7564331c-…`） | `tripo_mesh_7564331c-…` |
| `assets/models/station_3.glb` | wooden_house | （UUID） |
| `assets/models/station_4.glb` | glass_greenhouse | （UUID） |

外加同目录 7 张 `*_basecolor.jpg`（就是上面那 7 个 GLB 内嵌的贴图，Godot 导入后另存了一份）。

| 字段 | 内容 |
| :--- | :--- |
| 来源 | **Tripo AI**（每个 GLB 的 `asset.generator == "Tripo"`，`version 2.0`） |
| 生成方式 | 7 件里 6 件是**文生 3D**（mesh 名是 Tripo 任务 UUID）；<br>`station_2` 是**图生 3D**（image 名 `tripo_image_<uuid>`，即上传过一张参考图） |
| 许可 | **取决于生成时的账号档位与当时的条款** |
| 核实 | ❌ 未完成 |

**为什么这 7 件风险低于自行车**：`generator` 字段直接写了 Tripo，
模型是服务生成的产物，不是从别处抄来的既有作品；
6 件纯文生，连一张外部参考图都没吃过。

**但两点必须查清**：

1. **`station_2` 上传的那张参考图是哪一张。** 图生 3D 意味着它的观感来自一张
   你无权使用的图（很可能是一张图库照片或别人的模型截图）。
   **上传行为本身**就可能违反图源站的条款——哪怕生成物是新的。
   这一件的风险等级应当按「上传物的风险」算，不是按「生成物的风险」算。
2. **README 末尾那行 `*Tripothon S1 · #Tripothon · @TripoAI*`。**
   如果这批资产是在 Tripo 的活动期里生成的，那么**活动条款**（而不是通用服务条款）
   管着它们，而活动条款通常**附带署名或公开可见性义务**——
   那正是 `CREDITS.md` 要满足的东西，但也可能还有别的义务。
   **需要拿到活动页面的条款原文并截图存档**，条款会随时间改写。

**需要做的**：生成所用的 Tripo 账号（邮箱即可）、当时的档位（Free / Pro）、
生成日期、以及活动条款原文的存档。

---

### 2.3 ✅ 低风险 · 字体

| 字段 | 内容 |
| :--- | :--- |
| 文件 | `assets/fonts/LXGWWenKai-Regular.ttf`（25,575,676 B） |
| 版本 | **LXGW WenKai 1.522**（2026-03-17），读自 TTF `name` 表 |
| 版权 | Copyright 2021-2026 LXGW (github.com/lxgw/LxgwWenKai)；<br>Copyright 2020 The Klee Project Authors (github.com/fontworks-fonts/Klee) |
| 许可 | **SIL Open Font License 1.1**（字体文件 `name` 表 ID 13 自己写着） |
| 核实 | ✅ 条款明确 |

**要做的**：把 OFL 1.1 全文与上面两行版权放进 `CREDITS.md`，并在游戏内可见。

**⚠️ 顺带查出一处将来会踩的雷**：当前仓库里是**未经修改的上游全量字体**
（25.5 MB，与上游同尺寸）。而 `tools/subset_font.py` 的用法是
「**原地覆盖** `assets/fonts/LXGWWenKai-Regular.ttf`」——
OFL §3 明确要求：**修改过的版本不得使用保留字体名（Reserved Font Name）**，
而脚本原样保留文件名与 `name` 表，所以**它产出的任何子集都是违规分发**。
Web 导出确实需要子集（25 MB 会打进 PCK 首屏），所以这不是可以不做的事。

**修法**：`subset_font.py` 的 `subprocess` 调用加上
`--name-IDs='*' --name-legacy --notdef-outline` 之外，还必须
`--drop-tables+=DSIG` 并**改写 name 表 ID 3/4/6 为非保留名**（例如
`188 Gift Subset`），或者干脆把子集写成另一个文件名并保留全量字体作为来源。
**这是 Part 7（设置/打包）里 Web 导出正式启用前必须解决的一条。**

---

### 2.4 ✅ 原创 · 音频（17 个 .ogg）

| 来源脚本 | 产物 | 随机种子 |
| :--- | :--- | :--: |
| `tools/generate_ui_sfx.py` | `sfx/collect.ogg` `open.ogg` `synthesis.ogg` `export.ogg` | `SEED = 218` |
| `tools/generate_mini_game_sfx.py` | `sfx/bamboo_cut` `bird_call` `cloud_brush` `tea_pour` `zither_1..4` | `SEED = 913` |
| `tools/gen_ambient_audio.py` | `ambient/wind` `birds` `water` `song` | `random`（未固定，见下） |

全部由三个**在本仓库里**的 Python 脚本用 numpy/scipy 或 stdlib 正弦合成，
零采样库、零素材库。**属于本工程原创，不含任何第三方素材。**

> 注：`gen_ambient_audio.py` 的 docstring 说输出 `.wav`，仓库里是 `.ogg`——
> 中间有过一次手工转码。转码不改变归属，但**这个脚本现在跑一遍得到的文件名和仓库对不上**，
> 顺带记一笔。

---

### 2.5 ✅ 原创 · 其余全部非二进制资产

- **几何**：`RoadBuilder` / `TerrainBuilder` / `VegBuilder` / `GrassScatter` /
  `TreeScatter` / `FarRidge` / `RoadVerge` / `RoadSteles` / `CrossingMark`
  —— 全部程序化生成，零导入网格。
- **着色器**：`assets/shaders/*.gdshader` **四个**（`asphalt` / `terrain_grass` /
  `grass` / `water`），全部手写着色器代码。
  （写这一行时第一遍只数出三个、漏了 `water.gdshader`——**"我知道有几个"就是这条的病**，
  所以下面那张全量登记表由脚本对着目录数出来，不靠手数。）
- **驿站小件模型**：`assets/models/station_亭灯|凉亭|岭台|廊|神苑|茶寮|驿楼.glb`
  （共 7 个，10–22 KB，**无贴图**）——由 Blender 5.2.40 导出，
  材质名沿用 `World3D.STATION_ROOF_TINT` 的 `<站名>_roof` 后缀约定，
  即**本工程自己建的**。
  **核实**：源 `.blend` 里没有链接进来的现成资产库模型（若有请在提交里一并注明）。
- **UI / 文本 / 剧本**：全部原创。诗文取自公有领域（苏轼 1037–1101）。

---

## 三、全量文件登记表

**这张表由 `tools/verify_provenance.gd` 对着 `assets/` 目录逐个对拍**：
新增任何一个文件而没在这里登记，那条断言会红。
反过来，表上写着一个已经删掉的文件同样会红（它会让下一个人去找一份不存在的授权凭证）。

| 文件（相对 `assets/` 目录的路径，逐字） | 类别 | 来源 | 许可 | 核实 |
| :--- | :--- | :--- | :--- | :-: |
| `bike.glb` | 模型 | **待核实** | **待核实** | ❌ |
| `bike_10489_bicycle_diffuse.jpg` | 贴图 | **待核实** | **待核实** | ❌ |
| `models/bush.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/bush_round_shrub_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/tree.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/tree_pine_tree_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_0.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/station_0_traditional_chinese_pavilion_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_1.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/station_1_wooden_tea_house_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_2.glb` | 模型 | Tripo AI（**图生 3D**） | **待核实** | ❌ |
| `models/station_2_tripo_image_7564331c-6364-4002-9adf-a086dd0012a6_0_0.jpg` | 贴图（= 上传的参考图） | Tripo AI | **待核实** | ❌ |
| `models/station_3.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/station_3_wooden_house_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_4.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/station_4_glass_greenhouse_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_亭灯.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `models/station_凉亭.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `models/station_岭台.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `models/station_廊.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `models/station_神苑.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `models/station_茶寮.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `models/station_驿楼.glb` | 模型 | 本工程自建 | 同 LICENSE | ✅ |
| `fonts/LXGWWenKai-Regular.ttf` | 字体 | LXGW WenKai 1.522 | **SIL OFL 1.1** | ✅ |
| `audio/bgm.ogg` | 音频 | 本工程合成 | 同 LICENSE | ✅ |
| `audio/ambient/wind.ogg` | 音频 | `gen_ambient_audio.py` | 同 LICENSE | ✅ |
| `audio/ambient/birds.ogg` | 音频 | `gen_ambient_audio.py` | 同 LICENSE | ✅ |
| `audio/ambient/water.ogg` | 音频 | `gen_ambient_audio.py` | 同 LICENSE | ✅ |
| `audio/ambient/song.ogg` | 音频 | `gen_ambient_audio.py` | 同 LICENSE | ✅ |
| `audio/sfx/collect.ogg` | 音频 | `generate_ui_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/open.ogg` | 音频 | `generate_ui_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/synthesis.ogg` | 音频 | `generate_ui_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/export.ogg` | 音频 | `generate_ui_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/bamboo_cut.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/bird_call.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/cloud_brush.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/tea_pour.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/zither_1.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/zither_2.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/zither_3.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `audio/sfx/zither_4.ogg` | 音频 | `generate_mini_game_sfx.py` | 同 LICENSE | ✅ |
| `shaders/asphalt.gdshader` | 着色器 | 本工程原创 | 同 LICENSE | ✅ |
| `shaders/terrain_grass.gdshader` | 着色器 | 本工程原创 | 同 LICENSE | ✅ |
| `shaders/grass.gdshader` | 着色器 | 本工程原创 | 同 LICENSE | ✅ |
| `shaders/water.gdshader` | 着色器 | 本工程原创 | 同 LICENSE | ✅ |

**45 个受管文件。** 缺 3 项 ❌、13 项 ⚠️、29 项 ✅。

---

## 四、仓库里另外三处该补而没补的


| 项 | 现状 | 该怎么办 |
| :--- | :--- | :--- |
| `LICENSE` | **不存在** | 定作品授权（建议 MIT 或 CC-BY-4.0），并声明第三方资产另受各自条款约束 |
| `CREDITS.md` | **不存在** | 已建（见该文件），需把 §2.1/§2.2 的核实结果填进去 |
| `export_presets.cfg` | `company_name` / `product_name` / `package.name` 全空，`package.unique_name = "com.example.$genname"` | 商用前必填。`com.example.*` 这种占位包名**过不了任何应用商店的审核** |

---

## 五、核实状态汇总

- [ ] ❌ `assets/bike.glb` / `bike_10489_bicycle_diffuse.jpg` —— 追来源、定许可
- [ ] ❌ `assets/models/station_2.glb` —— 查清上传的参考图是哪一张
- [ ] ❌ 7 个 Tripo 资产 —— 账号档位 / 生成日期 / 活动条款原文
- [ ] ⚠️ 字体子集化 —— `tools/subset_font.py` 现状产出会违反 OFL §3
- [ ] ⚠️ `export_presets.cfg` 三处占位符
- [x] ✅ 音频 17 件 —— 本工程脚本合成
- [x] ✅ 驿站小件 7 件 —— 本工程自建
- [x] ✅ 字体本身 —— SIL OFL 1.1
- [x] ✅ 几何 / 着色器 / UI / 文本 —— 原创
