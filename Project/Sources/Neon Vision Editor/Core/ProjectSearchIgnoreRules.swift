import Foundation
import Darwin

/// Search-local rule cache. Skips symbolic links below the user-selected project.
nonisolated final class ProjectSearchIgnoreRules {
    private let root: URL
    private let excludedFolders: Set<String>
    private var rulesByDirectory: [String: [Rule]] = [:]

    private struct Rule {
        let pattern: String
        let negated: Bool
        let directoryOnly: Bool
        let anchored: Bool

        init?(_ line: String) {
            var value = line
            while value.last == " " {
                let preceding = value.dropLast().reversed().prefix { $0 == "\\" }.count
                if preceding % 2 == 1 { break }
                value.removeLast()
            }
            guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
            negated = value.hasPrefix("!")
            if negated { value.removeFirst() }
            directoryOnly = value.hasSuffix("/")
            if directoryOnly { value.removeLast() }
            anchored = value.contains("/")
            if value.hasPrefix("/") { value.removeFirst() }
            guard !value.isEmpty else { return nil }
            pattern = value
        }

        func matches(_ path: String, isDirectory: Bool) -> Bool {
            guard !directoryOnly || isDirectory else { return false }
            if !anchored {
                return fnmatch(pattern, String(path.split(separator: "/").last ?? ""), 0) == 0
            }
            let patterns = pattern.split(separator: "/").map(String.init)
            let components = path.split(separator: "/").map(String.init)
            var memo: [Int: Bool] = [:]
            func match(_ p: Int, _ c: Int) -> Bool {
                let key = p * (components.count + 1) + c
                if let cached = memo[key] { return cached }
                let result: Bool
                if p == patterns.count {
                    result = c == components.count
                } else if patterns[p] == "**" {
                    // A trailing /** matches descendants, not the directory itself.
                    result = p == patterns.count - 1
                        ? c < components.count
                        : match(p + 1, c) || (c < components.count && match(p, c + 1))
                } else {
                    result = c < components.count && fnmatch(patterns[p], components[c], 0) == 0 && match(p + 1, c + 1)
                }
                memo[key] = result
                return result
            }
            return match(0, 0)
        }
    }

    init(root: URL, excludedFolders: Set<String>) {
        self.root = root.standardizedFileURL
        self.excludedFolders = excludedFolders
    }

    func excludes(_ url: URL, isDirectory: Bool) -> Bool {
        let path = url.standardizedFileURL.path
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard path.hasPrefix(prefix) else { return true }
        let components = String(path.dropFirst(prefix.count)).split(separator: "/").map(String.init)
        var directory = root
        var inherited: [(Int, [Rule])] = []
        for index in components.indices {
            let directoryPath = directory.path
            if rulesByDirectory[directoryPath] == nil {
                // An indexed candidate may traverse a symlinked directory even
                // though the candidate file itself is a regular file.
                if index > 0,
                   (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                    return true
                }
                let ignoreURL = directory.appendingPathComponent(".gitignore")
                // Do not follow ignore-file symlinks outside the project.
                let values = try? ignoreURL.resourceValues(forKeys: [.isSymbolicLinkKey])
                let source = values?.isSymbolicLink == true ? "" : ((try? String(contentsOf: ignoreURL, encoding: .utf8)) ?? "")
                rulesByDirectory[directoryPath] = source.components(separatedBy: .newlines).compactMap(Rule.init)
            }
            inherited.append((index, rulesByDirectory[directoryPath] ?? []))
            let directoryComponent = index < components.count - 1 || isDirectory
            if directoryComponent && excludedFolders.contains(components[index]) { return true }
            var ignored = false
            for (base, rules) in inherited {
                let relative = components[base...index].joined(separator: "/")
                for rule in rules where rule.matches(relative, isDirectory: directoryComponent) {
                    ignored = !rule.negated
                }
            }
            // Git cannot re-include a child of an excluded directory.
            if ignored { return true }
            directory.appendPathComponent(components[index])
        }
        return false
    }
}
