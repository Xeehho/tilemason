class_name AssetPanel
extends PanelContainer
## 素材浏览器（质感方案 P2 §4.3）：搜索区（搜索框+清除+刷新）→ 筛选区
## （最近/收藏/标签 chip + 分类/分组树）→ 结果区（卡片：缩略图+名称+占格+锚点）
## 像素纪律：缩略图整数倍放大 + 最近邻重采样，hover 只抬层级不放大原图
## 全部节点代码动态创建（.tscn 精简纪律）

signal asset_selected(asset_id: String)
signal rescan_requested ## 刷新素材库（放入文件后点按即扫，无须重启）

const THUMB_BOX := 64 ## 缩略图最大边（px）：16px→4x=64、48px→1x=48，均为整数倍
const CARD_W := 100 ## 素材卡片宽（缩略图 64 + 卡片内边距；HFlow 按此自适应列数）
const PANEL_WIDTH := 320 ## 最小宽=紧凑档右 Dock（§4.2）；列数自适应兜底窄面板，标准档 400 由壳层给足
const TREE_W := 140 ## 分类树最小宽（chip 移出后树只留分类/分组，可收窄让位卡片）

## 分类显示名（design.md §6.1）
const CATEGORY_NAMES := {
	"ground": "地面", "road": "道路", "wall": "墙体", "building": "建筑",
	"tree": "树木", "stall": "摊位", "indoor": "室内", "furniture": "家具", "deco": "装饰",
}

var _library: AssetLibrary
var _category_list: Tree # 分类/分组树（虚拟分类已移至 chip 行）
var _grid: HFlowContainer
var _empty_hint: Label
var _selected: Button # 当前选中卡片
var _buttons := {} # asset_id -> 卡片 Button（当前分类网格内）
var _search_box: LineEdit # 搜索框（过滤当前分类，§6.1 搜索）
var _clear_btn: Button # 清除搜索词（§P2 搜索区）
var _chip_flow: HFlowContainer # 筛选 chip 行（最近/收藏/标签）
var _chips := {} # meta -> chip Button
var _active_chip := "" ## 当前激活的 chip meta（空=按树选中的分类）
var _last_tree_meta := "" ## chip 激活前的树选中项（chip 取消时恢复）
var _recent_ids: Array = [] # 最近使用
var _favorite_ids: Array = [] # 收藏（F 键切换）
var _tag_ids := {} # 标签反向索引 {tag: [asset_id]}（每个 #标签 一条 chip）
var _thumbs := {} # asset_id -> ImageTexture（整数倍缩放后的缩略图）

## 外部指定选中（快捷栏/吸管等入口）：切换到素材所在页并高亮（发 asset_selected）
## 返回是否成功——带 group 的素材（用户导入包）路由到分组叶：分类叶只含无分组素材，
## 旧按分类路由下分组素材永远不进网格，快捷栏点击成为无声空操作（2026-09-23 实测复现）
func select_asset(asset_id: String) -> bool:
	if not _buttons.has(asset_id):
		var asset := _library.get_asset(asset_id)
		if asset.is_empty():
			return false
		var group := str(asset.get("group", ""))
		var meta := ("__group:" + group) if not group.is_empty() else str(asset["category"])
		if not _select_by_meta(_category_list.get_root(), meta):
			return false
		_on_category_selected(meta)
	var btn: Button = _buttons.get(asset_id)
	if btn == null:
		return false
	_on_thumb_pressed(btn, asset_id)
	return true

