# TileMason

**通用 2D 像素地图拼装桌面工具** —— 像玩《我的世界》创造模式一样，用素材件搭出街道、建筑、庭院与室内。每个件都可编辑、可移动、可删除，可保存为结构化地图数据，并导出为 Godot 场景或 JSON。

*A general-purpose desktop tool for assembling 2D pixel tile maps — place, move and edit every piece like Minecraft creative mode, then export to Godot scenes or structured JSON.*

> 🚧 项目处于 **P0（可用画笔）** 早期开发阶段：当前仓库包含编辑器骨架（画布平移/整数倍缩放/网格），笔刷与图层正在路上。完整路线图见下文。

## 交付形态：独立桌面软件

TileMason 是**独立桌面软件**——最终用户（美术、策划、关卡设计）下载安装包，双击即用，**不需要安装 Godot 或任何依赖**。Godot 4 只是它的开发框架（同类先例：像素画软件 Pixelorama、材质工具 Material Maker）。将来随发布提供 Windows / macOS / Linux 安装包；首个发布版之前可从源码运行（见下方开发者指南）。

## 核心特性（按设计文档推进）

| 特性 | 状态 |
|------|------|
| 画布平移 + 整数倍显示缩放（100%~800%，最近邻像素） | ✅ P0 骨架 |
| 正式网格 + 主网格辅助线（默认 16px，可配） | ✅ P0 骨架 |
| 自由摆放模式（半透明预览/网格吸附/底边中心锚点） | 🚧 P0 |
| 连续相接模式（笔刷/直线/矩形/油漆桶 + 自动连接变体） | 📅 P2 |
| 图层栈（显示/锁定/透明度/独显/层级调整） | 📅 P1 |
| 橡皮擦（单格/笔刷/区域 + 按图层/按素材过滤） | 📅 P0-P1 |
| 素材库（分类/搜索/收藏/最近使用/快捷栏） | 📅 P3 |
| 预制件（组合保存/整体复用） | 📅 P3 |
| 地图检查（道路连通/建筑堵门/碰撞重叠） | 📅 P3-P4 |
| 导出 Godot 场景 / 结构化 JSON | 📅 P4 |
| 撤销/重做、自动保存、版本恢复 | 📅 P0/P3 |

设计基准文档：[docs/design.md](docs/design.md)（含完整交互约定与第一版验收标准）。

## 快速开始

### 用户

首个发布版（P0 完成）将提供免安装的可执行程序下载。当前阶段可从源码运行，或等待 Release。

### 开发者 / 贡献者

1. 安装 [Godot 4.6+](https://godotengine.org/download)（标准版即可，无需 .NET）。
2. 克隆仓库：

   ```bash
   git clone https://github.com/Xeehho/tilemason.git
   ```

3. 用 Godot 打开项目根目录的 `project.godot`，等待导入完成。
4. 按 **F5** 运行：滚轮缩放画布，中键（或空格+左键）拖拽平移。

### 发布流程（维护者）

推送 `v*` 标签即触发机器人自动构建并发布：

```bash
git tag v0.1.0
git push origin v0.1.0
```

CI（GitHub Actions）会自动导出 Windows / Linux / macOS 免安装包并挂到 GitHub Release。也可在 Actions 页手动触发 **Release** 工作流做一次试构建（产物在该次运行页下载，不会发布）。

## 素材约定

- TileMason **不内置任何素材包**（版权原因），自带素材放入 `assets/packs/<包名>/`，详见 [assets/packs/README.md](assets/packs/README.md)。
- 默认约定：**16px 纹理网格 + 48px 组装块**（源自实际像素城市项目的验证经验），同时支持其他网格尺寸。
- 建筑与道具使用**底边中心锚点**，地面与规则方块使用左上角锚点——这是 y-sort 遮挡正确的关键。

## 目录结构

```text
tilemason/
├── docs/design.md      # 设计基准文档
├── scenes/             # 场景（保持精简，复杂节点运行时创建）
├── src/
│   ├── main.gd         # 编辑器外壳：装配与工具路由
│   └── canvas/         # 画布：相机 / 网格 / 后续地图文档层
├── assets/packs/       # 本地素材包（不入库）
└── .github/workflows/  # CI：脚本解析检查 + 冒烟启动
```

## 路线图

- **P0 可用画笔**：单块/连续放置、半透明预览、橡皮擦、网格吸附、撤销重做、保存场景
- **P1 区域和图层**：矩形填充、框选/移动/复制、图层显隐/锁定/透明度
- **P2 自动连接**：道路/墙体连接、转角/T形/十字、边缘件、连接规则编辑器
- **P3 生产力**：收藏/最近/标签、快捷栏、预制件、批量替换、碰撞与通路检查
- **P4 运行时接入**：生成 Godot 场景与碰撞、交互锚点、验收截图

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。提交前请确认 `git status` 干净、CI 绿灯。

## 许可证

[MIT](LICENSE)。仓库不含任何第三方素材；素材包版权归各自作者。
