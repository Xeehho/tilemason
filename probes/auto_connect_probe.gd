extends SceneTree
## [TileMason] 自动连接核心探针（纯逻辑）：掩码换算 / 邻接掩码 / 变体匹配 / 刷新变更
## 运行：godot --headless --path . --script res://probes/auto_connect_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

const FIXTURE_ROOT := "user://ac" # 目录名=包 id，素材 id 前缀须为 ac/

func _init() -> void:
	print("[TileMason] 自动连接探针开始")
	_setup_fixtures()
	var lib := AssetLibrary.new()
	var scanned := lib.scan([FIXTURE_ROOT])
	print("[TileMason] 扫描到素材 %d 件" % scanned)
	for a in lib.get_assets():
		print("[TileMason]   id=%s conn=%s" % [a["id"], a["connections"]])
	var doc := MapDocument.new()
	_test_mask_helpers()
	_test_neighbor_mask(doc, lib)
	_test_pick_variant(lib)
	_test_refresh(doc, lib)
	_test_merge()
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

func _test_mask_helpers() -> void:
	_check(AutoConnect.dirs_to_mask(["left", "right"]) == 10, "left|right → 10")
	_check(AutoConnect.dirs_to_mask(["up", "right", "down", "left"]) == 15, "四向 → 15")
	_check(AutoConnect.dirs_to_mask(["bogus"]) == 0, "未知方向忽略")
	_check(AutoConnect.mask_to_dirs(6) == ["right", "down"], "6 → right|down")

func _test_neighbor_mask(doc: MapDocument, lib: AssetLibrary) -> void:
	# L 形：(0,0)-(1,0)-(1,1)，全部直线素材；角格 (1,0) 应得 E|S=6
	doc.set_tile("ground", Vector2i(0, 0), "ac/tiles/road_straight.png")
	doc.set_tile("ground", Vector2i(1, 0), "ac/tiles/road_straight.png")
	doc.set_tile("ground", Vector2i(1, 1), "ac/tiles/road_straight.png")
	_check(AutoConnect.neighbor_mask(doc, lib, "ground", Vector2i(1, 0), "road") == 12, "L 角邻接掩码 W|S=12")
	_check(AutoConnect.neighbor_mask(doc, lib, "ground", Vector2i(0, 0), "road") == 2, "端头掩码 E")
	# 异类不连接：墙放旁边不算道路邻居
	doc.set_tile("terrain", Vector2i(0, 1), "ac/tiles/wall_straight.png")
	_check(AutoConnect.neighbor_mask(doc, lib, "ground", Vector2i(0, 0), "road") == 2, "墙邻格不计入道路掩码")

func _test_pick_variant(lib: AssetLibrary) -> void:
	_check(AutoConnect.pick_variant(lib, "road", 10) == "ac/tiles/road_straight.png", "精确匹配直线")
	_check(AutoConnect.pick_variant(lib, "road", 6) == "ac/tiles/road_corner.png", "精确匹配弯道")
	_check(AutoConnect.pick_variant(lib, "road", 15) == "ac/tiles/road_cross.png", "十字取十字")
	_check(AutoConnect.pick_variant(lib, "road", 7) == "ac/tiles/road_t.png", "T 形取 T（无多余方向）")
	_check(AutoConnect.pick_variant(lib, "road", 14) == "ac/tiles/road_t2.png", "T 反向取 T2")
	_check(AutoConnect.pick_variant(lib, "road", 0) == "", "零掩码返回空")
	_check(AutoConnect.pick_variant(lib, "road", 1) == "ac/tiles/road_end.png", "端头取单连接变体")

