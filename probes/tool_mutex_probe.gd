extends SceneTree
## [TileMason] 工具模式互斥探针（用户反馈 #5：选直线后橡皮不生效）
var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] 模式互斥探针开始")
	var main: Node2D = load("res://src/main.gd").new()
	var lib := AssetLibrary.new()
	lib.scan(AssetLibrary.default_roots())
	main._library = lib
	main._selected_asset_id = "demo/tiles/road_h.png"
	main._toggle_line_mode()
	_check(main._line_mode, "进入直线模式")
	main._toggle_eraser()
	_check(main._eraser_mode and not main._line_mode, "E 进橡皮时直线自动退出（反馈 #5 场景）")
	main._toggle_select_mode()
	_check(main._select_mode and not main._eraser_mode, "S 进选择时橡皮自动退出")
	main._toggle_bucket_mode()
	_check(main._bucket_mode and not main._select_mode, "G 进油漆桶时选择自动退出")
	main._toggle_bucket_mode()
	main._toggle_line_mode()
	main._toggle_line_mode()
	_check(not main._line_mode, "L 双击退出直线")
	main.free()
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond: _pass += 1; print("[TileMason] PASS %s" % name)
	else: _fail += 1; print("[TileMason] FAIL %s" % name)
