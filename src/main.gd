extends Node2D
## TileMason 编辑器外壳 —— P0 起步骨架
## 装配编辑相机与网格覆盖层；后续在此接入地图文档、素材库与工具路由

const DEFAULT_GRID := 16 ## 默认正式网格（px）
const MAP_PATH := "user://map.json" ## P0 固定存档槽（文件对话框随 P1 图层 UI 做）

## 素材分类 → 文档图层路由（P0 简化：wall 暂入基础地形层，图层系统扩展后细化）
const CATEGORY_TO_LAYER := {
	"ground": "ground", "road": "ground", "wall": "terrain",
	"building": "building", "tree": "deco", "stall": "deco",
	"indoor": "deco", "furniture": "deco", "deco": "deco",
}

var _document := MapDocument.new() ## 地图文档（design.md §9：规则方块层 + 自由物件层）
var _commands := CommandStack.new() ## 命令栈（撤销/重做地基，后续工具路由接入）
var _library := AssetLibrary.new() ## 素材库（扫描 assets/demo、assets/packs 与 user://packs）
var _view: MapView ## 地图视图（文档 → 画布 Sprite）
var _panel: AssetPanel ## 素材面板（吸管选中联动用）
var _selected_asset_id := "" ## 当前选中素材（素材面板点击/吸管拾取）
var _preview: Sprite2D ## 半透明放置预览（跟随鼠标）
var _painting := false ## 方块笔画进行中（左键按住拖刷）
var _stroke_cells: Array = [] ## 笔画格记录 [{cell, old}]，抬手合成一个命令
var _stroke_layer := ""
var _stroke_asset_id := ""
var _last_cell := Vector2i(99999, 99999) ## 笔画去重
var _eraser_mode := false ## E 键切换：左键/拖动清除当前层（design.md §5）
var _erasing := false ## 擦除笔画进行中
var _erase_cells: Array = [] ## 擦除格记录 [{cell, old}]
var _erase_layer := ""
var _recting := false ## 矩形填充拖框进行中（Ctrl+左键，design.md §2.2/§6.3）
var _rect_start := Vector2i.ZERO
var _rect_preview: RectPreview

func _ready() -> void:
	var camera := EditorCamera.new()
	add_child(camera) # 唯一相机自动接管视图

	_view = MapView.new()
	_view.setup(_document, _library)
	add_child(_view)

	var grid := GridOverlay.new()
	grid.grid_size = DEFAULT_GRID
	add_child(grid)

	var asset_count := _library.scan(AssetLibrary.default_roots())
	_build_asset_panel()

	# 启动自动载入上次存档（验收 8：保存后重新打开仍可编辑）
	if FileAccess.file_exists(MAP_PATH):
		_load_map(false)

	_build_layer_panel()

	_preview = Sprite2D.new()
	_preview.modulate.a = 0.5 # 半透明预览（design.md §2.1）
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.z_index = 50 # 画布内容之上、网格覆盖层(100)之下
	_preview.visible = false
	add_child(_preview)

	_rect_preview = RectPreview.new()
	_rect_preview.z_index = 60
	add_child(_rect_preview)

	print("[TileMason] 编辑器骨架启动：grid=%dpx，文档 %d 层就绪，素材 %d 项；滚轮缩放，中键/空格+左键平移，面板选素材左键放置/拖刷，右键吸管，E 橡皮擦，Ctrl+Z/Y 撤销重做" % [DEFAULT_GRID, _document.layer_count(), asset_count])

	if OS.get_cmdline_user_args().has("--screenshot"):
		_capture_screenshot() # 无人值守视觉取证：摆样 + 延时截屏后退出

## 半透明预览：跟随鼠标展示选中素材落点（面板区域内/橡皮擦模式下隐藏）
func _process(_delta: float) -> void:
	if _eraser_mode or _selected_asset_id.is_empty() or _panel == null or _mouse_over_panel():
		_preview.visible = false
		return
	var asset := _library.get_asset(_selected_asset_id)
	var tex := _library.load_texture(_selected_asset_id)
	if asset.is_empty() or tex == null:
		_preview.visible = false
		return
	_preview.texture = tex
	var cell := mouse_cell()
	if AssetLibrary.TILE_CATEGORIES.has(str(asset["category"])):
		_preview.centered = false
		_preview.position = Vector2(cell) * DEFAULT_GRID
	else:
		var cells: Vector2i = asset["cells"]
		var anchor_x := float(cell.x) * DEFAULT_GRID + cells.x * DEFAULT_GRID / 2.0
		var anchor_y := float(cell.y) * DEFAULT_GRID + cells.y * DEFAULT_GRID
		_preview.centered = true
		_preview.position = Vector2(anchor_x, anchor_y - tex.get_height() / 2.0)
	_preview.visible = true

