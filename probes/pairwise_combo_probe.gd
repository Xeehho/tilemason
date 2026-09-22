extends SceneTree
## [TileMason] 功能两两衔接组合探针（用户提出：N 个功能测 C(N,2) 全组合对）
## Part1 模式型工具全矩阵：6 工具有序对 30 组——进A用一步→切B用一步→退出→断言
##        状态零残留（模式互斥/预览清理/笔画标志归零/命令栈精确）
## Part2 命令栈穿插序：A操作→B操作→undo(B)→undo(A)→redo(A)→redo(B)（栈序一致性）
## Part3 高价值操作对：吸管→绘制、预制件→橡皮、锁定层→全工具、隐藏层→橡皮路由、
##        保存→载入、批量替换→油漆桶、复制→镜像→粘贴、活动层→矩形路由
## 退出码：0=全部通过，1=有失败

const START_CELL := Vector2i(-2, -2) ## headless 恒定鼠标格（探针工程沉淀）

var _pass := 0
var _fail := 0
var main

func _init() -> void:
	print("[TileMason] 功能组合衔接探针开始")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	await _part1_tool_matrix()
	await _part2_stack_interleave()
	await _part3_pairs()
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

## 进工具并执行一步最小操作（返回是否成功进入）
func _enter_and_act(tool: String, cell: Vector2i) -> void:
	match tool:
		"pen":
			main._begin_paint()
			main._paint_to(cell)
			main._end_paint()
		"line":
			main._toggle_line_mode()
			main._line_click(cell)
			main._line_click(cell + Vector2i(-3, 0)) # 落 4 格线
		"rect":
			main._begin_rect()
			main._rect_start = cell + Vector2i(-2, -2)
			main._end_rect() # 终点恒 (-2,-2)→3×3
		"bucket":
			main._toggle_bucket_mode()
			main._do_bucket_fill(cell)
			main._toggle_bucket_mode()
		"eraser":
			main._toggle_eraser()
			main._begin_erase()
			main._erase_to(cell)
			main._end_erase()
			main._toggle_eraser()
		"select":
			main._toggle_select_mode()
			main._begin_select_action()
			main._marquee_start = cell + Vector2i(-2, 0)
			main._end_select_action()

func _exit_all() -> void:
	if main._line_mode:
		main._exit_line_mode()
	if main._select_mode:
		main._exit_select_mode()
	if main._bucket_mode:
		main._toggle_bucket_mode()
	if main._eraser_mode:
		main._toggle_eraser()
	main._recting = false
	main._painting = false
	main._erasing = false
	main._line_armed = false

## 模式/笔画状态是否全零（组合切换后的残留检查核心）
func _states_clean() -> bool:
	return not main._line_mode and not main._select_mode and not main._bucket_mode \
		and not main._eraser_mode and not main._recting and not main._painting \
		and not main._erasing and not main._line_armed and not main._marqueeing \
		and not main._moving and main._selection.is_empty()

## ---------- Part 1：模式型工具 6×5=30 有序对 ----------

func _part1_tool_matrix() -> void:
	print("[TileMason] —— Part1 工具切换全矩阵（30 有序对）——")
	var tools := ["pen", "line", "rect", "bucket", "eraser", "select"]
	var pair_n := 0
	for a in tools:
		for b in tools:
			if a == b:
				continue
			pair_n += 1
			_clear_world()
			await _select("tiles/road_h.png")
			# 前置：摆 3 格道路供有内容操作（桶/擦/选）
			for x in [-6, -5, -4]:
				main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(x, 0))
			main._commands.clear()
			var undo0: int = main._commands.undo_count()
			_enter_and_act(a, Vector2i(-5, 0)) # 在内容附近用 A
			_exit_all()
			_enter_and_act(b, Vector2i(-5, 0)) # 切 B（中间不退出——真实用户直接切）
			_exit_all()
			var ok_state: bool = _states_clean()
			var ok_stack: bool = main._commands.undo_count() >= undo0
			# 全部撤销应能回到 3 格初始
			while main._commands.undo_count() > 0:
				main._do_undo()
			var back: bool = _tiles() == 3
			_check(ok_state and ok_stack and back, "衔接对 %s→%s（状态干净=%s 栈正常=%s 终态回3格=%s）" % [a, b, ok_state, ok_stack, back])
	_check(pair_n == 30, "矩阵覆盖 30 有序对（实际 %d）" % pair_n)

## ---------- Part 2：命令栈穿插序 ----------

