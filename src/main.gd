extends Node2D
## TileMason 编辑器外壳 —— P0 起步骨架
## 装配编辑相机与网格覆盖层；后续在此接入地图文档、素材库与工具路由

const DEFAULT_GRID := 16 ## 默认正式网格（px）

var _document := MapDocument.new() ## 地图文档（design.md §9：规则方块层 + 自由物件层）
var _commands := CommandStack.new() ## 命令栈（撤销/重做地基，后续工具路由接入）
var _library := AssetLibrary.new() ## 素材库（扫描 assets/demo、assets/packs 与 user://packs）
var _selected_asset_id := "" ## 当前选中素材（素材面板点击，后续放置工具使用）

func _ready() -> void:
	var camera := EditorCamera.new()
	add_child(camera) # 唯一相机自动接管视图

	var grid := GridOverlay.new()
	grid.grid_size = DEFAULT_GRID
	add_child(grid)

	var asset_count := _library.scan(AssetLibrary.default_roots())
	_build_asset_panel()

	print("[TileMason] 编辑器骨架启动：grid=%dpx，文档 %d 层就绪，素材 %d 项；滚轮缩放，中键/空格+左键平移" % [DEFAULT_GRID, _document.layer_count(), asset_count])

	if OS.get_cmdline_user_args().has("--screenshot"):
		_capture_screenshot() # 无人值守视觉取证：延时截屏后退出

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

## 视觉取证用：等待布局与纹理就绪后截屏存盘并退出（须窗口模式运行，headless 无渲染）
func _capture_screenshot() -> void:
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_editor.png")
	print("[TileMason] 截图：%s" % ProjectSettings.globalize_path("user://screenshot_editor.png"))
	get_tree().quit(0)
