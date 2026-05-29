# Nexus

Nexus 是一个面向 macOS 的本地 AI 开发工作台，用来管理需求工作区、git worktree、微服务范围、风险信号、交付记录，以及面向 Codex 的本地工作流。

它适合需要同时维护多个本地服务仓库的团队，核心目标是让每个需求都有清晰、可持续追踪的工作区和文档沉淀。

[English](README.md)

## 功能特性

- 基于 Tauri、React、TailwindCSS 构建的原生 macOS 应用，并包含 Swift WidgetKit 小组件源码。
- 以工作区卡片展示需求目录、分支、服务范围、风险等级、最近活动和 worktree 状态。
- 支持在应用内创建符合 `ks-project-demand-workspace` 约定的需求工作区，包含源仓库扫描、服务勾选、手动补充、创建前预检、创建确认摘要和创建后的下一步引导。
- 支持在应用内预览 Markdown 文档，包括状态、服务范围、分支说明、任务、决策和交付记录。
- 支持配置本地工作区目录、源仓库目录和交付文档目录。
- 支持导出和导入团队配置 Profile，便于分享路径约定、Codex URL 和 IDE URL 模板；首次启动向导和原生 Settings 都可以直接导入 Profile。
- 原生 Settings 的本地路径行支持环境状态、目录选择、打开目录，并可检查配置路径、Git 可用性、工作区数量和源仓库数量。
- 原生 SwiftUI 主流程动作使用更克制的中文短标签，并通过 hover 提示解释路径恢复和任务处理动作。
- 支持本地审计日志，记录已确认的新建工作区和配置导出动作。
- 支持本地 SQLite + FTS 索引基础能力，用于索引工作区 Markdown、服务范围、任务、决策、交付记录和 SQL 备注。
- 原生 SwiftUI 壳支持 Markdown 文档预览/源码切换，用于查看 handoff、标准工作区文档和搜索命中的文档，并在 Documents Hub 中展示当前文档、高亮、加载和错误恢复。
- 原生工作区详情支持一键用 Finder、IDE、Terminal 或 Codex 打开当前工作区，其中 Codex 会先复制包含本地检查、服务/worktree、任务、交付和推荐动作的工作区接力包；IDE 使用 Settings 中的 URL 模板，默认适配 IntelliJ IDEA。
- 原生工作区详情支持绑定多个 Codex 会话深度链接，可查看、打开、复制和删除，并把绑定保存到工作区内的 `codex-sessions.json`；当近期 Agent Event 带有匹配当前工作区的 Codex 深链 metadata 时，Sessions 区块会给出建议绑定。
- 原生 SwiftUI 壳支持本地任务中心，从 `tasks.md` 展示未完成任务，可显示任务来源行号并定位源文档，支持持久化筛选、最近任务写回反馈，也能显示 Agent 写回的任务，并支持确认后完成、延期任务，以及复制任务级上下文并打开 Codex。
- 原生 SwiftUI 壳支持 macOS 菜单栏状态入口，可快速查看工作区、风险、任务、worktree 状态，并执行刷新、设置和复制摘要动作。
- 支持本地自动化检查，可从 Rust Core、Swift/Rust 桥接、原生菜单栏、可配置周期调度、可见检查回执和可配置 macOS 本地通知生成刷新、风险、交付、任务、worktree、未提交服务信号。
- 原生 SwiftUI 壳支持自动化动作中心，可把本地检查信号直接转成风险聚焦、交付文档打开、任务定位、worktree 处理和 Codex 交接 Prompt。
- 支持从本地工作区证据派生生命周期阶段，并在原生卡片和详情中展示进度、当前原因、下一步、文档打开和 Codex 交接动作。
- 支持在原生壳中确认写回生命周期状态到 `workspace.md` 和 `STATUS.md`，并为状态流转记录本地审计事件。
- 原生任务状态和生命周期写回成功后，会显示本地写入反馈卡，可直接聚焦受影响工作区、复查源文档并重新运行本地检查。
- 顶部全局搜索会展示索引命中的工作区文档、SQL 备注和浏览器预览模式下的元数据结果，并支持结果分组与键盘导航。
- 首次启动向导会引导导入团队 Profile、配置工作区/源仓库/交付文档路径、扫描服务仓库，并可选创建演示工作区。
- 支持环境健康检查，用于确认本地路径和 Git 是否可用。
- 打包后的应用通过原生命令扫描配置路径，不依赖本地 Python 脚本。
- 原生新建工作区流程支持扫描源仓库目录、筛选服务候选、勾选真实本地服务，并允许在需求早期把服务范围标记为待确认；创建前会预检工作区根目录、目录名、重复写入位置、环境健康和范围风险，创建后会聚焦新工作区，并给出初始化回执、handoff、worktree、Codex 和本地检查入口。
- 原生 worktree 创建前会进行预检，确认目标分支、缺失 worktree、源仓库和 workspace-local 写入位置；执行后会刷新工作区状态，解释 created/skipped/failed 服务，并把下一步引导到 Finder、带结果的 Codex 交接或本地检查。
- 原生工作区详情顶部提供 Command Center，把生命周期进度、主路径推荐、范围 -> worktree -> 风险 -> 任务 -> 交付 -> Codex 会话 -> Codex 交接的会话路径、Codex 继续、本地检查结果、Finder、IDE、Terminal 和工作区链接复制放到同一个固定入口，并把快捷动作收敛为交接、执行和本地工具三组。
- 原生工作区详情顶部提供状态概览，把生命周期、分支、服务、风险、任务、交付、Codex 会话和最近本地检查状态放在进入详情后的第一屏。
- 原生剪贴板反馈会明确 workspace、生命周期、风险、任务、自动化、Agent 事件、会话链接或任务定位上下文已经复制，并根据上下文提示下一步。
- 原生 Agent Event 详情支持复制 Codex 继续上下文，也支持复制后直接打开 Codex，并为复制/打开两条路径记录本地审计。
- 原生右侧检查器会把本地操作错误收敛为统一的操作反馈卡，支持关闭、复制错误、刷新、环境检查和打开 Settings。
- 原生工作区列表提供空状态和 setup 引导，能展示当前配置路径、环境检查结果，并直接进入 Settings、新建工作区、刷新和环境检查。
- 原生工作区详情提供 Workflow 汇总，集中展示开放任务、阻塞任务、交付状态、交付焦点卡、交付前检查、本地检查回执、生命周期写回建议、任务文档、交付记录、工作区 Codex 交接、交付补充 Codex 交接和验证/PR 交接，并使用中文优先的主动作标签。
- 原生工作区详情提供 Risk review 风险复核，把活动风险、非交付类就绪检查、阻塞项、警告项、状态文档、worktree 创建、本地复查回执和 Codex 风险复核 Prompt 放在同一个固定区块。
- 原生工作区详情提供 Documents Hub，可以直接打开并预览标准工作区文件；当标准文档缺失时，可在确认后创建安全骨架文件，不可读时仍提供重试、复制路径和 Finder 恢复入口。
- 支持分支一致性检查，当 worktree 实际分支和工作区目标分支不一致时会标记风险。
- 新建工作区时生成 `bootstrap-report.md` 和 `scripts/worktree-commands.sh`，用于半自动创建 worktree。
- 当 `交付记录.md` 仍是占位内容时，会提示交付记录待补充。
- 支持 SQL 产物完整性检查：只要 `交付记录.md` 任意位置记录了实际 SQL 变更，`sql/` 下必须同时存在正式 SQL 文件和回滚 SQL 文件，否则交付检查会阻塞。
- 提供 Codex 启动入口和可复制 Prompt，用于继续工作区、检查 git 状态、更新交付文档和分析风险。
- 生成小组件快照文件：`~/Library/Application Support/com.ks.nexus/widget-snapshot.json`，并在存在 `group.com.ks.nexus` App Group 时同步写入共享容器。
- 支持 `nexus://workspace/<workspace-folder>` 深链，可用于从小组件或其他工具跳转并聚焦指定工作区；Command Center 也可以复制当前工作区链接，并在右侧检查器展示可关闭的反馈卡。

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

