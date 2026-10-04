"""评审用的小工具：把定妆照切成原尺寸的区域来看。

用法：python tools/judge_crop.py <图> <x> <y> <w> <h> [放大倍数] [输出名]
不写输出名就打到 stdout 的临时目录。
"""
import sys
import os
from PIL import Image

src = sys.argv[1]
x, y, w, h = (int(v) for v in sys.argv[2:6])
scale = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0

im = Image.open(src).convert("RGB")
box = im.crop((x, y, x + w, y + h))
if scale != 1.0:
    box = box.resize((int(box.width * scale), int(box.height * scale)), Image.LANCZOS)

out = sys.argv[7] if len(sys.argv) > 7 else os.path.join(
    os.environ.get("TEMP", "."), "judge_crop.png")
box.save(out)
print(out, box.size)
