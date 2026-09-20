extends SceneTree
## [TileMason] 地图视图探针（headless 节点树断言，无需渲染）
## 覆盖：tile/物件 Sprite 映射、左上角与底边中心锚几何、镜像、信号驱动增删改、
##       命令栈撤销/重做联动视图、同文档重建
## 运行：godot --headless --path . --script res://probes/map_view_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

const FIXTURE_ROOT := "user://probe_mv"

func _init() -> void:
	print("[TileMason] 地图视图探针开始")
	_setup_fixtures()
	var lib := AssetLibrary.new()
	lib.scan([FIXTURE_ROOT])
	var doc := MapDocument.new()
	var view := MapView.new()
	view.setup(doc, lib)
	_test_tiles(doc, view)
	_test_objects(doc, view)
	_test_undo(doc, view)
	_test_pick(doc, view)
	_test_stroke(doc, view)
	_test_rebuild(doc, lib, view)
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

func _test_tiles(doc: MapDocument, view: MapView) -> void:
	doc.set_tile("ground", Vector2i(2, 3), "probe_mv/tiles/tile.png")
	_check(view.tile_sprite_count() == 1, "放置方块生成 1 个 Sprite")
	var s := view.get_tile_sprite("ground", Vector2i(2, 3))
	_check(s != null and s.position == Vector2(32, 48), "方块位置=格坐标×16（左上角锚）")
	_check(s != null and not s.centered, "方块 Sprite 不居中（左上角锚）")
	doc.set_tile("ground", Vector2i(2, 3), "probe_mv/tiles/tile.png") # 覆盖同格
	_check(view.tile_sprite_count() == 1, "覆盖同格不新增 Sprite")
	doc.erase_tile("ground", Vector2i(2, 3))
	_check(view.tile_sprite_count() == 0 and view.get_tile_sprite("ground", Vector2i(2, 3)) == null, "擦除方块移除 Sprite")

func _test_objects(doc: MapDocument, view: MapView) -> void:
	var id := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(0, 0)})
	var s := view.get_object_sprite(id)
	# 48px 件占 3×3 格：锚点=(0*16+48/2, 0*16+48)=(24,48)，居中 Sprite 中心=(24,24)
	_check(s != null and s.position == Vector2(24, 24), "物件底边中心锚几何正确（48px→中心 24,24）")
	_check(s != null and s.centered, "物件 Sprite 居中（配合锚点公式）")
	doc.update_object(id, {"mirror_h": true})
	_check(s != null and s.flip_h, "镜像更新生效")
	doc.update_object(id, {"cell": Vector2i(4, 2)})
	# 新锚点=(4*16+24, 2*16+48)=(88,80)，中心=(88,56)
	_check(s != null and s.position == Vector2(88, 56), "移动物件位置更新")
	doc.remove_object(id)
	_check(view.get_object_sprite(id) == null, "删除物件移除 Sprite")

func _test_undo(doc: MapDocument, view: MapView) -> void:
	var stack := CommandStack.new()
	var cell := Vector2i(7, 7)
	var ctx := {}
	var do_place := func() -> void:
		if not ctx.has("done"):
			ctx["old"] = doc.set_tile("ground", cell, "probe_mv/tiles/tile.png")
			ctx["done"] = true
		else:
			doc.set_tile("ground", cell, "probe_mv/tiles/tile.png", true)
	var undo_place := func() -> void:
		var prev: Dictionary = ctx.get("old", {})
		if prev.is_empty():
			doc.erase_tile("ground", cell, true)
		else:
			doc.set_tile("ground", cell, str(prev["asset_id"]), true)
	stack.push("放置", do_place, undo_place)
	_check(view.get_tile_sprite("ground", cell) != null, "命令放置后视图出现方块")
	stack.undo()
	_check(view.get_tile_sprite("ground", cell) == null, "撤销后视图移除方块（信号驱动）")
	stack.redo()
	_check(view.get_tile_sprite("ground", cell) != null, "重做后视图恢复方块")

