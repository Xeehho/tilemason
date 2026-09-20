# 贡献指南

感谢关注 TileMason！

## 开发环境

1. 安装 Godot 4.6+ 标准版。
2. 克隆仓库并用 Godot 打开 `project.godot`。
3. F5 运行即可看到编辑器骨架。

## 代码规范

- GDScript，Godot 4.x 语法，**Tab 缩进**。
- 函数/变量 `snake_case`，常量 `UPPER_SNAKE_CASE`，类 `class_name PascalCase`。
- 场景文件（`.tscn`）保持精简，复杂节点在运行时动态创建。
- 中文注释与 `[TileMason]` 前缀日志。
- 像素纪律：显示缩放只允许整数倍 + 最近邻过滤；禁止默认任意旋转/任意缩放。

## 提交与 PR

- commit 信息用类型前缀：`feat:` / `fix:` / `docs:` / `chore:` / `refactor:`。
- 推送前本地自检：

  ```bash
  # 脚本解析检查（任一 .gd 改动后）
  godot --headless --path . --check-only --script src/main.gd
  ```

- PR 会自动跑 CI（导入 + 全脚本解析检查 + 冒烟启动），保持绿灯。

## 素材红线

- **禁止提交任何第三方版权素材**（图集、贴图、音效）。素材包放 `assets/packs/`（已 gitignore），各自版权各自保留。
- 仓库内示例素材必须是自己绘制的或明确 CC0/可再分发的。

## 设计基准

功能取舍以 [docs/design.md](docs/design.md) 为准，尤其是「第 12 节 第一版验收标准」与「第 13 节 明确不做的事情」。改动设计先开 issue 讨论。
