class_name Hotbar
extends PanelContainer
## 快捷栏（design.md §6.2）：底部 1-9 数字键位，常用素材/工具一键可达
## 1-7 素材位（缩略图+序号），8 橡皮擦，9 吸管提示；全部节点动态创建

signal slot_activated(index: int) ## 点击槽位（数字键由 main 转发同一信号）

const SLOT_SIZE := 52

var _library: AssetLibrary
var _slots: Array = [] # Control
var _bindings: Array = ["", "", "", "", "", "", "", ""] # 1-7 素材 id；8/9 为工具位

func setup(lib: AssetLibrary, bindings: Array) -> void:
	_library = lib
	_bindings = bindings
	for child in get_children():
		child.queue_free()
	_slots.clear()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	for i in 9:
		var slot := _make_slot(i)
		_slots.append(slot)
		row.add_child(slot)

func _make_slot(index: int) -> Control:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.tooltip_text = "快捷键 %d" % (index + 1)
	slot.pressed.connect(func() -> void: slot_activated.emit(index))
	match index:
		7:
			slot.text = "8\n橡皮擦"
			slot.tooltip_text = "8 橡皮擦（E 同）"
		8:
			slot.text = "9\n吸管"
			slot.tooltip_text = "9 吸管（=右键吸取画布素材）"
		_:
			var asset_id: String = _bindings[index] if index < _bindings.size() else ""
			if asset_id.is_empty():
				slot.text = str(index + 1)
			else:
				var asset := _library.get_asset(asset_id)
				if asset.is_empty():
					slot.text = str(index + 1)
				else:
					slot.text = "%d\n%s" % [index + 1, str(asset["name"])]
					var tex := _library.load_texture(asset_id)
					if tex != null:
						slot.icon = tex
						slot.expand_icon = true
						slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	return slot

## 素材位（1-7）绑定的素材 id
func binding_asset_id(index: int) -> String:
	if index >= 7 or index >= _bindings.size():
		return ""
	return str(_bindings[index])
