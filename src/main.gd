extends Node2D
## TileMason 编辑器外壳 —— P0 起步骨架
## 装配编辑相机与网格覆盖层；后续在此接入地图文档、素材库与工具路由

const DEFAULT_GRID := 16 ## 默认正式网格（px）
const MAP_PATH := "user://map.json" ## 默认存档槽（启动自动恢复用）
const RECENT_PATH := "user://recent.json" ## 最近使用素材（最多 10 件）
const FAVORITES_PATH := "user://favorites.json" ## 收藏素材（F 键切换）
const AUTOSAVE_PATH := "user://map.autosave.json" ## 自动保存档（手动档丢失时兜底恢复）
var _current_map_path := MAP_PATH ## 当前编辑中的地图文件（打开/另存为切换，Ctrl+S 存这里）
var _dirty := false ## 有未保存变更（命令栈活动即置位，自动保存成功复位）

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
var _stroke_extra := {} ## 笔画期间的自动连接变更（cell -> {old_asset_id, new_asset_id}）
var _stroke_layer := ""
var _stroke_asset_id := ""
var _last_cell := Vector2i(99999, 99999) ## 笔画去重
var _eraser_mode := false ## E 键切换：左键/拖动清除当前层（design.md §5）
var _erasing := false ## 擦除笔画进行中
var _erase_cells: Array = [] ## 擦除格记录 [{cell, old}]
var _erase_extra := {} ## 擦除期间的自动连接变更
var _erase_layer := ""
var _recting := false ## 矩形填充拖框进行中（Ctrl+左键，design.md §2.2/§6.3）
var _rect_start := Vector2i.ZERO
var _rect_preview: RectPreview
var _footprint_preview: RectPreview ## 占格范围框（多格物件预览时显示覆盖区域，design.md §4/§8）
var _footprint_demo_lock := false ## 截图取证：锁定固定范围框，跳过 _process 的鼠标跟随
var _bucket_mode := false ## G 键油漆桶（design.md §2.2）：左键填充连通同素材区域
var _current_prefab := "" ## 当前预制件名（Ctrl+P 保存并选定、P 放置）
var _prefab_panel: PrefabPanel ## 预制件面板（列表/选用/删除）
var _tags := {} ## 素材标签表 {asset_id: [tag...]}（T 键编辑，user://tags.json）
var _tag_input_mode := false ## T 键标签输入模式（状态栏输入行，Enter/Esc）
var _tag_input_text := "" ## 输入缓冲
var _hotbar: Hotbar ## 底部快捷栏（design.md §6.2）
var _recent: Array = [] ## 最近使用素材 id（新选中的排最前）
var _favorites: Array = [] ## 收藏素材 id
const HOTBAR_DEFAULT: Array = [ ## 1-7 素材位默认绑定（随演示包；用户素材包就位后可扩展自定义）
	"demo/tiles/grass.png", "demo/tiles/road_h.png", "demo/tiles/wall_brick.png",
	"demo/props/house.png", "demo/props/tree_small.png", "demo/props/stall_red.png",
	"demo/props/house_shop.png",
]
var _selection := Selection.new() ## 选区（S 选择模式）
var _select_mode := false ## S 键切换：框选/移动物件（design.md §2.1/§7）
var _marqueeing := false ## 框选拖动进行中
var _marquee_start := Vector2i.ZERO
var _moving := false ## 选中物件拖动进行中
var _move_start_px := Vector2.ZERO
var _clipboard: Array = [] ## 复制的物件快照（design.md §7 复制粘贴）
var _clip_cells: Array = [] ## 复制的方块快照 [{layer, cell, asset_id}]；与物件共用粘贴基准
var _line_mode := false ## L 键直线工具（design.md §2.2）
var _line_armed := false ## 已定起点，等待终点
var _line_start := Vector2i.ZERO
var _line_sprites: Array = [] ## 直线预览 Sprite 池
var _status: StatusBar ## 底部状态栏（当前工具/素材常驻可见）

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
	_recent = _load_id_list(RECENT_PATH)
	_favorites = _load_id_list(FAVORITES_PATH)
	_build_asset_panel()
	_panel.set_recent(_recent)
	_panel.set_favorites(_favorites)
	_tags = TagStore.load_all()
	_panel.set_tags(TagStore.reverse_index(_tags))

	# 启动自动恢复：手动档优先，手动档丢失时从自动保存档兜底（design.md §10 恢复上一版本最小版）
	if FileAccess.file_exists(MAP_PATH):
		_load_map(false)
	elif FileAccess.file_exists(AUTOSAVE_PATH):
		if _load_map_from(AUTOSAVE_PATH):
			_current_map_path = MAP_PATH # 继续编辑仍指向手动档槽位
			print("[TileMason] 手动档缺失，已从自动保存恢复")

	_build_layer_panel()
	_build_status_bar()
	_build_hotbar()
	_connect_status_signals()
	_setup_autosave()
	if FileAccess.file_exists("user://prefab_current.json"):
		var pf := FileAccess.open("user://prefab_current.json", FileAccess.READ)
		if pf != null:
			_current_prefab = pf.get_as_text().strip_edges()
	refresh_status()

	_preview = Sprite2D.new()
	_preview.modulate.a = 0.5 # 半透明预览（design.md §2.1）
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.z_index = 50 # 画布内容之上、网格覆盖层(100)之下
	_preview.visible = false
	add_child(_preview)

	_rect_preview = RectPreview.new()
	_rect_preview.z_index = 60
	add_child(_rect_preview)

	_footprint_preview = RectPreview.new()
	_footprint_preview.z_index = 59 # 在预览 Sprite 之下、画布内容之上
	_footprint_preview.modulate = Color(0.35, 1.0, 0.45) # 绿色系：范围提示，与白色矩形工具区分
	add_child(_footprint_preview)

	print("[TileMason] 编辑器骨架启动：grid=%dpx，文档 %d 层就绪，素材 %d 项；滚轮缩放，中键/空格+左键平移，面板选素材左键放置/拖刷，右键吸管，E 橡皮擦，Ctrl+Z/Y 撤销重做" % [DEFAULT_GRID, _document.layer_count(), asset_count])

	if OS.get_cmdline_user_args().has("--screenshot"):
		_capture_screenshot() # 无人值守视觉取证：摆样 + 延时截屏后退出

## 半透明预览：跟随鼠标展示选中素材落点（面板区域内/橡皮擦模式下隐藏）
## 多格物件同时显示占格范围框（design.md §4 覆盖关系 / §8 占用格范围）
func _process(_delta: float) -> void:
	if _footprint_demo_lock:
		return # 截图取证模式：范围框由 _capture_screenshot 固定控制
	if _eraser_mode or _selected_asset_id.is_empty() or _panel == null or _mouse_over_panel():
		_preview.visible = false
		_footprint_preview.visible = false
		return
	var asset := _library.get_asset(_selected_asset_id)
	var tex := _library.load_texture(_selected_asset_id)
	if asset.is_empty() or tex == null:
		_preview.visible = false
		_footprint_preview.visible = false
		return
	_preview.texture = tex
	var cell := mouse_cell()
	if AssetLibrary.TILE_CATEGORIES.has(str(asset["category"])):
		_preview.centered = false
		_preview.position = Vector2(cell) * DEFAULT_GRID
		_footprint_preview.visible = false # 单格方块无需范围框
	else:
		var cells: Vector2i = asset["cells"]
		# 预览与放置共用同一几何：鼠标格=占格底边中心（修复图影与落点不一致）
		var cell_tl := MapView.footprint_cell_tl(cells, cell)
		_preview.centered = true
		_preview.position = MapView.object_sprite_position(cell_tl, cells, DEFAULT_GRID, tex.get_height())
		# 范围框与预览同步：覆盖整个占格区域（左上角锚矩形）
		_footprint_preview.set_rect_px(Rect2(Vector2(cell_tl) * DEFAULT_GRID, Vector2(cells) * DEFAULT_GRID))
		_footprint_preview.visible = true
	_preview.visible = true