func _mouse_over_panel() -> bool:
	return _panel.get_global_rect().has_point(_panel.get_global_mouse_position())

## 左键=放置（方块按住拖刷、物件单击），右键=吸管（design.md §6.3）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.ctrl_pressed and not _eraser_mode:
					_begin_rect() # Ctrl+左键：矩形填充拖框
				elif _eraser_mode:
					_begin_erase()
				else:
					_begin_paint()
			else:
				_end_rect()
				_end_paint()
				_end_erase()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if _eraser_mode:
				_begin_erase() # 橡皮擦模式下右键同样清除（design.md §6.3）
			else:
				_pick_under_mouse()
	elif event is InputEventMouseMotion and _painting:
		_paint_to(mouse_cell())
	elif event is InputEventMouseMotion and _erasing:
		_erase_to(mouse_cell())
	elif event is InputEventMouseMotion and _recting:
		_update_rect_preview(mouse_cell())
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_Z:
			_do_undo()
		elif key.ctrl_pressed and key.keycode == KEY_Y:
			_do_redo()
		elif key.ctrl_pressed and key.keycode == KEY_S:
			_save_map()
		elif key.ctrl_pressed and key.keycode == KEY_L:
			_load_map(true)
		elif key.keycode == KEY_E:
			_toggle_eraser()
		elif key.keycode == KEY_F9:
			_run_map_check()

## F9：导出前地图检查（design.md §8 最小版，验收 9）
func _run_map_check() -> void:
	var issues := MapChecker.check_all(_document, _library)
	if issues.is_empty():
		print("[TileMason] 地图检查通过：道路连通，无建筑堵路")
		return
	for issue in issues:
		print("[TileMason] [检查] %s" % str((issue as Dictionary)["message"]))

## 保存当前地图（P0 固定槽位；design.md §10 另存为/版本随后续 UI 扩展）
func _save_map() -> void:
	if _document.save_to_file(MAP_PATH):
		var tiles := 0
		for layer in _document.get_layers():
			tiles += _document.get_tile_coords(str((layer as Dictionary)["id"])).size()
		print("[TileMason] 已保存：%s（%d 方块，%d 物件）" % [MAP_PATH, tiles, _document.get_objects().size()])

## 载入地图：替换文档并重建视图；manual=false 用于启动静默载入
func _load_map(manual: bool) -> void:
	var doc := MapDocument.load_from_file(MAP_PATH)
	if doc == null:
		if manual:
			print("[TileMason] 载入失败：%s" % MAP_PATH)
		return
	_document = doc
	_commands.clear()
	_painting = false
	_erasing = false
	_eraser_mode = false
	_view.queue_free()
	_view = MapView.new()
	_view.setup(_document, _library)
	add_child(_view)
	_build_layer_panel() # 重绑新文档
	var tiles := 0
	for layer in _document.get_layers():
		tiles += _document.get_tile_coords(str((layer as Dictionary)["id"])).size()
	print("[TileMason] 已载入：%s（%d 方块，%d 物件）" % [MAP_PATH, tiles, _document.get_objects().size()])

## Ctrl+Z / Ctrl+Y（design.md §6.3）
func _do_undo() -> void:
	if _commands.undo():
		print("[TileMason] 撤销（剩余可撤销 %d）" % _commands.undo_count())
	else:
		print("[TileMason] 没有可撤销的操作")

func _do_redo() -> void:
	if _commands.redo():
		print("[TileMason] 重做（剩余可重做 %d）" % _commands.redo_count())
	else:
		print("[TileMason] 没有可重做的操作")

## ---- 橡皮擦（design.md §5：单格/笔刷，只清当前层）----

## ---- 矩形填充（design.md §2.2：Ctrl+左键拖框，整块单命令）----

