# Nexus 新窗口接续文档

日期：2026-06-17

这份文档不是产品总路线图，而是给下一次新窗口继续开发时直接使用的接续材料。目标是减少重新解释上下文的成本，让新窗口先读这份文档就能接上当前工作。

## 1. 当前产品方向

当前 Nexus 的产品方向已经明确：

- 主产品线是 `Native Mac`。
- 新的产品工作流功能优先写在 `Swift / SwiftUI / AppKit / WidgetKit`。
- `React / Tauri / Rust / TypeScript` 现在主要作为 legacy 预览、迁移参考、关键修复和构建支撑，不再承接新的主功能设计。

当前路线图以这两份文档为准：

- `docs/native-swift-only-roadmap.md`
- `docs/main-workflow.md`

## 2. 当前代码基线

仓库：

- `ks_project/workspaces/dashboard`

当前 Git 基线：

- `main` 已同步到最新远端。
- 最近已经合并两轮 Native Board 相关改动。

最近完成的关键 PR：

1. `#186 Add native workspace board surface`
   - Native SwiftUI 增加 `Console / Board` 双入口。
   - `Board` 以主流程阶段分列展示工作区。
   - 点击 Board 卡片会回到 Console 并聚焦对应工作区。

2. `#187 Add native board scope controls`
   - Board 内增加 `全部 / 需处理 / 交付 / 归档` 范围切换。
   - 增加 visible/total 计数和更准确的空状态文案。
   - 卡片增加 worktree 摘要，便于快速分流。

## 3. 当前已经稳定下来的能力

Native 主链路里，下面这些能力已经具备基础可用性：

- 工作区创建、源仓库扫描、预检、确认写入、初始化回执。
- `需求预检` 固定目录初始化和状态读取。
- `范围冻结`、服务/分支确认、worktree readiness、开发任务、交付检查、归档门禁的主阶段模型。
- Command Center、Workflow、Risk Review、Documents Hub、Task Center、Codex Sessions、Automation Action Center。
- 文档预览、SQL artifact 扫描、交付 SQL 正式/回滚文件守门。
- 本地检查、审计日志、Codex handoff、服务级 handoff、验证/PR handoff。

当前 Native 壳已经不是 demo，而是进入“收敛主链路”的阶段。

## 4. 当前最重要的目标

当前总目标不是继续横向扩功能，而是：

> 把 Native Mac 的 M1 主链路收敛成一条真正稳定的日常工作路径。

主链路是：

```text
新建工作区
  -> 需求预检
  -> 范围冻结
  -> 确认服务和分支
  -> worktree 准备
  -> 开发任务
  -> 交付检查
  -> 归档
```

当前窗口接续目标建议定为：

> 继续做 `Board` 的可操作性增强，但始终保持 `Console` 才是执行面，`Board` 只是分流和俯视面板。

也就是说，下一轮应继续加强 Board 的“发现问题并跳回 Console”的能力，而不是把 Board 做成第二套工作流。

## 5. 下一窗口建议优先做的内容

下一窗口建议只做一小轮，优先顺序如下：

1. 给 Board 卡片增加更直接的轻操作入口。
   - 例如：快速打开文档、快速打开工作区、快速进入本地检查或定位到当前 blocker。
   - 原则：动作只做跳转和分流，不在 Board 里承载复杂写入。

2. 让 Board 更清楚地区分几类工作区。
   - `阻塞`
   - `待处理`
   - `待交付`
   - `已归档`
   - 可以继续优化卡片摘要和列头提示，但不要复制一遍 Console 的详情内容。

3. 把 Board 和主路径术语继续对齐。
   - Board 中出现的状态、下一步、原因，必须复用 `WorkspaceMainStage` 的同一套语义。
   - 不要在 Board 里发明新的状态词。

4. 保持验证闭环。
   - 每轮完成后都运行：
   - `swift test --package-path native/Nexus`
   - `npm run verify`

## 6. 当前不要做的事情

下一窗口先不要继续扩这些方向：

- 不要再给 React/Tauri 版本加新的主功能。
- 不要让 Board 变成第二个 Command Center。
- 不要引入直接调用 AI 的能力。
- 不要先做 iPad/iPhone 扩展。
- 不要先做正式分发、签名、notarization、自动更新。
- 不要把新的主流程规则继续写进 Rust/TypeScript 作为首发实现。

## 7. 新窗口工作方式

新窗口建议沿用这套起手流程：

1. 先确认仓库在 `main` 且工作区干净。
2. 先读：
   - `docs/plans/2026-06-17-native-next-window-handoff.zh-CN.md`
   - `docs/main-workflow.md`
   - `docs/native-swift-only-roadmap.md`
3. 从最新 `main` 创建新分支：
   - `chen/<功能名>`
4. 新功能优先落在：
   - `native/Nexus/Sources/NexusApp`
   - 如需同步测试：
   - `native/Nexus/Tests/NexusAppTests`
5. 完成后运行验证，再开 PR。

## 8. 可直接贴给新窗口的提示词

下面这段可以直接作为新窗口的开场提示：

```text
继续迭代 Nexus Native Mac 主链路。先阅读：

1. docs/plans/2026-06-17-native-next-window-handoff.zh-CN.md
2. docs/main-workflow.md
3. docs/native-swift-only-roadmap.md

当前方向：
- 新的产品工作流功能只继续做在 Native Swift/SwiftUI/AppKit。
- React/Tauri/Rust/TypeScript 只作为 legacy 参考和关键修复，不新增主功能。

当前基线：
- main 已经合并 #186 和 #187。
- #186 做了 Console / Board 双入口。
- #187 做了 Board 的 All / Attention / Delivery / Archive scope 和卡片 worktree 摘要。

本轮目标：
- 继续增强 Board 的可操作性，但保持 Board 是分流面板，Console 才是执行面。
- 优先做轻操作入口、状态摘要和跳回 Console 的链路，不要把 Board 做成第二套工作流。

实现要求：
- 先检查 git 状态和当前分支。
- 从最新 main 新建 chen/<feature> 分支。
- 改动优先放在 native/Nexus/Sources/NexusApp。
- 补必要的 Swift 测试。
- 完成后运行：
  - swift test --package-path native/Nexus
  - npm run verify
```

## 9. 一句话目标

如果新窗口只保留一句目标，就用这句：

> 继续把 Nexus Native 做成“一个真实需求可以从建档一路走到交付归档”的 Mac 工作台，而不是继续横向堆功能。
