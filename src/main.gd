extends Node2D
## TileMason 编辑器外壳 —— P0 起步骨架
## 装配编辑相机与网格覆盖层；后续在此接入地图文档、素材库与工具路由

const DEFAULT_GRID := 16 ## 默认正式网格（px）

func _ready() -> void:
	var camera := EditorCamera.new()
	add_child(camera) # 唯一相机自动接管视图

	var grid := GridOverlay.new()
	grid.grid_size = DEFAULT_GRID
	add_child(grid)

	print("[TileMason] 编辑器骨架启动：grid=%dpx，滚轮缩放，中键/空格+左键平移" % DEFAULT_GRID)