func _begin_rect() -> void:
	if _selected_asset_id.is_empty() or _mouse_over_panel():
		return
	var asset := _library.get_asset(_selected_asset_id)
	if asset.is_empty() or not AssetLibrary.TILE_CATEGORIES.has(str(asset["category"])):
		return # 矩形填充仅用于规则方块
	_rect_start = mouse_cell()
	_recting = true
	_update_rect_preview(_rect_start)

func _update_rect_preview(cell: Vector2i) -> void:
	var r := Rect2i(Vector2i(mini(_rect_start.x, cell.x), mini(_rect_start.y, cell.y)),
		Vector2i(absi(cell.x - _rect_start.x) + 1, absi(cell.y - _rect_start.y) + 1))
	_rect_preview.set_rect_px(Rect2(Vector2(r.position) * DEFAULT_GRID, Vector2(r.size) * DEFAULT_GRID))

func _end_rect() -> void:
	if not _recting:
		return
	_recting = false
	_rect_preview.clear_rect()
	if _mouse_over_panel():
		return
	var asset := _library.get_asset(_selected_asset_id)
	if asset.is_empty():
		return
	var cell := mouse_cell()
	var rect := Rect2i(Vector2i(mini(_rect_start.x, cell.x), mini(_rect_start.y, cell.y)),
		Vector2i(absi(cell.x - _rect_start.x) + 1, absi(cell.y - _rect_start.y) + 1))
	var layer_id: String = CATEGORY_TO_LAYER.get(str(asset["category"]), "ground")
	# Shift 同按=「遇已有内容停止」模式（design.md §2.2），默认覆盖
	var skip := Input.is_key_pressed(KEY_SHIFT)
	var entries: Array = _document.fill_rect(layer_id, rect, str(asset["id"]), skip)
	if entries.is_empty():
		return
	var do_fill := func() -> void:
		for e in entries:
			_document.set_tile(layer_id, (e as Dictionary)["cell"], str(asset["id"]), true)
	var undo_fill := func() -> void:
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			var prev: Dictionary = e["old"]
			if prev.is_empty():
				_document.erase_tile(layer_id, e["cell"], true)
			else:
				_document.set_tile(layer_id, e["cell"], str(prev["asset_id"]), true)
	_commands.push("矩形填充 %d 格%s" % [entries.size(), "（跳过已有）" if skip else ""], do_fill, undo_fill)

func _toggle_eraser() -> void:
	_eraser_mode = not _eraser_mode
	print("[TileMason] 橡皮擦模式：%s" % ("开（左键/右键/拖动清除当前层，E 关闭）" if _eraser_mode else "关"))

## 当前层：选中素材分类路由的图层；未选中默认地面层
func _eraser_layer() -> String:
	if not _selected_asset_id.is_empty():
		var asset := _library.get_asset(_selected_asset_id)
		if not asset.is_empty():
			return CATEGORY_TO_LAYER.get(str(asset["category"]), "deco")
	return "ground"

func _begin_erase() -> void:
	if _mouse_over_panel():
		return
	var layer := _eraser_layer()
	if _document.is_layer_locked(layer):
		print("[TileMason] 图层已锁定，无法擦除：%s" % layer)
		return
	if _document.get_layer(layer)["type"] == "object":
		_erase_object_at(mouse_cell(), layer)
		return
	_erase_layer = layer
	_erasing = true
	_erase_cells = []
	_erase_to(mouse_cell())

func _erase_to(cell: Vector2i) -> void:
	if cell == _last_cell:
		return
	var old: Variant = _document.erase_tile(_erase_layer, cell)
	if old == null:
		return
	_erase_cells.append({"cell": cell, "old": old})
	_last_cell = cell

func _end_erase() -> void:
	_last_cell = Vector2i(99999, 99999)
	if not _erasing:
		return
	_erasing = false
	if _erase_cells.is_empty():
		return
	var entries: Array = _erase_cells.duplicate(true)
	var do_erase := func() -> void:
		for e in entries:
			_document.erase_tile(_erase_layer, (e as Dictionary)["cell"], true)
	var undo_erase := func() -> void:
		for e in entries:
			var prev: Dictionary = (e as Dictionary)["old"]
			if not prev.is_empty():
				_document.set_tile(_erase_layer, (e as Dictionary)["cell"], str(prev["asset_id"]), true)
	_commands.push("擦除 %d 格" % entries.size(), do_erase, undo_erase)

