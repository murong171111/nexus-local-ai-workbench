import Foundation
import NexusBridge

enum NativeWorktreeSetupStore {
    static func setup(
        request: SetupWorktreesRequest,
        fileManager: FileManager = .default
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

        let workspaceURL = URL(fileURLWithPath: (request.workspacePath as NSString).expandingTildeInPath)
        guard let workspaceType = fileType(at: workspaceURL, fileManager: fileManager) else {
            throw NativeWorktreeSetupError.workspaceMissing(workspaceURL.path)
        }
        guard workspaceType != .typeSymbolicLink else {
            throw NativeWorktreeSetupError.workspaceSymbolicLink(workspaceURL.path)
        }
        guard workspaceType == .typeDirectory else {
            throw NativeWorktreeSetupError.workspaceNotDirectory(workspaceURL.path)
        }

        let reposURL = workspaceURL.appendingPathComponent("repos", isDirectory: true)
        if let reposType = fileType(at: reposURL, fileManager: fileManager),
           reposType != .typeDirectory {
            throw NativeWorktreeSetupError.worktreeRootNotDirectory(reposURL.path)
        }

        let sourceRootURL = URL(fileURLWithPath: (request.sourceReposRoot as NSString).expandingTildeInPath)
        var created: [WorktreeSetupResult] = []
        var skipped: [WorktreeSetupResult] = []
        var failed: [WorktreeSetupResult] = []

        for service in services {
            let sourceURL = sourceRootURL.appendingPathComponent(service, isDirectory: true)
            let worktreeURL = reposURL.appendingPathComponent(service, isDirectory: true)
            guard isSafeServiceName(service) else {
                failed.append(result(service: service, sourceURL: sourceURL, worktreeURL: worktreeURL, status: "failed", detail: "service name must be a single safe path segment"))
                continue
            }
            if let worktreeType = fileType(at: worktreeURL, fileManager: fileManager) {
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

            if fileType(at: reposURL, fileManager: fileManager) == nil {
                try fileManager.createDirectory(at: reposURL, withIntermediateDirectories: false)
            }
            guard fileType(at: reposURL, fileManager: fileManager) == .typeDirectory else {
                throw NativeWorktreeSetupError.worktreeRootNotDirectory(reposURL.path)
            }
            if let currentTargetType = fileType(at: worktreeURL, fileManager: fileManager) {
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

            switch runGit(["worktree", "add", worktreeURL.path, targetBranch], in: sourceURL) {
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
            command: command(workspaceURL: workspaceURL, sourceReposRoot: request.sourceReposRoot, services: services, targetBranch: targetBranch),
            created: created,
            skipped: skipped,
            failed: failed
        )
        let audit = appendAuditEvent(request: request, response: response)
        return SetupWorktreesResponse(
            workspacePath: response.workspacePath,
            targetBranch: response.targetBranch,
            command: response.command,
            created: response.created,
            skipped: response.skipped,
            failed: response.failed,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path
        )
    }

    private static func appendAuditEvent(
        request: SetupWorktreesRequest,
        response: SetupWorktreesResponse
    ) -> AppendAuditEventResponse? {
        guard let auditRoot = request.auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return nil
        }
        return try? NativeAuditEventStore.append(
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
        targetBranch: String
    ) -> String {
        services.map { service in
            let sourcePath = "\(sourceReposRoot)/\(service)"
            let worktreePath = workspaceURL
                .appendingPathComponent("repos", isDirectory: true)
                .appendingPathComponent(service, isDirectory: true)
                .path
            return "# \(service)\ngit -C '\(sourcePath)' fetch origin\ngit -C '\(sourcePath)' worktree add '\(worktreePath)' '\(targetBranch)'"
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
