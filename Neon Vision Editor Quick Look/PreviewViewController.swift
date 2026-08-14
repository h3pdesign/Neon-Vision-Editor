//
//  PreviewViewController.swift
//  SyntaxQuicklook
//
//  View-based Quick Look using SwiftUI EditorView.
//

import Cocoa
import Quartz
import SwiftUI
import UniformTypeIdentifiers

class PreviewViewController: NSViewController, QLPreviewingController {
    private static let maximumPreviewBytes = 1_048_576
    private static let preferredPreviewSize = NSSize(width: 1_280, height: 900)

    override func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        self.view = visualEffectView
        preferredContentSize = Self.preferredPreviewSize
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configurePreviewWindow()
    }

    private func configurePreviewWindow() {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.hasShadow = true
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Quick Look may reuse the controller across files; clear previous content.
        view.subviews.forEach { $0.removeFromSuperview() }
        // Reassert the preferred size after Quick Look has attached the controller.
        // Some hosts query it before `loadView()` completes.
        preferredContentSize = Self.preferredPreviewSize

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int.init) ?? 0
        let isTruncated = fileSize > Self.maximumPreviewBytes
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumPreviewBytes) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let contentType = UTType(filenameExtension: url.pathExtension) ?? .plainText

        let swiftUIView = PreviewRootView(
            model: PreviewModel(
                text: text,
                contentType: contentType,
                fileExtension: url.pathExtension,
                isTruncated: isTruncated
            )
        )
        let hosting = NSHostingView(rootView: swiftUIView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let brandingBadge = makeBrandingBadge()
        view.addSubview(brandingBadge, positioned: .above, relativeTo: hosting)
        NSLayoutConstraint.activate([
            brandingBadge.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            brandingBadge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
    }

    private func makeBrandingBadge() -> NSVisualEffectView {
        let badge = NSVisualEffectView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.material = .hudWindow
        badge.blendingMode = .withinWindow
        badge.state = .active
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 10
        badge.setAccessibilityLabel("Preview provided by Neon Vision Editor Quick Look")

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Neon Vision Editor Quick Look")
        icon.contentTintColor = .controlAccentColor

        let label = NSTextField(labelWithString: "NVE Quick Look")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor

        let stack = NSStackView(views: [icon, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        badge.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: badge.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -5)
        ])
        return badge
    }
}
