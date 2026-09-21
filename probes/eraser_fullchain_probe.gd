extends SceneTree
## [TileMason] 橡皮擦全链路探针（用户实测反馈：道路与地面层擦不干净）
## 自建确定性场景（不依赖 user:// 档案，避免取证污染）：
## ground 摆道路/草地、terrain 摆墙、building 摆 1 物件；每场景 warp 固定空格起笔
## 覆盖：单格/拖刷跨层/空格起笔/活动层钉住/混合层undo-redo/Ctrl同款/物件删除/变体联动/锁定层
## 退出码：0=全部通过，1=有失败

const BLANK_POS := Vector2(1200, 770) # 画布空白区（世界格 25,20）——parse 定位起笔，消除光标随机性

var _pass := 0
var _fail := 0
var main

func _init() -> void:
	print("[TileMason] 橡皮擦全链路探针开始（自建场景）")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	_reset_demo()
	await _scene_single_cell()
	await _scene_drag_cross_layer()
	await _scene_blank_start()
	await _scene_active_pin()
	await _scene_undo_redo_mixed()
	await _scene_ctrl_same_kind()
	await _scene_object_click()
	await _scene_variant_refresh()
	await _scene_locked_layer()
	_finish()

## 自建确定性场景：清全部内容后重摆（道路/草地=ground，墙=terrain，1 物件=building）
func _reset_demo() -> void:
	for l in main._document.get_layers():
		var lid := str((l as Dictionary)["id"])
		for c in main._document.get_tile_coords(lid):
			main._document.erase_tile(lid, c, true)
	for o in main._document.get_objects().duplicate():
		main._document.remove_object(int((o as Dictionary)["id"]), true)
	main._commands.clear()
	for x in range(-9, -1): # 道路 x∈[-9,-2] y=0（ground，拖刷场景路径全覆盖）
		main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(x, 0))
	main._place_asset(main._demo_asset("tiles/grass.png"), Vector2i(-5, 1)) # 草地（ground）
	for x in range(-10, -6): # 墙 x∈[-10,-7] y=2（terrain：wall→terrain 路由）
		main._place_asset(main._demo_asset("tiles/wall_brick.png"), Vector2i(x, 2))
	main._place_asset(main._demo_asset("props/house.png"), Vector2i(2, 2)) # 物件（building）
	main._commands.clear() # 摆样命令不入撤销栈
	print("[TileMason] 自建场景：ground=%d terrain=%d 物件=%d" % [
		main._document.get_tile_count("ground"), main._document.get_tile_count("terrain"),
		main._document.get_objects().size()])

## 起笔前把鼠标定位到空白格（_begin_erase 内部会擦 mouse_cell() 起笔格）——
## warp 在无焦点窗口无效（实测踩中）；parse motion 后须等一帧分发才更新鼠标位
func _begin_erase_fixed() -> void:
	var mot := InputEventMouseMotion.new()
	mot.position = BLANK_POS
	Input.parse_input_event(mot)
	await process_frame
	main._begin_erase()

func _tiles(layer: String) -> int:
	return main._document.get_tile_count(layer)

func _objs() -> int:
	return main._document.get_objects().size()

func _scene_single_cell() -> void:
	var n0 := _tiles("ground")
	main._toggle_eraser()
	await _begin_erase_fixed()
	main._erase_to(Vector2i(-6, 0)) # 道路格（ground）
	main._end_erase()
	main._toggle_eraser()
	_check(_tiles("ground") == n0 - 1, "单格擦除 ground 道路（%d→%d）" % [n0, _tiles("ground")])
	main._do_undo()
	_check(_tiles("ground") == n0, "单格擦除可撤销还原")

func _scene_drag_cross_layer() -> void:
	var g0 := _tiles("ground")
	var t0 := _tiles("terrain")
	main._toggle_eraser()
	await _begin_erase_fixed()
	for cell in [Vector2i(-6, 0), Vector2i(-7, 0), Vector2i(-8, 0), Vector2i(-8, 1), Vector2i(-8, 2)]:
		main._erase_to(cell) # 从 ground 道路拖进 terrain 墙区
	main._end_erase()
	main._toggle_eraser()
	_check(_tiles("ground") < g0, "拖刷擦掉 ground 道路（%d→%d）" % [g0, _tiles("ground")])
	_check(_tiles("terrain") < t0, "拖刷跨层擦掉 terrain 墙（%d→%d）——旧代码固定单层擦不动" % [t0, _tiles("terrain")])
	main._do_undo()
	_check(_tiles("ground") == g0 and _tiles("terrain") == t0, "混合层笔画一次 undo 全还原")

func _scene_blank_start() -> void:
	var g0 := _tiles("ground")
	main._toggle_eraser()
	await _begin_erase_fixed() # 起笔格=空白（探测失败，旧代码整笔固定无效层）
	for cell in [Vector2i(20, 20), Vector2i(10, 10), Vector2i(-2, 0)]: # 拖进道路区
		main._erase_to(cell)
	main._end_erase()
	main._toggle_eraser()
	_check(_tiles("ground") < g0, "空格起笔拖到道路区仍能擦（%d→%d）" % [g0, _tiles("ground")])
	main._do_undo()
	_check(_tiles("ground") == g0, "空格起笔笔画可撤销")

