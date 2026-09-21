class_name Hotbar
extends PanelContainer
## 底部快捷栏 v3（UI 重构阶段 C §5.5）：橡皮常驻独立首格（角标 E）、
## 素材槽 1-7 数字角标（不看 tooltip 即知键位，§7 验收）、右键槽位自定义绑定（持久化）
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

	# 橡皮：常驻独立首格（当前工具高亮由 set_eraser_active 驱动；角标 E）
	var eraser_slot := _make_slot("E")
	row.add_child(eraser_slot)
	_eraser_btn = eraser_slot.get_meta("btn") as TextureButton
	_eraser_btn.texture_normal = load(ERASER_ICON)
	_eraser_btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	_eraser_btn.tooltip_text = "橡皮擦（常驻，=E 键）"
	_eraser_btn.pressed.connect(func() -> void: slot_activated.emit(0))

	# 间距（用户要求：橡皮与后面格子留距离）
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	row.add_child(gap)

	_slot_buttons.clear()
	for i in 7:
		var slot := _make_slot(str(i + 1))
		var btn := slot.get_meta("btn") as TextureButton
		_refresh_slot_icon(btn, i)
		var idx := i + 1
		btn.pressed.connect(func() -> void: slot_activated.emit(idx))
		btn.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
				slot_customized.emit(idx))
		_slot_buttons.append(btn)
		row.add_child(slot)

var _eraser_btn: TextureButton

## 单格：48×48 容器 + 铺满的按钮 + 右上角数字角标（§5.5 槽位显示 1..9 角标）
func _make_slot(badge_text: String) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var btn := TextureButton.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(btn)
	slot.set_meta("btn", btn)
	var badge := Label.new()
	badge.text = badge_text
	badge.add_theme_font_size_override("font_size", 11)
	badge.modulate = Color(1, 1, 1, 0.75)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -14
	badge.offset_top = 0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 3
	bg.content_margin_right = 3
	bg.content_margin_top = 0
	bg.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", bg)
	slot.add_child(badge)
	return slot

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
