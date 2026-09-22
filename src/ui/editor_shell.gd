class_name EditorShell
extends Control
## 编辑器壳层（UI 重构阶段 A/C，docs/ui-layout-refactor-2026-09-21.md）
## 单容器替代多 CanvasLayer 绝对偏移：顶栏 / 左 Dock / 画布区 / 右 Dock / 快捷栏 / 状态栏
## 阶段 C：左 Dock 改 TabContainer 页签（图层|预制件|检查，方案 §5.2——
## 预制件不再固定占高，图层获得全高）；槽位间补 Divider 色分隔线（§5.6）

signal left_dock_resized(width: int) ## 左 Dock 宽度变化（画布可视区联动用，后续接入）

const TOP_H := 48.0
const HOTBAR_H := 64.0
const STATUS_H := 30.0
const LEFT_W := 250.0
const RIGHT_W := 400.0
const LEFT_W_COMPACT := 224.0 ## 紧凑模式（<1400 宽视口，方案 §4.2：1280×720 左 224/右 320）
const RIGHT_W_COMPACT := 320.0
const COMPACT_BREAK := 1400.0

var top_bar: Control
var left_dock: TabContainer ## 左 Dock 页签容器（阶段 C：图层/预制件/检查三页）
var canvas_host: Control
var right_dock: Control
var hotbar_host: Control
var status_host: Control
var compact := false ## 紧凑模式标记（探针/取证可读）

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
	root_v.add_child(_hdivider(root_v))

	# 中段：左 Dock 页签 | 画布占位 | 右 Dock
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_v.add_child(body)
	_body_ref = body

	left_dock = TabContainer.new() # 左 Dock：图层|预制件|检查（全高页签，无固定高硬切）
	left_dock.custom_minimum_size = Vector2(LEFT_W, 0)
	left_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(left_dock)
	_left_handle = _make_dock_handle("left")

	canvas_host = Control.new() # 画布逻辑占位（实际渲染在 Node2D 层；此控件只预留空间）
	canvas_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(canvas_host)
	_right_handle = _make_dock_handle("right")

	right_dock = PanelContainer.new()
	right_dock.custom_minimum_size = Vector2(RIGHT_W, 0)
	body.add_child(right_dock)

	root_v.add_child(_hdivider(root_v))
	# 快捷栏（独立安全区，与状态栏分离）
	hotbar_host = MarginContainer.new()
	hotbar_host.custom_minimum_size = Vector2(0, HOTBAR_H)
	root_v.add_child(hotbar_host)
	root_v.add_child(_hdivider(root_v))

	# 状态栏（独立安全区）
	status_host = MarginContainer.new()
	status_host.custom_minimum_size = Vector2(0, STATUS_H)
	root_v.add_child(status_host)

var _left_collapsed := false
var _right_collapsed := false
var _left_handle: Button
var _right_handle: Button

## 左右 Dock 折叠手柄（兼作分隔线）：点击整条收起/展开 Dock，画布自动吃满腾出空间
func _make_dock_handle(side: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(14, 0)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.flat = true
	b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = ("收起/展开左侧栏（[ 键）" if side == "left" else "收起/展开右侧栏（] 键）")
	b.text = "⟨" if side == "left" else "⟩"
	b.pressed.connect(func() -> void:
		toggle_dock(side))
	_body_ref.add_child(b) # setup 中在 body 建好后调用
	return b

var _body_ref: Control

## 折叠/展开（side="left"/"right"）；信号宽度变化供相机取景联动
func toggle_dock(side: String) -> void:
	if side == "left":
		_left_collapsed = not _left_collapsed
		left_dock.visible = not _left_collapsed
		if _left_handle != null:
			_left_handle.text = "⟩" if _left_collapsed else "⟨"
		left_dock_resized.emit(0.0 if _left_collapsed else left_dock.custom_minimum_size.x)
	else:
		_right_collapsed = not _right_collapsed
		right_dock.visible = not _right_collapsed
		if _right_handle != null:
			_right_handle.text = "⟨" if _right_collapsed else "⟩"
		left_dock_resized.emit(0.0 if _right_collapsed else right_dock.custom_minimum_size.x)
	print("[TileMason] %s侧栏：%s" % [side, "已收起（再点手柄或快捷键展开）" if (side == "left" and _left_collapsed) or (side == "right" and _right_collapsed) else "已展开"])

func left_dock_collapsed() -> bool:
	return _left_collapsed

func right_dock_collapsed() -> bool:
	return _right_collapsed

## 紧凑模式（1280×720 档）动态跟踪视口宽：headless 启动早期视口仅 64px、
## 窗口运行中用户也会拖拽尺寸——size_changed 驱动而非 _ready 一次判定
func _ready() -> void:
	get_viewport().size_changed.connect(_update_compact)
	_update_compact()

func _update_compact() -> void:
	var vw := get_viewport_rect().size.x
	var want := vw >= 800.0 and vw < COMPACT_BREAK # 下限挡 headless 启动期的 64px 假视口
	if want == compact:
		return
	compact = want
	if compact:
		left_dock.custom_minimum_size = Vector2(LEFT_W_COMPACT, 0)
		right_dock.custom_minimum_size = Vector2(RIGHT_W_COMPACT, 0)
	else:
		left_dock.custom_minimum_size = Vector2(LEFT_W, 0)
		right_dock.custom_minimum_size = Vector2(RIGHT_W, 0)
	print("[TileMason] 壳层%s模式：%dpx 视口（左 %.0f / 右 %.0f）" % [
		"紧凑" if compact else "标准", int(vw),
		LEFT_W_COMPACT if compact else LEFT_W, RIGHT_W_COMPACT if compact else RIGHT_W])

## 把业务面板装进对应槽（保留面板自身信号与业务方法）
func mount_top(panel: Control) -> void:
	_reparent(panel, top_bar)

## 左 Dock 页签挂载（幂等：已在页签内的面板不换位，避免文档重载打乱页序）
func mount_left_tab(panel: Control, title: String) -> void:
	if panel.get_parent() != left_dock:
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		left_dock.add_child(panel)
	_clear_anchors(panel)
	left_dock.set_tab_title(panel.get_index(), title)

## 按标题切到左 Dock 指定页（检查结果产出后自动跳「检查」页）
func select_left_tab(title: String) -> void:
	for i in left_dock.get_tab_count():
		if left_dock.get_tab_title(i) == title:
			left_dock.current_tab = i
			return

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
	_clear_anchors(panel)

## 进入容器布局后清掉旧的锚点/偏移残留（原 CanvasLayer 绝对定位遗留）
func _clear_anchors(panel: Control) -> void:
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0

## 横向分隔线（顶栏/快捷栏/状态栏之间，§5.6 Divider）
func _hdivider(_parent: Control) -> ColorRect:
	var line := ColorRect.new()
	line.color = AppTheme.DIVIDER
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

## 画布可视矩形（世界坐标近似：壳层中央区，供相机限制/取景参考）
func canvas_rect_global() -> Rect2:
	var r := canvas_host.get_global_rect()
	return r