func _mouse_over_panel() -> bool:
	return _panel.get_global_rect().has_point(_panel.get_global_mouse_position())

## 左键=放置（方块按住拖刷、物件单击），右键=吸管（design.md §6.3）
func _unhandled_input(event: InputEvent) -> void:
	# 标签输入模式：吞掉一切输入，只响应字符/退格/回车/Esc（design.md §6.1 标签）
	if _tag_input_mode and event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			_exit_tag_input()
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			_commit_tag_input()
		elif k.keycode == KEY_BACKSPACE:
			_tag_input_text = _tag_input_text.substr(0, _tag_input_text.length() - 1)
			refresh_tag_input()
		elif k.unicode >= 32:
			_tag_input_text += char(k.unicode)
			refresh_tag_input()
		return # 输入态不透传其他快捷键
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _bucket_mode:
					_do_bucket_fill(mouse_cell())
				elif _line_mode:
					_line_click(mouse_cell())
				elif _select_mode:
					_begin_select_action()
				elif mb.ctrl_pressed:
					_begin_rect() # Ctrl+左键：矩形填充拖框
				elif _eraser_mode:
					_begin_erase()
				else:
					_begin_paint()
			else:
				_end_rect()
				_end_select_action()
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
	elif event is InputEventMouseMotion and _marqueeing:
		_update_marquee_preview(mouse_cell())
	elif event is InputEventMouseMotion and _moving:
		var delta_px := get_global_mouse_position() - _move_start_px
		_view.drag_object_sprites(_selection.object_ids(), delta_px)
		_view.drag_cells_sprites(_selection.cells_by_layer(), delta_px)
	elif event is InputEventMouseMotion and _line_armed:
		_rebuild_line_preview(mouse_cell())
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_Z:
			_do_undo()
		elif key.ctrl_pressed and key.keycode == KEY_Y:
			_do_redo()
		elif key.ctrl_pressed and key.keycode == KEY_S:
			if key.shift_pressed:
				_save_as_dialog() # Ctrl+Shift+S 另存为
			else:
				_save_map()
		elif key.ctrl_pressed and key.keycode == KEY_O:
			_open_map_dialog()
		elif key.ctrl_pressed and key.keycode == KEY_L:
			_load_map(true)
		elif key.keycode == KEY_E:
			_toggle_eraser()
		elif key.keycode == KEY_S and not key.ctrl_pressed:
			_toggle_select_mode()
		elif key.keycode == KEY_L and not key.ctrl_pressed:
			_toggle_line_mode()
		elif key.keycode == KEY_G and not key.ctrl_pressed:
			_toggle_bucket_mode()
		elif key.keycode == KEY_F and not key.ctrl_pressed:
			_toggle_favorite()
		elif key.keycode == KEY_R and not key.ctrl_pressed:
			_batch_replace_under_mouse()
		elif key.keycode == KEY_T and not key.ctrl_pressed:
			_begin_tag_input()
		elif key.keycode == KEY_TAB:
			_panel.visible = not _panel.visible # design.md §6.3 Tab 显隐素材库
			print("[TileMason] 素材面板：%s" % ("显示" if _panel.visible else "隐藏（Tab 再显）"))
		elif key.keycode == KEY_Q and not key.ctrl_pressed:
			_focus_selection() # design.md §6.3 F 聚焦——F 被收藏占用，用 Q 近旁键位
		elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
			_hotbar_activate(key.keycode - KEY_1)
		elif key.keycode == KEY_ESCAPE:
			_exit_select_mode()
			_exit_line_mode()
			if _bucket_mode:
				_toggle_bucket_mode()
		elif key.ctrl_pressed and key.keycode == KEY_C:
			_copy_selected()
		elif key.ctrl_pressed and key.keycode == KEY_V:
			_paste_clipboard()
		elif key.ctrl_pressed and key.keycode == KEY_P:
			_save_prefab_from_selection()
		elif key.ctrl_pressed and key.keycode == KEY_E:
			_export_map()
		elif key.keycode == KEY_P and not key.ctrl_pressed:
			_place_current_prefab()
		elif key.ctrl_pressed and key.keycode == KEY_A:
			_select_all()
		elif key.keycode == KEY_DELETE:
			_delete_selected()
		elif key.keycode == KEY_H and not key.ctrl_pressed:
			_mirror_selected()
		elif key.keycode == KEY_F9:
			_run_map_check()
		elif key.keycode == KEY_F8:
			_show_connection_rules()

## F8：连接规则查看（design.md §2.2 只读版，P3）——弹窗展示素材包声明的连接规则
func _show_connection_rules() -> void:
	var viewer := ConnectionRulesViewer.new()
	viewer.setup(_library)
	viewer.confirmed.connect(func() -> void: viewer.queue_free())
	viewer.close_requested.connect(func() -> void: viewer.queue_free())
	add_child(viewer)
	viewer.popup_centered(Vector2i(620, 520))
	var declared := 0
	for rule in viewer.rules:
		declared += ((rule as Dictionary)["assets"] as Array).size()
	print("[TileMason] 连接规则查看：%d 个分类、%d 件声明连接素材" % [viewer.rules.size(), declared])

## F9：导出前地图检查（design.md §8 最小版，验收 9）
func _run_map_check() -> void:
	var issues := MapChecker.check_all(_document, _library)
	if issues.is_empty():
		print("[TileMason] 地图检查通过：道路连通，无建筑堵路")
		return
	for issue in issues:
		print("[TileMason] [检查] %s" % str((issue as Dictionary)["message"]))

## 保存当前地图到当前文件（design.md §10；另存为走 _save_as_dialog）
func _save_map() -> void:
	if _document.save_to_file(_current_map_path):
		_dirty = false
		var tiles := 0
		for layer in _document.get_layers():
			tiles += _document.get_tile_coords(str((layer as Dictionary)["id"])).size()
		print("[TileMason] 已保存：%s（%d 方块，%d 物件）" % [_current_map_path, tiles, _document.get_objects().size()])

## 载入地图：替换文档并重建视图；manual=false 用于启动静默载入
func _load_map(manual: bool) -> void:
	if not _load_map_from(MAP_PATH) and manual:
		print("[TileMason] 载入失败：%s" % MAP_PATH)

## 从指定文件载入（打开对话框/启动恢复共用）；成功返回 true
func _load_map_from(path: String) -> bool:
	var doc := MapDocument.load_from_file(path)
	if doc == null:
		return false
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
	_connect_status_signals()
	refresh_status()
	var tiles := 0
	for layer in _document.get_layers():
		tiles += _document.get_tile_coords(str((layer as Dictionary)["id"])).size()
	print("[TileMason] 已载入：%s（%d 方块，%d 物件）" % [path, tiles, _document.get_objects().size()])
	return true

