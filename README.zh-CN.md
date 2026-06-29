# Nexus

Nexus 是一个面向 macOS 的本地 AI 开发工作台，用来管理需求工作区、git worktree、微服务范围、风险信号、交付记录，以及面向 Codex 的本地工作流。

它适合需要同时维护多个本地服务仓库的团队，核心目标是让每个需求都有清晰、可持续追踪的工作区和文档沉淀。

[English](README.md)

## 功能特性

- 基于 Tauri、React、TailwindCSS 构建的原生 macOS 应用，并包含 Swift WidgetKit 小组件源码。
- 以工作区卡片展示需求目录、分支、服务范围、风险等级、最近活动和 worktree 状态。
- 原生 SwiftUI 壳现在提供两个主入口：`Console / 控制台` 用于聚焦处理当前工作区，`Board / 面板` 用于按主流程阶段总览当前筛选下的工作区；Board 内可切换全部、需处理、交付和归档范围，卡片会显示 worktree 摘要，点击面板卡片会回到控制台并聚焦该工作区。
- 支持在应用内创建符合 `ks-project-demand-workspace` 约定的需求工作区，包含源仓库扫描、服务勾选、手动补充、创建前预检、创建确认摘要和创建后的下一步引导。
- 支持在工作区详情中执行 `需求预检`：检查或初始化固定 `需求/` 目录，生成 `requirement.md`、`questions.md`、`scope.md`、`tasks.md` 和 `delivery.md`，并复制 `$lanhu-demand-intake` Codex 预检提示词。原生壳会读取这些 Markdown，检查需求内容、未解决 P0、scope 状态和真实需求任务，并通过独立的范围冻结门禁检查本次实现、不实现、待确认 P0、冻结标记，以及范围变更是否记录原因和影响，确认后可把真实需求行转入根 `tasks.md`；Nexus 仍不直接解析蓝湖或调用 AI。
- 原生服务/分支确认门禁会检查 `services.md`、`branches.md`、工作区服务行、源仓库可用性、目标分支可用性和分支策略；只要源仓库存在目标分支或远端引用，source 当前 checkout 不要求切到目标分支。
- 原生 worktree 准备证据会检查缺失的 workspace-local worktree、源仓库中的目标分支可用性、源仓库可用性、创建命令可见性，以及服务级 create/skip/blocked 创建计划；source 当前分支只作为上下文展示，不作为阻塞条件。
- 原生开发任务证据会坚持 root `tasks.md` 是执行任务源，自动选择下一条活跃任务，阻塞未解决的任务 blocker，并展示任务推进计划，把任务归类为处理阻塞、当前推进、排队或已关闭，同时给出写回建议。
- 原生交付门禁证据会在交付就绪前统一检查任务、风险、服务/worktree、交付记录、SQL 产物、未提交服务和本地检查状态。
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
- Tauri 工作区详情抽屉也会读写工作区内的 `codex-sessions.json`，可以在同一条详情流里绑定、查看、打开、复制和删除多个 Codex 会话链接。
- 原生 SwiftUI 壳支持本地任务中心，从 `tasks.md` 展示未完成任务，可显示任务来源行号并定位源文档，支持持久化筛选、最近任务写回反馈，也能显示 Agent 写回的任务，并在写入后提供聚焦 Agent 任务和打开 `tasks.md` 的后续动作，同时支持确认后完成、延期任务，以及复制任务级上下文并打开 Codex。确认完成/延期会由 Swift Native 本地核心写回 root `tasks.md` 并记录 `workspace_task.updated` 审计事件。延期任务仍保留在延期筛选中，但不会继续触发活跃任务告警或交付阻塞。
- Rust Core 和原生本地检查会把 `进行中`/`待办` 任务汇总为 `active-tasks` 检查项，并生成 `continue-active-tasks` 下一步动作，让未完成任务直接回到 `tasks.md`，不会只藏在任务数量里。
- 原生 SwiftUI 壳支持工作区筛选持久化、实时计数、空筛选禁用，以及从侧边栏或空状态一键恢复全部工作区。
- 原生 SwiftUI 壳支持 macOS 菜单栏状态入口，可快速查看工作区、风险、任务、worktree 和未提交服务状态，并执行刷新、设置和复制摘要动作；缺失 worktree 或未提交服务会进入菜单栏标题和复制摘要。
- 支持本地自动化检查，由 Swift Native 基于当前工作区摘要生成刷新、风险、交付、目标分支可用性、任务、worktree、未提交服务信号，并保留 Rust Core 桥接作为兼容兜底；这些信号会进入原生菜单栏、可配置周期调度、可见检查回执和可配置 macOS 本地通知。
- 原生 SwiftUI 壳支持自动化动作中心，可把本地检查信号直接转成风险复核交接、带 SQL 上下文的交付交接或交付文档复查、分支文档复查、任务定位、worktree 处理、未提交服务交接和 Codex 交接 Prompt，并按任务、交付、风险、分支、worktree 或服务证据选择对应工作区上下文。
- 支持从本地工作区证据派生生命周期阶段，并在原生卡片和详情中展示进度、当前原因、下一步、文档打开和 Codex 交接动作。
- 支持在原生壳中确认写回生命周期状态到 `workspace.md` 和 `STATUS.md`，并为状态流转记录本地审计事件。
- 原生任务状态和生命周期写回成功后，会显示本地写入反馈卡，可直接聚焦受影响工作区、复查源文档并重新运行本地检查。
- 顶部全局搜索会展示索引命中的工作区文档、SQL 备注和浏览器预览模式下的元数据结果，并支持结果分组与键盘导航。
- 浏览器预览模式支持本地持久化置顶工作区，让关键工作区排在风险分排序之前，同时不改写工作区 Markdown。
- 首次启动向导会引导导入团队 Profile、配置工作区/源仓库/交付文档路径、扫描服务仓库，并可选创建演示工作区；原生空状态也会展示“团队配置 -> 环境检查 -> 创建工作区”的首次使用路径，新建工作区弹窗内提供演示模板。
- 原生左侧底部会显示本机 setup readiness，并把 Settings 保持在固定入口附近；环境检查通过时会明确提示不需要初始化，可直接刷新现有工作区或新建第一个工作区。
- 支持环境健康检查，用于确认本地路径和 Git 是否可用。
- 打包后的应用通过原生命令扫描配置路径，不依赖本地 Python 脚本。
- 原生新建工作区流程支持扫描源仓库目录、筛选服务候选、勾选真实本地服务，并允许在需求早期把服务范围标记为待确认；当还没有任何工作区时会提供演示模板预填，创建前仍会预检工作区根目录、目录名、重复写入位置、环境健康和范围风险，确认后由 Swift Native 写入标准 Markdown、SQL/log/repos/scripts 目录、初始化回执、`INDEX.md` 和 `workspace.created` 审计事件，再聚焦新工作区、自动打开生成的 `handoff.md`，并给出 handoff、worktree、Codex 和本地检查入口。
- 原生 worktree 创建前会展示 Swift-owned 证据卡和确认预检，确认目标分支、缺失 worktree、源仓库中的目标分支可用性、源仓库、创建脚本和 workspace-local 写入位置；执行后会刷新工作区状态，解释 created/skipped/failed 服务，把失败项归类为服务级恢复建议，并把下一步引导到 Finder、带结果的 Codex 交接或本地检查。
- 原生工作区详情顶部提供 Command Center，把生命周期进度、主路径推荐、任务状态、SQL 状态、交付状态、范围 -> worktree -> 风险 -> 任务 -> SQL -> 交付 -> Codex 会话 -> Codex 交接的工作流路径、Codex 继续、本地检查结果、Finder、IDE、Terminal 和工作区链接复制放到同一个固定入口；路径卡会显示紧凑动作标签，SQL 和交付卡会按状态路由到本地检查、SQL 产物复查、交付交接、验证/PR 交接或文档查看；状态标签采用中文优先，并把快捷动作收敛为交接、下一步和本地工具三组。
- 原生工作区详情顶部提供紧凑的 `详情导航 / Detail map`，把概览、工作台、任务交付、服务、风险、文档和活动作为可跳转区块，并附带短状态提示。
- 原生工作区详情会把 Rust Core 推荐动作收进 Command Center 下方的 `下一步队列 / Next-step queue`，作为主路径之外的文档、worktree 和交接候选入口，不再散落成独立的后置建议区块。
- 原生工作区详情顶部提供状态概览，把生命周期、分支、服务、风险、任务、SQL、交付、Codex 会话和最近本地检查状态放在进入详情后的第一屏；概览卡片可直接进入匹配动作，例如打开分支/服务/任务/SQL/交付文档、创建 worktree、风险交接、绑定或打开 Codex 会话、运行本地检查。
- 原生工作区详情的服务区块会汇总服务范围、缺失 worktree 和未提交服务，并在每个服务行提供 worktree、源仓库、IDE、确认创建 worktree 和服务级 Codex 交接动作。
- 原生工作区详情的 Workflow 会先展示 root `tasks.md` 的开发任务证据卡，把活跃、阻塞、已完成和延期任务证据放在交付清理动作之前。
- 原生工作区详情的 Workflow 也会在详细 checklist 前展示交付门禁证据卡，先给出交付 blocker、待检查项、复核项、已通过证据、按顺序排列的交付处理计划和单一下一步动作。
- 原生工作区详情的 Workflow 会在交付和归档之间展示验证/PR 证据，汇总本地检查、交付记录、任务/风险清理、PR/CI 或发布备注，以及生命周期是否已准备好进入最终归档。
- 原生剪贴板反馈会明确 workspace、生命周期、风险、任务、自动化、Agent 事件、会话链接或任务定位上下文已经复制，并根据上下文提示下一步。
- 原生侧边栏的 Agent Events 现在以 Agent Inbox 展示，按 `需要处理 / Attention` 和 `最近事件 / Recent` 分组，让 permission、question、tool-review 和 error 事件优先出现；没有事件时会显示清晰的空状态。Inbox 下方的 `Agent Workflow / 流转` 会把事件处理和 Agent 来源任务串起来，展示待处理事件数、Agent 任务数，并可直接聚焦任务中心的 Agent 筛选。Agent Event 详情支持复制 Codex 继续上下文，也支持复制后直接打开 Codex，并为复制/打开两条路径记录本地审计；permission、question 和 tool-review 事件会显示 Agent 动作面，可复制批准、拒绝、答复或复核模板，但不会执行 metadata 里的命令。Agent 任务草稿写入或发现已存在后，详情内会保留结果卡，可继续聚焦对应 Agent 任务或打开 `tasks.md`，右侧检查器也会显示统一的本地写入反馈。
- 原生右侧检查器会把本地操作错误收敛为统一的操作反馈卡，支持关闭、复制错误、刷新、环境检查和打开 Settings；预览 App 的失败 toast 也会补充操作名、目标路径和恢复建议。
- 原生工作区列表和详情空状态共用 setup 动作组，能展示当前配置路径、环境检查结果、首次使用路径，并直接进入新建工作区、Settings/团队配置、环境检查、刷新和显示全部恢复。
- 原生工作区详情提供 Workflow 汇总，集中展示开放任务、阻塞任务、交付状态、交付焦点卡、文档/检查/Agent 交接动作分组、交付前检查、本地检查回执、生命周期写回建议、任务文档、交付记录、工作区 Codex 交接、交付补充 Codex 交接和验证/PR 交接，并使用中文优先的主动作标签。
- 原生 Workflow 的交付前检查行可直接处理分支、服务/worktree、任务、风险、交付记录、SQL 和未提交服务问题，把交付清理动作保留在 Workflow 结构内。SQL 行通过时会进入 SQL 产物复查，缺正式或回滚 SQL 时会进入带 SQL 检查上下文的交付交接。
- 原生 Workflow 的交付前检查会分为 `需要处理 / Attention` 和 `已通过 / Passed`，交付收尾时先看到阻塞项和复核项，再查看已通过证据。
- 原生工作区详情提供 Risk review 风险复核，把活动风险、非交付类就绪检查、阻塞项、警告项、状态文档、worktree 创建、本地复查回执和 Codex 风险复核 Prompt 放在同一个固定区块；风险检查行可直接回到服务、分支、worktree、状态、任务或交付记录处理入口。
- 原生工作区详情提供 Documents Hub，可以直接打开并预览标准工作区文件和扫描到的 `sql/*.sql` 产物；每个文档入口会说明职责、更新时间、参与的 gate 和创建策略；预览区支持 Markdown 预览/源码切换和只关闭文档预览；当标准文档缺失时，可在确认后创建安全骨架文件，不可读时仍提供重试、复制路径和 Finder 恢复入口。
- 支持目标分支可用性检查：确认每个服务的源仓库存在指定目标分支或远端跟踪引用；worktree 当前检出的分支不同，不会单独作为阻塞项。
- 新建工作区时生成 `bootstrap-report.md` 和 `scripts/worktree-commands.sh`，用于半自动创建 worktree。
- 当 `交付记录.md` 仍是占位内容时，会提示交付记录待补充。
- 支持 SQL 产物完整性检查：只要 `交付记录.md` 任意位置记录了实际 SQL 变更，`sql/` 下必须同时存在正式 SQL 文件和回滚 SQL 文件，否则交付检查会阻塞。`SQL 变更` 段落里的 `变更类型：DDL/DML`、影响表、新增字段、回填脚本、数据修复说明，也会视为实际 SQL 变更。新建工作区模板也会在 `AGENTS.md`、`handoff.md` 和 `交付记录.md` 中重复这条守门规则，避免 SQL 只写在交付文档里就被误认为完成。
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
5. 可以在 `New Workspace` 中套用演示模板查看标准 Markdown 结构；真正写入前仍需要通过预检并勾选确认。
6. 点击顶部刷新按钮，扫描当前工作区。

