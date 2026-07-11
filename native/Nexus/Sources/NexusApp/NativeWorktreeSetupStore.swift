import Foundation
import NexusBridge

struct NativeWorktreeSetupPlan: Equatable {
    let workspacePath: String
    let sourceReposRoot: String
    let services: [String]
    let targetBranch: String
    let sourceRevisions: [String: String]
    let branchCreationBases: [String: NativeBranchCreationBase]
    let auditRoot: String?
    let actor: String?

    var summary: String {
        let branchDetail = branchCreationBases.isEmpty
            ? "复用已有目标分支"
            : "为 \(branchCreationBases.keys.sorted().joined(separator: ", ")) 创建目标分支"
        return "确认后将在 \(workspacePath)/repos/ 为 \(services.joined(separator: ", ")) 创建 \(targetBranch) worktree；\(branchDetail)，每个 source commit 已冻结。"
    }
}

struct NativeBranchCreationBase: Equatable {
    let reference: String
    let revision: String
}

enum NativeWorktreeSetupStore {
    static func makePlan(
        request: SetupWorktreesRequest,
        fileManager: FileManager = .default
    ) throws -> NativeWorktreeSetupPlan {
        let targetBranch = normalizedGitBranch(request.targetBranch)
        guard isConfirmedTargetBranch(targetBranch) else {
            throw NativeWorktreeSetupError.unconfirmedBranch
        }
        let services = normalizedServices(request.services)
        guard !services.isEmpty else {
            throw NativeWorktreeSetupError.noServices
        }

        let workspaceURL = expandedURL(for: request.workspacePath)
        try validateWorkspace(workspaceURL, fileManager: fileManager)
        let reposURL = workspaceURL.appendingPathComponent("repos", isDirectory: true)
        try validateReposRoot(reposURL, fileManager: fileManager)
        let sourceRootURL = expandedURL(for: request.sourceReposRoot)
        var sourceRevisions: [String: String] = [:]
        var branchCreationBases: [String: NativeBranchCreationBase] = [:]

        for service in services {
            guard isSafeServiceName(service) else {
                throw NativeWorktreeSetupError.unsafeServiceName(service)
            }
            let sourceURL = sourceRootURL.appendingPathComponent(service, isDirectory: true)
            let worktreeURL = reposURL.appendingPathComponent(service, isDirectory: true)
            guard fileType(at: sourceURL, fileManager: fileManager) == .typeDirectory else {
                throw NativeWorktreeSetupError.sourceNotDirectory(service, sourceURL.path)
            }
            guard fileManager.fileExists(atPath: sourceURL.appendingPathComponent(".git").path) else {
                throw NativeWorktreeSetupError.sourceNotGit(service, sourceURL.path)
            }
            guard fileType(at: worktreeURL, fileManager: fileManager) == nil else {
                throw NativeWorktreeSetupError.targetChangedSinceConfirmation(service, worktreeURL.path)
            }
            if let revision = branchRevision(targetBranch, in: sourceURL) {
                sourceRevisions[service] = revision
            } else if let base = defaultBranchCreationBase(in: sourceURL) {
                sourceRevisions[service] = base.revision
                branchCreationBases[service] = base
            } else {
                throw NativeWorktreeSetupError.branchRevisionUnavailable(service, targetBranch)
            }
        }

        return NativeWorktreeSetupPlan(
            workspacePath: workspaceURL.path,
            sourceReposRoot: sourceRootURL.path,
            services: services,
            targetBranch: targetBranch,
            sourceRevisions: sourceRevisions,
            branchCreationBases: branchCreationBases,
            auditRoot: request.auditRoot,
            actor: request.actor
        )
    }

    static func setup(
        plan: NativeWorktreeSetupPlan,
        confirmed: Bool,
        fileManager: FileManager = .default
    ) throws -> SetupWorktreesResponse {
        guard confirmed else {
            throw NativeWorktreeSetupError.unconfirmed
        }
        let currentPlan = try makePlan(
            request: request(from: plan, confirmed: false),
            fileManager: fileManager
        )
        guard currentPlan.sourceRevisions == plan.sourceRevisions,
              currentPlan.branchCreationBases == plan.branchCreationBases else {
            throw NativeWorktreeSetupError.planChangedSinceConfirmation
        }
        return try execute(
            request: request(from: plan, confirmed: true),
            expectedSourceRevisions: plan.sourceRevisions,
            expectedBranchCreationBases: plan.branchCreationBases,
            fileManager: fileManager
        )
    }