## ---- 文件对话框（design.md §10：另存为不同地图/打开）----

func _open_map_dialog() -> void:
	var dialog := _make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	dialog.file_selected.connect(func(path: String) -> void:
		if _load_map_from(path):
			_current_map_path = path
			print("[TileMason] 当前地图切换为：%s" % path))

func _save_as_dialog() -> void:
	var dialog := _make_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	dialog.file_selected.connect(func(path: String) -> void:
		_current_map_path = path
		_save_map())

func _make_dialog(mode: int) -> FileDialog:
	var dialog := FileDialog.new()
	if "use_native_dialog" in dialog:
		dialog.use_native_dialog = true # 优先系统原生对话框
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = ["*.json ; TileMason 地图"]
	dialog.current_dir = ProjectSettings.globalize_path("user://")
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.file_selected.connect(func(_p: String) -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(900, 550))
	return dialog

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
	var extras := {}
	for e in entries:
		_harvest_refresh(layer_id, (e as Dictionary)["cell"], extras)
	_push_tile_command("矩形填充 %d 格%s" % [entries.size(), "（跳过已有）" if skip else ""], layer_id, entries, extras, str(asset["id"]))

## ---- 选择模式（design.md §2.1/§7：框选、多选移动）----

func _toggle_select_mode() -> void:
	if _select_mode:
		_exit_select_mode()
		return
	_select_mode = true
	print("[TileMason] 选择模式：拖框选物件，拖动选中物件移动，Esc/S 退出")
	refresh_status()

func _exit_select_mode() -> void:
	if not _select_mode:
		return
	_select_mode = false
	_marqueeing = false
	_moving = false
	_rect_preview.clear_rect()
	_view.set_objects_tinted(_selection.object_ids(), false)
	_view.resync_objects(_selection.object_ids()) # 丢弃未提交的拖动位移
	_view.resync_cells(_selection.cells_by_layer())
	_selection.clear()
	print("[TileMason] 选择模式关闭")
	refresh_status()

## 按下：点中已选物件/已选格→拖动移动；否则→框选
func _begin_select_action() -> void:
	if _mouse_over_panel():
		return
	var cell := mouse_cell()
	var hits := _view.objects_in_rect(Rect2i(cell, Vector2i.ONE))
	var hit_id := -1
	for id in hits:
		hit_id = int(id) # 取最后一个（近似最上层）
	var can_move := (hit_id >= 0 and _selection.has_object(hit_id)) or _cell_selected_at(cell)
	if can_move and not _selection.is_empty():
		_moving = true
		_move_start_px = get_global_mouse_position()
		_view.begin_object_drag(_selection.object_ids())
		_view.begin_cells_drag(_selection.cells_by_layer())
	else:
		_marqueeing = true
		_marquee_start = cell
		_update_marquee_preview(cell)

## 该格是否在选区（任意层）
func _cell_selected_at(cell: Vector2i) -> bool:
	for layer_id in _selection.cells_by_layer().keys():
		if _selection.has_cell(str(layer_id), cell):
			return true
	return false

func _update_marquee_preview(cell: Vector2i) -> void:
	var r := Rect2i(Vector2i(mini(_marquee_start.x, cell.x), mini(_marquee_start.y, cell.y)),
		Vector2i(absi(cell.x - _marquee_start.x) + 1, absi(cell.y - _marquee_start.y) + 1))
	_rect_preview.set_rect_px(Rect2(Vector2(r.position) * DEFAULT_GRID, Vector2(r.size) * DEFAULT_GRID))

func _end_select_action() -> void:
	if _marqueeing:
		_marqueeing = false
		_rect_preview.clear_rect()
		var cell := mouse_cell()
		var rect := Rect2i(Vector2i(mini(_marquee_start.x, cell.x), mini(_marquee_start.y, cell.y)),
			Vector2i(absi(cell.x - _marquee_start.x) + 1, absi(cell.y - _marquee_start.y) + 1))
		if rect.size == Vector2i.ONE:
			# 单击：点中物件→单选；空地→清空
			var hits := _view.objects_in_rect(Rect2i(cell, Vector2i.ONE))
			_apply_selection(hits if not hits.is_empty() else [])
		else:
			_apply_selection(_view.objects_in_rect(rect), _view.tiles_in_rect(rect))
	elif _moving:
		_moving = false
		var delta_cell := Vector2i(((get_global_mouse_position() - _move_start_px) / float(DEFAULT_GRID)).round())
		if delta_cell == Vector2i.ZERO:
			_view.resync_objects(_selection.object_ids())
			_view.resync_cells(_selection.cells_by_layer())
			return
		_commit_move(delta_cell)

func _apply_selection(ids: Array, cells := {}) -> void:
	_clear_selection_tints()
	_selection.set_objects(ids)
	for layer_id in (cells as Dictionary).keys():
		for c in (cells as Dictionary)[str(layer_id)]:
			_selection.add_cell(str(layer_id), c as Vector2i)
	_view.set_objects_tinted(ids, true)
	for layer_id in _selection.cells_by_layer().keys():
		_view.set_cells_tinted(str(layer_id), _selection.cells_by_layer()[str(layer_id)], true)
	if _selection.is_empty():
		print("[TileMason] 取消选择")
	else:
		print("[TileMason] 选中 %d 件物件、%d 格" % [_selection.object_count(), _selection.cell_count()])

## 清掉当前选区在视图上的全部高亮（物件 + 格）
func _clear_selection_tints() -> void:
	_view.set_objects_tinted(_selection.object_ids(), false)
	for layer_id in _selection.cells_by_layer().keys():
		_view.set_cells_tinted(str(layer_id), _selection.cells_by_layer()[str(layer_id)], false)

## 拖动提交：物件+格块整体位移一格增量，单命令可撤销（design.md §7 多选移动）
func _commit_move(delta_cell: Vector2i) -> void:
	var obj_entries := []
	for id in _selection.object_ids():
		var obj := _document.get_object(int(id))
		if obj.is_empty():
			continue
		var from: Vector2i = obj["cell"]
		obj_entries.append({"id": int(id), "from": from, "to": from + delta_cell})
	# 格块快照源（asset_id 随方块走）
	var cells_by_layer := _selection.cells_by_layer()
	var block := []
	for layer_id in cells_by_layer.keys():
		for c in (cells_by_layer[str(layer_id)] as Array):
			var entry := _document.get_tile(str(layer_id), c as Vector2i)
			if not entry.is_empty():
				block.append({"layer": str(layer_id), "cell": c as Vector2i, "asset_id": str(entry["asset_id"])})
	if obj_entries.is_empty() and block.is_empty():
		_view.resync_objects(_selection.object_ids())
		_view.resync_cells(cells_by_layer)
		return
	var do_move := func() -> void:
		for e in obj_entries:
			_document.update_object(int((e as Dictionary)["id"]), {"cell": (e as Dictionary)["to"]}, true)
		for b in block: # 块内重叠安全：先清全部源
			var src: Dictionary = b
			_document.erase_tile(str(src["layer"]), src["cell"] as Vector2i, true)
		for b in block: # 再写全部目标
			var dst: Dictionary = b
			_document.set_tile(str(dst["layer"]), (dst["cell"] as Vector2i) + delta_cell, str(dst["asset_id"]), true)
	var undo_move := func() -> void:
		for b in block: # 反向：清目标
			var cl: Dictionary = b
			_document.erase_tile(str(cl["layer"]), (cl["cell"] as Vector2i) + delta_cell, true)
		for b in block: # 还原源
			var rs: Dictionary = b
			_document.set_tile(str(rs["layer"]), rs["cell"] as Vector2i, str(rs["asset_id"]), true)
		for e in obj_entries:
			_document.update_object(int((e as Dictionary)["id"]), {"cell": (e as Dictionary)["from"]}, true)
	_commands.push("移动 %d 件 %d 格" % [obj_entries.size(), block.size()], do_move, undo_move)
	# 选区跟随到新位置
	var new_cells := {}
	for b in block:
		var sel_c: Dictionary = b
		var layer_key := str(sel_c["layer"])
		if not new_cells.has(layer_key):
			new_cells[layer_key] = []
		(new_cells[layer_key] as Array).append((sel_c["cell"] as Vector2i) + delta_cell)
	_apply_selection(_selection.object_ids(), new_cells)

