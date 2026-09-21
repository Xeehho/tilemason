class_name AutoConnect
extends RefCounted
## 自动连接核心（design.md §2.2）：按 4 邻接掩码自动选择素材变体
## 掩码位序：N=1、E=2、S=4、W=8（0..15）；素材变体由其 connections 声明匹配
## 纯逻辑无副作用：refresh 只返回变更清单，应用与撤销由调用方并入命令栈

## 四方向与位序严格一致（N,E,S,W → 1,2,4,8）
const DIR_VECTORS: Array = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES: Array = ["up", "right", "down", "left"] # design/清单约定用 up/right/down/left

## connections 方向名列表 → 掩码（未知方向忽略）
static func dirs_to_mask(connections: Array) -> int:
	var mask := 0
	for c in connections:
		var idx := DIR_NAMES.find(str(c))
		if idx >= 0:
			mask |= 1 << idx
	return mask

## 掩码 → 方向名列表（调试与清单生成用）
static func mask_to_dirs(mask: int) -> Array:
	var result := []
	for i in 4:
		if mask & (1 << i):
			result.append(DIR_NAMES[i])
	return result

## 某格的邻接掩码：4 邻存在**同分类**方块的方向置位（道路连道路、墙连墙）
static func neighbor_mask(doc: MapDocument, lib: AssetLibrary, layer_id: String, cell: Vector2i, category: String) -> int:
	var mask := 0
	for i in 4:
		var entry := doc.get_tile(layer_id, cell + (DIR_VECTORS[i] as Vector2i))
		if entry.is_empty():
			continue
		var asset := lib.get_asset(str(entry.get("asset_id", "")))
		if not asset.is_empty() and str(asset["category"]) == category:
			mask |= 1 << i
	return mask

## 依掩码选变体：精确匹配（素材连接方向==所需）优先；否则取「包含所需方向的超集」中
## 多余方向最少者；无匹配返回空串（调用方保持原素材）
static func pick_variant(lib: AssetLibrary, category: String, mask: int) -> String:
	if mask == 0:
		return ""
	var best := ""
	var best_extra := 99
	for asset in lib.get_assets_by_category(category):
		var a := asset as Dictionary
		var have := dirs_to_mask(a.get("connections", []))
		var missing := mask & ~have
		if missing != 0:
			continue # 覆盖不了所需方向
		var extra := have & ~mask
		var extra_count := extra
		var count := 0
		while extra_count:
			count += extra_count & 1
			extra_count >>= 1
		if count < best_extra:
			best_extra = count
			best = str(a["id"])
	return best

## 落格/擦除后刷新：重算 cell 与其同类邻居的变体
## 返回变更清单 [{cell, old_asset_id, new_asset_id}]——已直接应用（set_tile force），
## 调用方把每条包进当前命令的 undo（old 恢复）/redo（new 重放）
static func refresh_around(doc: MapDocument, lib: AssetLibrary, layer_id: String, cell: Vector2i) -> Array:
	if doc.is_layer_locked(layer_id):
		return [] # 锁定层不自动改写（含邻居变体）
	var changes := []
	var targets := [cell]
	for i in 4:
		var n := cell + (DIR_VECTORS[i] as Vector2i)
		if not doc.get_tile(layer_id, n).is_empty():
			targets.append(n)
	for target in targets:
		var t := target as Vector2i
		var entry := doc.get_tile(layer_id, t)
		if entry.is_empty():
			continue
		var asset := lib.get_asset(str(entry.get("asset_id", "")))
		if asset.is_empty():
			continue
		var category := str(asset["category"])
		var mask := neighbor_mask(doc, lib, layer_id, t, category)
		var variant := pick_variant(lib, category, mask)
		if variant.is_empty() or variant == str(entry["asset_id"]):
			continue
		var old_id := str(entry["asset_id"])
		doc.set_tile(layer_id, t, variant, true)
		changes.append({"cell": t, "old_asset_id": old_id, "new_asset_id": variant})
	return changes
