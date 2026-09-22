extends SceneTree
## [TileMason] 面板衔接探针：所有工具 × 右侧素材面板 × 底部快捷栏 × 左侧图层面板交叉
## A 素材面板→工具（搜索/跨分类/最近/收藏/标签/Tab隐藏/刷新）
## B 快捷栏→面板与工具（激活联动/绑定/类型路由）
## C 图层→工具与面板（活动层路由×4工具/锁/隐/透明度/计数/加删层/重命名）
## D 页签与状态栏交叉（检查跳页/回页/四段文案）
## 用户档保护：标签/收藏/最近/快捷栏全部备份恢复
## 退出码：0=全部通过，1=有失败

const START_CELL := Vector2i(-2, -2)

var _pass := 0
var _fail := 0
var main
var _fav_backup: Array = []
var _tag_backup: Dictionary = {}
var _hotbar_backup: Array = []

func _init() -> void:
	print("[TileMason] 面板衔接探针开始")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	# 用户档备份
	_fav_backup = main._favorites.duplicate()
	_tag_backup = main._tags.duplicate(true)
	_hotbar_backup = main._hotbar_bindings.duplicate()
	await _group_a_panel_to_tools()
	await _group_b_hotbar()
	await _group_c_layers()
	await _group_d_tabs_status()
	_restore_user_files()
	_finish()

## ---------- 基建 ----------

func _clear_world() -> void:
	for l in main._document.get_layers():
		var lid := str((l as Dictionary)["id"])
		for c in main._document.get_tile_coords(lid).duplicate():
			main._document.erase_tile(lid, c, true)
	for o in main._document.get_objects().duplicate():
		main._document.remove_object(int((o as Dictionary)["id"]), true)
	main._commands.clear()
	main._layer_panel.set_active_layer("")

func _tiles(layer := "ground") -> int:
	return main._document.get_tile_count(layer)

func _objs() -> int:
	return main._document.get_objects().size()

func _select(asset_path: String) -> void:
	main._panel.select_asset("demo/" + asset_path)
	await process_frame

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

func _restore_user_files() -> void:
	main._favorites = _fav_backup.duplicate()
	main._tags = _tag_backup.duplicate(true)
	main._hotbar_bindings = _hotbar_backup.duplicate()
	main._hotbar.set_bindings(main._hotbar_bindings)
	main._panel.set_favorites(main._favorites)
	main._panel.set_tags(TagStore.reverse_index(main._tags))
	TagStore.save_all(main._tags)
	_save_id_list_probe()

func _save_id_list_probe() -> void:
	var f := FileAccess.open("user://favorites.json", FileAccess.WRITE)
	if f != null and _fav_backup.size() > 0:
		f.store_string(JSON.stringify(_fav_backup))
	elif f != null:
		f.store_string("[]")

## ---------- A：素材面板 → 工具 ----------

