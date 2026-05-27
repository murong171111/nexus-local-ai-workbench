# Nexus

Nexus 是一个面向 macOS 的本地 AI 开发工作台，用来管理需求工作区、git worktree、微服务范围、风险信号、交付记录，以及面向 Codex 的本地工作流。

它适合需要同时维护多个本地服务仓库的团队，核心目标是让每个需求都有清晰、可持续追踪的工作区和文档沉淀。

[English](README.md)

## 功能特性

- 基于 Tauri、React、TailwindCSS 构建的原生 macOS 应用，并包含 Swift WidgetKit 小组件源码。
- 以工作区卡片展示需求目录、分支、服务范围、风险等级、最近活动和 worktree 状态。
- 支持在应用内创建符合 `ks-project-demand-workspace` 约定的需求工作区。
- 支持在应用内预览 Markdown 文档，包括状态、服务范围、分支说明、任务、决策和交付记录。
- 支持配置本地工作区目录、源仓库目录和交付文档目录。
- 支持导出和导入团队配置 Profile，便于分享路径约定和基础应用设置。
- 首次启动向导会引导配置工作区、源仓库和交付文档路径。
- 支持环境健康检查，用于确认本地路径和 Git 是否可用。
- 打包后的应用通过原生命令扫描配置路径，不依赖本地 Python 脚本。
- 支持原生扫描源仓库目录，新建工作区时可以从真实本地服务仓库中勾选服务。
- 支持分支一致性检查，当 worktree 实际分支和工作区目标分支不一致时会标记风险。
- 新建工作区时生成 `bootstrap-report.md` 和 `scripts/worktree-commands.sh`，用于半自动创建 worktree。
- 当 `交付记录.md` 仍是占位内容时，会提示交付记录待补充。
- 提供 Codex 启动入口和可复制 Prompt，用于继续工作区、检查 git 状态、更新交付文档和分析风险。
- 生成小组件快照文件：`~/Library/Application Support/com.ks.nexus/widget-snapshot.json`。
- 注册 `nexus://workspace/<workspace-folder>` URL Scheme，可用于从小组件或其他工具跳转到指定工作区。

## 安装

从 GitHub Releases 下载最新的 `Nexus_*.dmg`，打开后将 `Nexus.app` 拖入 Applications。

首次启动后：

1. 点击左下角 `Settings`。
2. 配置本地路径：
   - Workspaces root，例如 `~/ks_project/workspaces`
   - Source repositories root，例如 `~/ks_project/source-repos`
   - Delivery documents root，例如 `~/ks_project/docs`
3. 点击 `Save` 保存设置。
4. 点击源仓库扫描按钮，生成服务选择列表。
5. 点击顶部刷新按钮，扫描当前工作区。

如果要把配置分享给其他人，打开 `Settings` 后使用 `导出配置`。导出的 JSON 只包含路径约定、Codex URL 和刷新间隔，不包含工作区内容和代码。对方可以通过 `导入配置` 应用同一套约定，再按自己的机器目录微调。

> 当前预发布包尚未接入 Apple Developer 签名和 notarization。首次打开时，macOS 可能会显示安全提示，需要在系统设置中手动允许。

## 工作区结构

Nexus 默认识别每个需求工作区下的 Markdown 文档和本地 worktree 目录。推荐结构如下：

```text
<workspace>/
  AGENTS.md
  workspace.md
  STATUS.md
  services.md
  branches.md
  plan.md
  tasks.md
  decisions.md
  handoff.md
  delivery.md
  交付记录.md
  bootstrap-report.md
  logs/
  sql/
  repos/
  scripts/
```

其中 `repos/<service>` 建议作为 git worktree 使用，便于多个需求、多条分支并行开发，避免频繁切换同一个源仓库分支互相影响。

## 创建工作区

点击左侧 `New Workspace` 新建需求工作区。Nexus 会基于已配置的源仓库目录扫描服务列表，新建时可以直接勾选涉及服务；如果某个服务还不在源仓库目录中，也可以手动输入。手动输入支持逗号、空格、换行、分号，以及 `、`、`，` 等中文分隔符。

创建动作会写入标准 Markdown 文档，并把选中的服务记录到 `services.md` 和 `branches.md`。同时会生成 `bootstrap-report.md` 和 `scripts/worktree-commands.sh`。

Nexus 不会自动执行 worktree 命令。你需要先确认分支和服务范围，再人工执行生成的脚本。

## 本地开发

环境要求：

- macOS 12+
- Node.js 22+
- Rust toolchain
- Xcode Command Line Tools，用于构建 Tauri 应用
- 如需编译 WidgetKit 小组件，需要完整 Xcode

安装依赖：

```bash
npm install
```

启动 Web 开发服务：

```bash
npm run dev
```

启动 Tauri 开发应用：

```bash
npm run tauri:dev
```

构建 macOS 应用：

```bash
npm run tauri:build
```

重新生成应用图标：

```bash
npm run icon
```

检查 WidgetKit Swift 源码：

```bash
npm run widget:typecheck
```

构建原生 SwiftUI Mac 壳骨架：

```bash
npm run native:build
```

构建 Rust Core 桥接动态库：

```bash
npm run ffi:build
```

原生壳开发时，可以把 `NEXUS_CORE_LIBRARY` 指向构建出的 `libnexus_ffi.dylib`，用于通过 Rust Core 读取真实工作区数据。未设置时，Swift 壳会使用预览兜底数据。

运行本地标准验证：

```bash
npm run verify
```

## 小组件状态

主应用已经实现小组件快照写入，并注册了 `nexus://` URL Scheme。WidgetKit 源码位于：

```text
widget/NexusWidget/NexusWidget.swift
```

如果要真正打包和分发 `.appex` 小组件，还需要完整的 Xcode 工程、Widget Extension Target、App Group 配置、签名和 notarization。更多说明见 [widget/README.md](widget/README.md)。

## 文档

- [架构说明](docs/architecture.md)
- [原生架构目标](docs/native-architecture.md)
- [原生迁移计划](docs/plans/2026-05-27-native-mac-migration.md)
- [分发说明](docs/distribution.md)
- [发布流程](docs/release-process.md)
- [小组件实现说明](widget/README.md)
- [macOS 应用实现记录](docs/mac-app-implementation.md)
- [路线图](ROADMAP.md)
- [更新日志](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)

## 分发建议

当前仓库已经适合作为公开项目继续完善。正式对外分发前，建议补齐：

- Apple Developer 证书签名。
- notarization 自动化流程。
- GitHub Actions 自动构建和发布。
- Intel 与 Apple Silicon 双架构构建，或 Universal Binary。
- 自动更新机制。

## License

MIT
