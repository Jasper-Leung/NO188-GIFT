# 定妆照

`tools/lookdev_journey.gd` 的真产物，不是手工摆的 mock。
重新生成：

```bash
"$GODOT" --path . --script tools/lookdev_journey.gd
# 输出在 user://lookdev_journey/，本目录是从那里拷过来的
```

**不能加 `--headless`、不能加 `--quit-after`** —— dummy renderer 不编译着色器，
也不做焦点路由，拍出来的图和玩家看见的不是一回事。
这条脚本自带 21 条断言（画面非纯色、提示圈还在、回访三处同数、
预览里有墨…),所以它同时是一条回归。

| 文件 | 这一屏在验什么 |
|---|---|
| `01_title.png` | 标题页（礼物盒要画在自己身上，别指望子节点待在它下面） |
| `02_ride.png` | 骑行 + 8 字交叉 + 到站机位车在画面里且够大 |
| `03_pass_station.png` | 路过风景驿那一行浮出来了，且 3.2 秒后自己收走 |
| `04_prompt_贴脸` → `04_prompt_closeup.png` | 贴脸 1.2m 时提示文字不许掉出屏外 |
| `05_revisit.png` | 回访：顶栏与脚下的圈必须说同一个「还差 N 次」 |
| `06_station_dialogue.png` | 驿站对白 |
| `07_shop.png` | 驿铺面板开着 |
| `08_noon.png` / `09_dusk.png` | **同机位 A/B**，少一张就没法判断天到底变了没有 |
| `10_all_collected.png` | 五块碎片合成 |
| `11_ending.png` | 终局二选一 |
| `12_postcard.png` | 明信片正面（玩家真正带走的那张） |

`docs/gameplay.mp4` 是 60 秒实机：真窗口 + Win32 真实按键事件，
从序章对白一路骑到 8 字交叉。录法见 `.review/webtest/record.ps1`（不入库）。