func setup(library: AssetLibrary) -> void:
	_library = library
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_build_ui()
	_populate_categories()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vbox)

	# —— 搜索区（§4.3）：搜索框 + 清除 + 刷新 ——
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 4)
	vbox.add_child(search_row)
	var search := LineEdit.new()
	search.placeholder_text = "搜索素材…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_t: String) -> void:
		_on_search_changed())
	search_row.add_child(search)
	_search_box = search
	_clear_btn = Button.new()
	_clear_btn.text = "×"
	_clear_btn.tooltip_text = "清除搜索词"
	_clear_btn.custom_minimum_size = Vector2(30, 0)
	_clear_btn.visible = false
	_clear_btn.pressed.connect(func() -> void:
		_search_box.clear()
		_on_search_changed())
	search_row.add_child(_clear_btn)
	var refresh := Button.new()
	refresh.text = "⟳"
	refresh.tooltip_text = "刷新素材库：放入新素材文件后点此立即扫描（也可随时重启）"
	refresh.custom_minimum_size = Vector2(30, 0)
	refresh.pressed.connect(func() -> void: rescan_requested.emit())
	search_row.add_child(refresh)

	# —— 筛选区（§4.3）：最近/收藏/标签 chip 行 ——
	_chip_flow = HFlowContainer.new()
	_chip_flow.add_theme_constant_override("h_separation", 4)
	_chip_flow.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_chip_flow)

	# —— 分类/分组树 + 结果区 ——
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	_category_list = Tree.new()
	_category_list.custom_minimum_size = Vector2(TREE_W, 0)
	_category_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_category_list.hide_root = true
	_category_list.scroll_horizontal_enabled = false
	_category_list.item_selected.connect(_on_tree_selected)
	hbox.add_child(_category_list)

	var sep := VSeparator.new() # 分类与缩略图区的视觉分隔
	hbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)

	_grid = HFlowContainer.new() # 流式布局：按可用宽自动换行（列数自适应且 min 只取单格宽——
	# GridContainer 按列数计 min 会与「列数按面板宽计算」互相卡死，紧凑档收缩不下去，实测踩中）
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)

	_empty_hint = Label.new()
	_empty_hint.text = "此分类暂无素材"
	_empty_hint.modulate.a = 0.6
	_empty_hint.visible = false
	box.add_child(_empty_hint)

func _populate_categories() -> void:
	_rebuild_category_list()
	_rebuild_chips()

## 分类/分组树：group 三层树（外层区域→板块叶）+ 原分类平铺；虚拟分类在 chip 行
func _rebuild_category_list() -> void:
	var selected_meta := _selected_meta()
	_category_list.clear()
	var root := _category_list.create_item()
	var group_roots := {}
	var boards := {}
	for asset in (_library.get_assets() if _library != null else []):
		var a := asset as Dictionary
		var group := str(a.get("group", ""))
		if group.is_empty():
			continue
		var parts := group.split("/", true, 1)
		var outer := parts[0]
		var board := parts[1] if parts.size() > 1 else outer
		if not group_roots.has(outer):
			var item := _category_list.create_item(root)
			item.set_text(0, outer)
			item.set_collapsed(true)
			group_roots[outer] = item
		if not boards.has(group):
			var leaf := _category_list.create_item(group_roots[outer])
			leaf.set_text(0, board)
			leaf.set_metadata(0, "__group:" + group)
			boards[group] = leaf
	# 原分类平铺（无 group 的素材）
	var categories: Array = _library.get_categories() if _library != null else []
	if categories.is_empty() and _recent_ids.is_empty() and _favorite_ids.is_empty() and _tag_ids.is_empty() and group_roots.is_empty():
		_empty_hint.text = "未找到素材包，可将自己的素材包放入 assets/packs/ 目录"
		_empty_hint.visible = true
		return
	for category in categories:
		var all := _library.get_assets_by_category(str(category))
		var plain := 0
		for a in all:
			if str((a as Dictionary).get("group", "")).is_empty():
				plain += 1
		if plain == 0 and not group_roots.is_empty():
			continue
		var label := str(CATEGORY_NAMES.get(str(category), str(category)))
		if plain > 0:
			label += "（%d）" % plain
		_add_leaf(root, label, str(category))
	if selected_meta != "" and _select_by_meta(root, selected_meta):
		return
	var first := root.get_first_child()
	if first != null:
		first.select(0)