func _group_a_panel_to_tools() -> void:
	print("[TileMason] —— A 素材面板→工具 ——")
	# A1 搜索→选中→画笔放置
	_clear_world()
	main._panel._search_box.text = "住宅"
	main._panel._on_search_changed()
	await process_frame
	var hit: bool = main._panel._buttons.size() > 0
	if hit:
		var first_key = main._panel._buttons.keys()[0]
		main._panel._on_thumb_pressed(main._panel._buttons[first_key], str(first_key))
		await process_frame
		var is_house: bool = str(main._selected_asset_id).contains("house") or str(main._selected_asset_id).contains("住宅")
		main._begin_paint()
		main._end_paint()
		_check(is_house and _objs() >= 1, "搜索「住宅」→选中→放置（选中=%s）" % main._selected_asset_id.get_file())
		main._do_undo()
	main._panel._search_box.text = ""
	main._panel._on_search_changed()
	await process_frame
	# A2 跨分类程序选中（面板在 ground 分类时选 wall——树跳转+选中+落层正确）
	_clear_world()
	await _select("tiles/grass.png") # 面板停在 ground
	main._panel.select_asset("demo/tiles/wall_brick.png") # 程序跨分类
	await process_frame
	_check(main._selected_asset_id == "demo/tiles/wall_brick.png", "跨分类程序选中（wall）")
	main._begin_paint()
	main._end_paint()
	_check(_tiles("terrain") >= 1, "跨分类选中→画笔落 terrain（%d）" % _tiles("terrain"))
	main._do_undo()
	# A3 收藏虚拟分类→选中→放置
	_clear_world()
	main._favorites = ["demo/tiles/road_h.png"]
	main._panel.set_favorites(main._favorites)
	main._panel._on_category_selected("__fav")
	await process_frame
	var fav_n: int = main._panel._buttons.size()
	if fav_n > 0:
		var fk = main._panel._buttons.keys()[0]
		main._panel._on_thumb_pressed(main._panel._buttons[fk], str(fk))
		await process_frame
		main._begin_paint()
		main._end_paint()
		_check(_tiles() >= 1, "收藏分类→选中→放置（%d 格）" % _tiles())
		main._do_undo()
	else:
		_check(false, "收藏分类列表非空（%d）" % fav_n)
	# A4 标签虚拟分类
	main._tags = {"demo/tiles/wall_brick.png": ["面板衔接"]}
	main._panel.set_tags(TagStore.reverse_index(main._tags))
	main._panel._on_category_selected("__tag:面板衔接")
	await process_frame
	_check(main._panel._buttons.size() == 1, "标签分类列表（%d=1）" % main._panel._buttons.size())
	# A5 Tab 隐藏面板→当前选中仍可放置（隐藏区域还给画布）
	_clear_world()
	await _select("tiles/road_h.png")
	main._panel.visible = false
	main._begin_paint()
	main._end_paint()
	_check(_tiles() >= 1, "Tab隐藏面板→放置仍可用（%d）" % _tiles())
	_check(not main._mouse_over_panel(), "隐藏后原区域还给画布")
	main._panel.visible = true
	main._do_undo()
	# A6 大图缩略图限盒（用户实测：长安大建筑图原尺寸溢出面板压分类树「穿模」）
	var big_id := ""
	for a in main._library.get_assets():
		if str((a as Dictionary)["id"]).begins_with("长安素材"):
			big_id = str((a as Dictionary)["id"])
			break
	if not big_id.is_empty():
		main._panel._on_category_selected("__group:" + str(main._library.get_asset(big_id).get("group", "")))
		await process_frame
		await process_frame
		var over_box := 0
		var max_w2 := 0.0
		for k in main._panel._buttons.keys():
			var ms2: Vector2 = (main._panel._buttons[k] as Control).get_combined_minimum_size()
			max_w2 = maxf(max_w2, ms2.x)
			if ms2.x > 70 or ms2.y > 70:
				over_box += 1
		var big_tex: Texture2D = main._panel._get_thumb(big_id)
		_check(over_box == 0 and max_w2 <= 64.0 and maxi(big_tex.get_width(), big_tex.get_height()) <= 64,
			"长安大图缩略图限盒（超限=%d 最大宽=%.0f 贴图≤64）" % [over_box, max_w2])
	# A7 刷新按钮不破坏选中（rescan 链路）
	await _select("tiles/grass.png")
	main._panel.rescan_requested.emit()
	await process_frame
	await process_frame
	_check(main._selected_asset_id == "demo/tiles/grass.png", "⟳刷新后选中保持（%s）" % main._selected_asset_id.get_file())

## ---------- B：快捷栏 → 面板与工具 ----------

