class_name StatusBar
extends PanelContainer
## 底部状态栏（质感方案 §4.4/P4）：四段——坐标|工具|素材/图层|文件状态
## 文件状态=色点+文字双通道（●已保存/●未保存/●已自动恢复）；
## show_notice 短暂通知（图层删除失败/自动保存完成等，图标色+文字）；? 按钮/F1 帮助
## 全部节点代码动态创建

signal help_requested ## ? 按钮点击：弹出快捷键帮助

var _pos_label: Label
var _tool_label: Label
var _asset_label: Label
var _file_label: Label
var _state_label: Label ## ●+文字（色点与文字双通道表达同一状态）
var _dirty := false
var _restored := false ## 本次会话从自动保存档恢复过（首次手动保存前一直提示）
var _file_text := ""
var _last_pos := ""
var _last_tool := ""
var _last_asset := ""
var _notice_timer: Timer

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
	_asset_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # 富余不足时省略（tooltip 兜底）
	_state_label = _seg(row)
	_state_label.add_theme_font_size_override("font_size", 12)
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
	# 注意：不设 overrun——TRIM_ELLIPSIS 会把 Label 最小宽塌到 1px，HBox 内非展开段
	# 会被饿死成不可见（旧版即此 bug：状态栏只剩素材段和 ?）。仅素材段单独设省略。
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
	_last_pos = pos_text
	_last_tool = tool_text
	_last_asset = asset_text
	if _notice_timer == null or not _notice_timer.time_left > 0.0:
		_pos_label.text = pos_text
		_tool_label.text = tool_text
		_tool_label.modulate = Color(1, 1, 1, 0.85)
	_asset_label.text = asset_text
	_asset_label.tooltip_text = asset_text if asset_text.length() > 20 else ""
	_file_text = file_text
	_file_label.text = file_text
	_file_label.tooltip_text = file_text
	_refresh_file()

## 未保存脏标记（呈现统一走 _refresh_file；不清「自动恢复」标记——refresh_status 高频调用）
func set_dirty(on: bool) -> void:
	_dirty = on
	_refresh_file()

## 手动保存落盘（「自动恢复」提示到此为止）
func mark_saved() -> void:
	_restored = false
	_dirty = false
	_refresh_file()
	flash_saved()

## 启动时从自动保存档恢复（design.md §10 兜底）→ 文件状态提示「已自动恢复」
func mark_restored() -> void:
	_restored = true
	_dirty = false
	_refresh_file()

## 保存完成一瞬的强调反馈（状态点短暂提亮后回落，§P4）
func flash_saved() -> void:
	if _state_label == null:
		return
	var tw := create_tween()
	tw.tween_property(_state_label, "modulate", Color(2.2, 2.2, 2.2), 0.12)
	tw.tween_property(_state_label, "modulate", Color.WHITE, 0.35)

func _refresh_file() -> void:
	if _dirty:
		_state_label.text = "● 未保存"
		_state_label.modulate = AppTheme.WARNING
	elif _restored:
		_state_label.text = "● 已自动恢复"
		_state_label.modulate = AppTheme.ACCENT
	else:
		_state_label.text = "● 已保存"
		_state_label.modulate = AppTheme.SUCCESS

## 短暂状态通知（§P4：错误/警告=图标色+文字双通道；2 秒后自动还原状态栏）
## kind: "warn" | "error" | "ok" | "info"
func show_notice(text: String, kind: String) -> void:
	if _tool_label == null:
		return
	var color := AppTheme.TEXT
	match kind:
		"warn":
			color = AppTheme.WARNING
		"error":
			color = AppTheme.DANGER
		"ok":
			color = AppTheme.SUCCESS
		"info":
			color = AppTheme.TEXT_DIM
	_tool_label.text = "⚠ " + text if kind == "warn" or kind == "error" else text
	_tool_label.modulate = color
	if _notice_timer == null:
		_notice_timer = Timer.new()
		_notice_timer.one_shot = true
		_notice_timer.wait_time = 2.0
		_notice_timer.timeout.connect(func() -> void:
			_pos_label.text = _last_pos
			_tool_label.text = _last_tool
			_tool_label.modulate = Color(1, 1, 1, 0.85))
		add_child(_notice_timer)
	_notice_timer.start()

## 整行覆盖（标签输入模式：只显示输入提示，其余段清空让位）
func set_line(text: String) -> void:
	_pos_label.text = ""
	_tool_label.text = text
	_asset_label.text = ""
	_file_label.text = ""
	_state_label.text = ""