## 筛选 chip 行（§P2：最近/收藏/标签改 chip，树只留分类与分组）
func _rebuild_chips() -> void:
	if _chip_flow == null:
		return
	for child in _chip_flow.get_children():
		child.queue_free()
	_chips.clear()
	if not _recent_ids.is_empty():
		_add_chip("最近（%d）" % _recent_ids.size(), "__recent")
	if not _favorite_ids.is_empty():
		_add_chip("★收藏（%d）" % _favorite_ids.size(), "__fav")
	for tag in _tag_ids.keys():
		_add_chip("#%s（%d）" % [str(tag), (_tag_ids[tag] as Array).size()], "__tag:" + str(tag))
	_chip_flow.visible = not _chips.is_empty()
	_refresh_chip_styles()

func _add_chip(label: String, meta: String) -> void:
	var chip := Button.new()
	chip.text = label
	chip.toggle_mode = true
	chip.custom_minimum_size = Vector2(0, 26)
	chip.add_theme_font_size_override("font_size", 12)
	chip.tooltip_text = "筛选：%s（再点一次回到分类树）" % label
	chip.toggled.connect(func(on: bool) -> void: _on_chip_toggled(meta, on))
	_chips[meta] = chip
	_chip_flow.add_child(chip)

## chip 样式：未选=Surface-2 淡底；选中=金色低亮底+暗金边（§P2 选中不再整块金）
func _refresh_chip_styles() -> void:
	for meta in _chips.keys():
		var chip: Button = _chips[meta]
		var sb := StyleBoxFlat.new()
		if str(meta) == _active_chip:
			sb.bg_color = AppTheme.ACCENT_SOFT
			sb.border_color = AppTheme.ACCENT_DIM
			sb.set_border_width_all(1)
			chip.add_theme_color_override("font_color", Color.WHITE)
			chip.add_theme_color_override("font_hover_color", Color.WHITE)
			chip.add_theme_color_override("font_pressed_color", Color.WHITE)
		else:
			sb.bg_color = AppTheme.SURFACE_2
			sb.border_color = Color(1, 1, 1, 0.06)
			sb.set_border_width_all(1)
			chip.remove_theme_color_override("font_color")
			chip.remove_theme_color_override("font_hover_color")
			chip.remove_theme_color_override("font_pressed_color")
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		chip.add_theme_stylebox_override("normal", sb)
		chip.add_theme_stylebox_override("hover", sb)
		chip.add_theme_stylebox_override("pressed", sb)
		chip.set_pressed_no_signal(str(meta) == _active_chip)

## chip 开关：激活→记录并展示该虚拟分类；取消→恢复此前树选中的分类
func _on_chip_toggled(meta: String, on: bool) -> void:
	if on:
		_active_chip = meta
		if _selected_meta() != "":
			_last_tree_meta = _selected_meta()
		if _category_list.get_selected() != null:
			_category_list.get_selected().deselect(0) # 双筛选通道只保留一个（chip 优先）
	else:
		_active_chip = ""
		if _last_tree_meta != "" and _select_by_meta(_category_list.get_root(), _last_tree_meta):
			_on_category_selected(_last_tree_meta)
			_refresh_chip_styles()
			return
		var first := _category_list.get_root()
		if first != null:
			first = first.get_first_child()
		if first != null:
			first.select(0) # 无历史选择则回第一个分类
	_refresh_chip_styles()
	_on_category_selected(meta if on else _selected_meta())

func _add_leaf(parent: TreeItem, label: String, meta: String) -> TreeItem:
	var item := _category_list.create_item(parent)
	item.set_text(0, label)
	item.set_metadata(0, meta)
	return item

func _selected_meta() -> String:
	var sel := _category_list.get_selected()
	return str(sel.get_metadata(0)) if sel != null else ""

