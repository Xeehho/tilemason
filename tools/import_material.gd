extends SceneTree
## [TileMason] 外部素材智能导入：扫 C:/Learn/material/scaled/<区域>/<板块>/*.png
## 自动建包 assets/packs/长安素材/（props/<区域>/<板块>/，pack.json 含 group 三层路径）
## 外层命名=抠图文件夹的父级文件夹名（区域名），如「东宫1/东宫核心建筑板」（用户约定）
## data/ 底稿目录跳过；文件拷贝（原素材不动）；重复运行覆盖更新
## 运行：godot --headless --path . --script res://tools/import_material.gd

const SRC_ROOT := "C:/Learn/material/scaled"
const PACK_DIR := "res://assets/packs/长安素材"
const DEFAULT_CATEGORY := "building" ## 长安素材以建筑/大型物件为主（底边中心锚），散件同路由到建筑层

func _init() -> void:
	print("[TileMason] 智能导入开始：%s" % SRC_ROOT)
	if not DirAccess.dir_exists_absolute(SRC_ROOT):
		print("[TileMason] 源目录不存在，退出")
		quit(1)
		return
	var assets := []
	var copied := 0
	var regions := 0
	var dir := DirAccess.open(SRC_ROOT)
	dir.list_dir_begin()
	var region := dir.get_next()
	while not region.is_empty():
		if dir.current_is_dir() and not region.begins_with("."):
			regions += 1
			copied += _import_region(str(region), assets)
		region = dir.get_next()
	dir.list_dir_end()
	# 写清单（group=区域/板块 三层路径；name=文件名去序号前缀）
	var f := FileAccess.open(PACK_DIR + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "长安素材", "assets": assets}, "\t"))
	f = null
	print("[TileMason] 智能导入完成：%d 区域、%d 件素材 → %s（点素材面板「⟳ 刷新」即可使用）" % [regions, copied, PACK_DIR])
	quit(0)

## 导入单个区域：遍历其下板块文件夹（=抠图文件夹），PNG 拷入包内并登记
func _import_region(region: String, assets: Array) -> int:
	var count := 0
	var rdir := DirAccess.open(SRC_ROOT + "/" + region)
	rdir.list_dir_begin()
	var board := rdir.get_next()
	while not board.is_empty():
		if rdir.current_is_dir() and not board.begins_with("."):
			var board_dir := SRC_ROOT + "/" + region + "/" + board
			var rel_dir := "props/" + region + "/" + board
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACK_DIR + "/" + rel_dir))
			var bdir := DirAccess.open(board_dir)
			bdir.list_dir_begin()
			var file := bdir.get_next()
			while not file.is_empty():
				if str(file).to_lower().ends_with(".png"):
					var dst := PACK_DIR + "/" + rel_dir + "/" + str(file)
					DirAccess.copy_absolute(board_dir + "/" + str(file), ProjectSettings.globalize_path(dst))
					var display := str(file).get_basename()
					var us := display.find("_")
					if us > 0 and display.left(us).is_valid_int(): # 去序号前缀「00_」
						display = display.substr(us + 1)
					assets.append({
						"file": rel_dir + "/" + str(file),
						"name": display,
						"category": DEFAULT_CATEGORY,
						"group": region + "/" + str(board), # 三层菜单路径（外层=父文件夹名=区域）
					})
					count += 1
				file = bdir.get_next()
			bdir.list_dir_end()
		board = rdir.get_next()
	rdir.list_dir_end()
	print("[TileMason] 区域「%s」：%d 件" % [region, count])
	return count