## 复制选中内容（物件快照 + 方块快照）
func _copy_selected() -> void:
	_clipboard.clear()
	_clip_cells.clear()
	for id in _selection.object_ids():
		var obj := _document.get_object(int(id))
		if not obj.is_empty():
			_clipboard.append(obj.duplicate(true))
	for layer_id in _selection.cells_by_layer().keys():
		for c in _selection.cells_by_layer()[str(layer_id)]:
			var entry := _document.get_tile(str(layer_id), c as Vector2i)
			if not entry.is_empty():
				_clip_cells.append({"layer": str(layer_id), "cell": c, "asset_id": str(entry["asset_id"])})
	if _clipboard.is_empty() and _clip_cells.is_empty():
		print("[TileMason] 剪贴板为空（先在选择模式下框选内容）")
	else:
		print("[TileMason] 已复制 %d 件物件、%d 格" % [_clipboard.size(), _clip_cells.size()])

## 粘贴到鼠标位置：整组保持相对布局、左上角对齐鼠标格（§7 复制后自动吸附网格）
func _paste_clipboard() -> void:
	if _clipboard.is_empty() and _clip_cells.is_empty():
		print("[TileMason] 剪贴板为空（Ctrl+C 复制选中内容）")
		return
	var base := Vector2i(99999, 99999)
	for snap in _clipboard:
		var c: Vector2i = (snap as Dictionary)["cell"]
		base = Vector2i(mini(base.x, c.x), mini(base.y, c.y))
	for e in _clip_cells:
		var c2: Vector2i = (e as Dictionary)["cell"]
		base = Vector2i(mini(base.x, c2.x), mini(base.y, c2.y))
	var delta := mouse_cell() - base
	var ctx := {}
	var do_paste := func() -> void:
		if not ctx.has("objs"):
			var created: Array = []
			for snap in _clipboard:
				var props := (snap as Dictionary).duplicate()
				props.erase("id")
				props["cell"] = (props["cell"] as Vector2i) + delta
				var new_id := _document.add_object(props)
				if new_id > 0:
					created.append(_document.get_object(new_id).duplicate(true))
			ctx["objs"] = created
		else:
			for o in ctx["objs"]:
				_document.insert_object(o as Dictionary, true) # 重做按原 id 复原
	var undo_paste := func() -> void:
		for o in ctx["objs"]:
			_document.remove_object(int((o as Dictionary)["id"]), true)
	# 方块：非强制写入（锁定层跳过），整段并入同一命令
	var cell_entries := []
	for e in _clip_cells:
		var ce: Dictionary = e
		var target := (ce["cell"] as Vector2i) + delta
		var old: Variant = _document.set_tile(str(ce["layer"]), target, str(ce["asset_id"]))
		if old != null:
			cell_entries.append({"layer": str(ce["layer"]), "cell": target, "old": old, "asset_id": str(ce["asset_id"])})
	var do_cells := func() -> void:
		for ce in cell_entries:
			var c: Dictionary = ce
			_document.set_tile(str(c["layer"]), c["cell"], str(c["asset_id"]), true)
	var undo_cells := func() -> void:
		for i in range(cell_entries.size() - 1, -1, -1):
			var ce: Dictionary = cell_entries[i]
			var prev: Dictionary = ce["old"]
			if prev.is_empty():
				_document.erase_tile(str(ce["layer"]), ce["cell"], true)
			else:
				_document.set_tile(str(ce["layer"]), ce["cell"], str(prev["asset_id"]), true)
	var do_all := func() -> void:
		do_paste.call()
		do_cells.call()
	var undo_all := func() -> void:
		undo_cells.call()
		undo_paste.call()
	_commands.push("粘贴 %d 件 %d 格" % [_clipboard.size(), cell_entries.size()], do_all, undo_all)
	# 粘贴后选中新物件，便于连续移动
	var pasted: Array = ctx.get("objs", [])
	if not pasted.is_empty():
		var new_ids := []
		for o in pasted:
			new_ids.append(int((o as Dictionary)["id"]))
		if not _select_mode:
			_toggle_select_mode()
		_apply_selection(new_ids)

## 删除选中内容（物件+格，单命令可撤销；锁定层内容拒绝删除——修复此前 force 旁路锁定）
func _delete_selected() -> void:
	if _selection.is_empty():
		return
	var snapshots := []
	for id in _selection.object_ids():
		var removed: Variant = _document.remove_object(int(id)) # 非强制：锁定层拒删
		if removed is Dictionary and not (removed as Dictionary).is_empty():
			snapshots.append(removed)
	var cell_entries := []
	for layer_id in _selection.cells_by_layer().keys():
		for c in _selection.cells_by_layer()[str(layer_id)]:
			var old: Variant = _document.erase_tile(str(layer_id), c as Vector2i) # 非强制
			if old != null:
				cell_entries.append({"layer": str(layer_id), "cell": c, "old": old})
	if snapshots.is_empty() and cell_entries.is_empty():
		return
	var ids := []
	for snap in snapshots:
		ids.append(int((snap as Dictionary)["id"]))
	var do_del := func() -> void:
		for id in ids:
			_document.remove_object(int(id), true)
		for e in cell_entries:
			_document.erase_tile(str((e as Dictionary)["layer"]), (e as Dictionary)["cell"] as Vector2i, true)
	var undo_del := func() -> void:
		for snap in snapshots:
			_document.insert_object(snap as Dictionary, true)
		for i in range(cell_entries.size() - 1, -1, -1):
			var e: Dictionary = cell_entries[i]
			var prev: Dictionary = e["old"]
			if not prev.is_empty():
				_document.set_tile(str(e["layer"]), e["cell"] as Vector2i, str(prev["asset_id"]), true)
	_commands.push("删除 %d 件 %d 格" % [snapshots.size(), cell_entries.size()], do_del, undo_del)
	_apply_selection([])

## ---- 直线工具（design.md §2.2：两点画线，整段单命令）----

func _toggle_line_mode() -> void:
	if _line_mode:
		_exit_line_mode()
		return
	if _selected_asset_id.is_empty() or not AssetLibrary.TILE_CATEGORIES.has(str(_library.get_asset(_selected_asset_id).get("category", ""))):
		print("[TileMason] 直线工具需要先选中规则方块类素材")
		return
	_line_mode = true
	_line_armed = false
	print("[TileMason] 直线工具：点起点，再点终点画线（L/Esc 退出）")
	refresh_status()