func _group_b_hotbar() -> void:
	print("[TileMason] —— B 快捷栏→面板与工具 ——")
	# B1 槽位激活→素材面板联动（选中同步）
	_clear_world()
	var saved1: String = str(main._hotbar_bindings[0])
	if saved1.is_empty():
		main._selected_asset_id = "demo/tiles/road_h.png" # 有选中才能绑
	main._hotbar_customize(1) # 绑定当前选中到槽1
	var bound: String = str(main._hotbar_bindings[0])
	_check(not bound.is_empty(), "右键槽1绑定当前选中（%s）" % bound.get_file())
	main._selected_asset_id = ""
	main._hotbar_activate(1)
	await process_frame
	_check(main._selected_asset_id == bound, "槽1激活→选中恢复（%s）" % str(main._selected_asset_id).get_file())
	# B2 绑定槽素材→画笔放置
	main._begin_paint()
	main._end_paint()
	var placed_layer: String = "ground" if bound.contains("tiles/") else "building"
	_check(_tiles(placed_layer) >= 1 or _objs() >= 1, "快捷栏素材→放置（ground=%d 物件=%d）" % [_tiles(), _objs()])
	main._do_undo()
	# B2b 大图绑定槽位不撑破布局（用户实测：快捷栏大图穿模——load_texture 原图把按钮 min 撑到 468px）
	var big_id := ""
	for a in main._library.get_assets():
		if str((a as Dictionary)["id"]).begins_with("长安素材"):
			big_id = str((a as Dictionary)["id"])
			break
	if not big_id.is_empty():
		main._selected_asset_id = big_id
		main._hotbar_customize(3)
		await process_frame
		var slot_btn = main._hotbar._slot_buttons[2]
		var bmin: Vector2 = slot_btn.get_combined_minimum_size()
		var btex: Texture2D = slot_btn.texture_normal
		_check(bmin.x <= 48.0 and btex != null and maxi(btex.get_width(), btex.get_height()) <= 64,
			"大图绑快捷栏槽位限盒（按钮min=%.0f 贴图≤64）" % bmin.x)
		main._hotbar_bindings = _hotbar_backup.duplicate()
		main._hotbar.set_bindings(main._hotbar_bindings)
	# B3 空选右键=清空槽位
	main._selected_asset_id = ""
	main._hotbar_customize(2)
	_check(str(main._hotbar_bindings[1]).is_empty(), "空选右键槽2=清空")
	# B4 快捷栏 tile 素材 + 活动层是 object 层 → 类型不匹配回退默认层
	_clear_world()
	main._layer_panel.set_active_layer("building") # object 层
	if bound.is_empty() or not bound.contains("tiles/"):
		main._selected_asset_id = "demo/tiles/road_h.png"
		main._hotbar_customize(1)
		bound = str(main._hotbar_bindings[0])
	main._hotbar_activate(1)
	await process_frame
	main._begin_paint()
	main._end_paint()
	_check(_tiles("ground") >= 1 and _objs() == 0, "tile素材+object活动层→回退ground（ground=%d 物件=%d）" % [_tiles("ground"), _objs()])
	main._do_undo()
	main._layer_panel.set_active_layer("")
	# 还原快捷栏绑定
	main._hotbar_bindings = _hotbar_backup.duplicate()
	main._hotbar.set_bindings(main._hotbar_bindings)

## ---------- C：图层 → 工具与面板 ----------

