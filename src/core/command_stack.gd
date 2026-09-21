class_name CommandStack
extends RefCounted
## 命令栈基础：撤销/重做地基（design.md §6.3 Ctrl+Z / Ctrl+Y）
## 命令 = {name, do, undo} 一对 Callable；push 立即执行 do，撤销/重做由栈驱动
## 注意（dev-pitfalls 12）：Callable 捕获本地变量是值拷贝，
## do/undo 之间共享状态必须用 Dictionary/Array 等引用容器传递

signal changed(can_undo: bool, can_redo: bool)

var history_limit := 128 ## 撤销历史上限，超出丢弃最旧

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

func push(cmd_name: String, do_cb: Callable, undo_cb: Callable) -> void:
	## 压入并立即执行；任何新编辑都会清空重做栈
	do_cb.call()
	_undo_stack.append({"name": cmd_name, "do": do_cb, "undo": undo_cb})
	if _undo_stack.size() > history_limit:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_emit_changed()

func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var cmd: Dictionary = _undo_stack.pop_back()
	(cmd["undo"] as Callable).call()
	_redo_stack.append(cmd)
	_emit_changed()
	return true

func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var cmd: Dictionary = _redo_stack.pop_back()
	(cmd["do"] as Callable).call()
	_undo_stack.append(cmd)
	_emit_changed()
	return true

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func undo_count() -> int:
	return _undo_stack.size()

func redo_count() -> int:
	return _redo_stack.size()

func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_emit_changed()

func _emit_changed() -> void:
	changed.emit(can_undo(), can_redo())