如果没有显示任何工作区，原生工作区列表和详情空状态会展示共用 setup 动作组：当前 workspace/source/docs 路径、最近一次环境检查结果、团队配置 -> 环境检查 -> 创建工作区的首次使用路径，以及新建工作区、Settings/团队配置、环境检查、刷新和显示全部恢复入口。如果是搜索或筛选导致列表为空，可以点击 `显示全部`，或使用侧边栏筛选区的 `清空筛选 / Reset` 清空已持久化的工作区筛选和搜索。

如果要把配置分享给其他人，打开 `Settings` 后导出 `nexus-settings-profile-*.json`。导出的 JSON 只包含路径约定、Codex URL、IDE URL 模板和刷新间隔，不包含工作区内容和代码。对方可以在首次启动向导或原生 Settings 中导入 Profile，再按自己的机器目录微调。

导入 Profile 后，可以在原生 Settings 中用路径行选择本地目录、打开已有目录，并运行 `Environment Check`，确认目录是否存在、是否可写、Git 是否可用，以及是否识别到了工作区和源仓库。`Tool Links` 中可以配置 Codex URL 和 IDE URL 模板，IDE 模板用 `{path}` 表示 URL 编码后的工作区路径，默认是 `idea://open?file={path}`。手动修改路径后，旧的环境检查结果会被清空，避免继续使用过期状态。