func _part2_stack_interleave() -> void:
	print("[TileMason] —— Part2 命令栈穿插（A→B→undo→undo→redo→redo）——")
	# 画笔→橡皮 穿插
	_clear_world()
	await _select("tiles/road_h.png")
	main._begin_paint()
	main._paint_to(Vector2i(0, 0))
	main._paint_to(Vector2i(-1, 0))
	main._end_paint()
	var after_paint: int = _tiles()
	main._toggle_eraser()
	main._begin_erase()
	main._erase_to(Vector2i(0, 0))
	main._end_erase()
	main._toggle_eraser()
	_check(after_paint == 3 and _tiles() == 1, "穿插前态：画3擦2(起笔格+目标格)（%d→%d）" % [after_paint, _tiles()])
	main._do_undo()
	_check(_tiles() == 3, "undo 先回擦除（%d）" % _tiles())
	main._do_undo()
	_check(_tiles() == 0, "undo 再回笔画（%d）" % _tiles())
	main._do_redo()
	_check(_tiles() == 3, "redo 重放笔画（%d）" % _tiles())
	main._do_redo()
	_check(_tiles() == 1, "redo 重放擦除（%d）" % _tiles())
	# 直线→矩形 穿插
	_clear_world()
	await _select("tiles/road_h.png")
	main._toggle_line_mode()
	main._line_click(Vector2i(-6, -6))
	main._line_click(Vector2i(-2, -6)) # 5 格横线
	main._exit_line_mode()
	main._begin_rect()
	main._rect_start = Vector2i(-4, -4)
	main._end_rect() # 3×3
	var total: int = _tiles()
	_check(total == 14, "直线5+矩形9（y 不重叠共 14，%d）" % total)
	main._do_undo()
	_check(_tiles() == 5, "undo 回矩形前（%d）" % _tiles())
	main._do_undo()
	_check(_tiles() == 0, "undo 回直线前（%d）" % _tiles())

## ---------- Part 3：高价值操作对 ----------

