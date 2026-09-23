extends SceneTree
## [TileMason] 工具栏图标生成器：程序化 24px 像素图标（自绘 CC0），存 res://assets/ui/icons/
## 运行：godot --headless --path . --script res://tools/gen_toolbar_icons.gd

const OUT := "res://assets/ui/icons"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_save("pen", _draw_pen())          # 画笔
	_save("line", _draw_line())        # 直线
	_save("rect", _draw_rect())        # 矩形
	_save("bucket", _draw_bucket())    # 油漆桶
	_save("eraser", _draw_eraser())    # 橡皮擦
	_save("select", _draw_select())    # 选择
	_save("eyedrop", _draw_eyedrop())  # 吸管
	_save("prefab", _draw_prefab())    # 预制件
	_save("undo", _draw_undo())        # 撤销
	_save("redo", _draw_redo())        # 重做
	_save("save", _draw_save())        # 保存（工作流组，质感方案 P1）
	_save("check", _draw_check())      # 检查
	_save("export", _draw_export())    # 导出
	print("[TileMason] 工具图标生成完毕（13 件）")
	quit(0)

func _save(name: String, img: Image) -> void:
	img.save_png(OUT + "/" + name + ".png")

func _canvas() -> Image:
	return Image.create(24, 24, false, Image.FORMAT_RGBA8)

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < 24 and y < 24:
		img.set_pixel(x, y, c)

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for py in range(y, y + h):
		for px2 in range(x, x + w):
			_px(img, px2, py, c)

func _draw_pen() -> Image:
	var img := _canvas()
	var ink := Color(0.35, 0.62, 0.95)
	for i in 14: # 笔杆斜线
		_px(img, 6 + i, 17 - i, ink)
		_px(img, 7 + i, 17 - i, ink)
	_rect(img, 4, 18, 4, 3, ink) # 笔尖
	_rect(img, 17, 3, 4, 4, ink) # 笔帽
	return img

func _draw_line() -> Image:
	var img := _canvas()
	var c := Color(0.85, 0.87, 0.9)
	for i in 16:
		_px(img, 4 + i, 19 - i, c)
		_px(img, 5 + i, 19 - i, c)
	_rect(img, 3, 18, 3, 3, c)
	_rect(img, 18, 3, 3, 3, c)
	return img

func _draw_rect() -> Image:
	var img := _canvas()
	var c := Color(0.85, 0.87, 0.9)
	_rect(img, 4, 6, 16, 2, c)
	_rect(img, 4, 16, 16, 2, c)
	_rect(img, 4, 6, 2, 12, c)
	_rect(img, 18, 6, 2, 12, c)
	return img

func _draw_bucket() -> Image:
	var img := _canvas()
	var body := Color(0.82, 0.45, 0.3)
	_rect(img, 7, 9, 10, 9, body)   # 桶身
	_rect(img, 9, 7, 8, 2, Color(0.6, 0.35, 0.25)) # 桶口
	_px(img, 19, 5, body) # 提手
	_px(img, 20, 4, body)
	_px(img, 18, 4, body)
	_rect(img, 5, 19, 3, 3, Color(0.35, 0.55, 0.9)) # 滴落的漆滴
	return img

func _draw_eraser() -> Image:
	var img := _canvas()
	var c := Color(0.95, 0.72, 0.72)
	for y in 8: # 斜置橡皮块
		for x in 12:
			_px(img, 5 + x + y / 2, 7 + y, c)
	_rect(img, 9, 18, 8, 2, Color(0.7, 0.5, 0.5)) # 底影
	return img

func _draw_select() -> Image:
	var img := _canvas()
	var c := Color(0.98, 0.85, 0.35)
	for i in range(4, 20, 3): # 四边虚线
		_rect(img, i, 4, 2, 2, c)
		_rect(img, i, 18, 2, 2, c)
		_rect(img, 4, i, 2, 2, c)
		_rect(img, 18, i, 2, 2, c)
	return img

func _draw_eyedrop() -> Image:
	var img := _canvas()
	var c := Color(0.55, 0.8, 0.55)
	for i in 12: # 管身
		_px(img, 8 + i, 15 - i, c)
		_px(img, 9 + i, 15 - i, c)
	_rect(img, 5, 17, 4, 3, c) # 吸头
	_rect(img, 17, 3, 4, 5, c) # 胶头
	return img

func _arrow(color: Color, flip: bool) -> Image:
	var img := _canvas()
	for i in 8: # 箭杆
		var y := 10 + i
		var x := (17 - i) if flip else (6 + i)
		_px(img, x, y, color)
		_px(img, x + 1, y, color)
	var tip_x := 6 if flip else 16
	for j in 5: # 箭头折线
		_px(img, tip_x + (j if flip else -j), 10 + j, color)
		_px(img, tip_x + 1 + (j if flip else -j), 10 + j, color)
	return img

func _draw_undo() -> Image:
	return _arrow(Color(0.75, 0.78, 0.85), true)

func _draw_redo() -> Image:
	return _arrow(Color(0.75, 0.78, 0.85), false)

func _draw_prefab() -> Image:
	var img := _canvas()
	var c := Color(0.75, 0.65, 0.95)
	_rect(img, 5, 5, 6, 5, c)   # 上块
	_rect(img, 13, 5, 6, 5, c)
	_rect(img, 5, 13, 6, 5, c)  # 下块
	_rect(img, 13, 13, 6, 5, Color(0.55, 0.45, 0.75))
	return img

func _draw_save() -> Image: # 软盘：轮廓 + 护标签条
	var img := _canvas()
	var c := Color(0.6, 0.78, 0.95)
	_rect(img, 4, 4, 16, 16, c)          # 外形
	_rect(img, 6, 6, 12, 12, Color(0, 0, 0, 0)) # 透明内芯（覆盖为底色不可行，改用深色格）
	_rect(img, 6, 6, 12, 12, Color(0.12, 0.13, 0.16))
	_rect(img, 8, 6, 8, 6, c)            # 护标签
	_rect(img, 9, 13, 6, 4, c)           # 底部读片条
	return img

func _draw_check() -> Image: # 剪贴板 + 对勾
	var img := _canvas()
	var c := Color(0.55, 0.82, 0.6)
	_rect(img, 5, 5, 14, 15, c)          # 板身
	_rect(img, 7, 7, 10, 11, Color(0.12, 0.13, 0.16))
	_rect(img, 9, 4, 6, 3, c)            # 顶部夹子
	var tick := Color(0.55, 0.9, 0.6)
	_px(img, 8, 12, tick)                # 对勾
	_px(img, 9, 13, tick)
	_px(img, 10, 14, tick)
	_px(img, 11, 13, tick)
	_px(img, 12, 12, tick)
	_px(img, 13, 11, tick)
	_px(img, 14, 10, tick)
	return img

func _draw_export() -> Image: # 托盘 + 上行箭头（交付/导出）
	var img := _canvas()
	var c := Color(0.92, 0.75, 0.45)
	for x in range(4, 20):               # 托盘底边
		_px(img, x, 18, c)
		_px(img, x, 19, c)
	_rect(img, 4, 16, 2, 2, c)
	_rect(img, 18, 16, 2, 2, c)
	for y in range(6, 14):               # 箭杆
		_px(img, 11, y, c)
		_px(img, 12, y, c)
	_px(img, 11, 5, c)                   # 箭头折角
	_px(img, 12, 5, c)
	_px(img, 9, 7, c)
	_px(img, 10, 6, c)
	_px(img, 13, 6, c)
	_px(img, 14, 7, c)
	_px(img, 8, 8, c)
	_px(img, 15, 8, c)
	return img
