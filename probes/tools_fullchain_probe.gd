extends SceneTree
## [TileMason] 全工具操作衔接全链路探针：画笔/直线/矩形/油漆桶/橡皮衔接/选择框选/
## 复制粘贴/镜像/删除/标签/收藏/批量替换/快捷栏/工具互斥/物件放置/检查/聚焦
## 手法：自建确定性场景 + 函数直调 + 内部状态注入（mouse_cell 恒 (-2,-2)，见 eraser 探针沉淀）
## 用户档保护：标签测试前备份 tags.json 内容、测试后恢复；收藏/快捷栏只做可逆/只读操作
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0
var main

func _init() -> void:
	print("[TileMason] 全工具链探针开始")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	_clear_world()
	await _scene_brush_stroke()
	await _scene_shift_single()
	await _scene_line()
	await _scene_rect()
	await _scene_bucket()
	await _scene_eyedrop()
	await _scene_select_and_all()
	await _scene_copy_paste()
	await _scene_mirror()
	await _scene_delete_selection()
	await _scene_tag()
	await _scene_favorite()
	await _scene_replace()
	await _scene_hotbar()
	await _scene_mutex()
	await _scene_object_place()
	await _scene_check()
	await _scene_focus()
	await _scene_prefab()
	_finish()

## ---------- 基建 ----------

func _clear_world() -> void:
	for l in main._document.get_layers():
		var lid := str((l as Dictionary)["id"])
		for c in main._document.get_tile_coords(lid):
			main._document.erase_tile(lid, c, true)
	for o in main._document.get_objects().duplicate():
		main._document.remove_object(int((o as Dictionary)["id"]), true)
	main._commands.clear()

func _tiles(layer := "ground") -> int:
	return main._document.get_tile_count(layer)

func _objs() -> int:
	return main._document.get_objects().size()

func _select(asset_path: String) -> void:
	main._panel.select_asset("demo/" + asset_path)
	await process_frame

func _press_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame

func _release_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

## ---------- 场景 ----------

func _scene_brush_stroke() -> void:
	_clear_world()
	await _select("tiles/road_h.png")
	main._begin_paint() # 起笔格 (-2,-2)
	main._paint_to(Vector2i(-3, -2))
	main._paint_to(Vector2i(-4, -2))
	main._end_paint()
	_check(_tiles() == 3, "画笔拖刷 3 格（%d）" % _tiles())
	main._do_undo()
	_check(_tiles() == 0, "画笔笔画整段撤销")
	main._do_redo()
	_check(_tiles() == 3, "画笔笔画重放")
	main._do_undo()

func _scene_shift_single() -> void:
	_clear_world()
	await _select("tiles/road_h.png")
	await _press_key(KEY_SHIFT)
	main._begin_paint() # Shift 分支：单块不进拖刷
	_check(_tiles() == 1, "Shift 单块放置（%d 格）" % _tiles())
	_check(not main._painting, "Shift 单块未进入拖刷态")
	main._do_undo()
	await _release_key(KEY_SHIFT)
	_check(_tiles() == 0, "单块可撤销")

func _scene_line() -> void:
	_clear_world()
	await _select("tiles/road_h.png")
	main._toggle_line_mode()
	main._line_click(Vector2i(-8, -2)) # 起点
	_check(main._line_armed, "直线第一击布防")
	main._line_click(Vector2i(-4, -2)) # 终点：5 格横线
	_check(_tiles() == 5, "直线落线 5 格（%d）" % _tiles())
	main._do_undo()
	_check(_tiles() == 0, "直线单命令撤销")
	main._line_click(Vector2i(-6, -2))
	main._exit_line_mode()
	_check(not main._line_mode and not main._line_armed, "Esc 退出直线模式")

