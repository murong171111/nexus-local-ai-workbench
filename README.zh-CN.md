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
- 支持导出和导入团队配置 Profile，便于分享路径约定和基础应用设置；首次启动向导也可以直接导入 Profile。
- 支持本地审计日志，记录已确认的新建工作区和配置导出动作。
- 支持本地 SQLite + FTS 索引基础能力，用于索引工作区 Markdown、服务范围、任务、决策、交付记录和 SQL 备注。
- 原生 SwiftUI 壳支持 Markdown 文档预览/源码切换，用于查看 handoff 和搜索命中的工作区文档。
- 原生 SwiftUI 壳支持本地任务中心，从 `tasks.md` 展示未完成任务，支持持久化筛选，也能显示 Agent 写回的任务，并支持确认后完成、延期任务和复制任务级 Codex 上下文。
- 原生 SwiftUI 壳支持 macOS 菜单栏状态入口，可快速查看工作区、风险、任务、worktree 状态，并执行刷新、设置和复制摘要动作。
- 支持本地自动化检查，可从 Rust Core、Swift/Rust 桥接、原生菜单栏、可配置周期调度和可配置 macOS 本地通知生成刷新、风险、交付、任务、worktree、未提交服务信号。
- 原生 SwiftUI 壳支持自动化动作中心，可把本地检查信号直接转成风险聚焦、交付文档打开、任务定位、worktree 处理和 Codex 交接 Prompt。
- 支持从本地工作区证据派生生命周期阶段，并在原生卡片和详情中展示进度、当前原因、下一步、文档打开和 Codex 交接动作。
- 支持在原生壳中确认写回生命周期状态到 `workspace.md` 和 `STATUS.md`，并为状态流转记录本地审计事件。
- 顶部全局搜索会展示索引命中的工作区文档、SQL 备注和浏览器预览模式下的元数据结果，并支持结果分组与键盘导航。
- 首次启动向导会引导导入团队 Profile、配置工作区/源仓库/交付文档路径、扫描服务仓库，并可选创建演示工作区。
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

1. 如果团队已经分享 `nexus-settings-profile-*.json`，可以在初始化向导中先导入；也可以手动配置。
2. 配置本地路径：
   - Workspaces root，例如 `~/ks_project/workspaces`
   - Source repositories root，例如 `~/ks_project/source-repos`
   - Delivery documents root，例如 `~/ks_project/docs`
3. 点击 `Save` 保存设置。
4. 点击源仓库扫描按钮，生成服务选择列表。
5. 可以在初始化向导中创建演示工作区，用来查看标准 Markdown 结构。
6. 点击顶部刷新按钮，扫描当前工作区。

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

创建前需要确认本地写入。创建动作会写入标准 Markdown 文档，并把选中的服务记录到 `services.md` 和 `branches.md`。同时会生成 `bootstrap-report.md`、`scripts/worktree-commands.sh`，并写入一条本地审计事件。

Nexus 不会自动执行 worktree 命令。你需要先确认分支和服务范围，再人工执行生成的脚本。

## 本地审计日志

Nexus 会把用户可感知的本地写入记录为 JSONL 事件，默认位置是 `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl`。当前会记录新建工作区和导出设置 Profile；高频缓存写入，例如小组件快照刷新，不会写入审计日志。

原生菜单栏可以手动运行本地自动化检查，也可以在 Nexus 运行期间按持久化调度执行。该检查会扫描工作区 Markdown 和 git 状态，生成刷新、风险、交付、任务、worktree、未提交服务信号，并在 Rust Core 桥接可用时写入 `automation.check.completed` 审计事件。macOS 通知默认关闭，支持冷却时间和信号类型偏好，只会在检查结果匹配所选最低提醒级别时触发。

原生右侧检查器还会展示 `Automation Action Center`。运行检查后，Nexus 会把风险、交付、任务和 worktree 信号转换成可点击动作，例如聚焦有风险的工作区、打开交付记录、定位任务中心、弹出 worktree 创建确认，或复制一段带当前路径和工作区上下文的 Codex Prompt。

已归档工作区仍会保留在工作区列表和“归档”筛选中，但不会再计入菜单栏活跃统计、任务中心总数和自动化提醒信号。

## 工作区生命周期

Rust Core 会根据当前 Markdown、任务、风险、服务范围、分支、交付记录和 git worktree 状态，为每个工作区派生生命周期阶段。原生壳会在工作区卡片和详情检查器中展示阶段、进度、当前原因、下一步动作和 Codex 交接入口。

当前阶段包括 `scoping`、`setup`、`developing`、`delivery`、`done`、`blocked` 和 `archived`。Nexus 不会自动改写生命周期文件，而是读取本地证据后引导下一步安全动作。

当 Rust Core 桥接可用时，可以在显式确认后把 `developing`、`delivery`、`done`、`blocked`、`archived` 等状态写回工作区。写回只更新 `workspace.md` 和 `STATUS.md`，并追加 `workspace_lifecycle.updated` 审计事件；不会移动目录、删除 worktree、切换 git 分支或自动完成任务。

## 本地搜索索引

Nexus 可以在 `~/Library/Application Support/com.ks.nexus/nexus-index.sqlite3` 重建本地 SQLite + FTS 索引。索引只是缓存，可以从可读的工作区文件重新生成；当前会索引标准工作区 Markdown 文件和 `sql/` 目录下的备注/SQL 文件。

打包应用中的顶部搜索框会查询这个本地索引，结果会按工作区、状态、任务交付和 SQL 内容分组。可以使用方向键移动选中项，按 Enter 打开，按 Esc 清空搜索。浏览器预览模式没有 Tauri 命令时，会回退到工作区元数据搜索，便于开发和展示。

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
- [本地自动化 Hooks](docs/local-automation-hooks.md)
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
