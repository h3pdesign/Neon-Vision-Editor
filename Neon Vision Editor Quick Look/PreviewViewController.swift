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

    override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Quick Look may reuse the controller across files; clear previous content.
        view.subviews.forEach { $0.removeFromSuperview() }

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
                fileName: url.lastPathComponent,
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
    }
}
