extends SceneTree
## [TileMason] 版本轮转探针：模拟 _save_map 的历史滚入链（main._rotate_history 同逻辑），
## 连存 7 次验证 map.json + map.1..map.5 上限、map.6 清尾
## 运行：godot --headless --path . --script res://probes/version_history_probe.gd

func _init() -> void:
	print("[TileMason] 版本轮转探针开始")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://verhist"))
	var doc := MapDocument.new()
	doc.set_tile("ground", Vector2i(0, 0), "x")
	for i in 7:
		var ok_save := doc.save_to_file("user://verhist/map.json")
		if not ok_save:
			_fail("第 %d 次保存失败" % (i + 1))
			_finish()
			return
		for j in range(4, 0, -1):
			var from := "user://verhist/map.%d.json" % j
			var to := "user://verhist/map.%d.json" % (j + 1)
			if FileAccess.file_exists(from):
				DirAccess.copy_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
		DirAccess.copy_absolute(ProjectSettings.globalize_path("user://verhist/map.json"), ProjectSettings.globalize_path("user://verhist/map.1.json"))
		if FileAccess.file_exists("user://verhist/map.6.json"):
			var d := DirAccess.open("user://verhist")
			if d != null:
				d.remove("map.6.json")
	var names := []
	var dir := DirAccess.open("user://verhist")
	dir.list_dir_begin()
	var e := dir.get_next()
	while not e.is_empty():
		if str(e).ends_with(".json"):
			names.append(str(e))
		e = dir.get_next()
	dir.list_dir_end()
	print("[TileMason] 历史文件=", names)
	_check(names.has("map.json") and names.has("map.1.json") and names.has("map.5.json"), "当前档+历史 1..5 齐全")
	_check(not names.has("map.6.json") and names.size() == 6, "上限 5 版（第 6 版被清）")
	_finish()

var _pass := 0
var _fail_count := 0

func _finish() -> void:
	var c := DirAccess.open("user://verhist")
	if c != null:
		c.list_dir_begin()
		var e := c.get_next()
		while not e.is_empty():
			if str(e).ends_with(".json"):
				c.remove(str(e))
			e = c.get_next()
		c.list_dir_end()
		DirAccess.open("user://").remove("verhist")
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail_count += 1
		print("[TileMason] FAIL %s" % name)

func _fail(name: String) -> void:
	_fail_count += 1
	print("[TileMason] FAIL %s" % name)
