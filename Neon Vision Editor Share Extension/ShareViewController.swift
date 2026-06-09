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
    private var didStartImport = false
    private var importedFileURLs: [URL] = []

    #if canImport(UIKit)
    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Neon Vision Editor"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        statusLabel.text = "Preparing shared content..."
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel

        openButton.setTitle("Open Neon Vision Editor", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        openButton.addTarget(self, action: #selector(ShareViewController.openButtonTapped), for: .touchUpInside)
        openButton.isHidden = true
        openButton.accessibilityLabel = "Open Neon Vision Editor"

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        doneButton.addTarget(self, action: #selector(ShareViewController.doneButtonTapped), for: .touchUpInside)
        doneButton.accessibilityLabel = "Done"

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, openButton, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: rootView.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: rootView.centerYAnchor)
        ])

        view = rootView
    }
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
    private let statusLabel = NSTextField(labelWithString: "Preparing shared content...")
    private let openButton = NSButton(title: "Open Neon Vision Editor", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))

        let titleLabel = NSTextField(labelWithString: "Neon Vision Editor")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0

        openButton.target = self
        openButton.action = #selector(ShareViewController.openButtonTapped)
        openButton.isHidden = true
        doneButton.target = self
        doneButton.action = #selector(ShareViewController.doneButtonTapped)

        let stack = NSStackView(views: [titleLabel, statusLabel, openButton, doneButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: rootView.centerYAnchor)
        ])

        view = rootView
    }
    #endif

    #if canImport(UIKit)
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        beginImportIfNeeded()
    }
    #elseif canImport(AppKit)
    override func viewDidAppear() {
        super.viewDidAppear()
        beginImportIfNeeded()
    }
    #endif

    private func beginImportIfNeeded() {
        guard !didStartImport else { return }
        didStartImport = true
        showStatus("Preparing shared content...", showsOpenButton: false, showsDoneButton: true)
        importSharedItems()
    }

    private func importSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showNoSupportedContent()
            return
        }
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        let itemTextURLs = extensionItems.compactMap { writeSharedExtensionItemText($0) }
        guard !providers.isEmpty || !itemTextURLs.isEmpty else {
            showNoSupportedContent()
            return
        }

        let group = DispatchGroup()
        let collector = ShareImportedURLCollector()
        itemTextURLs.forEach { collector.append($0) }
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
                if importedURLs.isEmpty {
                    self.showNoSupportedContent()
                } else {
                    self.importedFileURLs = importedURLs
                    self.openMainApp(importedFileURLs: importedURLs)
                }
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
        let textTypes = [
            UTType.plainText.identifier,
            "public.utf8-plain-text",
            UTType.text.identifier,
            UTType.html.identifier,
            UTType.rtf.identifier
        ]
        guard let textType = textTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else { return false }
        let suggestedName = provider.suggestedName
        provider.loadItem(forTypeIdentifier: textType) { [weak self] item, _ in
            guard let self else { return }
            let text = self.text(from: item, typeIdentifier: textType)
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
            } else if let sharedURL = item as? NSURL {
                url = sharedURL as URL
            } else if let string = item as? String {
                url = URL(string: string)
            } else if let string = item as? NSString {
                url = URL(string: string as String)
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
        if let url = item as? NSURL {
            return url as URL
        }
        if let string = item as? String {
            return URL(string: string)
        }
        if let string = item as? NSString {
            return URL(string: string as String)
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

    private nonisolated func writeSharedExtensionItemText(_ item: NSExtensionItem) -> URL? {
        let title = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [title, content]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { return nil }
        return writeSharedText(text, filename: "Shared Text.txt")
    }

    private nonisolated func text(from item: NSSecureCoding?, typeIdentifier: String) -> String? {
        if let string = item as? String {
            return string
        }
        if let string = item as? NSString {
            return string as String
        }
        if let attributedString = item as? NSAttributedString {
            return attributedString.string
        }
        if let url = item as? URL {
            return url.absoluteString
        }
        if let url = item as? NSURL {
            return (url as URL).absoluteString
        }
        if let data = item as? Data {
            if typeIdentifier == UTType.rtf.identifier,
               let attributedString = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                return attributedString.string
            }
            if typeIdentifier == UTType.html.identifier,
               let attributedString = try? NSAttributedString(
                   data: data,
                   options: [
                       .documentType: NSAttributedString.DocumentType.html,
                       .characterEncoding: String.Encoding.utf8.rawValue
                   ],
                   documentAttributes: nil
               ) {
                return attributedString.string
            }
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func openMainApp(importedFileURLs: [URL]) {
        var components = URLComponents()
        components.scheme = "neonvisioneditor"
        components.host = "share-import"
        components.queryItems = importedFileURLs.map { URLQueryItem(name: "file", value: $0.path) }
        guard let url = components.url else {
            showOpenFailed()
            return
        }
        showStatus("Opening Neon Vision Editor...", showsOpenButton: false, showsDoneButton: true)
        DispatchQueue.main.async {
            guard let extensionContext = self.extensionContext else {
                self.showOpenFailed()
                return
            }
            extensionContext.open(url) { [weak self] success in
                Task { @MainActor in
                    guard let self else { return }
                    if success {
                        self.finish()
                    } else {
                        self.showOpenFailed()
                    }
                }
            }
        }
    }

    private func retryOpenMainApp() {
        if importedFileURLs.isEmpty {
            showNoSupportedContent()
        } else {
            openMainApp(importedFileURLs: importedFileURLs)
        }
    }

    private func showNoSupportedContent() {
        showStatus(
            "No supported shared text, URLs, or files were found.",
            showsOpenButton: false,
            showsDoneButton: true
        )
    }

    private func showOpenFailed() {
        showStatus(
            "The shared content was imported. Open Neon Vision Editor to choose where to place it.",
            showsOpenButton: true,
            showsDoneButton: true
        )
    }

    private func showStatus(_ message: String, showsOpenButton: Bool, showsDoneButton: Bool) {
        #if canImport(UIKit)
        statusLabel.text = message
        #elseif canImport(AppKit)
        statusLabel.stringValue = message
        #endif
        openButton.isHidden = !showsOpenButton
        doneButton.isHidden = !showsDoneButton
    }

    @objc private func openButtonTapped() {
        retryOpenMainApp()
    }

    @objc private func doneButtonTapped() {
        finish()
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
