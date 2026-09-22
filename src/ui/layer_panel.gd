class_name LayerPanel
extends PanelContainer
## 图层面板 v3（UI 重构阶段 C §5.2）：两行结构——
## 行1：拖柄+名称（点击=活动层/双击重命名）+内容计数；行2：显隐/锁/透明度/更多菜单
## 命中区≥32px（§3.3）；活动层=金边+▸符号（颜色之外的可读表达，§7）
## 添加层合并为单按钮弹类型菜单；删除/排序收进 ⋯ 菜单

signal layer_activity_requested(layer_id: String) ## 点击行：设为活动层

var _document: MapDocument
var _rows := {} # layer_id -> LayerEntry
var _active_layer := "" ## 活动层（高亮；放置/擦除优先目标）
var _box: VBoxContainer

func setup(doc: MapDocument) -> void:
	_document = doc
	custom_minimum_size = Vector2(210, 0)
	for child in get_children(): # 重复 setup（载入新文档）时重建
		child.queue_free()
	_rows.clear()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	var hint := Label.new()
	hint.text = "拖柄排序 · 双击改名 · 点名=活动层"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate.a = 0.55
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # 防 min 宽超过紧凑档
	_box.add_child(hint)
	_rebuild_rows()
	if not _document.layer_changed.is_connected(_on_layer_changed):
		_document.layer_changed.connect(_on_layer_changed)
	if not _document.layers_restructured.is_connected(_on_restructured):
		_document.layers_restructured.connect(_on_restructured)
	# 内容计数随放置/擦除/物件增删刷新（只改计数文本，不重建行——避免打断滑杆拖动）
	if not _document.tile_changed.is_connected(_on_content_changed):
		_document.tile_changed.connect(_on_content_changed)
	if not _document.object_added.is_connected(_on_content_changed):
		_document.object_added.connect(_on_content_changed)
	if not _document.object_removed.is_connected(_on_content_changed):
		_document.object_removed.connect(_on_content_changed)
	if not _document.object_changed.is_connected(_on_content_changed):
		_document.object_changed.connect(_on_content_changed) # 物件替换/跨层移动也影响计数

var _count_dirty := false ## 计数刷新去抖：批量落格（矩形 2500 格）逐格 tile_changed 会
## 触发同次数全行计数重算（每行遍历文档），帧末合并为一次

## 手动拖拽排序（引擎 drag-drop 检测多轮实测不可达——force_drag/Button 模态/parse 模拟
## 均失败；按下-位移-释放全自管，探针可逐段验证）
var _drag_pending: LayerEntry = null
var _drag_active := false
var _drag_press_pos := Vector2.ZERO
var _drag_highlight: LayerEntry = null

func _on_content_changed(_a = null, _b = null) -> void:
	_count_dirty = true

func _process(_delta: float) -> void:
	if _count_dirty:
		_count_dirty = false
		for id in _rows.keys():
			(_rows[id] as LayerEntry).refresh_count()
	_process_drag()

func _process_drag() -> void:
	if _drag_pending != null and is_instance_valid(_drag_pending):
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not _drag_active:
				_drag_pending = null # 未移动即释放=普通点击，不排序
				return
			_finish_drag()
			return
		if not _drag_active and _drag_press_pos.distance_to(get_global_mouse_position()) > 8.0:
			_drag_active = true
		if _drag_active:
			_set_drag_highlight(_entry_under_mouse())
	elif _drag_active:
		_finish_drag()

## 按下拖柄/名称：开始跟踪（是否成拖拽由后续位移决定）
func _begin_drag_track(entry: LayerEntry) -> void:
	_drag_pending = entry
	_drag_press_pos = get_global_mouse_position()
	_drag_active = false

func _entry_under_mouse() -> LayerEntry:
	var mp := get_global_mouse_position()
	for id in _rows.keys():
		var e = _rows[id]
		if e != null and is_instance_valid(e) and e.get_global_rect().has_point(mp):
			return e
	return null

func _set_drag_highlight(entry: LayerEntry) -> void:
	if entry == _drag_highlight:
		return
	if _drag_highlight != null and is_instance_valid(_drag_highlight):
		_drag_highlight.modulate = Color.WHITE
	_drag_highlight = entry
	if entry != null:
		entry.modulate = Color(1.3, 1.15, 0.75) # 目标行高亮（释放即落位到该行）

