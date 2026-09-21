extends SceneTree
## [TileMason] 连接规则查看器探针：build_rules 纯函数 + 弹窗渲染
## 运行：godot --headless --path . --script res://probes/connection_rules_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

const FIXTURE_ROOT := "user://crv" # 目录名=包 id，素材 id 前缀须为 crv/

func _init() -> void:
	print("[TileMason] 连接规则查看器探针开始")
	_setup_fixtures()
	var lib := AssetLibrary.new()
	lib.scan([FIXTURE_ROOT])
	var rules: Array = ConnectionRulesViewer.build_rules(lib)
	_test_categories(rules)
	_test_assets(rules)
	_test_resolutions(rules)
	_test_text_helpers()
	_test_dialog(lib)
	_test_empty_library()
	_cleanup()
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

## 只有声明了 connections 的分类才入表；ground（无声明）不得出现
func _test_categories(rules: Array) -> void:
	var names := []
	for r in rules:
		names.append(str((r as Dictionary)["category"]))
	_check(names == ["road", "wall"], "分类只含声明连接的 road/wall（%s）" % str(names))

func _test_assets(rules: Array) -> void:
	var road: Dictionary
	var wall: Dictionary
	for r in rules:
		if str((r as Dictionary)["category"]) == "road":
			road = r
		elif str((r as Dictionary)["category"]) == "wall":
			wall = r
	_check((road["assets"] as Array).size() == 4, "道路 4 件声明")
	_check((wall["assets"] as Array).size() == 1, "墙体 1 件声明")
	var by_name := {}
	for a in road["assets"]:
		by_name[str((a as Dictionary)["name"])] = a
	_check(str((by_name["road_straight"] as Dictionary)["dirs_text"]) == "←→", "直线 ←→")
	_check(str((by_name["road_corner"] as Dictionary)["dirs_text"]) == "→↓", "弯道 →↓")
	_check(str((by_name["road_cross"] as Dictionary)["dirs_text"]) == "↑→↓←", "十字 ↑→↓←")
	_check(int((by_name["road_end"] as Dictionary)["mask"]) == 1, "端头掩码 1")
	_check(int((by_name["road_straight"] as Dictionary)["mask"]) == 10, "直线掩码 10")

## 掩码解析表：道路全 15 种可解析（十字兜底）；墙体只有 ⊆←→ 的 3 种
func _test_resolutions(rules: Array) -> void:
	var road: Dictionary
	var wall: Dictionary
	for r in rules:
		if str((r as Dictionary)["category"]) == "road":
			road = r
		elif str((r as Dictionary)["category"]) == "wall":
			wall = r
	var road_res := road["resolutions"] as Array
	_check(road_res.size() == 15, "道路 15 种邻接全部可解析（十字兜底）")
	var wall_res := wall["resolutions"] as Array
	_check(wall_res.size() == 3, "墙体仅 3 种可解析（←→子集）")
	var road_by_mask := {}
	for res in road_res:
		road_by_mask[int((res as Dictionary)["mask"])] = res
	_check(str((road_by_mask[10] as Dictionary)["variant_id"]) == "crv/tiles/road_straight.png", "掩码10 精确取直线")
	_check(str((road_by_mask[6] as Dictionary)["variant_id"]) == "crv/tiles/road_corner.png", "掩码6 精确取弯道")
	_check(str((road_by_mask[15] as Dictionary)["variant_id"]) == "crv/tiles/road_cross.png", "掩码15 取十字")
	_check(str((road_by_mask[1] as Dictionary)["variant_id"]) == "crv/tiles/road_end.png", "掩码1 取端头")
	_check(str((road_by_mask[5] as Dictionary)["variant_id"]) == "crv/tiles/road_cross.png", "掩码5 无精确超集兜底取十字")
	var wall_ids := []
	for res in wall_res:
		wall_ids.append(str((res as Dictionary)["variant_id"]))
	_check(wall_ids.has("crv/tiles/wall_straight.png") and wall_ids.size() == 3, "墙体可解析项全部指向直线墙")
	var masks_sorted := true
	var prev := 0
	for res in road_res:
		var m := int((res as Dictionary)["mask"])
		if m <= prev:
			masks_sorted = false
		prev = m
	_check(masks_sorted, "解析表按掩码升序")
	_check(str((road_by_mask[3] as Dictionary)["dirs_text"]) == "↑→", "掩码3 方向文本 ↑→")

