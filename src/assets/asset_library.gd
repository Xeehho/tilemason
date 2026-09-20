class_name AssetLibrary
extends RefCounted
## 素材库数据层（design.md §6.1 + assets/packs/README.md 包结构约定）
## 扫描素材包根目录 → 解析 pack.json 清单 → 分类索引 + 图像/纹理缓存
## PNG 一律 Image.load_from_file + 内存缓存（dev-pitfalls 20），禁用 load()
## 面板 UI 与缩略图展示在 demo 素材里程碑接入（无素材时 UI 无法实测）

## 分类全集（design.md §6.1，UI 面板按此排序）
const ALL_CATEGORIES: Array = [
	"ground", "road", "wall", "building", "tree", "stall", "indoor", "furniture", "deco",
]
## 规则方块分类（锚点默认左上角，design.md §2.2/§3.3）
const TILE_CATEGORIES: Array = ["ground", "road", "wall"]
const ANCHOR_TOP_LEFT: String = "top_left"
const ANCHOR_BOTTOM_CENTER: String = "bottom_center"

var grid_px := 16 ## 正式地图网格，用于 cells 缺省推导

var packs: Array[Dictionary] = [] ## 已加载素材包 [{id, name, dir}]

var _assets := {} # asset_id("包id/相对路径") -> 素材 Dictionary
var _images := {} # 绝对路径 -> Image
var _textures := {} # asset_id -> ImageTexture（缩略图用）

## 默认扫描根：开发态 res 包目录 + 用户目录；导出 exe 相对路径随导出里程碑扩展
static func default_roots() -> Array:
	return ["res://assets/packs", "user://packs"]

## 扫描所有根目录下的素材包，返回素材总数；目录缺失只告警不算失败
func scan(roots: Array) -> int:
	for root in roots:
		var dir := DirAccess.open(str(root))
		if dir == null:
			continue # 根目录不存在（如全新环境无包），正常情况
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if dir.current_is_dir() and not str(entry).begins_with("."):
				_load_pack(str(root).path_join(str(entry)), str(entry))
			entry = dir.get_next()
		dir.list_dir_end()
	return _assets.size()

## 素材包数 / 素材数
func pack_count() -> int:
	return packs.size()

func asset_count() -> int:
	return _assets.size()

func get_asset(asset_id: String) -> Dictionary:
	return _assets.get(asset_id, {})

func get_assets() -> Array:
	return _assets.values()

## 分类下素材列表（保持清单顺序）
func get_assets_by_category(category: String) -> Array:
	var result := []
	for asset_id in _assets.keys():
		if str((_assets[asset_id] as Dictionary)["category"]) == category:
			result.append(_assets[asset_id])
	return result

## 当前实际存在素材的分类（按 ALL_CATEGORIES 顺序，未知分类排尾部）
func get_categories() -> Array:
	var present := {}
	for asset in _assets.values():
		present[str((asset as Dictionary)["category"])] = true
	var result := []
	for category in ALL_CATEGORIES:
		if present.has(category):
			result.append(category)
	for category in present.keys():
		if not ALL_CATEGORIES.has(category):
			result.append(str(category))
	return result

## 加载素材原图（带缓存）；失败返回 null
func load_image(asset_id: String) -> Image:
	var asset := get_asset(asset_id)
	if asset.is_empty():
		push_warning("[TileMason] load_image：素材不存在 %s" % asset_id)
		return null
	var abs_path := ProjectSettings.globalize_path(str(asset["path"]))
	if _images.has(abs_path):
		return _images[abs_path]
	if not FileAccess.file_exists(str(asset["path"])):
		push_warning("[TileMason] load_image：文件不存在 %s" % str(asset["path"]))
		return null
	var img := Image.load_from_file(abs_path) # 静态方法，失败返回 null（dev-pitfalls 20）
	if img == null:
		push_warning("[TileMason] load_image：读取失败 %s" % str(asset["path"]))
		return null
	_images[abs_path] = img
	return img

## 缩略图纹理（带缓存）；失败返回 null
func load_texture(asset_id: String) -> ImageTexture:
	if _textures.has(asset_id):
		return _textures[asset_id]
	var img := load_image(asset_id)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_textures[asset_id] = tex
	return tex

## 读取单个素材包：pack.json 缺失/损坏则跳过整包并告警；重复扫描同包不翻倍
func _load_pack(pack_dir: String, pack_id: String) -> void:
	for p in packs:
		if str(p["id"]) == pack_id:
			return # 已加载过，直接跳过防止重复扫描翻倍
	var manifest_path := pack_dir.path_join("pack.json")
	if not FileAccess.file_exists(manifest_path):
		push_warning("[TileMason] 素材包缺少 pack.json，跳过：%s" % pack_dir)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		push_warning("[TileMason] pack.json 解析失败，跳过：%s" % manifest_path)
		return
	var manifest := parsed as Dictionary
	packs.append({"id": pack_id, "name": str(manifest.get("name", pack_id)), "dir": pack_dir})
	for raw in manifest.get("assets", []):
		var asset := _normalize_asset(raw as Dictionary, pack_dir, pack_id)
		if asset.is_empty():
			continue
		_assets[str(asset["id"])] = asset

## 清单条目归一化：补默认值、推导缺省 cells；文件缺失或不可读则返回空（跳过）
func _normalize_asset(raw: Dictionary, pack_dir: String, pack_id: String) -> Dictionary:
	var file := str(raw.get("file", ""))
	if file.is_empty():
		push_warning("[TileMason] 清单条目缺 file，跳过（包 %s）" % pack_id)
		return {}
	var path := pack_dir.path_join(file)
	if not FileAccess.file_exists(path):
		push_warning("[TileMason] 素材文件不存在，跳过：%s" % path)
		return {}
	var category := str(raw.get("category", "deco"))
	# 锚点缺省：规则方块类=左上角，其余（建筑/树木等独立物件）=底边中心
	var anchor := str(raw.get("anchor", ANCHOR_TOP_LEFT if TILE_CATEGORIES.has(category) else ANCHOR_BOTTOM_CENTER))
	var asset := {
		"id": "%s/%s" % [pack_id, file],
		"pack": pack_id,
		"file": file,
		"path": path,
		"name": str(raw.get("name", file.get_file())),
		"category": category,
		"anchor": anchor,
		"connections": (raw.get("connections", []) as Array).duplicate(),
	}
	# cells 缺省按 PNG 实际尺寸 / 网格推导（48px→3×3）；清单显式声明优先
	if raw.has("cells"):
		var cells: Array = raw["cells"]
		asset["cells"] = Vector2i(int(cells[0]), int(cells[1])) if cells.size() >= 2 else Vector2i.ONE
	else:
		var img := _read_image_size(path)
		if img == null:
			return {} # 文件存在但不可读，按损坏跳过
		asset["cells"] = Vector2i(maxi(1, ceili(img.x / float(grid_px))), maxi(1, ceili(img.y / float(grid_px))))
	return asset

## 仅读尺寸用：走全局缓存避免重复解码
func _read_image_size(path: String) -> Vector2i:
	var img := load_image_by_path(path)
	if img == null:
		return Vector2i(-1, -1)
	return Vector2i(img.get_width(), img.get_height())

func load_image_by_path(path: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(path)
	if _images.has(abs_path):
		return _images[abs_path]
	var img := Image.load_from_file(abs_path) # 静态方法，失败返回 null（dev-pitfalls 20）
	if img == null:
		return null
	_images[abs_path] = img
	return img
