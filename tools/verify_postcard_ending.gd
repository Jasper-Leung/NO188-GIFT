extends SceneTree
## verify_postcard_ending.gd — 明信片纸面分级 + 终局二选一 回归
##
## 整合方案 §5.3 把明信片分成三层，只有第一层是买的。这个脚本验「买的那层」
## 和「选的那层」，中间「挣的那层」（五块碎片 → _variant）只验它没被档位带偏：
##   1. 纸面档位：0/1/2/3 各自的纸色、外框、帘纹、墨色
##   2. 越界档位：postcard_tier 被写成 99 或 -5 都要夹住，不能踩出调色板
##   3. 散件：宣纸 / 松烟墨 / 蜡封 / 信封 各管各的那一笔，且互不覆盖
##   4. 终局二选一：覆盖层压在明信片揭示之前；keep 把那句写上背面、
##      break 让背面留白并把封口的蜡掰开——抉择必须落在正面（导出那张 PNG）上，
##      不只是"多一句可改的预填"；点描述文字也算命中
##   5. 未竟：碎片不齐直接出明信片，背面留白
##   6. EndCard 管线：显示用的 Postcard 与导出用的 PostcardExport 拿到同一套纸面
##
## 颜色与档位名一律从 Postcard.gd 和 Localization 自己取（get_script_constant_map()
## + Localization.t()），不硬编码：改调色板或改文案不会把这条回归弄红。
## 购买链路（价格、碎片门槛、幂等扣账）已由 verify_economy.gd /
## verify_shop_world.gd 覆盖，所以这里直接摆 GameManager.inv，
## 只测「摆好之后画成什么样」。
##
## 像素级观感要带窗口看，见 tools/lookdev_postcard.gd。
##
## 用法： godot --headless --path . --script tools/verify_postcard_ending.gd

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _pc_script: GDScript = null
var _frag_idx: Array = []


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_ck(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _ensure_autoloads() -> void:
	var paths := {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}
	for n in paths:
		if root.get_node_or_null(n) == null:
			var node: Node = load(paths[n]).new()
			node.name = n
			root.add_child(node)


## 从 Postcard.gd 的常量表取调色板，别在测试里再抄一份颜色值。
func _pc(name: String) -> Variant:
	return _pc_script.get_script_constant_map().get(name, "<<missing: %s>>" % name)


## 摆背包再实例化一张明信片。tier <= 0 表示没买套餐。
func _make_postcard(tier: int, extras: Array) -> Control:
	_gm.reset()
	_gm.inv.clear()
	if tier > 0:
		_gm.inv["postcard_tier"] = tier
	for id in extras:
		_gm.inv[id] = 1
	var pc: Control = _pc_script.new()
	pc.name = "PC"
	pc.size = Vector2(900, 506)
	root.add_child(pc)
	await process_frame
	return pc


## 让 5 个碎片驿站都记 1 次打卡，使 _needs_choice() 成立。
func _collect_all() -> void:
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 1


## 摆 EndCard 并等两帧（_ready() 里有 tween，一帧不够）。
func _make_endcard() -> Control:
	var card: Control = load("res://scenes/EndCard.tscn").instantiate()
	root.add_child(card)
	await process_frame
	await process_frame
	return card


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
		await process_frame


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_loc.set_language("zh")
	_pc_script = load("res://scripts/Postcard.gd")
	_frag_idx = load("res://scripts/road_data.gd").get_script_constant_map().get(
		"FRAGMENT_SLOT_STATION_IDX", [])
	_gm.reset()
	_run.call_deferred()


func _run() -> void:
	print("=== 明信片纸面分级 + 终局二选一 ===")
	_ck("取到 5 个碎片驿站索引", _frag_idx.size() == 5, "got %d" % _frag_idx.size())

	# 每个 audit 都是协程（内部 await 帧），必须逐条 await，
	# 否则 _run() 跑完第一行就抢跑到汇总，全部断言变成"跑在 quit 之后"。
	await _audit_tiers()
	await _audit_extras()
	await _audit_variant_independent()
	await _audit_ending_choice()
	await _audit_ending_restored()
	await _audit_unfinished()
	await _audit_endcard_pipeline()
	await _audit_run_recap()

	_gm._clear_save()
	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)