func _select_by_meta(from: TreeItem, meta: String) -> bool:
	var item := from.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == meta and item.get_first_child() == null:
			item.select(0)
			return true
		if _select_by_meta(item, meta):
			return true
		item = item.get_next()
	return false

## Tree 选中：转发到统一分类处理（meta 字符串与旧 index 版语义对齐）
func _on_tree_selected() -> void:
	var sel := _category_list.get_selected()
	if sel == null:
		return
	var meta := str(sel.get_metadata(0))
	if meta.is_empty(): # 区域父节点：展开由 Tree 自理，不切素材
		return
	if _active_chip != "": # 树选择优先：撤下 chip，避免双通道并立
		_active_chip = ""
		_refresh_chip_styles()
	_on_category_selected(meta)

func set_recent(ids: Array) -> void:
	_recent_ids = ids.duplicate()
	_rebuild_chips()

## 外部注入收藏清单（「★收藏」chip 内容）
## 注入标签反向索引（每个 #标签 一条 chip）
func set_tags(tag_index: Dictionary) -> void:
	_tag_ids = tag_index.duplicate()
	_rebuild_chips()

func set_favorites(ids: Array) -> void:
	_favorite_ids = ids.duplicate()
	_rebuild_chips()

func _on_category_selected(meta: String) -> void:
	if _selected != null and is_instance_valid(_selected):
		_apply_card_style(_selected, false)
		_selected = null
	for child in _grid.get_children():
		child.queue_free()
	_buttons.clear()
	var category := meta
	var assets: Array
	if category == "__recent" or category == "__fav" or category.begins_with("__tag:"):
		var ids: Array
		if category == "__recent":
			ids = _recent_ids
		elif category == "__fav":
			ids = _favorite_ids
		else:
			ids = _tag_ids.get(category.substr("__tag:".length()), [])
		var vlist := []
		for id in ids:
			var asset := _library.get_asset(str(id))
			if not asset.is_empty():
				vlist.append(asset)
		assets = vlist
	elif category.begins_with("__group:"):
		var want := category.substr("__group:".length())
		for a in _library.get_assets():
			if str((a as Dictionary).get("group", "")) == want:
				assets.append(a)
	else:
		var raw := _library.get_assets_by_category(category)
		for a in raw:
			if str((a as Dictionary).get("group", "")).is_empty():
				assets.append(a)
	# 搜索过滤（当前分类内按名称/id 匹配）
	var keyword := _search_box.text.strip_edges().to_lower()
	if not keyword.is_empty():
		var klist := []
		for asset in assets:
			var name_l := str((asset as Dictionary)["name"]).to_lower()
			if name_l.find(keyword) >= 0 or str((asset as Dictionary)["id"]).to_lower().find(keyword) >= 0:
				klist.append(asset)
		assets = klist
	_empty_hint.visible = assets.is_empty()
	for asset in assets:
		var btn := _make_thumb_button(asset as Dictionary)
		_buttons[str((asset as Dictionary)["id"])] = btn
		_grid.add_child(btn)

## 搜索词变化：重刷当前内容（chip 激活时作用于 chip 分类）；空词显示清除按钮
func _on_search_changed() -> void:
	if _clear_btn != null:
		_clear_btn.visible = not _search_box.text.is_empty()
	var meta := _active_chip if _active_chip != "" else _selected_meta()
	if not meta.is_empty():
		_on_category_selected(meta)

