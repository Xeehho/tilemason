extends Node2D
## TileMason 编辑器外壳 —— P0 起步骨架
## 装配编辑相机与网格覆盖层；后续在此接入地图文档、素材库与工具路由

const DEFAULT_GRID := 16 ## 默认正式网格（px）

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
var _selected_asset_id := "" ## 当前选中素材（素材面板点击，放置工具使用）

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

	print("[TileMason] 编辑器骨架启动：grid=%dpx，文档 %d 层就绪，素材 %d 项；滚轮缩放，中键/空格+左键平移，面板选素材后左键放置" % [DEFAULT_GRID, _document.layer_count(), asset_count])

	if OS.get_cmdline_user_args().has("--screenshot"):
		_capture_screenshot() # 无人值守视觉取证：摆样 + 延时截屏后退出

## 左键放置当前选中素材（素材面板选中后；面板自身的点击不进这里）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _selected_asset_id.is_empty():
			var asset := _library.get_asset(_selected_asset_id)
			if not asset.is_empty():
				_place_asset(asset, mouse_cell())

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
	var panel := AssetPanel.new()
	panel.setup(_library)
	panel.asset_selected.connect(_on_asset_selected)
	layer.add_child(panel)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -380
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0

func _on_asset_selected(asset_id: String) -> void:
	_selected_asset_id = asset_id
	var asset := _library.get_asset(asset_id)
	if not asset.is_empty():
		print("[TileMason] 选中素材：%s（%s · %s）" % [asset["name"], asset_id, asset["category"]])

## 视觉取证用：文档为空时程序化摆样（一条道路+草地+建筑+树），延时截屏存盘后退出
## 须窗口模式运行，headless 无渲染
func _capture_screenshot() -> void:
	_demo_place_for_screenshot()
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_editor.png")
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
