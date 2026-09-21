class_name MapDocument
extends RefCounted
## 地图文档模型（design.md §9）
## 规则方块层：稀疏网格字典（Vector2i -> {asset_id}），适合大面积铺设与批量替换
## 自由物件层：对象字典（自增 id -> 物件），每个物件独立可编辑（§9.2 全字段）
## 本类只管数据与序列化，不碰渲染；锁定层的写保护在编辑入口统一拦截
## （force=true 供命令栈撤销/重做恢复现场时绕过锁定）

signal tile_changed(layer_id: String, coords: Vector2i)
signal object_added(object_id: int)
signal object_removed(object_id: int)
signal object_changed(object_id: int)
signal layer_changed(layer_id: String, key: String)

const FORMAT_VERSION: int = 1
const ANCHOR_BOTTOM_CENTER: String = "bottom_center" # 独立物件默认锚点
const ANCHOR_TOP_LEFT: String = "top_left" # 规则方块默认锚点

## 默认图层栈，渲染自底向上（design.md §4 五层：底部两块 tile 层 + 顶部三块 object 层）
const DEFAULT_LAYERS: Array = [
	{"id": "terrain", "name": "基础地形层", "type": "tile"},
	{"id": "ground", "name": "道路与地面层", "type": "tile"},
	{"id": "deco", "name": "装饰层", "type": "object"},
	{"id": "building", "name": "建筑与大型道具层", "type": "object"},
	{"id": "foreground", "name": "前景遮挡层", "type": "object"},
]

## 物件可编辑字段白名单（id 由文档分配，不接受外部修改）
const OBJECT_FIELDS: Array = [
	"asset_id", "resource_path", "cell", "anchor", "layer", "scale",
	"mirror_h", "mirror_v", "collision", "interaction_offset", "prefab",
]

## 图层可编辑属性白名单（id 与 type 建档后不可改，防数据模型错乱）
const LAYER_FIELDS: Array = ["name", "visible", "locked", "opacity"]

var grid_px := 16 # 正式地图网格

var _layers: Array[Dictionary] = []
var _tiles := {} # layer_id(String) -> Dictionary(Vector2i -> {"asset_id": String})
var _objects := {} # 自增 id(int) -> 物件 Dictionary
var _next_object_id := 1

func _init() -> void:
	for layer in DEFAULT_LAYERS:
		_layers.append(_normalize_layer(layer as Dictionary))

#region 图层

func layer_count() -> int:
	return _layers.size()

func get_layers() -> Array:
	return _layers.duplicate()

func get_layer(layer_id: String) -> Dictionary:
	var idx := _layer_index(layer_id)
	if idx < 0:
		return {}
	return _layers[idx]

func set_layer_property(layer_id: String, key: String, value: Variant) -> bool:
	if not LAYER_FIELDS.has(key):
		push_warning("[TileMason] set_layer_property：字段不可改 %s" % key)
		return false
	var idx := _layer_index(layer_id)
	if idx < 0:
		push_warning("[TileMason] set_layer_property：图层不存在 %s" % layer_id)
		return false
	_layers[idx][key] = value
	layer_changed.emit(layer_id, key)
	return true

func is_layer_locked(layer_id: String) -> bool:
	var layer := get_layer(layer_id)
	return not layer.is_empty() and bool(layer.get("locked", false))

func _layer_index(layer_id: String) -> int:
	for i in _layers.size():
		if str(_layers[i]["id"]) == layer_id:
			return i
	return -1

static func _normalize_layer(raw: Dictionary) -> Dictionary:
	return {
		"id": str(raw.get("id", "")),
		"name": str(raw.get("name", raw.get("id", ""))),
		"type": str(raw.get("type", "object")),
		"visible": bool(raw.get("visible", true)),
		"locked": bool(raw.get("locked", false)),
		"opacity": float(raw.get("opacity", 1.0)),
	}

#endregion

#region 规则方块

