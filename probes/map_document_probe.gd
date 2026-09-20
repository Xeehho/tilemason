extends SceneTree
## [TileMason] 地图文档模型探针（无人值守验证，dev-pitfalls 4/5：纯逻辑无帧等待，末尾 quit）
## 覆盖：默认图层栈 / 方块读写与锁定保护 / 自由物件增改删 / 命令栈撤销重做 / 序列化与文件往返
## 运行：godot --headless --path . --script res://probes/map_document_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] 地图文档探针开始")
	_test_default_layers()
	_test_tile_ops()
	_test_layer_lock()
	_test_objects()
	_test_fill_rect()
	_test_command_stack()
	_test_undo_with_document()
	_test_serialization()
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

func _test_default_layers() -> void:
	var doc := MapDocument.new()
	_check(doc.layer_count() == 5, "默认五层图层栈")
	_check(doc.get_layer("terrain")["type"] == "tile" and doc.get_layer("ground")["type"] == "tile", "底部两层为 tile 层")
	_check(doc.get_layer("foreground")["type"] == "object", "前景层为 object 层")
	_check(doc.get_layer("nope").is_empty(), "不存在图层返回空")
	_check(not doc.is_layer_locked("ground"), "默认不锁定")

func _test_tile_ops() -> void:
	var doc := MapDocument.new()
	var old: Variant = doc.set_tile("ground", Vector2i(1, 2), "road_straight")
	_check(old != null and (old as Dictionary).is_empty(), "空格放置返回空旧值")
	_check(doc.get_tile("ground", Vector2i(1, 2))["asset_id"] == "road_straight", "读回方块")
	old = doc.set_tile("ground", Vector2i(1, 2), "floor_a")
	_check((old as Dictionary)["asset_id"] == "road_straight", "覆盖返回旧条目")
	_check(doc.set_tile("bad_layer", Vector2i.ZERO, "x") == null, "非法图层拒绝")
	old = doc.erase_tile("ground", Vector2i(1, 2))
	_check((old as Dictionary)["asset_id"] == "floor_a", "擦除返回被清条目")
	_check(doc.get_tile("ground", Vector2i(1, 2)).is_empty(), "擦除后为空")

func _test_layer_lock() -> void:
	var doc := MapDocument.new()
	doc.set_layer_property("ground", "locked", true)
	_check(doc.set_tile("ground", Vector2i.ZERO, "road") == null, "锁定层放置被拒")
	_check(doc.get_tile("ground", Vector2i.ZERO).is_empty(), "锁定层数据未变")
	_check(doc.set_tile("ground", Vector2i.ZERO, "road", true) != null, "force 可写（撤销恢复路径）")
	doc.set_layer_property("ground", "locked", false)
	_check(doc.set_tile("ground", Vector2i.ZERO, "road") != null, "解锁后可写")
	_check(not doc.set_layer_property("ground", "id", "hack"), "图层 id 不可改")

func _test_objects() -> void:
	var doc := MapDocument.new()
	var id1 := doc.add_object({"asset_id": "house_a", "layer": "building", "cell": Vector2i(4, 7)})
	var id2 := doc.add_object({"asset_id": "tree_a", "layer": "deco"})
	_check(id1 > 0 and id2 > 0 and id1 != id2, "物件 id 唯一自增")
	var obj := doc.get_object(id1)
	_check(obj["cell"] == Vector2i(4, 7) and obj["anchor"] == "bottom_center" and obj["scale"] == 1, "缺省字段补全（锚点/缩放）")
	_check(doc.get_objects_on_layer("deco").size() == 1, "按图层取物件")
	_check(doc.add_object({"asset_id": "x", "layer": "ground"}) == -1, "tile 层拒绝挂物件")
	_check(doc.add_object({"layer": "deco"}) == -1, "缺 asset_id 拒绝")
	var oldv: Variant = doc.update_object(id1, {"cell": Vector2i(5, 7), "mirror_h": true})
	_check(oldv is Dictionary and (oldv as Dictionary)["cell"] == Vector2i(4, 7), "更新返回旧值")
	_check(doc.get_object(id1)["cell"] == Vector2i(5, 7) and doc.get_object(id1)["mirror_h"], "更新生效")
	_check(doc.update_object(999, {}) == null, "更新不存在物件返回 null")
	var removed: Variant = doc.remove_object(id2)
	_check(removed is Dictionary and (removed as Dictionary)["asset_id"] == "tree_a", "删除返回被删物件")
	_check(doc.remove_object(id2) == null, "重复删除返回 null")

