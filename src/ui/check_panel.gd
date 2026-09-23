class_name CheckPanel
extends PanelContainer
## 地图检查页签（UI 重构阶段 C §5.2）：F9 检查结果从纯日志输出升级为左 Dock 页面
## 结果为空显示金色通过提示；有问题逐条橙色警示（颜色之外有文字，§7 验收）
## 全部节点动态创建

signal check_rerun_requested ## 页内「重新检查」按钮：main 重跑 check_all 并回填

var _list_box: VBoxContainer

func setup() -> void:
	for child in get_children(): # 重复 setup 防御
		child.queue_free()
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
	title.text = "地图检查"
	title.add_theme_font_size_override("font_size", 12)
	title.modulate.a = 0.7
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	_show_placeholder()
	_add_rerun_button(box)

func _show_placeholder() -> void:
	var hint := Label.new()
	hint.text = "尚未运行检查（F9 或检查页内按钮）"
	hint.modulate.a = 0.55
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # 不设会把页签 min 宽撑过紧凑档 224
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_list_box.add_child(hint)

## 展示检查结果（issues 来自 MapChecker.check_all：[{message:..,..}]）
func show_results(issues: Array) -> void:
	for child in _list_box.get_children():
		child.queue_free()
	if issues.is_empty():
		var ok := Label.new()
		ok.text = "✓ 通过：道路连通，无建筑堵路"
		ok.modulate = AppTheme.SUCCESS ## 检查通过走 SUCCESS 通道（§3.2：与金色强调分离）
		_list_box.add_child(ok)
		return
	var head := Label.new()
	head.text = "发现 %d 个问题：" % issues.size()
	head.modulate = AppTheme.WARNING
	_list_box.add_child(head)
	for issue in issues:
		var row := Label.new()
		row.text = "⚠ " + str((issue as Dictionary).get("message", ""))
		row.modulate = AppTheme.WARNING
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_list_box.add_child(row)

## 页内重跑按钮（等宽页签下 F9 之外的可见入口）
func _add_rerun_button(box: VBoxContainer) -> void:
	var rerun := Button.new()
	rerun.text = "重新检查"
	rerun.tooltip_text = "重跑地图检查（=F9）"
	rerun.pressed.connect(func() -> void: check_rerun_requested.emit())
	box.add_child(rerun)
