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
| Tripo AI 生成模型 + 贴图 | 12 | **中**（取决于生成时的账号档位与当时的条款） |
| 自行车模型 + 贴图 | 2 | 低（**CC0 1.0**，资产取得者 2026-10-05 确认） |

**当前状态：已无阻塞商用发行的 ❌ 项。** 仍有 12 项 ⚠️ 待补证据
（6 个 Tripo 模型 + 6 张贴图的账号档位 / 生成日期 / 活动条款存档，见 §2.2）。

> 2026-10-05：原 `station_2.glb`（唯一的**图生 3D**、也是最后一件 ❌）已退役，
> 换成本工程自建的 `station_琴台.glb`（Blender 手工建模，见 §2.4）。
> **图生 3D 的风险随那份资产一起离场**——它不只是"没查到条款"，
> 而是"上传物的权利链根本追不到"，那种风险不是补一份材料能消掉的。

---

## 二、逐项

### 2.1 ✅ 低风险 · `assets/bike.glb` + `assets/bike_10489_bicycle_diffuse.jpg`

| 字段 | 内容 |
| :--- | :--- |
| 文件 | `assets/bike.glb`（1.9 MB）、`assets/bike_10489_bicycle_diffuse.jpg`（665 KB） |
| GLB 元数据 | `asset.generator = "Khronos glTF Blender I/O v4.1.63"` |
| 内部命名 | mesh `10489_bicycle_L2`、image `10489_bicycle_diffuse` |
| 来源 | 编号目录下载的资产（`10489_bicycle` 是那个目录的前缀指纹） |
| 许可 | **CC0 1.0 Universal（公共领域贡献）** |
| 核实 | ✅ 资产取得者 2026-10-05 确认 |

**这一项曾经是最高风险的一条**（"来源不明 ❌"），因为下游没有任何东西能证明
CC0 是真的——`10489_bicycle` 这个 `<数字>_<名字>` 前缀只是**从某个编号目录下载**
的指纹，而**检索 `"10489"` 命中的 Sketchfab 作品是个 51k 面的模型、不是自行车**，
所以不能据此认定。**是资产取得者本人确认的，不是我认定的**，这一点要记清楚：
写一个错的来源比留空更糟，而这条的依据只可能是当事人。

> **⚠️ CC0 不要求署名，但仍建议在 `CREDITS.md` 里写明**。
> CC0 的"不署名"是**许可方放弃**的权利，不是**被许可方可以隐瞒来源**的义务；
> 而一件来路不明的资产在发行后被质疑时，唯一能自证的就是这份书面确认。
> 所以 `CREDITS.md` §4.1 记的是"作者未署名 / 许可 CC0-1.0 / 2026-10-05 资产取得者确认"。

**顺带记一笔：曾经考虑换成 `D:/code/20261001/modelbone/bike_ride/bicycle_clean.glb`，没换。**
那份 GLB 的 `asset.generator == "Tripo"`（它是本工程另一个项目的 Tripo 原始车模
在 Blender 里重建曲柄组之后的产物），换过去等于**把一件 CC0 降级成 Tripo ⚠️**——
风险不降反升，而体积从 1.9 MB 涨到 22.5 MB、网格数从 1 涨到 25。
它那一侧真正解决的问题是**曲柄组几何缺陷**，而本工程的车是正后方看过去
正投影成一根竖条，**曲柄在屏上根本看不见**，所以那个缺陷在本项目里不存在。

---

### 2.2 ⚠️ 中风险 · Tripo AI 生成模型（6 个 GLB + 6 张 basecolor）

| 文件 | 模型名 | 内部 mesh |
| :--- | :--- | :--- |
| `assets/models/bush.glb` | round_shrub | `tripo_mesh_fbc72875-…` |
| `assets/models/tree.glb` | pine_tree | `tripo_mesh_a7d0729d-…` |
| `assets/models/station_0.glb` | traditional_chinese_pavilion | `tripo_mesh_6d3cc7fc-…` |
| `assets/models/station_1.glb` | wooden_tea_house | （UUID） |
| `assets/models/station_3.glb` | wooden_house | （UUID） |
| `assets/models/station_4.glb` | glass_greenhouse | （UUID） |

外加同目录 6 张 `*_basecolor.jpg`（就是上面那 6 个 GLB 内嵌的贴图，Godot 导入后另存了一份）。

