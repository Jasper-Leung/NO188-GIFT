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

### 4.1 自行车

- 文件：`assets/bike.glb`、`assets/bike_10489_bicycle_diffuse.jpg`
- 作者：**未署名**（该模型以 CC0 分发，未附作者署名）
- 许可：**CC0 1.0 Universal — Public Domain Dedication**
  （<https://creativecommons.org/publicdomain/zero/1.0/>）
- 确认日期：2026-10-05，由资产取得者确认

```
CC0 1.0 Universal

CREATIVE COMMONS CORPORATION IS NOT A LAW FIRM AND DOES NOT PROVIDE
LEGAL SERVICES. DISTRIBUTION OF THIS DOCUMENT DOES NOT CREATE AN
ATTORNEY-CLIENT RELATIONSHIP. CREATIVE COMMONS PROVIDES THIS
INFORMATION ON AN "AS-IS" BASIS. CREATIVE COMMONS MAKES NO WARRANTIES
REGARDING THE USE OF THIS DOCUMENT OR THE INFORMATION OR WORKS
PROVIDED HEREUNDER, AND DISCLAIMS LIABILITY FOR DAMAGES RESULTING FROM
THE USE OF THIS DOCUMENT OR THE INFORMATION OR WORKS PROVIDED
HEREUNDER.

Statement of Purpose

The laws of most jurisdictions throughout the world automatically
exclusively grant Copyright and Related Rights (Defined Below) to the
author and subsequent owner(s) (each and all, an "owner") of an
original work of authorship and/or a database (each, a "Work").

Certain owners wish to permanently relinquish those rights to a Work
for the purpose of contributing to a commons of creative, cultural and
scientific works ("Commons") that the public can reliably and without
fear of later claims of infringement build upon, modify, incorporate in
other works, reuse and redistribute as freely as possible in any form
whatsoever and for any purposes, including without limitation
commercial purposes. These owners may contribute to the Commons to
promote the ideal of a free culture and the further production of
creative, cultural and scientific works, or to gain reputation or
greater distribution for their Work in part through the use and efforts
of others.

For these and/or other purposes and motivations, and without any
expectation of additional consideration or compensation, the person
associating CC0 with a Work (the "Affirmer"), to the extent that he or
she is an owner of Copyright and Related Rights in the Work, freely
elects to apply CC0 to the Work and publicly distribute the Work under
its terms, with knowledge of his or her Copyright and Related Rights in
the Work and the meaning and intended legal effect of CC0 on those
rights.

1. Copyright and Related Rights. A Work made available under CC0 may be
protected by copyright and related or neighboring rights ("Copyright
and Related Rights"). Copyright and Related Rights include, but are not
limited to, the following:

  i. the right to reproduce, adapt, distribute, perform, display,
     communicate, and translate a Work;
 ii. moral rights retained by the original author(s) and/or performer(s);
iii. publicity and privacy rights pertaining to a person's image or
     likeness depicted in a Work;
 iv. rights protecting against unfair competition in regards to a Work,
     subject to the limitations in paragraph 4(a), below;
  v. rights protecting the extraction, dissemination, use and reuse of
     data in a Work;
 vi. database rights (such as those arising under Directive 96/9/EC of
     the European Parliament and of the Council of 11 March 1996 on the
     legal protection of databases, and under any national implementation
     thereof, including any amended or successor version of such
     directive); and
vii. other similar, equivalent or corresponding rights throughout the
     world based on applicable law or treaty, and any national
     implementations thereof.

2. Waiver. To the greatest extent permitted by, but not in contravention
of, applicable law, Affirmer hereby overtly, fully, permanently,
irrevocably and unconditionally waives, abandons, and surrenders all of
Affirmer's Copyright and Related Rights and associated claims and causes
of action, whether now known or unknown (including existing as well as
future claims and causes of action), in the Work (i) in all territories
worldwide, (ii) for the maximum duration provided by applicable law or
treaty (including future time extensions), (iii) in any current or future
medium and for any number of copies, and (iv) for any purpose whatsoever,
including without limitation commercial, advertising or promotional
purposes (the "Waiver"). Affirmer makes the Waiver for the benefit of each
member of the public at large and to the detriment of Affirmer's heirs and
successors, fully intending that such Waiver shall not be subject to
revocation, rescission, cancellation, termination, or any other legal or
equitable action to disrupt the quiet enjoyment of the Work by the public
as contemplated by Affirmer's express Statement of Purpose.

3. Public License Fallback. Should any part of the Waiver for any reason
be judged legally invalid or ineffective under applicable law, then the
Waiver shall be preserved to the maximum extent permitted taking into
account Affirmer's express Statement of Purpose. In addition, to the
extent the Waiver is so judged Affirmer hereby grants to each affected
person a royalty-free, non transferable, non sublicensable, non exclusive,
irrevocable and unconditional license to exercise Affirmer's Copyright and
Related Rights in the Work (i) in all territories worldwide, (ii) for the
maximum duration provided by applicable law or treaty (including future
time extensions), (iii) in any current or future medium and for any number
of copies, and (iv) for any purpose whatsoever, including without
limitation commercial, advertising or promotional purposes (the
"License"). The License shall be deemed effective as of the date CC0 was
applied by Affirmer to the Work. Should any part of the License for any
reason be judged legally invalid or ineffective under applicable law, such
partial invalidity or ineffectiveness shall not invalidate the remainder
of the License, and in such case Affirmer hereby affirms that he or she
will not (i) exercise any of his or her remaining Copyright and Related
Rights in the Work or (ii) assert any associated claims and causes of
action with respect to the Work, in either case contrary to Affirmer's
express Statement of Purpose.

4. Limitations and Disclaimers.

 a. No trademark or patent rights held by Affirmer are waived, abandoned,
    surrendered, licensed or otherwise affected by this document.
 b. Affirmer offers the Work as-is and makes no representations or
    warranties of any kind concerning the Work, express, implied,
    statutory or otherwise, including without limitation warranties of
    title, merchantability, fitness for a particular purpose, non
    infringement, or the absence of latent or other defects, accuracy, or
    the present or absence of errors, whether or not discoverable, all to
    the greatest extent permissible under applicable law.
 c. Affirmer disclaims responsibility for clearing rights of other persons
    that may apply to the Work or any use thereof, including without
    limitation any person's Copyright and Related Rights in the Work.
    Further, Affirmer disclaims responsibility for obtaining any necessary
    consents, permissions or other rights required for any use of the
    Work.
 d. Affirmer understands and acknowledges that Creative Commons is not a
    party to this document and has no duty or obligation with respect to
    this CC0 or use of the Work.
```

