import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ProjectTreePerformanceTests: XCTestCase {
    func testInitialProjectTreeOnlyLoadsRootLevelChildren() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-tree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Sources/Ada", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("with Ada.Text_IO;\n".utf8)
            .write(to: nested.appendingPathComponent("Huge.adb"))

        let rootNodes = ContentView.projectTreeNodesForTesting(
            at: root,
            supportedOnly: false,
            includeHidden: false,
            ignoredFolderNames: []
        )

        XCTAssertEqual(rootNodes.map(\.url.lastPathComponent), ["Sources"])
        XCTAssertTrue(rootNodes[0].children.isEmpty, "Initial sidebar load must not recurse into descendants")

        let sourceNodes = ContentView.projectTreeChildrenForTesting(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            supportedOnly: false,
            includeHidden: false,
            ignoredFolderNames: []
        )

        XCTAssertEqual(sourceNodes.map(\.url.lastPathComponent), ["Ada"])
        XCTAssertTrue(sourceNodes[0].children.isEmpty, "Directory expansion should load one level at a time")
    }

    func testTOCSidebarBoundsLargeLineCount() {
        let content = String(repeating: "procedure Ada_Line is null;\n", count: 10_000)
        let items = SidebarView.tocItemsForTesting(content: content, language: "ada")

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].line)
        XCTAssertTrue(items[0].title.contains("TOC disabled"))
    }
}