func _test_refresh(doc: MapDocument, lib: AssetLibrary) -> void:
	# 刷新 L 角：中心格应变弯道，端格保持直线（掩码 2 仍精确匹配）
	var changes := AutoConnect.refresh_around(doc, lib, "ground", Vector2i(1, 0))
	var center_changed := false
	for c in changes:
		if (c as Dictionary)["cell"] == Vector2i(1, 0) and (c as Dictionary)["new_asset_id"] == "ac/tiles/road_corner_wd.png":
			center_changed = true
	_check(center_changed, "L 角刷新为弯道变体（W|S）")
	_check(doc.get_tile("ground", Vector2i(1, 0))["asset_id"] == "ac/tiles/road_corner_wd.png", "变更已应用")
	var straight_kept := true
	for c in changes:
		if (c as Dictionary)["cell"] == Vector2i(0, 0):
			straight_kept = false
	_check(straight_kept, "精确匹配的端格不被改写")
	# 撤销语义：按变更清单可完整还原
	for c in changes:
		doc.set_tile("ground", (c as Dictionary)["cell"], str((c as Dictionary)["old_asset_id"]), true)
	_check(doc.get_tile("ground", Vector2i(1, 0))["asset_id"] == "ac/tiles/road_straight.png", "按清单撤销还原")

func _test_merge() -> void:
	# 回归：合并条目必须带 cell 键（曾因丢键致所有方块命令运行时报错，check-only 查不出）
	var base := [{"cell": Vector2i(1, 0), "old": {"asset_id": "a"}}, {"cell": Vector2i(2, 0), "old": {}}]
	var extras := {
		Vector2i(1, 0): {"cell": Vector2i(1, 0), "old_asset_id": "a", "new_asset_id": "v12"},
		Vector2i(9, 9): {"cell": Vector2i(9, 9), "old_asset_id": "b", "new_asset_id": "v3"},
	}
	var entries: Array = AutoConnect.merge_tile_changes(base, extras, "a")
	_check(entries.size() == 3, "合并去重 3 条（同格并 1）")
	var all_have_cell := true
	var cell1_new := ""
	for e in entries:
		var ee: Dictionary = e
		if not ee.has("cell"):
			all_have_cell = false
		if (ee["cell"] as Vector2i) == Vector2i(1, 0):
			cell1_new = str(ee["new"])
	_check(all_have_cell, "每条都带 cell 键（回归）")
	_check(cell1_new == "v12", "同格取最终新值（变体覆盖）")
	# 擦除语义：new 为 null
	var e2: Array = AutoConnect.merge_tile_changes([{"cell": Vector2i(0, 0), "old": {"asset_id": "x"}}], {}, "")
	_check((e2[0] as Dictionary)["new"] == null, "擦除语义 new=null")
	# 纯刷新格：old 由 extras 提供
	var e3: Array = AutoConnect.merge_tile_changes([], {Vector2i(5, 5): {"cell": Vector2i(5, 5), "old_asset_id": "b", "new_asset_id": "c"}}, "z")
	var first: Dictionary = e3[0]
	_check(str((first["old"] as Dictionary)["asset_id"]) == "b" and str(first["new"]) == "c", "纯刷新格旧新值正确")

func _setup_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/tiles"))
	var variants := [
		["road_straight.png", ["left", "right"], false],
		["road_corner.png", ["right", "down"], false],
		["road_corner_wd.png", ["left", "down"], false],
		["road_t.png", ["up", "right", "down"], false],
		["road_t2.png", ["right", "down", "left"], false],
		["road_cross.png", ["up", "right", "down", "left"], false],
		["road_end.png", ["up"], false],
		["wall_straight.png", ["left", "right"], true],
	]
	var assets := []
	for v in variants:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.45, 0.42, 0.38) if (v[2] as bool) else Color(0.35, 0.35, 0.4))
		img.save_png(FIXTURE_ROOT + "/tiles/" + str(v[0]))
		assets.append({"file": "tiles/" + str(v[0]), "name": str(v[0]).get_basename(), "category": "wall" if (v[2] as bool) else "road", "connections": v[1]})
	var f := FileAccess.open(FIXTURE_ROOT + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "自动连接夹具", "assets": assets}, "\t"))
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