func _exit_line_mode() -> void:
	if not _line_mode:
		return
	_line_mode = false
	_line_armed = false
	_clear_line_preview()
	print("[TileMason] 直线工具关闭")
	refresh_status()

func _line_click(cell: Vector2i) -> void:
	if _mouse_over_panel():
		return
	if not _line_armed:
		_line_armed = true
		_line_start = cell
		_rebuild_line_preview(cell)
		refresh_status()
		return
	# 第二击：落线
	var asset := _library.get_asset(_selected_asset_id)
	if asset.is_empty():
		_exit_line_mode()
		return
	var layer_id: String = CATEGORY_TO_LAYER.get(str(asset["category"]), "ground")
	var entries := []
	for c in MapDocument.line_cells(_line_start, cell):
		var prev: Variant = _document.set_tile(layer_id, c, str(asset["id"]))
		if prev != null:
			entries.append({"cell": c, "old": prev})
	_line_armed = false
	_clear_line_preview()
	refresh_status()
	if entries.is_empty():
		return
	var extras := {}
	for e in entries:
		_harvest_refresh(layer_id, (e as Dictionary)["cell"], extras)
	_push_tile_command("直线 %d 格" % entries.size(), layer_id, entries, extras, str(asset["id"]))

## 直线预览：沿线格铺半透明 Sprite（35% 透明度）
func _rebuild_line_preview(to_cell: Vector2i) -> void:
	_clear_line_preview()
	if _selected_asset_id.is_empty():
		return
	var tex := _library.load_texture(_selected_asset_id)
	if tex == null:
		return
	var asset := _library.get_asset(_selected_asset_id)
	var layer_id: String = CATEGORY_TO_LAYER.get(str(asset.get("category", "")), "ground")
	if _document.is_layer_locked(layer_id):
		return
	for c in MapDocument.line_cells(_line_start, to_cell):
		if _line_sprites.size() >= 512: # 超长线保护
			break
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.modulate.a = 0.35
		s.position = Vector2(c) * DEFAULT_GRID
		s.z_index = 60
		add_child(s)
		_line_sprites.append(s)

func _clear_line_preview() -> void:
	for s in _line_sprites:
		(s as Node2D).queue_free()
	_line_sprites.clear()

## 水平镜像选中物件（design.md §7 镜像；mirror_h 记录翻转，保留原素材方向 §3.3）
func _mirror_selected() -> void:
	if _selection.is_empty():
		return
	var entries := []
	for id in _selection.object_ids():
		var obj := _document.get_object(int(id))
		if obj.is_empty():
			continue
		entries.append({"id": int(id), "from": bool(obj["mirror_h"]), "to": not bool(obj["mirror_h"])})
	if entries.is_empty():
		return
	var do_mirror := func() -> void:
		for e in entries:
			_document.update_object(int((e as Dictionary)["id"]), {"mirror_h": (e as Dictionary)["to"]}, true)
	var undo_mirror := func() -> void:
		for e in entries:
			_document.update_object(int((e as Dictionary)["id"]), {"mirror_h": (e as Dictionary)["from"]}, true)
	_commands.push("镜像 %d 件" % entries.size(), do_mirror, undo_mirror)

## Ctrl+A 全选（选择模式下：全部物件 + 全部非空方块格）
func _select_all() -> void:
	if not _select_mode:
		_toggle_select_mode()
	var ids := []
	for obj in _document.get_objects():
		ids.append(int((obj as Dictionary)["id"]))
	var cells := {}
	for layer in _document.get_layers():
		var layer_id := str((layer as Dictionary)["id"])
		if str((layer as Dictionary)["type"]) == "tile":
			var coords: Array = _document.get_tile_coords(layer_id)
			if not coords.is_empty():
				cells[layer_id] = coords
	_apply_selection(ids, cells)

## 导出地图（design.md §10/P4）：Ctrl+E 场景导出（形态A）+ JSON 导出
func _export_map() -> void:
	var result: Dictionary = SceneExporter.export_scene(_document, _library)
	for w in result.get("warnings", []):
		print("[TileMason] [导出] %s" % str(w))
	if not result.get("ok", false):
		print("[TileMason] 场景导出失败：%s" % str(result.get("warnings", "")))
		return
	var json_path := _current_map_path.get_basename() + ".export.json"
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(_document.to_dict(), "	"))
		jf = null
	print("[TileMason] 导出完成：场景 %s（%d 方块 %d 物件）｜ JSON %s" % [
		ProjectSettings.globalize_path(str(result["path"])), int(result["tiles"]), int(result["props"]), json_path])

## 选中内容存为预制件（design.md §7）：相对化快照落盘并设为当前
func _save_prefab_from_selection() -> void:
	if _selection.is_empty():
		print("[TileMason] 预制件：先在选择模式下框选内容（S）")
		return
	var snapshot := Prefab.build_snapshot(_document, _selection.object_ids(), _selection.cells_by_layer())
	if snapshot.is_empty():
		print("[TileMason] 预制件：选区没有可保存的内容")
		return
	var name := "预制件%d" % (Prefab.list_names().size() + 1)
	var path := Prefab.save_prefab(name, snapshot)
	if path.is_empty():
		print("[TileMason] 预制件保存失败")
		return
	_current_prefab = name
	var f := FileAccess.open("user://prefab_current.json", FileAccess.WRITE)
	if f != null:
		f.store_string(name)
	_prefab_panel.refresh(_current_prefab)
	print("[TileMason] 已存预制件「%s」：%d 方块 %d 物件（P 键放置到鼠标处）" % [name, (snapshot["tiles"] as Array).size(), (snapshot["objects"] as Array).size()])

## T 键：进入标签输入模式（对当前选中素材；状态栏即输入行）
func _begin_tag_input() -> void:
	if _selected_asset_id.is_empty():
		print("[TileMason] 标签：先选中一个素材（右侧面板/快捷栏/吸管）")
		return
	_tag_input_mode = true
	var current: Array = _tags.get(_selected_asset_id, [])
	_tag_input_text = "，".join(PackedStringArray(current))
	refresh_tag_input()

func refresh_tag_input() -> void:
	_status.set_line("标签（%s）：%s ｜ Enter 保存 · Esc 取消 · 退格删字（逗号/空格分隔多个）" % [_library.get_asset(_selected_asset_id).get("name", ""), _tag_input_text])

func _commit_tag_input() -> void:
	var parsed := TagStore.parse_input(_tag_input_text)
	_tags = TagStore.set_tags(_tags, _selected_asset_id, parsed)
	TagStore.save_all(_tags)
	_panel.set_tags(TagStore.reverse_index(_tags))
	_exit_tag_input()
	print("[TileMason] 已保存标签：%s → %s" % [_selected_asset_id, str(parsed)])

func _exit_tag_input() -> void:
	_tag_input_mode = false
	_tag_input_text = ""
	refresh_status()

## 面板选用预制件为当前件
func _choose_prefab(name: String) -> void:
	_current_prefab = name
	var f := FileAccess.open("user://prefab_current.json", FileAccess.WRITE)
	if f != null:
		f.store_string(name)
	_prefab_panel.refresh(name)
	print("[TileMason] 当前预制件：「%s」（P 放置）" % name)

