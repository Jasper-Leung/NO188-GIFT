"""字体子集化：把 25MB 的 LXGW WenKai 裁到工程实际用到的字符。

Godot Web 导出会把整个 TTF 原样打进 PCK，25MB 字体占了首屏一半以上。
本脚本收集工程内所有文本用到的字符，生成子集字体原地覆盖，并在覆盖前校验无缺字
（缺字在运行时渲染成豆腐块 □，属阻断性缺陷）。

用法:
    python tools/subset_font.py              # 原地子集化 assets/fonts 下的字体
    python tools/subset_font.py <源ttf>      # 从完整字体重新生成（如从 git 历史恢复）

依赖: pip install fonttools
"""
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

SRC = os.path.join("assets", "fonts", "LXGWWenKai-Regular.ttf")

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


def main() -> None:
    os.chdir(_project_root())

    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    if not os.path.isfile(src):
        print(f"源字体不存在: {src}", file=sys.stderr)
        sys.exit(1)

    required = collect_chars(".")
    print(f"工程文本字符数: {len(required)}")
    print(f"源字体: {os.path.getsize(src) / 1048576:.2f} MB")

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(text="".join(sorted(required)))

    font = TTFont(src, fontNumber=0)
    orig_cmap = set(font.getBestCmap().keys())
    subsetter.subset(font)

    tmp = src + ".subset.ttf"
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

    os.replace(tmp, SRC if os.path.abspath(src) == os.path.abspath(SRC) else src)
    print(f"完成: {len(required)} 字符 -> {os.path.getsize(src) / 1048576:.2f} MB")


if __name__ == "__main__":
    main()
