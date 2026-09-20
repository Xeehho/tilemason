class_name Selection
extends RefCounted
## 选区模型（design.md §2.1/§7）：物件 id 集 + 各层格集，框选/移动/复制的基底
## 纯数据不含渲染；选中高亮由视图监听 changed 后自行处理

signal changed

var _object_ids: Array = [] # int，保持选择顺序
var _cells := {} # layer_id -> Dictionary(Vector2i -> true)

func clear() -> void:
	if is_empty():
		return
	_object_ids.clear()
	_cells.clear()
	changed.emit()

func is_empty() -> bool:
	return _object_ids.is_empty() and _cells.is_empty()

func object_ids() -> Array:
	return _object_ids.duplicate()

func object_count() -> int:
	return _object_ids.size()

func cell_count() -> int:
	var n := 0
	for key in _cells.keys():
		n += (_cells[key] as Dictionary).size()
	return n

func has_object(object_id: int) -> bool:
	return _object_ids.has(object_id)

func add_object(object_id: int) -> void:
	if _object_ids.has(object_id):
		return
	_object_ids.append(object_id)
	changed.emit()

func remove_object(object_id: int) -> void:
	_object_ids.erase(object_id)
	changed.emit()

## 整批设置（框选结果），同时清空格选区
func set_objects(ids: Array) -> void:
	_object_ids.clear()
	for id in ids:
		if not _object_ids.has(int(id)):
			_object_ids.append(int(id))
	_cells.clear()
	changed.emit()

func has_cell(layer_id: String, cell: Vector2i) -> bool:
	return _cells.has(layer_id) and (_cells[layer_id] as Dictionary).has(cell)

## 各层选中格 {layer_id: [Vector2i]}（视图高亮与删除遍历用）
func cells_by_layer() -> Dictionary:
	var result := {}
	for key in _cells.keys():
		result[key] = (_cells[key] as Dictionary).keys()
	return result

func add_cell(layer_id: String, cell: Vector2i) -> void:
	if not _cells.has(layer_id):
		_cells[layer_id] = {}
	(_cells[layer_id] as Dictionary)[cell] = true
	changed.emit()