## 物件层擦除：删掉鼠标格脚印覆盖的最上层物件（单命令可撤销）
func _erase_object_at(cell: Vector2i, layer: String) -> void:
	var obj_id := _view.pick_object_on_layer(layer, cell)
	if obj_id < 0:
		return
	var removed: Dictionary = _document.remove_object(obj_id)
	if removed.is_empty():
		return
	var snapshot := removed.duplicate(true)
	var do_del := func() -> void: _document.remove_object(obj_id, true)
	var undo_del := func() -> void: _document.insert_object(snapshot, true)
	_commands.push("擦除物件", do_del, undo_del)

func _begin_paint() -> void:
	if _selected_asset_id.is_empty() or _mouse_over_panel():
		return
	var asset := _library.get_asset(_selected_asset_id)
	if asset.is_empty():
		return
	var cell := mouse_cell()
	if AssetLibrary.TILE_CATEGORIES.has(str(asset["category"])):
		# 方块笔画：按下起笔、拖动连刷、抬手合成一个命令（区域操作整段撤销的地基）
		var layer_id: String = CATEGORY_TO_LAYER.get(str(asset["category"]), "ground")
		if _document.is_layer_locked(layer_id):
			print("[TileMason] 图层已锁定，无法放置：%s" % layer_id)
			return
		_stroke_layer = layer_id
		_stroke_asset_id = _selected_asset_id
		_stroke_cells = []
		_painting = true
		_paint_to(cell)
	else:
		_place_asset(asset, cell) # 物件：单击放置（底边中心对齐），不连刷

func _paint_to(cell: Vector2i) -> void:
	if cell == _last_cell:
		return
	var old: Variant = _document.set_tile(_stroke_layer, cell, _stroke_asset_id)
	if old == null:
		return # 放置被拒（锁定等）
	_stroke_cells.append({"cell": cell, "old": old})
	_last_cell = cell

## 抬手：把整段笔画合成一个命令压栈（undo 一次回滚整段，redo 整段重放）
func _end_paint() -> void:
	_last_cell = Vector2i(99999, 99999)
	if not _painting:
		return
	_painting = false
	if _stroke_cells.is_empty():
		return
	var entries: Array = _stroke_cells.duplicate(true)
	var do_stroke := func() -> void:
		for e in entries:
			_document.set_tile(_stroke_layer, (e as Dictionary)["cell"], _stroke_asset_id, true)
	var undo_stroke := func() -> void:
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			var prev: Dictionary = e["old"]
			if prev.is_empty():
				_document.erase_tile(_stroke_layer, e["cell"], true)
			else:
				_document.set_tile(_stroke_layer, e["cell"], str(prev["asset_id"]), true)
	_commands.push("笔画 %d 格" % entries.size(), do_stroke, undo_stroke)

## 吸管：取鼠标下最上层素材并联动面板选中
func _pick_under_mouse() -> void:
	var picked := _view.pick_asset_id_at(mouse_cell())
	if not picked.is_empty():
		_panel.select_asset(picked)

func mouse_cell() -> Vector2i:
	return Vector2i((get_global_mouse_position() / float(DEFAULT_GRID)).floor())

