class_name MapView
extends Node2D
## 地图视图：把 MapDocument 数据渲染到画布（P0：每格/每物件一个 Sprite2D，轻量可替换）
## 像素纪律：1:1 原生尺寸 + 最近邻过滤（本节点设置后子节点继承），禁任意缩放
## 注：形态A TileMapLayer 配方（dev-pitfalls 21）为 P4 运行时导出目标；
##     编辑器画布先用 Sprite 渲染，数据模型不变，后续可整体替换渲染层

const OBJECT_Z := 10 ## 物件层基准 z（整体在 tile 层之上，同层内 y-sort）

var document: MapDocument
var library: AssetLibrary
var grid_px := 16

var _tile_sprites := {} # "layer|x,y" -> Sprite2D
var _object_sprites := {} # object_id(int) -> Sprite2D
var _props_root: Node2D
var _layer_z := {} # layer_id -> z_index（tile 层按图层栈顺序）

func setup(doc: MapDocument, lib: AssetLibrary) -> void:
	document = doc
	library = lib
	grid_px = doc.grid_px
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -5 # 画布内容在网格覆盖层(100)之下

	_props_root = Node2D.new()
	_props_root.y_sort_enabled = true # 同层物件按 y 排序遮挡（design.md §4：图层顺序与 y-sort 分离）
	_props_root.z_index = OBJECT_Z
	add_child(_props_root)

	var z := 0
	for layer in doc.get_layers():
		_layer_z[str((layer as Dictionary)["id"])] = z
		z += 1

	document.tile_changed.connect(_on_tile_changed)
	document.object_added.connect(func(id: int) -> void: _sync_object(id))
	document.object_changed.connect(func(id: int) -> void: _sync_object(id))
	document.object_removed.connect(func(id: int) -> void: _remove_object(id))
	document.layer_changed.connect(_on_layer_changed)
	_rebuild()

## ---- 供探针/工具检视 ----

func tile_sprite_count() -> int:
	return _tile_sprites.size()

func get_tile_sprite(layer_id: String, coords: Vector2i) -> Sprite2D:
	return _tile_sprites.get(_tile_key(layer_id, coords))

func get_object_sprite(object_id: int) -> Sprite2D:
	return _object_sprites.get(object_id)

## 吸管：取指定格最上层内容的素材 id（物件层自顶向下按脚印命中，其次 tile 层自顶向下）
## 空格返回空串
func pick_asset_id_at(cell: Vector2i) -> String:
	for i in range(document.layer_count() - 1, -1, -1):
		var layer: Dictionary = document.get_layers()[i]
		var layer_id := str(layer["id"])
		if layer["type"] != "object":
			continue
		for obj in document.get_objects_on_layer(layer_id):
			var o := obj as Dictionary
			var tl: Vector2i = o["cell"]
			var asset := library.get_asset(str(o["asset_id"]))
			var cells: Vector2i = Vector2i.ONE if asset.is_empty() else asset["cells"]
			if cell.x >= tl.x and cell.y >= tl.y and cell.x < tl.x + cells.x and cell.y < tl.y + cells.y:
				return str(o["asset_id"])
	for i in range(document.layer_count() - 1, -1, -1):
		var layer: Dictionary = document.get_layers()[i]
		if str(layer["type"]) != "tile":
			continue
		var entry := document.get_tile(str(layer["id"]), cell)
		if not entry.is_empty():
			return str(entry["asset_id"])
	return ""

## 取某物件层指定格脚印覆盖的物件 id（同层多个取后加入的；无返回 -1）——橡皮擦用
func pick_object_on_layer(layer_id: String, cell: Vector2i) -> int:
	var found := -1
	for obj in document.get_objects_on_layer(layer_id):
		var o := obj as Dictionary
		var tl: Vector2i = o["cell"]
		var asset := library.get_asset(str(o["asset_id"]))
		var cells: Vector2i = Vector2i.ONE if asset.is_empty() else asset["cells"]
		if cell.x >= tl.x and cell.y >= tl.y and cell.x < tl.x + cells.x and cell.y < tl.y + cells.y:
			found = int(o["id"]) # 继续找，保留后加入的
	return found

## 框选（design.md §7）：脚印与矩形相交的物件 id 列表
func objects_in_rect(rect: Rect2i) -> Array:
	var result := []
	for obj in document.get_objects():
		var o := obj as Dictionary
		var tl: Vector2i = o["cell"]
		var asset := library.get_asset(str(o["asset_id"]))
		var cells: Vector2i = Vector2i.ONE if asset.is_empty() else asset["cells"]
		if Rect2i(tl, cells).intersects(rect):
			result.append(int(o["id"]))
	return result

## ---- 选择模式视觉支持 ----

## 选中高亮（黄色调，与半透明预览区分）
func set_objects_tinted(object_ids: Array, on: bool) -> void:
	for id in object_ids:
		var s := _object_sprites.get(int(id)) as Sprite2D
		if s != null:
			s.modulate = Color(1.0, 0.85, 0.4) if on else Color.WHITE

## 拖动预览：记录基准位置（只动 Sprite 不动文档）
func begin_object_drag(object_ids: Array) -> void:
	for id in object_ids:
		var s := _object_sprites.get(int(id)) as Sprite2D
		if s != null:
			s.set_meta("_base_pos", s.position)

