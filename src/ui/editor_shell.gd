class_name EditorShell
extends Control
## 编辑器壳层（UI 重构阶段 A，docs/ui-layout-refactor-2026-09-21.md）
## 单容器替代多 CanvasLayer 绝对偏移：顶栏 / 左 Dock / 画布区 / 右 Dock / 快捷栏 / 状态栏
## 各槽位由 VBox+HBox 布局管理，互不覆盖；业务面板保留原信号接口只换父节点

signal left_dock_resized(width: int) ## 左 Dock 宽度变化（画布可视区联动用，后续接入）

const TOP_H := 48.0
const HOTBAR_H := 64.0
const STATUS_H := 30.0
const LEFT_W := 250.0
const RIGHT_W := 400.0
const GAP := 2.0 ## 槽位间分隔线宽

var top_bar: Control
var left_dock: Control
var canvas_host: Control
var right_dock: Control
var hotbar_host: Control
var status_host: Control

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # 壳层不吞画布输入，实体面板自行拦截

	var root_v := VBoxContainer.new()
	root_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_v.add_theme_constant_override("separation", 0)
	root_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_v)

	# 顶栏（全宽安全区）
	top_bar = MarginContainer.new()
	top_bar.custom_minimum_size = Vector2(0, TOP_H)
	root_v.add_child(top_bar)

	# 中段：左 Dock | 画布占位 | 右 Dock
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_v.add_child(body)

	left_dock = VSplitContainer.new() # 竖向分栏：图层/预制件比例可调
	left_dock.custom_minimum_size = Vector2(LEFT_W, 0)
	body.add_child(left_dock)

	canvas_host = Control.new() # 画布逻辑占位（实际渲染在 Node2D 层；此控件只预留空间）
	canvas_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(canvas_host)

	right_dock = PanelContainer.new()
	right_dock.custom_minimum_size = Vector2(RIGHT_W, 0)
	body.add_child(right_dock)

	# 快捷栏（独立安全区，与状态栏分离）
	hotbar_host = MarginContainer.new()
	hotbar_host.custom_minimum_size = Vector2(0, HOTBAR_H)
	root_v.add_child(hotbar_host)

	# 状态栏（独立安全区）
	status_host = MarginContainer.new()
	status_host.custom_minimum_size = Vector2(0, STATUS_H)
	root_v.add_child(status_host)

## 把业务面板装进对应槽（保留面板自身信号与业务方法）
func mount_top(panel: Control) -> void:
	_reparent(panel, top_bar)

func mount_left_top(panel: Control) -> void:
	(left_dock as SplitContainer).split_percent_max = 1e9 # 占满可用
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reparent(panel, left_dock)

func mount_left_bottom(panel: Control) -> void:
	panel.custom_minimum_size = Vector2(0, 180)
	_reparent(panel, left_dock)

func mount_right(panel: Control) -> void:
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reparent(panel, right_dock)

func mount_hotbar(panel: Control) -> void:
	_reparent(panel, hotbar_host)

func mount_status(panel: Control) -> void:
	_reparent(panel, status_host)

func _reparent(panel: Control, host: Control) -> void:
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	host.add_child(panel)
	# 进入容器布局后清掉旧的锚点/偏移残留（原 CanvasLayer 绝对定位遗留）
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0

## 画布可视矩形（世界坐标近似：壳层中央区，供相机限制/取景参考）
func canvas_rect_global() -> Rect2:
	var r := canvas_host.get_global_rect()
	return r
