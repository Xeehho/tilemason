extends SceneTree
## [TileMason] demo 占位素材包生成器：程序化像素画，确定性输出（可重复运行，产物一致）
## 产物提交进 assets/demo/ 随仓库分发（自绘 CC0）；assets/packs/ 留给用户自己的包
## 运行：godot --headless --path . --script res://tools/gen_demo_pack.gd

const OUT_DIR := "res://assets/demo"

# 配色（占位集统一色板）
const GRASS_BASE := Color("3a7d2c")
const GRASS_DARK := Color("2f6b22")
const GRASS_LIGHT := Color("4f9a3a")
const DIRT_BASE := Color("8a6b47")
const DIRT_DARK := Color("75583a")
const ROAD_BODY := Color("5a5a5a")
const ROAD_EDGE := Color("2e2e2e")
const ROAD_DASH := Color("c9b458")
const TRUNK := Color("6b4a2b")
const LEAF_DARK := Color("2d6b24")
const LEAF_BASE := Color("3d8a30")
const LEAF_LIGHT := Color("54a344")
const WALL := Color("d9c08b")
const WALL_SHADE := Color("bfa671")
const ROOF := Color("8b3a2f")
const ROOF_DARK := Color("6f2d24")
const DOOR := Color("5a3a1e")
const WINDOW := Color("8fb8d9")
const AWNING_A := Color("c94f4f")
const AWNING_B := Color("f0f0e8")
const WALL_BASE := Color("76766e")
const WALL_DARK := Color("66665f")
const WALL_LIGHT := Color("8a8a80")
const MORTAR := Color("4a4a45")
const STALL_GOODS_A := Color("c9b458")
const STALL_GOODS_B := Color("8fb8d9")

func _init() -> void:
	_prepare_dirs()
	_gen_tile("tiles/grass.png", _paint_grass)
	_gen_tile("tiles/dirt.png", _paint_dirt)
	_gen_tile("tiles/road_h.png", _paint_road_h)
	_gen_tile("tiles/road_corner.png", _paint_road_corner)
	_gen_tile("tiles/wall_brick.png", _paint_wall_brick)
	_gen_tile("tiles/wall_gate.png", _paint_wall_gate)
	_gen_prop("props/tree_small.png", _paint_tree_small)
	_gen_prop("props/tree_big.png", _paint_tree_big)
	_gen_prop("props/house.png", _paint_house)
	_gen_prop("props/house_shop.png", _paint_house_shop)
	_gen_prop("props/stall_red.png", _paint_stall.bind(AWNING_A, STALL_GOODS_A))
	_gen_prop("props/stall_green.png", _paint_stall.bind(Color("4f9a3a"), STALL_GOODS_B))
	# 自动连接变体集：道路/墙各 15 种掩码（P2，design.md §2.2）
	for mask in range(1, 16):
		_gen_tile("tiles/road_v%d.png" % mask, _paint_road_mask.bind(mask))
	for mask in range(1, 16):
		_gen_tile("tiles/wall_v%d.png" % mask, _paint_wall_mask.bind(mask))
	_write_manifest()
	print("[TileMason] demo 素材包生成完毕：%s（42 件）" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _prepare_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "/tiles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "/props"))

func _gen_tile(file: String, painter: Callable) -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	painter.call(img)
	img.save_png(OUT_DIR.path_join(file))

func _gen_prop(file: String, painter: Callable) -> void:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	painter.call(img)
	img.save_png(OUT_DIR.path_join(file))

## 确定性杂色：坐标哈希挑色，避免每次生成长得不一样
func _speckle(img: Image, x: int, y: int, base: Color, dark: Color, light: Color) -> void:
	var h := (x * 7 + y * 13) % 16
	if h == 0:
		img.set_pixel(x, y, dark)
	elif h == 5:
		img.set_pixel(x, y, light)
	else:
		img.set_pixel(x, y, base)

func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, color)

