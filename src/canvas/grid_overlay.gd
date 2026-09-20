class_name GridOverlay
extends Node2D
## 网格覆盖层：绘制正式地图网格（grid_size）与主网格线
## 视图（相机移动/缩放/窗口变化）不变则不重绘

const COLOR_MINOR := Color(1, 1, 1, 0.07)
const COLOR_MAJOR := Color(1, 1, 1, 0.16)

var grid_size := 16 ## 正式地图网格（px）
var major_every := 8 ## 每 N 格画一条主网格线

var _camera: Camera2D
var _last_view := Rect2()

func _ready() -> void:
	_camera = get_viewport().get_camera_2d()
	z_index = 100 # 覆盖在后续地图图层之上

func _process(_delta: float) -> void:
	var view := _view_rect()
	if view != _last_view:
		_last_view = view
		queue_redraw()

func _draw() -> void:
	if _camera == null or _last_view.size == Vector2.ZERO:
		return
	var line_w := 1.0 / maxf(_camera.zoom.x, 0.001) # 屏幕上恒为 1px 细线
	var draw_minor := grid_size * _camera.zoom.x >= 4.0 # 过密时只画主网格，防止糊成一团
	var major_step := grid_size * major_every

	var x0 := floorf(_last_view.position.x / grid_size) * grid_size
	var y0 := floorf(_last_view.position.y / grid_size) * grid_size
	var x1 := _last_view.end.x
	var y1 := _last_view.end.y

	var x := x0
	while x <= x1:
		var x_major := is_zero_approx(fmod(x, major_step))
		if x_major or draw_minor:
			draw_line(Vector2(x, y0), Vector2(x, y1), COLOR_MAJOR if x_major else COLOR_MINOR, line_w)
		x += grid_size
	var y := y0
	while y <= y1:
		var y_major := is_zero_approx(fmod(y, major_step))
		if y_major or draw_minor:
			draw_line(Vector2(x0, y), Vector2(x1, y), COLOR_MAJOR if y_major else COLOR_MINOR, line_w)
		y += grid_size

func _view_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var half := get_viewport_rect().size / _camera.zoom / 2.0
	return Rect2(_camera.position - half, half * 2.0)