func _test_fill_rect() -> void:
	var doc := MapDocument.new()
	var stack := CommandStack.new()
	doc.set_tile("ground", Vector2i(0, 0), "old_floor") # 预置旧内容验证覆盖与恢复
	var entries := doc.fill_rect("ground", Rect2i(Vector2i(0, 0), Vector2i(2, 3)), "floor_a")
	_check(entries.size() == 6, "矩形填充 2×3 全部应用（覆盖模式含旧格）")
	_check(doc.get_tile("ground", Vector2i(1, 2))["asset_id"] == "floor_a", "区域内格已写入")
	var do_fill := func() -> void:
		for e in entries:
			doc.set_tile("ground", (e as Dictionary)["cell"], "floor_a", true)
	var undo_fill := func() -> void:
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			var prev: Dictionary = e["old"]
			if prev.is_empty():
				doc.erase_tile("ground", e["cell"], true)
			else:
				doc.set_tile("ground", e["cell"], str(prev["asset_id"]), true)
	stack.push("矩形填充", do_fill, undo_fill)
	stack.undo()
	_check(doc.get_tile("ground", Vector2i(1, 2)).is_empty() and doc.get_tile("ground", Vector2i(0, 0))["asset_id"] == "old_floor", "整段撤销恢复原状（含旧格）")
	stack.redo()
	_check(doc.get_tile("ground", Vector2i(1, 2))["asset_id"] == "floor_a", "重做整段恢复")
	doc.set_tile("ground", Vector2i(5, 5), "keep_me")
	var entries2 := doc.fill_rect("ground", Rect2i(Vector2i(5, 5), Vector2i(2, 2)), "floor_b", true)
	_check(entries2.size() == 3 and doc.get_tile("ground", Vector2i(5, 5))["asset_id"] == "keep_me", "跳过模式保留已有内容")
	doc.set_layer_property("ground", "locked", true)
	_check(doc.fill_rect("ground", Rect2i(Vector2i(9, 9), Vector2i.ONE), "x").is_empty(), "锁定层拒绝矩形填充")
	doc.set_layer_property("ground", "locked", false)

func _test_command_stack() -> void:
	var stack := CommandStack.new()
	var log_arr: Array = [] # 引用容器：闭包内外共享（dev-pitfalls 11）
	stack.push("a",
		func() -> void: log_arr.append("do_a"),
		func() -> void: log_arr.append("undo_a"))
	stack.push("b",
		func() -> void: log_arr.append("do_b"),
		func() -> void: log_arr.append("undo_b"))
	_check(log_arr == ["do_a", "do_b"], "push 立即执行")
	stack.undo()
	stack.undo()
	_check(log_arr == ["do_a", "do_b", "undo_b", "undo_a"], "撤销按逆序回滚")
	stack.redo()
	# 标准语义：undo 逆序回滚 b、a，redo 先重放最后被撤销的 a
	_check(log_arr == ["do_a", "do_b", "undo_b", "undo_a", "do_a"], "重做重放最后撤销项")

	var signal_log: Array = []
	stack.changed.connect(func(cu: bool, cr: bool) -> void: signal_log.append([cu, cr]))
	stack.push("c", func() -> void: pass, func() -> void: pass)
	_check(signal_log.size() > 0 and signal_log.back() == [true, false], "changed 信号携带可用状态")
	stack.undo()
	stack.undo()
	_check(not stack.undo(), "撤销到空返回 false")

	stack.push("x", func() -> void: pass, func() -> void: pass)
	_check(stack.redo_count() == 0 and not stack.redo(), "新编辑清空重做栈")

	var small := CommandStack.new()
	small.history_limit = 3
	for i in range(5):
		small.push("cmd%d" % i, func() -> void: pass, func() -> void: pass)
	_check(small.undo_count() == 3, "历史超限丢弃最旧")

func _test_undo_with_document() -> void:
	var doc := MapDocument.new()
	var stack := CommandStack.new()
	var cell := Vector2i(2, 3)
	doc.set_tile("ground", cell, "old_floor") # 预置旧方块，验证撤销能恢复原值
	var ctx := {} # 引用容器：do 首次执行捕获旧值，供 undo/redo 共享
	var do_edit := func() -> void:
		if ctx.get("captured", false):
			doc.set_tile("ground", cell, "new_floor", true)
		else:
			ctx["old"] = doc.set_tile("ground", cell, "new_floor", true)
			ctx["captured"] = true
	var undo_edit := func() -> void:
		var prev: Dictionary = ctx.get("old", {})
		if prev.is_empty():
			doc.erase_tile("ground", cell, true)
		else:
			doc.set_tile("ground", cell, str(prev["asset_id"]), true)
	stack.push("改地砖", do_edit, undo_edit)
	_check(doc.get_tile("ground", cell)["asset_id"] == "new_floor", "命令执行改值")
	stack.undo()
	_check(doc.get_tile("ground", cell)["asset_id"] == "old_floor", "撤销恢复旧值")
	stack.redo()
	_check(doc.get_tile("ground", cell)["asset_id"] == "new_floor", "重做再次生效")
	stack.undo()
	_check(doc.get_tile("ground", cell)["asset_id"] == "old_floor", "二次撤销仍正确（旧值只捕获一次）")

func _test_serialization() -> void:
	var doc := MapDocument.new()
	doc.set_tile("ground", Vector2i(-3, 9), "road_corner")
	doc.set_tile("terrain", Vector2i(0, 0), "grass")
	doc.add_object({"asset_id": "house_a", "layer": "building", "cell": Vector2i(10, 4), "mirror_h": true})
	doc.set_layer_property("deco", "locked", true)
	doc.set_layer_property("foreground", "opacity", 0.8)
	var first := JSON.stringify(doc.to_dict())
	var parsed: Variant = JSON.parse_string(first)
	var doc2 := MapDocument.from_dict(parsed as Dictionary)
	_check(JSON.stringify(doc2.to_dict()) == first, "序列化 JSON 往返一致（含锁定/透明度/负坐标）")
	_check(doc2.get_object(1)["cell"] == Vector2i(10, 4), "坐标 int 矫正（JSON float 还原）")
	_check(doc2.is_layer_locked("deco"), "锁定状态保留")

	var path := "user://probe_map_roundtrip.json"
	_check(doc.save_to_file(path), "写地图文件")
	var doc3 := MapDocument.load_from_file(path)
	_check(doc3 != null and JSON.stringify(doc3.to_dict()) == first, "文件读写往返一致")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("probe_map_roundtrip.json") # 清理探针临时文件
