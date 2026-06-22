import Foundation

struct WorkspaceSqlSummary: Hashable {
    let value: String
    let detail: String
    let status: WorkflowPathStatus
    let actionLabel: String

    init(workspace: WorkspaceSummary) {
        let sqlFileCount = workspace.sqlFiles.count
        if let sqlCheck = Self.sqlCheck(in: workspace) {
            detail = sqlCheck.detail
            switch sqlCheck.status.lowercased() {
            case "pass", "ok":
                value = sqlFileCount > 0 ? "已匹配" : "无变更"
                status = .ready
                actionLabel = sqlFileCount > 0 ? "打开 SQL" : "复查 SQL"
            case "fail", "blocked", "blocker":
                value = "缺产物"
                status = .blocked
                actionLabel = "SQL 交接"
            default:
                value = "需复核"
                status = .review
                actionLabel = "SQL 交接"
            }
            return
        }

        if sqlFileCount > 0 {
            value = "\(sqlFileCount) 文件"
            detail = "已有 SQL 文件，但尚未生成 SQL 目录检查。运行本地检查确认正式/回滚匹配。"
            status = .review
            actionLabel = "复查 SQL"
        } else {
            value = "待检查"
            detail = "暂未生成 SQL 目录检查，运行本地检查后可刷新。"
            status = .pending
            actionLabel = "运行检查"
        }
    }

    private static func sqlCheck(in workspace: WorkspaceSummary) -> WorkspaceHealthCheck? {
        workspace.healthChecks.first { check in
            check.id == "sql-directory" || check.action == "sql"
        }
    }
}

struct WorkspaceDocumentRole: Hashable {
    let key: String
    let purpose: String
    let updateTiming: String
    let gate: String
    let createPolicy: String
    let participatesInGate: Bool

    var gateLabel: String {
        participatesInGate ? gate : "参考 / Reference"
    }

    static func standard(for key: String) -> WorkspaceDocumentRole {
        standardRoles[key] ?? WorkspaceDocumentRole(
            key: key,
            purpose: "工作区补充资料或历史上下文。",
            updateTiming: "当该资料影响当前需求判断时更新。",
            gate: "handoff support",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: false
        )
    }

    static func sqlArtifact(for key: String) -> WorkspaceDocumentRole {
        WorkspaceDocumentRole(
            key: key,
            purpose: "正式 SQL、回滚 SQL 或 SQL 说明，用来证明数据库变更可交付、可回退。",
            updateTiming: "当交付记录声明真实 SQL 变更、回滚或数据处理时更新。",
            gate: "delivery_check, archived",
            createPolicy: "动态扫描条目，只读复查；Nexus 不会自动生成 SQL 产物。",
            participatesInGate: true
        )
    }

    private static let standardRoles: [String: WorkspaceDocumentRole] = [
        "workspace": WorkspaceDocumentRole(
            key: "workspace",
            purpose: "记录需求身份、工作区边界和生命周期上下文。",
            updateTiming: "创建工作区、生命周期写回或需求身份变化时更新。",
            gate: "created, archived",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "status": WorkspaceDocumentRole(
            key: "status",
            purpose: "汇总当前状态、风险、阻塞项和下一步说明。",
            updateTiming: "本地检查、生命周期变化或风险状态变化时更新。",
            gate: "all stages",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "services": WorkspaceDocumentRole(
            key: "services",
            purpose: "确认本次需求涉及的微服务范围。",
            updateTiming: "服务范围确认、追加或剔除时更新。",
            gate: "service_branch_confirm, worktree_setup",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "branches": WorkspaceDocumentRole(
            key: "branches",
            purpose: "记录目标分支、分支策略和例外说明。",
            updateTiming: "目标分支确认、分支策略变化或 branch mismatch 处理时更新。",
            gate: "service_branch_confirm, worktree_setup",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "requirements": WorkspaceDocumentRole(
            key: "requirements",
            purpose: "保留需求规则、业务约束和非蓝湖补充说明。",
            updateTiming: "需求规则被确认或补充时更新；蓝湖预检主产物仍在 `需求/` 下。",
            gate: "demand_intake support",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: false
        ),
        "acceptance": WorkspaceDocumentRole(
            key: "acceptance",
            purpose: "记录验收标准、验证口径和人工确认项。",
            updateTiming: "范围冻结、交付验证或 PR/CI 复核时更新。",
            gate: "scope_freeze, delivery_check",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "changes": WorkspaceDocumentRole(
            key: "changes",
            purpose: "记录范围变化、代码变化、文档整理和重要决策历史。",
            updateTiming: "范围变化、开发调整或交付整理时追加。",
            gate: "development, delivery_check",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "tasks": WorkspaceDocumentRole(
            key: "tasks",
            purpose: "唯一的工程执行任务来源，参与 Task Center 和交付阻塞判断。",
            updateTiming: "需求任务转入、开发拆分、完成、延期或阻塞处理时更新。",
            gate: "development, delivery_check",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "delivery": WorkspaceDocumentRole(
            key: "delivery",
            purpose: "记录真实代码、逻辑、配置、SQL、验证和 PR 交付证据。",
            updateTiming: "代码变更、SQL 变更、验证结果或交付补充时更新。",
            gate: "delivery_check, archived",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        ),
        "handoff": WorkspaceDocumentRole(
            key: "handoff",
            purpose: "保存 Codex 接力上下文、恢复线索和协作说明。",
            updateTiming: "需要跨会话继续需求、恢复历史上下文或交接给他人时更新。",
            gate: "handoff support",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: false
        ),
        "bootstrap": WorkspaceDocumentRole(
            key: "bootstrap",
            purpose: "保留工作区初始化回执、标准文件和初始服务/分支状态。",
            updateTiming: "工作区创建时生成；后续主要用于追溯。",
            gate: "created",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: false
        ),
        "worktreeScript": WorkspaceDocumentRole(
            key: "worktreeScript",
            purpose: "记录可审查的 workspace-local worktree 创建命令。",
            updateTiming: "服务范围或目标分支变化后需要重建 worktree 计划时更新。",
            gate: "worktree_setup",
            createPolicy: "缺失时可在确认后创建标准骨架。",
            participatesInGate: true
        )
    ]
}
