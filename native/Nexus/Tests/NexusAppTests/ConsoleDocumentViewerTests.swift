import Foundation
import XCTest

final class ConsoleDocumentViewerTests: XCTestCase {
    func testConsoleDocumentsOpenInLargeSheetInsteadOfRenderingInsideDrawer() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NexusApp/Views/RootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("WorkspaceConsoleDocumentViewerSheet"))
        XCTAssertTrue(source.contains("isDocumentViewerPresented = true"))
        XCTAssertTrue(source.contains("fillsAvailableSpace: true"))
        XCTAssertTrue(source.contains("private func openDocumentInViewer("))
        XCTAssertTrue(source.contains("private func openSQLInViewer("))
        XCTAssertTrue(source.contains("private func openTaskInViewer("))

        let actionsStart = try XCTUnwrap(source.range(of: "private func run(_ action: WorkspaceSessionAction"))
        let actionsEnd = try XCTUnwrap(
            source.range(of: "private func routeToDemandInput", range: actionsStart.upperBound..<source.endIndex)
        )
        let actions = source[actionsStart.lowerBound..<actionsEnd.lowerBound]
        XCTAssertTrue(actions.contains("openDocumentInViewer("))
        XCTAssertTrue(actions.contains("openSQLInViewer("))
        XCTAssertTrue(actions.contains("openTaskInViewer("))

        let panelStart = try XCTUnwrap(source.range(of: "private struct WorkspaceConsoleDocumentPanel"))
        let panelEnd = try XCTUnwrap(source.range(of: "private struct ConsoleFileGroup", range: panelStart.upperBound..<source.endIndex))
        let panel = source[panelStart.lowerBound..<panelEnd.lowerBound]
        XCTAssertFalse(panel.contains("documentPreviewContent"))
        XCTAssertFalse(panel.contains("点击后在下方预览"))
    }
}