func set_tile(layer_id: String, coords: Vector2i, asset_id: String, force := false) -> Variant:
	## 放置/覆盖方块；返回被覆盖的旧条目（Dictionary，空{}=原本无方块）
	## 层不存在或被锁定时返回 null 且不改数据
	var idx := _layer_index(layer_id)
	if idx < 0 or _layers[idx]["type"] != "tile":
		push_warning("[TileMason] set_tile：图层不存在或非 tile 层 %s" % layer_id)
		return null
	if not force and bool(_layers[idx].get("locked", false)):
		push_warning("[TileMason] set_tile：图层已锁定 %s" % layer_id)
		return null
	var store := _ensure_tile_store(layer_id)
	var old: Dictionary = store.get(coords, {})
	store[coords] = {"asset_id": asset_id}
	tile_changed.emit(layer_id, coords)
	return old

func erase_tile(layer_id: String, coords: Vector2i, force := false) -> Variant:
	## 擦除方块；返回被清掉的旧条目（空{}=原本无方块）；拒绝规则同 set_tile
	var idx := _layer_index(layer_id)
	if idx < 0 or _layers[idx]["type"] != "tile":
		push_warning("[TileMason] erase_tile：图层不存在或非 tile 层 %s" % layer_id)
		return null
	if not force and bool(_layers[idx].get("locked", false)):
		push_warning("[TileMason] erase_tile：图层已锁定 %s" % layer_id)
		return null
	if not _tiles.has(layer_id):
		return {}
	var store: Dictionary = _tiles[layer_id]
	var old: Dictionary = store.get(coords, {})
	store.erase(coords)
	tile_changed.emit(layer_id, coords)
	return old

## 矩形填充（design.md §2.2）：立即应用并返回变更记录 [{cell, old}]，供命令栈合成整段撤销
## skip_existing=true 时已有内容的格跳过（「遇到已有内容停止」模式）；层无效/锁定返回空数组
func fill_rect(layer_id: String, rect: Rect2i, asset_id: String, skip_existing := false) -> Array:
	var idx := _layer_index(layer_id)
	if idx < 0 or _layers[idx]["type"] != "tile" or bool(_layers[idx].get("locked", false)):
		push_warning("[TileMason] fill_rect：图层无效或已锁定 %s" % layer_id)
		return []
	var entries := []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if skip_existing and not get_tile(layer_id, cell).is_empty():
				continue
			var prev: Variant = set_tile(layer_id, cell, asset_id)
			if prev != null:
				entries.append({"cell": cell, "old": prev})
	return entries

## 两点间的格序列（Bresenham 直线，design.md §2.2 直线工具），含起终点
static func line_cells(from: Vector2i, to: Vector2i) -> Array:
	var cells := []
	var x := from.x
	var y := from.y
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx + dy
	while true:
		cells.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return cells

## 油漆桶填充（design.md §2.2）：从 start 出发的 4 邻接连通区域内、
## 与 start 格当前内容相同（同 asset_id 或同为空）的所有格整体替换；
## 立即应用并返回变更记录 [{cell, old}]；层无效/锁定返回空，4096 格安全上限
func flood_fill(layer_id: String, start: Vector2i, asset_id: String) -> Array:
	var idx := _layer_index(layer_id)
	if idx < 0 or _layers[idx]["type"] != "tile" or bool(_layers[idx].get("locked", false)):
		push_warning("[TileMason] flood_fill：图层无效或已锁定 %s" % layer_id)
		return []
	var source := get_tile(layer_id, start)
	var source_key := str(source.get("asset_id", "")) # 空=填充连通空区
	var store := _ensure_tile_store(layer_id)
	var visited := {}
	var queue: Array = [start]
	visited[start] = true
	var region: Array = []
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var entry: Dictionary = store.get(c, {})
		var is_empty := entry.is_empty()
		if (source_key.is_empty() and not is_empty) or (not source_key.is_empty() and (is_empty or str(entry["asset_id"]) != source_key)):
			continue # 内容不同：边界
		region.append(c)
		if region.size() >= 4096:
			break
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dir
			if not visited.has(n):
				visited[n] = true
				queue.append(n)
	var entries := []
	for c in region:
		var prev: Variant = set_tile(layer_id, c, asset_id)
		if prev != null:
			entries.append({"cell": c, "old": prev})
	return entries

func get_tile(layer_id: String, coords: Vector2i) -> Dictionary:
	if not _tiles.has(layer_id):
		return {}
	return (_tiles[layer_id] as Dictionary).get(coords, {})

