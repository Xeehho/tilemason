class_name EditorCamera
extends Camera2D
## 编辑相机：整数倍显示缩放（只影响视图，不改地图数据）+ 画布平移
## 平移手势：按住中键拖拽，或按住空格后左键拖拽

const ZOOM_STEPS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const DEFAULT_ZOOM_IDX := 2 ## 1.0（100%）

var _zoom_idx := DEFAULT_ZOOM_IDX
var _pan_buttons := {} ## 当前触发平移的鼠标键

func _ready() -> void:
	zoom = Vector2.ONE * ZOOM_STEPS[_zoom_idx]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _is_pan_button(mb.button_index):
			if mb.pressed:
				_pan_buttons[mb.button_index] = true
			else:
				_pan_buttons.erase(mb.button_index)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_step_zoom(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_step_zoom(-1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _pan_buttons.is_empty():
			position -= mm.relative / zoom.x

func _is_pan_button(btn: MouseButton) -> bool:
	return btn == MOUSE_BUTTON_MIDDLE \
		or (btn == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE))

func _step_zoom(dir: int) -> void:
	_zoom_idx = clampi(_zoom_idx + dir, 0, ZOOM_STEPS.size() - 1)
	zoom = Vector2.ONE * ZOOM_STEPS[_zoom_idx]
