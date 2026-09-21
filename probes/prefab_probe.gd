extends SceneTree
## [TileMason] 预制件核心探针：相对化快照、存取往返、清单
## 运行：godot --headless --path . --script res://probes/prefab_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] 预制件探针开始")
	var doc := MapDocument.new()
	# 内容：(10,10) 格 + (12,9) 3×3 物件 → 左上角 (10,9)
	doc.set_tile("ground", Vector2i(10, 10), "g")
	doc.set_tile("ground", Vector2i(11, 10), "g")
	var obj_id := doc.add_object({"asset_id": "house", "layer": "building", "cell": Vector2i(12, 9)})
	var sel := Selection.new()
	sel.add_object(obj_id)
	sel.add_cell("ground", Vector2i(10, 10))
	sel.add_cell("ground", Vector2i(11, 10))

	var snap := Prefab.build_snapshot(doc, sel.object_ids(), sel.cells_by_layer())
	_check(not snap.is_empty(), "快照非空")
	_check((snap["tiles"] as Array).size() == 2, "方块 2 件入快照")
	_check((snap["objects"] as Array).size() == 1, "物件 1 件入快照")
	# 相对坐标：物件 (12,9)→(2,0)，格 (10,10)→(0,1)
	var o0: Dictionary = (snap["objects"] as Array)[0]
	_check(o0["cell"] == [2, 0], "物件格坐标相对化 (12,9)→(2,0)")
	var t0: Dictionary = (snap["tiles"] as Array)[0]
	_check(t0["cell"] == [0, 1], "方块格坐标相对化 (10,10)→(0,1)")
	_check(not o0.has("id"), "物件快照剥离 id（放置时重新分配）")

	var path := Prefab.save_prefab("探针件", snap)
	_check(not path.is_empty(), "保存成功")
	var loaded := Prefab.load_prefab("探针件")
	_check(not loaded.is_empty() and (loaded["tiles"] as Array).size() == 2, "读取往返完整")
	_check(Prefab.list_names().has("探针件"), "清单包含已存预制件")
	_check(Prefab.load_prefab("不存在").is_empty(), "不存在返回空")
	# 清理探针产物
	var dir := DirAccess.open(Prefab.PREFAB_DIR)
	if dir != null:
		dir.remove("探针件.json")
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)