func _test_pick(doc: MapDocument, view: MapView) -> void:
	# 物件脚印 (0..2, 0..2) 盖在方块 (1,1) 上：物件层优先
	var obj_id := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(0, 0)})
	doc.set_tile("ground", Vector2i(1, 1), "probe_mv/tiles/tile.png")
	_check(view.pick_asset_id_at(Vector2i(0, 0)) == "probe_mv/props/prop.png", "吸管命中物件脚印角格")
	_check(view.pick_asset_id_at(Vector2i(1, 1)) == "probe_mv/props/prop.png", "物件层优先于 tile 层")
	doc.remove_object(obj_id)
	_check(view.pick_asset_id_at(Vector2i(1, 1)) == "probe_mv/tiles/tile.png", "物件删除后命中底层方块")
	_check(view.pick_asset_id_at(Vector2i(9, 9)).is_empty(), "空格返回空串")

func _test_stroke(doc: MapDocument, view: MapView) -> void:
	# 模拟拖刷 3 格 + 抬手合成一个命令：undo 一次整段回滚，redo 整段重放
	var stack := CommandStack.new()
	var layer := "ground"
	var asset := "probe_mv/tiles/tile.png"
	var cells := [Vector2i(10, 0), Vector2i(11, 0), Vector2i(12, 0)]
	var entries: Array = []
	for c in cells:
		entries.append({"cell": c, "old": doc.set_tile(layer, c, asset)})
	var do_stroke := func() -> void:
		for e in entries:
			doc.set_tile(layer, (e as Dictionary)["cell"], asset, true)
	var undo_stroke := func() -> void:
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			var prev: Dictionary = e["old"]
			if prev.is_empty():
				doc.erase_tile(layer, e["cell"], true)
			else:
				doc.set_tile(layer, e["cell"], str(prev["asset_id"]), true)
	stack.push("笔画 3 格", do_stroke, undo_stroke)
	var all_visible := view.get_tile_sprite(layer, cells[0]) != null \
		and view.get_tile_sprite(layer, cells[1]) != null \
		and view.get_tile_sprite(layer, cells[2]) != null
	_check(all_visible, "笔画 3 格全部渲染")
	stack.undo()
	var all_gone := view.get_tile_sprite(layer, cells[0]) == null \
		and view.get_tile_sprite(layer, cells[1]) == null \
		and view.get_tile_sprite(layer, cells[2]) == null
	_check(all_gone, "撤销一次回滚整段笔画")
	stack.redo()
	_check(view.get_tile_sprite(layer, cells[2]) != null, "重做整段恢复")

func _test_rebuild(doc: MapDocument, lib: AssetLibrary, view: MapView) -> void:
	var tiles_before := view.tile_sprite_count()
	doc.set_tile("terrain", Vector2i(1, 1), "probe_mv/tiles/tile.png")
	doc.set_tile("ground", Vector2i(2, 2), "probe_mv/tiles/tile.png")
	var obj_id := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(0, 0)})
	var view2 := MapView.new()
	view2.setup(doc, lib)
	_check(view2.tile_sprite_count() == tiles_before + 2 and view2.get_object_sprite(obj_id) != null, "同文档重建视图全量渲染（%d 方块+新物件）" % view2.tile_sprite_count())

func _setup_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/tiles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT + "/props"))
	var tile := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0.3, 0.4, 0.9))
	tile.save_png(FIXTURE_ROOT + "/tiles/tile.png")
	var prop := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	prop.fill(Color(0.9, 0.3, 0.3))
	prop.save_png(FIXTURE_ROOT + "/props/prop.png")
	var f := FileAccess.open(FIXTURE_ROOT + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"name": "视图探针夹具",
		"assets": [
			{"file": "tiles/tile.png", "name": "瓦片", "category": "ground"},
			{"file": "props/prop.png", "name": "物件", "category": "deco"},
		],
	}, "\t"))

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
