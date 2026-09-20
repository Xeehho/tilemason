# AGENTS.md - TileMason 开发指南

面向开发者和 AI 辅助工具的项目约定。首次会话请完整读完本文与 [docs/design.md](docs/design.md)、[docs/dev-pitfalls.md](docs/dev-pitfalls.md)。

## 项目定位与红线

- TileMason 是**独立桌面软件**（Godot 4.6 框架，成品为免安装单文件可执行程序）。最终用户是美术、策划、关卡设计——**不允许要求他们安装 Godot 或理解引擎概念**；面向用户的一切文案按"普通桌面软件"措辞，"Godot"字样只出现在开发者视角。
- 工具核心原则（design.md §13）：可编辑、可保存、可验证、可继续扩展。禁止把地图烘焙成不可编辑的图片。
- **AI 不自创拼法**：素材如何组合成建筑/街区由人类用户创作，AI 只做工具、管线和工程化辅助；禁止生成"示范布局"塞给用户。
- **素材红线**：第三方版权素材禁止入库（`assets/packs/` 已 gitignore）。
- **像素纪律**：画布显示缩放只允许整数倍 + 最近邻过滤；素材实际缩放默认 1:1（整数倍选项）；禁止默认任意旋转/任意缩放；独立物件用底边中心锚点，规则方块用左上角锚点。

## 代码规范

- GDScript，Godot 4.6 语法，Tab 缩进
- 函数/变量 `snake_case`，常量 `UPPER_SNAKE_CASE`，`class_name` 用 `PascalCase`
- 中文注释与日志，日志前缀 `[TileMason]`
- 场景文件（`.tscn`）保持精简（根+脚本引用），复杂节点运行时动态创建
- 运行时加载 PNG 用 `Image.load_from_file` + 内存缓存封装、存在性用 `FileAccess.file_exists`（新生成 PNG 无 import 数据，直接 `load()` 会失败）

## 验证（改动后必跑）

本机 Godot 4.6.2：`C:\迅雷下载\Godot_v4.6.2-stable_win64.exe`（贡献者自行安装 4.6+）：

```bash
GODOT=<godot可执行文件>
"$GODOT" --headless --path . --import                                # 导入/生成 .uid
"$GODOT" --headless --path . --check-only --script res://src/main.gd # 逐脚本解析（--check-only 必须带 --script）
"$GODOT" --headless --path . --quit-after 5                          # 冒烟启动
```

CI 在 push/PR 自动跑同样三道关。**禁止目测估框：改动效果必须实测**（探针脚本/截图/产物证据），逻辑自洽不等于跑得通；视觉问题须截图取证复验。

## 发布

- 打 tag 即发布：`git tag v0.1.0 && git push origin v0.1.0` → Release 机器人自动导出三平台免安装包
- 试构建（不发布）：Actions → Release → Run workflow
- macOS universal 导出依赖项目设置 `import_etc2_astc=true` 与预设 bundle identifier，勿删

## 引擎陷阱

改代码前先扫一遍 [docs/dev-pitfalls.md](docs/dev-pitfalls.md)（Godot 4.6 语法/对象/TileMap/导出四类 25 条），能避开绝大多数返工。

## 本地工作流（ZCode 会话 · 全自动无人值守）

- **自动提交与推送（用户 2026-09-20 授权）**：本仓库由定时任务无人值守开发。需求开发结束且验证三关通过、`.zcode/gameWork.md` 记录完毕后，AI **无须询问用户，直接自行 commit 并 push 到 main**；**唯一例外：打 tag 触发 Release 发布必须经用户确认，禁止静默 tag**
- **自主扩展（用户 2026-09-20 授权）**：总目标是收敛为「可完整交付的桌面工具」。design.md 未覆盖、但明确提升工具完整度/稳定性/易用性的改进（BUG、易用性、性能、测试补充、小功能），AI 自行评估、记入任务文件「自主扩展」节后开发，无须请示；**重大改动（产品方向、新增大型子系统、地图数据格式不兼容、引入外部依赖/付费服务、素材版权、修改验收标准）必须交用户决策**。「AI 不自创拼法」红线只约束内容创作（示范布局），不禁止工具功能扩展
- **交付纪律**：main 任何时点保持可导出可用成品；已有测试/探针每轮全量重跑，新功能尽量配可自动重跑的验证；每完成一个阶段（或每累计 5 轮）对照 design.md §12 验收标准走查一次（截图取证），达可发布状态时在任务文件标注并建议用户验收、打 tag
- **工具自足（用户 2026-09-20 授权）**：开发中需要 MCP/插件/skill 时，自行安装到 ZCode 使用，无须询问；来源限官方市场或可信开源项目，安装后在 `.zcode/gameWork.md` 记录名称与用途。仅当需要账号、API key、付费、客户端重启等必须用户配合的事项时，写入任务文件「待用户决策」等用户处理
- `.zcode/rules/`（本地文件，已 gitignore）：需求变更记录（`.zcode/gameWork.md`）/ 长任务交接（`.zcode/tasks/`）/ 开发完成自动保存提交——与主项目同款纪律
- 交接文件：长任务开工即建 `.zcode/tasks/<slug>.md`，续跑会话先读再动手
- commit 规范：类型前缀（feat/fix/docs/chore/refactor）保留英文；**标题与正文使用中文**，须写清「改了什么、为什么」，正文必要时分点展开，禁止一句话敷衍；AI 协作提交带 `Co-authored-by: GLM <noreply@z.ai>`；**push 前代码类改动必须已过验证三关**
