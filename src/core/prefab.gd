class_name Prefab
extends RefCounted
## 预制件（design.md §7）：把选中内容存为可重复放置的组合
## 快照相对化（以内容左上角为原点），JSON 存 user://prefabs/<名>.json
## 纯逻辑：构建/读取/序列化；放置命令由 main 复用粘贴模式组装

const PREFAB_DIR := "user://prefabs"

## 从文档选区构建预制件快照（tiles/objects 格坐标相对左上角）
static func build_snapshot(doc: MapDocument, object_ids: Array, cells_by_layer: Dictionary) -> Dictionary:
	var base := Vector2i(99999, 99999)
	for id in object_ids:
		var obj := doc.get_object(int(id))
		if not obj.is_empty():
			var c: Vector2i = obj["cell"]
			base = Vector2i(mini(base.x, c.x), mini(base.y, c.y))
	for layer_id in cells_by_layer.keys():
		for c in (cells_by_layer[layer_id] as Array):
			var cc: Vector2i = c
			base = Vector2i(mini(base.x, cc.x), mini(base.y, cc.y))
	if base == Vector2i(99999, 99999):
		return {}
	var tiles := []
	for layer_id in cells_by_layer.keys():
		for c in (cells_by_layer[layer_id] as Array):
			var entry := doc.get_tile(str(layer_id), c as Vector2i)
			if not entry.is_empty():
				tiles.append({
					"layer": str(layer_id),
					"cell": [ (c as Vector2i).x - base.x, (c as Vector2i).y - base.y ],
					"asset_id": str(entry["asset_id"]),
				})
	var objects := []
	for id in object_ids:
		var obj := doc.get_object(int(id))
		if obj.is_empty():
			continue
		var o := obj.duplicate(true)
		o.erase("id")
		var oc: Vector2i = o["cell"]
		o["cell"] = [oc.x - base.x, oc.y - base.y]
		objects.append(o)
	return {"version": 1, "base_offset": [base.x, base.y], "tiles": tiles, "objects": objects}

## 保存到 user://prefabs/<name>.json；成功返回路径
static func save_prefab(name: String, snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREFAB_DIR))
	var path := PREFAB_DIR + "/" + name + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(snapshot, "\t"))
	f = null
	return path

## 读取预制件；失败返回空字典
static func load_prefab(name: String) -> Dictionary:
	var path := PREFAB_DIR + "/" + name + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

## 列出已存预制件名
static func list_names() -> Array:
	var dir := DirAccess.open(PREFAB_DIR)
	if dir == null:
		return []
	var names := []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if str(entry).ends_with(".json"):
			names.append(str(entry).get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	return names
