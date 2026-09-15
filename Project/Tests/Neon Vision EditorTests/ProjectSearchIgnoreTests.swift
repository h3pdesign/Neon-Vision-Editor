import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ProjectSearchIgnoreTests: XCTestCase {
    private func fixture(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testLiveAndIndexedSearchRespectRulesAndUnknownExtensions() async throws {
        let root = try fixture([
            ".gitignore": "*.log\n!keep.log\ncache/\n",
            "keep.log": "needle", "drop.log": "needle", "notes.unusual": "needle",
            "cache/data": "needle", "node_modules/lib.js": "needle", "build/output": "needle",
            "src/.gitignore": "local.*\n", "src/local.txt": "needle", "src/code.swift": "needle"
        ])
        let indexed = ["keep.log", "drop.log", "notes.unusual", "cache/data", "node_modules/lib.js",
                       "build/output", "src/local.txt", "src/code.swift"].map { root.appendingPathComponent($0) }
        for candidates in [nil, indexed] as [[URL]?] {
            let results = await ContentView.findInFiles(root: root, candidateFiles: candidates, query: "needle", caseSensitive: true, maxResults: 100)
            XCTAssertEqual(Set(results.map(\.fileURL.lastPathComponent)), ["keep.log", "notes.unusual", "code.swift"])
        }
    }

    func testEmptyCandidatesNeverFallBackToWholeTree() async throws {
        let root = try fixture(["notes.txt": "needle"])
        let results = await ContentView.findInFiles(root: root, candidateFiles: [], query: "needle", caseSensitive: true, maxResults: 100)
        XCTAssertTrue(results.isEmpty)
    }

    func testLargeCandidateListDoesNotWidenSearch() async throws {
        let root = try fixture(["keep.txt": "needle", "excluded/data.txt": "needle"])
        let candidates = Array(repeating: root.appendingPathComponent("keep.txt"), count: 2_001)
        let results = await ContentView.findInFiles(root: root, candidateFiles: candidates, query: "needle", caseSensitive: true, maxResults: 3, ignoredFolderNames: ["excluded"])
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.fileURL.lastPathComponent == "keep.txt" })
    }

    func testLiteralQueryAndResultURL() async throws {
        let root = try fixture(["-notes.unknown": "-n[1]", "other.txt": "-n1"])
        let results = await ContentView.findInFiles(root: root, candidateFiles: nil, query: "-n[1]", caseSensitive: true, maxResults: 10)
        XCTAssertEqual(results.map(\.fileURL), [root.appendingPathComponent("-notes.unknown")])
    }

    func testCustomFolderExclusionAndChangedIgnoreFile() async throws {
        let root = try fixture(["generated/output": "needle", "keep.txt": "needle", ".gitignore": "keep.txt"])
        let first = await ContentView.findInFiles(root: root, candidateFiles: nil, query: "needle", caseSensitive: true, maxResults: 100, ignoredFolderNames: ["generated"])
        XCTAssertTrue(first.isEmpty)
        try Data().write(to: root.appendingPathComponent(".gitignore"))
        let second = await ContentView.findInFiles(root: root, candidateFiles: nil, query: "needle", caseSensitive: true, maxResults: 100, ignoredFolderNames: ["generated"])
        XCTAssertEqual(second.map(\.fileURL.lastPathComponent), ["keep.txt"])
    }

    func testGitPatternSemantics() throws {
        let root = try fixture([
            ".gitignore": "# comment\n/root.txt\n*.log\n!keep.log\ncache/\na/**/generated?.[ch]\nblocked/\n!blocked/keep.txt\n\\#literal\n\\!literal\nspace\\ \ntrimmed   \n",
            "nested/.gitignore": "!child.log\n/local.txt\n"
        ])
        let rules = ProjectSearchIgnoreRules(root: root, excludedFolders: [])
        let excluded = ["root.txt", "deep/error.log", "cache/a", "a/generated1.c", "a/b/c/generated2.h",
                        "blocked/keep.txt", "#literal", "!literal", "space ", "trimmed", "nested/local.txt"]
        for path in excluded { XCTAssertTrue(rules.excludes(root.appendingPathComponent(path), isDirectory: false), path) }
        let included = ["deep/root.txt", "keep.log", "deep/keep.log", "cache", "a/generated12.c",
                        "nested/child.log", "nested/deeper/local.txt", "notes.unknown"]
        for path in included { XCTAssertFalse(rules.excludes(root.appendingPathComponent(path), isDirectory: false), path) }
        XCTAssertTrue(rules.excludes(root.appendingPathComponent("cache"), isDirectory: true))
        XCTAssertTrue(rules.excludes(root.deletingLastPathComponent().appendingPathComponent("outside"), isDirectory: false))
    }

    func testDoubleStarDescendantsAndReincludedDirectory() throws {
        let root = try fixture([".gitignore": "abc/**\noutput/*\n!output/keep/\n**/temp\n"])
        let rules = ProjectSearchIgnoreRules(root: root, excludedFolders: [])
        XCTAssertFalse(rules.excludes(root.appendingPathComponent("abc"), isDirectory: true))
        XCTAssertTrue(rules.excludes(root.appendingPathComponent("abc/file"), isDirectory: false))
        XCTAssertFalse(rules.excludes(root.appendingPathComponent("output/keep/file"), isDirectory: false))
        XCTAssertTrue(rules.excludes(root.appendingPathComponent("output/drop/file"), isDirectory: false))
        XCTAssertTrue(rules.excludes(root.appendingPathComponent("a/b/temp"), isDirectory: false))
    }

    func testCandidateDirectorySymlinkCannotEscapeProject() async throws {
        let root = try fixture(["keep.txt": "needle"])
        let outside = try fixture(["outside.txt": "needle"])
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        let candidate = alias.appendingPathComponent("outside.txt")
        let rules = ProjectSearchIgnoreRules(root: root, excludedFolders: [])
        XCTAssertTrue(rules.excludes(candidate, isDirectory: false))
        let results = await ContentView.findInFiles(root: root, candidateFiles: [candidate], query: "needle", caseSensitive: true, maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testIgnoreFileSymlinkIsNotRead() throws {
        let root = try fixture(["keep.txt": "needle"])
        let outside = try fixture(["rules": "keep.txt"])
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".gitignore"), withDestinationURL: outside.appendingPathComponent("rules"))
        let rules = ProjectSearchIgnoreRules(root: root, excludedFolders: [])
        XCTAssertFalse(rules.excludes(root.appendingPathComponent("keep.txt"), isDirectory: false))
    }
}
