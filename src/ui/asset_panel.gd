class_name AssetPanel
extends PanelContainer
## 素材面板（design.md §6.1 最小版）：左分类列表 + 右缩略图网格
## 像素纪律：缩略图整数倍放大 + 最近邻重采样，不做任意拉伸
## 全部节点代码动态创建（.tscn 精简纪律）

signal asset_selected(asset_id: String)
signal rescan_requested ## 刷新素材库（放入文件后点按即扫，无须重启）

const THUMB_BOX := 64 ## 缩略图最大边（px）：16px→4x=64、48px→1x=48，均为整数倍
const PANEL_WIDTH := 320 ## 最小宽=紧凑档右 Dock（§4.2）；列数自适应 2-5 列兜底窄面板，标准档 400 由壳层给足

## 分类显示名（design.md §6.1）
const CATEGORY_NAMES := {
	"ground": "地面", "road": "道路", "wall": "墙体", "building": "建筑",
	"tree": "树木", "stall": "摊位", "indoor": "室内", "furniture": "家具", "deco": "装饰",
}

var _library: AssetLibrary
var _category_list: Tree # 三层菜单树（虚拟分类置顶+group 树+原分类）
var _grid: HFlowContainer
var _empty_hint: Label
var _selected: TextureButton
var _buttons := {} # asset_id -> TextureButton（当前分类网格内的按钮）
var _search_box: LineEdit # 搜索框（过滤当前分类，§6.1 搜索）
var _recent_ids: Array = [] # 最近使用（虚拟分类「最近」）
var _favorite_ids: Array = [] # 收藏（虚拟分类「★收藏」，F 键切换）
var _tag_ids := {} # 标签反向索引 {tag: [asset_id]}（虚拟分类「#标签」）
var _thumbs := {} # asset_id -> ImageTexture（整数倍缩放后的缩略图）

## 外部指定选中（吸管等入口）：切换到对应分类并高亮（会发 asset_selected 信号）
func select_asset(asset_id: String) -> void:
	if not _buttons.has(asset_id):
		var asset := _library.get_asset(asset_id)
		if asset.is_empty():
			return
		# 目标素材不在当前缩略图区：先切到它所属分类再选（三层树按 meta 遍历，
		# 旧 item_count/get_item_metadata(index) 是 ItemList 残留 API，Tree 上会抛错中断选中）
		var meta := str(asset["category"])
		if _select_by_meta(_category_list.get_root(), meta):
			_on_category_selected(meta)
	var btn: TextureButton = _buttons.get(asset_id)
	if btn != null:
		_on_thumb_pressed(btn, asset_id)

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

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(hbox)

	_category_list = Tree.new()
	_category_list.custom_minimum_size = Vector2(150, 0)
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

	var refresh := Button.new()
	refresh.text = "⟳ 刷新素材库"
	refresh.tooltip_text = "放入新素材文件后点此立即扫描（也可随时重启）"
	refresh.pressed.connect(func() -> void: rescan_requested.emit())
	box.add_child(refresh)

	var search := LineEdit.new()
	search.placeholder_text = "搜索素材…"
	search.right_icon = null
	search.text_changed.connect(func(_t: String) -> void:
		_on_search_changed())
	box.add_child(search)
	_search_box = search

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

## 分类列表：虚拟分类（最近/★收藏）置顶，其后按固定顺序列实际分类；重入选中保持
func _rebuild_category_list() -> void:
	var selected_meta := _selected_meta()
	_category_list.clear()
	var root := _category_list.create_item()
	if not _recent_ids.is_empty():
		_add_leaf(root, "最近", "__recent")
	if not _favorite_ids.is_empty():
		_add_leaf(root, "★收藏", "__fav")
	for tag in _tag_ids.keys():
		_add_leaf(root, "#%s" % str(tag), "__tag:" + str(tag))
	# group 三层树：外层（区域=抠图文件夹父级名）→ 板块（叶=选中显示素材）
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
	_on_category_selected(meta)

func set_recent(ids: Array) -> void:
	_recent_ids = ids.duplicate()
	_rebuild_category_list()

## 外部注入收藏清单（虚拟分类「★收藏」内容）
## 注入标签反向索引（每个 #标签 一条虚拟分类）
func set_tags(tag_index: Dictionary) -> void:
	_tag_ids = tag_index.duplicate()
	_rebuild_category_list()

func set_favorites(ids: Array) -> void:
	_favorite_ids = ids.duplicate()
	_rebuild_category_list()

func _on_category_selected(meta: String) -> void:
	if _selected != null:
		_selected.modulate = Color.WHITE
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

## 搜索词变化：重刷当前选中节点内容
func _on_search_changed() -> void:
	var sel := _category_list.get_selected()
	if sel != null:
		_on_category_selected(str(sel.get_metadata(0)))

func _make_thumb_button(asset: Dictionary) -> TextureButton:
	var asset_id := str(asset["id"])
	var btn := TextureButton.new()
	btn.texture_normal = _get_thumb(asset_id)
	# 锚点角标（design.md §6.1 缩略图显示锚点类型）：底边中心=▽、左上角=△
	var anchor := str(asset.get("anchor", "bottom_center"))
	btn.tooltip_text = "%s\n占格 %d×%d\n锚点 %s" % [str(asset["name"]), (asset["cells"] as Vector2i).x, (asset["cells"] as Vector2i).y, "底边中心" if anchor == "bottom_center" else "左上角"]
	var badge := Label.new()
	badge.text = "▽" if anchor == "bottom_center" else "△"
	badge.add_theme_font_size_override("font_size", 11)
	badge.modulate = Color(1, 1, 1, 0.75)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.add_child(badge)
	btn.pressed.connect(_on_thumb_pressed.bind(btn, asset_id))
	return btn

func _on_thumb_pressed(btn: TextureButton, asset_id: String) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.modulate = Color.WHITE # 切分类重建缩略图后旧引用已释放（帧末 queue_free），须校验

	_selected = btn
	btn.modulate = Color(1.0, 0.9, 0.5) # 选中高亮
	asset_selected.emit(asset_id)

## 整数倍缩放缩略图（最近邻）：16px→4x、48px→1x，不产生非整数拉伸
func _get_thumb(asset_id: String) -> ImageTexture:
	if _thumbs.has(asset_id):
		return _thumbs[asset_id]
	var img := _library.load_image(asset_id)
	if img == null:
		return ImageTexture.new()
	var scale := maxi(1, THUMB_BOX / maxi(img.get_width(), img.get_height()))
	var thumb := img
	if scale > 1:
		thumb = img.duplicate()
		thumb.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(thumb)
	_thumbs[asset_id] = tex
	return tex