## 某层全部有方块的格坐标（视图重建与导出遍历用）
func get_tile_coords(layer_id: String) -> Array:
	if not _tiles.has(layer_id):
		return []
	return (_tiles[layer_id] as Dictionary).keys()

## 文档是否已有内容（任意 tile 层有方块或存在任何物件）
func has_content() -> bool:
	for layer_id in _tiles.keys():
		if not (_tiles[layer_id] as Dictionary).is_empty():
			return true
	return not _objects.is_empty()

func _ensure_tile_store(layer_id: String) -> Dictionary:
	if not _tiles.has(layer_id):
		_tiles[layer_id] = {}
	return _tiles[layer_id]

#endregion

#region 自由物件

func add_object(props: Dictionary, force := false) -> int:
	## 新增物件（缺省字段自动补全）；成功返回新 id，图层无效/锁定或 asset_id 为空返回 -1
	var layer_id := str(props.get("layer", ""))
	var layer := get_layer(layer_id)
	if layer.is_empty() or layer["type"] != "object":
		push_warning("[TileMason] add_object：图层不存在或非 object 层 %s" % layer_id)
		return -1
	if not force and is_layer_locked(layer_id):
		push_warning("[TileMason] add_object：图层已锁定 %s" % layer_id)
		return -1
	if str(props.get("asset_id", "")).is_empty():
		push_warning("[TileMason] add_object：asset_id 不能为空")
		return -1
	var obj := _normalize_object(props, _next_object_id)
	_objects[_next_object_id] = obj
	_next_object_id += 1
	object_added.emit(int(obj["id"]))
	return int(obj["id"])

func update_object(object_id: int, patch: Dictionary, force := false) -> Variant:
	## 按白名单打补丁；返回被覆盖的旧值字典；物件不存在或图层锁定返回 null
	if not _objects.has(object_id):
		push_warning("[TileMason] update_object：物件不存在 %d" % object_id)
		return null
	var obj: Dictionary = _objects[object_id]
	if not force and is_layer_locked(str(obj["layer"])):
		push_warning("[TileMason] update_object：图层已锁定 %s" % str(obj["layer"]))
		return null
	if patch.has("layer"):
		var target := get_layer(str(patch["layer"]))
		if target.is_empty() or target["type"] != "object":
			push_warning("[TileMason] update_object：目标图层无效 %s" % str(patch["layer"]))
			return null
	# 用「原物件合并补丁再归一化」的方式改写，未知字段自动丢弃，类型统一矫正
	# 注意（dev-pitfalls 8）：merged() 默认不覆盖已有键，必须显式传 true
	var normalized := _normalize_object(obj.merged(patch, true), object_id)
	var old := {}
	for key in OBJECT_FIELDS:
		if patch.has(key):
			old[key] = obj[key]
			obj[key] = normalized[key]
	object_changed.emit(object_id)
	return old

## 插入完整物件（含既有 id，供序列化重建与命令栈重做复用）；id 计数器前移保持唯一
func insert_object(obj: Dictionary, force := false) -> int:
	var object_id := int(obj.get("id", 0))
	if object_id <= 0:
		return add_object(obj, force)
	var normalized := _normalize_object(obj, object_id)
	var layer := get_layer(str(normalized["layer"]))
	if str(normalized["asset_id"]).is_empty() or layer.is_empty() or layer["type"] != "object":
		push_warning("[TileMason] insert_object：物件数据无效（layer=%s）" % str(normalized["layer"]))
		return -1
	if not force and bool(layer.get("locked", false)):
		push_warning("[TileMason] insert_object：图层已锁定 %s" % str(normalized["layer"]))
		return -1
	_objects[object_id] = normalized
	_next_object_id = maxi(_next_object_id, object_id + 1)
	object_added.emit(object_id)
	return object_id

func remove_object(object_id: int, force := false) -> Variant:
	## 删除物件；返回被删物件；不存在或图层锁定返回 null
	if not _objects.has(object_id):
		return null
	var obj: Dictionary = _objects[object_id]
	if not force and is_layer_locked(str(obj["layer"])):
		push_warning("[TileMason] remove_object：图层已锁定 %s" % str(obj["layer"]))
		return null
	_objects.erase(object_id)
	object_removed.emit(object_id)
	return obj

func get_object(object_id: int) -> Dictionary:
	return _objects.get(object_id, {})

func get_objects() -> Array:
	return _objects.values()

