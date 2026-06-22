import Foundation

enum NativeDistributionRequirement: String, CaseIterable, Hashable {
    case installTarget
    case widgetExtension
    case legacyDeletion
    case releaseReadiness

    var label: String {
        switch self {
        case .installTarget:
            return "安装目标 / Install target"
        case .widgetExtension:
            return "WidgetKit 目标 / Widget target"
        case .legacyDeletion:
            return "Legacy 删除 / Legacy deletion"
        case .releaseReadiness:
            return "发布就绪 / Release readiness"
        }
    }
}

struct NativeDistributionCheck: Hashable, Identifiable {
    let requirement: NativeDistributionRequirement
    let status: WorkflowPathStatus
    let detail: String
    let evidence: [String]

    var id: NativeDistributionRequirement { requirement }
}

struct NativeDistributionReadinessEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let checks: [NativeDistributionCheck]

    var ready: Bool {
        status == .ready
    }

    var readinessSummary: String {
        "\(checks.filter { $0.status == .ready }.count)/\(checks.count) Ready checks"
    }

    static func resolve(
        repositoryRoot: String,
        m1Ready: Bool,
        m2Ready: Bool,
        realLifecycleProven: Bool,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        directoryExists: (String) -> Bool = { path in
            var isDirectory = ObjCBool(false)
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        },
        fileContains: (String, String) -> Bool = { path, needle in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return text.contains(needle)
        }
    ) -> NativeDistributionReadinessEvidence {
        let checks = [
            installTargetCheck(repositoryRoot: repositoryRoot, fileExists: fileExists),
            widgetExtensionCheck(
                repositoryRoot: repositoryRoot,
                fileExists: fileExists,
                directoryExists: directoryExists,
                fileContains: fileContains
            ),
            legacyDeletionCheck(
                repositoryRoot: repositoryRoot,
                m1Ready: m1Ready,
                m2Ready: m2Ready,
                realLifecycleProven: realLifecycleProven,
                directoryExists: directoryExists,
                fileExists: fileExists,
                fileContains: fileContains
            ),
            releaseReadinessCheck(
                repositoryRoot: repositoryRoot,
                m1Ready: m1Ready,
                m2Ready: m2Ready,
                fileExists: fileExists,
                fileContains: fileContains
            )
        ]
        let blockers = checks.filter { $0.status == .blocked }
        let status: WorkflowPathStatus = blockers.isEmpty ? .ready : .blocked
        let reason = blockers.isEmpty
            ? "M3 Native Distribution 已具备安装目标、Widget Extension、legacy 删除条件和发布证据。"
            : "M3 仍有 \(blockers.count) 个分发条件未满足：\(blockers.map { $0.requirement.label }.joined(separator: ", "))。"
        return NativeDistributionReadinessEvidence(status: status, reason: reason, checks: checks)
    }

    private static func installTargetCheck(
        repositoryRoot: String,
        fileExists: (String) -> Bool
    ) -> NativeDistributionCheck {
        let packagePath = "\(repositoryRoot)/native/Nexus/Package.swift"
        let xcodeProjectPath = "\(repositoryRoot)/native/Nexus/Nexus.xcodeproj/project.pbxproj"
        let bundleScriptPath = "\(repositoryRoot)/native/Nexus/Scripts/build-app-bundle.sh"
        let bundleInfoPath = "\(repositoryRoot)/native/Nexus/Packaging/Info.plist"
        let hasSwiftPackage = fileExists(packagePath)
        let hasXcodeAppTarget = fileExists(xcodeProjectPath)
        let hasSwiftPMBundleTarget = fileExists(bundleScriptPath) && fileExists(bundleInfoPath)
        let hasInstallableAppTarget = hasXcodeAppTarget || hasSwiftPMBundleTarget
        return NativeDistributionCheck(
            requirement: .installTarget,
            status: hasSwiftPackage && hasInstallableAppTarget ? .ready : .blocked,
            detail: hasSwiftPackage && hasInstallableAppTarget
                ? "Native app has a Swift package and installable app bundle path for local installation."
                : "SwiftPM executable 不等于可本地安装的 .app；需要 Xcode app target 或等价安装证据后，Native 才能替代 Tauri bundle。",
            evidence: [packagePath, xcodeProjectPath, bundleScriptPath, bundleInfoPath]
        )
    }

    private static func widgetExtensionCheck(
        repositoryRoot: String,
        fileExists: (String) -> Bool,
        directoryExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeDistributionCheck {
        let legacyWidgetSource = "\(repositoryRoot)/widget/NexusWidget/NexusWidget.swift"
        let nativeWidgetSource = "\(repositoryRoot)/native/NexusWidget/Sources/NexusWidget/NexusWidget.swift"
        let nativeWidgetInfo = "\(repositoryRoot)/native/NexusWidget/Info.plist"
        let nativeWidgetEntitlements = "\(repositoryRoot)/native/NexusWidget/NexusWidget.entitlements"
        let hasWidgetSource = fileExists(legacyWidgetSource) || fileExists(nativeWidgetSource)
        let hasNativeWidgetTarget = directoryExists("\(repositoryRoot)/native/NexusWidget")
            && fileExists(nativeWidgetSource)
            && fileExists(nativeWidgetInfo)
            && fileExists(nativeWidgetEntitlements)
            && fileContains(nativeWidgetInfo, "com.apple.widgetkit-extension")
            && fileContains(nativeWidgetEntitlements, "group.com.ks.nexus")
        let ready = hasWidgetSource && hasNativeWidgetTarget
        return NativeDistributionCheck(
            requirement: .widgetExtension,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "WidgetKit source, extension plist, and App Group entitlements are attached to the Native target path."
                : "WidgetKit Swift source exists only as a standalone source file; add a native Widget Extension target before M3 can pass.",
            evidence: [legacyWidgetSource, nativeWidgetSource, nativeWidgetInfo, nativeWidgetEntitlements]
        )
    }

    private static func legacyDeletionCheck(
        repositoryRoot: String,
        m1Ready: Bool,
        m2Ready: Bool,
        realLifecycleProven: Bool,
        directoryExists: (String) -> Bool,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeDistributionCheck {
        let legacyDirectories = ["src", "src-tauri", "crates"].map { "\(repositoryRoot)/\($0)" }
        let retirementAuditPath = "\(repositoryRoot)/docs/legacy-retirement-audit.md"
        let legacyStillPresent = legacyDirectories.filter(directoryExists)
        let hasRetirementAudit = fileExists(retirementAuditPath)
            && fileContains(retirementAuditPath, "Native Deletion Order")
            && fileContains(retirementAuditPath, "Current Legacy Surfaces")
        let blockers = legacyDeletionBlockers(
            m1Ready: m1Ready,
            m2Ready: m2Ready,
            realLifecycleProven: realLifecycleProven,
            legacyStillPresent: legacyStillPresent,
            hasRetirementAudit: hasRetirementAudit,
            retirementAuditPath: retirementAuditPath
        )
        let ready = m1Ready && m2Ready && realLifecycleProven && legacyStillPresent.isEmpty
        return NativeDistributionCheck(
            requirement: .legacyDeletion,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Legacy Web/Tauri/Rust/TypeScript paths have been removed after Native proof."
                : "Legacy deletion blockers: \(blockers.joined(separator: " "))",
            evidence: legacyStillPresent.isEmpty ? legacyDirectories + [retirementAuditPath] : legacyStillPresent + [retirementAuditPath] + blockers
        )
    }

    private static func legacyDeletionBlockers(
        m1Ready: Bool,
        m2Ready: Bool,
        realLifecycleProven: Bool,
        legacyStillPresent: [String],
        hasRetirementAudit: Bool,
        retirementAuditPath: String
    ) -> [String] {
        var blockers: [String] = []
        if !m1Ready {
            blockers.append("M1 main workflow acceptance is not ready.")
        }
        if !m2Ready {
            blockers.append("M2 Native Local Core is not ready.")
        }
        if !realLifecycleProven {
            blockers.append("No real archived workspace lifecycle proof is available.")
        }
        if !legacyStillPresent.isEmpty {
            blockers.append("Legacy directories still exist: \(legacyStillPresent.joined(separator: ", ")).")
            if hasRetirementAudit {
                blockers.append("Next step: follow the Native deletion order in \(retirementAuditPath).")
            }
        }
        if !hasRetirementAudit {
            blockers.append("Legacy retirement audit is missing or incomplete: \(retirementAuditPath).")
        }
        return blockers
    }

    private static func releaseReadinessCheck(
        repositoryRoot: String,
        m1Ready: Bool,
        m2Ready: Bool,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeDistributionCheck {
        let distributionDoc = "\(repositoryRoot)/docs/distribution.md"
        let releaseDoc = "\(repositoryRoot)/docs/release-process.md"
        let ciWorkflow = "\(repositoryRoot)/.github/workflows/ci.yml"
        let releaseWorkflow = "\(repositoryRoot)/.github/workflows/release.yml"
        let hasDocs = fileExists(distributionDoc) && fileExists(releaseDoc)
        let ciMentionsSwift = fileContains(ciWorkflow, "swift test")
        let releaseMentionsNative = fileContains(releaseWorkflow, "native/Nexus")
            || fileContains(releaseWorkflow, "native:build")
            || fileContains(releaseWorkflow, "NexusNative")
        let distributionMentionsNative = fileContains(distributionDoc, "native/Nexus")
            || fileContains(distributionDoc, "NexusNative")
            || fileContains(distributionDoc, "Swift")
        let releaseDocMentionsNative = fileContains(releaseDoc, "native/Nexus")
            || fileContains(releaseDoc, "NexusNative")
            || fileContains(releaseDoc, "Swift")
        let releaseStillTauri = fileContains(releaseWorkflow, "tauri")
            || fileContains(releaseWorkflow, "src-tauri")
            || fileContains(releaseDoc, "Tauri")
            || fileContains(releaseDoc, "src-tauri")
            || fileContains(distributionDoc, "Tauri")
            || fileContains(distributionDoc, "src-tauri")
        let blockers = releaseReadinessBlockers(
            m1Ready: m1Ready,
            m2Ready: m2Ready,
            hasDocs: hasDocs,
            ciMentionsSwift: ciMentionsSwift,
            releaseMentionsNative: releaseMentionsNative,
            distributionMentionsNative: distributionMentionsNative,
            releaseDocMentionsNative: releaseDocMentionsNative,
            releaseStillTauri: releaseStillTauri
        )
        let ready = blockers.isEmpty
        return NativeDistributionCheck(
            requirement: .releaseReadiness,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Release docs, CI, and release workflow point at Swift-native artifacts."
                : "Release readiness blockers: \(blockers.joined(separator: " "))",
            evidence: [distributionDoc, releaseDoc, ciWorkflow, releaseWorkflow] + blockers
        )
    }

    private static func releaseReadinessBlockers(
        m1Ready: Bool,
        m2Ready: Bool,
        hasDocs: Bool,
        ciMentionsSwift: Bool,
        releaseMentionsNative: Bool,
        distributionMentionsNative: Bool,
        releaseDocMentionsNative: Bool,
        releaseStillTauri: Bool
    ) -> [String] {
        var blockers: [String] = []
        if !m1Ready {
            blockers.append("M1 main workflow acceptance is not ready.")
        }
        if !m2Ready {
            blockers.append("M2 Native Local Core is not ready.")
        }
        if !hasDocs {
            blockers.append("Distribution and release docs are missing.")
        }
        if !ciMentionsSwift {
            blockers.append("CI does not run Swift Native tests.")
        }
        if !releaseMentionsNative {
            blockers.append("Release workflow does not build a Native app artifact.")
        }
        if !distributionMentionsNative {
            blockers.append("Distribution docs do not describe the Native app path.")
        }
        if !releaseDocMentionsNative {
            blockers.append("Release process docs do not describe the Native app path.")
        }
        if releaseStillTauri {
            blockers.append("Release docs or workflows still point to Tauri artifacts.")
        }
        return blockers
    }
}