func _finish_drag() -> void:
	var target := _entry_under_mouse()
	var src := _drag_pending
	_drag_active = false
	_drag_pending = null
	_set_drag_highlight(null)
	if src != null and is_instance_valid(src) and target != null and target != src:
		_document.move_layer(str(src._layer["id"]), target._panel_index_to_layer_index())
		print("[TileMason] 图层已排序（%s → 目标行位置）" % str(src._layer["id"]))

func _on_layer_changed(layer_id: String, key: String) -> void:
	# 只重建名字（行结构）；visible/locked/opacity 由行内控件自更新——
	# 全量重建会打断透明度滑杆的连续拖动（实测行为退化）
	if key == "name":
		_on_restructured()

func _on_restructured() -> void:
	if not _active_layer.is_empty() and _document.get_layer(_active_layer).is_empty():
		_active_layer = "" # 活动层已被删除：清引用，否则擦除/放置路由到不存在的层
	_rebuild_rows()

## 全量重建行（视觉自顶向下=列表倒序：末层显示在最上）
func _rebuild_rows() -> void:
	for child in _box.get_children():
		if child is LayerEntry:
			child.queue_free()
	_rows.clear()
	var layers: Array = _document.get_layers()
	for i in range(layers.size() - 1, -1, -1):
		var layer := layers[i] as Dictionary
		var row := LayerEntry.new()
		row.setup(self, layer, str(layer["id"]) == _active_layer)
		_rows[str(layer["id"])] = row
		_box.add_child(row)
	for child in _box.get_children(): # 工具行保持垫底（新加条目排到了它后面）
		if str(child.name) == "ToolsRow":
			_box.move_child(child, -1)
			break
	_ensure_tools_row()

## 底部「+添加层」按钮（单入口弹菜单选类型，§5.2：减底部横向拥挤）
func _ensure_tools_row() -> void:
	for child in _box.get_children():
		if child is HBoxContainer and str(child.name).begins_with("ToolsRow"):
			return # 已有
	var tools := HBoxContainer.new()
	tools.name = "ToolsRow"
	var add := Button.new()
	add.text = "+ 添加层"
	add.tooltip_text = "选择要新建的层类型"
	add.custom_minimum_size = Vector2(0, 32)
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var menu := PopupMenu.new()
	tools.add_child(menu) # Popup 必须在树内才能 popup（挂工具行下，默认隐藏不占布局）
	menu.add_item("方块层（16px 网格）", 0)
	menu.add_item("物件层（建筑/树木等自由摆放）", 1)
	menu.id_pressed.connect(func(id: int) -> void:
		var layer_id := _document.add_layer("tile" if id == 0 else "object")
		set_active_layer(layer_id))
	add.pressed.connect(func() -> void:
		menu.reset_size()
		var gp := add.global_position
		menu.position = Vector2i(int(gp.x), int(gp.y + add.size.y))
		menu.popup())
	tools.add_child(add)
	_box.add_child(tools)

## 活动层（放置/擦除优先落点；空=按素材分类默认路由）
func set_active_layer(layer_id: String) -> void:
	_active_layer = layer_id
	_on_restructured()

func active_layer() -> String:
	return _active_layer

