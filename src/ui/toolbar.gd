class_name Toolbar
extends PanelContainer
## 顶部工具栏（质感方案 §4.1/P1）：左侧品牌+当前文档名；工具按
## 绘制|选择|组织|工作流 分组（轻量组标题+留白+细 Divider）；
## 选中工具显示短标签（未选中纯图标）；工作流组收纳撤销/重做/保存/检查/导出

signal tool_requested(tool_id: String) ## pen/line/rect/bucket/eraser/select/eyedrop/prefab/undo/redo
signal action_requested(action_id: String) ## save/check/export（工作流动作，main 分发到既有函数）

const ICON_DIR := "res://assets/ui/icons"

## 分组工具表（§4.1：绘制/选择/组织/交付四类语义；交付=工作流动作组）
const TOOL_GROUPS: Array = [
	{"title": "绘制", "tools": [
		{"id": "pen", "icon": "pen", "label": "画笔", "hint": "画笔：左键放置/拖刷，Shift 单块"},
		{"id": "line", "icon": "line", "label": "直线", "hint": "直线 L：点起点再点终点"},
		{"id": "rect", "icon": "rect", "label": "矩形", "hint": "矩形填充：Ctrl+左键拖框（+Shift 跳过已有）"},
		{"id": "bucket", "icon": "bucket", "label": "油漆桶", "hint": "油漆桶 G：连通区域填充"},
		{"id": "eraser", "icon": "eraser", "label": "橡皮", "hint": "橡皮擦 E（+Ctrl 只清同款素材）"},
	]},
	{"title": "选择", "tools": [
		{"id": "select", "icon": "select", "label": "选择", "hint": "选择 S：框选/移动/复制"},
		{"id": "eyedrop", "icon": "eyedrop", "label": "吸管", "hint": "吸管（=画布右键）"},
	]},
	{"title": "组织", "tools": [
		{"id": "prefab", "icon": "prefab", "label": "预制件", "hint": "预制件：Ctrl+P 保存 / P 放置"},
	]},
	{"title": "工作流", "tools": [
		{"id": "undo", "icon": "undo", "label": "撤销", "hint": "撤销 Ctrl+Z"},
		{"id": "redo", "icon": "redo", "label": "重做", "hint": "重做 Ctrl+Y"},
		{"id": "save", "icon": "save", "label": "保存", "hint": "保存地图 Ctrl+S（Ctrl+Shift+S 另存）"},
		{"id": "check", "icon": "check", "label": "检查", "hint": "地图检查 F9（道路连通/遮挡）"},
		{"id": "export", "icon": "export", "label": "导出", "hint": "导出可运行场景 Ctrl+E"},
	]},
]

var _buttons := {} # tool_id -> Button（icon 模式，可挂选中背景框）
var _active := "pen"
var _doc_label: Label

func setup() -> void:
	custom_minimum_size = Vector2(0, 46)
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(row)

	# 品牌标识 + 当前文档名（§4.1「专业软件」身份）
	var brand := Label.new()
	brand.text = "TileMason"
	brand.add_theme_font_size_override("font_size", 15)
	brand.modulate = AppTheme.ACCENT
	row.add_child(brand)
	_doc_label = Label.new()
	_doc_label.add_theme_font_size_override("font_size", 12)
	_doc_label.modulate = AppTheme.TEXT_DIM
	_doc_label.custom_minimum_size = Vector2(96, 0) # overrun 会把 min 塌到 1px——给固定最小宽保证可见
	_doc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_doc_label.mouse_filter = Control.MOUSE_FILTER_STOP # 截断时 hover 见完整路径
	row.add_child(_doc_label)
	row.add_child(_group_gap())

	# 工具组（绘制|选择|组织）；工作流组推到右端，与绘制工具视觉分组
	var first := true
	for group in TOOL_GROUPS:
		var g: Dictionary = group
		if str(g["title"]) == "工作流":
			var spring := Control.new()
			spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spring)
		elif not first:
			row.add_child(_group_gap())
		first = false
		var title := Label.new()
		title.text = str(g["title"])
		title.add_theme_font_size_override("font_size", 11)
		title.modulate = Color(AppTheme.TEXT_DIM, 0.72)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(title)
		var title_gap := Control.new()
		title_gap.custom_minimum_size = Vector2(2, 0)
		row.add_child(title_gap)
		for tool in (g["tools"] as Array):
			var t: Dictionary = tool
			var btn := Button.new()
			var tex: Texture2D = load(ICON_DIR + "/" + str(t["icon"]) + ".png")
			if tex != null:
				btn.icon = tex
				btn.expand_icon = true
			btn.custom_minimum_size = Vector2(40, 38)
			btn.tooltip_text = str(t["hint"])
			var tool_id := str(t["id"])
			btn.pressed.connect(func() -> void:
				if tool_id == "save" or tool_id == "check" or tool_id == "export":
					action_requested.emit(tool_id)
				else:
					tool_requested.emit(tool_id))
			_buttons[tool_id] = btn
			row.add_child(btn)
	set_active("pen")

## 组间留白（12px，§P1「分组留白」——不新增 Divider 实线，避免顶栏割碎）
func _group_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	return gap

## 当前文档名（截断省略，hover 见完整路径）
func set_document(path: String) -> void:
	if _doc_label == null:
		return
	_doc_label.text = path.get_file() if not path.is_empty() else "未命名"
	_doc_label.tooltip_text = path

## 选中样式（§P1）：金色低亮底 + 金描边 + 短标签；未选中恢复纯图标常态
func set_active(tool_id: String) -> void:
	_active = tool_id
	for id in _buttons.keys():
		var btn: Button = _buttons[id]
		var info := _tool_info(str(id))
		if str(id) == tool_id and info != null:
			var sel := StyleBoxFlat.new()
			sel.bg_color = AppTheme.ACCENT_SOFT
			sel.border_color = AppTheme.ACCENT
			sel.set_border_width_all(1)
			sel.set_corner_radius_all(AppTheme.RADIUS_MD)
			sel.content_margin_left = 8
			sel.content_margin_right = 8
			btn.add_theme_stylebox_override("normal", sel)
			btn.add_theme_stylebox_override("hover", sel)
			btn.add_theme_stylebox_override("pressed", sel)
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.add_theme_color_override("font_pressed_color", Color.WHITE)
			btn.text = str(info["label"]) # 选中显示短标签（未选中只显示图标）
			btn.modulate = Color.WHITE
		else:
			btn.remove_theme_stylebox_override("normal") # 传 null 会在 4.6 打 rp_style 错误日志
			btn.remove_theme_stylebox_override("hover")
			btn.remove_theme_stylebox_override("pressed")
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_hover_color")
			btn.remove_theme_color_override("font_pressed_color")
			btn.text = ""
			btn.modulate = Color(0.85, 0.87, 0.9)

func _tool_info(tool_id: String) -> Dictionary:
	for group in TOOL_GROUPS:
		for tool in (group as Dictionary)["tools"] as Array:
			if str((tool as Dictionary)["id"]) == tool_id:
				return tool
	return {}
