#!/usr/bin/env bash
# check_all.sh — 一条命令跑完所有无头回归，打印一张给评审看的表。
#
# 为什么要它：这个工程有 30+ 条回归，可它们散在 CLAUDE.md 的命令清单里，
# 评委不会去翻。这一条把"工程靠不靠得住"变成**一次运行、一张表**。
#
#   bash tools/check_all.sh            # 全部无头回归
#   GODOT=/path/to/godot bash tools/check_all.sh
#   bash tools/check_all.sh verify_water verify_story    # 只跑指定的几条
#   bash tools/check_all.sh --window   # 要开窗口的那几条（焦点路由）
#   bash tools/check_all.sh --lookdev  # 出图看观感（同样要开窗口）
#
# ---- 只跑无头的那些，另外几条要开窗口 ----
# `verify_panel_keyboard` / `verify_checkin_all5` / `verify_mini_game_keys` /
# `verify_bamboo_done` 依赖**真焦点路由**：`--headless` 用的是 dummy display
# server，不做焦点路由，键盘事件到不了 `_gui_input`，跑出来的 PASS 是假的。
# `verify_bamboo_world` 靠 `--quit-after` 掐进程，退出码恒为 0。
# 这几条不列进默认那一轮，是因为**列进来等于告诉他们跑过了**——而没跑的条目必须
# 在输出里明写"没跑"并给出跑法，不能靠沉默。
#
# ---- 判据不信退出码 ----
# 一条回归自己抛异常时，`--quit-after` 收掉进程的退出码是 **0**，一行断言都没打过的
# 回归看着像跑通了。所以这里看两件事：输出里有没有 `[FAIL]`，以及**有没有打出断言**。
# 一条断言都没打印的单独算 TIMEOUT/NO-ASSERT，不许算 PASS。
set -u

GODOT="${GODOT:-D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe}"
TIMEOUT_S="${TIMEOUT_S:-240}"

# 要开窗口才准的那些（理由见文件头）。
# `verify_camera_bike` 也在这一栏：它量的是**真机 16:9 视口**下的车身上投影，
# 而 `--headless` 的 dummy display server 给的是 1280×1280 的方视口，
# 竖直方向多出来的 560px 会让所有投影数失真（脚本里有一条断言正是在量这件事，
# headless 下它会红给你看——所以这一条不能放进默认轮次里充数）。
# `verify_demo_path` 同理：它自己的文件头就写着"约 90 秒，不能加 --headless"，
# 演示走 `Input.parse_input_event`，无头下对白收不到按键、驾驶员一路顶到墙上，
# 量出来的"演示能跑完"是假的。第一版把它留在默认轮次里，于是它每次都报一条红——
# 那条红是真的（它确实没跑成），只是根因不在被测的代码上。
NEEDS_WINDOW="verify_bamboo_done verify_bamboo_world verify_camera_bike verify_checkin_all5 verify_demo_path verify_mini_game_keys verify_panel_keyboard"

# 少数几条要额外命令行参数。`verify_layout_editor` 断的是"编辑模式的开关认不认
# `--gift-editor`"，不带这个参数跑它，那条断言量的是一个根本没发生过的前提。
extra_args() {
	case "$1" in
		verify_layout_editor) echo "--gift-editor" ;;
		*) echo "" ;;
	esac
}

mode="headless"
LIST=""
case "${1:-}" in
	--window) mode="window"; shift; LIST="$NEEDS_WINDOW" ;;
	--lookdev) mode="lookdev"; shift ;;
esac
if [ -z "$LIST" ] && [ $# -gt 0 ]; then
	LIST="$*"
elif [ -z "$LIST" ]; then
	LIST=""
	for s in $(cd "$(dirname "$0")" && ls verify_*.gd | sed 's/\.gd$//'); do
		case " $NEEDS_WINDOW " in
			*" $s "*) ;;
			*) LIST="$LIST $s" ;;
		esac
	done
fi

if [ "$mode" = "lookdev" ]; then
	# 出图这一族不能加 --headless 也不能加 --quit-after：dummy renderer 不编译
	# 着色器、`_draw()` 一笔都不落盘，而这两族的断言全是像素的。
	echo "=== 出图（要开窗口；--headless 渲不出东西）==="
	for f in tools/lookdev_*.gd; do
		n=$(basename "$f" .gd)
		echo "--- $n ---"
		timeout 600 "$GODOT" --path . --script "$f" 2>&1 | grep -E '^\[(OK|FAIL)|^\[lookdev' || true
	done
	exit 0
fi

if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "找不到 Godot：$GODOT"
	echo "用 GODOT=/path/to/godot 覆盖，或照 CLAUDE.md 里的路径别名改这一行。"
	exit 2
fi

echo "=== ${mode} 回归 ==="
pass=0; fail=0; empty=0; skipped=0; tot_ok=0; tot_bad=0
t_start=$(date +%s)

