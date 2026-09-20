extends SceneTree
## [TileMason] 素材库探针（无人值守验证）：在 user:// 下构造夹具素材包实测扫描/清单解析/分类/
## 锚点默认与覆盖/cells 推导/图像与纹理缓存/坏包与缺文件容错/重复扫描幂等
## 运行：godot --headless --path . --script res://probes/asset_library_probe.gd
## 退出码：0=全部通过，1=有失败

var _pass := 0
var _fail := 0

const FIXTURE_ROOT := "user://probe_packs"

func _init() -> void:
	print("[TileMason] 素材库探针开始")
	_setup_fixtures()
	_test_scan()
	_test_defaults()
	_test_images()
	_cleanup_fixtures()
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

## 构造夹具：pack_a（4 件，含显式/缺省字段组合）、pack_b（缺清单，应跳过）、pack_c（1 件有效 + 1 件缺文件）
func _setup_fixtures() -> void:
	_mkdir(FIXTURE_ROOT.path_join("pack_a/tiles"))
	_mkdir(FIXTURE_ROOT.path_join("pack_a/props"))
	_mkdir(FIXTURE_ROOT.path_join("pack_b"))
	_mkdir(FIXTURE_ROOT.path_join("pack_c"))
	_make_png(FIXTURE_ROOT.path_join("pack_a/tiles/grass.png"), 16, Color(0.2, 0.7, 0.2))
	_make_png(FIXTURE_ROOT.path_join("pack_a/tiles/road.png"), 16, Color(0.4, 0.4, 0.4))
	_make_png(FIXTURE_ROOT.path_join("pack_a/props/tree.png"), 48, Color(0.1, 0.5, 0.1))
	_make_png(FIXTURE_ROOT.path_join("pack_a/props/house.png"), 48, Color(0.8, 0.6, 0.3))
	_make_png(FIXTURE_ROOT.path_join("pack_c/stone.png"), 16, Color(0.5, 0.5, 0.6))
	_write_json(FIXTURE_ROOT.path_join("pack_a/pack.json"), {
		"name": "夹具包A",
		"assets": [
			{"file": "tiles/grass.png", "name": "草地", "category": "ground"},
			{"file": "tiles/road.png", "name": "道路", "category": "road", "connections": ["left", "right"]},
			{"file": "props/tree.png", "category": "tree"},
			{"file": "props/house.png", "category": "building", "anchor": "bottom_center", "cells": [2, 2]},
		],
	})
	_write_json(FIXTURE_ROOT.path_join("pack_c/pack.json"), {
		"name": "夹具包C",
		"assets": [
			{"file": "stone.png", "category": "deco"},
			{"file": "ghost.png", "category": "deco"},
		],
	})

func _test_scan() -> void:
	var lib := AssetLibrary.new()
	var total := lib.scan([FIXTURE_ROOT])
	_check(total == 5, "素材总数 5（pack_a 4 + pack_c 1，缺文件条目跳过）")
	_check(lib.pack_count() == 2, "包数 2（缺 pack.json 的 pack_b 跳过）")
	_check(lib.get_categories() == ["ground", "road", "building", "tree", "deco"], "分类索引按固定顺序")
	_check(lib.get_assets_by_category("ground").size() == 1, "按分类取素材")
	_check(lib.get_asset("pack_a/tiles/grass.png")["name"] == "草地", "按 id 取素材")
	_check(lib.get_asset("pack_a/props/ghost.png").is_empty(), "不存在 id 返回空")
	var again := lib.scan([FIXTURE_ROOT])
	_check(again == 5 and lib.pack_count() == 2, "重复扫描幂等（不翻倍）")

func _test_defaults() -> void:
	var lib := AssetLibrary.new()
	lib.scan([FIXTURE_ROOT])
	var grass := lib.get_asset("pack_a/tiles/grass.png")
	var road := lib.get_asset("pack_a/tiles/road.png")
	var tree := lib.get_asset("pack_a/props/tree.png")
	var house := lib.get_asset("pack_a/props/house.png")
	_check(grass["anchor"] == "top_left", "规则方块类锚点默认左上角")
	_check(tree["anchor"] == "bottom_center", "独立物件锚点默认底边中心")
	_check(house["anchor"] == "bottom_center", "清单显式锚点生效")
	_check(grass["cells"] == Vector2i(1, 1), "16px 推导 1×1 占格")
	_check(tree["cells"] == Vector2i(3, 3), "48px 推导 3×3 占格")
	_check(house["cells"] == Vector2i(2, 2), "清单显式 cells 优先于尺寸推导")
	_check((road["connections"] as Array) == ["left", "right"], "连接方向声明保留（P2 自动连接用）")
	_check(lib.get_asset("pack_c/stone.png")["cells"] == Vector2i(1, 1), "pack_c 有效素材正常入库")

func _test_images() -> void:
	var lib := AssetLibrary.new()
	lib.scan([FIXTURE_ROOT])
	var img1 := lib.load_image("pack_a/tiles/grass.png")
	_check(img1 != null and img1.get_width() == 16 and img1.get_height() == 16, "加载原图尺寸正确")
	var img2 := lib.load_image("pack_a/tiles/grass.png")
	_check(img1 != null and img2 != null and img1.get_instance_id() == img2.get_instance_id(), "图像缓存命中（同一实例）")
	var tex := lib.load_texture("pack_a/props/tree.png")
	var tex2 := lib.load_texture("pack_a/props/tree.png")
	_check(tex != null and tex.get_width() == 48, "缩略图纹理尺寸正确")
	_check(tex != null and tex2 != null and tex.get_instance_id() == tex2.get_instance_id(), "纹理缓存命中（同一实例）")
	_check(lib.load_image("pack_a/nope.png") == null, "不存在的素材返回 null")

func _mkdir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func _make_png(path: String, size: int, color: Color) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.save_png(path)

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))

func _cleanup_fixtures() -> void:
	_remove_dir_recursive(FIXTURE_ROOT)

func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if str(entry) != "." and str(entry) != "..":
			names.append(str(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	for n in names:
		if dir.dir_exists(n):
			_remove_dir_recursive(path.path_join(n))
		else:
			dir.remove(n)
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
