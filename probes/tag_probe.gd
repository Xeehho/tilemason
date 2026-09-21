extends SceneTree
## [TileMason] 标签存储探针：输入解析 / 设置与反向索引 / 持久化往返
## 运行：godot --headless --path . --script res://probes/tag_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] 标签探针开始")
	_test_parse()
	_test_set_and_index()
	_test_roundtrip()
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

func _test_parse() -> void:
	_check(TagStore.parse_input("a, b，c") == ["a", "b", "c"], "中英逗号混合解析")
	_check(TagStore.parse_input("  x   y  ") == ["x", "y"], "多空格切分并去空白")
	_check(TagStore.parse_input("a a,b") == ["a", "b"], "去重")
	_check(TagStore.parse_input("1,2,3,4,5,6,7,8,9,10").size() == 8, "最多 8 个")
	_check(TagStore.parse_input("   ").is_empty(), "空串返回空")

func _test_set_and_index() -> void:
	var tags := {}
	tags = TagStore.set_tags(tags, "a1", ["外墙", "石头"])
	tags = TagStore.set_tags(tags, "a2", ["石头"])
	var rev := TagStore.reverse_index(tags)
	_check((rev.get("石头", []) as Array).size() == 2, "反向索引聚合同标签")
	_check((rev.get("外墙", []) as Array) == ["a1"], "单标签索引")
	tags = TagStore.set_tags(tags, "a1", [])
	_check(not tags.has("a1") and tags.has("a2"), "空标签集移除条目")

func _test_roundtrip() -> void:
	var tags := {"demo/x.png": ["红", "屋顶"]}
	_check(TagStore.save_all(tags), "保存成功")
	var loaded := TagStore.load_all()
	_check((loaded.get("demo/x.png", []) as Array) == ["红", "屋顶"], "读取往返一致")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("tags.json") # 清理探针产物
	_check(TagStore.load_all().is_empty(), "清理后为空")
