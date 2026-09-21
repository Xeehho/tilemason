extends SceneTree
## [TileMason] 场景导出探针（P4）：形态A 结构、cell 数据完整性、回载校验
## 运行：godot --headless --path . --script res://probes/scene_export_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

const FIXTURE_ROOT := "user://se" # 目录名=包 id，素材 id 前缀须为 se/

func _init() -> void:
	print("[TileMason] 场景导出探针开始")
	_setup_fixtures()
	var lib := AssetLibrary.new()
	lib.scan([FIXTURE_ROOT])
	var doc := _build_doc()
	doc.update_object(1, {"interaction_offset": Vector2i(1, -1)}) # 交互锚点偏移测试
	var result: Dictionary = SceneExporter.export_scene(doc, lib, "probe_map")
	_check(bool(result.get("ok", false)), "导出成功")
	if not result.get("ok", false):
		_finish()
		return
	_check(int(result.get("tiles", 0)) == 4, "地面格计数 4（跨两层）")
	_check(int(result.get("props", 0)) == 1, "物件计数 1")
	var path := str(result.get("path", ""))
	_check(FileAccess.file_exists(path), "场景文件落盘：" + path)
	# 回载校验：结构 + cell 数据（headless 直接查 TileMapLayer，不依赖实例化帧）
	var packed: PackedScene = load(path)
	_check(packed != null, "场景可回载")
	if packed != null:
		var inst := packed.instantiate()
		_check(inst is Node2D and inst.name == "TileMasonMap", "根节点 TileMasonMap")
		var sort := inst.get_node_or_null("SortRoot")
		_check(sort != null and sort.y_sort_enabled, "SortRoot 且 y_sort 开启（形态A）")
		var ground := sort.get_node_or_null("GroundLayer") as TileMapLayer
		var props_layer := sort.get_node_or_null("PropsLayer") as TileMapLayer
		_check(ground != null and props_layer != null, "地面/物件双 TileMapLayer")
		if ground != null:
			var present := 0
			for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)]:
				if ground.get_cell_source_id(c) != -1:
					present += 1
			_check(present == 4, "回载后 4 个地面格数据完整（含跨层合并）")
			_check(ground.get_cell_source_id(Vector2i(9, 9)) == -1, "空格不被误填")
			_check(ground.tile_set != null and ground.tile_set.tile_size == Vector2i(16, 16), "TileSet 网格 16px")
		if props_layer != null:
			_check(props_layer.y_sort_enabled, "物件层 y_sort 开启")
			_check(props_layer.get_cell_source_id(Vector2i(2, 5)) != -1, "物件格已注册 scene tile")
		# 交互锚点：Anchor_1 存在于 InteractionAnchors，位置=底边中心(56,96)+偏移(16,-16)
		var anchors := inst.get_node_or_null("InteractionAnchors")
		_check(anchors != null and anchors.get_child_count() == 1, "交互锚点容器+单锚点")
		if anchors != null and anchors.get_child_count() > 0:
			var marker := anchors.get_child(0) as Marker2D
			# cell(2,5) 3×3 件：底边中心=(2*16+24, 5*16+48)=(56,128)；+偏移(16,-16)=(72,112)
			_check(marker.name == "Anchor_1" and marker.position == Vector2(72, 112), "锚点命名=物件 id、位置=底边中心+交互偏移")
		# 件场景形态A 几何回归（直接实例化 prop 场景断言配方）
		var prop_scene: PackedScene = load(SceneExporter.EXPORT_DIR + "/prop_se_props_house_png.tscn")
		_check(prop_scene != null, "件场景可独立回载")
		if prop_scene != null:
			var prop := prop_scene.instantiate()
			var sprite := prop.get_node_or_null("Sprite") as Sprite2D
			_check(sprite != null and sprite.offset == Vector2(0, -24.0), "Sprite offset=-h/2（48px 件=-24，根=底边中心）")
			var body := prop.get_node_or_null("Body/Shape") as CollisionShape2D
			var rect_shape := (body.shape as RectangleShape2D) if body != null else null
			_check(rect_shape != null and rect_shape.size == Vector2(48, 16), "碰撞=底边脚印 48×min(48,16)")
			prop.free()
		inst.free()
	_test_path()
	_finish()

func _finish() -> void:
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

func _test_path() -> void:
	# 可通行性（design.md §10 真实移动的离散近似）：碰撞脚印占格为障碍的 BFS
	# 夹具件在 (2,5)、48px 件脚印=3 宽×1 高（形态A：宽×min(件高,格高)）
	var blocked := {}
	for dx in 3:
		blocked[Vector2i(2 + dx, 5)] = true
	_check(_path_exists(blocked, Vector2i(0, 8), Vector2i(6, 8), Rect2i(-3, 0, 12, 12)), "绕开碰撞脚印存在通路")
	for y in range(0, 12): # x=2 整列封断（边界内无绕行）
		blocked[Vector2i(2, y)] = true
	_check(not _path_exists(blocked, Vector2i(0, 8), Vector2i(6, 8), Rect2i(-3, 0, 12, 12)), "整列封断后无通路（负例）")

func _path_exists(blocked: Dictionary, from: Vector2i, to: Vector2i, bounds: Rect2i) -> bool:
	var visited := {}
	var queue: Array = [from]
	visited[from] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			return true
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dir
			if bounds.has_point(n) and not blocked.has(n) and not visited.has(n):
				visited[n] = true
				queue.append(n)
	return false

func _build_doc() -> MapDocument:
	var doc := MapDocument.new()
	doc.set_tile("ground", Vector2i(0, 0), "se/tiles/road.png")
	doc.set_tile("ground", Vector2i(1, 0), "se/tiles/road.png")
	doc.set_tile("ground", Vector2i(2, 0), "se/tiles/road.png")
	doc.set_tile("terrain", Vector2i(0, 1), "se/tiles/road.png") # 跨层合并进同一 GroundLayer
	doc.add_object({"asset_id": "se/props/house.png", "layer": "building", "cell": Vector2i(2, 5)})
	return doc

func _setup_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/tiles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/props"))
	var road := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	road.fill(Color(0.35, 0.35, 0.4))
	road.save_png(FIXTURE_ROOT + "/tiles/road.png")
	var house := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	house.fill(Color(0.8, 0.6, 0.3))
	house.save_png(FIXTURE_ROOT + "/props/house.png")
	var f := FileAccess.open(FIXTURE_ROOT + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"name": "导出探针夹具",
		"assets": [
			{"file": "tiles/road.png", "name": "路", "category": "road"},
			{"file": "props/house.png", "name": "屋", "category": "building"},
		],
	}, "\t"))
	f = null

func _cleanup() -> void:
	_remove_dir_recursive(FIXTURE_ROOT)
	_remove_dir_recursive(SceneExporter.EXPORT_DIR)

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