func _audit_tiers() -> void:
	print("\n---------- 1. 纸面档位 ----------")
	var p0 = await _make_postcard(0, [])
	_eq("tier 0: _tier", p0._tier, 0)
	_eq("tier 0: 纸色", p0._paper, _pc("LAND_COL"))
	_eq("tier 0: 墨色", p0._ink, _pc("INK_COL"))
	_eq("tier 0: 外框色", p0._frame_col, _pc("FRAME_PLAIN"))
	_eq("tier 0: 外框宽", p0._frame_w, 4.0)
	_eq("tier 0: 无帘纹", p0._laid_lines, false)
	_eq("tier 0: 不打纸名", p0.tier_name(), "")
	var col0 = p0._paper
	await _free(p0)

	var p1 = await _make_postcard(1, [])
	_eq("tier 1: _tier", p1._tier, 1)
	_eq("tier 1: 素笺有自己的纸色", p1._paper, _pc("PAPER_PLAIN"))
	# 素笺必须和「没买套餐」分得开：买了张素笺却渲染成同一张纸，
	# 玩家根本看不出自己花了钱。
	_eq("tier 1 与 tier 0 纸色不同", p1._paper != col0, true)
	_eq("tier 1: 纸名", p1.tier_name(), _loc.t("tier_plain"))
	await _free(p1)

	var p2 = await _make_postcard(2, [])
	_eq("tier 2: _tier", p2._tier, 2)
	_eq("tier 2: 换了纸色", p2._paper, _pc("PAPER_FINE"))
	_eq("tier 2: 上笺有帘纹", p2._laid_lines, true)
	_eq("tier 2: 外框仍是素框", p2._frame_col, _pc("FRAME_PLAIN"))
	_eq("tier 2: 墨色未变", p2._ink, _pc("INK_COL"))
	_eq("tier 2: 纸名", p2.tier_name(), _loc.t("tier_fine"))
	await _free(p2)

	var p3 = await _make_postcard(3, [])
	_eq("tier 3: _tier", p3._tier, 3)
	_eq("tier 3: 换了纸色", p3._paper, _pc("PAPER_RARE"))
	_eq("tier 3: 金描边", p3._frame_col, _pc("FRAME_GOLD"))
	_eq("tier 3: 外框加宽", p3._frame_w, 6.0)
	_eq("tier 3: 有帘纹", p3._laid_lines, true)
	_eq("tier 3: 纸名", p3.tier_name(), _loc.t("tier_rare"))
	await _free(p3)

	# 存档被写坏 / 玩家手改过 inv 时档位可能是任意值，必须夹住
	var pbig = await _make_postcard(99, [])
	_eq("tier 99 夹到 3", pbig._tier, 3)
	_eq("tier 99 用珍藏纸", pbig._paper, _pc("PAPER_RARE"))
	await _free(pbig)

	var pneg = await _make_postcard(-7, [])
	_eq("tier -7 夹到 0", pneg._tier, 0)
	_eq("tier -7 不打纸名", pneg.tier_name(), "")
	await _free(pneg)


func _audit_extras() -> void:
	print("\n---------- 2. 散件 ----------")

	var pp = await _make_postcard(1, ["paper"])
	_eq("宣纸: 纤维标记", pp._fiber, true)
	_eq("宣纸: 顺带帘纹", pp._laid_lines, true)
	_eq("宣纸: 不改纸色（仍是素笺纸）", pp._paper, _pc("PAPER_PLAIN"))
	await _free(pp)

	var pi = await _make_postcard(1, ["ink"])
	_eq("松烟墨: 换墨色", pi._ink, _pc("INK_PINE"))
	_eq("松烟墨: 不动帘纹", pi._laid_lines, false)
	_eq("松烟墨: 不动纸色", pi._paper, _pc("PAPER_PLAIN"))
	await _free(pi)

	var ps = await _make_postcard(1, ["seal"])
	_eq("蜡封: 封口标记", ps._has_wax, true)
	_eq("蜡封: 不动纸色", ps._paper, _pc("PAPER_PLAIN"))
	await _free(ps)

	var pe = await _make_postcard(1, ["env"])
	_eq("信封: 折角标记", pe._has_env, true)
	_eq("信封: 不动纸色", pe._paper, _pc("PAPER_PLAIN"))
	await _free(pe)

	# 四件散件同时持有，每一件都得生效
	var pall = await _make_postcard(2, ["paper", "ink", "seal", "env"])
	_eq("全购: 纤维", pall._fiber, true)
	_eq("全购: 帘纹", pall._laid_lines, true)
	_eq("全购: 墨色", pall._ink, _pc("INK_PINE"))
	_eq("全购: 蜡封", pall._has_wax, true)
	_eq("全购: 信封", pall._has_env, true)
	_eq("全购: 仍是上笺纸", pall._paper, _pc("PAPER_FINE"))
	await _free(pall)

	# 宣纸的帘纹在素笺档也要生效——散件不该被档位挡掉
	var pplain_fiber = await _make_postcard(0, ["paper"])
	_eq("宣纸在 tier 0 也给帘纹", pplain_fiber._laid_lines, true)
	_eq("tier 0 + 宣纸仍不打纸名", pplain_fiber.tier_name(), "")
	await _free(pplain_fiber)