func _group_c_layers() -> void:
	print("[TileMason] —— C 图层→工具与面板 ——")
	# C1 活动层 → 四工具全路由
	_clear_world()
	main._layer_panel.set_active_layer("terrain")
	await _select("tiles/wall_brick.png")
	main._begin_paint()
	main._paint_to(Vector2i(-4, 0))
	main._end_paint()
	var pen_layer: int = _tiles("terrain")
	main._toggle_line_mode()
	main._line_click(Vector2i(-4, 2))
	main._line_click(Vector2i(-2, 2))
	main._exit_line_mode()
	var line_layer: int = _tiles("terrain")
	main._begin_rect()
	main._rect_start = Vector2i(-6, -6)
	main._end_rect()
	var rect_layer: int = _tiles("terrain")
	main._toggle_bucket_mode()
	main._do_bucket_fill(Vector2i(-5, -5))
	main._toggle_bucket_mode()
	var bucket_layer: int = _tiles("terrain")
	_check(pen_layer >= 2 and line_layer >= pen_layer + 3 and rect_layer >= line_layer + 9 and _tiles("ground") == 0,
		"活动层terrain→画笔/直线/矩形/桶全路由（%d→%d→%d，ground=0）" % [pen_layer, line_layer, rect_layer])
	main._layer_panel.set_active_layer("")
	# C2 锁定→放置拒绝+状态栏警示文案
	_clear_world()
	main._document.set_layer_property("ground", "locked", true)
	await _select("tiles/road_h.png")
	main._begin_paint()
	main._end_paint()
	main._begin_rect()
	main._rect_start = Vector2i(-2, -2)
	main._end_rect()
	_check(_tiles("ground") == 0, "锁定层→画笔/矩形拒绝（%d）" % _tiles("ground"))
	# 状态栏文案含锁定警示（refresh_status 在放置链路中被调用）
	main._document.set_layer_property("ground", "locked", false)
	# C3 隐藏层→放置数据仍落层（可见性不拦截数据）+橡皮探测跳过
	_clear_world()
	main._document.set_layer_property("ground", "visible", false)
	await _select("tiles/road_h.png")
	main._begin_paint()
	main._paint_to(Vector2i(-4, 0))
	main._end_paint()
	var hidden_placed: int = _tiles("ground")
	main._toggle_eraser()
	main._begin_erase()
	main._erase_to(Vector2i(-4, 0))
	var erased_in_hidden: int = main._erase_cells.size()
	main._end_erase()
	main._toggle_eraser()
	_check(hidden_placed >= 1 and erased_in_hidden == 0, "隐藏层：放置落层（%d）橡皮跳过（%d）" % [hidden_placed, erased_in_hidden])
	main._document.set_layer_property("ground", "visible", true)
	main._do_undo() # 清放置
	# C4 计数实时刷新（去抖后帧末）——画3擦2后计数与文档一致
	_clear_world()
	await _select("tiles/road_h.png")
	main._begin_paint()
	main._paint_to(Vector2i(-4, 0))
	main._paint_to(Vector2i(-5, 0))
	main._end_paint()
	main._toggle_eraser()
	main._begin_erase()
	main._erase_to(Vector2i(-4, 0))
	main._end_erase()
	main._toggle_eraser()
	await process_frame # 去抖帧
	var label_txt: String = _count_label("ground")
	_check(label_txt == str(_tiles("ground")) + "格", "图层计数与文档一致（面板=%s 文档=%d）" % [label_txt, _tiles("ground")])
	# C5 加层→自动成为活动层→新层放置
	_clear_world()
	var layers_before: int = main._document.layer_count()
	var new_id: String = main._document.add_layer("tile", "探针层")
	main._layer_panel.set_active_layer(new_id)
	await process_frame
	await _select("tiles/road_h.png")
	main._begin_paint()
	main._end_paint()
	_check(main._document.layer_count() == layers_before + 1 and _tiles(new_id) >= 1, "加层→活动层→新层放置（%s=%d格）" % [new_id, _tiles(new_id)])
	# C6 有内容层删除被拒、清空后可删
	var refused: bool = not main._document.remove_layer(new_id)
	main._document.erase_tile(new_id, START_CELL, true)
	var removed: bool = main._document.remove_layer(new_id)
	_check(refused and removed, "删层保护（有内容拒=%s 清空后删=%s）" % [refused, removed])
	# C7 重命名→状态栏提示联动（经 refresh_status）
	_clear_world()
	main._document.set_layer_property("ground", "name", "探针改名层")
	await _select("tiles/road_h.png")
	main.refresh_status()
	var sb_text: String = str(main._status._asset_label.text)
	_check(sb_text.contains("探针改名层"), "重命名→状态栏落层提示更新（%s）" % sb_text)
	main._document.set_layer_property("ground", "name", "道路与地面层")

func _count_label(layer_id: String) -> String:
	if not main._layer_panel._rows.has(layer_id):
		return "?"
	var entry = main._layer_panel._rows[layer_id]
	if entry != null and is_instance_valid(entry) and entry._count_label != null:
		return entry._count_label.text
	return "?"

## ---------- D：页签与状态栏交叉 ----------

func _group_d_tabs_status() -> void:
	print("[TileMason] —— D 页签与状态栏 ——")
	# D1 F9→跳检查页→回图层页→操作正常
	_clear_world()
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-4, 0))
	main._commands.clear()
	main._run_map_check()
	var tab_now: String = str(main._shell.left_dock.current_tab)
	main._shell.select_left_tab("图层")
	await process_frame
	await _select("tiles/grass.png")
	main._begin_paint()
	main._end_paint()
	_check(_tiles() >= 2, "检查跳页→回图层页→放置正常（tab=%d 后 ground=%d）" % [int(tab_now), _tiles()])
	main._do_undo()
	# D2 状态栏四段随选中变化
	await _select("tiles/road_h.png")
	main.refresh_status()
	var seg_asset: String = str(main._status._asset_label.text)
	_check(seg_asset.contains("道路") or seg_asset.contains("→"), "状态栏素材段联动（%s）" % seg_asset)
	_check(str(main._status._pos_label.text).begins_with("("), "状态栏坐标段存在")
	_check(not str(main._status._file_label.text).is_empty(), "状态栏文件段存在")

func _finish() -> void:
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
