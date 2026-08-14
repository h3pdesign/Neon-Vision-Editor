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
        XCTAssertFalse(rootNodes[0].childrenLoaded, "An empty child list must remain distinguishable from a loaded empty directory.")

        let sourceNodes = ContentView.projectTreeChildrenForTesting(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            supportedOnly: false,
            includeHidden: false,
            ignoredFolderNames: []
        )

        XCTAssertEqual(sourceNodes.map(\.url.lastPathComponent), ["Ada"])
        XCTAssertTrue(sourceNodes[0].children.isEmpty, "Directory expansion should load one level at a time")

        let refreshed = ContentView.projectTreeNodesReplacingChildren(
            replacingChildrenOf: rootNodes[0].url,
            with: sourceNodes,
            in: rootNodes
        )
        XCTAssertTrue(refreshed[0].childrenLoaded, "Expanding a directory must mark its child list as loaded even when it is empty.")
        XCTAssertEqual(refreshed[0].children.map(\.url.lastPathComponent), ["Ada"])
    }

    func testRefreshingSubtreePreservesFileNodesAsFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-tree-file-kind-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let sourceFile = sources.appendingPathComponent("TEST.swift")
        try Data("print(\"test\")\n".utf8).write(to: sourceFile)

        let rootNodes = ContentView.projectTreeNodesForTesting(
            at: root,
            supportedOnly: false,
            includeHidden: false,
            ignoredFolderNames: []
        )
        let children = ContentView.projectTreeChildrenForTesting(
            at: sources,
            supportedOnly: false,
            includeHidden: false,
            ignoredFolderNames: []
        )
        let refreshed = ContentView.projectTreeNodesReplacingChildren(
            replacingChildrenOf: sources,
            with: children,
            in: rootNodes
        )

        let refreshedSources = try XCTUnwrap(refreshed.first)
        let refreshedFile = try XCTUnwrap(refreshedSources.children.first)
        XCTAssertTrue(refreshedSources.isDirectory)
        XCTAssertFalse(refreshedFile.isDirectory)
        XCTAssertEqual(refreshedFile.url.lastPathComponent, "TEST.swift")
    }

    func testExpandAllSnapshotLoadsDescendantsInOneTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-tree-expand-all-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Sources/Ada/Deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("with Ada.Text_IO;\n".utf8)
            .write(to: nested.appendingPathComponent("Main.adb"))

        let snapshot = ContentView.projectTreeNodesRecursivelyForTesting(
            at: root,
            supportedOnly: false,
            includeHidden: false,
            ignoredFolderNames: []
        )

        let sources = try XCTUnwrap(snapshot.first)
        let ada = try XCTUnwrap(sources.children.first)
        let deep = try XCTUnwrap(ada.children.first)
        XCTAssertTrue(sources.childrenLoaded)
        XCTAssertTrue(ada.childrenLoaded)
        XCTAssertTrue(deep.childrenLoaded)
        XCTAssertEqual(deep.children.map(\.url.lastPathComponent), ["Main.adb"])
    }

    func testTOCSidebarBoundsLargeLineCount() {
        let content = String(repeating: "procedure Ada_Line is null;\n", count: 10_000)
        let items = SidebarView.tocItemsForTesting(content: content, language: "ada")

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].line)
        XCTAssertTrue(items[0].title.contains("TOC disabled"))
    }

    func testProjectFileIndexSkipsGeneratedBuildDirectoryByDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        let buildDirectory = root.appendingPathComponent("build/Debug", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        try Data("print(\"source\")".utf8).write(to: sourceDirectory.appendingPathComponent("App.swift"))
        try Data("generated".utf8).write(to: buildDirectory.appendingPathComponent("Generated.swift"))

        let snapshot = await ProjectFileIndex.buildSnapshot(
            at: root,
            supportedOnly: false,
            isSupportedFile: { _ in true }
        )

        XCTAssertEqual(snapshot.entries.map(\.relativePath), ["Sources/App.swift"])
    }
}
