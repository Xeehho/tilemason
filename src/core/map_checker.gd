class_name MapChecker
extends RefCounted
## 地图检查（design.md §8 最小版，验收 9）：道路连通性 + 建筑堵路
## 纯逻辑无 UI，供导出前检查与 F9 手动触发；连通性语义：所有道路格
## 构成单个 4 邻接连通块；堵路语义：建筑（building 类）脚印覆盖道路格

## 返回问题列表（空=通过）；每项 {type, message}，type ∈ road_disconnected / building_blocks_road
static func check_all(doc: MapDocument, lib: AssetLibrary) -> Array:
	var issues: Array = []
	issues.append_array(check_road_connectivity(doc, lib))
	issues.append_array(check_blocking(doc, lib))
	return issues

## 道路连通性：全部道路格应为一个 4 邻接连通块
static func check_road_connectivity(doc: MapDocument, lib: AssetLibrary) -> Array:
	var road_cells := {} # "x,y" -> Vector2i
	for layer in doc.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if str((layer as Dictionary)["type"]) != "tile":
			continue
		for coords in doc.get_tile_coords(layer_id):
			var entry := doc.get_tile(layer_id, coords as Vector2i)
			var asset := lib.get_asset(str(entry.get("asset_id", "")))
			if not asset.is_empty() and str(asset["category"]) == "road":
				var c := coords as Vector2i
				road_cells["%d,%d" % [c.x, c.y]] = c
	if road_cells.is_empty():
		return []
	var components := _count_components(road_cells)
	if components > 1:
		return [{
			"type": "road_disconnected",
			"message": "道路不连通：分为 %d 段（共 %d 格），请检查断点" % [components, road_cells.size()],
		}]
	return []

## 建筑堵路：building 类物件脚印覆盖到道路格
static func check_blocking(doc: MapDocument, lib: AssetLibrary) -> Array:
	var road_cells := {}
	for layer in doc.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if str((layer as Dictionary)["type"]) != "tile":
			continue
		for coords in doc.get_tile_coords(layer_id):
			var entry := doc.get_tile(layer_id, coords as Vector2i)
			var asset := lib.get_asset(str(entry.get("asset_id", "")))
			if not asset.is_empty() and str(asset["category"]) == "road":
				var c := coords as Vector2i
				road_cells["%d,%d" % [c.x, c.y]] = c
	var issues: Array = []
	for obj in doc.get_objects():
		var o := obj as Dictionary
		var asset := lib.get_asset(str(o["asset_id"]))
		if asset.is_empty() or str(asset["category"]) != "building":
			continue
		var tl: Vector2i = o["cell"]
		var cells: Vector2i = asset["cells"]
		var blocked := false
		for dy in cells.y:
			if blocked:
				break
			for dx in cells.x:
				var key := "%d,%d" % [tl.x + dx, tl.y + dy]
				if road_cells.has(key):
					issues.append({
						"type": "building_blocks_road",
						"message": "建筑（%s，id=%d）在 %s 堵住道路" % [str(asset["name"]), int(o["id"]), key],
					})
					blocked = true # 一个建筑只报一次
					break
	return issues

## 4 邻接连通块计数
static func _count_components(cells: Dictionary) -> int:
	var visited := {}
	var count := 0
	for key in cells.keys():
		if visited.has(key):
			continue
		count += 1
		var queue: Array = [cells[key]]
		visited[key] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_front()
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + dir
				var nk := "%d,%d" % [n.x, n.y]
				if cells.has(nk) and not visited.has(nk):
					visited[nk] = true
					queue.append(cells[nk])
	return count
