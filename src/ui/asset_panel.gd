class_name AssetPanel
extends PanelContainer
## 素材面板（design.md §6.1 最小版）：左分类列表 + 右缩略图网格
## 像素纪律：缩略图整数倍放大 + 最近邻重采样，不做任意拉伸
## 全部节点代码动态创建（.tscn 精简纪律）

signal asset_selected(asset_id: String)

const THUMB_BOX := 64 ## 缩略图最大边（px）：16px→4x=64、48px→1x=48，均为整数倍
const PANEL_WIDTH := 380

## 分类显示名（design.md §6.1）
const CATEGORY_NAMES := {
	"ground": "地面", "road": "道路", "wall": "墙体", "building": "建筑",
	"tree": "树木", "stall": "摊位", "indoor": "室内", "furniture": "家具", "deco": "装饰",
}

var _library: AssetLibrary
var _category_list: ItemList
var _grid: GridContainer
var _empty_hint: Label
var _selected: TextureButton
var _buttons := {} # asset_id -> TextureButton（当前分类网格内的按钮）
var _search_box: LineEdit # 搜索框（过滤当前分类，§6.1 搜索）
var _recent_ids: Array = [] # 最近使用（虚拟分类「最近」）
var _favorite_ids: Array = [] # 收藏（虚拟分类「★收藏」，F 键切换）
var _thumbs := {} # asset_id -> ImageTexture（整数倍缩放后的缩略图）

## 外部指定选中（吸管等入口）：切换到对应分类并高亮（会发 asset_selected 信号）
func select_asset(asset_id: String) -> void:
	if not _buttons.has(asset_id):
		var asset := _library.get_asset(asset_id)
		if asset.is_empty():
			return
		for i in _category_list.item_count:
			if str(_category_list.get_item_metadata(i)) == str(asset["category"]):
				_category_list.select(i)
				_on_category_selected(i)
				break
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

	_category_list = ItemList.new()
	_category_list.custom_minimum_size = Vector2(96, 0)
	_category_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_category_list.item_selected.connect(_on_category_selected)
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

	var search := LineEdit.new()
	search.placeholder_text = "搜索素材…"
	search.right_icon = null
	search.text_changed.connect(func(_t: String) -> void:
		_on_search_changed())
	box.add_child(search)
	_search_box = search

	_grid = GridContainer.new()
	_grid.columns = 3
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
	var selected_meta := ""
	if _category_list.item_count > 0 and _category_list.get_selected_items().size() > 0:
		selected_meta = str(_category_list.get_item_metadata(_category_list.get_selected_items()[0]))
	_category_list.clear()
	if not _recent_ids.is_empty():
		_category_list.add_item("最近")
		_category_list.set_item_metadata(_category_list.item_count - 1, "__recent")
	if not _favorite_ids.is_empty():
		_category_list.add_item("★收藏")
		_category_list.set_item_metadata(_category_list.item_count - 1, "__fav")
	var categories: Array = _library.get_categories() if _library != null else []
	if categories.is_empty() and _recent_ids.is_empty() and _favorite_ids.is_empty():
		_empty_hint.text = "未找到素材包\n可将自己的素材包放入\nassets/packs/ 目录"
		_empty_hint.visible = true
		return
	for category in categories:
		_category_list.add_item(str(CATEGORY_NAMES.get(str(category), str(category))))
		_category_list.set_item_metadata(_category_list.item_count - 1, str(category))
	for i in _category_list.item_count: # 恢复选中；原选中不存在则选第一项
		if str(_category_list.get_item_metadata(i)) == selected_meta:
			_category_list.select(i)
			_on_category_selected(i)
			return
	_category_list.select(0)
	_category_list.item_selected.emit(0)

## 搜索词变化：重刷当前分类网格
func _on_search_changed() -> void:
	if _category_list.get_selected_items().size() > 0:
		_on_category_selected(_category_list.get_selected_items()[0])

## 外部注入最近使用清单（虚拟分类「最近」内容）
func set_recent(ids: Array) -> void:
	_recent_ids = ids.duplicate()
	_rebuild_category_list()

## 外部注入收藏清单（虚拟分类「★收藏」内容）
func set_favorites(ids: Array) -> void:
	_favorite_ids = ids.duplicate()
	_rebuild_category_list()

func _on_category_selected(index: int) -> void:
	if _selected != null:
		_selected.modulate = Color.WHITE
		_selected = null
	for child in _grid.get_children():
		child.queue_free()
	_buttons.clear()
	var category := str(_category_list.get_item_metadata(index))
	var assets: Array
	if category == "__recent" or category == "__fav":
		# 虚拟分类：按记录顺序映射素材（失效 id 过滤）
		var ids := _recent_ids if category == "__recent" else _favorite_ids
		for id in ids:
			var asset := _library.get_asset(str(id))
			if not asset.is_empty():
				assets.append(asset)
	else:
		assets = _library.get_assets_by_category(category)
	# 搜索过滤（§6.1）：按名称/素材 id 包含匹配，虚拟分类同样生效
	var keyword := _search_box.text.strip_edges().to_lower()
	if not keyword.is_empty():
		var filtered := []
		for asset in assets:
			var name_l := str((asset as Dictionary)["name"]).to_lower()
			if name_l.find(keyword) >= 0 or str((asset as Dictionary)["id"]).to_lower().find(keyword) >= 0:
				filtered.append(asset)
		assets = filtered
	_empty_hint.visible = assets.is_empty()
	for asset in assets:
		var btn := _make_thumb_button(asset as Dictionary)
		_buttons[str((asset as Dictionary)["id"])] = btn
		_grid.add_child(btn)

func _make_thumb_button(asset: Dictionary) -> TextureButton:
	var asset_id := str(asset["id"])
	var btn := TextureButton.new()
	btn.texture_normal = _get_thumb(asset_id)
	btn.tooltip_text = "%s\n占格 %d×%d" % [str(asset["name"]), (asset["cells"] as Vector2i).x, (asset["cells"] as Vector2i).y]
	btn.pressed.connect(_on_thumb_pressed.bind(btn, asset_id))
	return btn

func _on_thumb_pressed(btn: TextureButton, asset_id: String) -> void:
	if _selected != null:
		_selected.modulate = Color.WHITE
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
