import Foundation
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
typealias PlatformShareViewController = UIViewController
#elseif canImport(AppKit)
import AppKit
typealias PlatformShareViewController = NSViewController
#endif

private final class ShareImportedURLCollector: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var importedURLs: [URL] = []

    nonisolated func append(_ url: URL) {
        lock.lock()
        importedURLs.append(url)
        lock.unlock()
    }

    nonisolated func snapshot() -> [URL] {
        lock.lock()
        let urls = importedURLs
        lock.unlock()
        return urls
    }
}

final class ShareViewController: PlatformShareViewController {
    private nonisolated static let importDirectoryName = "SharedImports"
    private nonisolated static let appGroupIdentifier = "group.h3p.Neon-Vision-Editor"

    #if canImport(AppKit) && !canImport(UIKit)
    override func loadView() {
        view = NSView(frame: .zero)
    }
    #endif

    #if canImport(UIKit)
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        importSharedItems()
    }
    #elseif canImport(AppKit)
    override func viewDidAppear() {
        super.viewDidAppear()
        importSharedItems()
    }
    #endif

    private func importSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish()
            return
        }
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            finish()
            return
        }

        let group = DispatchGroup()
        let collector = ShareImportedURLCollector()
        for provider in providers {
            group.enter()
            importItem(from: provider) { importedURL in
                if let importedURL {
                    collector.append(importedURL)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let importedURLs = collector.snapshot()
            Task { @MainActor in
                importedURLs.isEmpty ? self.finish() : self.openMainApp(importedFileURLs: importedURLs)
            }
        }
    }

    private func importItem(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        if loadFileURL(from: provider, completion: completion) { return }
        if loadText(from: provider, completion: completion) { return }
        if loadWebURL(from: provider, completion: completion) { return }
        if loadFile(from: provider, completion: completion) { return }
        completion(nil)
    }

    @discardableResult
    private func loadFileURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        let fileURLType = UTType.fileURL.identifier
        guard provider.hasItemConformingToTypeIdentifier(fileURLType) else { return false }
        provider.loadItem(forTypeIdentifier: fileURLType) { [weak self] item, _ in
            guard let self else { return }
            let sourceURL = self.fileURL(from: item)
            let copiedURL = sourceURL.flatMap { self.copySharedFile(from: $0) }
            completion(copiedURL)
        }
        return true
    }

    @discardableResult
    private func loadFile(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        let identifiers = provider.registeredTypeIdentifiers
        guard let identifier = identifiers.first(where: { isBinaryFileType($0) }) else {
            return false
        }
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, _ in
            guard let self else { return }
            let copiedURL = url.flatMap { self.copySharedFile(from: $0) }
            completion(copiedURL)
        }
        return true
    }

    @discardableResult
    private func loadText(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        let textType = UTType.plainText.identifier
        guard provider.hasItemConformingToTypeIdentifier(textType) else { return false }
        let suggestedName = provider.suggestedName
        provider.loadItem(forTypeIdentifier: textType) { [weak self] item, _ in
            guard let self else { return }
            let text: String?
            if let string = item as? String {
                text = string
            } else if let data = item as? Data {
                text = String(data: data, encoding: .utf8)
            } else {
                text = nil
            }
            let filename = self.textFilename(from: suggestedName, fallback: "Shared Text.txt")
            let copiedURL = text.flatMap { self.writeSharedText($0, filename: filename) }
            completion(copiedURL)
        }
        return true
    }

    @discardableResult
    private func loadWebURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        let urlType = UTType.url.identifier
        guard provider.hasItemConformingToTypeIdentifier(urlType) else { return false }
        let suggestedName = provider.suggestedName
        provider.loadItem(forTypeIdentifier: urlType) { [weak self] item, _ in
            guard let self else { return }
            let url: URL?
            if let sharedURL = item as? URL {
                url = sharedURL
            } else if let string = item as? String {
                url = URL(string: string)
            } else {
                url = nil
            }
            let filename = self.textFilename(from: suggestedName, fallback: "Shared URL.txt")
            let copiedURL = url.flatMap { self.writeSharedText($0.absoluteString, filename: filename) }
            completion(copiedURL)
        }
        return true
    }

    private nonisolated func copySharedFile(from sourceURL: URL) -> URL? {
        guard let directory = sharedImportDirectory() else { return nil }
        let filename = sanitizedFilename(sourceURL.lastPathComponent.isEmpty ? "Shared File.txt" : sourceURL.lastPathComponent)
        let destination = uniqueDestination(in: directory, filename: filename)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private nonisolated func writeSharedText(_ text: String) -> URL? {
        return writeSharedText(text, filename: "Shared Text.txt")
    }

    private nonisolated func writeSharedText(_ text: String, filename: String) -> URL? {
        guard let directory = sharedImportDirectory() else { return nil }
        let destination = uniqueDestination(in: directory, filename: filename)
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch {
            return nil
        }
    }

    private nonisolated func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }
        return nil
    }

    private nonisolated func isBinaryFileType(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
    }

    private nonisolated func sharedImportDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            return nil
        }
        let directory = container.appendingPathComponent(Self.importDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private nonisolated func uniqueDestination(in directory: URL, filename: String) -> URL {
        let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        let suffix = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let uniqueName = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
        return directory.appendingPathComponent(uniqueName, isDirectory: false)
    }

    private nonisolated func sanitizedFilename(_ filename: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let parts = filename.components(separatedBy: invalid).filter { !$0.isEmpty }
        return parts.joined(separator: "-").isEmpty ? "Shared File.txt" : parts.joined(separator: "-")
    }

    private nonisolated func textFilename(from suggestedName: String?, fallback: String) -> String {
        guard let suggestedName, !suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        let sanitized = sanitizedFilename(suggestedName)
        return URL(fileURLWithPath: sanitized).pathExtension.isEmpty ? "\(sanitized).txt" : sanitized
    }

    private func openMainApp(importedFileURLs: [URL]) {
        var components = URLComponents()
        components.scheme = "neonvisioneditor"
        components.host = "share-import"
        components.queryItems = importedFileURLs.map { URLQueryItem(name: "file", value: $0.path) }
        guard let url = components.url else {
            finish()
            return
        }
        DispatchQueue.main.async {
            self.extensionContext?.open(url) { [weak self] _ in
                Task { @MainActor in
                    self?.finish()
                }
            }
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
