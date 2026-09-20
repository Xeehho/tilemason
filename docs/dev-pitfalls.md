# Godot 4.6 开发陷阱手册

来源：《江湖志》主仓（C:\Learn\my-godot-project）实战踩坑沉淀 + 直拼管线探针结论 + TileMason CI/CD 落地，2026-09-20 整理。改对应模块前先扫对应章节。

## 一、GDScript 语法与运行时

1. **const 字面量推断 StringName**：`const A := "x"` 的类型是 StringName 而非 String，做字典键或跨类型比较时踩坑。需要 String 时显式 `const A: String = "x"`。
2. **Dictionary 布尔判断**：不要用 `bool(dict)` 语义判存在/判空混用；判空用 `is_empty()`。
3. **Array.count 只收值不收谓词**：`arr.count(x)` 统计等于 x 的个数；按条件计数用 `filter().size()` 或循环，传函数进去不会被当谓词调用。
4. **无帧推进时 process_frames 恒 0**：`--headless --script` 的纯 SceneTree 模式里 `await process_frame` 永不返回（永挂）。需要帧推进就用带 `_process()` 的自定义 MainLoop 探针。
5. **quit() 在首轮迭代末才生效**：主场景总会先 boot；"启动即退出"的探针要等就绪后再 quit 并检查退出码。
6. **`_init` 期挂 root 卡死**：SceneTree 脚本在 `_init` 阶段把节点挂到 root 不会入树；正确姿势 `_initialize()` 建树 + `_process()` 首帧断言。
7. **JSON.parse_string 数字全是 float**：整数字面量也解析为 float；`==` 对 Array/Dictionary 是非递归比较（嵌套内容不等价判真），深比较逐层或比序列化。
8. **Dictionary.merged 默认不覆盖**：`a.merged(b)` 的 `overwrite` 默认 false，b 中与 a 重名的键被静默丢弃；打补丁语义必须显式 `a.merged(b, true)`（TileMason update_object 探针实测踩中）。

## 二、对象与信号

9. **内联 RefCounted 即建即释**：临时创建的 RefCounted 实例在所在表达式结束后立即释放，之后再取的引用悬空；需要存活就存进成员变量。
10. **Callable(self, "method") 不可靠场景**：目标方法来自动态添加或内联对象时失效；绑定回调用方法引用 `self._on_x` 或 `Signal.connect`。
11. **lambda 按值捕获**：闭包捕获的是变量拷贝；循环里挂延迟回调把循环变量显式传参。
12. **双重 free 堆损坏**：同一节点两次释放（free+queue_free、手动+自动）→ 进程以 0xC0000374 崩溃；删除统一走一次 `queue_free()`。
13. **RefCounted 环引用整图泄漏**：互相持有的引用链没有 GC；跨对象双向关系用 WeakRef 或显式断开。

## 三、TileMap / 场景 / 资源

14. **TileSet 先 add_source 再写 TileData**：source 未加入 TileSet 前，TileData 感知不到物理层（`physics.size()=0`），碰撞多边形写入会**静默失败**。
15. **y_sort_origin 设在 TileData 上**，不是 TileSet 属性。
16. **scene tile 实例化非同步**：`set_cell` 当帧子节点不可见/查不到，须隔帧断言；运行时逻辑引用实例同理（call_deferred / 等一帧）。
17. **scene tile id 不假设为 0**：用 `get_scene_tile_id(idx)` 动态取。
18. **PackedScene.pack 前子节点必须 `owner = root`**：漏设会打包出空壳场景。
19. **ResourceSaver 内嵌内存资源**：把内存中的 PackedScene 注册进 TileSet/场景，会被内嵌成 sub_resource 副本（改单件不生效、体积膨胀、列表显示内部名）；先 `save()` 落盘再 `load()` 回来注册。
20. **运行时生成的 PNG 无 import 数据**：`load()` / `ResourceLoader.exists()` 失败（资源隐形）；加载统一走 `Image.load_from_file`（**静态方法，须传绝对路径，返回 Image、失败返回 null**，不是实例方法返回错误码）+ 内存缓存，存在性用 `FileAccess.file_exists`。
21. **形态A配方（探针全过，直接抄）**：`SortRoot(y_sort_enabled)` → `GroundLayer(z=-10, atlas tiles)` + `PropsLayer(y_sort_enabled, scenes collection)`；件场景根原点=底边中心、Sprite `offset=-h/2`、`StaticBody2D` 碰撞=底边脚印（宽×min(件高,格高)）；嵌套 y-sort 与层外角色互遮挡经像素级验证正确。16px 地面与 48px 件需两个 TileMapLayer（tile_size 是 TileSet 全局属性）。

## 四、导出与 CI

22. **--check-only 必须带 --script**：`--headless --check-only --script res://path.gd` 才会真正解析脚本。
23. **macOS universal 导出双要求**：项目设置 `rendering/textures/vram_compression/import_etc2_astc=true`（预设里 texture_format 开关不够用）+ 预设选项 `application/bundle_identifier`（键名没有 `export/` 前缀）。
24. **新克隆/worktree 三步**：`--import` 重建 `.godot` 类缓存（class_name 解析必需）；新 `.gd` 首跑生成 `.uid` 随提交；缺缓存时脚本报"类不存在"多为缓存未建。
25. **project.godot 换行纪律**：仓库 `.gitattributes` 已强制 LF；任何工具化读写注入前先做字节快照校验，防止静默改换行。
