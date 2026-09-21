class_name LayerPanel
extends PanelContainer
## 图层面板 v2（用户反馈 #1/#2）：重命名（双击名）/加层/删层/拖拽排序（上=高层级）
## + 活动层选择（点击行=活动层，放置优先落此层）——全部节点动态创建

signal layer_activity_requested(layer_id: String) ## 点击行：设为活动层

var _document: MapDocument
var _rows := {} # layer_id -> LayerRow
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
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(_box)
	_rebuild_rows()
	if not _document.layer_changed.is_connected(_on_layer_changed):
		_document.layer_changed.connect(_on_layer_changed)
	if not _document.layers_restructured.is_connected(_on_restructured):
		_document.layers_restructured.connect(_on_restructured)

func _on_layer_changed(layer_id: String, key: String) -> void:
	if key == "name":
		_on_restructured()

func _on_restructured() -> void:
	_rebuild_rows()

## 全量重建行（视觉自顶向下=列表倒序：末层显示在最上）
func _rebuild_rows() -> void:
	for child in _box.get_children():
		child.queue_free()
	_rows.clear()
	var title := Label.new()
	title.text = "图层（拖柄排序·双击改名·点名=活动层）"
	title.add_theme_font_size_override("font_size", 12)
	_box.add_child(title)
	var layers: Array = _document.get_layers()
	for i in range(layers.size() - 1, -1, -1):
		var layer := layers[i] as Dictionary
		var row := LayerRow.new()
		row.setup(self, layer, str(layer["id"]) == _active_layer)
		_rows[str(layer["id"])] = row
		_box.add_child(row)
	var tools := HBoxContainer.new()
	var add_tile := Button.new()
	add_tile.text = "+方块层"
	add_tile.tooltip_text = "新建规则方块层（16px 网格）"
	add_tile.pressed.connect(func() -> void:
		var id := _document.add_layer("tile")
		set_active_layer(id))
	var add_obj := Button.new()
	add_obj.text = "+物件层"
	add_obj.tooltip_text = "新建自由物件层（建筑/树木等）"
	add_obj.pressed.connect(func() -> void:
		var id := _document.add_layer("object")
		set_active_layer(id))
	tools.add_child(add_tile)
	tools.add_child(add_obj)
	_box.add_child(tools)

## 活动层（放置/擦除优先落点；空=按素材分类默认路由）
func set_active_layer(layer_id: String) -> void:
	_active_layer = layer_id
	_on_restructured()

func active_layer() -> String:
	return _active_layer

