class_name ConnectionRulesViewer
extends AcceptDialog
## 连接规则查看器（P3，design.md §2.2 只读版）：展示素材包声明的自动连接规则
## 数据与渲染分离：build_rules 为纯函数（探针可无头回归），对话框只负责排版
## 措辞按普通桌面软件——不出现引擎术语，方向用箭头示意
## 全部节点代码动态创建（.tscn 精简纪律）

const DIR_ARROWS: Dictionary = {"up": "↑", "right": "→", "down": "↓", "left": "←"}

## setup() 后保存的规则数据（探针与调试可直接读）
var rules: Array = []

## 纯函数：按分类汇总连接规则（只含有声明连接素材的分类）
## 返回 [{category, assets: [{id, name, dirs_text, mask}], resolutions: [{mask, dirs_text, variant_id, variant_name}]}]
## resolutions 覆盖 1..15 中能解析到变体的全部掩码，按掩码升序
static func build_rules(lib: AssetLibrary) -> Array:
	var result := []
	for category in lib.get_categories():
		var assets := []
		for entry in lib.get_assets_by_category(category):
			var asset := entry as Dictionary
			var dirs: Array = asset.get("connections", [])
			if dirs.is_empty():
				continue
			assets.append({
				"id": str(asset["id"]),
				"name": str(asset.get("name", str(asset["id"]).get_file())),
				"dirs_text": dirs_to_text(dirs),
				"mask": AutoConnect.dirs_to_mask(dirs),
			})
		if assets.is_empty():
			continue
		var resolutions := []
		for mask in range(1, 16):
			var variant_id := AutoConnect.pick_variant(lib, str(category), mask)
			if variant_id.is_empty():
				continue
			var variant := lib.get_asset(variant_id)
			resolutions.append({
				"mask": mask,
				"dirs_text": mask_to_text(mask),
				"variant_id": variant_id,
				"variant_name": str(variant.get("name", variant_id.get_file())) if not variant.is_empty() else variant_id.get_file(),
			})
		result.append({"category": str(category), "assets": assets, "resolutions": resolutions})
	return result

## 方向名列表 → 箭头串（未知方向原样保留，便于发现清单写错）
static func dirs_to_text(dirs: Array) -> String:
	var parts := []
	for d in dirs:
		parts.append(str(DIR_ARROWS.get(str(d), str(d))))
	return "".join(parts)

## 掩码 → 箭头串（按 N,E,S,W 位序）
static func mask_to_text(mask: int) -> String:
	return dirs_to_text(AutoConnect.mask_to_dirs(mask))

func setup(lib: AssetLibrary) -> void:
	rules = build_rules(lib)
	title = "连接规则"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	_add_label(box, "说明：同类方块相邻时，按相邻方向组合自动选用变体（↑上 →右 ↓下 ←左）。", 13, 0.7)
	_add_label(box, "精确匹配优先，否则选用多出方向最少的变体；没有可用变体时保持原素材。", 13, 0.7)
	if rules.is_empty():
		_add_label(box, "当前素材包没有声明任何连接规则（道路、墙体素材可在素材包清单中声明 connections）。", 14, 0.9)
	for rule in rules:
		var r := rule as Dictionary
		var cname := str(AssetPanel.CATEGORY_NAMES.get(str(r["category"]), str(r["category"])))
		_add_label(box, "", 8, 1.0) # 分组间距
		_add_label(box, "【%s】声明连接的素材 %d 件" % [cname, (r["assets"] as Array).size()], 15, 1.0)
		for asset in r["assets"]:
			var a := asset as Dictionary
			_add_label(box, "　%s — 连接 %s（掩码 %d）" % [a["name"], a["dirs_text"], a["mask"]], 13, 0.85)
		_add_label(box, "　邻接情况 → 自动选用：%d 种" % (r["resolutions"] as Array).size(), 14, 0.9)
		for res in r["resolutions"]:
			var q := res as Dictionary
			_add_label(box, "　　%s → %s" % [q["dirs_text"], q["variant_name"]], 13, 0.85)
	add_child(scroll)

func _add_label(parent: Node, text: String, size: int, alpha: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate.a = alpha
	parent.add_child(label)
