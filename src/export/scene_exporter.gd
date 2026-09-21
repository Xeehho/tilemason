class_name SceneExporter
extends RefCounted
## 场景导出（design.md §10/§11 P4）：MapDocument → 形态A 运行时场景
## SortRoot(y_sort) → GroundLayer(TileMapLayer·atlas) + PropsLayer(TileMapLayer·scenes collection)
## 配方来源 dev-pitfalls 22（探针全过直接抄）：件根=底边中心、Sprite offset=-h/2、
## 碰撞=底边脚印；TileSet 注册的 PackedScene 先落盘再 load（pitfall 20，禁内嵌）

const EXPORT_DIR := "user://export"

static var _scene_tile_cache := {} # asset_id -> scene tile id（单次导出内有效）

## 导出主入口：返回 {ok, path, tiles, props, warnings}
static func export_scene(doc: MapDocument, lib: AssetLibrary, file_name := "map") -> Dictionary:
	var warnings: Array = []
	_scene_tile_cache = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
	var root := Node2D.new()
	root.name = "TileMasonMap"
	var sort_root := Node2D.new()
	sort_root.name = "SortRoot"
	sort_root.y_sort_enabled = true
	root.add_child(sort_root)

	# ---- 地面层：单 TileSet 动态 atlas（tile_size=grid_px 全局唯一）----
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(doc.grid_px, doc.grid_px)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = _placeholder_atlas_texture()
	tile_set.add_source(atlas, 0)
	var ground := TileMapLayer.new()
	ground.name = "GroundLayer"
	ground.tile_set = tile_set
	sort_root.add_child(ground)
	var atlas_cursor := Vector2i.ZERO
	var asset_to_atlas := {} # asset_id -> atlas 坐标
	var tile_count := 0
	for layer in doc.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if str((layer as Dictionary)["type"]) != "tile":
			continue
		for coords in doc.get_tile_coords(layer_id):
			var entry := doc.get_tile(layer_id, coords as Vector2i)
			var asset_id := str(entry.get("asset_id", ""))
			if not asset_to_atlas.has(asset_id):
				atlas.create_tile(atlas_cursor)
				asset_to_atlas[asset_id] = atlas_cursor
				atlas_cursor += Vector2i(1, 0)
				if atlas_cursor.x >= 64: # atlas 宽度上限，换行
					atlas_cursor = Vector2i(0, atlas_cursor.y + 1)
			ground.set_cell(coords as Vector2i, 0, asset_to_atlas[asset_id])
			tile_count += 1
	warnings.append("地面层为占位 atlas（数据/坐标完整，纹理由运行时素材包对位）")

	# ---- 物件层：scenes collection（每素材一个子场景文件，先落盘再注册）----
	var props := TileMapLayer.new()
	props.name = "PropsLayer"
	props.y_sort_enabled = true
	props.tile_set = _props_tile_set(doc, lib, warnings)
	sort_root.add_child(props)
	var prop_count := 0
	for obj in doc.get_objects():
		var o := obj as Dictionary
		var asset_id := str(o["asset_id"])
		if not _scene_tile_cache.has(asset_id):
			continue
		props.set_cell(o["cell"] as Vector2i, 0, Vector2i(int(_scene_tile_cache[asset_id]), 0)) # scene tile id 编码进 atlas 坐标位
		prop_count += 1

	# ---- 交互锚点（design.md §9.2/§11 P4）：每物件一个 Marker2D，命名=物件 id，
	# 位置=占格底边中心 + interaction_offset（供运行时 NPC/任务定位）----
	var anchors := Node2D.new()
	anchors.name = "InteractionAnchors"
	root.add_child(anchors)
	for obj in doc.get_objects():
		var o := obj as Dictionary
		var asset := lib.get_asset(str(o["asset_id"]))
		var cells: Vector2i = Vector2i.ONE if asset.is_empty() else asset["cells"]
		var marker := Marker2D.new()
		marker.name = "Anchor_%d" % int(o["id"])
		var tl: Vector2i = o["cell"]
		marker.position = Vector2(
			float(tl.x) * doc.grid_px + cells.x * doc.grid_px / 2.0,
			float(tl.y) * doc.grid_px + cells.y * doc.grid_px) + Vector2(o.get("interaction_offset", Vector2i.ZERO) as Vector2i) * doc.grid_px
		anchors.add_child(marker)

	# ---- 打包（pitfall 19：pack 前全子树 owner=root）----
	sort_root.owner = root
	ground.owner = root
	props.owner = root
	anchors.owner = root
	for marker in anchors.get_children():
		(marker as Node2D).owner = root
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "path": "", "tiles": 0, "props": 0, "warnings": ["pack 失败"]}
	var path := EXPORT_DIR + "/" + file_name + ".tscn"
	if ResourceSaver.save(packed, path) != OK:
		root.free()
		return {"ok": false, "path": "", "tiles": 0, "props": 0, "warnings": ["保存失败"]}
	if root.is_inside_tree():
		root.queue_free()
	else:
		root.free() # 无 SceneTree（自定义 MainLoop/纯探针）时 queue_free 不可用
	return {"ok": true, "path": path, "tiles": tile_count, "props": prop_count, "warnings": warnings}

