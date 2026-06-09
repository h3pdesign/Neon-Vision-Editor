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

private final class ShareImportedCandidateCollector: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var bestCandidate: (priority: Int, url: URL)?

    nonisolated func append(_ url: URL, priority: Int) {
        lock.lock()
        if bestCandidate.map({ priority < $0.priority }) ?? true {
            bestCandidate = (priority, url)
        }
        lock.unlock()
    }

    nonisolated func snapshot() -> URL? {
        lock.lock()
        let url = bestCandidate?.url
        lock.unlock()
        return url
    }
}

final class ShareViewController: PlatformShareViewController {
    private nonisolated static let importDirectoryName = "SharedImports"
    private nonisolated static let appGroupIdentifier = "group.h3p.Neon-Vision-Editor"
    private nonisolated static let pendingManifestFilename = "PendingSharedImports.json"
    private nonisolated static let pendingImportDarwinNotificationName = "h3p.NeonVisionEditor.sharedImportPending"
    private nonisolated static let webArchiveTypeIdentifier = "com.apple.webarchive"
    private var didStartImport = false

    #if canImport(UIKit)
    private let statusLabel = UILabel()
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

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        doneButton.addTarget(self, action: #selector(ShareViewController.doneButtonTapped), for: .touchUpInside)
        doneButton.accessibilityLabel = "Done"

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, doneButton])
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
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))

        let titleLabel = NSTextField(labelWithString: "Neon Vision Editor")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0

        doneButton.target = self
        doneButton.action = #selector(ShareViewController.doneButtonTapped)

        let stack = NSStackView(views: [titleLabel, statusLabel, doneButton])
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
        showStatus("Preparing shared content...", showsDoneButton: true)
        importSharedItems()
    }

    private func importSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showNoSupportedContent()
            return
        }
        let providers = extensionItems.flatMap { sharedItemProviders(from: $0) }
        let itemTexts = extensionItems.compactMap { sharedExtensionItemText($0) }
        guard !providers.isEmpty || !itemTexts.isEmpty else {
            showNoSupportedContent()
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
            let providerImportedURLs = collector.snapshot()
            Task { @MainActor in
                let importedURLs = providerImportedURLs.isEmpty
                    ? self.writeFallbackSharedExtensionTexts(itemTexts)
                    : providerImportedURLs
                if importedURLs.isEmpty {
                    self.showNoSupportedContent()
                } else {
                    self.writePendingImportManifest(importedFileURLs: importedURLs)
                    self.showImportComplete(importedCount: importedURLs.count)
                }
            }
        }
    }

    private func importItem(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        let group = DispatchGroup()
        let collector = ShareImportedCandidateCollector()
        var didStartLoad = false

        func load(priority: Int, _ loader: (@escaping @Sendable (URL?) -> Void) -> Bool) {
            group.enter()
            let didStart = loader { importedURL in
                if let importedURL {
                    collector.append(importedURL, priority: priority)
                }
                group.leave()
            }
            didStartLoad = didStartLoad || didStart
            if !didStart {
                group.leave()
            }
        }

        load(priority: 0) { self.loadStringObject(from: provider, completion: $0) }
        load(priority: 1) { self.loadURLObject(from: provider, completion: $0) }
        load(priority: 2) { self.loadText(from: provider, completion: $0) }
        load(priority: 3) { self.loadWebURL(from: provider, completion: $0) }
        load(priority: 4) { self.loadDataText(from: provider, completion: $0) }
        load(priority: 5) { self.loadFileURL(from: provider, completion: $0) }
        load(priority: 6) { self.loadFile(from: provider, completion: $0) }

        guard didStartLoad else {
            completion(nil)
            return
        }

        group.notify(queue: .main) {
            completion(collector.snapshot())
        }
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
    private func loadStringObject(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        guard provider.canLoadObject(ofClass: NSString.self) else { return false }
        let suggestedName = provider.suggestedName
        provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let self else {
                completion(nil)
                return
            }
            let text = (object as? NSString as String?)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = self.textFilename(from: suggestedName, fallback: "Shared Text.txt")
            let copiedURL = text.flatMap { $0.isEmpty ? nil : self.writeSharedText($0, filename: filename) }
            completion(copiedURL)
        }
        return true
    }

    @discardableResult
    private func loadURLObject(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        guard provider.canLoadObject(ofClass: NSURL.self) else { return false }
        let suggestedName = provider.suggestedName
        provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
            guard let self else {
                completion(nil)
                return
            }
            let url = (object as? NSURL).map { $0 as URL }
            let filename = self.textFilename(from: suggestedName, fallback: "Shared URL.txt")
            let copiedURL = url.flatMap { self.writeSharedText($0.absoluteString, filename: filename) }
            completion(copiedURL)
        }
        return true
    }

    @discardableResult
    private func loadText(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        let textTypes = [
            UTType.plainText.identifier,
            "public.utf8-plain-text",
            "public.url-name",
            UTType.html.identifier,
            UTType.rtf.identifier,
            UTType.text.identifier
        ]
        guard let textType = registeredTypeIdentifier(in: provider, preferredTypes: textTypes) else { return false }
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
        guard let urlType = registeredTypeIdentifier(in: provider, preferredTypes: [UTType.url.identifier]) else { return false }
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

    @discardableResult
    private func loadDataText(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) -> Bool {
        guard let dataType = dataTextTypeIdentifier(in: provider) else { return false }
        let suggestedName = provider.suggestedName
        provider.loadDataRepresentation(forTypeIdentifier: dataType) { [weak self] data, _ in
            guard let self else {
                completion(nil)
                return
            }
            let text = data.flatMap { self.text(from: $0, typeIdentifier: dataType) }
            let filename = self.textFilename(from: suggestedName, fallback: "Shared Text.txt")
            let copiedURL = text.flatMap { self.writeSharedText($0, filename: filename) }
            completion(copiedURL)
        }
        return true
    }

    private nonisolated func registeredTypeIdentifier(in provider: NSItemProvider, preferredTypes: [String]) -> String? {
        for preferredType in preferredTypes {
            if provider.registeredTypeIdentifiers.contains(preferredType) {
                return preferredType
            }
            if provider.hasItemConformingToTypeIdentifier(preferredType) {
                return preferredType
            }
            guard let preferredUTType = UTType(preferredType) else { continue }
            if let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
                UTType(identifier)?.conforms(to: preferredUTType) == true
            }) {
                return identifier
            }
        }
        return nil
    }

    private nonisolated func dataTextTypeIdentifier(in provider: NSItemProvider) -> String? {
        let preferredTypes = [
            UTType.plainText.identifier,
            "public.utf8-plain-text",
            "public.url-name",
            UTType.url.identifier,
            UTType.html.identifier,
            UTType.rtf.identifier,
            UTType.text.identifier,
            Self.webArchiveTypeIdentifier,
            UTType.data.identifier
        ]
        return registeredTypeIdentifier(in: provider, preferredTypes: preferredTypes)
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

    private nonisolated func writePendingImportManifest(importedFileURLs: [URL]) {
        guard let directory = sharedImportDirectory(), !importedFileURLs.isEmpty else { return }
        let manifest: [String: Any] = [
            "filePaths": importedFileURLs.map { $0.standardizedFileURL.path },
            "createdAt": Date().timeIntervalSince1970
        ]
        let manifestURL = directory.appendingPathComponent(Self.pendingManifestFilename, isDirectory: false)
        guard let data = try? JSONSerialization.data(withJSONObject: manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
        postPendingImportNotification()
    }

    private nonisolated func postPendingImportNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.pendingImportDarwinNotificationName as CFString),
            nil,
            nil,
            true
        )
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

    private nonisolated func sharedExtensionItemText(_ item: NSExtensionItem) -> String? {
        let title = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [title, content]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { return nil }
        return text
    }

    private nonisolated func sharedItemProviders(from item: NSExtensionItem) -> [NSItemProvider] {
        if let attachments = item.attachments, !attachments.isEmpty {
            return attachments
        }
        return item.userInfo?[NSExtensionItemAttachmentsKey] as? [NSItemProvider] ?? []
    }

    private nonisolated func writeFallbackSharedExtensionTexts(_ texts: [String]) -> [URL] {
        var seen: Set<String> = []
        return texts.compactMap { text in
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return writeSharedText(normalized, filename: "Shared Text.txt")
        }
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
            return text(from: data, typeIdentifier: typeIdentifier)
        }
        return nil
    }

    private nonisolated func text(from data: Data, typeIdentifier: String) -> String? {
        if typeIdentifier == Self.webArchiveTypeIdentifier,
           let webArchiveText = textFromWebArchive(data) {
            return webArchiveText
        }
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
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = String(data: data, encoding: .utf16) {
            return string
        }
        return textFromWebArchive(data)
    }

    private nonisolated func textFromWebArchive(_ data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let archive = plist as? [String: Any],
            let mainResource = archive["WebMainResource"] as? [String: Any],
            let resourceData = mainResource["WebResourceData"] as? Data
        else {
            return nil
        }

        if let mimeType = mainResource["WebResourceMIMEType"] as? String,
           mimeType.localizedCaseInsensitiveContains("html"),
           let attributedString = try? NSAttributedString(
               data: resourceData,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil
           ) {
            let text = attributedString.string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        if let string = String(data: resourceData, encoding: .utf8) {
            let text = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let string = String(data: resourceData, encoding: .utf16) {
            let text = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func showNoSupportedContent() {
        showStatus(
            "No supported shared text, URLs, or files were found.",
            showsDoneButton: true
        )
    }

    private func showImportComplete(importedCount: Int) {
        let itemText = importedCount == 1 ? "item" : "items"
        #if canImport(AppKit) && !canImport(UIKit)
        let message = "Imported \(importedCount) shared \(itemText). You can close this share sheet."
        #else
        let message = "Imported \(importedCount) shared \(itemText). Switch to Neon Vision Editor to choose where to place it."
        #endif
        showStatus(
            message,
            showsDoneButton: true
        )
    }

    private func showStatus(_ message: String, showsDoneButton: Bool) {
        #if canImport(UIKit)
        statusLabel.text = message
        #elseif canImport(AppKit)
        statusLabel.stringValue = message
        #endif
        doneButton.isHidden = !showsDoneButton
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