## 拖动预览：按像素位移偏移选中 Sprite（取消时 resync 回文档位置）
func drag_object_sprites(object_ids: Array, delta_px: Vector2) -> void:
	for id in object_ids:
		var s := _object_sprites.get(int(id)) as Sprite2D
		if s != null and s.has_meta("_base_pos"):
			s.position = (s.get_meta("_base_pos") as Vector2) + delta_px

## 按文档数据重算物件位置（拖动取消/外部修改后）
func resync_objects(object_ids: Array) -> void:
	for id in object_ids:
		_sync_object(int(id))

## ---- 内部：tile 渲染 ----

func _tile_key(layer_id: String, coords: Vector2i) -> String:
	return "%s|%d,%d" % [layer_id, coords.x, coords.y]

## 图层属性变化：visible 隐藏/显示、opacity 调整透明度（design.md §4）
func _on_layer_changed(layer_id: String, key: String) -> void:
	if key == "visible":
		var visible := bool(document.get_layer(layer_id).get("visible", true))
		for key2 in _tile_sprites.keys():
			if str(key2).begins_with(layer_id + "|"):
				(_tile_sprites[key2] as Sprite2D).visible = visible
		for obj in document.get_objects_on_layer(layer_id):
			var sprite := _object_sprites.get(int((obj as Dictionary)["id"])) as Sprite2D
			if sprite != null:
				sprite.visible = visible
	elif key == "opacity":
		var alpha := float(document.get_layer(layer_id).get("opacity", 1.0))
		for key2 in _tile_sprites.keys():
			if str(key2).begins_with(layer_id + "|"):
				(_tile_sprites[key2] as Sprite2D).modulate.a = alpha
		for obj in document.get_objects_on_layer(layer_id):
			var sprite := _object_sprites.get(int((obj as Dictionary)["id"])) as Sprite2D
			if sprite != null:
				sprite.modulate.a = alpha

## 新建 Sprite 时应用所属图层当前可见性与透明度
func _apply_layer_state(sprite: Sprite2D, layer_id: String) -> void:
	var layer := document.get_layer(layer_id)
	sprite.visible = bool(layer.get("visible", true))
	sprite.modulate.a = float(layer.get("opacity", 1.0))

func _on_tile_changed(layer_id: String, coords: Vector2i) -> void:
	var entry := document.get_tile(layer_id, coords)
	if entry.is_empty():
		var sprite: Sprite2D = _tile_sprites.get(_tile_key(layer_id, coords))
		if sprite != null:
			sprite.queue_free()
			_tile_sprites.erase(_tile_key(layer_id, coords))
		return
	_upsert_tile_sprite(layer_id, coords, str(entry["asset_id"]))

func _upsert_tile_sprite(layer_id: String, coords: Vector2i, asset_id: String) -> void:
	var key := _tile_key(layer_id, coords)
	var sprite := _tile_sprites.get(key) as Sprite2D
	var tex := library.load_texture(asset_id)
	if tex == null:
		return # 素材缺图：数据保留，渲染跳过
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = false # 规则方块左上角锚（design.md §2.1）
		add_child(sprite)
		_tile_sprites[key] = sprite
		_apply_layer_state(sprite, layer_id)
	sprite.texture = tex
	sprite.position = Vector2(coords) * grid_px
	sprite.z_index = int(_layer_z.get(layer_id, 0))

## ---- 内部：物件渲染 ----

func _sync_object(object_id: int) -> void:
	var obj := document.get_object(object_id)
	if obj.is_empty():
		_remove_object(object_id)
		return
	var tex := library.load_texture(str(obj["asset_id"]))
	if tex == null:
		return
	var sprite := _object_sprites.get(object_id) as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		_props_root.add_child(sprite)
		_object_sprites[object_id] = sprite
		_apply_layer_state(sprite, str(obj["layer"]))
	sprite.texture = tex
	sprite.flip_h = bool(obj["mirror_h"])
	sprite.flip_v = bool(obj["mirror_v"])
	# 锚点约定：cell=占格左上角；渲染锚=占格底边中心（形态A 同款几何）
	# Sprite 居中放置 → 中心点 = 锚点上方半个图高；占格尺寸来自素材定义（§9.2 物件只存锚点格）
	var cell: Vector2i = obj["cell"]
	var asset := library.get_asset(str(obj["asset_id"]))
	var cells: Vector2i = Vector2i.ONE
	if not asset.is_empty():
		cells = asset["cells"]
	var anchor_x := float(cell.x) * grid_px + cells.x * grid_px / 2.0
	var anchor_y := float(cell.y) * grid_px + cells.y * grid_px
	sprite.centered = true
	sprite.position = Vector2(anchor_x, anchor_y - tex.get_height() / 2.0)

func _remove_object(object_id: int) -> void:
	var sprite: Sprite2D = _object_sprites.get(object_id)
	if sprite != null:
		sprite.queue_free()
		_object_sprites.erase(object_id)

## ---- 全量重建（加载文档/初始化）----

func _rebuild() -> void:
	for key in _tile_sprites.keys():
		(_tile_sprites[key] as Sprite2D).queue_free()
	_tile_sprites.clear()
	for child in _props_root.get_children():
		child.queue_free()
	_object_sprites.clear()
	for layer in document.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if layer_id.is_empty() or (layer as Dictionary)["type"] != "tile":
			continue
		for coords in document.get_tile_coords(layer_id):
			var entry := document.get_tile(layer_id, coords as Vector2i)
			if not entry.is_empty():
				_upsert_tile_sprite(layer_id, coords as Vector2i, str(entry["asset_id"]))
	for obj in document.get_objects():
		_sync_object(int((obj as Dictionary)["id"]))
