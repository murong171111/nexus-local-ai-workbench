import Foundation

enum NativeReleasePolicyRequirement: String, CaseIterable, Hashable {
    case releaseNotes
    case updaterDefault
    case settingsUpdateChannel
    case manifestMetadata
    case publicReleaseBlockers

    var label: String {
        switch self {
        case .releaseNotes:
            return "Release notes"
        case .updaterDefault:
            return "Updater default"
        case .settingsUpdateChannel:
            return "Settings update channel"
        case .manifestMetadata:
            return "Manifest metadata"
        case .publicReleaseBlockers:
            return "Public blockers"
        }
    }
}

struct NativeReleasePolicyCheck: Hashable, Identifiable {
    let requirement: NativeReleasePolicyRequirement
    let status: WorkflowPathStatus
    let detail: String
    let evidence: [String]

    var id: NativeReleasePolicyRequirement { requirement }
}

struct NativeReleasePolicyEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let checks: [NativeReleasePolicyCheck]

    var ready: Bool {
        status == .ready
    }

    var blockerDetails: [String] {
        checks
            .filter { $0.status == .blocked }
            .map(\.detail)
    }

    static func resolve(
        repositoryRoot: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileContains: (String, String) -> Bool = { path, needle in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return text.contains(needle)
        }
    ) -> NativeReleasePolicyEvidence {
        let releaseNotesDoc = "\(repositoryRoot)/docs/native-release-notes-and-updater.md"
        let releaseProcessDoc = "\(repositoryRoot)/docs/release-process.md"
        let distributionDoc = "\(repositoryRoot)/docs/distribution.md"
        let releaseManifestScript = "\(repositoryRoot)/native/Nexus/Scripts/generate-release-manifest.sh"
        let releaseBundleVerifierScript = "\(repositoryRoot)/native/Nexus/Scripts/verify-release-bundle.sh"
        let releaseNotesVerifierScript = "\(repositoryRoot)/native/Nexus/Scripts/verify-release-notes.sh"
        let releaseWorkflow = "\(repositoryRoot)/.github/workflows/release.yml"
        let appStateSource = "\(repositoryRoot)/native/Nexus/Sources/NexusApp/AppState.swift"
        let rootViewSource = "\(repositoryRoot)/native/Nexus/Sources/NexusApp/Views/RootView.swift"

        let checks = [
            releaseNotesCheck(
                releaseNotesDoc: releaseNotesDoc,
                releaseNotesVerifierScript: releaseNotesVerifierScript,
                releaseWorkflow: releaseWorkflow,
                fileExists: fileExists,
                fileContains: fileContains
            ),
            updaterDefaultCheck(
                releaseNotesDoc: releaseNotesDoc,
                fileExists: fileExists,
                fileContains: fileContains
            ),
            settingsUpdateChannelCheck(
                releaseNotesDoc: releaseNotesDoc,
                appStateSource: appStateSource,
                rootViewSource: rootViewSource,
                fileExists: fileExists,
                fileContains: fileContains
            ),
            manifestMetadataCheck(
                releaseManifestScript: releaseManifestScript,
                releaseBundleVerifierScript: releaseBundleVerifierScript,
                fileExists: fileExists,
                fileContains: fileContains
            ),
            publicReleaseBlockersCheck(
                releaseNotesDoc: releaseNotesDoc,
                releaseProcessDoc: releaseProcessDoc,
                distributionDoc: distributionDoc,
                fileExists: fileExists,
                fileContains: fileContains
            )
        ]

        let blockers = checks.filter { $0.status == .blocked }
        let status: WorkflowPathStatus = blockers.isEmpty ? .ready : .blocked
        let reason = blockers.isEmpty
            ? "Release notes, updater default, manual manifest metadata, and public-release blocker policy are ready."
            : "Release policy blockers: \(blockers.map(\.detail).joined(separator: " "))"
        return NativeReleasePolicyEvidence(status: status, reason: reason, checks: checks)
    }

    private static func releaseNotesCheck(
        releaseNotesDoc: String,
        releaseNotesVerifierScript: String,
        releaseWorkflow: String,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeReleasePolicyCheck {
        let requiredNeedles = [
            "Release Notes Gate",
            "version/tag",
            "native artifact names",
            "checksums",
            "signing/notarization status",
            "migration and rollback notes",
            "known blockers",
            "validation summary",
            "release manifest metadata",
            "manifest SHA-256 values"
        ]
        var missing = missingNeedles(requiredNeedles, path: releaseNotesDoc, fileContains: fileContains)
        let verifierNeedles = [
            "--notes",
            "--tag",
            "--assets-dir",
            "--manifest",
            "signing/notarization",
            "known blocker",
            "validation summary",
            "migration",
            "rollback",
            "nexus-native-*.dmg",
            ".dmg.sha256",
            "nexus-native-release-manifest.json",
            "manifest SHA-256",
            "checksum sidecar",
            "Release manifest sha256 must match checksum sidecar"
        ]
        missing.append(contentsOf: verifierNeedles
            .filter { !fileContains(releaseNotesVerifierScript, $0) }
            .map { "verify-release-notes.sh: \($0)" }
        )
        if !fileContains(releaseWorkflow, "verify-release-notes.sh") {
            missing.append("release.yml: verify-release-notes.sh")
        }
        let ready = fileExists(releaseNotesDoc)
            && fileExists(releaseNotesVerifierScript)
            && fileExists(releaseWorkflow)
            && missing.isEmpty
        return NativeReleasePolicyCheck(
            requirement: .releaseNotes,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Release notes gate lists and verifies version, artifacts, checksums, signing status, blockers, validation, manifest SHA-256 values, migration, and rollback requirements."
                : "Release notes gate is missing or incomplete: \(missing.joined(separator: ", ")).",
            evidence: [releaseNotesDoc, releaseNotesVerifierScript, releaseWorkflow] + missing
        )
    }

    private static func updaterDefaultCheck(
        releaseNotesDoc: String,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeReleasePolicyCheck {
        let requiredNeedles = [
            "Updater Gate",
            "Automatic updates disabled",
            "Do not enable automatic updates",
            "Settings exposes a user-visible update channel",
            "must not silently check for, download, or install updates"
        ]
        let missing = missingNeedles(requiredNeedles, path: releaseNotesDoc, fileContains: fileContains)
        let ready = fileExists(releaseNotesDoc) && missing.isEmpty
        return NativeReleasePolicyCheck(
            requirement: .updaterDefault,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Updater policy keeps automatic updates disabled until signing, metadata, settings, and rollback gates pass."
                : "Updater policy gate is missing or incomplete: \(missing.joined(separator: ", ")).",
            evidence: [releaseNotesDoc] + missing
        )
    }

    private static func manifestMetadataCheck(
        releaseManifestScript: String,
        releaseBundleVerifierScript: String,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeReleasePolicyCheck {
        let generatorNeedles = [
            "nexus-native-release-manifest.json",
            "manual-github-release",
            "automaticUpdatesEnabled",
            "\"automaticUpdatesEnabled\": False",
            "\"updateChannel\": \"manual-github-release\"",
            "does not enable automatic updates"
        ]
        let verifierNeedles = [
            "Release manifest sha256 must match checksum sidecar",
            "sidecar_checksums",
            "updateChannel",
            "automaticUpdatesEnabled"
        ]
        var missing = missingNeedles(generatorNeedles, path: releaseManifestScript, fileContains: fileContains)
        missing.append(contentsOf: verifierNeedles
            .filter { !fileContains(releaseBundleVerifierScript, $0) }
            .map { "verify-release-bundle.sh: \($0)" }
        )
        let ready = fileExists(releaseManifestScript)
            && fileExists(releaseBundleVerifierScript)
            && missing.isEmpty
        return NativeReleasePolicyCheck(
            requirement: .manifestMetadata,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Release manifest generation records the manual GitHub channel and automaticUpdatesEnabled=false, and verification matches manifest SHA-256 values to checksum sidecars."
                : "Release manifest metadata is missing or incomplete: \(missing.joined(separator: ", ")).",
            evidence: [releaseManifestScript, releaseBundleVerifierScript] + missing
        )
    }

    private static func settingsUpdateChannelCheck(
        releaseNotesDoc: String,
        appStateSource: String,
        rootViewSource: String,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeReleasePolicyCheck {
        let requiredSourceNeedles = [
            (appStateSource, "struct NativeUpdateChannelStatus"),
            (appStateSource, "manual-github-release"),
            (appStateSource, "automaticUpdatesEnabled: false"),
            (appStateSource, "nexus-native-release-manifest.json"),
            (appStateSource, "Manual download"),
            (appStateSource, "No silent update checks, downloads, or installs"),
            (rootViewSource, "NativeUpdateChannelStatusView"),
            (rootViewSource, "status.checkMode"),
            (rootViewSource, "status.automaticUpdatesLabel"),
            (rootViewSource, "status.manifestFilename"),
            (rootViewSource, "manual-github-release keeps automaticUpdatesEnabled=false"),
            (releaseNotesDoc, "Settings exposes a user-visible update channel")
        ]
        let missing = requiredSourceNeedles.compactMap { path, needle in
            fileContains(path, needle) ? nil : "\(path): \(needle)"
        }
        let ready = fileExists(releaseNotesDoc)
            && fileExists(appStateSource)
            && fileExists(rootViewSource)
            && missing.isEmpty
        return NativeReleasePolicyCheck(
            requirement: .settingsUpdateChannel,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Settings exposes the manual GitHub release channel, automaticUpdatesEnabled=false, manifest name, and no-silent-update policy."
                : "Settings update channel gate is missing or incomplete: \(missing.joined(separator: ", ")).",
            evidence: [releaseNotesDoc, appStateSource, rootViewSource] + missing
        )
    }

    private static func publicReleaseBlockersCheck(
        releaseNotesDoc: String,
        releaseProcessDoc: String,
        distributionDoc: String,
        fileExists: (String) -> Bool,
        fileContains: (String, String) -> Bool
    ) -> NativeReleasePolicyCheck {
        let docs = [releaseNotesDoc, releaseProcessDoc, distributionDoc]
        let docsExist = docs.allSatisfy(fileExists)
        let blockers = [
            "signed WidgetKit",
            "real-credential notarized release run",
            "updater signing keys",
            "appcast metadata",
            "rollback instructions"
        ]
        let missing = blockers.filter { blocker in
            !docs.contains { fileContains($0, blocker) }
        }
        let ready = docsExist && missing.isEmpty
        return NativeReleasePolicyCheck(
            requirement: .publicReleaseBlockers,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "Public-release blockers remain explicit across release notes, release process, and distribution docs."
                : "Public-release blocker policy is missing or incomplete: \(missing.joined(separator: ", ")).",
            evidence: docs + missing
        )
    }

    private static func missingNeedles(
        _ needles: [String],
        path: String,
        fileContains: (String, String) -> Bool
    ) -> [String] {
        needles.filter { !fileContains(path, $0) }
    }
}
