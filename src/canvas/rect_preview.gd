class_name RectPreview
extends Node2D
## 矩形工具预览：半透明填充 + 白色描边（像素坐标）

var rect := Rect2()

func _draw() -> void:
	if rect.size <= Vector2.ONE:
		return
	draw_rect(rect, Color(1, 1, 1, 0.08), true)
	draw_rect(rect, Color(1, 1, 1, 0.8), false, 1.0)

func set_rect_px(r: Rect2) -> void:
	if r != rect:
		rect = r
		queue_redraw()

func clear_rect() -> void:
	set_rect_px(Rect2())
