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
	_test_layer_visibility(doc, view)
	_test_selection(doc, view)
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
	_check(view.pick_object_on_layer("deco", Vector2i(2, 2)) == -1, "物件已删：脚印格返回 -1")
	# 橡皮擦物件拾取：两个物件脚印叠放时取后加入的
	var id_a := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(5, 5)})
	var id_b := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(5, 5)})
	_check(view.pick_object_on_layer("deco", Vector2i(6, 6)) == id_b, "同层叠放取后加入的物件")
	_check(view.pick_object_on_layer("building", Vector2i(6, 6)) == -1, "其他物件层不误伤")

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

func _test_layer_visibility(doc: MapDocument, view: MapView) -> void:
	var cell := Vector2i(20, 5)
	doc.set_tile("ground", cell, "probe_mv/tiles/tile.png")
	var s := view.get_tile_sprite("ground", cell)
	_check(s != null and s.visible, "默认层可见")
	doc.set_layer_property("ground", "visible", false)
	_check(s != null and not s.visible, "隐藏图层后 Sprite 隐藏")
	doc.set_tile("ground", cell + Vector2i(1, 0), "probe_mv/tiles/tile.png") # 隐藏期间新增
	var s2 := view.get_tile_sprite("ground", cell + Vector2i(1, 0))
	_check(s2 != null and not s2.visible, "隐藏期间新增的 Sprite 也隐藏")
	doc.set_layer_property("ground", "visible", true)
	_check(s != null and s.visible and s2 != null and s2.visible, "恢复显示后全部可见")
	# 透明度（design.md §4）
	doc.set_layer_property("ground", "opacity", 0.5)
	_check(s != null and is_equal_approx(s.modulate.a, 0.5), "图层透明度 0.5 生效")
	doc.set_tile("ground", cell + Vector2i(2, 0), "probe_mv/tiles/tile.png") # 半透明期间新增
	var s3 := view.get_tile_sprite("ground", cell + Vector2i(2, 0))
	_check(s3 != null and is_equal_approx(s3.modulate.a, 0.5), "半透明期间新增 Sprite 同步初始化")
	doc.set_layer_property("ground", "opacity", 1.0)
	# 物件层同样生效
	var obj_id := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(20, 5)})
	var os := view.get_object_sprite(obj_id)
	doc.set_layer_property("deco", "visible", false)
	_check(os != null and not os.visible, "物件层隐藏生效")
	doc.set_layer_property("deco", "visible", true)

func _test_selection(doc: MapDocument, view: MapView) -> void:
	# 选区模型
	var sel := Selection.new()
	sel.add_object(1)
	sel.add_object(1)
	_check(sel.object_count() == 1, "选区物件去重")
	sel.add_object(2)
	sel.set_objects([3, 4, 4])
	_check(sel.object_count() == 2 and sel.has_object(3) and not sel.has_object(1), "整批设置清旧+去重")
	sel.add_cell("ground", Vector2i(0, 0))
	sel.add_cell("ground", Vector2i(0, 0))
	_check(sel.cell_count() == 1, "格选区去重")
	sel.clear()
	_check(sel.is_empty(), "清空选区")

	# 框选命中（物件 30,0 与 40,0，前测物件在别处）
	var a := doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(30, 0)})
	doc.add_object({"asset_id": "probe_mv/props/prop.png", "layer": "deco", "cell": Vector2i(40, 0)})
	_check(view.objects_in_rect(Rect2i(Vector2i(29, -1), Vector2i(5, 5))) == [a], "框选命中单个物件")
	_check(view.objects_in_rect(Rect2i(Vector2i(0, 0), Vector2i(100, 20))).size() >= 2, "大框选命中多物件")

	# 高亮/拖动预览/回同步
	view.set_objects_tinted([a], true)
	_check(view.get_object_sprite(a) != null and view.get_object_sprite(a).modulate != Color.WHITE, "选中高亮生效")
	view.set_objects_tinted([a], false)
	view.begin_object_drag([a])
	view.drag_object_sprites([a], Vector2(32, 16))
	view.resync_objects([a])
	_check(view.get_object_sprite(a) != null, "拖动预览与回同步不崩溃")

	# 移动命令往返
	var stack := CommandStack.new()
	var from: Vector2i = doc.get_object(a)["cell"]
	var to := from + Vector2i(2, 3)
	var entries := [{"id": a, "from": from, "to": to}]
	var do_move := func() -> void:
		for e in entries:
			doc.update_object(int((e as Dictionary)["id"]), {"cell": (e as Dictionary)["to"]}, true)
	var undo_move := func() -> void:
		for e in entries:
			doc.update_object(int((e as Dictionary)["id"]), {"cell": (e as Dictionary)["from"]}, true)
	stack.push("移动", do_move, undo_move)
	_check(doc.get_object(a)["cell"] == to, "移动命令应用")
	stack.undo()
	_check(doc.get_object(a)["cell"] == from, "撤销移动恢复原位")

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
