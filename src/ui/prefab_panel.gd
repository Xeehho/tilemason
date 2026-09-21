class_name PrefabPanel
extends PanelContainer
## 预制件面板（design.md §7）：列出已存预制件，选用为当前件（P 放置）/删除
## 全部节点动态创建；左下角停靠（图层面板下方）

signal prefab_chosen(name: String) ## 选用为当前件
signal prefab_deleted(name: String) ## 删除

var _list_box: VBoxContainer
var _rows := {} # name -> HBoxContainer
var _current := "" ## 当前选用件名（高亮）

func setup() -> void:
	custom_minimum_size = Vector2(190, 0)
	for child in get_children():
		child.queue_free()
	_rows.clear()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(box)
	var title := Label.new()
	title.text = "预制件"
	box.add_child(title)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 2)
	box.add_child(_list_box)

## 刷新列表（names 来自 Prefab.list_names；统计从各件快照读取）
func refresh(current: String) -> void:
	_current = current
	for child in _list_box.get_children():
		child.queue_free()
	_rows.clear()
	var names := Prefab.list_names()
	if names.is_empty():
		var hint := Label.new()
		hint.text = "无预制件（框选内容后 Ctrl+P 保存）"
		hint.modulate.a = 0.6
		_list_box.add_child(hint)
		return
	for name in names:
		var row := _make_row(str(name))
		_rows[str(name)] = row
		_list_box.add_child(row)

func _make_row(name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var snap := Prefab.load_prefab(name)
	var tiles: int = (snap.get("tiles", []) as Array).size()
	var objects: int = (snap.get("objects", []) as Array).size()
	var choose := Button.new()
	choose.text = "%s（%d格%d件）" % [name, tiles, objects]
	choose.tooltip_text = "选用为当前件（P 键放置到鼠标处）"
	if name == _current:
		choose.modulate = Color(1.0, 0.85, 0.4) # 当前件高亮
	choose.pressed.connect(func() -> void: prefab_chosen.emit(name))
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(choose)
	var del := Button.new()
	del.text = "×"
	del.tooltip_text = "删除该预制件"
	del.pressed.connect(func() -> void: prefab_deleted.emit(name))
	row.add_child(del)
	return row
