class_name Toolbar
extends PanelContainer
## 顶部工具栏（用户验收反馈的图标化正解）：当前工具常驻高亮，一眼可见
## 点击=切换对应模式（复用 main 既有切换函数）；全部节点动态创建

signal tool_requested(tool_id: String) ## pen/line/rect/bucket/eraser/select

const ICON_DIR := "res://assets/ui/icons"
const TOOLS: Array = [
	{"id": "pen", "icon": "pen", "hint": "画笔（左键放置/拖刷，Shift 单块）"},
	{"id": "line", "icon": "line", "hint": "直线 L（点起点再点终点）"},
	{"id": "rect", "icon": "rect", "hint": "矩形填充 Ctrl+左键拖框"},
	{"id": "bucket", "icon": "bucket", "hint": "油漆桶 G（连通区域填充）"},
	{"id": "eraser", "icon": "eraser", "hint": "橡皮擦 E（+Ctrl 只清同款素材）"},
	{"id": "select", "icon": "select", "hint": "选择 S（框选/移动/复制）"},
	{"id": "eyedrop", "icon": "eyedrop", "hint": "吸管（=画布右键）"},
	{"id": "prefab", "icon": "prefab", "hint": "预制件（Ctrl+P 保存 / P 放置）"},
]

var _buttons := {} # tool_id -> TextureButton
var _active := "pen"

func setup() -> void:
	custom_minimum_size = Vector2(0, 44)
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(row)
	for tool in TOOLS:
		var t: Dictionary = tool
		var btn := TextureButton.new()
		var tex: Texture2D = load(ICON_DIR + "/" + str(t["icon"]) + ".png")
		if tex != null:
			btn.texture_normal = tex
			btn.custom_minimum_size = Vector2(36, 36)
			btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
		else:
			btn.custom_minimum_size = Vector2(36, 36) # 图标缺失兜底：空白占位
		btn.tooltip_text = str(t["hint"])
		btn.pressed.connect(func() -> void: tool_requested.emit(str(t["id"])))
		_buttons[str(t["id"])] = btn
		row.add_child(btn)
	set_active("pen")

## 当前工具高亮（其余恢复常态）
func set_active(tool_id: String) -> void:
	_active = tool_id
	for id in _buttons.keys():
		var btn: TextureButton = _buttons[id]
		btn.modulate = Color(1.0, 0.85, 0.4) if str(id) == tool_id else Color.WHITE