## 单行：拖柄（拖拽源）+名称（点击=活动层/双击重命名）/显示/锁/透明度/删
class LayerRow extends HBoxContainer:
	var _panel: LayerPanel
	var _layer: Dictionary
	var _name_btn: Button
	var _rename_edit: LineEdit
	var _renaming := false

	func setup(panel: LayerPanel, layer: Dictionary, is_active: bool) -> void:
		_panel = panel
		_layer = layer
		add_theme_constant_override("separation", 3)
		custom_minimum_size = Vector2(0, 26)

		var grip := Label.new()
		grip.text = "⠿"
		grip.modulate.a = 0.5
		grip.mouse_filter = Control.MOUSE_FILTER_STOP # 拖柄：按下发起拖拽
		grip.gui_input.connect(_on_grip_input)
		add_child(grip)

		_name_btn = Button.new()
		_name_btn.text = str(layer.get("name", layer.get("id", "")))
		_name_btn.flat = true
		_name_btn.add_theme_font_size_override("font_size", 12)
		if is_active:
			_name_btn.modulate = Color(1.0, 0.85, 0.4)
		add_child(_name_btn)
		# 单击=活动层；双击=重命名（0.28s 内两击算双击）
		_name_btn.button_down.connect(_on_name_pressed)

		var visible_box := CheckBox.new()
		visible_box.button_pressed = bool(layer.get("visible", true))
		visible_box.tooltip_text = "显示/隐藏"
		visible_box.toggled.connect(func(on: bool) -> void:
			panel._document.set_layer_property(str(_layer["id"]), "visible", on))
		add_child(visible_box)

		var locked_box := CheckBox.new()
		locked_box.text = "锁"
		locked_box.button_pressed = bool(layer.get("locked", false))
		locked_box.tooltip_text = "锁定后不可放置/擦除"
		locked_box.toggled.connect(func(on: bool) -> void:
			panel._document.set_layer_property(str(_layer["id"]), "locked", on))
		add_child(locked_box)

		var opacity := HSlider.new()
		opacity.min_value = 0.1
		opacity.max_value = 1.0
		opacity.step = 0.1
		opacity.value = float(layer.get("opacity", 1.0))
		opacity.custom_minimum_size = Vector2(40, 12)
		opacity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		opacity.tooltip_text = "透明度"
		opacity.value_changed.connect(func(v: float) -> void:
			panel._document.set_layer_property(str(_layer["id"]), "opacity", v))
		add_child(opacity)

		var del := Button.new()
		del.text = "×"
		del.tooltip_text = "删除该层（需先清空内容）"
		del.pressed.connect(func() -> void:
			if not panel._document.remove_layer(str(_layer["id"])):
				print("[TileMason] 删除失败：层上有内容或已是最后一层（先清空该层）"))
		add_child(del)

	var _last_press_ms := 0

	func _on_name_pressed() -> void:
		var now := Time.get_ticks_msec()
		if now - _last_press_ms < 280: # 双击 → 重命名
			_start_rename()
			_last_press_ms = 0
		else:
			_last_press_ms = now
			# 单击 → 活动层（延迟到双击窗口结束再生效，避免双击也切层）
			var id := str(_layer["id"])
			_name_btn.set_deferred.call_deferred("modulate", _name_btn.modulate) # no-op 占位
			get_tree().create_timer(0.3).timeout.connect(func() -> void:
				if not _renaming and _last_press_ms != 0:
					_panel.layer_activity_requested.emit(id)
					_last_press_ms = 0)

	func _start_rename() -> void:
		_renaming = true
		_rename_edit = LineEdit.new()
		_rename_edit.text = _name_btn.text
		_rename_edit.custom_minimum_size = Vector2(70, 22)
		_rename_edit.text_submitted.connect(func(new_name: String) -> void:
			_panel._document.set_layer_property(str(_layer["id"]), "name", new_name)
			_end_rename())
		_rename_edit.focus_exited.connect(func() -> void: _end_rename())
		_name_btn.visible = false
		add_child(_rename_edit)
		_rename_edit.grab_focus()
		_rename_edit.select_all()

	func _end_rename() -> void:
		if not _renaming:
			return
		_renaming = false
		if is_instance_valid(_rename_edit):
			_rename_edit.queue_free()
		_name_btn.visible = true

	func _on_grip_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			force_drag({"layer_id": str(_layer["id"]), "from_index": panel_index_to_layer_index()}, _make_preview())

	func _make_preview() -> Control:
		var lab := Label.new()
		lab.text = "↕ " + str(_layer.get("name", ""))
		lab.modulate = Color(1, 1, 1, 0.8)
		return lab

	func panel_index_to_layer_index() -> int:
		## 本行面板序号 → 文档层序（面板倒序：面板第 1 行=文档末层）
		var idx := get_index() - 1 # 减标题行
		var total := _panel._document.layer_count()
		return clampi(total - 1 - idx, 0, total - 1)

	## 行本身也是放置目标：拖到某行=移到该层序（上=更高层级）
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		# 需要行接收拖放：面板级转发由 Godot 冒泡，行实现三件套
		return data is Dictionary and (data as Dictionary).has("layer_id")

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var d := data as Dictionary
		var target := panel_index_to_layer_index()
		_panel._document.move_layer(str(d["layer_id"]), target)
		print("[TileMason] 图层已排序（%s → 序 %d，上=高）" % [str(d["layer_id"]), target])

	func _get_drag_data(_pos: Vector2) -> Variant:
		return null # 拖拽由拖柄 force_drag 发起
