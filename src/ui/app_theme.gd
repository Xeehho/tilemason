class_name AppTheme
extends RefCounted
## 全局统一主题（程序化生成，零外部依赖）
## 决策说明：Godot 4 桌面生态无成熟可信的第三方 UI 库（引入不成熟依赖
## 属外部依赖风险），以自绘 Theme 达到「引入库」的同等效果——统一
## 暗色色板、圆角、间距、hover/selected 态、字号

const BG_PANEL := Color("26262c") ## 面板底（Surface-1）
const BG_DARK := Color("1c1d22") ## 输入框/列表底（Surface-2）
const BTN_NORMAL := Color("34353e") ## 按钮/卡片（Surface-3）
const BTN_HOVER := Color("3f414d")
const BTN_PRESSED := Color("2b2c34")
const DIVIDER := Color("555761") ## 分隔线（UI 重构 §5.6：可见但不抢焦点）
const ACCENT := Color("f0c560") ## 金色强调（选中/焦点/滑柄）
const ACCENT_DIM := Color("8a6f38")
const WARNING := Color("f29a52") ## 遮挡/检查警告
const DANGER := Color("e56b6f") ## 删除/错误
const TEXT := Color("e4e5ea")
const TEXT_DIM := Color("b3b5bf") ## 辅助文字（§5.6：自 9a9ca6 提亮一档）

static func build() -> Theme:
	var t := Theme.new()

	# 面板类
	var panel := _flat(BG_PANEL, 8, 0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# 按钮
	var bn := _flat(BTN_NORMAL, 6, 1)
	bn.border_color = Color(1, 1, 1, 0.06)
	var bh := _flat(BTN_HOVER, 6, 1)
	bh.border_color = ACCENT_DIM
	var bp := _flat(BTN_PRESSED, 6, 1)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("focus", "Button", _empty())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("icon_normal_color", "Button", TEXT)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 13)

	# 输入框
	var le := _flat(BG_DARK, 6, 1)
	le.border_color = Color(1, 1, 1, 0.08)
	var le_focus := _flat(BG_DARK, 6, 1)
	le_focus.border_color = ACCENT_DIM
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_font_size("font_size", "LineEdit", 13)

	# 树（素材面板三层菜单/后续列表）
	t.set_stylebox("panel", "Tree", _flat(Color(BG_PANEL, 0.0), 0, 0))
	var ts := _flat(BG_DARK, 4, 0)
	var tsel := _flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18), 4, 1)
	tsel.border_color = ACCENT_DIM
	t.set_stylebox("selected", "Tree", tsel)
	t.set_stylebox("selected_focus", "Tree", tsel)
	t.set_stylebox("hovered", "Tree", _flat(Color(1, 1, 1, 0.04), 4, 0))
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

	# 滑杆
	var grab := _flat(ACCENT, 4, 0)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	grab.content_margin_top = 3
	grab.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", _flat(ACCENT_DIM, 2, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT, 2, 0))
	t.set_stylebox("slider", "HSlider", _flat(BG_DARK, 2, 0))
	t.set_stylebox("grabber_normal", "HSlider", grab)
	t.set_stylebox("grabber_highlight", "HSlider", grab)

	# 滚动条
	t.set_stylebox("scroll", "VScrollBar", _flat(BG_DARK, 3, 0))
	t.set_stylebox("scroll_focus", "VScrollBar", _flat(BG_DARK, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", _flat(BTN_NORMAL, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(BTN_HOVER, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(BTN_PRESSED, 3, 0))
	t.set_stylebox("scroll", "HScrollBar", _flat(BG_DARK, 3, 0))
	t.set_stylebox("grabber", "HScrollBar", _flat(BTN_NORMAL, 3, 0))
	t.set_stylebox("grabber_highlight", "HScrollBar", _flat(BTN_HOVER, 3, 0))

	# 工具提示
	var tt := _flat(Color("14151a"), 4, 1)
	tt.border_color = ACCENT_DIM
	tt.content_margin_left = 8
	tt.content_margin_right = 8
	tt.content_margin_top = 5
	tt.content_margin_bottom = 5
	t.set_stylebox("panel", "TooltipPanel", tt)
	t.set_color("font_color", "TooltipLabel", TEXT)

	# 页签容器（左 Dock：图层|预制件|检查）——无样式时 tab 条为默认亮色
	# panel 样式零内边距：页面内容自带 margin，容器再加会撑过紧凑档 224（实测踩中）
	var tcp := _flat(BG_PANEL, 0, 0)
	tcp.content_margin_left = 0
	tcp.content_margin_right = 0
	tcp.content_margin_top = 0
	tcp.content_margin_bottom = 0
	t.set_stylebox("panel", "TabContainer", tcp)
	var tab_bg := _flat(BG_DARK, 6, 0)
	tab_bg.corner_radius_bottom_left = 0
	tab_bg.corner_radius_bottom_right = 0
	var tab_sel := _flat(BG_PANEL, 6, 0)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.set_border_width_all(0)
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = ACCENT_DIM
	var tab_hov := _flat(Color("2c2d34"), 6, 0)
	tab_hov.corner_radius_bottom_left = 0
	tab_hov.corner_radius_bottom_right = 0
	t.set_stylebox("tab_unselected", "TabContainer", tab_bg)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_color("font_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_font_size("font_size", "TabContainer", 13)
	t.set_constant("h_separation", "TabContainer", 2)

	# 右键/更多菜单（图层行 ⋯ 菜单、添加层类型选择）
	var pm := _flat(BG_PANEL, 6, 1)
	pm.border_color = DIVIDER
	pm.content_margin_left = 4
	pm.content_margin_right = 4
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", _flat(BTN_HOVER, 4, 0))
	t.set_stylebox("separator", "PopupMenu", _hline(DIVIDER))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", 13)

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
