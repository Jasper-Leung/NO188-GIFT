"""字体子集化：把 25MB 的 LXGW WenKai 裁到工程实际用到的字符。

**当前不启用。** 发行计划里字体要整个换掉，而 25.5MB 全量随包会打进 Web 的
PCK 首屏——所以这件事迟早要做，但**不是现在**，也不是这个脚本要顺手做的。

## 它为什么不再原地覆盖（OFL §3）

旧版把子集**直接盖回源字体**，而 SIL OFL 1.1 §3 写的是：

> No Modified Version of the Font Software may use the Reserved Font Name(s)
> unless explicit written permission is granted by the corresponding Copyright
> Holder. This restriction only applies to the primary font name as presented
> to the users.

裁剪本身就是 "Modified Version"（§1 的定义：*by changing formats or by porting
the Font Software to a new environment* 之外的任何增减替换），而脚本原样保留了
文件名与 name 表 ID 3/4/6 —— 于是**它产出的任何子集都是一个自称「LXGW WenKai」
的修改版**。§3 违规不可逆：文件发出去之后再改名，违规已经发生了。

⚠️ **"有没有保留字体名"这件事，从二进制里读不出来。** 保留字体名是在版权声明
之后声明的名字（§1 的定义），而本字体 name 表 ID 0 的版权行里**没有**这一句：

    Copyright 2021-2026 LXGW (https://github.com/lxgw/LxgwWenKai)
    Copyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee)

没有声明就等于**本字体自己没有保留任何名字**，§3 那一条对它不成立。但 LXGW 的
字形派生自 Klee，而 **Klee 的 OFL 头里通常带 "with Reserved Font Name 'Klee'"**——
**这一句在 `LICENSE` 文件里，不在 TTF 里**，所以量不出来。见
`PROVENANCE.md` §2.3。**真要发子集之前，先去 `github.com/fontworks-fonts/klee`
把 LICENSE 那几行读出来。**

所以这里做的是**把违约变成一个需要两次确认的显式动作**，而不是替人判断：
子集默认写到**另一个文件名**、name 表改写成非保留名、DSIG 丢掉，
而原地覆盖要 `--in-place` 加 `--ofl-reserved-name-cleared` **两个**键。

用法:
    python tools/subset_font.py                        # 另存 assets/fonts/LXGWWenKai-Subset.ttf
    python tools/subset_font.py <源ttf>                 # 从完整字体重新生成
    python tools/subset_font.py --in-place --ofl-reserved-name-cleared
                                                        # 原地覆盖（需要两个键）

依赖: pip install fonttools
"""
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

SRC = os.path.join("assets", "fonts", "LXGWWenKai-Regular.ttf")
DST = os.path.join("assets", "fonts", "LXGWWenKai-Subset.ttf")

# OFL §3：修改版不得使用保留字体名。裁剪版一律改用这个**非保留**名。
SUBSET_FAMILY = "188 Gift Subset"

# 跳过导入缓存 / 构建产物 / 版本库
EXCLUDE_DIRS = {".godot", "android", "__pycache__", ".git", "build"}
TEXT_EXT = {
    ".gd", ".tscn", ".cfg", ".tres", ".md", ".py", ".html",
    ".gdshader", ".svg", ".import", ".uid", ".txt", ".svg",
}

# 工程外的文案来源：PRD 与真实路网数据。游戏文案以它们为准，
# 一并纳入可防止后续补文案时出现缺字。
EXTRA_GLOBS = [
    os.path.join("..", "No218gift", "*.md"),
    os.path.join("..", "No218gift", "*.svg"),
]

# 兜底字符集：ASCII 可打印 + 中文/全角常用标点
EXTRA_CHARS = "　、。，．；：？！…—–·「」『』【】〔〕《》〈〉（）〈〉“”‘’〃～￥％＆＃＊＋＝－／\\"
EXTRA_CHARS += "　｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙレﾛﾎﾜﾝﾞﾟ"


def _project_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def collect_chars(root: str) -> set:
    chars = set()

    def absorb(path: str) -> None:
        try:
            with open(path, encoding="utf-8", errors="ignore") as fh:
                for ch in fh.read():
                    if ord(ch) >= 32:
                        chars.add(ch)
        except OSError:
            pass

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fname in filenames:
            if os.path.splitext(fname)[1].lower() not in TEXT_EXT:
                continue
            absorb(os.path.join(dirpath, fname))

    for pattern in EXTRA_GLOBS:
        for path in glob.glob(os.path.join(root, pattern)):
            absorb(path)

    chars.update(chr(c) for c in range(0x21, 0x80))
    chars.update(EXTRA_CHARS)
    return chars