func _audit_variant_independent() -> void:
	print("\n---------- 3. 碎片档位不被纸面档位带偏 ----------")

	# 3 个碎片驿站各打 1 次 = 朝圣者（_variant 2），与纸面档位无关
	_gm.reset()
	for i in _frag_idx.size():
		if i < 3:
			_gm.collected[_frag_idx[i]] = 1
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 3
	var pc: Control = _pc_script.new()
	pc.name = "PC"
	pc.size = Vector2(900, 506)
	root.add_child(pc)
	await process_frame
	_eq("3 碎片 + 珍藏笺：_variant", pc._variant, 2)
	_eq("3 碎片 + 珍藏笺：_tier", pc._tier, 3)

	# 反过来：没买任何套餐，碎片档位照样算
	await _free(pc)
	_gm.reset()
	_collect_all()
	var pc2: Control = _pc_script.new()
	pc2.name = "PC"
	pc2.size = Vector2(900, 506)
	root.add_child(pc2)
	await process_frame
	_eq("5 碎片 + 无套餐：_variant", pc2._variant, 3)
	_eq("5 碎片 + 无套餐：_tier", pc2._tier, 0)
	await _free(pc2)

	# 五档布局里「占位灰块」与「真碎片」必须严格互斥：
	# 占位 ⇔ slot_idx < 0。历史上完满档第 5 格被误标成占位，玩家集齐五件
	# 却在最后一格看到灰底「?」，正好戳破「五块碎片无价」那层承诺。
	var layouts: Array = _pc("VARIANT_LAYOUTS")
	_eq("布局档位齐全", layouts.size(), 5)
	for li in layouts.size():
		for entry in layouts[li]:
			_ck("布局 %d 第 %s 格 占位标记与槽位一致" % [li, str(entry[0])],
					entry[1] == (entry[0] < 0), "entry=%s" % str(entry))

	await _audit_panel_identity()


## 画区那一格的「颜色 / 图标 / 标签」必须讲同一件碎片。
## 历史上颜色表和图标分派各整体错位一格而标签是对的：五格里错四格，
## 而两张错位的表彼此自洽，缩略图一眼扫过去完全正常——可玩家存走的那张
## PNG 就是这张错位图。颜色已改成 FRAGMENT_COLS[slot_idx] 按下标查，
## 下面这三条把「三处同序」钉死：调色板不许分叉、五个名字不许重名、
## 完满档五格必须一次覆盖五件。
func _audit_panel_identity() -> void:
	print("\n---------- 3b. 画区颜色/图标/标签同序 ----------")
	var cols: Array = _pc("FRAGMENT_COLS")
	_eq("FRAGMENT_COLS 是五件", cols.size(), 5)

	# 顶栏碎片栏那份同名常量表是玩家最先认下的配色，两处不许分叉
	var fb = load("res://scripts/FragmentBar.gd")
	_ck("与 FragmentBar.FRAGMENT_COLORS 逐件一致",
			str(cols) == str(fb.FRAGMENT_COLORS),
			"postcard=%s bar=%s" % [str(cols), str(fb.FRAGMENT_COLORS)])

	# 五个格子写着五个字。两个 key 若指到同一句，上面那条同序就失去意义，
	# 而「云字下面配一只鸟」在图上仍然是自洽的，只能靠这里拦。
	var uniq := {}
	for i in 5:
		uniq[_loc.t("fragment_%d" % i)] = true
	_eq("五件碎片的名字互不相同", uniq.size(), 5)

	# 完满档五格全真，逐一确认它引用的正是 0..4 —— 布局表最容易出的错就是
	# 少一格或重一格，五个真格如果只是四个下标加一个重复，图标就会重影。
	var layout: Array = _pc_script.VARIANT_LAYOUTS[4]
	_eq("完满档五格", layout.size(), 5)
	var seen := {}
	for i in layout.size():
		var slot: int = layout[i][0]
		_eq("完满第 %d 格就是第 %d 件" % [i, i], slot, i)
		_eq("完满第 %d 格不是占位" % [i], layout[i][1], false)
		seen[cols[slot].to_html(false)] = true
	_ck("五格颜色恰好覆盖五件碎片", seen.size() == 5, "seen=%s" % str(seen.keys()))


