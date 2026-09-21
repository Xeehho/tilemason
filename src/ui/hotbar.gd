class_name Hotbar
extends PanelContainer
## 底部快捷栏 v2（用户反馈 #4）：橡皮常驻独立首格（与素材槽留间距）、
## 素材槽纯图标（无数字无文字，tooltip 提示）、右键槽位自定义绑定（持久化）
## 布局：[橡皮（常驻）] | 间距 | [槽1]..[槽7]

signal slot_activated(index: int) ## 0=橡皮；1-7=素材槽
signal slot_customized(index: int) ## 右键素材槽：绑定当前选中素材/空选清空（main 处理+持久化）

const ERASER_ICON := "res://assets/ui/icons/eraser.png"
const SLOT_SIZE := 48

var _library: AssetLibrary
var _bindings: Array = ["", "", "", "", "", "", ""] ## 槽 1-7 的素材 id
var _slot_buttons: Array = [] ## 槽 1-7 的按钮

func setup(lib: AssetLibrary, bindings: Array) -> void:
	_library = lib
	_bindings = bindings.duplicate()
	while _bindings.size() < 7:
		_bindings.append("")
	for child in get_children():
		child.queue_free()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(row)

	# 橡皮：常驻独立首格（当前工具高亮由 set_active 驱动）
	var eraser := _icon_button(ERASER_ICON)
	eraser.tooltip_text = "橡皮擦（常驻，=E 键）"
	eraser.pressed.connect(func() -> void: slot_activated.emit(0))
	row.add_child(eraser)
	_eraser_btn = eraser

	# 间距（用户要求：橡皮与后面格子留距离）
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	row.add_child(gap)

	_slot_buttons.clear()
	for i in 7:
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		btn.tooltip_text = "右键：绑定当前选中素材\n左键：选用"
		_refresh_slot_icon(btn, i)
		var idx := i + 1
		btn.pressed.connect(func() -> void: slot_activated.emit(idx))
		btn.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
				slot_customized.emit(idx))
		_slot_buttons.append(btn)
		row.add_child(btn)

var _eraser_btn: TextureButton

func _icon_button(icon_path: String) -> TextureButton:
	var btn := TextureButton.new()
	btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var tex: Texture2D = load(icon_path)
	if tex != null:
		btn.texture_normal = tex
		btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	return btn

## 刷新某槽图标（按绑定；空槽显示淡色空框占位）
func _refresh_slot_icon(btn: TextureButton, i: int) -> void:
	var asset_id: String = _bindings[i] if i < _bindings.size() else ""
	if asset_id.is_empty():
		btn.texture_normal = null
		btn.modulate = Color(1, 1, 1, 0.35)
		return
	var tex := _library.load_texture(asset_id)
	btn.texture_normal = tex
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.modulate = Color.WHITE
	var asset := _library.get_asset(asset_id)
	if not asset.is_empty():
		btn.tooltip_text = "%s\n右键换绑：先选中新素材再右键此格；右键空选=清空" % str(asset["name"])

## 重设绑定并刷新全部槽位
func set_bindings(bindings: Array) -> void:
	_bindings = bindings.duplicate()
	while _bindings.size() < 7:
		_bindings.append("")
	for i in 7:
		_refresh_slot_icon(_slot_buttons[i], i)

## 当前绑定（持久化用）
func bindings() -> Array:
	return _bindings.duplicate()

## 橡皮格高亮开关（当前工具是否橡皮）
func set_eraser_active(on: bool) -> void:
	if _eraser_btn != null:
		_eraser_btn.modulate = Color(1.0, 0.85, 0.4) if on else Color.WHITE