def _rename(font: TTFont) -> None:
    """把 name 表 3/4/6 改写成非保留名（OFL §3）。

    §3 只约束「primary font name as presented to the users」，也就是 ID 4；
    ID 3（唯一标识）和 ID 6（PostScript 名）留着原样的话，一份子集仍然
    自称「LXGW WenKai」，而在 macOS / Windows 的字体菜单里 **ID 3 和 ID 6
    才是被认出来的那两个**——所以三个一起改。
    """
    version = "1.522"
    postscript = SUBSET_FAMILY.replace(" ", "")
    mapping = {
        3: f"{SUBSET_FAMILY}:Subset of LXGW WenKai {version}",
        4: SUBSET_FAMILY,
        6: postscript,
    }
    for rec in list(font["name"].names):
        if rec.nameID in mapping:
            font["name"].setName(mapping[rec.nameID], rec.nameID, rec.platformID,
                                 rec.platEncID, rec.langID)


def main() -> None:
    os.chdir(_project_root())

    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    in_place = "--in-place" in sys.argv
    cleared = "--ofl-reserved-name-cleared" in sys.argv

    if in_place and not cleared:
        print(
            "拒绝执行：--in-place 会把裁剪版盖回源字体。\n"
            "  裁剪是 OFL 的 Modified Version，§3 要求它不得使用保留字体名，\n"
            "  而保留字体名写在**上游 LICENSE 文件里、不在 TTF 里**，量不出来。\n"
            "  先去 github.com/fontworks-fonts/klee 读 LICENSE 确认无保留名，\n"
            "  再加 --ofl-reserved-name-cleared 一起跑。",
            file=sys.stderr,
        )
        sys.exit(2)

    src = argv[0] if argv else SRC
    if not os.path.isfile(src):
        print(f"源字体不存在: {src}", file=sys.stderr)
        sys.exit(1)

    dst = src if in_place else (DST if os.path.abspath(src) == os.path.abspath(SRC) else src)

    required = collect_chars(".")
    print(f"工程文本字符数: {len(required)}")
    print(f"源字体: {os.path.getsize(src) / 1048576:.2f} MB")

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    # DSIG 是旧式数字签名的容器；裁剪必然让它失效，留着只会让某些校验器报错。
    opts.drop_tables += ["DSIG"]
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(text="".join(sorted(required)))

    font = TTFont(src, fontNumber=0)
    orig_cmap = set(font.getBestCmap().keys())
    subsetter.subset(font)
    _rename(font)

    tmp = dst + ".subset.ttf"
    font.save(tmp)

    # 覆盖前校验：子集不得比原字体少字（缺字在运行时渲染成豆腐块）。
    # 原字体本身就不含的字符（如 emoji，多来自 PRD 的 markdown）不算回退，单独报告。
    cmap = set(TTFont(tmp, fontNumber=0).getBestCmap().keys())
    dropped = sorted(c for c in required if ord(c) not in cmap and ord(c) in orig_cmap)
    if dropped:
        os.remove(tmp)
        print(f"失败: 子集比原字体少了 {len(dropped)} 个字符", file=sys.stderr)
        print("前 40 个: " + "".join(dropped[:40]), file=sys.stderr)
        sys.exit(1)

    # 原字体缺的字符：不是本次改动引入的，但游戏里若真用到会显示豆腐块
    no_glyph = sorted(c for c in required if ord(c) not in orig_cmap)
    if no_glyph:
        print(f"提示: 原字体本身不含 {len(no_glyph)} 个字符: " + "".join(no_glyph[:40]))

    os.replace(tmp, dst)
    print(f"完成: {len(required)} 字符 -> {os.path.getsize(dst) / 1048576:.2f} MB ({dst})")
    if not in_place:
        print("提醒：源字体保持原样。要随包发子集的话，把 Godot 主题指向 "
              f"res://assets/fonts/{os.path.basename(dst)} 并把全量 TTF 移出工程。")


if __name__ == "__main__":
    main()