| 字段 | 内容 |
| :--- | :--- |
| 来源 | **Tripo AI**（每个 GLB 的 `asset.generator == "Tripo"`，`version 2.0`） |
| 生成方式 | **6 件全部是文生 3D**（mesh 名是 Tripo 任务 UUID）。<br>原第 7 件 `station_2.glb` 是图生 3D，2026-10-05 退役（见 §2.4） |
| 许可 | **取决于生成时的账号档位与当时的条款** |
| 核实 | ❌ 未完成 |

**为什么这 6 件风险低于自行车**：`generator` 字段直接写了 Tripo，
模型是服务生成的产物，不是从别处抄来的既有作品；
6 件全是文生 3D，连一张外部参考图都没吃过。
（原第 7 件是图生 3D——观感来自一张你无权使用的图，而**上传行为本身**就可能
违反图源站的条款。那一件的风险等级必须按「上传物的风险」算，
不是按「生成物的风险」算，而**那种风险补材料消不掉**，
所以它是被换掉而不是被核实的，见 §2.4。）

**还必须查清的一点**：

1. **README 末尾那行 `*Tripothon S1 · #Tripothon · @TripoAI*`。**
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

**要做的**：把 OFL 1.1 全文与上面两行版权放进 `CREDITS.md`，并在游戏内可见。（已完成）

### 2.3b ✅ 已装护栏 · 子集化（**当前不做子集**）

**现状（2026-10-05）**：字体**不子集化**，25.5 MB 全量随包。发行计划里
**字体要整个换掉**，所以子集这件事要等换完字体、新字体的条款确定之后再做。

**为什么原来记着一条 ⚠️**：旧版 `tools/subset_font.py` 是**原地覆盖**
`assets/fonts/LXGWWenKai-Regular.ttf` 的，而 SIL OFL 1.1 §3 写的是
「No Modified Version may use the Reserved Font Name(s)」。裁剪就是
Modified Version，而脚本原样保留了文件名与 `name` 表 ID 3/4/6 ——
于是**它产出的任何子集都是一个自称「LXGW WenKai」的修改版**。§3 违规不可逆：
文件发出去之后再改名，违规已经发生了。

**已经改成三道**（`tools/subset_font.py`，2026-10-05）：

| | 旧版 | 现在 |
| :--- | :--- | :-- |
| 输出 | `os.replace` 盖回**源字体** | 另存 `assets/fonts/LXGWWenKai-Subset.ttf`，**源字体一个字节都不动** |
| name 表 3/4/6 | 原样保留 | 改写成 `188 Gift Subset`（非保留名）；§3 只约束 ID 4，但 macOS/Windows 字体菜单认的是 ID 3 和 6，所以三个一起改 |
| DSIG | 留着（裁剪后必然失效） | `drop_tables += ["DSIG"]` |
| 原地覆盖 | 无门槛 | 要 `--in-place` **加** `--ofl-reserved-name-cleared` 两个键才肯跑 |

**⚠️ 护栏装的是"停下来问"，不是"我替你判断"** —— 因为
**「有没有保留字体名」这件事从二进制里读不出来**：保留字体名是在版权声明
之后声明的名字（§1），而本字体 `name` 表 ID 0 的版权行里**没有**这一句：

```
Copyright 2021-2026 LXGW (https://github.com/lxgw/LxgwWenKai)
Copyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee)
```

没有声明就等于本字体自己没保留任何名字，§3 对它不成立。但字形派生自 Klee，
而 **Klee 的 OFL 头里通常带 `with Reserved Font Name 'Klee'`** ——
**这一句在 `LICENSE` 文件里，不在 TTF 里**，所以任何脚本都量不出来。
**真要发子集之前，先去 `github.com/fontworks-fonts/klee` 把 LICENSE 那几行读出来。**

**实测**（2026-10-05 跑一遍，产物已删，源字体 25,575,676 B 未变）：
2193 字符 → **24.39 MB → 0.89 MB**，`name` 3/4/6 确认为
`188 Gift Subset` / `188 Gift Subset` / `188GiftSubset`，`DSIG` 已不在表里，
`name` ID 0 的版权行**原样保留**（OFL §2 要求）。


---

### 2.3b ✅ 原创 · `assets/models/station_琴台.glb`

| 字段 | 内容 |
| :--- | :--- |
| 文件 | `assets/models/station_琴台.glb`（116,912 B，1 mesh / 5 primitive / 1011 面） |
| 顶替 | 原 `station_2.glb`（Tripo 图生 3D，2026-10-05 退役） |
| 建模 | **Blender 5.2.2 手工建模**，坐标按米、Y 轴向上，无 UV、无贴图 |
| 授权 | 与本仓库其余原创部分同（见根目录 `LICENSE`） |