在工作区详情中，可以使用 `Finder`、`IDE`、`Terminal` 或 `Codex` 将当前工作区交给本地工具。`IDE` 动作会用 Settings 中的 URL 模板打开当前工作区；`Codex` 动作会复制一段工作区接力包，并打开 Settings 中配置的 Codex URL。接力包会包含最近本地检查、服务/worktree 摘要、开放任务、交付检查、标准文档路径和 Nexus 推荐动作。

工作区详情中的 `Codex 会话 / Sessions` 区块可以绑定多个 Codex 深度链接。绑定、打开、复制和删除都会在应用内给出反馈；删除只移除 Nexus 本地绑定，不会删除 Codex 里的会话。

绑定后的会话链接也会进入 Codex 接力 Prompt。工作区、生命周期、任务、风险、交付、验证/PR、服务和自动化交接都会列出相关会话标题和 URL，新的 Codex 继续窗口可以优先回到已有会话，再使用新复制的上下文包补齐当前状态。

每次交接 Codex、复制上下文、复制会话链接或定位任务来源后，原生右侧检查器会显示可关闭的剪贴板反馈面板，包含上下文类型、时间、复制内容类型和下一步提示。Codex Prompt 会继续提示可直接粘贴，任务定位则会指向 `tasks.md` 和 Documents Hub 中的聚焦行上下文。