## 物件 TileSet：scenes collection；每素材生成子场景文件（底边中心配方）落盘后注册
static func _props_tile_set(doc: MapDocument, lib: AssetLibrary, warnings: Array) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(doc.grid_px, doc.grid_px)
	var scenes := TileSetScenesCollectionSource.new()
	ts.add_source(scenes, 0)
	for obj in doc.get_objects():
		var o := obj as Dictionary
		var asset_id := str(o["asset_id"])
		if _scene_tile_cache.has(asset_id):
			continue
		var asset := lib.get_asset(asset_id)
		if asset.is_empty():
			warnings.append("物件素材缺失，跳过：" + asset_id)
			continue
		var tex := lib.load_texture(asset_id)
		if tex == null:
			warnings.append("物件纹理加载失败，跳过：" + asset_id)
			continue
		var scene_path := _save_prop_scene(tex, asset_id)
		if scene_path.is_empty():
			warnings.append("件场景保存失败：" + asset_id)
			continue
		var loaded: PackedScene = load(scene_path)
		if loaded == null:
			warnings.append("件场景回载失败：" + asset_id)
			continue
		var tile_id: int = scenes.create_scene_tile(loaded) # 4.6 API：create 返回 tile id（get_scene_tile_id 收的是索引，勿混用）
		_scene_tile_cache[asset_id] = tile_id
	return ts

## 件子场景：根=底边中心锚、Sprite offset=-h/2、StaticBody2D 底边脚印（形态A 配方）
static func _save_prop_scene(tex: Texture2D, asset_id: String) -> String:
	var root := Node2D.new()
	root.name = "Prop"
	var sprite := Sprite2D.new()
	sprite.name = "Sprite" # 显式命名防 pack 自动改名（@Name@N 现象）
	sprite.texture = tex
	sprite.offset = Vector2(0, -tex.get_height() / 2.0) # 根在底边中心
	root.add_child(sprite)
	var body := StaticBody2D.new()
	body.name = "Body"
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tex.get_width(), mini(tex.get_height(), 16.0)) # 底边脚印：宽×min(件高,格高)
	shape.shape = rect
	shape.position = Vector2(0, -rect.size.y / 2.0) # 脚印贴根
	body.add_child(shape)
	root.add_child(body)
	sprite.owner = root
	body.owner = root
	shape.owner = root
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR)) # 防御：单独调用时目录可能未建
	var safe := asset_id.replace("/", "_").replace(".", "_")
	var path := EXPORT_DIR + "/prop_" + safe + ".tscn"
	if ResourceSaver.save(packed, path) != OK:
		root.free()
		return ""
	root.free()
	return path

## 占位 atlas 纹理（导出以数据正确性为先；真实素材纹理由运行时素材包对位）
static func _placeholder_atlas_texture() -> Texture2D:
	var img := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.55, 0.6))
	return ImageTexture.create_from_image(img)