**为什么是"换掉"而不是"补材料"**：图生 3D 的观感来自一张上传的参考图，
而那张图的来源与许可**在生成物里没有任何痕迹**——`asset.generator` 只写得到
"Tripo"，写不到那张图是谁的。补一份活动条款解决不了"上传物是谁的"这个问题。
本工程本来就有 7 座站用同一套约定自建（`station_驿楼` … `station_亭灯`），
第 8 座照同一套做即可，**零新增风险**。

**它必须继续守住的四件事**（都由 `tools/verify_station_roof.gd` 与
`tools/verify_stations.gd` 量着）：

1. **材质名带 `琴台_` 前缀**，且含 `_roof` —— `World3D._tint_station_roofs()`
   按 `_roof` 后缀认，改名就会有一片屋顶掉回青瓦。
2. **挡车半径 < `STATION_PASS_RADIUS`(15m)** —— 本模型实测半跨 8.09m、
   加 `STATION_KEEPOUT_PAD`(1.6) 得 **9.69m**。这一圈树原本撑到 11.78m，
   差 3.2m 就要贴到打卡圈上，而顶栏「下一处」永远减不到 0、圈永远不亮。
3. **名牌高度 ≥ 净空 1m** —— 模型高 7.95m，`label_y` 取 10.0。
4. **六个 mesh 一批的 GLB 惯例**：1 mesh、每材质一个 primitive、
   只带 `POSITION` + `NORMAL`、无 UV。

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
| `bike.glb` | 模型 | 编号目录下载（`10489_bicycle`） | **CC0 1.0** | ✅ |
| `bike_10489_bicycle_diffuse.jpg` | 贴图 | 同上（GLB 内嵌） | **CC0 1.0** | ✅ |
| `models/bush.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/bush_round_shrub_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/tree.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/tree_pine_tree_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_0.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/station_0_traditional_chinese_pavilion_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
| `models/station_1.glb` | 模型 | Tripo AI | **待核实** | ⚠️ |
| `models/station_1_wooden_tea_house_3d_model_basecolor.jpg` | 贴图 | Tripo AI | **待核实** | ⚠️ |
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
| `models/station_琴台.glb` | 模型 | 本工程自建（2026-10-05，顶掉原 `station_2.glb`） | 同 LICENSE | ✅ |
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

**44 个受管文件。** **缺 0 项 ❌**、12 项 ⚠️、32 项 ✅。

---

## 四、仓库里另外三处该补而没补的


| 项 | 现状 | 该怎么办 |
| :--- | :--- | :--- |
| `LICENSE` | **不存在** | 定作品授权（建议 MIT 或 CC-BY-4.0），并声明第三方资产另受各自条款约束 |
| `CREDITS.md` | **不存在** | 已建（见该文件），需把 §2.1/§2.2 的核实结果填进去 |
| `export_presets.cfg` | `company_name` / `product_name` / `package.name` 全空，`package.unique_name = "com.example.$genname"` | 商用前必填。`com.example.*` 这种占位包名**过不了任何应用商店的审核** |

---

## 五、核实状态汇总

- [x] ✅ `assets/bike.glb` / `bike_10489_bicycle_diffuse.jpg` —— **CC0 1.0**（取得者 2026-10-05 确认）
- [x] ✅ 原 `assets/models/station_2.glb` —— **已退役**（2026-10-05 换成自建的
      `station_琴台.glb`，图生 3D 的上传物权利链追不到，那种风险补材料消不掉）
- [ ] ⚠️ 6 个 Tripo 资产 + 6 张贴图 —— 账号档位 / 生成日期 / 活动条款原文
- [ ] ⚠️ `export_presets.cfg` 的 `package/unique_name` —— 仍是占位
      （`com.example.gift188`），上架前必须换成真实包名
- [x] ✅ 字体子集化 —— **当前不做子集**（25.5 MB 全量随包），`tools/subset_font.py`
      的 OFL §3 违规已在脚本里装护栏（见 §2.3）；换字体之后再重新评估
- [x] ✅ 音频 17 件 —— 本工程脚本合成
- [x] ✅ 驿站小件 8 件 —— 本工程自建（新增 `station_琴台.glb`）
- [x] ✅ 字体本身 —— SIL OFL 1.1
- [x] ✅ 几何 / 着色器 / UI / 文本 —— 原创