func _test_text_helpers() -> void:
	_check(ConnectionRulesViewer.mask_to_text(12) == "↓←", "掩码12 → ↓←")
	_check(ConnectionRulesViewer.dirs_to_text(["up", "down"]) == "↑↓", "方向列表 → ↑↓")
	_check(ConnectionRulesViewer.dirs_to_text(["bogus"]) == "bogus", "未知方向原样保留（暴露清单写错）")

## 弹窗渲染：标题/分组行/解析行真实存在，且 rules 与纯函数一致
func _test_dialog(lib: AssetLibrary) -> void:
	var viewer := ConnectionRulesViewer.new()
	viewer.setup(lib)
	_check(viewer.title == "连接规则", "弹窗标题")
	_check(viewer.rules.size() == 2, "rules 成员与纯函数一致")
	var texts := []
	_collect_labels(viewer, texts)
	var joined := "\n".join(texts)
	_check(texts.size() > 10, "渲染标签数 %d > 10" % texts.size())
	_check(joined.contains("【道路】声明连接的素材 4 件"), "道路分组行可见")
	_check(joined.contains("【墙体】声明连接的素材 1 件"), "墙体分组行可见")
	_check(joined.contains("←→（掩码 10）"), "素材声明行可见（直线）")
	_check(joined.contains("↑→↓← → road_cross"), "解析行可见（十字）")
	_check(joined.contains("↑上 →右 ↓下 ←左"), "说明文字可见")
	viewer.free() # 生命周期纪律：探针内创建的节点必须显式释放

func _test_empty_library() -> void:
	var empty_lib := AssetLibrary.new()
	var empty_rules: Array = ConnectionRulesViewer.build_rules(empty_lib)
	_check(empty_rules.is_empty(), "空素材库返回空规则表")
	var viewer := ConnectionRulesViewer.new()
	viewer.setup(empty_lib)
	var texts := []
	_collect_labels(viewer, texts)
	_check("\n".join(texts).contains("没有声明任何连接规则"), "空库提示文案可见")
	viewer.free()

func _collect_labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_collect_labels(child, out)

func _setup_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/tiles"))
	var variants := [
		["road_straight.png", ["left", "right"], "road"],
		["road_corner.png", ["right", "down"], "road"],
		["road_cross.png", ["up", "right", "down", "left"], "road"],
		["road_end.png", ["up"], "road"],
		["wall_straight.png", ["left", "right"], "wall"],
		["grass.png", [], "ground"], # 无连接声明：分类不得入表
	]
	var assets := []
	for v in variants:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.35, 0.35, 0.4))
		img.save_png(FIXTURE_ROOT + "/tiles/" + str(v[0]))
		assets.append({"file": "tiles/" + str(v[0]), "name": str(v[0]).get_basename(), "category": str(v[2]), "connections": v[1]})
	var f := FileAccess.open(FIXTURE_ROOT + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "连接规则查看器夹具", "assets": assets}, "\t"))
	f.flush() # 显式落盘（dev-pitfalls：FileAccess 缓冲在释放前不保证可读）
	f = null
	if not FileAccess.file_exists(FIXTURE_ROOT + "/pack.json"):
		_fail += 1
		print("[TileMason] FAIL 夹具清单未落盘（环境异常）")

func _cleanup() -> void:
	_remove_dir_recursive(FIXTURE_ROOT)

func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if str(entry) != "." and str(entry) != "..":
			names.append(str(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	for n in names:
		if dir.dir_exists(n):
			_remove_dir_recursive(path.path_join(n))
		else:
			dir.remove(n)
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