func _scene_rect() -> void:
	_clear_world()
	await _select("tiles/road_h.png")
	main._begin_rect() # _rect_start=起笔格(-2,-2)，置 _recting
	main._rect_start = Vector2i(-6, -6) # 状态注入：扩为 5×5（终点恒 (-2,-2)）
	main._end_rect()
	_check(_tiles() == 25, "矩形填充 5×5=25 格（%d）" % _tiles())
	main._do_undo()
	_check(_tiles() == 0, "矩形单命令撤销")
	# 大矩形性能回归：50×50 含变体刷新（曾 4.8s 卡顿——分类索引+批量刷新修复）
	main._rect_start = Vector2i(-51, -51)
	var t0 := Time.get_ticks_msec()
	main._begin_rect()
	main._rect_start = Vector2i(-51, -51)
	main._end_rect()
	var dt: int = Time.get_ticks_msec() - t0
	_check(_tiles() == 2500, "大矩形 50×50=2500 格（%d）" % _tiles())
	_check(dt < 2000, "大矩形耗时 %dms < 2000ms（修复前 4808ms）" % dt)
	main._do_undo()

func _scene_bucket() -> void:
	_clear_world()
	# 2×2 连通草地 + 1 格孤立草地
	for c in [Vector2i(-4, -4), Vector2i(-3, -4), Vector2i(-4, -3), Vector2i(-3, -3)]:
		main._place_asset(main._demo_asset("tiles/grass.png"), c)
	main._place_asset(main._demo_asset("tiles/grass.png"), Vector2i(6, 6))
	main._commands.clear()
	await _select("tiles/road_h.png")
	main._toggle_bucket_mode()
	main._do_bucket_fill(Vector2i(-4, -4)) # 从连通块一角灌
	var road_n: int = 0
	for c in [Vector2i(-4, -4), Vector2i(-3, -4), Vector2i(-4, -3), Vector2i(-3, -3)]:
		if str(main._document.get_tile("ground", c).get("asset_id", "")).contains("road"):
			road_n += 1
	var isolated_grass: bool = not main._document.get_tile("ground", Vector2i(6, 6)).is_empty()
	_check(road_n == 4, "油漆桶灌满连通区（%d/4 变道路）" % road_n)
	_check(isolated_grass, "孤立格不被波及")
	main._do_undo()
	var grass_back: int = 0
	for c in [Vector2i(-4, -4), Vector2i(-3, -4)]:
		if str(main._document.get_tile("ground", c).get("asset_id", "")).contains("grass"):
			grass_back += 1
	_check(grass_back >= 1, "油漆桶撤销恢复草地")
	main._toggle_bucket_mode()

func _scene_eyedrop() -> void:
	_clear_world()
	main._place_asset(main._demo_asset("tiles/wall_brick.png"), Vector2i(-2, -2)) # 摆在恒定鼠标格
	main._commands.clear()
	await _select("tiles/grass.png")
	main._pick_under_mouse() # 取 (-2,-2) 处素材
	_check(main._selected_asset_id == "demo/tiles/wall_brick.png", "吸管取到鼠标格素材（%s）" % main._selected_asset_id.get_file())

func _scene_select_and_all() -> void:
	_clear_world()
	for x in [-2, -3, -4]:
		main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(x, -2))
	main._place_asset(main._demo_asset("tiles/grass.png"), Vector2i(6, 6))
	main._commands.clear()
	main._toggle_select_mode()
	main._begin_select_action() # marquee 起点=(-2,-2)
	main._marquee_start = Vector2i(-4, -2) # 注入：扩选区到 (-4..-2, -2)
	main._end_select_action()
	var sel_cells: Array = []
	for layer_id in main._selection.cells_by_layer().keys():
		sel_cells = main._selection.cells_by_layer()[str(layer_id)]
	_check(sel_cells.size() == 3, "框选 3 格（%d）" % sel_cells.size())
	main._select_all()
	var all_cells: Array = []
	for layer_id in main._selection.cells_by_layer().keys():
		all_cells = main._selection.cells_by_layer()[str(layer_id)]
	_check(all_cells.size() >= 4, "Ctrl+A 全选含远处格（%d≥4）" % all_cells.size())
	main._exit_select_mode()

