class_name AppTheme
extends RefCounted
## 全局统一主题（程序化生成，零外部依赖）
## 决策说明：Godot 4 桌面生态无成熟可信的第三方 UI 库（引入不成熟依赖
## 属外部依赖风险），以自绘 Theme 达到「引入库」的同等效果——统一
## 暗色色板、圆角、间距、hover/pressed/disabled/active 四态、字号
## 质感方案（docs/ui-polish-plan-2026-09-22.md §3）：四层可辨识深色表面，
## 靠亮度差 + 1px Divider + 内边距分层，不用大面积渐变/发光

## —— 色彩 Token（§3.2，仅作用于 UI 控件；不改变画布素材颜色与最近邻显示）——
const SURFACE_0 := Color("17181d") ## 最外层/底部安全区
const SURFACE_1 := Color("22232a") ## 一级 Dock 背景
const SURFACE_2 := Color("2a2b33") ## 输入框、分类列表、浮层内部
const SURFACE_3 := Color("343640") ## 按钮、卡片、悬停区域
const SURFACE_HOVER := Color("3c3e49") ## 按钮/卡片悬停抬升
const SURFACE_PRESSED := Color("2e3038") ## 按压
const SURFACE_ACTIVE := Color("3c3a32") ## 活动行/选中卡片的低亮背景（暖调）
const DIVIDER := Color("555761") ## 1px 结构分隔线
const TEXT := Color("e6e7eb") ## 主文本
const TEXT_DIM := Color("aeb1bb") ## 辅助文本和尺寸信息
const ACCENT := Color("e7b950") ## 当前工具、焦点、主按钮
const ACCENT_SOFT := Color("5d4c2c") ## 金色低亮背景（选中底）
const ACCENT_DIM := Color("8a6f38") ## 金色暗边框
const WARNING := Color("e99a52") ## 遮挡、检查警告
const DANGER := Color("d96b73") ## 删除、错误
const SUCCESS := Color("73c28a") ## 已保存、检查通过

## —— 间距与尺寸 Token（§3.3，4px 基础单位；只作用于编辑器控件）——
const SPACE_1 := 4  ## 图标与文字间距
const SPACE_2 := 8  ## 控件内部间距
const SPACE_3 := 12 ## 卡片/分组间距
const SPACE_4 := 16 ## Dock 内边距
const CONTROL_H := 32 ## 普通点击控件最小高度
const TOOL_H := 38 ## 顶部工具按钮高度
const RADIUS_SM := 4 ## 输入框、卡片
const RADIUS_MD := 6 ## 面板按钮、活动卡片

