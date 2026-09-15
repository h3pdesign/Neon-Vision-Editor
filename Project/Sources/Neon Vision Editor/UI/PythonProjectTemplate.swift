import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum PythonProjectTemplateError: LocalizedError, Equatable {
    case invalidProjectName
    case projectAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidProjectName:
            return "Choose a project name without slashes or colons."
        case .projectAlreadyExists:
            return "A folder with this project name already exists."
        }
    }
}

enum PythonProjectTemplate {
    static let projectFiles = [
        "README.md",
        "requirements.txt",
        "pyproject.toml",
        ".gitignore",
        "src/{package}/__init__.py",
        "src/{package}/main.py",
        "tests/test_main.py"
    ]

    static func create(projectName: String, in parentURL: URL) throws -> URL {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.contains("/"),
              !trimmedName.contains(":") else {
            throw PythonProjectTemplateError.invalidProjectName
        }

        let projectURL = parentURL.appendingPathComponent(trimmedName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: projectURL.path) else {
            throw PythonProjectTemplateError.projectAlreadyExists
        }

        let packageName = packageName(for: trimmedName)
        let files = projectFiles.map { $0.replacingOccurrences(of: "{package}", with: packageName) }
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false)

        do {
            for relativePath in files {
                let fileURL = projectURL.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let contents = contents(for: relativePath, projectName: trimmedName, packageName: packageName)
                guard FileManager.default.createFile(atPath: fileURL.path, contents: contents.data(using: .utf8)) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: projectURL)
            throw error
        }

        return projectURL
    }

    static func packageName(for projectName: String) -> String {
        let lowered = projectName.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return Character(String(scalar))
            }
            return "_"
        }
        let collapsed = String(scalars).split(separator: "_").joined(separator: "_")
        let safe = collapsed.isEmpty ? "app" : collapsed
        return safe.first?.isNumber == true ? "app_\(safe)" : safe
    }

    private static func contents(for path: String, projectName: String, packageName: String) -> String {
        switch path {
        case "README.md":
            return """
            # \(projectName)

            A Python application created with the PyDev project template.

            ## Requirements

            ### Runtime

            Runtime dependencies belong in `requirements.txt` under the Runtime section.

            ### Development

            Development tools are declared in the `dev` optional dependency group in `pyproject.toml`.

            ## Setup

            ```sh
            python3 -m venv .venv
            . .venv/bin/activate
            python -m pip install --upgrade pip
            python -m pip install -e '.[dev]'
            ```

            ## Run

            ```sh
            python -m \(packageName).main
            ```

            ## Test and quality checks

            ```sh
            pytest
            ruff check .
            mypy src
            ```
            """
        case "requirements.txt":
            return """
            # Runtime dependencies
            # Add application packages here, one machine-readable requirement per line.

            # Development dependencies
            # The canonical development group lives in pyproject.toml.
            pytest>=8.0
            ruff>=0.6
            mypy>=1.11
            """
        case "pyproject.toml":
            return """
            [build-system]
            requires = ["setuptools>=69"]
            build-backend = "setuptools.build_meta"

            [project]
            name = "\(packageName)"
            version = "0.1.0"
            description = "A Python application created with the PyDev template."
            readme = "README.md"
            requires-python = ">=3.11"
            dependencies = []

            [project.optional-dependencies]
            dev = [
                "mypy>=1.11",
                "pytest>=8.0",
                "ruff>=0.6",
            ]

            [tool.pytest.ini_options]
            pythonpath = ["src"]
            testpaths = ["tests"]

            [tool.ruff]
            line-length = 100
            target-version = "py311"

            [tool.setuptools.packages.find]
            where = ["src"]
            """
        case ".gitignore":
            return """
            .venv/
            __pycache__/
            *.py[cod]
            .pytest_cache/
            .ruff_cache/
            .mypy_cache/
            dist/
            build/
            *.egg-info/
            """
        case "src/\(packageName)/__init__.py":
            return """
            """
        case "src/\(packageName)/main.py":
            return """
            from __future__ import annotations


            def main() -> None:
                print("Hello from \(projectName)!")


            if __name__ == "__main__":
                main()
            """
        case "tests/test_main.py":
            return """
            from \(packageName).main import main


            def test_main(capsys) -> None:
                main()
                assert "Hello" in capsys.readouterr().out
            """
        default:
            return ""
        }
    }
}

struct PythonProjectTemplateSheet: View {
    let initialDestinationURL: URL
    let allowsDestinationSelection: Bool
    let onCreate: (URL, String) -> Void
    let onCancel: () -> Void

    @State private var projectName = "my-python-project"
    @State private var destinationURL: URL

    init(
        initialDestinationURL: URL,
        allowsDestinationSelection: Bool,
        onCreate: @escaping (URL, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialDestinationURL = initialDestinationURL
        self.allowsDestinationSelection = allowsDestinationSelection
        self.onCreate = onCreate
        self.onCancel = onCancel
        _destinationURL = State(initialValue: initialDestinationURL)
    }

    private var canCreate: Bool {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.contains(":")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $projectName)
                        .textContentType(.name)
                        .accessibilityLabel("Python project name")

                    HStack {
                        Label(destinationURL.path, systemImage: "folder")
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
#if os(macOS)
                        if allowsDestinationSelection {
                            Button("Choose…") {
                                chooseDestination()
                            }
                        }
#endif
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Project destination")
                } header: {
                    Text("New Python Project")
                } footer: {
                    Text("Creates a src layout, tests, grouped requirements, and a pyproject.toml development group.")
                }

                Section("Files") {
                    ForEach(PythonProjectTemplate.projectFiles.map { $0.replacingOccurrences(of: "{package}", with: PythonProjectTemplate.packageName(for: projectName)) }, id: \.self) { path in
                        Label(path, systemImage: path.hasSuffix("/") ? "folder" : "doc.text")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle("PyDev")
#if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 520, minHeight: 520)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Project") {
                        onCreate(destinationURL, projectName.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

#if os(macOS)
    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Python Project Location"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url
        }
    }
#endif
}