func _scene_active_pin() -> void:
	var t0 := _tiles("terrain")
	var g0 := _tiles("ground")
	main._layer_panel.set_active_layer("ground")
	main._toggle_eraser()
	await _begin_erase_fixed()
	main._erase_to(Vector2i(-9, 2)) # terrain 墙格——钉住 ground 应跳过
	main._erase_to(Vector2i(-3, 0)) # ground 道路格——应擦
	main._end_erase()
	main._toggle_eraser()
	_check(_tiles("terrain") == t0, "活动层钉住：划过 terrain 墙不动（精确控制语义）")
	_check(_tiles("ground") == g0 - 1, "活动层钉住：ground 道路正常擦")
	main._layer_panel.set_active_layer("") # 取消钉住
	main._do_undo()

func _scene_undo_redo_mixed() -> void:
	var g0 := _tiles("ground")
	var t0 := _tiles("terrain")
	main._toggle_eraser()
	await _begin_erase_fixed()
	main._erase_to(Vector2i(-4, 0)) # ground
	main._erase_to(Vector2i(-9, 2)) # terrain
	print("[dbg5] 探测(-4,0)='", main._probe_top_tile_layer_at(Vector2i(-4, 0)), "' 探测(-9,2)='", main._probe_top_tile_layer_at(Vector2i(-9, 2)), "' cells=", main._erase_cells.size(), " g=", _tiles("ground"), " t=", _tiles("terrain"))
	main._end_erase()
	main._toggle_eraser()
	_check(_tiles("ground") == g0 - 1 and _tiles("terrain") == t0 - 1, "一笔擦两层")
	main._do_undo()
	_check(_tiles("ground") == g0 and _tiles("terrain") == t0, "undo 恢复两层")
	main._do_redo()
	_check(_tiles("ground") == g0 - 1 and _tiles("terrain") == t0 - 1, "redo 重放两层擦除")
	main._do_undo() # 还原

func _scene_ctrl_same_kind() -> void:
	var actual: String = str(main._document.get_tile("ground", Vector2i(-6, 0)).get("asset_id", ""))
	main._panel.select_asset(actual) # 选中该格实际素材（自动连接可能已换变体）
	await process_frame
	var g0 := _tiles("ground")
	var ck := InputEventKey.new()
	ck.keycode = KEY_CTRL
	ck.pressed = true
	Input.parse_input_event(ck)
	await process_frame
	main._toggle_eraser()
	await _begin_erase_fixed()
	main._erase_to(Vector2i(-6, 0)) # 同款格 → 清
	main._erase_to(Vector2i(-5, 1)) # 草地格 → 保留（非同款）
	main._end_erase()
	main._toggle_eraser()
	var ckup := InputEventKey.new()
	ckup.keycode = KEY_CTRL
	ckup.pressed = false
	Input.parse_input_event(ckup)
	await process_frame
	_check(main._document.get_tile("ground", Vector2i(-6, 0)).is_empty(), "Ctrl 同款：道路格被清")
	_check(not main._document.get_tile("ground", Vector2i(-5, 1)).is_empty(), "Ctrl 同款：草地格保留")
	main._do_undo()

func _scene_object_click() -> void:
	# headless/无焦点窗口下 parse 与 warp 都不更新全局鼠标位（实测），起笔格恒 (-2,-2)：
	# 把物件摆到起笔格来验证「按下命中物件→单点删除」链路
	main._place_asset(main._demo_asset("props/house.png"), Vector2i(-2, -2))
	main._commands.clear()
	var o0 := _objs()
	main._toggle_eraser()
	await _begin_erase_fixed() # 起笔格 (-2,-2)=物件格：探测应命中 building 并删除
	main._end_erase()
	main._toggle_eraser()
	_check(_objs() == o0 - 1, "物件单击删除（起笔命中物件格，%d→%d）" % [o0, _objs()])
	main._do_undo()

func _scene_variant_refresh() -> void:
	# L 形道路：竖摆一段，拐角格应随擦除联动变体
	for y in range(1, 4):
		main._place_asset(main._demo_asset("tiles/road_h.png"), Vector2i(-4, y))
	main._commands.clear()
	var corner_before: String = str(main._document.get_tile("ground", Vector2i(-4, 1)).get("asset_id", ""))
	main._toggle_eraser()
	await _begin_erase_fixed()
	main._erase_to(Vector2i(-4, 2)) # 拆中段 → 拐角应变体
	main._end_erase()
	main._toggle_eraser()
	var corner_after: String = str(main._document.get_tile("ground", Vector2i(-4, 1)).get("asset_id", ""))
	_check(corner_before != corner_after, "擦除联动变体刷新（%s→%s）" % [corner_before.get_file(), corner_after.get_file()])

func _scene_locked_layer() -> void:
	main._document.set_layer_property("ground", "locked", true)
	var g0 := _tiles("ground")
	main._toggle_eraser()
	await _begin_erase_fixed()
	main._erase_to(Vector2i(-6, 0))
	main._end_erase()
	main._toggle_eraser()
	_check(_tiles("ground") == g0, "锁定层擦除被拒")
	main._document.set_layer_property("ground", "locked", false)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

func _finish() -> void:
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