    static func setup(
        request: SetupWorktreesRequest,
        fileManager: FileManager = .default
    ) throws -> SetupWorktreesResponse {
        try execute(
            request: request,
            expectedSourceRevisions: nil,
            expectedBranchCreationBases: nil,
            fileManager: fileManager
        )
    }

    private static func execute(
        request: SetupWorktreesRequest,
        expectedSourceRevisions: [String: String]?,
        expectedBranchCreationBases: [String: NativeBranchCreationBase]?,
        fileManager: FileManager
    ) throws -> SetupWorktreesResponse {
        guard request.confirmed else {
            throw NativeWorktreeSetupError.unconfirmed
        }
        let targetBranch = normalizedGitBranch(request.targetBranch)
        guard isConfirmedTargetBranch(targetBranch) else {
            throw NativeWorktreeSetupError.unconfirmedBranch
        }
        let services = normalizedServices(request.services)
        guard !services.isEmpty else {
            throw NativeWorktreeSetupError.noServices
        }

        let workspaceURL = expandedURL(for: request.workspacePath)
        try validateWorkspace(workspaceURL, fileManager: fileManager)

        let reposURL = workspaceURL.appendingPathComponent("repos", isDirectory: true)
        try validateReposRoot(reposURL, fileManager: fileManager)

        let sourceRootURL = expandedURL(for: request.sourceReposRoot)
        var created: [WorktreeSetupResult] = []
        var skipped: [WorktreeSetupResult] = []
        var failed: [WorktreeSetupResult] = []
        var branchCreationBasesUsed: [String: NativeBranchCreationBase] = [:]

        for service in services {
            let sourceURL = sourceRootURL.appendingPathComponent(service, isDirectory: true)
            let worktreeURL = reposURL.appendingPathComponent(service, isDirectory: true)
            guard isSafeServiceName(service) else {
                failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "service name must be a single safe path segment"))
                continue
            }
            if let worktreeType = fileType(at: worktreeURL, fileManager: fileManager) {
                if expectedSourceRevisions?[service] != nil {
                    failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "worktree path changed since confirmation"))
                    continue
                }
                guard worktreeType == .typeDirectory else {
                    failed.append(result(
                        service: service,
                        sourceURL: sourceURL,
                        worktreeURL: worktreeURL,
                        status: "failed",
                        detail: "worktree path is not a real directory; symbolic links and files are not trusted"
                    ))
                    continue
                }
                skipped.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "skipped", detail: "worktree path already exists"))
                continue
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "source repository does not exist"))
                continue
            }
            guard fileManager.fileExists(atPath: sourceURL.appendingPathComponent(".git").path) else {
                failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "source path is not a git worktree"))
                continue
            }

            switch runGit(["fetch", "origin"], in: sourceURL) {
            case .success:
                break
            case .failure(let detail):
                failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "git fetch failed: \(detail)"))
                continue
            }

            if let expectedBase = expectedBranchCreationBases?[service] {
                guard branchRevision(targetBranch, in: sourceURL) == nil,
                      revision(expectedBase.reference, in: sourceURL) == expectedBase.revision else {
                    failed.append(result(
                        service: service,
                        sourceURL: sourceURL,
                        worktreeURL: worktreeURL,
                        status: "failed",
                        detail: "branch creation base changed since confirmation; refresh and confirm the worktree plan again"
                    ))
                    continue
                }
            } else if let expectedRevision = expectedSourceRevisions?[service],
                      branchRevision(targetBranch, in: sourceURL) != expectedRevision {
                    failed.append(result(
                        service: service,
                        sourceURL: sourceURL,
                        worktreeURL: worktreeURL,
                        status: "failed",
                        detail: "target branch changed since confirmation; refresh and confirm the worktree plan again"
                    ))
                    continue
            }

            if fileType(at: reposURL, fileManager: fileManager) == nil {
                try fileManager.createDirectory(at: reposURL, withIntermediateDirectories: false)
            }
            guard fileType(at: reposURL, fileManager: fileManager) == .typeDirectory else {
                throw NativeWorktreeSetupError.worktreeRootNotDirectory(reposURL.path)
            }
            if let currentTargetType = fileType(at: worktreeURL, fileManager: fileManager) {
                if expectedSourceRevisions?[service] != nil {
                    failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "worktree path changed since confirmation"))
                    continue
                }
                if currentTargetType == .typeDirectory {
                    skipped.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "skipped", detail: "worktree path appeared before creation"))
                } else {
                    failed.append(result(
                        service: service,
                        sourceURL: sourceURL,
                        worktreeURL: worktreeURL,
                        status: "failed",
                        detail: "worktree path changed before creation; symbolic links and files are not trusted"
                    ))
                }
                continue
            }

            let branchCreationBase = expectedBranchCreationBases?[service]
                ?? (branchRevision(targetBranch, in: sourceURL) == nil ? defaultBranchCreationBase(in: sourceURL) : nil)
            let worktreeArguments: [String]
            if let branchCreationBase {
                worktreeArguments = ["worktree", "add", "-b", targetBranch, worktreeURL.path, branchCreationBase.revision]
                branchCreationBasesUsed[service] = branchCreationBase
            } else {
                worktreeArguments = ["worktree", "add", worktreeURL.path, targetBranch]
            }

            switch runGit(worktreeArguments, in: sourceURL) {
            case .success(let output):
                created.append(result(
                    service: service,
                    sourceURL: sourceURL,
                    worktreeURL: worktreeURL,
                    status: "created",
                    detail: output.isEmpty ? "worktree created" : output
                ))
            case .failure(let detail):
                failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "git worktree add failed: \(detail)"))
            }
        }

        let response = SetupWorktreesResponse(
            workspacePath: workspaceURL.path,
            targetBranch: targetBranch,
            command: command(
                workspaceURL: workspaceURL,
                sourceReposRoot: request.sourceReposRoot,
                services: services,
                targetBranch: targetBranch,
                branchCreationBases: branchCreationBasesUsed
            ),
            created: created,
            skipped: skipped,
            failed: failed
        )
        let audit: AppendAuditEventResponse?
        let auditError: String?
        do {
            audit = try appendAuditEvent(request: request, response: response)
            auditError = nil
        } catch {
            audit = nil
            auditError = error.localizedDescription
        }
        return SetupWorktreesResponse(
            workspacePath: response.workspacePath,
            targetBranch: response.targetBranch,
            command: response.command,
            created: response.created,
            skipped: response.skipped,
            failed: response.failed,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path,
            auditError: auditError
        )
    }

    private static func appendAuditEvent(
        request: SetupWorktreesRequest,
        response: SetupWorktreesResponse
    ) throws -> AppendAuditEventResponse? {
        guard let auditRoot = request.auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return nil
        }
        return try NativeAuditEventStore.append(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: request.actor ?? "Nexus Native",
                action: "worktree_setup.executed",
                target: response.workspacePath,
                summary: "Created \(response.created.count), skipped \(response.skipped.count), failed \(response.failed.count) workspace-local worktrees",
                metadata: [
                    "workspace": response.workspacePath,
                    "targetBranch": response.targetBranch,
                    "created": "\(response.created.count)",
                    "skipped": "\(response.skipped.count)",
                    "failed": "\(response.failed.count)",
                    "createdServices": response.created.map(\.service).joined(separator: ","),
                    "skippedServices": response.skipped.map(\.service).joined(separator: ","),
                    "failedServices": response.failed.map(\.service).joined(separator: ",")
                ]
            )
        )
    }

    private static func normalizedServices(_ services: [String]) -> [String] {
        Array(Set(services.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func validateWorkspace(_ url: URL, fileManager: FileManager) throws {
        guard let workspaceType = fileType(at: url, fileManager: fileManager) else {
            throw NativeWorktreeSetupError.workspaceMissing(url.path)
        }
        guard workspaceType != .typeSymbolicLink else {
            throw NativeWorktreeSetupError.workspaceSymbolicLink(url.path)
        }
        guard workspaceType == .typeDirectory else {
            throw NativeWorktreeSetupError.workspaceNotDirectory(url.path)
        }
    }

    private static func validateReposRoot(_ url: URL, fileManager: FileManager) throws {
        if let reposType = fileType(at: url, fileManager: fileManager),
           reposType != .typeDirectory {
            throw NativeWorktreeSetupError.worktreeRootNotDirectory(url.path)
        }
    }

    private static func request(
        from plan: NativeWorktreeSetupPlan,
        confirmed: Bool
    ) -> SetupWorktreesRequest {
        SetupWorktreesRequest(
            workspacePath: plan.workspacePath,
            sourceReposRoot: plan.sourceReposRoot,
            services: plan.services,
            targetBranch: plan.targetBranch,
            confirmed: confirmed,
            auditRoot: plan.auditRoot,
            actor: plan.actor
        )
    }

    private static func branchRevision(_ branch: String, in sourceURL: URL) -> String? {
        for reference in [branch, "origin/\(branch)"] {
            switch runGit(["rev-parse", "--verify", "\(reference)^{commit}"], in: sourceURL) {
            case .success(let revision) where !revision.isEmpty:
                return revision
            case .success, .failure:
                continue
            }
        }
        return nil
    }

    private static func defaultBranchCreationBase(in sourceURL: URL) -> NativeBranchCreationBase? {
        for reference in ["origin/HEAD", "HEAD"] {
            if let revision = revision(reference, in: sourceURL) {
                return NativeBranchCreationBase(reference: reference, revision: revision)
            }
        }
        return nil
    }

    private static func revision(_ reference: String, in sourceURL: URL) -> String? {
        switch runGit(["rev-parse", "--verify", "\(reference)^{commit}"], in: sourceURL) {
        case .success(let revision) where !revision.isEmpty:
            return revision
        case .success, .failure:
            return nil
        }
    }

    private static func fileType(at url: URL, fileManager: FileManager) -> FileAttributeType? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.type] as? FileAttributeType
    }

    private static func isSafeServiceName(_ service: String) -> Bool {
        guard !service.isEmpty,
              service != ".",
              service != "..",
              !service.contains("/"),
              !service.contains("\\") else {
            return false
        }
        return service.rangeOfCharacter(from: CharacterSet(charactersIn: "\0")) == nil
    }

    private static func isConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("todo")
            && !normalized.contains("tbd")
            && !normalized.contains("unknown")
    }

    private static func normalizedGitBranch(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("## ")
            .split(separator: "...")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func result(
        service: String,
        sourceURL: URL,
        worktreeURL: URL,
        status: String,
        detail: String
    ) -> WorktreeSetupResult {
        WorktreeSetupResult(
            service: service,
            sourcePath: sourceURL.path,
            worktreePath: worktreeURL.path,
            status: status,
            detail: detail
        )
    }

    private static func command(
        workspaceURL: URL,
        sourceReposRoot: String,
        services: [String],
        targetBranch: String,
        branchCreationBases: [String: NativeBranchCreationBase]
    ) -> String {
        services.map { service in
            let sourcePath = "\(sourceReposRoot)/\(service)"
            let worktreePath = workspaceURL
                .appendingPathComponent("repos", isDirectory: true)
                .appendingPathComponent(service, isDirectory: true)
                .path
            let worktreeCommand = if let base = branchCreationBases[service] {
                "git -C '\(sourcePath)' worktree add -b '\(targetBranch)' '\(worktreePath)' '\(base.revision)'"
            } else {
                "git -C '\(sourcePath)' worktree add '\(worktreePath)' '\(targetBranch)'"
            }
            return "# \(service)\ngit -C '\(sourcePath)' fetch origin\n\(worktreeCommand)"
        }
        .joined(separator: "\n\n")
    }

    private static func runGit(_ arguments: [String], in directory: URL) -> NativeGitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(error.localizedDescription)
        }
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            return .failure(errorOutput.isEmpty ? output : errorOutput)
        }
        return .success(output)
    }
}

