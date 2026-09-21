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
	issues.append_array(check_enclosed_regions(doc, lib))
	issues.append_array(check_collision_overlaps(doc, lib))
	issues.append_array(check_missing_assets(doc, lib))
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

## 悬空素材（design.md §10 资源完整性）：素材库中查无此 id 的方块/物件——
## 素材包被移走/改名/清单漏登记都会产生，导出前必须暴露
static func check_missing_assets(doc: MapDocument, lib: AssetLibrary) -> Array:
	var issues := []
	for layer in doc.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if str((layer as Dictionary)["type"]) != "tile":
			continue
		for coords in doc.get_tile_coords(layer_id):
			var entry := doc.get_tile(layer_id, coords as Vector2i)
			var asset := lib.get_asset(str(entry.get("asset_id", "")))
			if asset.is_empty():
				issues.append({
					"type": "missing_asset",
					"message": "方块素材缺失（层 %s 格 %s）：%s" % [layer_id, str(coords), str(entry.get("asset_id", ""))],
				})
	for obj in doc.get_objects():
		var o := obj as Dictionary
		var asset := lib.get_asset(str(o["asset_id"]))
		if asset.is_empty():
			issues.append({
				"type": "missing_asset",
				"message": "物件素材缺失（id=%d）：%s" % [int(o["id"]), str(o["asset_id"])],
			})
	return issues

## 孤立区域（design.md §8）：被内容完全围住、与地图外缘不连通的空格群
## 语义：空格 = 所有 tile 层均无方块的格；从包围盒边界的空格洪泛可达者为开放区，
## 其余成团的空格即孤立区域（数量/格数），返回 {count, cells:[[x,y]...]}（上限 512 格记录）
static func check_enclosed_regions(doc: MapDocument, lib: AssetLibrary) -> Array:
	# 收集包围盒与占用集
	var occupied := {} # "x,y" -> true
	var min_c := Vector2i(99999, 99999)
	var max_c := Vector2i(-99999, -99999)
	for layer in doc.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if str((layer as Dictionary)["type"]) != "tile":
			continue
		for coords in doc.get_tile_coords(layer_id):
			var c := coords as Vector2i
			occupied["%d,%d" % [c.x, c.y]] = true
			min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
			max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	if max_c.x < min_c.x:
		return [] # 空图
	# 从边界空格洪泛标记开放区
	var open_set := {}
	var queue: Array = []
	for x in range(min_c.x - 1, max_c.x + 2): # 包围盒外一圈必为空
		for y in [min_c.y - 1, max_c.y + 1]:
			queue.append(Vector2i(x, y))
	for y in range(min_c.y - 1, max_c.y + 2):
		for x in [min_c.x - 1, max_c.x + 1]:
			queue.append(Vector2i(x, y))
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var key := "%d,%d" % [c.x, c.y]
		if open_set.has(key) or occupied.has(key):
			continue
		open_set[key] = true
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dir
			if n.x >= min_c.x - 1 and n.x <= max_c.x + 1 and n.y >= min_c.y - 1 and n.y <= max_c.y + 1:
				queue.append(n)
	# 盒内空格且非开放 → 孤立；成团计数
	var visited := {}
	var regions := []
	for x in range(min_c.x, max_c.x + 1):
		for y in range(min_c.y, max_c.y + 1):
			var key := "%d,%d" % [x, y]
			if occupied.has(key) or open_set.has(key) or visited.has(key):
				continue
			var cells := []
			var q2: Array = [Vector2i(x, y)]
			visited[key] = true
			while not q2.is_empty():
				var c: Vector2i = q2.pop_front()
				cells.append([c.x, c.y])
				if cells.size() > 512:
					break
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + dir
					var nk := "%d,%d" % [n.x, n.y]
					if not occupied.has(nk) and not open_set.has(nk) and not visited.has(nk) 							and n.x >= min_c.x and n.x <= max_c.x and n.y >= min_c.y and n.y <= max_c.y:
						visited[nk] = true
						q2.append(n)
			regions.append({"type": "enclosed_region", "count": cells.size(), "cells": cells})
	return regions

## 碰撞重叠（design.md §8）：物件脚印（cells 占格）相互重叠的检测
## 返回 [{type, message}]；同格叠放两个以上物件即报
static func check_collision_overlaps(doc: MapDocument, lib: AssetLibrary) -> Array:
	var foot := {} # "x,y" -> Array[object_id]
	for obj in doc.get_objects():
		var o := obj as Dictionary
		var asset := lib.get_asset(str(o["asset_id"]))
		var cells: Vector2i = Vector2i.ONE if asset.is_empty() else asset["cells"]
		var tl: Vector2i = o["cell"]
		for dy in cells.y:
			for dx in cells.x:
				var key := "%d,%d" % [tl.x + dx, tl.y + dy]
				if not foot.has(key):
					foot[key] = []
				(foot[key] as Array).append(int(o["id"]))
	var issues := []
	for key in foot.keys():
		if (foot[key] as Array).size() > 1:
			issues.append({
				"type": "collision_overlap",
				"message": "格 %s 有 %d 件物件脚印重叠（id：%s）" % [str(key), (foot[key] as Array).size(), str(foot[key])],
			})
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