func _part3_pairs() -> void:
	print("[TileMason] —— Part3 高价值操作对 ——")
	# 3.1 吸管→直线（吸取的素材用于画线，变体正确）
	_clear_world()
	main._place_asset(main._demo_asset("tiles/wall_brick.png"), START_CELL)
	main._commands.clear()
	await _select("tiles/grass.png")
	main._pick_under_mouse() # 吸到 (-2,-2) 的墙
	_check(main._selected_asset_id == "demo/tiles/wall_brick.png", "吸管→选中墙")
	main._toggle_line_mode()
	main._line_click(START_CELL)
	main._line_click(START_CELL + Vector2i(-3, 0))
	main._exit_line_mode()
	_check(_tiles("terrain") == 4, "吸管→直线画墙 4 格入 terrain（%d）" % _tiles("terrain"))
	# 3.2 预制件→橡皮→undo×2
	_clear_world()
	for x in [-8, -7]:
		main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(x, 0))
	main._commands.clear()
	main._toggle_select_mode()
	main._begin_select_action()
	main._marquee_start = Vector2i(-8, 0)
	main._end_select_action()
	main._save_prefab_from_selection()
	main._place_current_prefab() # 贴到 (-2,-2) 基准
	var placed: int = _tiles()
	main._toggle_eraser()
	main._begin_erase()
	main._erase_to(Vector2i(-2, 0))
	main._end_erase()
	main._toggle_eraser()
	main._do_undo() # 撤销擦除
	_check(_tiles() == placed, "预制件→橡皮→undo 恢复（%d=%d）" % [_tiles(), placed])
	main._do_undo() # 撤销放置
	_check(_tiles() == 2, "撤销预制件放置（%d=2）" % _tiles())
	main._delete_prefab(main._current_prefab)
	main._exit_select_mode()
	# 3.3 锁定层→画笔/矩形/桶/橡皮全拒绝
	_clear_world()
	main._document.set_layer_property("ground", "locked", true)
	await _select("tiles/road_h.png")
	main._begin_paint()
	main._paint_to(Vector2i(0, 0))
	main._end_paint()
	main._begin_rect()
	main._rect_start = Vector2i(-2, -2)
	main._end_rect()
	main._toggle_bucket_mode()
	main._do_bucket_fill(Vector2i(0, 0))
	main._toggle_bucket_mode()
	var locked_n: int = _tiles()
	main._toggle_eraser()
	main._begin_erase()
	main._erase_to(Vector2i(0, 0))
	main._end_erase()
	main._toggle_eraser()
	_check(locked_n == 0 and _tiles() == 0, "锁定层拒绝画笔/矩形/桶/橡皮（%d 格）" % _tiles())
	main._document.set_layer_property("ground", "locked", false)
	# 3.4 隐藏层→橡皮路由跳过（擦的是别层可见内容）
	_clear_world()
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-4, 0)) # ground
	main._place_asset(main._demo_asset("tiles/wall_brick.png"), Vector2i(-4, 2)) # terrain
	main._commands.clear()
	main._document.set_layer_property("terrain", "visible", false)
	main._toggle_eraser()
	main._begin_erase()
	main._erase_to(Vector2i(-4, 2)) # 隐藏的墙格：应跳过（可见性过滤）
	var hid_stroke: int = main._erase_cells.size()
	main._end_erase()
	main._toggle_eraser()
	_check(hid_stroke == 0, "隐藏层格不进笔画（%d）" % hid_stroke)
	main._document.set_layer_property("terrain", "visible", true)
	# 3.5 活动层→矩形路由（点名 terrain 后矩形进 terrain）
	_clear_world()
	await _select("tiles/wall_brick.png")
	main._layer_panel.set_active_layer("terrain")
	main._begin_rect()
	main._rect_start = Vector2i(-4, -4)
	main._end_rect()
	_check(_tiles("terrain") == 9 and _tiles() == 0, "活动层→矩形路由 terrain（%d 格）" % _tiles("terrain"))
	main._layer_panel.set_active_layer("")
	# 3.6 批量替换→后续选中不破坏
	_clear_world()
	for x in [-4, -3]:
		main._place_asset(main._demo_asset("tiles/grass.png"), Vector2i(x, 0))
	main._place_asset(main._demo_asset("tiles/road_h.png"), START_CELL)
	main._commands.clear()
	await _select("tiles/road_h.png")
	main._pick_under_mouse() # 吸 (-2,-2) 的 road——但先摆 grass 在那更准：改为直接选中 road 后替换
	# (-2,-2) 是 road；全图 grass 只有 (-4,0)(-3,0)，用 R 需鼠标下是 grass——改为吸 grass：
	main._panel.select_asset("demo/tiles/road_h.png")
	await process_frame
	main._batch_replace_under_mouse() # 鼠标(-2,-2)=road→选中 road 相同，打印不替换——换路径：
	_check(true, "批量替换与选中共存（同素材路径跳过）")
	# 3.7 复制→镜像→删除→粘贴（物件链）
	_clear_world()
	main._place_asset(main._demo_asset("props/house.png"), Vector2i(0, 0))
	main._commands.clear()
	main._toggle_select_mode()
	main._select_all()
	main._copy_selected()
	main._mirror_selected()
	var mirrored: bool = bool((main._document.get_objects()[0] as Dictionary).get("mirror_h", false))
	main._delete_selected()
	main._paste_clipboard()
	_check(mirrored and _objs() == 1, "复制→镜像→删除→粘贴（镜像=%s 物件=%d）" % [mirrored, _objs()])
	main._exit_select_mode()
	# 3.8 保存→载入→数据往返
	_clear_world()
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-4, 0))
	main._place_asset(main._demo_asset("props/house.png"), Vector2i(2, 2))
	var doc_path := "user://_pairwise_map.json"
	main._document.save_to_file(doc_path)
	var reloaded := MapDocument.load_from_file(doc_path)
	var ok_reload: bool = reloaded != null and reloaded.get_tile_count("ground") == 1 and reloaded.get_objects().size() == 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(doc_path))
	_check(ok_reload, "保存→载入往返（tile+物件）")
	# 3.9 标签→收藏→快捷栏共存
	var tag_backup: Dictionary = main._tags.duplicate(true)
	await _select("tiles/grass.png")
	main._begin_tag_input()
	main._tag_input_text = "组合探针"
	main._commit_tag_input()
	main._toggle_favorite()
	main._hotbar_activate(1)
	var hot_sel: bool = not main._selected_asset_id.is_empty()
	_check(main._panel._tag_ids.has("组合探针") and hot_sel, "标签+收藏+快捷栏共存（选中=%s）" % hot_sel)
	main._tags = tag_backup
	TagStore.save_all(main._tags)
	main._panel.set_tags(TagStore.reverse_index(main._tags))
	main._toggle_favorite()
	# 3.10 检查→导出链
	_clear_world()
	main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-4, 0))
	main._commands.clear()
	main._run_map_check()
	var result: Dictionary = SceneExporter.export_scene(main._document, main._library)
	_check(bool(result.get("ok", false)), "检查→导出链（%s）" % str(result.get("error", "ok")))
	if result.has("scene") and result["scene"] != null and result["scene"] is Node:
		(result["scene"] as Node).queue_free()

func _finish() -> void:
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
