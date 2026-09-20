extends SceneTree
## [TileMason] 截图像素断言探针：对 --screenshot 产物做程序化视觉取证
## 断言右侧素材面板确实渲染出缩略图（demo 调色板色块出现在面板区、且成整数倍缩放块）
## 运行前置：先窗口模式跑 godot --path . -- --screenshot 生成 user://screenshot_editor.png
## 退出码：0=全部通过，1=有失败

const SHOT_PATH := "user://screenshot_editor.png"
## 面板默认展开第一个分类（地面）→ 只断言该分类两个素材的特征色
const PANEL_PROOF_COLORS: Array = [
	Color("3a7d2c"), # 草地绿
	Color("8a6b47"), # 泥土棕
]
## 其余 demo 特征色（供后续多分类截图取证扩展）
const EXTRA_PROOF_COLORS: Array = [
	Color("555555"), # 道路灰
	Color("3d8a30"), # 树冠绿
	Color("d9c08b"), # 房墙米黄
]
const PANEL_WIDTH := 380 ## 与 main.gd 停靠宽度一致
const COLOR_DIST := 0.07 ## 允许的色彩偏差（sRGB 渲染/抗锯齿）

var _pass := 0
var _fail := 0

func _init() -> void:
	print("[TileMason] 截图像素断言开始")
	if not FileAccess.file_exists(SHOT_PATH):
		_fail += 1
		print("[TileMason] FAIL 截图不存在（先窗口模式跑 -- --screenshot）")
		_finish()
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHOT_PATH))
	_check(img != null and img.get_width() >= 800, "截图分辨率正常（>=800 宽）")
	if img == null:
		_finish()
		return
	_test_panel_region(img)
	_test_canvas_region(img)
	_finish()

func _test_panel_region(img: Image) -> void:
	var panel_left := img.get_width() - PANEL_WIDTH
	var hits: Dictionary = {}
	for color in PANEL_PROOF_COLORS:
		hits[(color as Color).to_html()] = 0
	for y in range(0, img.get_height(), 2):
		for x in range(panel_left + 96, img.get_width(), 2): # 跳过分类列表区，只看缩略图区
			var px := img.get_pixel(x, y)
			for color in PANEL_PROOF_COLORS:
				if _near(px, color as Color):
					hits[(color as Color).to_html()] += 1
					break
	var found := 0
	for color in PANEL_PROOF_COLORS:
		if hits[(color as Color).to_html()] > 0:
			found += 1
	_check(found == PANEL_PROOF_COLORS.size(), "默认分类（地面）两件素材缩略图均渲染（特征色 %d/%d）" % [found, PANEL_PROOF_COLORS.size()])
	# 缩略图整数倍缩放块：草地绿应形成 >=16px 的横向连续段
	var longest := _longest_run(img, panel_left + 96, img.get_width(), Color("3a7d2c"))
	_check(longest >= 16, "特征色成块状渲染（草地绿最长连续 %dpx，>=16 为整数倍缩放块）" % longest)

func _test_canvas_region(img: Image) -> void:
	# 画布区：扫描整列像素，网格线（每 16px 一条）应带来亮度波动；单行采样可能恰好落在两线之间
	var panel_left := img.get_width() - PANEL_WIDTH - 20
	var probe_x := mini(200, panel_left - 1)
	var values: Array = []
	for y in range(0, img.get_height()):
		values.append(img.get_pixel(probe_x, y).v)
	var mn := float(values.min())
	var mx := float(values.max())
	_check(mx - mn > 0.02, "画布区网格线可见（纵向亮度极差 %.4f > 0.02）" % (mx - mn))
	# 摆样内容（--screenshot 模式自动摆的道路/建筑）应出现在画布区
	var road := _count_region(img, 0, panel_left, Color("555555"))
	_check(road > 40, "画布区出现道路（道路灰像素 %d > 40）" % road)
	var roof := _count_region(img, 0, panel_left, Color("8b3a2f"))
	_check(roof > 40, "画布区出现建筑屋顶（砖红像素 %d > 40）" % roof)

func _count_region(img: Image, x0: int, x1: int, color: Color) -> int:
	var count := 0
	for y in range(0, img.get_height(), 2):
		for x in range(x0, x1, 2):
			if _near(img.get_pixel(x, y), color):
				count += 1
	return count

func _longest_run(img: Image, x0: int, x1: int, color: Color) -> int:
	var best := 0
	var run := 0
	var y := img.get_height() / 2
	# 在面板纵向多个高度扫描，取最长横向连续段
	for yy in range(40, img.get_height() - 40, 12):
		run = 0
		for x in range(x0, x1):
			if _near(img.get_pixel(x, yy), color):
				run += 1
				best = maxi(best, run)
			else:
				run = 0
	return best

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < COLOR_DIST and absf(a.g - b.g) < COLOR_DIST and absf(a.b - b.b) < COLOR_DIST

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[TileMason] PASS %s" % name)
	else:
		_fail += 1
		print("[TileMason] FAIL %s" % name)

func _finish() -> void:
	print("[TileMason] 探针结束：通过 %d / 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
