# CREDITS / 致谢与授权

本文件是**随发行物一起提供**的署名与许可声明。
需要改的不是这份文件，而是它下面标 `⚠️ 待核实` 的几行——把它们填成事实，
而不是填成免责。

完整的来源扫描与核实进度见 [`PROVENANCE.md`](PROVENANCE.md)。

---

## 一、本工程原创

- **程序**、**游戏世界几何**（路线、地形、路肩、远景山线、路碑、交叉点碑、植被与草皮）
- **全部着色器**（`assets/shaders/*.gdshader`）
- **全部界面与字体排版逻辑**
- **全部音频**：17 个 `.ogg` 由本仓库的三个 Python 脚本用正弦/噪声合成
  （`tools/generate_ui_sfx.py`、`tools/generate_mini_game_sfx.py`、
  `tools/gen_ambient_audio.py`），**未使用任何采样库或素材库**
- **全部文本**：游戏脚本、界面文案，以及取自公有领域的东坡诗文
  （苏轼，1037–1101）

## 二、叙事与路线

- 路线为**自行构造的数学 8 字图案**（`scripts/road_data.gd` 的解析式 lemniscate 采样），
  **不参考、不还原任何现实公路走向**。全部驿站名为**虚构雅称**。
- 题材取自公有领域的东坡诗文与「风景骑行」这一公共文化母题。

---

## 三、字体

### LXGW WenKai

- 文件：`assets/fonts/LXGWWenKai-Regular.ttf`，版本 **1.522**（2026-03-17）
- 版权：
  - Copyright 2021-2026 LXGW (https://github.com/lxgw/LxgwWenKai)
  - Copyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee)
- 许可：**SIL Open Font License, Version 1.1**
  （<https://openfontlicense.org>）

```
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical writer
or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```

---

## 四、第三方 3D 模型与贴图

### 4.1 ⚠️ 待核实 · 自行车

- 文件：`assets/bike.glb`、`assets/bike_10489_bicycle_diffuse.jpg`
- 作者：**待核实**
- 来源页面：**待核实**
- 许可：**待核实**

> **这一行现在写的是「待核实」，不是免责。**
> 该资产带有一个第三方编号前缀（mesh 名 `10489_bicycle_L2`），
> 说明它是从某个编号目录下载的，而**来源尚未追到**。
> 在追到之前，本文件不宣称任何授权。见 `PROVENANCE.md` §2.1。

### 4.2 ⚠️ 待核实 · Tripo AI 生成模型

以下 7 个模型及其 basecolor 贴图由 **Tripo AI** 生成
（每个 GLB 内部 `asset.generator == "Tripo"`）：

`bush` · `tree` · `station_0`（traditional_chinese_pavilion）·
`station_1`（wooden_tea_house）· `station_2`（图生 3D）·
`station_3`（wooden_house）· `station_4`（glass_greenhouse）

- 生成服务：Tripo AI — https://tripo3d.ai
- 账号档位 / 生成日期：**待补**
- 适用条款（通用服务条款 or 活动条款）：**待补**
- 图生 3D 的参考图出处：**待核实**

> `station_2` 是**上传参考图**后生成的，因此还要遵守**上传物本身**的条款。
> 见 `PROVENANCE.md` §2.2。

---

## 五、项目自身的许可

见仓库根目录 [`LICENSE`](LICENSE)。该许可**只覆盖本工程原创部分**，
第三部分钟全部资产另受上列各自条款约束。
