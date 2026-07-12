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

        let panelStart = try XCTUnwrap(source.range(of: "private struct WorkspaceConsoleDocumentPanel"))
        let panelEnd = try XCTUnwrap(source.range(of: "private struct ConsoleFileGroup", range: panelStart.upperBound..<source.endIndex))
        let panel = source[panelStart.lowerBound..<panelEnd.lowerBound]
        XCTAssertFalse(panel.contains("documentPreviewContent"))
        XCTAssertFalse(panel.contains("点击后在下方预览"))
    }
}