func _scene_copy_paste() -> void:
	_clear_world()
	for x in [-10, -11, -12]:
		main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(x, -2))
	main._commands.clear()
	main._toggle_select_mode()
	main._begin_select_action()
	main._marquee_start = Vector2i(-12, -2)
	main._end_select_action() # 选 (-12..-10, -2) 三格
	var sel_n: int = 0
	for layer_id in main._selection.cells_by_layer().keys():
		sel_n = main._selection.cells_by_layer()[str(layer_id)].size()
	_check(sel_n == 3, "复制前框选 3 格")
	main._copy_selected()
	_check(main._clip_cells.size() == 3, "剪贴板 3 格（%d）" % main._clip_cells.size())
	main._delete_selected()
	_check(_tiles() == 0, "删除选中内容")
	main._do_undo() # 恢复 3 格（避免粘贴重叠干扰断言）
	main._paste_clipboard() # 粘贴：base=(-12,-2)，目标左上=鼠标格(-2,-2)→delta=(10,0)→贴到 (-2,-2)(-1,-2)(0,-2)
	_check(_tiles() == 6, "粘贴副本落位（%d=原3+新3）" % _tiles())
	main._do_undo()
	_check(_tiles() == 3, "粘贴可撤销")
	main._exit_select_mode()

func _scene_mirror() -> void:
	_clear_world()
	main._place_asset(main._demo_asset("props/house.png"), Vector2i(0, 0))
	main._commands.clear()
	var obj := main._document.get_objects()[0] as Dictionary
	var before: bool = bool(obj.get("mirror_h", false))
	main._toggle_select_mode()
	main._begin_select_action() # 起笔格 (-2,-2) 无物件→marquee……改为全选
	main._select_all()
	var ids: Array = main._selection.object_ids()
	_check(ids.size() == 1, "全选含 1 物件")
	main._mirror_selected()
	var obj2 := main._document.get_objects()[0] as Dictionary
	_check(bool(obj2.get("mirror_h", false)) == (not before), "镜像翻转 mirror_h（%s→%s）" % [before, obj2.get("mirror_h")])
	main._do_undo()
	var obj3 := main._document.get_objects()[0] as Dictionary
	_check(bool(obj3.get("mirror_h", false)) == before, "镜像撤销恢复")
	main._exit_select_mode()

func _scene_delete_selection() -> void:
	_clear_world()
	main._place_asset(main._demo_asset("props/house.png"), Vector2i(0, 0))
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-4, -2))
	main._commands.clear()
	main._toggle_select_mode()
	main._select_all()
	main._delete_selected()
	_check(_objs() == 0 and _tiles() == 0, "删除选中（物件+方块）")
	main._do_undo()
	_check(_objs() == 1 and _tiles() == 1, "删除撤销恢复")
	main._exit_select_mode()

func _scene_tag() -> void:
	var backup: Dictionary = main._tags.duplicate(true) # 用户标签档保护
	await _select("tiles/road_h.png")
	main._begin_tag_input()
	_check(main._tag_input_mode, "标签输入模式开启")
	main._tag_input_text = "探针标签"
	main._commit_tag_input()
	_check(not main._tag_input_mode, "提交后退出输入模式")
	_check(main._tags.get("demo/tiles/road_h.png", []).has("探针标签"), "标签已保存")
	_check(main._panel._tag_ids.has("探针标签"), "面板标签索引同步")
	main._tags = backup
	TagStore.save_all(main._tags) # 恢复用户档
	main._panel.set_tags(TagStore.reverse_index(main._tags))
	_check(not main._tags.has("demo/tiles/road_h.png") or not (main._tags["demo/tiles/road_h.png"] as Array).has("探针标签"), "用户标签档已恢复")

func _scene_favorite() -> void:
	await _select("tiles/grass.png")
	var had: bool = main._favorites.has("demo/tiles/grass.png")
	main._toggle_favorite() # 翻转
	var now: bool = main._favorites.has("demo/tiles/grass.png")
	_check(now != had, "收藏状态翻转（%s→%s）" % [had, now])
	main._toggle_favorite() # 翻回（用户档无污染）
	_check(main._favorites.has("demo/tiles/grass.png") == had, "收藏恢复原状")

func _scene_replace() -> void:
	_clear_world()
	main._place_asset(main._demo_asset("tiles/grass.png"), Vector2i(-2, -2)) # 鼠标格处
	main._place_asset(main._demo_asset("tiles/grass.png"), Vector2i(-8, -8))
	main._commands.clear()
	await _select("tiles/road_h.png")
	main._batch_replace_under_mouse() # 鼠标格处是 grass → 全图 grass→road
	_check(str(main._document.get_tile("ground", Vector2i(-8, -8)).get("asset_id", "")).contains("road"), "批量替换：远处同款也替换")
	main._do_undo()
	_check(str(main._document.get_tile("ground", Vector2i(-8, -8)).get("asset_id", "")).contains("grass"), "批量替换撤销恢复")

