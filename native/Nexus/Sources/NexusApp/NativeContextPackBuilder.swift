import Foundation

struct NativeContextFeature: Hashable, Sendable {
    let id: String
    let title: String
    let status: String
    let detail: String
}

struct NativeContextTask: Hashable, Sendable {
    let id: String
    let title: String
    let status: String
    let detail: String
}

struct NativeContextService: Hashable, Sendable {
    let name: String
    let branch: String
    let gitSummary: String
}

struct NativeContextEvidence: Hashable, Sendable {
    let path: String
    let summary: String?
}

struct NativeFeatureProposalContext: Hashable, Sendable {
    let requirement: String
    let links: [String]
    let materialPaths: [String]
    let draftPath: String
}

struct NativeContextPackInput: Hashable, Sendable {
    var generatedAt: String
    var workspaceName: String
    var workspacePath: String
    var selectedFeature: NativeContextFeature?
    var activeLinkedTasks: [NativeContextTask]
    var blockers: [String]
    var nextAction: String
    var services: [NativeContextService]
    var gitSummary: [String]
    var latestRelevantCheck: String?
    var confirmedChanges: [String]
    var evidence: [NativeContextEvidence]
    var sourceRevisions: [String: String]
    var featureProposal: NativeFeatureProposalContext? = nil
}

enum NativeContextPackStatus: Hashable, Sendable {
    case ready
    case overflow(requiredUTF8Bytes: Int, maximumUTF8Bytes: Int)
}

struct NativeContextPack: Hashable, Sendable {
    let markdown: String
    let status: NativeContextPackStatus
    let includedSourceRevisions: [String: String]
    let omittedSections: [String]
}

enum NativeContextPackBuilder {
    static func build(input: NativeContextPackInput, maximumUTF8Bytes: Int = 6_144) -> NativeContextPack {
        let maximum = max(0, maximumUTF8Bytes)
        var changes = Array(input.confirmedChanges.prefix(3))
        var evidenceSummaries = input.evidence.map(\.summary)
        var omitted: [String] = []

        func render() -> String {
            markdown(
                input: input,
                changes: changes,
                evidenceSummaries: evidenceSummaries
            )
        }

        var rendered = render()
        while rendered.utf8.count > maximum, let removed = changes.popLast() {
            omitted.append("confirmed-change:\(changeName(removed))")
            rendered = render()
        }
        if rendered.utf8.count > maximum {
            for index in evidenceSummaries.indices.reversed() where evidenceSummaries[index] != nil {
                evidenceSummaries[index] = nil
                omitted.append("evidence-summary:\(input.evidence[index].path)")
                rendered = render()
                if rendered.utf8.count <= maximum { break }
            }
        }
        guard rendered.utf8.count <= maximum else {
            return NativeContextPack(
                markdown: "",
                status: .overflow(requiredUTF8Bytes: rendered.utf8.count, maximumUTF8Bytes: maximum),
                includedSourceRevisions: input.sourceRevisions,
                omittedSections: omitted + ["required-content-overflow"]
            )
        }
        return NativeContextPack(
            markdown: rendered,
            status: .ready,
            includedSourceRevisions: input.sourceRevisions,
            omittedSections: omitted
        )
    }

    private static func markdown(
        input: NativeContextPackInput,
        changes: [String],
        evidenceSummaries: [String?]
    ) -> String {
        var lines = [
            "# Nexus Context Pack",
            "",
            "Generated: \(input.generatedAt)",
            "",
            "## Workspace",
            "- Name: \(input.workspaceName)",
            "- Path: \(input.workspacePath)"
        ]
        if let feature = input.selectedFeature {
            lines += [
                "",
                "## Selected Feature",
                "- \(feature.id) [\(feature.status)]: \(singleLine(feature.title))",
                "- Detail: \(singleLine(feature.detail))",
                "",
                "### Active Linked Tasks"
            ]
            lines += input.activeLinkedTasks.isEmpty
                ? ["- None."]
                : input.activeLinkedTasks.map {
                    "- \($0.id) [\($0.status)]: \(singleLine($0.title)) | \(singleLine($0.detail))"
                }
        }
        if let proposal = input.featureProposal {
            lines += ["", "## Feature Proposal Input", "### Requirement"]
            let requirementLines = proposal.requirement.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).map(String.init)
            lines += requirementLines.isEmpty ? ["No requirement text saved yet."] : requirementLines
            lines += ["", "### Links"]
            lines += proposal.links.isEmpty ? ["- None."] : proposal.links.map { "- \($0)" }
            lines += ["", "### Confirmed Material Paths"]
            lines += proposal.materialPaths.isEmpty ? ["- None confirmed."] : proposal.materialPaths.map { "- \($0)" }
            lines += [
                "",
                "### Output Contract",
                "- Write a proposal to \(proposal.draftPath).",
                "- Do not modify FEATURES.md.",
                "- Use stable provisional IDs DRAFT-001, DRAFT-002, ... ."
            ]
        }
        lines += ["", "## Blockers And Next Action"]
        lines += input.blockers.isEmpty ? ["- Blockers: None."] : input.blockers.map { "- Blocker: \(singleLine($0))" }
        lines.append("- Next: \(singleLine(input.nextAction))")

        if !input.services.isEmpty || !input.gitSummary.isEmpty {
            lines += ["", "## Service, Branch And Git"]
            lines += input.services.map {
                "- \($0.name): branch=\($0.branch), git=\(singleLine($0.gitSummary))"
            }
            lines += input.gitSummary.map { "- \(singleLine($0))" }
        }
        if let check = input.latestRelevantCheck {
            lines += ["", "## Latest Relevant Check", "- \(singleLine(check))"]
        }
        if !changes.isEmpty {
            lines += ["", "## Newest Confirmed Changes"]
            for change in changes {
                lines += change.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            }
        }
        lines += ["", "## Evidence Paths", "- 完整事实按需读取 / Read complete facts on demand:"]
        for (index, evidence) in input.evidence.enumerated() {
            let summary = evidenceSummaries[index].flatMap(safeSummary)
            lines.append("- \(evidence.path)\(summary.map { ": \($0)" } ?? "")")
        }
        lines += ["", "## Source Revisions"]
        for key in input.sourceRevisions.keys.sorted() {
            lines.append("- \(key): \(input.sourceRevisions[key]!)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func safeSummary(_ value: String) -> String? {
        let line = singleLine(value)
        guard !line.isEmpty, line.utf8.count <= 240 else { return nil }
        return line
    }

    private static func singleLine(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func changeName(_ value: String) -> String {
        let first = singleLine(value).trimmingCharacters(in: .whitespaces)
        return first.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
    }
}