## 面板删除预制件
func _delete_prefab(name: String) -> void:
	var dir := DirAccess.open(Prefab.PREFAB_DIR)
	if dir != null:
		dir.remove(name + ".json")
	if _current_prefab == name:
		_current_prefab = ""
		var f := FileAccess.open("user://prefab_current.json", FileAccess.WRITE)
		if f != null:
			f.store_string("")
	_prefab_panel.refresh(_current_prefab)
	print("[TileMason] 已删除预制件「%s」" % name)

## 放置当前预制件：整组落到鼠标格（左上角对齐），单命令可撤销（复用粘贴模式）
func _place_current_prefab() -> void:
	if _current_prefab.is_empty():
		var names := Prefab.list_names()
		if names.is_empty():
			print("[TileMason] 预制件：还没有保存过（选择内容后 Ctrl+P）")
		else:
			print("[TileMason] 预制件：未选定当前件。已存：%s（重按 Ctrl+P 覆盖更新同名件）" % "、".join(PackedStringArray(names)))
		return
	var snap := Prefab.load_prefab(_current_prefab)
	if snap.is_empty():
		print("[TileMason] 预制件「%s」读取失败" % _current_prefab)
		return
	var base := mouse_cell()
	var tile_entries := []
	var obj_entries := []
	for t in snap.get("tiles", []):
		var te: Dictionary = t
		var cell := base + Vector2i(int(te["cell"][0]), int(te["cell"][1]))
		var old: Variant = _document.set_tile(str(te["layer"]), cell, str(te["asset_id"]))
		if old != null:
			tile_entries.append({"layer": str(te["layer"]), "cell": cell, "old": old, "asset_id": str(te["asset_id"])})
	for o in snap.get("objects", []):
		var oe: Dictionary = o
		var props := oe.duplicate(true)
		props["cell"] = base + Vector2i(int(oe["cell"][0]), int(oe["cell"][1]))
		var new_id := _document.add_object(props)
		if new_id > 0:
			obj_entries.append(_document.get_object(new_id).duplicate(true))
	if tile_entries.is_empty() and obj_entries.is_empty():
		return
	var do_place := func() -> void:
		for te in tile_entries:
			var t2: Dictionary = te
			_document.set_tile(str(t2["layer"]), t2["cell"] as Vector2i, str(t2["asset_id"]), true)
		for oe in obj_entries:
			_document.insert_object(oe as Dictionary, true)
	var undo_place := func() -> void:
		for oe in obj_entries:
			_document.remove_object(int((oe as Dictionary)["id"]), true)
		for i in range(tile_entries.size() - 1, -1, -1):
			var t2: Dictionary = tile_entries[i]
			var prev: Dictionary = t2["old"]
			if prev.is_empty():
				_document.erase_tile(str(t2["layer"]), t2["cell"] as Vector2i, true)
			else:
				_document.set_tile(str(t2["layer"]), t2["cell"] as Vector2i, str(prev["asset_id"]), true)
	_commands.push("放置预制件「%s」" % _current_prefab, do_place, undo_place)
	print("[TileMason] 已放置预制件「%s」：%d 方块 %d 物件" % [_current_prefab, tile_entries.size(), obj_entries.size()])

## 批量替换素材（design.md §3/P3）：鼠标所指素材全图替换为当前选中素材
## 鼠标指到什么（吸管同款取法）就把全图同款换掉——tile 与物件分别处理，单命令可撤销
func _batch_replace_under_mouse() -> void:
	if _selected_asset_id.is_empty() or _mouse_over_panel():
		return
	var target_asset := _library.get_asset(_selected_asset_id)
	if target_asset.is_empty():
		return
	var from_id := _view.pick_asset_id_at(mouse_cell())
	if from_id.is_empty() or from_id == _selected_asset_id:
		print("[TileMason] 批量替换：鼠标下没有可替换的素材（或与选中相同）")
		return
	var replaced: Dictionary = _document.replace_asset(from_id, _selected_asset_id)
	var tiles: Array = replaced["tile_entries"]
	var objects: Array = replaced["object_entries"]
	if tiles.is_empty() and objects.is_empty():
		print("[TileMason] 批量替换：地图中没有该素材")
		return
	# 自动连接刷新（撤销/重放后同样刷新，保证变体与内容一致）
	var refresh := func() -> void:
		for e in tiles:
			AutoConnect.refresh_around(_document, _library, str((e as Dictionary)["layer"]), (e as Dictionary)["cell"] as Vector2i)
	var do_rep := func() -> void:
		for e in tiles:
			var ee: Dictionary = e
			_document.set_tile(str(ee["layer"]), ee["cell"] as Vector2i, _selected_asset_id, true)
		for o in objects:
			_document.update_object(int((o as Dictionary)["id"]), {"asset_id": _selected_asset_id}, true)
		refresh.call()
	var undo_rep := func() -> void:
		for o in objects:
			_document.update_object(int((o as Dictionary)["id"]), {"asset_id": str((o as Dictionary)["old_asset_id"])}, true)
		for i in range(tiles.size() - 1, -1, -1):
			var ee: Dictionary = tiles[i]
			var prev: Dictionary = ee["old"]
			if prev.is_empty():
				_document.erase_tile(str(ee["layer"]), ee["cell"] as Vector2i, true)
			else:
				_document.set_tile(str(ee["layer"]), ee["cell"] as Vector2i, str(prev["asset_id"]), true)
		refresh.call()
	var from_name := from_id
	var fa := _library.get_asset(from_id)
	if not fa.is_empty():
		from_name = str(fa["name"])
	_commands.push("批量替换 %s → %s（%d 方块 %d 物件）" % [from_name, target_asset["name"], tiles.size(), objects.size()], do_rep, undo_rep)
	print("[TileMason] 批量替换完成：%s → %s（%d 方块、%d 物件，Ctrl+Z 可撤销）" % [from_name, target_asset["name"], tiles.size(), objects.size()])

## 聚焦：相机跳到选中内容中心（无选中则到鼠标格；§6.3 聚焦选中对象）
func _focus_selection() -> void:
	var target := Vector2(mouse_cell()) * DEFAULT_GRID + Vector2.ONE * DEFAULT_GRID / 2.0
	if not _selection.is_empty():
		var sum := Vector2.ZERO
		var n := 0
		for id in _selection.object_ids():
			var obj := _document.get_object(int(id))
			if not obj.is_empty():
				sum += MapView.object_sprite_position(obj["cell"], Vector2i.ONE, DEFAULT_GRID, DEFAULT_GRID)
				n += 1
		for layer_id in _selection.cells_by_layer().keys():
			for c in _selection.cells_by_layer()[str(layer_id)]:
				sum += (Vector2(c as Vector2i) + Vector2.ONE * 0.5) * DEFAULT_GRID
				n += 1
		if n > 0:
			target = sum / n
	get_viewport().get_camera_2d().position = target
	print("[TileMason] 已聚焦到 %s" % str(target))

## 最近使用：新选中排最前、去重、最多 10 件，落盘并刷新面板
func _push_recent(asset_id: String) -> void:
	_recent.erase(asset_id)
	_recent.push_front(asset_id)
	if _recent.size() > 10:
		_recent.resize(10)
	_save_id_list(RECENT_PATH, _recent)
	_panel.set_recent(_recent)

