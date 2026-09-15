import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class PythonProjectTemplateTests: XCTestCase {
    func testCreatesCompletePyDevProjectLayout() throws {
        let parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NVE-PyDev-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parentURL) }
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let projectURL = try PythonProjectTemplate.create(projectName: "Example Project", in: parentURL)
        let packageURL = projectURL.appendingPathComponent("src/example_project")

        for relativePath in [
            "README.md",
            "requirements.txt",
            "pyproject.toml",
            ".gitignore",
            "src/example_project/__init__.py",
            "src/example_project/main.py",
            "tests/test_main.py"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent(relativePath).path))
        }

        let pyproject = try String(contentsOf: projectURL.appendingPathComponent("pyproject.toml"), encoding: .utf8)
        XCTAssertTrue(pyproject.contains("[project.optional-dependencies]"))
        XCTAssertTrue(pyproject.contains("dev = ["))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("main.py").path))
    }

    func testDoesNotOverwriteExistingProjectFolder() throws {
        let parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NVE-PyDev-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parentURL) }
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: parentURL.appendingPathComponent("existing"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try PythonProjectTemplate.create(projectName: "existing", in: parentURL)) { error in
            XCTAssertEqual(error as? PythonProjectTemplateError, .projectAlreadyExists)
        }
    }
}