# ---- 护住 res://layout.json（编辑模式 Ctrl+S 的产物）----
#
# 这个文件不是测试数据，是**玩家之外的另一个作者**（关卡编辑）攒下来的东西，
# 而游戏启动时真的会读它（`World3D._setup_stations()` / `VegBuilder.setup()`）。
# 第一版 `verify_layout_editor` 直接往上面写自己的样例数据、最后 `LayoutData.clear()`：
# 一次回归就把编辑模式的成果抹掉，而它自己一个断言都不打，跑起来悄无声息。
# 脚本内部现在自己做备份/还原，但**脚本中途抛异常就还原不了** —— 所以外层再兜一层：
# 整轮跑之前存一份，跑完原样写回去；本来没有就还它没有。
#
# 这不是洁癖：一份被样例数据污染的 layout.json 会把两座驿站摆到相隔 3m，
# 于是路过一次发两份旅币、"到过 N 驿"的计数一次涨 2 —— 而 `verify_shop_world`
# 报的正是这两条红，根因却完全不在它测的那段代码上。
LAYOUT_BACKUP=""
had_layout=0
if [ -f layout.json ]; then
	had_layout=1
	LAYOUT_BACKUP="$(mktemp)"
	cp layout.json "$LAYOUT_BACKUP"
	echo "（发现已有 layout.json，已护住，跑完原样还回）"
fi

for s in $LIST; do
	f="tools/$s.gd"
	if [ ! -f "$f" ]; then
		echo "没有这条回归：$s" >&2
		exit 2
	fi
	t0=$(date +%s)
	ex=$(extra_args "$s")
	if [ "$mode" = "window" ]; then
		out=$(timeout "$TIMEOUT_S" "$GODOT" --path . --script "$f" $ex 2>&1)
	else
		out=$(timeout "$TIMEOUT_S" "$GODOT" --headless --path . --script "$f" $ex 2>&1)
	fi
	rc=$?
	t1=$(date +%s)
	dt=$((t1 - t0))

	ok=$(printf '%s' "$out" | grep -c '^\[OK\]' || true)
	bad=$(printf '%s' "$out" | grep -c '^\[FAIL\]' || true)
	tot_ok=$((tot_ok + ok)); tot_bad=$((tot_bad + bad))

	if [ "$bad" -gt 0 ]; then
		verdict="FAIL"; fail=$((fail + 1))
	elif [ "$ok" -eq 0 ] && [ "$bad" -eq 0 ]; then
		# 一条断言都没打出来 = 没跑成。退出码在这时候是 0，所以必须单独判。
		if [ $rc -eq 124 ]; then verdict="TIMEOUT"; else verdict="NO-ASSERT"; fi
		empty=$((empty + 1))
	elif [ $rc -ne 0 ]; then
		verdict="FAIL(rc=$rc)"; fail=$((fail + 1))
	else
		verdict="PASS"; pass=$((pass + 1))
	fi

	printf '  %-28s %-12s %5ds  %3d ok / %d fail\n' "$s" "$verdict" "$dt" "$ok" "$bad"
	if [ "$verdict" != "PASS" ]; then
		printf '%s\n' "$out" | grep -E '^\[FAIL\]' | sed 's/^/      /'
	fi
done

if [ "$mode" = "headless" ]; then
	for s in $NEEDS_WINDOW; do
		case " $LIST " in
			*" $s "*) continue ;;
		esac
		skipped=$((skipped + 1))
	done
fi

t_end=$(date +%s)

# ---- 还回 layout.json ----
if [ "$had_layout" = "1" ]; then
	cp "$LAYOUT_BACKUP" layout.json
	rm -f "$LAYOUT_BACKUP"
	echo "（layout.json 已原样还回）"
elif [ -f layout.json ]; then
	# 本来没有，跑完却多出来了：那就是某条回归把测试数据留在产品文件里。
	# 留着它会污染**每一次**后续运行，所以直接清掉并说一声。
	rm -f layout.json
	echo "[check_all] 某条回归往 res://layout.json 里留了测试数据，已清掉（它不是产品输入）"
fi

echo
echo "=== 自检摘要 ==="
printf '  跑过 %d 条：PASS %d / FAIL %d / 没跑成 %d\n' \
	"$((pass + fail + empty))" "$pass" "$fail" "$empty"
	printf '  断言 %d 条，其中 %d 条红\n' "$tot_ok" "$tot_bad"
if [ "$mode" = "headless" ]; then
	printf '  没跑（要开窗口，--headless 跑出来的 PASS 是假的）：%d 条\n' "$skipped"
	printf '    → bash tools/check_all.sh --window\n'
fi
printf '  用时 %ds\n' "$((t_end - t_start))"
echo
echo "  完整陷阱清单与「改什么先跑哪条」：CLAUDE.md"
echo "  要开窗口的那几条：      bash tools/check_all.sh --window"
echo "  出图看观感：            bash tools/check_all.sh --lookdev"

if [ "$fail" -gt 0 ] || [ "$empty" -gt 0 ]; then
	echo
	echo "[check_all] FAIL"
	exit 1
fi
echo
echo "[check_all] PASS"