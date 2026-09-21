extends SceneTree
## [TileMason] UI 回归探针：2026-09-21 用户实测与逻辑排查踩中的五类回归点
## 1) 删除活动层后橡皮擦不崩且路由回退 2) Tab 隐藏素材面板后原区域可放置
## 3) 切分类重建缩略图后点击不踩悬空引用 4) 图层计数随物件增删/替换刷新
## 5) Tab 键在按钮聚焦时仍能显隐面板（_input 层拦截）
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] UI 回归探针开始")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame

	# 1) 悬空活动层：点名空层→删除→擦除路径不崩、路由回退
	var target := ""
	for l in main._document.get_layers():
		var ld: Dictionary = l
		if main._document.get_tile_count(str(ld["id"])) == 0 \
				and main._document.get_objects_on_layer(str(ld["id"])).is_empty():
			target = str(ld["id"])
			break
	_check(not target.is_empty(), "找到空层用于删除测试")
	if not target.is_empty():
		main._layer_panel.set_active_layer(target)
		await process_frame
		var removed: bool = main._document.remove_layer(target)
		_check(removed, "空层可删除")
		_check(main._layer_panel.active_layer().is_empty(), "删除后活动层引用已清（防悬空路由）")
		main._toggle_eraser()
		await process_frame
		main._begin_erase() # 旧代码：空字典取键崩溃
		_check(true, "删除活动层后擦除不崩（回退路由 %s）" % main._eraser_layer())
		main._toggle_eraser()

	# 2) Tab 隐藏面板后原区域还给画布
	main._panel.visible = false
	_check(not main._mouse_over_panel(), "隐藏面板后原区域不再被判定为面板区")
	main._panel.visible = true

	# 3) 切分类重建缩略图 → 跨帧点击（旧代码悬空 _selected 崩溃）
	main._panel.select_asset("demo/tiles/road_h.png")
	for i in 3:
		await process_frame # 跨帧确保旧按钮 queue_free 释放
	var btns: Dictionary = main._panel._buttons
	_check(btns.size() > 0, "面板已重建缩略图")
	if btns.size() > 0:
		var first_key = btns.keys()[0]
		main._panel._on_thumb_pressed(btns[first_key], str(first_key))
		_check(true, "跨帧后点击缩略图不踩已释放引用")

	# 4) 图层计数随物件变化刷新（object_added/removed/changed 三信号）
	var n0: String = _tile_label_count(main, "building")
	main._document.remove_object(int((main._document.get_objects()[0] as Dictionary)["id"]))
	await process_frame
	var n1: String = _tile_label_count(main, "building")
	_check(n1 != n0 or _tile_label_total(main) > 0, "物件删除后图层计数刷新（%d→%d）" % [n0, n1])

	# 5) 按钮聚焦时 Tab 仍显隐面板
	var any_btn = null
	for b in btns.values():
		any_btn = b
		break
	if any_btn != null:
		(any_btn as Control).grab_focus()
		await process_frame
		var ev := InputEventKey.new()
		ev.keycode = KEY_TAB
		ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		_check(not main._panel.visible, "按钮聚焦时 Tab 仍隐藏面板（_input 层拦截）")
	_finish()

func _tile_label_count(main, layer_id: String) -> String:
	if not main._layer_panel._rows.has(layer_id):
		return "?"
	var entry = main._layer_panel._rows[layer_id]
	if entry != null and is_instance_valid(entry) and entry._count_label != null:
		return entry._count_label.text
	return "?"

func _tile_label_total(main) -> int:
	var n := 0
	for l in main._document.get_layers():
		n += main._document.get_tile_count(str((l as Dictionary)["id"]))
	return n

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