## 填充圆（像素风：中心距离判定 + 单色调）
func _disc(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for py in range(cy - r, cy + r + 1):
		for px in range(cx - r, cx + r + 1):
			if Vector2(px - cx, py - cy).length() <= r:
				img.set_pixel(px, py, color)

# ---- 16px 规则方块 ----

func _paint_grass(img: Image) -> void:
	for y in 16:
		for x in 16:
			_speckle(img, x, y, GRASS_BASE, GRASS_DARK, GRASS_LIGHT)

func _paint_dirt(img: Image) -> void:
	for y in 16:
		for x in 16:
			_speckle(img, x, y, DIRT_BASE, DIRT_DARK, DIRT_LIGHT)
	# 石子点缀
	img.set_pixel(3, 4, Color("a08a6a"))
	img.set_pixel(11, 9, Color("a08a6a"))
	img.set_pixel(7, 13, Color("a08a6a"))

const DIRT_LIGHT := Color("9c7d55")

func _paint_road_h(img: Image) -> void:
	_rect(img, 0, 0, 16, 2, ROAD_EDGE) # 上路缘
	_rect(img, 0, 14, 16, 2, ROAD_EDGE) # 下路缘
	_rect(img, 0, 2, 16, 12, ROAD_BODY) # 路面
	for x in range(2, 14, 4): # 中央虚线
		_rect(img, x, 7, 2, 2, ROAD_DASH)

func _paint_road_corner(img: Image) -> void:
	# 连接方向：右+下（L 形弯道占位）
	_rect(img, 0, 0, 16, 2, ROAD_EDGE)
	_rect(img, 0, 14, 16, 2, ROAD_EDGE)
	_rect(img, 0, 0, 2, 16, ROAD_EDGE)
	_rect(img, 14, 0, 2, 16, ROAD_EDGE)
	_rect(img, 2, 2, 14, 12, ROAD_BODY) # 横向路面（通右）
	_rect(img, 2, 2, 12, 14, ROAD_BODY) # 纵向路面（通下）
	_rect(img, 12, 12, 2, 2, ROAD_DASH) # 弯道提示点

# ---- 48px 独立物件（底边中心锚约定由素材库按分类默认处理）----

func _paint_tree_small(img: Image) -> void:
	_rect(img, 22, 30, 4, 18, TRUNK) # 树干落地（底边 y=47）
	_disc(img, 24, 18, 12, LEAF_BASE)
	_disc(img, 19, 14, 5, LEAF_LIGHT)
	_disc(img, 29, 22, 4, LEAF_DARK)

func _paint_tree_big(img: Image) -> void:
	_rect(img, 21, 26, 6, 22, TRUNK)
	_disc(img, 24, 16, 16, LEAF_DARK)
	_disc(img, 24, 15, 13, LEAF_BASE)
	_disc(img, 18, 10, 6, LEAF_LIGHT)
	_disc(img, 30, 20, 5, LEAF_LIGHT)

func _paint_house(img: Image) -> void:
	# 墙体（落地 y=47）
	_rect(img, 8, 18, 32, 30, WALL)
	_rect(img, 8, 44, 32, 4, WALL_SHADE) # 墙脚阴影
	# 阶梯屋顶（从尖到宽）
	for i in 14:
		var w := 6 + i * 2
		_rect(img, 24 - w / 2, 4 + i, w, 1, ROOF if i % 5 != 0 else ROOF_DARK)
	# 门（底边中心）与窗
	_rect(img, 20, 32, 8, 16, DOOR)
	_rect(img, 12, 24, 6, 6, WINDOW)
	_rect(img, 30, 24, 6, 6, WINDOW)

func _paint_house_shop(img: Image) -> void:
	_paint_house(img)
	# 店铺差异：雨棚条纹 + 招牌底座
	for x in range(8, 40, 4):
		_rect(img, x, 18, 4, 5, AWNING_A if ((x - 8) / 4) % 2 == 0 else AWNING_B)
	_rect(img, 24, 24, 12, 6, Color("3d3d3d")) # 招牌占位
	_rect(img, 26, 26, 8, 2, Color("f0d060"))

# ---- 墙与摊位（demo 扩充：12 件）----

func _paint_wall_brick(img: Image) -> void:
	for y in 16:
		for x in 16:
			_speckle(img, x, y, WALL_BASE, WALL_DARK, WALL_LIGHT)
	for y in range(0, 16, 4): # 水平砖缝
		for x in 16:
			img.set_pixel(x, y, MORTAR)
	for row in 4: # 垂直砖缝（逐行错缝）
		var joints := [8] if row % 2 == 0 else [4, 12]
		for jx in joints:
			for y in range(row * 4 + 1, row * 4 + 4):
				img.set_pixel(jx, y, MORTAR)

func _paint_wall_gate(img: Image) -> void:
	_paint_wall_brick(img)
	_rect(img, 4, 8, 8, 8, DOOR) # 门洞占下半（P2 自动连接按整墙处理）

## 摊位绘制（雨棚主色 + 货品色经 bind 传入；支柱/柜台共用）
func _paint_stall(img: Image, canopy: Color, goods: Color) -> void:
	_rect(img, 6, 8, 3, 40, TRUNK) # 支柱
	_rect(img, 39, 8, 3, 40, TRUNK)
	_rect(img, 4, 30, 40, 18, Color("8a6b47")) # 柜台
	_rect(img, 4, 30, 40, 3, Color("a08a6a")) # 台面
	for x in range(2, 46, 6): # 雨棚条纹
		_rect(img, x, 4, 6, 10, canopy if ((x - 2) / 6) % 2 == 0 else AWNING_B)
	_rect(img, 2, 14, 44, 2, Color("3d3d3d")) # 棚檐
	_rect(img, 12, 26, 5, 4, goods) # 货品
	_rect(img, 22, 26, 5, 4, goods)
	_rect(img, 32, 26, 5, 4, goods)

## 通用道路变体：开方向路面通到边，闭方向画 3px 路缘带（N=1 E=2 S=4 W=8）
func _paint_road_mask(img: Image, mask: int) -> void:
	_rect(img, 0, 0, 16, 16, ROAD_BODY)
	if not (mask & 1): # N 闭
		_rect(img, 0, 0, 16, 3, ROAD_EDGE)
	if not (mask & 4): # S 闭
		_rect(img, 0, 13, 16, 3, ROAD_EDGE)
	if not (mask & 8): # W 闭
		_rect(img, 0, 0, 3, 16, ROAD_EDGE)
	if not (mask & 2): # E 闭
		_rect(img, 13, 0, 3, 16, ROAD_EDGE)
	_rect(img, 7, 7, 2, 2, ROAD_DASH) # 中心提示点

## 通用墙变体：砖面打底，闭方向画砂浆封边带
func _paint_wall_mask(img: Image, mask: int) -> void:
	_paint_wall_brick(img)
	if not (mask & 1):
		_rect(img, 0, 0, 16, 2, MORTAR)
	if not (mask & 4):
		_rect(img, 0, 14, 16, 2, MORTAR)
	if not (mask & 8):
		_rect(img, 0, 0, 2, 16, MORTAR)
	if not (mask & 2):
		_rect(img, 14, 0, 2, 16, MORTAR)

func _write_manifest() -> void:
	var assets := [
		{"file": "tiles/grass.png", "name": "草地", "category": "ground"},
		{"file": "tiles/dirt.png", "name": "泥土", "category": "ground"},
		{"file": "tiles/road_h.png", "name": "道路·直", "category": "road", "connections": ["left", "right"]},
		{"file": "tiles/road_corner.png", "name": "道路·弯", "category": "road", "connections": ["right", "down"]},
		{"file": "tiles/wall_brick.png", "name": "砖墙", "category": "wall", "connections": ["left", "right"]},
		{"file": "tiles/wall_gate.png", "name": "墙·门洞", "category": "wall", "connections": ["left", "right"]},
		{"file": "props/tree_small.png", "name": "小树", "category": "tree"},
		{"file": "props/tree_big.png", "name": "大树", "category": "tree"},
		{"file": "props/house.png", "name": "民居", "category": "building"},
		{"file": "props/house_shop.png", "name": "店铺", "category": "building"},
		{"file": "props/stall_red.png", "name": "摊位·食", "category": "stall"},
		{"file": "props/stall_green.png", "name": "摊位·杂", "category": "stall"},
	]
	# 变体清单：连接方向按掩码位生成（与 AutoConnect.mask_to_dirs 同序）
	const DIR_NAMES := ["up", "right", "down", "left"]
	for mask in range(1, 16):
		var dirs := []
		for i in 4:
			if mask & (1 << i):
				dirs.append(DIR_NAMES[i])
		var label := "+".join(dirs)
		assets.append({"file": "tiles/road_v%d.png" % mask, "name": "路·%s" % label, "category": "road", "connections": dirs})
		assets.append({"file": "tiles/wall_v%d.png" % mask, "name": "墙·%s" % label, "category": "wall", "connections": dirs})
	var f := FileAccess.open(OUT_DIR + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "演示素材包", "assets": assets}, "\t"))
	f = null