static func build() -> Theme:
	var t := Theme.new()

	# 面板类（Surface-1）
	var panel := _flat(SURFACE_1, RADIUS_MD, 0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# 按钮（四态：normal/hover/pressed/disabled；active 态由各面板叠加 override）
	var bn := _flat(SURFACE_3, RADIUS_MD, 1)
	bn.border_color = Color(1, 1, 1, 0.06)
	bn.content_margin_left = 10
	bn.content_margin_right = 10
	bn.content_margin_top = 4
	bn.content_margin_bottom = 4
	var bh := _flat(SURFACE_HOVER, RADIUS_MD, 1)
	bh.border_color = ACCENT_DIM
	var bp := _flat(SURFACE_PRESSED, RADIUS_MD, 1)
	var bd := _flat(SURFACE_0, RADIUS_MD, 1)
	bd.border_color = Color(1, 1, 1, 0.04)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", _empty())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.5))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("icon_normal_color", "Button", TEXT)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(TEXT_DIM, 0.5))
	t.set_font_size("font_size", "Button", 13)

	# 输入框（Surface-2 + 明确焦点边框）
	var le := _flat(SURFACE_2, RADIUS_SM, 1)
	le.border_color = Color(1, 1, 1, 0.08)
	le.content_margin_left = 8
	le.content_margin_right = 8
	le.content_margin_top = 4
	le.content_margin_bottom = 4
	var le_focus := _flat(SURFACE_2, RADIUS_SM, 1)
	le_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_font_size("font_size", "LineEdit", 13)

	# 树（素材面板分类/分组）
	t.set_stylebox("panel", "Tree", _flat(Color(SURFACE_1, 0.0), 0, 0))
	var ts := _flat(SURFACE_2, RADIUS_SM, 0)
	ts.content_margin_left = 8
	ts.content_margin_right = 8
	var tsel := _flat(ACCENT_SOFT, RADIUS_SM, 1)
	tsel.border_color = ACCENT_DIM
	tsel.content_margin_left = 8
	tsel.content_margin_right = 8
	t.set_stylebox("selected", "Tree", tsel)
	t.set_stylebox("selected_focus", "Tree", tsel)
	t.set_stylebox("hovered", "Tree", _flat(Color(1, 1, 1, 0.04), RADIUS_SM, 0))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_font_size("font_size", "Tree", 13)
	t.set_constant("item_margin", "Tree", 8)
	t.set_constant("inner_item_margin_bottom", "Tree", 3)
	t.set_constant("inner_item_margin_top", "Tree", 3)
	# 展开箭头
	var arrow := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 10:
			if absi(x - (9 - y)) <= 2 and y >= 1 and y <= 8: # ▸ 箭头形状
				arrow.set_pixel(x, y, TEXT_DIM)
	t.set_icon("arrow", "Tree", ImageTexture.create_from_image(arrow))
	t.set_icon("arrow_collapsed", "Tree", ImageTexture.create_from_image(_rotate90(arrow)))

	# 复选框文字
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_font_size("font_size", "CheckBox", 13)

	# 标签
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 13)

	# 滑杆（轨道/滑块统一排版，§P3）
	var grab := _flat(ACCENT, RADIUS_SM, 0)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	grab.content_margin_top = 3
	grab.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", _flat(ACCENT_DIM, 2, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT, 2, 0))
	t.set_stylebox("slider", "HSlider", _flat(SURFACE_2, 2, 0))
	t.set_stylebox("grabber_normal", "HSlider", grab)
	t.set_stylebox("grabber_highlight", "HSlider", grab)

	# 滚动条
	t.set_stylebox("scroll", "VScrollBar", _flat(SURFACE_2, 3, 0))
	t.set_stylebox("scroll_focus", "VScrollBar", _flat(SURFACE_2, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", _flat(SURFACE_3, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(SURFACE_HOVER, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(SURFACE_PRESSED, 3, 0))
	t.set_stylebox("scroll", "HScrollBar", _flat(SURFACE_2, 3, 0))
	t.set_stylebox("grabber", "HScrollBar", _flat(SURFACE_3, 3, 0))
	t.set_stylebox("grabber_highlight", "HScrollBar", _flat(SURFACE_HOVER, 3, 0))

	# 工具提示（Surface-0 底）
	var tt := _flat(SURFACE_0, RADIUS_SM, 1)
	tt.border_color = ACCENT_DIM
	tt.content_margin_left = 8
	tt.content_margin_right = 8
	tt.content_margin_top = 5
	tt.content_margin_bottom = 5
	t.set_stylebox("panel", "TooltipPanel", tt)
	t.set_color("font_color", "TooltipLabel", TEXT)

	# 页签容器（左 Dock：图层|预制件|检查）——无样式时 tab 条为默认亮色
	# panel 样式零内边距：页面内容自带 margin，容器再加会撑过紧凑档 224（实测踩中）
	var tcp := _flat(SURFACE_1, 0, 0)
	tcp.content_margin_left = 0
	tcp.content_margin_right = 0
	tcp.content_margin_top = 0
	tcp.content_margin_bottom = 0
	t.set_stylebox("panel", "TabContainer", tcp)
	var tab_bg := _flat(SURFACE_0, RADIUS_MD, 0)
	tab_bg.corner_radius_bottom_left = 0
	tab_bg.corner_radius_bottom_right = 0
	var tab_sel := _flat(SURFACE_1, RADIUS_MD, 0)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.set_border_width_all(0)
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = ACCENT
	var tab_hov := _flat(Color("1f2026"), RADIUS_MD, 0)
	tab_hov.corner_radius_bottom_left = 0
	tab_hov.corner_radius_bottom_right = 0
	# 页签内边距放宽（用户反馈「三个 tab 连接太紧密」：侧 12/上下 5，留出呼吸感）
	for sb in [tab_bg, tab_sel, tab_hov]:
		(sb as StyleBoxFlat).content_margin_left = 12
		(sb as StyleBoxFlat).content_margin_right = 12
		(sb as StyleBoxFlat).content_margin_top = 5
		(sb as StyleBoxFlat).content_margin_bottom = 5
	t.set_stylebox("tab_unselected", "TabContainer", tab_bg)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_color("font_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_font_size("font_size", "TabContainer", 13)
	t.set_constant("h_separation", "TabContainer", 8)

	# 右键/更多菜单（浮层内部=Surface-2，§P4 统一层级）
	var pm := _flat(SURFACE_2, RADIUS_MD, 1)
	pm.border_color = DIVIDER
	pm.content_margin_left = 4
	pm.content_margin_right = 4
	pm.content_margin_top = 4
	pm.content_margin_bottom = 4
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", _flat(SURFACE_3, RADIUS_SM, 0))
	t.set_stylebox("separator", "PopupMenu", _hline(DIVIDER))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", 13)

	# 嵌入式窗口（F1 帮助等 AcceptDialog）：Surface-1 底 + Divider 边 + 标题文字
	var win := _flat(SURFACE_1, RADIUS_MD, 1)
	win.border_color = DIVIDER
	win.content_margin_left = 12
	win.content_margin_right = 12
	win.content_margin_top = 6
	win.content_margin_bottom = 10
	t.set_stylebox("embedded_border", "Window", win)
	t.set_color("title_color", "Window", TEXT)
	t.set_color("title_outline_modulate", "Window", Color(0, 0, 0, 0.5))
	t.set_font_size("title_font_size", "Window", 14)

	return t

static func _flat(bg: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = Color(1, 1, 1, 0.08)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

static func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

## 1px 横分隔线（PopupMenu separator / 壳层槽位分隔）
static func _hline(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	return sb

static func _rotate90(img: Image) -> Image:
	var out := Image.create(img.get_height(), img.get_width(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			out.set_pixel(y, x, img.get_pixel(x, y))
	return out