## 放置素材到指定格（tile 类直接落格；物件类把鼠标格作为占格底边中心）
## 所有编辑走命令栈：可撤销/重做，区域整段撤销在此基础上扩展
func _place_asset(asset: Dictionary, cell: Vector2i) -> void:
	var category := str(asset["category"])
	var layer_id: String = CATEGORY_TO_LAYER.get(category, "deco")
	if _document.is_layer_locked(layer_id):
		print("[TileMason] 图层已锁定，无法放置：%s" % layer_id)
		return
	var asset_id := str(asset["id"])
	var ctx := {} # 引用容器：do/undo 间共享旧值/新对象（dev-pitfalls 11）
	if AssetLibrary.TILE_CATEGORIES.has(category):
		var do_place := func() -> void:
			if not ctx.has("done"):
				ctx["old"] = _document.set_tile(layer_id, cell, asset_id)
				ctx["done"] = true
			else:
				_document.set_tile(layer_id, cell, asset_id, true) # 重做恢复
		var undo_place := func() -> void:
			var prev: Dictionary = ctx.get("old", {})
			if prev.is_empty():
				_document.erase_tile(layer_id, cell, true)
			else:
				_document.set_tile(layer_id, cell, str(prev["asset_id"]), true)
		_commands.push("放置 %s" % str(asset["name"]), do_place, undo_place)
	else:
		var cells: Vector2i = asset["cells"]
		var cell_tl := cell - Vector2i((cells.x - 1) / 2, cells.y - 1) # 底边中心对齐鼠标格
		var do_add := func() -> void:
			if not ctx.has("obj"):
				var new_id := _document.add_object({"asset_id": asset_id, "layer": layer_id, "cell": cell_tl})
				if new_id > 0:
					ctx["obj"] = _document.get_object(new_id)
			else:
				_document.insert_object(ctx["obj"] as Dictionary, true) # 重做按原 id 复原
		var undo_add := func() -> void:
			var obj: Dictionary = ctx.get("obj", {})
			if not obj.is_empty():
				_document.remove_object(int(obj["id"]), true)
		_commands.push("放置 %s" % str(asset["name"]), do_add, undo_add)

## 素材面板：右侧全高停靠（design.md §6.1 最小版）
func _build_asset_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10 # 画布之上、网格覆盖层(100)之下
	add_child(layer)
	_panel = AssetPanel.new()
	_panel.setup(_library)
	_panel.asset_selected.connect(_on_asset_selected)
	layer.add_child(_panel)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -380
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0

var _layer_panel: LayerPanel ## 图层面板（载入新文档时重绑）

## 图层面板：左侧全高停靠（design.md §4 最小版：显示/锁定）
func _build_layer_panel() -> void:
	if _layer_panel == null:
		var layer_ui := CanvasLayer.new()
		layer_ui.layer = 10
		add_child(layer_ui)
		_layer_panel = LayerPanel.new()
		layer_ui.add_child(_layer_panel)
		_layer_panel.anchor_left = 0.0
		_layer_panel.anchor_right = 0.0
		_layer_panel.anchor_top = 0.0
		_layer_panel.anchor_bottom = 1.0
		_layer_panel.offset_left = 0
		_layer_panel.offset_right = 190
		_layer_panel.offset_top = 0
		_layer_panel.offset_bottom = 0
	_layer_panel.setup(_document)

func _on_asset_selected(asset_id: String) -> void:
	_selected_asset_id = asset_id
	var asset := _library.get_asset(asset_id)
	if not asset.is_empty():
		print("[TileMason] 选中素材：%s（%s · %s）" % [asset["name"], asset_id, asset["category"]])

## 视觉取证用：文档为空时程序化摆样（一条道路+草地+建筑+树），延时截屏存盘后退出
## 须窗口模式运行，headless 无渲染
func _capture_screenshot() -> void:
	_demo_place_for_screenshot()
	# 选中建筑并把鼠标移到画布空位：截图中展示半透明放置预览
	_selected_asset_id = "demo/props/house.png"
	get_viewport().warp_mouse(Vector2(150, 330))
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_editor.png")
	_save_map() # 顺带落盘：下轮截图/冒烟验证「保存→重开→仍可编辑」链路
	print("[TileMason] 截图：%s" % ProjectSettings.globalize_path("user://screenshot_editor.png"))
	get_tree().quit(0)

func _demo_place_for_screenshot() -> void:
	if _document.has_content():
		return # 已有内容不摆样
	# 一条东西向道路（y=0，x=-6..-2）
	for x in range(-6, -1):
		_place_asset(_demo_asset("tiles/road_h.png"), Vector2i(x, 0))
	# 道路下铺两块草地
	_place_asset(_demo_asset("tiles/grass.png"), Vector2i(-5, 1))
	_place_asset(_demo_asset("tiles/grass.png"), Vector2i(-4, 1))
	# 建筑与树（物件，底边中心锚自动对齐）
	_place_asset(_demo_asset("props/house.png"), Vector2i(2, 2))
	_place_asset(_demo_asset("props/tree_small.png"), Vector2i(5, 1))
	print("[TileMason] 截图摆样完成：道路×5、草地×2、建筑×1、树×1")

func _demo_asset(file: String) -> Dictionary:
	return _library.get_asset("demo/" + file)