## F 键收藏/取消收藏当前选中素材
func _toggle_favorite() -> void:
	if _selected_asset_id.is_empty():
		return
	if _favorites.has(_selected_asset_id):
		_favorites.erase(_selected_asset_id)
		print("[TileMason] 已取消收藏")
	else:
		_favorites.push_back(_selected_asset_id)
		print("[TileMason] 已加入收藏")
	_save_id_list(FAVORITES_PATH, _favorites)
	_panel.set_favorites(_favorites)

## 简易 id 清单持久化（JSON 数组）
func _load_id_list(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Array).duplicate() if parsed is Array else []

func _save_id_list(path: String, ids: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ids, "	"))
		f = null

## 底部快捷栏（design.md §6.2）：居中悬于状态栏上方
func _build_hotbar() -> void:
	var layer_ui := CanvasLayer.new()
	layer_ui.layer = 10
	add_child(layer_ui)
	_hotbar = Hotbar.new()
	_hotbar.setup(_library, HOTBAR_DEFAULT)
	_hotbar.slot_activated.connect(_hotbar_activate)
	layer_ui.add_child(_hotbar)
	_hotbar.anchor_left = 0.5
	_hotbar.anchor_right = 0.5
	_hotbar.anchor_top = 1.0
	_hotbar.anchor_bottom = 1.0
	_hotbar.offset_left = -250
	_hotbar.offset_right = 250
	_hotbar.offset_top = -84
	_hotbar.offset_bottom = -30

## 槽位激活：1-7 选素材、8 橡皮擦、9 吸管提示
func _hotbar_activate(index: int) -> void:
	match index:
		7:
			_toggle_eraser()
		8:
			print("[TileMason] 吸管：在画布上直接右键即可吸取素材")
		_:
			var asset_id := _hotbar.binding_asset_id(index)
			if asset_id.is_empty():
				return
			_panel.select_asset(asset_id) # 走面板选中链路（信号回写选中+状态栏）

## 油漆桶（design.md §2.2 油漆桶填充）：连通同素材区域整体替换，整段单命令
func _toggle_bucket_mode() -> void:
	_bucket_mode = not _bucket_mode
	print("[TileMason] 油漆桶模式：%s" % ("开（左键点击填充连通区域）" if _bucket_mode else "关"))
	refresh_status()

func _do_bucket_fill(cell: Vector2i) -> void:
	if _selected_asset_id.is_empty() or _mouse_over_panel():
		return
	var asset := _library.get_asset(_selected_asset_id)
	if asset.is_empty() or not AssetLibrary.TILE_CATEGORIES.has(str(asset["category"])):
		return
	var layer_id: String = CATEGORY_TO_LAYER.get(str(asset["category"]), "ground")
	var entries: Array = _document.flood_fill(layer_id, cell, str(asset["id"]))
	if entries.is_empty():
		return
	var extras := {}
	for e in entries:
		_harvest_refresh(layer_id, (e as Dictionary)["cell"], extras)
	_push_tile_command("油漆桶 %d 格" % entries.size(), layer_id, entries, extras, str(asset["id"]))

## 收集自动连接刷新变更（同格多次刷新保留最初旧值、最新新值）
func _harvest_refresh(layer_id: String, cell: Vector2i, store: Dictionary) -> void:
	if _document.is_layer_locked(layer_id):
		return
	for rc in AutoConnect.refresh_around(_document, _library, layer_id, cell):
		var c: Dictionary = rc
		var key: Vector2i = c["cell"]
		if store.has(key):
			(store[key] as Dictionary)["new_asset_id"] = str(c["new_asset_id"])
		else:
			store[key] = {"cell": key, "old_asset_id": str(c["old_asset_id"]), "new_asset_id": str(c["new_asset_id"])}

## 统一构造方块类命令：base=直接编辑格 [{cell, old}]，extras=自动连接变更格
## painted_asset 为空串＝擦除语义（重放清格），否则重放写该素材；extras 的 new 优先（变体覆盖）
## 撤销按合并前的最初旧值整段还原，重放按最终新值整段恢复——变体切换天然可撤销
func _push_tile_command(cmd_name: String, layer_id: String, base: Array, extras: Dictionary, painted_asset: String) -> void:
	if base.is_empty() and extras.is_empty():
		return
	var entries: Array = AutoConnect.merge_tile_changes(base, extras, painted_asset)
	var do_cmd := func() -> void:
		for e in entries:
			var ee: Dictionary = e
			if ee["new"] == null:
				_document.erase_tile(layer_id, ee["cell"] as Vector2i, true)
			else:
				_document.set_tile(layer_id, ee["cell"] as Vector2i, str(ee["new"]), true)
	var undo_cmd := func() -> void:
		for i in range(entries.size() - 1, -1, -1):
			var ee: Dictionary = entries[i]
			var prev: Dictionary = ee["old"]
			if prev.is_empty():
				_document.erase_tile(layer_id, ee["cell"] as Vector2i, true)
			else:
				_document.set_tile(layer_id, ee["cell"] as Vector2i, str(prev["asset_id"]), true)
	_commands.push(cmd_name, do_cmd, undo_cmd)

func _toggle_eraser() -> void:
	_eraser_mode = not _eraser_mode
	print("[TileMason] 橡皮擦模式：%s" % ("开（左键/右键/拖动清除当前层，E 关闭）" if _eraser_mode else "关"))
	refresh_status()

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
	_harvest_refresh(_erase_layer, cell, _erase_extra)
	_last_cell = cell

func _end_erase() -> void:
	_last_cell = Vector2i(99999, 99999)
	if not _erasing:
		return
	_erasing = false
	if _erase_cells.is_empty():
		return
	_push_tile_command("擦除 %d 格" % _erase_cells.size(), _erase_layer, _erase_cells, _erase_extra, "")

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
		if Input.is_key_pressed(KEY_SHIFT):
			_place_asset(asset, cell) # Shift：临时单块放置，不进入拖刷笔画（design.md §6.3）
			return
		# 方块笔画：按下起笔、拖动连刷、抬手合成一个命令（区域操作整段撤销的地基）
		var layer_id: String = CATEGORY_TO_LAYER.get(str(asset["category"]), "ground")
		if _document.is_layer_locked(layer_id):
			print("[TileMason] 图层已锁定，无法放置：%s" % layer_id)
			return
		_stroke_layer = layer_id
		_stroke_asset_id = _selected_asset_id
		_stroke_cells = []
		_stroke_extra = {}
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
	_harvest_refresh(_stroke_layer, cell, _stroke_extra)
	_last_cell = cell