如果本地操作失败，例如路径不可用、Codex URL 无效、IDE URL 模板无效、文档读取失败、Terminal 打不开或 worktree 创建失败，右侧检查器顶部会显示 `操作反馈 / Operation`。这里可以直接复制错误、刷新工作区、运行环境检查、进入 Settings 调整路径，或关闭该反馈继续处理当前工作区。预览 App 的 toast 也会补充操作名、目标路径和恢复建议，用于文档打开、索引重建、工作区创建、配置导入导出和 worktree 创建失败。

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
  需求/
    requirement.md
    questions.md
    scope.md
    tasks.md
    delivery.md
  logs/
  sql/
  repos/
  scripts/
```

其中 `repos/<service>` 建议作为 git worktree 使用，便于多个需求、多条分支并行开发，避免频繁切换同一个源仓库分支互相影响。

## 创建工作区

点击左侧 `New Workspace` 新建需求工作区。Nexus 会基于已配置的源仓库目录扫描服务列表，可以筛选候选仓库并直接勾选涉及服务；如果某个服务还不在源仓库目录中，也可以手动输入。需求早期还没确认服务范围时，可以先留空，让工作区保持“服务范围待确认”。手动输入支持逗号、空格、换行、分号，以及 `、`、`，` 等中文分隔符。

创建前会展示目标路径、分支、服务范围摘要，并要求确认本地写入。预检会提前标出会导致创建失败的阻塞项，例如工作区根目录为空、根路径不是目录、目录名非法或目标目录已存在；服务范围待确认、目标分支待确认、环境检查未运行或部分服务未在源仓库扫描中出现，会显示为 review 项，不阻止先建档。创建动作会写入标准 Markdown 文档，并把选中的服务记录到 `services.md` 和 `branches.md`。同时会生成 `bootstrap-report.md`、`scripts/worktree-commands.sh`，写入一条本地审计事件，并返回初始化回执，用来确认标准文件、目录、初始 `STATUS.md`、服务范围、目标分支和 worktree 准备状态。

创建完成后，Nexus 会自动选中新工作区、清理旧的文档预览，并在右侧详情中展示下一步清单。第一步建议先在 `需求预检` 区块初始化 `需求/`，填写需求名称、蓝湖链接和补充说明，复制 `$lanhu-demand-intake` 提示词给 Codex 整理 `requirement.md`、`questions.md`，并在 `需求/tasks.md` 建立未完成需求列表。原生壳会检查整理后的 Markdown 是否已经包含非占位需求内容、P0 是否清零，以及 `需求/tasks.md` 是否有真实需求点。下一道原生门禁是 `范围冻结`，它会读取 `需求/scope.md` 中本次实现、暂不实现、待确认 P0、冻结标记和范围变更记录；如果文档提到范围变更，但缺少变更原因或影响服务/任务/SQL/交付说明，会进入复核状态。当 `需求/tasks.md` 中已经有真实需求行时，Nexus 可以在明确确认后把它们转入根 `tasks.md`；任务中心和交付门禁仍以根 `tasks.md` 为准。Nexus 不会自动解析蓝湖，也不会直接调用 AI；真正的需求理解和问题分级仍由后续 Codex 会话完成。

完成需求预检并冻结 `需求/scope.md` 后，再继续确认服务范围、目标分支、worktree、`handoff.md` 和首次本地检查。原生服务/分支门禁会解释 `services.md`、`branches.md`、source repo 和分支策略是否就绪，待确认服务或分支会直接打开对应文档，服务和分支已确认后才进入 worktree 创建流程。

Nexus 不会在创建工作区时自动创建 worktree。你需要先确认分支和服务范围，再使用原生 worktree 创建动作执行已确认的本地 `git fetch` 和 `git worktree add` 流程。在执行前，Nexus 会展示预检结果：目标分支是否已确认、哪些服务缺失 worktree、源仓库是否存在、将写入哪个 `repos/<service>` 目录。执行完成后，Nexus 会刷新工作区状态，以中文优先展示已创建、已跳过、失败的服务结果，并提供 Finder、带结果的 Codex 交接和本地检查后续入口。从结果卡运行本地检查后，会直接在卡片内显示检查摘要。

## 本地审计日志

Nexus 会把用户可感知的本地写入和交接动作记录为 JSONL 事件，默认位置是 `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl`。当前会记录新建工作区、导入/导出设置 Profile、文档打开/创建、worktree 设置、本地检查、Codex 会话/任务/交付/验证 PR 交接等动作；高频缓存写入，例如小组件快照刷新，不会写入审计日志。

原生菜单栏可以手动运行本地自动化检查，也可以在 Nexus 运行期间按持久化调度执行。该检查现在使用 Swift Native 工作区摘要生成刷新、风险、交付、目标分支可用性、任务、worktree、未提交服务信号，并通过 Native 审计存储写入 `automation.check.completed` 事件；只有本地刷新无法提供状态时才兜底走 Rust Core 桥接。目标分支可用性表示每个服务 source repo 里存在指定分支或 remote-tracking ref，source 当前 checkout 到其他分支不会单独触发分支信号。macOS 通知默认关闭，支持冷却时间和信号类型偏好，只会在检查结果匹配所选最低提醒级别时触发。

原生右侧检查器还会展示 `Automation Action Center`。运行检查后，Nexus 会把风险、交付、分支、任务、worktree 和未提交服务信号转换成可点击动作，例如为有风险的工作区复制风险复核 Codex 交接、打开目标分支不可用工作区的 `branches.md`、定位任务中心、弹出 worktree 创建确认、把第一个未提交服务作为服务级上下文交给 Codex，或复制一段带当前路径和工作区上下文的 Codex Prompt。交付信号会先定位真正有问题的工作区，并优先处理 SQL 产物问题；缺正式/回滚 SQL 时进入带 SQL 检查明细的交付交接，缺交付记录时回到交付文档复查入口。Worktree 信号的交接 Prompt 会带上缺失服务、源仓库可用性、创建脚本路径、就绪检查和目标分支是否已确认，避免只靠人工翻 `services.md` 和 `branches.md`。复制自动化 Prompt 时还会带上 Nexus 推荐动作，让确认目标分支、确认服务范围等前置 blocker 和信号证据一起交给 Codex。任务信号只关注活跃任务，已延期任务保留在 Task Center 的延期筛选里，不再制造本地检查噪音。风险、任务、分支、worktree 和未提交服务信号复制自动化 Prompt 时，也会优先选择存在对应证据的工作区，避免把无关的当前选中工作区交给 Codex。

原生侧边栏中的 Agent Event 会先进入 Agent Inbox：`需要处理 / Attention` 优先显示 permission、question、tool-review 和 error 事件，`最近事件 / Recent` 保留其他信息事件，没有事件时会显示“暂无待处理事件”。Inbox 下方的 `Agent Workflow / 流转` 会说明下一步是先处理事件，还是继续已写入 `tasks.md` 的 Agent 任务；存在 Agent 来源任务时，可一键把任务中心切换到 Agent 筛选并聚焦第一条任务。点击事件后可以打开详情复核，选中匹配工作区、打开安全的本地路径或网页链接、复制共享的 Codex 继续上下文，或复制后直接打开 Settings 中配置的 Codex URL。permission、question 和 tool-review 事件会在详情中显示 `Agent 动作面 / Action surface`，用于复制批准、拒绝、答复或复核模板；这些复制动作会进入本地审计，但 metadata 里的命令仍只作为可审查文本展示，Nexus 不会自动执行。当 Agent 任务草稿写入 `tasks.md`，或同一任务已经存在时，事件详情会显示结果卡，让用户直接跳转任务中心的 Agent 筛选或复查源文档，不需要关闭后重新寻找上下文。

每个工作区详情顶部会先展示 `详情导航 / Detail map` 和状态概览。详情导航把概览、工作台、任务交付、服务、风险、文档和活动压缩成一组可跳转区块，并用短状态提示显示当前主路径、任务、服务、风险、文档和活动概况。状态概览汇总生命周期、目标分支、服务/worktree、风险、任务、SQL、交付、Codex 会话和最近本地检查。概览卡片本身也是轻量入口：阶段卡打开当前阶段文档，分支/服务/任务/SQL 卡回到对应 Markdown 或 SQL 产物，缺失 worktree 时服务卡进入创建流程，风险卡复制风险交接，交付卡复用状态路由进入本地检查、交付交接、验证/PR 交接或文档查看，会话卡可打开最近会话或进入绑定。随后 `Command Center` 会汇总生命周期进度、分支确认状态、服务和 worktree 情况、风险等级、任务状态、SQL 状态、交付/归档状态、会话绑定，并先给出一个带原因的主路径推荐；任务、SQL、交付和归档指标来自同一份工作流证据，所以阻塞/开放任务、SQL 产物状态、交付记录就绪状态和最终归档资格会在进入深层 Workflow 前先露出。已有 Codex 会话时会优先回到最近会话，没有会话时仍可从这里绑定或复制新的接力包。随后用工作流路径把范围、worktree、风险、任务、SQL、交付、归档、Codex 会话和 Codex 交接压缩成一组可点击状态，并统一使用中文优先的状态标签和动作标签；其中 SQL 路径会根据状态运行检查、打开 SQL 产物或进入 SQL 交接，交付路径会根据状态直接选择下一步：待检查运行本地检查，需补充或阻塞时打开交付补充 Codex 交接，已完成时进入验证/PR 交接，记录可用或归档时打开交付文档；归档路径会复用交付硬门禁，展示归档确认计划，并通过确认弹窗进入交付、标记完成、归档，或把已归档工作区显式恢复为开发状态。再把快捷动作分成 `交接 / Handoff`、`下一步 / Next` 和 `本地打开 / Local`，分别承载 Codex 会话、本地检查/生命周期动作，以及 Finder/IDE/Terminal/工作区链接复制。Command Center 下方的 `下一步队列 / Next-step queue` 会收纳 Rust Core 从 readiness/session action 推导出的候选动作，用来保留可并行查看或稍后处理的文档、worktree 和交接入口。运行本地检查后，这里会保留一张检查回执，展示状态、风险/交付/任务/worktree 指标、审计写入状态和可复制摘要。

从任务、风险、交付、搜索或 Documents Hub 打开文档后，工作区详情顶部会出现 `当前文档 / Active document` 轻量条，展示当前文档的加载、错误或就绪状态。这里可以跳回 Documents 预览、复制路径，或只关闭文档预览而不关闭工作区详情，避免文档层和详情层互相干扰。Documents Hub 卡片也会说明这个文件负责什么、什么时候更新、是否参与当前 gate，以及 Nexus 能否创建缺失骨架或只能把它作为动态产物复查。

服务区块是这个流程里的服务级操作枢纽。它会汇总服务数量、缺失 worktree 和未提交服务信号，并把每个服务行连接到具体本地动作：打开 workspace-local worktree、打开 source repo 做只读对照、用 Settings 中的 IDE URL 模板打开该服务 worktree、在缺失 worktree 时进入确认创建流程，或复制并打开一份服务级 Codex 交接上下文。服务交接会带上服务路径、source 路径、分支、git 摘要、任务和交付文档入口，避免只靠工作区级 Prompt 解释单个服务问题。

每个工作区详情中都有 `Workflow` 区块，把任务和交付状态放在一起：顶部先展示开发任务、交付门禁、验证/PR 和归档门禁证据卡，再保留交付焦点卡用于兼容单步建议。归档门禁会复用交付硬门禁：仍有开放/阻塞任务、风险、缺失 SQL 产物、未提交服务或交付记录不完整时，不会出现归档动作；交付通过后，归档卡会展示归档确认计划，按顺序提示复核交付记录、复核验证/PR、写回生命周期和最终归档，再通过确认弹窗进入交付、标记完成或归档，避免跳过最终复核。已归档工作区在同一张卡里默认保持只读：主动作打开 handoff 证据，单独的“恢复开发”行才会在确认后把生命周期写回 developing，并提示重新运行本地检查。下方继续展示开放任务数、阻塞任务数、交付记录是否需要复核，并把常用动作收敛成 `文档 / Docs`、`检查 / Check`、`Agent 交接 / Handoff` 三组，分别承载打开 `tasks.md`/`交付记录.md`、运行本地检查、交接工作区/交付补充/验证 PR 上下文。随后继续汇总目标分支、服务 worktree、任务关闭、风险、SQL、未提交服务和交付记录这些交付前检查项。交付前检查会分为 `需要处理 / Attention` 和 `已通过 / Passed`，让阻塞项和复核项保持在已通过证据之前。交付前检查行本身也可点击：分支行打开分支文档，服务行打开服务文档或进入确认创建 worktree，任务行打开 `tasks.md`，风险行复制风险复核交接，交付记录行进入交付补充交接，SQL 通过时打开 SQL 产物复查，缺正式或回滚 SQL 时进入带 SQL 检查上下文的交付交接，未提交服务行会把第一个未提交服务作为服务级上下文交给 Codex。Workflow 触发或承接本地检查后，会在任务和交付动作旁保留同一张紧凑检查回执，展示指标、审计状态和可复制摘要。SQL 检查会读取整份 `交付记录.md`：如果文档任意位置声明有实际 SQL 变更，包括代码变更说明、表格、带明细的标题，或 SQL 段落里的 `变更类型：DDL/DML`、影响表、新增字段、回填脚本，就要求 `sql/` 下同时存在正式 SQL 和回滚 SQL 文件。验证/PR 交接上下文会带上交付记录、任务、SQL 检查、风险、服务/worktree、最近本地检查和 PR 描述要求，避免在收尾阶段靠记忆整理提交信息。

任务行会带上 Rust Core 扫描 `tasks.md` 得到的来源行号。任务中心和工作区任务行都可以定位任务：打开 `tasks.md`、复制一段任务来源定位信息，并在 Documents Hub 中显示当前聚焦的行上下文。当任务状态写回更新了 `tasks.md`，原生任务中心会保留一张最近写回卡片，提供聚焦受影响工作区和打开源文档的入口，即使刷新后任务列表发生变化也能继续复查。

任务写回后会继续推动处理流：完成或延期任务后，Nexus 可以聚焦下一条活跃任务，并优先选择同一工作区的下一项，再回退到全局下一项。Agent Event 写成任务后也会自动切到 Agent 筛选并聚焦匹配任务，方便从转换后的任务继续处理。

每个工作区详情也有 `Risk review` 区块，把活动风险和非交付类就绪检查统一成风险数、阻塞项和警告项。这里可以重新运行本地检查、查看最近检查回执、打开 `STATUS.md`、在缺失服务 worktree 时进入确认创建流程，或复制一段专门用于风险复核的 Codex Prompt。检查列表不是只读摘要：服务范围、目标分支、worktree、状态、任务和 SQL 产物问题会分别路由到对应文档、worktree 创建或交付记录入口。

工作区详情还包含 `Documents` 文档入口，可直接打开 `workspace.md`、`STATUS.md`、`services.md`、`branches.md`、`tasks.md`、`交付记录.md`、`handoff.md`、`bootstrap-report.md` 和 `scripts/worktree-commands.sh`。这些入口不再只是文件列表，而是轻量证据地图：每张卡都会展示文档职责、更新时间、参与的 gate 和创建策略。同一区块会把扫描到的 `sql/*.sql` 文件单独列成 `SQL 产物 / SQL artifacts`，正式 SQL 和回滚 SQL 都能在应用内用源码模式复查，不必回 Finder 找文件。当前打开的文档会高亮显示；文档预览区可以复制路径，也可以只关闭预览而保留工作区详情；如果标准文件缺失，文档区块会显示确认创建入口，Nexus 只创建缺失骨架、不覆盖已有文件，并在创建后刷新工作区、打开新文档、显示本地写入反馈；动态 SQL 文件只作为复查入口，不会通过缺失文档恢复流程自动生成；如果文件不可读，则继续提供失败原因、目标路径、重试、复制路径和 Finder 入口。切换工作区时会清理旧文档预览，避免误看其他工作区的文件。

已归档工作区仍会保留在工作区列表和“归档”筛选中，但不会再计入菜单栏活跃统计、任务中心总数和自动化提醒信号。恢复工作区必须显式点击归档确认计划中的“恢复开发”，确认写回生命周期后才会重新进入活跃检查。

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
npm run env:check
npm run verify
```

如果只改文档或样例数据，可以先跑较快的公开预览基线：

```bash
npm run test
npm run build
npm run privacy:check
```

## 小组件状态

主应用已经实现小组件快照写入，并注册了 `nexus://` URL Scheme。原生壳会写入 Application Support，处理 `nexus://workspace/<folder>` 聚焦跳转，并在应用配置了 App Group entitlement 后同步写入 `group.com.ks.nexus`。WidgetKit 源码位于：

```text
native/NexusWidget/
```

如果要真正打包和分发 `.appex` 小组件，还需要完整的 Xcode 工程、Widget Extension Target、App Group 配置、签名和 notarization。更多说明见 [widget/README.md](widget/README.md)。

## 文档

- [完整产品形态](docs/product-shape.zh-CN.md)
- [Swift Native-only 路线图](docs/native-swift-only-roadmap.md)
- [主流程契约](docs/main-workflow.md)
- [主流程审计](docs/main-workflow-audit.zh-CN.md)
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