func _audit_ending_choice() -> void:
	print("\n---------- 4. 终局二选一 ----------")
	_gm.reset()
	_collect_all()
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 2

	var card = await _make_endcard()
	_ck("需要抉择", card._needs_choice())
	_ck("覆盖层已建", card._ending_overlay != null)
	_ck("抉择期间明信片藏着", not card._postcard.visible)
	_ck("抉择期间按钮栏藏着", not card.get_node("VBox").visible)

	var ed: Control = card._ending_overlay
	_eq("覆盖层铺满", ed.size, card.size)
	_eq("覆盖层子节点数", ed.get_child_count(), 5)

	# 几何体检：项目在这上面摔过多次（锚点不写、size 与 offset 互踩）
	var i := 0
	for c in ed.get_children():
		var r: Rect2 = c.get_rect()
		var inside := r.position.y >= -0.5 and r.end.y <= ed.size.y + 0.5 \
				and r.end.x <= ed.size.x + 0.5 \
				and r.size.x > 0.0 and r.size.y > 0.0
		_ck("[%d] %s 正尺寸且在界内" % [i, c.get_class()], inside, "rect=%s" % str(r))
		i += 1

	_ck("两张抉择卡都在树里", ed.get_node_or_null("Choice_keep") != null
			and ed.get_node_or_null("Choice_break") != null)
	var keep_card: Control = ed.get_node("Choice_keep")
	var break_card: Control = ed.get_node("Choice_break")

	# 文案齐：标题、提示、两条分支的标题与正文
	# 卡片正文写的就是选完之后真正会发生的事：留门 = 背面就多这一句，
	# 放手 = 背面留白、蜡封掰开、那句话退成占位提示。所以这里比的是
	# back_keep 和 back_break_blank，不是"两个形容"。
	_eq("标题文案", card._choice_title.text, _loc.t("ending_title"))
	_eq("提示文案", card._choice_hint.text, _loc.t("ending_hint"))
	_eq("留门标题", card._choice_keep_title.text, _loc.t("ending_keep"))
	_eq("留门正文 = 背面那一句", card._choice_keep_desc.text, _loc.t("back_keep"))
	_eq("放手标题", card._choice_break_title.text, _loc.t("ending_break"))
	_eq("放手正文说的是留白", card._choice_break_desc.text, _loc.t("back_break_blank"))
	_ck("两条正文说的不是同一件事", card._choice_keep_desc.text != card._choice_break_desc.text)
	_eq("抉择前背面留白", card._back_text, "")
	_eq("抉择前 ending_id 为空", _gm.ending_id, "")

	# 松开 / 右键 / 点空区都不算选择
	_click(keep_card, false, MOUSE_BUTTON_LEFT)
	_eq("松开不算选择", _gm.ending_id, "")
	_click(keep_card, true, MOUSE_BUTTON_RIGHT)
	_eq("右键不算选择", _gm.ending_id, "")

	# 点「守住归途」
	_click(keep_card, true, MOUSE_BUTTON_LEFT)
	_eq("选择后 ending_id", _gm.ending_id, "keep")
	_eq("播种背面文案", card._back_text, _loc.t("back_keep"))
	_eq("背面卡片同步", card._back_postcard.get_back_text(), _loc.t("back_keep"))
	# 抉择必须落在**正面**上，否则玩家的收获就是"多一句可改的预填"。
	# 蜡封是留门/放手之间唯一画在正面的差别，而正面才是导出的那张 PNG。
	_ck("留门：蜡封是完好的", not card._postcard.seal_broken())
	_ck("留门：导出卡片的蜡封也是完好的", not card._postcard_export.seal_broken())
	_eq("覆盖层已清", card._ending_overlay, null)
	_ck("明信片已揭示", card._postcard.visible)
	_ck("按钮栏已揭示", card.get_node("VBox").visible)
	# queue_free 是延迟的，等两帧再验节点真的没了
	await process_frame
	await process_frame
	_ck("覆盖层节点已释放", not is_instance_valid(ed))
	_ck("抉择卡节点已释放", not is_instance_valid(keep_card))

	# 已选过就不能再弹
	_eq("选过后不再要求抉择", card._needs_choice(), false)

	# 背面编辑器拿到的应该是那句定稿，不是空框 + 占位提示
	card._show_back_editor()
	await process_frame
	_eq("编辑器预填默认文案", card._back_text_edit.text, _loc.t("back_keep"))

	# 写字时的卡片缩略图：这一屏原本是「空框 + 两个按钮」，玩家不知道字会印成什么样。
	# 缩略图抓的是导出同一个 SubViewport 的纹理，所以要拦的是"改了字、卡片没跟着改"
	# —— set_back_text() 原来只在确认时才调，整个写字过程里预览一直停在选完那句。
	_ck("编辑器里有卡片缩略图", card._back_thumb != null
			and is_instance_valid(card._back_thumb))
	_ck("缩略图不拦截点击", card._back_thumb.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_ck("缩略图有说明文字", card._back_thumb_caption != null
			and card._back_thumb_caption.text == _loc.t("back_preview_caption"))
	# 缩略图不能压到两个按钮上、也不能出屏。两处都拿真视口尺寸比：
	# 这一屏的布局全按 get_viewport_rect().size 算，写死 720 会在别的分辨率下
	# 拿一个不存在的屏高去判（headless 这里的视口就不是 720 高）。
	var vh: float = card.get_viewport_rect().size.y
	var skip_bottom: float = vh * float(card.THUMB_BTN_Y_FRAC) + float(card.THUMB_BTN_H)
	_ck("缩略图不遮按钮", card._back_thumb.offset_top > skip_bottom,
			"上沿 %.0f，按钮下沿 %.0f" % [card._back_thumb.offset_top, skip_bottom])
	_ck("两个按钮不叠在一起（叠着就各吃一行，预览的份额又少一截）",
			absf(card._back_skip_btn.offset_left - card._back_confirm_btn.offset_left)
					>= card._back_confirm_btn.offset_right
					- card._back_confirm_btn.offset_left - 1.0,
			"确认 %.0f~%.0f，跳过 %.0f~%.0f" % [
				card._back_confirm_btn.offset_left, card._back_confirm_btn.offset_right,
				card._back_skip_btn.offset_left, card._back_skip_btn.offset_right])
	_ck("两个按钮都在屏内",
			card._back_confirm_btn.offset_right <= card.get_viewport_rect().size.x
			and card._back_skip_btn.offset_right <= card.get_viewport_rect().size.x,
			"确认右沿 %.0f，跳过右沿 %.0f" % [card._back_confirm_btn.offset_right,
			card._back_skip_btn.offset_right])
	_ck("缩略图不出屏", card._back_thumb.offset_bottom <= vh,
			"底沿 %.0f，屏高 %.0f" % [card._back_thumb.offset_bottom, vh])
	_ck("说明行也没出屏", card._back_thumb_caption.offset_top >= 0.0
			and card._back_thumb_caption.offset_bottom <= card._back_thumb.offset_top,
			"caption %.0f~%.0f, thumb %.0f" % [card._back_thumb_caption.offset_top,
			card._back_thumb_caption.offset_bottom, card._back_thumb.offset_top])
	# 预览的意义全在"字看得清"。原来固定 200px 宽 —— 卡片在 SubViewport 里按原
	# 尺寸画完再缩下来，200px 宽的预览里一行字只剩七来个像素高，放大三倍也读不
	# 出是哪个字，"所见即导出"就成了一句空话。要 400 以上才认得出自己写的那句。
	# 判的是宽度下限：`_add_back_thumb` 先按屏宽算一遍（上限 460），再按"按钮
	# 下沿到屏底"的空当算一遍高度，取小的。headless 的视口比 720p 高，高度那道
	# 约束在这里不生效，所以量到的就是屏宽那一档 —— 正好是个下界。
	# 比 720p 更矮的屏上预览会等比缩下去，那是有意的降级，不在这里拦。
	var tw: float = card._back_thumb.offset_right - card._back_thumb.offset_left
	_ck("预览至少有 400px 宽（原来只有 200，字读不出来）", tw >= 400.0,
			"%.0fpx @ 视口 %dx%d" % [tw, int(card.get_viewport_rect().size.x), int(vh)])

	# 手动发信号：程序化赋 .text 不发 text_changed（_on_back_confirmed 里也是因此
	# 才回头再读一次 TextEdit）。这里要的就是"玩家敲了一个键"那一刻发生的事。
	card._back_text_edit.text = "改过的字"
	card._back_text_edit.text_changed.emit()
	await process_frame
	_eq("打字立刻同步到背面卡片", card._back_postcard.get_back_text(), "改过的字")
	_eq("打字写进 _back_text", card._back_text, "改过的字")
	_ck("打字把缩略图置脏", card._back_thumb_dirty)
	# 节流是按累计 delta 掐的（THUMB_REFRESH_SEC = 0.12s），headless 下 process_frame
	# 的 delta 只有一两毫秒，跑两帧等不到阈值——必须等墙钟。
	await create_timer(0.25).timeout
	await process_frame
	_ck("缩略图已刷新回干净状态", not card._back_thumb_dirty)
	await _free(card)


func _click(card: Control, pressed: bool, button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.pressed = pressed
	ev.button_index = button
	# gui_input 的连接是带 bind(ending) 的，所以这里只发事件本身，
	# 分支参数由 connect 时绑的 ending 补齐
	card.gui_input.emit(ev)


func _audit_ending_restored() -> void:
	print("\n---------- 5. 存档恢复已选结局 ----------")
	# 读档后 ending_id 已经在，不该再弹一次二选一
	_gm.reset()
	_collect_all()
	_gm.set_ending("break")
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 3

	var card = await _make_endcard()
	_eq("已选过：不需要抉择", card._needs_choice(), false)
	_eq("已选过：没有覆盖层", card._ending_overlay, null)
	_ck("已选过：明信片直接出", card._postcard.visible)
	_ck("已选过：按钮栏直接出", card.get_node("VBox").visible)
	_eq("已选过（放手）：背面留白", card._back_text, "")
	_eq("已选过（放手）：背面卡片也留白", card._back_postcard.get_back_text(), "")
	_ck("已选过（放手）：蜡封是掰开的", card._postcard.seal_broken())
	# 那句话没有消失，只是退成了灰色占位提示——摆在那儿，拿不拿随玩家。
	card._show_back_editor()
	await process_frame
	_eq("放手时占位提示是那句没写上去的话",
			card._back_text_edit.placeholder_text, _loc.t("back_break"))
	_eq("放手时输入框仍然是空的", card._back_text_edit.text, "")
	await _free(card)


func _audit_unfinished() -> void:
	print("\n---------- 6. 未竟（碎片不齐） ----------")
	# 只到 4 块碎片就走 K188：不弹二选一，直接出一张正面缺格、背面空白的明信片。
	# 这是 §2.2「no failure state」在结局层的兑现——礼物仍然成立。
	_gm.reset()
	for i in _frag_idx.size():
		if i < 4:
			_gm.collected[_frag_idx[i]] = 1
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 1

	var card = await _make_endcard()
	_eq("未竟：不弹二选一", card._needs_choice(), false)
	_eq("未竟：没有覆盖层", card._ending_overlay, null)
	_ck("未竟：明信片照样出", card._postcard.visible)
	_eq("未竟：背面留白", card._back_text, "")
	_eq("未竟：背面卡片留白", card._back_postcard.get_back_text(), "")
	_eq("未竟：ending_id 保持空", _gm.ending_id, "")
	# 正面缺格：4 个碎片 → 大师（_variant 3）
	_eq("未竟：正面按碎片数出格", card._postcard._variant, 3)
	await _free(card)


func _audit_endcard_pipeline() -> void:
	print("\n---------- 7. 显示与导出拿同一套纸面 ----------")
	_gm.reset()
	_collect_all()
	_gm.inv.clear()
	_gm.inv["postcard_tier"] = 3
	for id in ["paper", "ink", "seal", "env"]:
		_gm.inv[id] = 1

	var card = await _make_endcard()
	# 抉择走完，两边才算真正的产出状态
	_click(card._ending_overlay.get_node("Choice_break"), true, MOUSE_BUTTON_LEFT)
	await process_frame
	await process_frame

	_eq("显示卡片 tier", card._postcard._tier, 3)
	_eq("导出卡片 tier", card._postcard_export._tier, 3)
	_eq("显示卡片纸色", card._postcard._paper, _pc("PAPER_RARE"))
	_eq("导出卡片纸色", card._postcard_export._paper, _pc("PAPER_RARE"))
	_eq("显示卡片金边", card._postcard._frame_col, _pc("FRAME_GOLD"))
	_eq("导出卡片金边", card._postcard_export._frame_col, _pc("FRAME_GOLD"))
	_eq("导出卡片松烟墨", card._postcard_export._ink, _pc("INK_PINE"))
	_eq("导出卡片蜡封", card._postcard_export._has_wax, true)
	_eq("导出卡片信封", card._postcard_export._has_env, true)
	_eq("导出卡片帘纹", card._postcard_export._laid_lines, true)
	_eq("导出卡片纸名", card._postcard_export.tier_name(), _loc.t("tier_rare"))
	# 抉择的痕迹必须一起进导出：显示的正面和导出的正面要是两回事，
	# 玩家看到的是掰开的蜡、拿到的 PNG 却是一枚完好的，那就成了渲染事故。
	_ck("放手：显示卡片蜡封掰开", card._postcard.seal_broken())
	_ck("放手：导出卡片蜡封也掰开", card._postcard_export.seal_broken())
	await _free(card)


## 走完整一趟之后按「重新开始」，弹出来的是这一趟真实漏掉的东西。
##
## 拦的是两种失败：**编**（说了玩家没做过的事，第二趟发现根本没有，比不弹
## 更伤）和**漏**（明明漏了却不说，回执变成一句客套）。所以每一条都对着
## 摆出来的存档逐字核对：报到几个驿、哪几块碎片没拿、哪几件没赢过。
func _audit_run_recap() -> void:
	print("\n---------- 8. 重新开始前的「这一趟」回执 ----------")
	var rd = load("res://scripts/road_data.gd").new()
	var total_stations: int = rd.stations.size()

	# 空存档：连一块碎片都没有，press restart 不该弹回执（nothing to recap）
	_gm.reset()
	var fresh = await _make_endcard()
	_eq("空存档：不弹回执", fresh._recap_worth_showing(), false)
	await _free(fresh)

	# 摆一趟"只骑了一半"的真实存档
	_gm.reset()
	var seen := [0, 1, 4, 7, 10]          # 5 座驿站，其中 4/7/10 是碎片站
	for i in seen:
		_gm.seen_stations[i] = true
	for st_idx in [_frag_idx[0], _frag_idx[1]]:
		_gm.collected[st_idx] = 1
	_gm.earned_tags["mini_%d_win" % _frag_idx[0]] = true
	_gm.earned_tags["mini_%d_lose" % _frag_idx[1]] = true
	_gm.lvbi = 40
	_gm.inv.clear()

	var card = await _make_endcard()
	_eq("半途：弹回执", card._recap_worth_showing(), true)

	var lines: Array = card._recap_lines()
	var joined := "\n".join(lines)
	print("    回执：\n      " + joined.replace("\n", "\n      "))

	# 没拿到的碎片：3 块，按碎片顺序点名，一个不多一个不少。
	# 拿渲染后的整句去比，不要拿 key 里的 "%s" 去 contains —— 那永远匹配不上。
	var missing: Array = []
	for st_idx in _frag_idx:
		if not _gm.is_collected(st_idx):
			missing.append(rd.station_display_fragment(st_idx))
	_eq("点出漏掉的碎片数", missing.size(), 3)
	_ck("漏碎片那一行逐字对得上",
			lines.has(_loc.t("recap_frag_missing") % _join(missing)),
			"lines=" + str(lines))

	# 驿数按实际 seen_stations 报，不按「游戏跑了多久」编
	_ck("驿数按存档报 5/%d" % total_stations,
			lines.has(_loc.t("recap_seen") % [seen.size(), total_stations]), str(lines))

	# 没赢过的：只赢了 _frag_idx[0]，另外四个都要被点名
	var lost: Array = []
	for st_idx in _frag_idx:
		if not _gm.earned_tags.has("mini_%d_win" % st_idx):
			lost.append(rd.station_display_fragment(st_idx))
	_eq("点出没赢过的件数", lost.size(), 4)
	_ck("没赢过的那一行逐字对得上",
			lines.has(_loc.t("recap_mini_lost") % _join(lost)), str(lines))
	_ck("赢了一件就报一件", lines.has(_loc.t("recap_mini") % [1]))
	# 没读到的风景话只点前三个，第四个不硬凑
	var all_unread: Array = []
	for i in total_stations:
		if not _gm.seen_stations.has(i):
			all_unread.append(rd.station_display_name(i))
	_ck("没读到的话点前三个", lines.has(_loc.t("recap_unread") % _join(all_unread.slice(0, 3))),
			str(lines))
	_ck("只点三个，不把剩下的也塞进去",
			not str(lines).contains(all_unread[3]))

	# 没选过结局就不提「另一边还空着」——没选过的事不能说
	_eq("没选过结局", _gm.ending_id, "")
	_ck("没选结局：不提另一边还空着", not joined.contains(_loc.t("ending_keep"))
			and not joined.contains(_loc.t("ending_break")))
	# 余额 40 > 0 才报没花完
	_ck("余额 40：报没花完", lines.has(_loc.t("recap_lvbi") % 40))
	# 正面只有 2 块碎片 → 探索者(1)，不是大师(3)，所以不该出现第五格那行
	_ck("评级没到大师：不提第五格问号", not joined.contains(_loc.t("postcard_variant_hint")))

	# 选过之后那一行必须出现，而且必须是他选的那一边
	_gm.set_ending("break")
	_ck("选了放手：报「另一边还空着」", card._recap_lines().has(
			_loc.t("recap_ending") % _loc.t("ending_break")))
	_ck("选了放手：不提留门", not str(card._recap_lines()).contains(_loc.t("ending_keep")))
	# 大师档（5 块碎片、没有一站到 3 次）才提示第五格
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 1
	_ck("大师档：提示第五格", card._recap_lines().has(_loc.t("postcard_variant_hint")))
	# 完满判据是 all_fragments_maxed()，不是"任意一站到访 3 次"。
	# 原来这里只把 [0] 摆到 3 就期望进完满档——那正是把旧那个 bug 当成规格写进了
	# 测试：玩家只把云影台刷满三次、另外四站只去过一次，正面就已经是"完满"，
	# 而导航还在指另外四站。现在只刷满一站仍是大师，五站全满才是完满。
	_gm.collected[_frag_idx[0]] = _gm.MAX_VISITS_PER_STATION
	_ck("只刷满一站：仍是大师，仍提示第五格", card._recap_lines().has(
			_loc.t("postcard_variant_hint")))
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = _gm.MAX_VISITS_PER_STATION
	_ck("完满档：不再提第五格", not card._recap_lines().has(
			_loc.t("postcard_variant_hint")))
	# 摆回半途基线：只有前两块碎片收过、没选结局。
	# 这里必须把五块全摆回去而不是只摆 [0]——上面那两行把其余三块也填上了，
	# 只还原 [0] 的话后面量到的碎片数是 5，「回执正文 == 开头那份 lines」也对不上。
	_gm.collected[_frag_idx[0]] = 1
	_gm.collected[_frag_idx[2]] = 0
	_gm.collected[_frag_idx[3]] = 0
	_gm.collected[_frag_idx[4]] = 0
	_gm.set_ending("")
	_eq("基线还原：碎片 2 块", _gm.get_collected_count(), 2)

	# 覆盖层：按重新开始弹出来、两个按钮都在、留下不重置
	card._on_restart_pressed()
	await process_frame
	_ck("按重新开始弹出回执", card._recap_overlay != null)
	if card._recap_overlay != null:
		_ck("回执标题是那句", card._recap_title.text == _loc.t("recap_title"))
		_ck("回执正文就是那些行", card._recap_body.text == joined,
				"got=" + card._recap_body.text)
		_ck("「再骑一趟」在", card._recap_again_btn != null
				and card._recap_again_btn.text == _loc.t("recap_again"))
		_ck("「留下这张卡」在", card._recap_stay_btn != null
				and card._recap_stay_btn.text == _loc.t("recap_stay"))
		card._on_recap_stay_pressed()
		await process_frame
		_eq("留下：回执收走", card._recap_overlay, null)
		_eq("留下：不重置存档", _gm.seen_stations.size(), seen.size())
		_eq("留下：碎片还在", _gm.get_collected_count(), 2)

	# 切语言：行数不变、每行都换过、且没有裸 key 漏出来
	var zh_lines: Array = card._recap_lines()
	_loc.set_language("en")
	var en_lines: Array = card._recap_lines()
	_eq("切语言后行数不变", en_lines.size(), zh_lines.size())
	_ck("切语言后每行都变了", _all_differ(en_lines, zh_lines))
	_ck("英文里没有漏掉的 key", not str(en_lines).contains("recap_"))
	_loc.set_language("zh")

	# 走到头：16 座全路过、5 件全赢、某一站到过 3 次（完满）、旅币花光 ——
	# 剩的仍然有而且必须有一样：另一边的结局没走过。keep/break 一次只选一个，
	# 存档又随重开清零，所以这一行永远不会消失，回执也就永远有事可说。
	# 要是哪天把它写成「全都走到了」，那才是真的在骗玩家。
	_gm.reset()
	for i in total_stations:
		_gm.seen_stations[i] = true
	for st_idx in _frag_idx:
		_gm.collected[st_idx] = 3
		_gm.earned_tags["mini_%d_win" % st_idx] = true
	_gm.set_ending("keep")
	_gm.lvbi = 0
	var full: Array = card._recap_lines()
	_eq("走到头：正文只剩一行", full.size(), 1)
	_eq("走到头：剩的就是另一边", full, [_loc.t("recap_ending") % _loc.t("ending_keep")])
	_ck("走到头：不再报驿数", not str(full).contains(_loc.t("recap_seen") % [16, 16]))
	_ck("走到头：不再报没赢过", not str(full).contains(_loc.t("recap_mini_lost")))
	_ck("走到头：不报没花完", not str(full).contains(_loc.t("recap_lvbi")))
	await _free(card)


## 接名字列表。分隔符要跟 EndCard._join_names 一致，所以调它而不是自己写死。
func _join(names: Array) -> String:
	return (", " if _loc.is_english() else "、").join(names)


func _all_differ(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] == b[i]:
			return false
	return true