## 抬手：把整段笔画合成一个命令压栈（undo 一次回滚整段，redo 整段重放）
func _end_paint() -> void:
	_last_cell = Vector2i(99999, 99999)
	if not _painting:
		return
	_painting = false
	if _stroke_cells.is_empty():
		return
	_push_tile_command("笔画 %d 格" % _stroke_cells.size(), _stroke_layer, _stroke_cells, _stroke_extra, _stroke_asset_id)

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
	var ctx := {} # 引用容器：do/undo 间共享旧值/新对象（dev-pitfalls 12）
	if AssetLibrary.TILE_CATEGORIES.has(category):
		var old: Variant = _document.set_tile(layer_id, cell, asset_id)
		if old == null:
			return # 层无效/锁定
		var entries := [{"cell": cell, "old": old}]
		var extras := {}
		_harvest_refresh(layer_id, cell, extras)
		_push_tile_command("放置 %s" % str(asset["name"]), layer_id, entries, extras, asset_id)
	else:
		var cells: Vector2i = asset["cells"]
		var cell_tl := MapView.footprint_cell_tl(cells, cell) # 底边中心对齐鼠标格（与预览同源）
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
		_layer_panel.offset_bottom = -224 # 给下方预制件面板让位
	_layer_panel.setup(_document)
	var pf_layer := CanvasLayer.new()
	pf_layer.layer = 10
	add_child(pf_layer)
	_prefab_panel = PrefabPanel.new()
	_prefab_panel.setup()
	_prefab_panel.prefab_chosen.connect(_choose_prefab)
	_prefab_panel.prefab_deleted.connect(_delete_prefab)
	pf_layer.add_child(_prefab_panel)
	_prefab_panel.anchor_left = 0.0
	_prefab_panel.anchor_right = 0.0
	_prefab_panel.anchor_top = 1.0
	_prefab_panel.anchor_bottom = 1.0
	_prefab_panel.offset_left = 0
	_prefab_panel.offset_right = 190
	_prefab_panel.offset_top = -220
	_prefab_panel.offset_bottom = -26 # 状态栏之上
	_prefab_panel.refresh(_current_prefab)

func _on_asset_selected(asset_id: String) -> void:
	_selected_asset_id = asset_id
	var asset := _library.get_asset(asset_id)
	if not asset.is_empty():
		print("[TileMason] 选中素材：%s（%s · %s）" % [asset["name"], asset_id, asset["category"]])
		_push_recent(asset_id)
	refresh_status()

## 底部状态栏：全宽停靠，常驻显示当前操作状态
func _build_status_bar() -> void:
	var layer_ui := CanvasLayer.new()
	layer_ui.layer = 10
	add_child(layer_ui)
	_status = StatusBar.new()
	_status.setup()
	layer_ui.add_child(_status)
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 0
	_status.offset_right = 0
	_status.offset_top = -26
	_status.offset_bottom = 0

## 汇总当前状态刷到状态栏（任何工具/素材变化后调用）
func refresh_status() -> void:
	if _status == null:
		return
	var tool := "画笔（左键放置/拖刷，Shift 单块）"
	if _bucket_mode:
		tool = "油漆桶（左键填充连通同素材区域，G 退出）"
	if _eraser_mode:
		tool = "橡皮擦（清「%s」层，左键/拖动/E 退出）" % _eraser_layer_name()
	elif _select_mode:
		tool = "选择（拖框选 · 拖动移动 · Ctrl+C/V 复制粘贴 · H 镜像 · Del 删除）"
	elif _line_mode:
		tool = "直线（%s，L/Esc 退出）" % ("已定起点，点终点" if _line_armed else "点起点")
	var asset_text := "未选（右侧面板点素材）"
	if not _selected_asset_id.is_empty():
		var asset := _library.get_asset(_selected_asset_id)
		if not asset.is_empty():
			# 显示放置目标图层与锁定警示（用户验收反馈：需要知道操作会作用在哪）
			var layer_id: String = CATEGORY_TO_LAYER.get(str(asset["category"]), "deco")
			var layer := _document.get_layer(layer_id)
			var layer_name := str(layer.get("name", layer_id)) if not layer.is_empty() else layer_id
			var lock_hint := "（该层已锁定，放置会被拒绝）" if _document.is_layer_locked(layer_id) else ""
			asset_text = "%s → 落在「%s」%s" % [asset["name"], layer_name, lock_hint]
	var file_name := _current_map_path.get_file()
	var pos_text := "(%d,%d)" % [mouse_cell().x, mouse_cell().y]
	_status.set_line("坐标：%s ｜ 工具：%s ｜ 素材：%s ｜ 文件：%s ｜ S 选择 · E 橡皮 · L 直线 · G 油漆桶 · Ctrl+框 矩形 · Ctrl+Z/Y 撤销重做 · R 批量替换 · Ctrl+P 存预制件 · Ctrl+S 保存 · Ctrl+E 导出 · F9 检查 · F8 连接规则" % [pos_text, tool, asset_text, file_name])

## 图层属性变化影响素材落层提示（锁定警示），载入新文档后重连
func _connect_status_signals() -> void:
	if not _document.layer_changed.is_connected(_on_doc_layer_changed):
		_document.layer_changed.connect(_on_doc_layer_changed)

## 自动保存：90 秒一跳，有未保存变更才写自动档（design.md §10）
func _setup_autosave() -> void:
	_commands.changed.connect(func(_u: bool, _r: bool) -> void: _dirty = true)
	var timer := Timer.new()
	timer.wait_time = 90.0
	timer.autostart = true
	timer.timeout.connect(_auto_save)
	add_child(timer)

func _auto_save() -> void:
	if not _dirty:
		return
	if _document.save_to_file(AUTOSAVE_PATH):
		_dirty = false
		print("[TileMason] 自动保存：%s" % AUTOSAVE_PATH)

func _on_doc_layer_changed(_layer_id: String, _key: String) -> void:
	refresh_status()

func _eraser_layer_name() -> String:
	var layer := _document.get_layer(_eraser_layer())
	if layer.is_empty():
		return _eraser_layer()
	return str(layer["name"])

## 视觉取证用：文档为空时程序化摆样（一条道路+草地+建筑+树），延时截屏存盘后退出
## 须窗口模式运行，headless 无渲染
func _capture_screenshot() -> void:
	_demo_place_for_screenshot()
	# 选中建筑并把鼠标移到画布空位：截图中展示半透明放置预览
	# 走面板选中链路（同步产生「最近使用」记录）
	_panel.select_asset("demo/props/house.png")
	get_viewport().warp_mouse(Vector2(150, 330))
	# 确定性取证：warp 在后台窗口下不稳定，固定画一个范围框（世界 256,256 起占 6×6 格）
	_footprint_demo_lock = true
	_footprint_preview.set_rect_px(Rect2(256, 256, 96, 96))
	_footprint_preview.visible = true
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_editor.png")
	_save_map() # 顺带落盘：下轮截图/冒烟验证「保存→重开→仍可编辑」链路
	print("[TileMason] 截图：%s" % ProjectSettings.globalize_path("user://screenshot_editor.png"))
	get_tree().quit(0)

func _demo_place_for_screenshot() -> void:
	if _document.has_content():
		print("[TileMason] [取证] 文档已有内容，跳过摆样（截图像素断言将不成立——取证须在空文档/隔离用户数据目录下运行）")
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
	# L 形道路（全部用直线素材摆放，自动连接应把拐角变弯道、端头变端头变体）
	for x in range(-3, 1):
		_place_asset(_demo_asset("tiles/road_h.png"), Vector2i(x, 4))
	for y in range(5, 8):
		_place_asset(_demo_asset("tiles/road_h.png"), Vector2i(0, y))
	# 墙体一列 + 摊位（demo 扩充素材）
	for x in range(-10, -6):
		_place_asset(_demo_asset("tiles/wall_brick.png"), Vector2i(x, 2))
	_place_asset(_demo_asset("props/stall_red.png"), Vector2i(7, 3))
	print("[TileMason] 截图摆样完成：道路×5、草地×2、建筑×1、树×1、砖墙×4、摊位×1")

func _demo_asset(file: String) -> Dictionary:
	return _library.get_asset("demo/" + file)
