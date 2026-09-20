class_name LayerPanel
extends PanelContainer
## 图层面板（最小版，design.md §4）：显示/隐藏 + 锁定/解锁
## 列表按视觉自顶向下（前景在最上）；透明度/独显/排序属 P1
## 全部节点代码动态创建

var _document: MapDocument
var _rows := {} # layer_id -> {visible: CheckBox, locked: CheckBox}

func setup(doc: MapDocument) -> void:
	_document = doc
	custom_minimum_size = Vector2(190, 0)
	for child in get_children(): # 重复 setup（载入新文档）时重建
		child.queue_free()
	_rows.clear()
	_build()
	if not _document.layer_changed.is_connected(_on_layer_changed):
		_document.layer_changed.connect(_on_layer_changed)

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(box)

	var title := Label.new()
	title.text = "图层"
	box.add_child(title)

	# 视觉自顶向下：图层栈倒序展示（栈底 terrain 显示在最下方）
	var layers: Array = _document.get_layers()
	for i in range(layers.size() - 1, -1, -1):
		box.add_child(_make_row(layers[i] as Dictionary))

func _make_row(layer: Dictionary) -> HBoxContainer:
	var layer_id := str(layer["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var visible_box := CheckBox.new()
	visible_box.text = str(layer["name"])
	visible_box.button_pressed = bool(layer.get("visible", true))
	visible_box.tooltip_text = "显示/隐藏该图层"
	visible_box.toggled.connect(func(on: bool) -> void:
		_document.set_layer_property(layer_id, "visible", on))
	row.add_child(visible_box)

	var locked_box := CheckBox.new()
	locked_box.text = "锁"
	locked_box.button_pressed = bool(layer.get("locked", false))
	locked_box.tooltip_text = "锁定后该图层不可放置/擦除（防止误改）"
	locked_box.toggled.connect(func(on: bool) -> void:
		_document.set_layer_property(layer_id, "locked", on))
	row.add_child(locked_box)

	_rows[layer_id] = {"visible": visible_box, "locked": locked_box}
	return row

## 文档层属性被其他入口改动时（如探针/未来菜单）同步勾选状态
func _on_layer_changed(layer_id: String, key: String) -> void:
	if not _rows.has(layer_id) or not _rows[layer_id].has(key):
		return
	var layer := _document.get_layer(layer_id)
	if layer.is_empty():
		return
	(_rows[layer_id][key] as CheckBox).set_pressed_no_signal(bool(layer.get(key, key != "locked")))