func get_objects_on_layer(layer_id: String) -> Array:
	var result := []
	for obj in _objects.values():
		if str((obj as Dictionary)["layer"]) == layer_id:
			result.append(obj)
	return result

static func _normalize_object(raw: Dictionary, object_id: int) -> Dictionary:
	return {
		"id": object_id,
		"asset_id": str(raw.get("asset_id", "")),
		"resource_path": str(raw.get("resource_path", "")),
		"cell": _to_cell(raw.get("cell", Vector2i.ZERO)),
		"anchor": str(raw.get("anchor", ANCHOR_BOTTOM_CENTER)),
		"layer": str(raw.get("layer", "")),
		"scale": int(raw.get("scale", 1)),
		"mirror_h": bool(raw.get("mirror_h", false)),
		"mirror_v": bool(raw.get("mirror_v", false)),
		"collision": (raw.get("collision", {}) as Dictionary).duplicate(true),
		"interaction_offset": _to_cell(raw.get("interaction_offset", Vector2i.ZERO)),
		"prefab": str(raw.get("prefab", "")),
	}

## 坐标矫正：接受 Vector2i 或 [x, y] 数组（JSON 往返后是 float 数组）
static func _to_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO

#endregion

#region 序列化

func to_dict() -> Dictionary:
	## 序列化为 JSON 安全结构：Vector2i 转 [x,y]，网格键转 "x,y"
	## （JSON.parse_string 回来数字全是 float，from_dict 负责 int 矫正）
	var layers := []
	for layer in _layers:
		layers.append((layer as Dictionary).duplicate())
	var tiles := {}
	for layer_id in _tiles.keys():
		var cells := {}
		for coords in (_tiles[layer_id] as Dictionary).keys():
			var c := coords as Vector2i
			cells["%d,%d" % [c.x, c.y]] = ((_tiles[layer_id] as Dictionary)[coords] as Dictionary).duplicate()
		tiles[layer_id] = cells
	var objects := []
	for obj in _objects.values():
		var o := (obj as Dictionary).duplicate()
		o["cell"] = [o["cell"].x, o["cell"].y]
		o["interaction_offset"] = [o["interaction_offset"].x, o["interaction_offset"].y]
		objects.append(o)
	return {
		"version": FORMAT_VERSION,
		"grid_px": grid_px,
		"layers": layers,
		"tiles": tiles,
		"objects": objects,
	}

static func from_dict(data: Dictionary) -> MapDocument:
	## 从序列化数据重建；损坏字段跳过并告警，不抛错
	var doc := MapDocument.new()
	if data.has("grid_px"):
		doc.grid_px = int(data["grid_px"])
	if data.has("layers") and (data["layers"] as Array).size() > 0:
		doc._layers.clear()
		for layer in data["layers"]:
			doc._layers.append(_normalize_layer(layer as Dictionary))
	var tiles := data.get("tiles", {}) as Dictionary
	for layer_id in tiles.keys():
		var store := doc._ensure_tile_store(str(layer_id))
		for cell_key in (tiles[layer_id] as Dictionary).keys():
			var parts := str(cell_key).split(",")
			if parts.size() != 2:
				continue
			var entry: Variant = (tiles[layer_id] as Dictionary)[cell_key]
			if entry is Dictionary:
				store[Vector2i(int(parts[0]), int(parts[1]))] = {
					"asset_id": str((entry as Dictionary).get("asset_id", "")),
				}
	for raw_obj in data.get("objects", []):
		var obj := _normalize_object(raw_obj as Dictionary, doc._next_object_id)
		var layer := doc.get_layer(str(obj["layer"]))
		if str(obj["asset_id"]).is_empty() or layer.is_empty() or layer["type"] != "object":
			push_warning("[TileMason] from_dict：跳过损坏物件条目")
			continue
		doc._objects[doc._next_object_id] = obj
		doc._next_object_id += 1
	return doc

func save_to_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[TileMason] 保存失败：%s（%s）" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true

static func load_from_file(path: String) -> MapDocument:
	if not FileAccess.file_exists(path):
		push_warning("[TileMason] 地图文件不存在：%s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return from_dict(parsed as Dictionary)
	push_warning("[TileMason] 地图文件解析失败：%s" % path)
	return null

#endregion