private enum NativeGitCommandResult {
    case success(String)
    case failure(String)
}

private enum NativeWorktreeSetupError: LocalizedError {
    case unconfirmed
    case unconfirmedBranch
    case workspaceMissing(String)
    case workspaceSymbolicLink(String)
    case workspaceNotDirectory(String)
    case worktreeRootNotDirectory(String)
    case unsafeServiceName(String)
    case sourceNotDirectory(String, String)
    case sourceNotGit(String, String)
    case branchRevisionUnavailable(String, String)
    case targetChangedSinceConfirmation(String, String)
    case planChangedSinceConfirmation
    case noServices

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "worktree setup requires explicit confirmation"
        case .unconfirmedBranch:
            return "target branch must be confirmed before creating worktrees"
        case .workspaceMissing(let path):
            return "workspace does not exist: \(path)"
        case .workspaceSymbolicLink(let path):
            return "workspace must be a real directory; symbolic links are not allowed: \(path)"
        case .workspaceNotDirectory(let path):
            return "workspace is not a directory: \(path)"
        case .worktreeRootNotDirectory(let path):
            return "worktree root must be a real directory; symbolic links and files are not allowed: \(path)"
        case .unsafeServiceName(let service):
            return "service name must be a single safe path segment: \(service)"
        case .sourceNotDirectory(let service, let path):
            return "source repository must be a real directory for \(service): \(path)"
        case .sourceNotGit(let service, let path):
            return "source path is not a git worktree for \(service): \(path)"
        case .branchRevisionUnavailable(let service, let branch):
            return "target branch revision is unavailable for \(service): \(branch)"
        case .targetChangedSinceConfirmation(let service, let path):
            return "worktree target changed since confirmation for \(service): \(path)"
        case .planChangedSinceConfirmation:
            return "worktree source revisions changed since confirmation; refresh and confirm the plan again"
        case .noServices:
            return "no services selected for worktree setup"
        }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
