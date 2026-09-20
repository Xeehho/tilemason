class_name StatusBar
extends PanelContainer
## 底部状态栏：常驻显示当前工具/选中素材/快捷键速记
## 解决「按了 E 不知道橡皮擦是否激活」的可见性问题（用户验收反馈）
## 全部节点代码动态创建

var _label: Label

func setup() -> void:
	custom_minimum_size = Vector2(0, 26)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.modulate.a = 0.85
	margin.add_child(_label)

func set_line(text: String) -> void:
	_label.text = text
