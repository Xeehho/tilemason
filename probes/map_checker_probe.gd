extends SceneTree
## [TileMason] 地图检查探针（验收 9）：道路连通性 + 建筑堵路
## 运行：godot --headless --path . --script res://probes/map_checker_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

const FIXTURE_ROOT := "user://probe_checker"

func _init() -> void:
	print("[TileMason] 地图检查探针开始")
	_setup_fixtures()
	var lib := AssetLibrary.new()
	lib.scan([FIXTURE_ROOT])
	var road := "probe_checker/tiles/road.png"
	var building := "probe_checker/props/house.png"

	# 场景一：连通道路 + 不挡路建筑 → 无问题
	var doc := MapDocument.new()
	for x in range(0, 5):
		doc.set_tile("ground", Vector2i(x, 0), road)
	doc.add_object({"asset_id": building, "layer": "building", "cell": Vector2i(2, -4)}) # 脚印 (2..4, -4..-2)，远离道路
	var issues := MapChecker.check_all(doc, lib)
	_check(issues.is_empty(), "连通道路+不堵路 → 检查通过")

	# 场景二：道路断成两段 → road_disconnected
	doc = MapDocument.new()
	for x in range(0, 3):
		doc.set_tile("ground", Vector2i(x, 0), road)
	for x in range(5, 8):
		doc.set_tile("ground", Vector2i(x, 0), road)
	issues = MapChecker.check_all(doc, lib)
	_check(issues.size() == 1 and issues[0]["type"] == "road_disconnected", "道路两段 → 报断路")

	# 场景三：L 形连通（4 邻接含拐角）→ 通过
	doc = MapDocument.new()
	doc.set_tile("ground", Vector2i(0, 0), road)
	doc.set_tile("ground", Vector2i(1, 0), road)
	doc.set_tile("ground", Vector2i(1, 1), road)
	doc.set_tile("ground", Vector2i(1, 2), road)
	issues = MapChecker.check_road_connectivity(doc, lib)
	_check(issues.is_empty(), "L 形连通 → 通过")

	# 场景四：建筑脚印盖到道路 → building_blocks_road
	doc = MapDocument.new()
	for x in range(0, 5):
		doc.set_tile("ground", Vector2i(x, 0), road)
	doc.add_object({"asset_id": building, "layer": "building", "cell": Vector2i(1, -2)}) # 脚印 (1..3, -2..0)，(1,0)(2,0)(3,0) 压路
	issues = MapChecker.check_blocking(doc, lib)
	_check(issues.size() >= 1 and issues[0]["type"] == "building_blocks_road", "建筑压路 → 报堵路")

	# 场景五：对角相邻不算连通（4 邻接语义）
	doc = MapDocument.new()
	doc.set_tile("ground", Vector2i(0, 0), road)
	doc.set_tile("ground", Vector2i(1, 1), road)
	issues = MapChecker.check_road_connectivity(doc, lib)
	_check(issues.size() == 1, "对角相邻不算连通")

	# 场景六b：孤立区域——环路围出一块内部空区
	var doc2e := MapDocument.new()
	for i in 5:
		doc2e.set_tile("ground", Vector2i(i, 0), "x")
		doc2e.set_tile("ground", Vector2i(i, 4), "x")
		doc2e.set_tile("ground", Vector2i(0, i), "x")
		doc2e.set_tile("ground", Vector2i(4, i), "x")
	var enclosed := MapChecker.check_enclosed_regions(doc2e, lib)
	_check(enclosed.size() == 1 and enclosed[0]["count"] == 9, "环路内孤立区域 9 格（场景六前置）")
	# 开放空区不报：单条直线旁的空地
	var doc2o := MapDocument.new()
	doc2o.set_tile("ground", Vector2i(0, 0), "x")
	_check(MapChecker.check_enclosed_regions(doc2o, lib).is_empty(), "开放空区不报孤立")
	# 碰撞重叠：两件 3×3 物件同格叠放
	var doc2c := MapDocument.new()
	doc2c.add_object({"asset_id": building, "layer": "building", "cell": Vector2i(0, 0)})
	doc2c.add_object({"asset_id": building, "layer": "building", "cell": Vector2i(0, 0)})
	var overlaps := MapChecker.check_collision_overlaps(doc2c, lib)
	_check(overlaps.size() == 9 and overlaps[0]["type"] == "collision_overlap", "同格叠放 9 格重叠全报")
	# 相邻不重叠：错开一格
	var doc2d := MapDocument.new()
	doc2d.add_object({"asset_id": building, "layer": "building", "cell": Vector2i(0, 0)})
	doc2d.add_object({"asset_id": building, "layer": "building", "cell": Vector2i(3, 0)})
	_check(MapChecker.check_collision_overlaps(doc2d, lib).is_empty(), "相邻摆放不重叠")

	# 悬空素材：文档里引用素材库没有的 id（方块+物件双路径）
	var docm := MapDocument.new()
	docm.set_tile("ground", Vector2i(0, 0), "nope/missing.png")
	docm.add_object({"asset_id": "nope/prop.png", "layer": "building", "cell": Vector2i(0, 0)})
	var miss := MapChecker.check_missing_assets(docm, lib)
	_check(miss.size() == 2 and miss[0]["type"] == "missing_asset", "悬空素材方块+物件各报一条")
	var docok := MapDocument.new()
	docok.set_tile("ground", Vector2i(0, 0), road)
	_check(MapChecker.check_missing_assets(docok, lib).is_empty(), "素材齐全不误报")

	# 场景六：无道路 → 不误报
	doc = MapDocument.new()
	issues = MapChecker.check_all(doc, lib)
	_check(issues.is_empty(), "无道路不误报")

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

func _setup_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/tiles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/props"))
	var road := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	road.fill(Color(0.35, 0.35, 0.35))
	road.save_png(FIXTURE_ROOT + "/tiles/road.png")
	var house := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	house.fill(Color(0.8, 0.6, 0.3))
	house.save_png(FIXTURE_ROOT + "/props/house.png")
	var f := FileAccess.open(FIXTURE_ROOT + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"name": "检查探针夹具",
		"assets": [
			{"file": "tiles/road.png", "name": "路", "category": "road"},
			{"file": "props/house.png", "name": "屋", "category": "building"},
		],
	}, "\t"))
	f = null # 释放 FileAccess 使缓冲落盘，再扫描

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