如果没有显示任何工作区，原生工作区列表会展示 setup 空状态：当前 workspace/source/docs 路径、最近一次环境检查结果，以及 Settings、New Workspace、Refresh、Environment Check 入口。如果是搜索或筛选导致列表为空，可以点击 `Show all` 清空筛选和搜索。

如果要把配置分享给其他人，打开 `Settings` 后导出 `nexus-settings-profile-*.json`。导出的 JSON 只包含路径约定、Codex URL、IDE URL 模板和刷新间隔，不包含工作区内容和代码。对方可以在首次启动向导或原生 Settings 中导入 Profile，再按自己的机器目录微调。

导入 Profile 后，可以在原生 Settings 中用路径行选择本地目录、打开已有目录，并运行 `Environment Check`，确认目录是否存在、是否可写、Git 是否可用，以及是否识别到了工作区和源仓库。`Tool Links` 中可以配置 Codex URL 和 IDE URL 模板，IDE 模板用 `{path}` 表示 URL 编码后的工作区路径，默认是 `idea://open?file={path}`。手动修改路径后，旧的环境检查结果会被清空，避免继续使用过期状态。

在工作区详情中，可以使用 `Finder`、`IDE`、`Terminal` 或 `Codex` 将当前工作区交给本地工具。`IDE` 动作会用 Settings 中的 URL 模板打开当前工作区；`Codex` 动作会复制一段工作区接力包，并打开 Settings 中配置的 Codex URL。接力包会包含最近本地检查、服务/worktree 摘要、开放任务、交付检查、标准文档路径和 Nexus 推荐动作。

