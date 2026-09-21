class_name TagStore
extends RefCounted
## 标签存储（design.md §6.1 标签系统）：素材自定义标签
## 纯逻辑：解析输入串 / 增删标签 / user://tags.json 持久化

const TAGS_PATH := "user://tags.json"

## 输入串解析：逗号/空格/中文逗号分隔，去空去重，最多 8 个
static func parse_input(text: String) -> Array:
	var result := []
	for raw in text.replace("，", ",").replace(",", " ").split(" ", false):
		var tag := str(raw).strip_edges()
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	if result.size() > 8:
		result.resize(8)
	return result

## 读取全部标签表 {asset_id: [tag...]}
static func load_all() -> Dictionary:
	if not FileAccess.file_exists(TAGS_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TAGS_PATH))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

## 整表保存
static func save_all(tags: Dictionary) -> bool:
	var f := FileAccess.open(TAGS_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(tags, "\t"))
	f = null
	return true

## 给素材设置标签集（覆盖）；空列表则移除条目
static func set_tags(tags: Dictionary, asset_id: String, new_tags: Array) -> Dictionary:
	if new_tags.is_empty():
		tags.erase(asset_id)
	else:
		tags[asset_id] = new_tags.duplicate()
	return tags

## 反向索引：{tag: [asset_id...]}（面板虚拟分类用，按素材库顺序过滤由调用方做）
static func reverse_index(tags: Dictionary) -> Dictionary:
	var result := {}
	for asset_id in tags.keys():
		for tag in (tags[asset_id] as Array):
			var key := str(tag)
			if not result.has(key):
				result[key] = []
			(result[key] as Array).append(str(asset_id))
	return result