> **为什么 CC0 仍然写进这一份。** CC0 的"不署名"是**许可方放弃**的权利，
> 不是**被许可方可以隐瞒来源**的义务。而这件资产带一个第三方编号前缀
> （mesh 名 `10489_bicycle_L2`），发行后若被质疑，唯一能自证的就是这份书面确认。
> 详见 `PROVENANCE.md` §2.1。

### 4.2 ⚠️ 待核实 · Tripo AI 生成模型

以下 **6** 个模型及其 basecolor 贴图由 **Tripo AI** 生成
（每个 GLB 内部 `asset.generator == "Tripo"`），**全部是文生 3D**：

`bush` · `tree` · `station_0`（traditional_chinese_pavilion）·
`station_1`（wooden_tea_house）· `station_3`（wooden_house）·
`station_4`（glass_greenhouse）

- 生成服务：Tripo AI — https://tripo3d.ai
- 账号档位 / 生成日期：**待补**
- 适用条款（通用服务条款 or 活动条款）：**待补**

> 原本还有第 7 个 `station_2`——它是用**上传参考图**的方式生成的，
> 因此还要遵守**上传物本身**的条款，而那张图的来源在生成物里查不到。
> 2026-10-05 已用本工程自建的 `station_琴台.glb` 换掉并退役，
> 见 `PROVENANCE.md` §2.2 与 §2.3b。

### 4.3 驿站建筑（11 件）· 本工程自建

`驿楼` · `茶寮` · `岭台` · `神苑` · `凉亭` · `廊` · `亭灯` · `琴台` ·
**`钟楼`** · **`望台`** · **`风亭`**

全部由本仓库用 Blender 手工建模后导出 GLB，**无 UV、无贴图**，
材质为程序化纯色。授权与本工程原创部分相同（见根目录 `LICENSE`）。

`钟楼` / `望台` / `风亭` 也是 2026-10-05 新建的，替代三对**共用同一个 GLB**
的驿站（`起程驿楼`/`东岭驿楼`、`右岭岭台`/`西谷岭台`、`岭口凉亭`/`北岭凉亭`）：
现在 **16 座站指向 16 个互不相同的模型**。三个新模型是**新几何**而不是
旧模型换一次颜色——同族那把「颜色签名」尺子分不开它们（同一个 GLB 实测
0.0114，而真的一对不同建筑 0.0407，离阈值 0.04 只差 0.0007）。

`琴台` 是 2026-10-05 新建的，替代原 Tripo 的 `station_2`。
它的造型取自 `docs/station_joy_prompts.md` §3.12 定的两条硬要求：
**六棵细瘦的树围成半圈、中间留天光**，以及**琴和台面必须看得见**——
古琴的**十三根弦一根不少**（几何上确实建了 13 根，但骑行那一档 18m 外
那 13 根只占约 7px、间距 0.54px，**数不出来的**；量法见
`docs/station_joy_prompts.md` §3.12 末尾「一条做不到的要求」）。

---

## 五、项目自身的许可

见仓库根目录 [`LICENSE`](LICENSE)。该许可**只覆盖本工程原创部分**，
第三部分钟全部资产另受上列各自条款约束。