工作区详情中的 `Codex 会话 / Sessions` 区块可以绑定多个 Codex 深度链接。绑定、打开、复制和删除都会在应用内给出反馈；删除只移除 Nexus 本地绑定，不会删除 Codex 里的会话。

每次交接 Codex、复制上下文、复制会话链接或定位任务来源后，原生右侧检查器会显示可关闭的剪贴板反馈面板，包含上下文类型、时间、复制内容类型和下一步提示。Codex Prompt 会继续提示可直接粘贴，任务定位则会指向 `tasks.md` 和 Documents Hub 中的聚焦行上下文。

如果本地操作失败，例如路径不可用、Codex URL 无效、IDE URL 模板无效、文档读取失败、Terminal 打不开或 worktree 创建失败，右侧检查器顶部会显示 `操作反馈 / Operation`。这里可以直接复制错误、刷新工作区、运行环境检查、进入 Settings 调整路径，或关闭该反馈继续处理当前工作区。

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
  codex-sessions.json
  bootstrap-report.md
  logs/
  sql/
  repos/
  scripts/
```

其中 `repos/<service>` 建议作为 git worktree 使用，便于多个需求、多条分支并行开发，避免频繁切换同一个源仓库分支互相影响。

## 创建工作区

点击左侧 `New Workspace` 新建需求工作区。Nexus 会基于已配置的源仓库目录扫描服务列表，可以筛选候选仓库并直接勾选涉及服务；如果某个服务还不在源仓库目录中，也可以手动输入。需求早期还没确认服务范围时，可以先留空，让工作区保持“服务范围待确认”。手动输入支持逗号、空格、换行、分号，以及 `、`、`，` 等中文分隔符。

创建前会展示目标路径、分支、服务范围摘要，并要求确认本地写入。预检会提前标出会导致创建失败的阻塞项，例如工作区根目录为空、根路径不是目录、目录名非法或目标目录已存在；服务范围待确认、目标分支待确认、环境检查未运行或部分服务未在源仓库扫描中出现，会显示为 review 项，不阻止先建档。创建动作会写入标准 Markdown 文档，并把选中的服务记录到 `services.md` 和 `branches.md`。同时会生成 `bootstrap-report.md`、`scripts/worktree-commands.sh`，写入一条本地审计事件，并返回初始化回执，用来确认标准文件、目录、初始 `STATUS.md`、服务范围、目标分支和 worktree 准备状态。

创建完成后，Nexus 会自动选中新工作区、清理旧的文档预览，并在右侧详情中展示下一步面板：查看初始化回执、打开 `handoff.md`、在服务和分支已确认时创建 worktree、交接 Codex，或运行本地检查。

Nexus 不会在创建工作区时自动创建 worktree。你需要先确认分支和服务范围，再使用原生 worktree 创建动作执行已确认的本地 `git fetch` 和 `git worktree add` 流程。在执行前，Nexus 会展示预检结果：目标分支是否已确认、哪些服务缺失 worktree、源仓库是否存在、将写入哪个 `repos/<service>` 目录。执行完成后，Nexus 会刷新工作区状态，以中文优先展示已创建、已跳过、失败的服务结果，并提供 Finder、带结果的 Codex 交接和本地检查后续入口。从结果卡运行本地检查后，会直接在卡片内显示检查摘要。

## 本地审计日志

Nexus 会把用户可感知的本地写入和交接动作记录为 JSONL 事件，默认位置是 `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl`。当前会记录新建工作区、导入/导出设置 Profile、文档打开/创建、worktree 设置、本地检查、Codex 会话/任务/交付/验证 PR 交接等动作；高频缓存写入，例如小组件快照刷新，不会写入审计日志。

原生菜单栏可以手动运行本地自动化检查，也可以在 Nexus 运行期间按持久化调度执行。该检查会扫描工作区 Markdown 和 git 状态，生成刷新、风险、交付、任务、worktree、未提交服务信号，并在 Rust Core 桥接可用时写入 `automation.check.completed` 审计事件。macOS 通知默认关闭，支持冷却时间和信号类型偏好，只会在检查结果匹配所选最低提醒级别时触发。

原生右侧检查器还会展示 `Automation Action Center`。运行检查后，Nexus 会把风险、交付、任务和 worktree 信号转换成可点击动作，例如聚焦有风险的工作区、打开交付记录、定位任务中心、弹出 worktree 创建确认，或复制一段带当前路径和工作区上下文的 Codex Prompt。

原生侧边栏中的近期 Agent Event 可以打开详情复核。详情页可以选中匹配工作区、打开安全的本地路径或网页链接、复制共享的 Codex 继续上下文，或复制后直接打开 Settings 中配置的 Codex URL。事件交接会进入本地审计；metadata 里的命令仍只作为可审查文本展示，Nexus 不会自动执行。

每个工作区详情顶部会先展示状态概览，汇总生命周期、目标分支、服务/worktree、风险、任务、交付、Codex 会话和最近本地检查。随后 `Command Center` 会汇总生命周期进度、分支确认状态、服务和 worktree 情况、风险等级、开放任务、会话绑定，并先给出一个带原因的主路径推荐；已有 Codex 会话时会优先回到最近会话，没有会话时仍可从这里绑定或复制新的接力包。随后用会话路径把范围、worktree、风险、任务、交付、Codex 会话和 Codex 交接压缩成一组可点击状态，再把快捷动作分成 `交接 / Handoff`、`执行 / Execute` 和 `本地 / Local`，分别承载 Codex 会话、本地检查/生命周期动作，以及 Finder/IDE/Terminal/工作区链接复制。运行本地检查后，这里会保留一张检查回执，展示状态、风险/交付/任务/worktree 指标、审计写入状态和可复制摘要。

每个工作区详情中都有 `Workflow` 区块，把任务和交付状态放在一起：顶部交付焦点卡会从目标分支、服务范围、worktree、阻塞/开放任务、风险、交付记录、SQL、未提交服务、进入交付、标记完成以及完成后的 PR/CI 复核中选择一个下一步动作；下方继续展示开放任务数、阻塞任务数、交付记录是否需要复核，并汇总目标分支、服务 worktree、任务关闭、风险、SQL、未提交服务和交付记录这些交付前检查项；也可以直接打开 `tasks.md`、`交付记录.md`、运行本地检查、交接整个工作区、复制一段专门用于补充交付记录的 Codex 上下文，或复制验证/PR 交接上下文。Workflow 触发或承接本地检查后，会在任务和交付动作旁保留同一张紧凑检查回执，展示指标、审计状态和可复制摘要。SQL 检查会读取整份 `交付记录.md`：如果文档任意位置声明有实际 SQL 变更，包括代码变更说明、表格或带明细的标题，就要求 `sql/` 下同时存在正式 SQL 和回滚 SQL 文件。验证/PR 交接上下文会带上交付记录、任务、SQL 检查、风险、服务/worktree、最近本地检查和 PR 描述要求，避免在收尾阶段靠记忆整理提交信息。

任务行会带上 Rust Core 扫描 `tasks.md` 得到的来源行号。任务中心和工作区任务行都可以定位任务：打开 `tasks.md`、复制一段任务来源定位信息，并在 Documents Hub 中显示当前聚焦的行上下文。当任务状态写回更新了 `tasks.md`，原生任务中心会保留一张最近写回卡片，提供聚焦受影响工作区和打开源文档的入口，即使刷新后任务列表发生变化也能继续复查。

每个工作区详情也有 `Risk review` 区块，把活动风险和非交付类就绪检查统一成风险数、阻塞项和警告项。这里可以重新运行本地检查、查看最近检查回执、打开 `STATUS.md`、在缺失服务 worktree 时进入确认创建流程，或复制一段专门用于风险复核的 Codex Prompt。

工作区详情还包含 `Documents` 文档入口，可直接打开 `workspace.md`、`STATUS.md`、`services.md`、`branches.md`、`tasks.md`、`交付记录.md`、`handoff.md`、`bootstrap-report.md` 和 `scripts/worktree-commands.sh`。当前打开的文档会高亮显示；如果标准文件缺失，文档区块会显示确认创建入口，Nexus 只创建缺失骨架、不覆盖已有文件，并在创建后刷新工作区、打开新文档、显示本地写入反馈；如果文件不可读，则继续提供失败原因、目标路径、重试、复制路径和 Finder 入口。切换工作区时会清理旧文档预览，避免误看其他工作区的文件。

已归档工作区仍会保留在工作区列表和“归档”筛选中，但不会再计入菜单栏活跃统计、任务中心总数和自动化提醒信号。

## 工作区生命周期

Rust Core 会根据当前 Markdown、任务、风险、服务范围、分支、交付记录和 git worktree 状态，为每个工作区派生生命周期阶段。原生壳会在工作区卡片和详情检查器中展示阶段、进度、当前原因、下一步动作和 Codex 交接入口。

当前阶段包括 `scoping`、`setup`、`developing`、`delivery`、`done`、`blocked` 和 `archived`。Nexus 不会自动改写生命周期文件，而是读取本地证据后引导下一步安全动作。

当 Rust Core 桥接可用时，可以在显式确认后把 `developing`、`delivery`、`done`、`blocked`、`archived` 等状态写回工作区。写回只更新 `workspace.md` 和 `STATUS.md`，并追加 `workspace_lifecycle.updated` 审计事件；不会移动目录、删除 worktree、切换 git 分支或自动完成任务。

任务状态或生命周期写回完成后，原生右侧检查器会展示本地写入反馈卡，说明状态变化、工作区已刷新，并提供聚焦受影响工作区、打开源文档和再次运行本地检查的入口。打开源文档和运行检查也会先聚焦受影响工作区，避免复查时停留在旧上下文。

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

主应用已经实现小组件快照写入，并注册了 `nexus://` URL Scheme。原生壳会写入 Application Support，处理 `nexus://workspace/<folder>` 聚焦跳转，并在应用配置了 App Group entitlement 后同步写入 `group.com.ks.nexus`。WidgetKit 源码位于：

```text
widget/NexusWidget/NexusWidget.swift
```

如果要真正打包和分发 `.appex` 小组件，还需要完整的 Xcode 工程、Widget Extension Target、App Group 配置、签名和 notarization。更多说明见 [widget/README.md](widget/README.md)。

## 文档

- [完整产品形态](docs/product-shape.zh-CN.md)
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
