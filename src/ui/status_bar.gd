class_name StatusBar
extends PanelContainer
## 底部状态栏（UI 重构阶段 B §5.5）：拆四段——坐标|工具|素材|文件+脏标记
## 快捷键速记不再常驻：右侧 ? 按钮/F1 弹帮助浮层（main._show_shortcut_help）
## 全部节点代码动态创建

signal help_requested ## ? 按钮点击：弹出快捷键帮助

var _pos_label: Label
var _tool_label: Label
var _asset_label: Label
var _file_label: Label
var _dirty := false
var _file_text := ""

func setup() -> void:
	custom_minimum_size = Vector2(0, 26)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 6)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(row)

	_pos_label = _seg(row)
	row.add_child(_sep())
	_tool_label = _seg(row)
	row.add_child(_sep())
	_asset_label = _seg(row)
	_asset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL # 素材段吃掉中段富余
	_file_label = _seg(row)

	var help := Button.new()
	help.text = "?"
	help.tooltip_text = "快捷键帮助（F1）"
	help.custom_minimum_size = Vector2(26, 20)
	help.pressed.connect(func() -> void: help_requested.emit())
	row.add_child(help)

func _seg(row: HBoxContainer) -> Label:
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 13)
	lab.modulate.a = 0.85
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # 长文本省略+tooltip 兜底
	row.add_child(lab)
	return lab

func _sep() -> Control:
	var s := Label.new()
	s.text = "｜"
	s.add_theme_font_size_override("font_size", 13)
	s.modulate = Color(1, 1, 1, 0.22)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

## 四段状态刷新（refresh_status 组好各段文本后调用）
func set_segments(pos_text: String, tool_text: String, asset_text: String, file_text: String) -> void:
	_pos_label.text = pos_text
	_tool_label.text = tool_text
	_asset_label.text = asset_text
	_asset_label.tooltip_text = asset_text if asset_text.length() > 20 else ""
	_file_text = file_text
	_refresh_file()

## 未保存脏标记（保存完成后清除；● 只挂文件段尾，不占独立段）
func set_dirty(on: bool) -> void:
	_dirty = on
	_refresh_file()

func _refresh_file() -> void:
	_file_label.text = _file_text + (" ●未保存" if _dirty else "")

## 整行覆盖（标签输入模式：只显示输入提示，其余段清空让位）
func set_line(text: String) -> void:
	_pos_label.text = ""
	_tool_label.text = text
	_asset_label.text = ""
	_file_label.text = ""