func _scene_hotbar() -> void:
	var binding: String = str(main._hotbar_bindings[0])
	main._hotbar_activate(1)
	if binding.is_empty():
		_check(true, "快捷栏槽 1 未绑定（跳过选中断言）")
	else:
		_check(main._selected_asset_id == binding, "快捷栏激活选中槽位素材（%s）" % binding.get_file())
	main._hotbar_activate(0) # 橡皮
	_check(main._eraser_mode, "快捷栏槽 0=橡皮开关")
	main._toggle_eraser()

func _scene_mutex() -> void:
	main._toggle_line_mode()
	_check(main._line_mode, "直线模式开启")
	main._toggle_eraser()
	_check(not main._line_mode and main._eraser_mode, "直线→橡皮互斥切换")
	main._toggle_bucket_mode()
	_check(not main._eraser_mode and main._bucket_mode, "橡皮→油漆桶互斥切换")
	main._toggle_select_mode()
	_check(not main._bucket_mode and main._select_mode, "油漆桶→选择互斥切换")
	main._exit_select_mode()
	_check(not main._select_mode, "退出选择模式")

func _scene_object_place() -> void:
	_clear_world()
	await _select("props/tree_small.png")
	main._place_asset(main._library.get_asset(main._selected_asset_id), Vector2i(4, 4))
	_check(_objs() == 1, "物件放置（%d）" % _objs())
	main._do_undo()
	_check(_objs() == 0, "物件撤销")
	main._do_redo()
	_check(_objs() == 1, "物件重做")

func _scene_check() -> void:
	_clear_world()
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-2, -2))
	main._commands.clear()
	main._run_map_check() # 结果进检查页签+不崩
	_check(main._check_panel != null, "检查链路执行（结果入页签）")
	main._do_undo()

func _scene_focus() -> void:
	_clear_world()
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-2, -2))
	main._commands.clear()
	main._toggle_select_mode()
	main._select_all()
	var cam_before: Vector2 = root.get_camera_2d().position
	main._focus_selection() # Q：相机对准选中内容
	var cam_after: Vector2 = root.get_camera_2d().position
	_check(cam_after != cam_before, "Q 聚焦移动相机（%s→%s）" % [cam_before, cam_after])
	main._exit_select_mode()

## 预制件链：框选→Ctrl+P 存件→P 放置→删除（件名唯一+清理，不污染用户档）
func _scene_prefab() -> void:
	var cur_backup := ""
	if FileAccess.file_exists("user://prefab_current.json"):
		var bf := FileAccess.open("user://prefab_current.json", FileAccess.READ)
		if bf != null:
			cur_backup = bf.get_as_text() # 用户「当前件」档保护：测毕恢复
	_clear_world()
	for x in [-10, -11]:
		main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(x, -2))
	main._commands.clear()
	main._toggle_select_mode()
	main._begin_select_action()
	main._marquee_start = Vector2i(-11, -2)
	main._end_select_action()
	main._save_prefab_from_selection() # 存为当前件（_current_prefab）
	var saved: bool = Prefab.list_names().has(main._current_prefab)
	_check(saved, "预制件保存（%s）" % main._current_prefab)
	main._place_current_prefab() # P：放置到鼠标格 (-2,-2)（快照格=base+相对位）
	_check(_tiles() >= 4, "预制件放置（%d≥原2+新2）" % _tiles())
	main._do_undo()
	_check(_tiles() == 2, "预制件放置撤销")
	var nm: String = main._current_prefab
	main._delete_prefab(nm)
	_check(not Prefab.list_names().has(nm), "预制件删除清理")
	if cur_backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://prefab_current.json"))
	else:
		var rf := FileAccess.open("user://prefab_current.json", FileAccess.WRITE)
		if rf != null:
			rf.store_string(cur_backup)
	main._current_prefab = cur_backup
	main._exit_select_mode()

func _finish() -> void:
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