## 层条目：两行卡片（行1 名称/计数，行2 显隐/锁/透明度/更多）
class LayerEntry extends PanelContainer:
	var _panel: LayerPanel
	var _layer: Dictionary
	var _name_btn: Button
	var _count_label: Label
	var _rename_edit: LineEdit
	var _renaming := false

	func setup(panel: LayerPanel, layer: Dictionary, is_active: bool) -> void:
		_panel = panel
		_layer = layer
		var sb := StyleBoxFlat.new()
		sb.bg_color = AppTheme.BG_DARK
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		var is_locked := bool(layer.get("locked", false))
		if is_active:
			sb.set_border_width_all(1)
			sb.border_color = AppTheme.ACCENT_DIM # 活动层金边（+▸ 符号双通道表达）
		add_theme_stylebox_override("panel", sb)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(box)

		# 行1：拖柄 + 名称（EXPAND）+ 计数 —— 命中区 32px
		var row1 := HBoxContainer.new()
		row1.add_theme_constant_override("separation", 4)
		box.add_child(row1)
		var grip := GripLabel.new()
		grip.text = "⠿"
		grip.modulate.a = 0.55
		grip.custom_minimum_size = Vector2(24, 32) # 命中区 24×32（曾 10×19 点不中）
		grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grip.mouse_filter = Control.MOUSE_FILTER_STOP
		grip.tooltip_text = "按住拖动排序（上=更高层级）"
		grip.entry = self
		row1.add_child(grip)
		_name_btn = NameButton.new()
		_name_btn.entry = self # 名称区域也可拖排序（按住移动；单击/双击语义不变）
		var shown_name := str(layer.get("name", layer.get("id", "")))
		_name_btn.text = ("▸ " if is_active else "") + shown_name
		_name_btn.flat = true
		_name_btn.add_theme_font_size_override("font_size", 13)
		_name_btn.custom_minimum_size = Vector2(0, 32)
		_name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name_btn.tooltip_text = shown_name # 截断兜底：hover 见全名（§3.3）
		row1.add_child(_name_btn)
		_count_label = Label.new()
		_count_label.add_theme_font_size_override("font_size", 12)
		_count_label.modulate.a = 0.6
		_count_label.text = _count_text()
		_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(_count_label)
		# 单击=活动层；双击=重命名（0.28s 内两击算双击）
		_name_btn.button_down.connect(_on_name_pressed)

		# 行2：显隐 / 锁 / 透明度 / 更多 —— 按钮 32px 档命中区，文字态随开关切换
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 4)
		box.add_child(row2)
		var visible_btn := Button.new()
		visible_btn.toggle_mode = true
		visible_btn.button_pressed = bool(layer.get("visible", true))
		visible_btn.text = "显" if visible_btn.button_pressed else "隐"
		visible_btn.tooltip_text = "显示/隐藏该层"
		visible_btn.custom_minimum_size = Vector2(34, 28)
		visible_btn.toggled.connect(func(on: bool) -> void:
			visible_btn.text = "显" if on else "隐"
			panel._document.set_layer_property(str(_layer["id"]), "visible", on))
		row2.add_child(visible_btn)
		var lock_btn := Button.new()
		lock_btn.toggle_mode = true
		lock_btn.button_pressed = is_locked
		lock_btn.text = "锁"
		lock_btn.tooltip_text = "锁定后不可放置/擦除"
		lock_btn.custom_minimum_size = Vector2(34, 28)
		lock_btn.modulate = AppTheme.WARNING if is_locked else Color(1, 1, 1, 0.6)
		lock_btn.toggled.connect(func(on: bool) -> void:
			lock_btn.modulate = AppTheme.WARNING if on else Color(1, 1, 1, 0.6)
			lock_btn.tooltip_text = "锁定后不可放置/擦除（当前：已锁定）" if on else "锁定后不可放置/擦除"
			panel._document.set_layer_property(str(_layer["id"]), "locked", on))
		row2.add_child(lock_btn)
		var opacity := HSlider.new()
		opacity.min_value = 0.1
		opacity.max_value = 1.0
		opacity.step = 0.1
		opacity.value = float(layer.get("opacity", 1.0))
		opacity.custom_minimum_size = Vector2(40, 24)
		opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opacity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		opacity.tooltip_text = "透明度"
		opacity.value_changed.connect(func(v: float) -> void:
			panel._document.set_layer_property(str(_layer["id"]), "opacity", v))
		row2.add_child(opacity)
		var pct := Label.new()
		pct.text = "%d%%" % roundi(float(layer.get("opacity", 1.0)) * 100.0)
		pct.add_theme_font_size_override("font_size", 11)
		pct.modulate.a = 0.55
		pct.custom_minimum_size = Vector2(30, 0)
		row2.add_child(pct)
		row2.add_child(_make_more_menu())

	## 内容计数（tile 层数格 / object 层数件）
	func _count_text() -> String:
		var id := str(_layer["id"])
		if str(_layer.get("type", "tile")) == "object":
			return "%d件" % _panel._document.get_objects_on_layer(id).size()
		return "%d格" % _panel._document.get_tile_count(id)

	## 内容变化时只更新计数文本（全量重建会打断行2 控件交互）
	func refresh_count() -> void:
		if _count_label != null:
			_count_label.text = _count_text()

	## ⋯ 更多菜单：重命名/上移/下移/删除（低频操作不常驻，§5.2）
	func _make_more_menu() -> Button:
		var more := Button.new()
		more.text = "⋯"
		more.tooltip_text = "重命名 / 排序 / 删除"
		more.custom_minimum_size = Vector2(34, 28)
		var menu := PopupMenu.new()
		add_child(menu) # Popup 必须在树内才能 popup（挂条目下，默认隐藏不占布局）
		menu.add_item("重命名", 0)
		menu.add_item("上移（更高层级）", 1)
		menu.add_item("下移（更低层级）", 2)
		menu.add_separator()
		menu.add_item("删除该层（需先清空内容）", 3)
		menu.id_pressed.connect(_on_more_id)
		more.pressed.connect(func() -> void:
			menu.reset_size()
			var gp := more.global_position
			menu.position = Vector2i(int(gp.x), int(gp.y + more.size.y))
			menu.popup())
		return more

	## ⋯ 菜单项分发（match 抽独立方法：lambda 内嵌 match 多分支解析不稳）
	func _on_more_id(id: int) -> void:
		match id:
			0:
				_start_rename()
			1:
				_panel._document.move_layer(str(_layer["id"]), _panel_index_to_layer_index() + 1)
			2:
				_panel._document.move_layer(str(_layer["id"]), _panel_index_to_layer_index() - 1)
			3:
				if not _panel._document.remove_layer(str(_layer["id"])):
					print("[TileMason] 删除失败：层上有内容或已是最后一层（先清空该层）")

	var _last_press_ms := 0

	func _on_name_pressed() -> void:
		var now := Time.get_ticks_msec()
		if now - _last_press_ms < 280: # 双击 → 重命名
			_start_rename()
			_last_press_ms = 0
		else:
			_last_press_ms = now
			# 单击 → 立即设活动层（幂等：双击重命名的首击切到本层属合理行为；
			# 旧版等 0.3s 双击窗口再生效，用户实测「点击反应慢」，取消延迟）
			_panel.layer_activity_requested.emit(str(_layer["id"]))

	## 重命名：整行编辑框（§5.2：不与按钮争抢宽度——行1 名称位替换为 LineEdit 铺满）
	func _start_rename() -> void:
		if _renaming:
			return
		_renaming = true
		_rename_edit = LineEdit.new()
		_rename_edit.text = str(_layer.get("name", _layer.get("id", "")))
		_rename_edit.custom_minimum_size = Vector2(60, 30)
		_rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rename_edit.text_submitted.connect(func(new_name: String) -> void:
			_panel._document.set_layer_property(str(_layer["id"]), "name", new_name)
			_end_rename())
		_rename_edit.focus_exited.connect(func() -> void: _end_rename())
		_name_btn.visible = false
		var row1 := _name_btn.get_parent() as HBoxContainer
		row1.add_child(_rename_edit)
		row1.move_child(_rename_edit, _name_btn.get_index())
		_rename_edit.grab_focus()
		_rename_edit.select_all()

	func _end_rename() -> void:
		if not _renaming:
			return
		_renaming = false
		if is_instance_valid(_rename_edit):
			_rename_edit.queue_free()
		_name_btn.visible = true

	func _make_preview() -> Control:
		var lab := Label.new()
		lab.text = "↕ " + str(_layer.get("name", ""))
		lab.modulate = Color(1, 1, 1, 0.8)
		return lab

	## 本条目面板序号 → 文档层序（面板倒序：面板第 1 条=文档末层）
	func _panel_index_to_layer_index() -> int:
		var idx := get_index() - 1 # 减提示行
		var total := _panel._document.layer_count()
		return clampi(total - 1 - idx, 0, total - 1)

## 拖柄（按下即开始拖拽跟踪；引擎 drag-drop 检测三轮实测不可达，改 LayerPanel 手动托管）
class GripLabel extends Label:
	var entry: Variant # 所属 LayerEntry
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed 				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			(entry as LayerEntry)._panel._begin_drag_track(entry)

## 名称按钮：名称区域同样可拖（按住移动=排序；未移动按放=单击/双击语义不变）
class NameButton extends Button:
	var entry: Variant # 所属 LayerEntry
	func _init() -> void:
		button_down.connect(_on_down)
	func _on_down() -> void:
		(entry as LayerEntry)._panel._begin_drag_track(entry)