## 素材卡片（§P2 §4.3）：缩略图（整数倍最近邻）+ 名称（省略+tooltip）+ 占格行 + 锚点角标
func _make_thumb_button(asset: Dictionary) -> Button:
	var asset_id := str(asset["id"])
	var cells: Vector2i = asset["cells"]
	var anchor := str(asset.get("anchor", "bottom_center"))
	var anchor_name := "底边中心" if anchor == "bottom_center" else "左上角"
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, 0)
	btn.tooltip_text = "%s\n%d×%dpx · 占格 %d×%d\n锚点：%s" % [
		str(asset["name"]), int(cells.x) * 16, int(cells.y) * 16,
		cells.x, cells.y, anchor_name]
	_apply_card_style(btn, false)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE # 卡片子控件不吞点击
	btn.add_child(box)

	var thumb_area := Control.new()
	thumb_area.custom_minimum_size = Vector2(THUMB_BOX, THUMB_BOX)
	thumb_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumb_area)
	var tex := TextureRect.new()
	tex.texture = _get_thumb(asset_id)
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 像素纪律：最近邻
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_area.add_child(tex)
	var badge := Label.new()
	badge.text = "▽" if anchor == "bottom_center" else "△"
	badge.add_theme_font_size_override("font_size", 11)
	badge.modulate = Color(1, 1, 1, 0.75)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_area.add_child(badge)

	var name_lab := Label.new()
	name_lab.text = str(asset["name"])
	name_lab.add_theme_font_size_override("font_size", 12)
	name_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # 截断兜底：卡片 tooltip 见全名
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_lab)
	var info := Label.new()
	info.text = "%d×%d格" % [cells.x, cells.y]
	info.add_theme_font_size_override("font_size", 11)
	info.modulate = AppTheme.TEXT_DIM
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(info)

	btn.pressed.connect(_on_thumb_pressed.bind(btn, asset_id))
	return btn

## 卡片态（§P2）：常态 Surface-2；hover 抬到 Surface-3（不放大原图）；选中=左 Accent 条+低亮底
func _apply_card_style(btn: Button, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	for sb in [normal, hover]:
		(sb as StyleBoxFlat).set_corner_radius_all(AppTheme.RADIUS_MD)
		(sb as StyleBoxFlat).content_margin_left = 4
		(sb as StyleBoxFlat).content_margin_right = 4
		(sb as StyleBoxFlat).content_margin_top = 4
		(sb as StyleBoxFlat).content_margin_bottom = 4
		(sb as StyleBoxFlat).set_border_width_all(1)
	if selected:
		normal.bg_color = AppTheme.SURFACE_ACTIVE
		normal.border_color = Color(1, 1, 1, 0.0)
		normal.border_width_left = 3
		normal.border_color = AppTheme.ACCENT # 左侧 Accent 条（避免整块金色过重）
		hover.bg_color = AppTheme.SURFACE_ACTIVE
		hover.border_width_left = 3
		hover.border_color = AppTheme.ACCENT
	else:
		normal.bg_color = AppTheme.SURFACE_2
		normal.border_color = Color(1, 1, 1, 0.06)
		hover.bg_color = AppTheme.SURFACE_3 # hover 抬层级（§P2）
		hover.border_color = AppTheme.DIVIDER
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = AppTheme.SURFACE_ACTIVE
	pressed.set_corner_radius_all(AppTheme.RADIUS_MD)
	pressed.content_margin_left = 4
	pressed.content_margin_right = 4
	pressed.content_margin_top = 4
	pressed.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)

func _on_thumb_pressed(btn: Button, asset_id: String) -> void:
	if _selected != null and is_instance_valid(_selected):
		_apply_card_style(_selected, false) # 切分类重建缩略图后旧引用已释放（帧末 queue_free），须校验
	_selected = btn
	_apply_card_style(btn, true)
	asset_selected.emit(asset_id)

## 清除选中卡片高亮（画布空白处右键取消选中用；不发信号——选中态由 main 持有）
func clear_selection() -> void:
	if _selected != null and is_instance_valid(_selected):
		_apply_card_style(_selected, false)
	_selected = null

## 面板缩略图：库级 64 盒缩放缓存（整数倍缩放，面板/快捷栏共用）
func _get_thumb(asset_id: String) -> ImageTexture:
	return _library.load_thumb(asset_id)
