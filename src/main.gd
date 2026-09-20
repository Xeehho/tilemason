extends Node2D
## TileMason 编辑器外壳 —— P0 起步骨架
## 装配编辑相机与网格覆盖层；后续在此接入地图文档、素材库与工具路由

const DEFAULT_GRID := 16 ## 默认正式网格（px）

var _document := MapDocument.new() ## 地图文档（design.md §9：规则方块层 + 自由物件层）
var _commands := CommandStack.new() ## 命令栈（撤销/重做地基，后续工具路由接入）
var _library := AssetLibrary.new() ## 素材库（扫描 assets/packs 与 user://packs）

func _ready() -> void:
	var camera := EditorCamera.new()
	add_child(camera) # 唯一相机自动接管视图

	var grid := GridOverlay.new()
	grid.grid_size = DEFAULT_GRID
	add_child(grid)

	var asset_count := _library.scan(AssetLibrary.default_roots())
	print("[TileMason] 编辑器骨架启动：grid=%dpx，文档 %d 层就绪，素材 %d 项；滚轮缩放，中键/空格+左键平移" % [DEFAULT_GRID, _document.layer_count(), asset_count])
