extends SceneTree
## [TileMason] 渲染层性能压测（自主扩展遗留项评估）：5000/20000 格的数据+视图开销
## 运行：godot --headless --path . --script res://probes/perf_probe.gd
var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] 性能压测开始")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://perf/tiles"))
	var t := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	t.fill(Color(0.3, 0.4, 0.3))
	t.save_png("user://perf/tiles/g.png")
	var f := FileAccess.open("user://perf/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "p", "assets": [{"file": "tiles/g.png", "name": "g", "category": "ground"}]}))
	f = null
	var lib := AssetLibrary.new()
	lib.scan(["user://perf"])

	for n in [5000, 20000]:
		var doc := MapDocument.new()
		var view := MapView.new()
		view.setup(doc, lib)
		var t0 := Time.get_ticks_msec()
		var i := 0
		while i < n: # 方块蛇形铺满 sqrt(n)×sqrt(n)
			doc.set_tile("ground", Vector2i(i % 141, i / 141), "perf/tiles/g.png")
			i += 1
		var t_write := Time.get_ticks_msec() - t0
		var t1 := Time.get_ticks_msec()
		var view2 := MapView.new()
		view2.setup(doc, lib) # 全量重建（新视图）
		var t_rebuild := Time.get_ticks_msec() - t1
		print("[TileMason] %d 格：写入+信号同步 %dms ｜ 全量重建 %dms ｜ Sprite 数 %d" % [n, t_write, t_rebuild, view2.tile_sprite_count()])
		_check(t_write < 8000, "%d 格写入 <8s（实测 %dms）" % [n, t_write])
		_check(view2.tile_sprite_count() == n, "%d 格全量渲染计数一致" % n)
		view.free(); view2.free()
	_cleanup()
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond: _pass += 1; print("[TileMason] PASS %s" % name)
	else: _fail += 1; print("[TileMason] FAIL %s" % name)

func _cleanup() -> void:
	var dir := DirAccess.open("user://perf")
	if dir != null:
		dir.remove("pack.json")
		dir.remove("tiles/g.png")
	var u := DirAccess.open("user://")
	if u != null:
		u.remove("perf")
