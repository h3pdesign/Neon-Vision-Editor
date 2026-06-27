import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Preview Split Coordination

extension ContentView {
    var isSVGDocument: Bool {
        if viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "svg" {
            return true
        }
        let lowerLanguage = currentLanguage.lowercased()
        guard lowerLanguage == "xml" || lowerLanguage == "svg" else { return false }
        let sample = currentContent.prefix(1024).lowercased()
        return sample.contains("<svg")
    }

    var isHTMLPreviewDocument: Bool {
        if let pathExtension = viewModel.selectedTab?.fileURL?.pathExtension.lowercased(),
           pathExtension == "html" || pathExtension == "htm" || pathExtension == "xhtml" {
            return true
        }
        let lowerLanguage = currentLanguage.lowercased()
        return lowerLanguage == "html" || lowerLanguage == "xhtml"
    }

    var canShowMarkdownPreviewPane: Bool { true }

    var isMarkdownPreviewSplitVisible: Bool {
        canShowMarkdownPreviewSplitPane &&
        showMarkdownPreviewPane &&
        currentLanguage == "markdown" &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }

    var isWebPreviewSplitVisible: Bool {
        canShowWebPreviewSplitPane &&
        (isSVGDocument || isHTMLPreviewDocument) &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }

#if os(iOS) || os(visionOS)
    var markdownPreviewSheetPresentationBinding: Binding<Bool> {
        Binding(
            get: { shouldPresentMarkdownPreviewSheetOnIPhone },
            set: { isPresented in
                if !isPresented {
                    showMarkdownPreviewPane = false
                }
            }
        )
    }
#endif

    @ViewBuilder
    var markdownPreviewSplitPane: some View {
        previewSplitPane {
            markdownPreviewPane
        }
    }

    @ViewBuilder
    var webPreviewSplitPane: some View {
        previewSplitPane {
            webPreviewPane
        }
    }

#if os(macOS)
    var markdownPreviewSplitTransition: some View {
        LinearGradient(
            stops: [
                .init(color: Color.secondary.opacity(0.10), location: 0),
                .init(color: Color.secondary.opacity(0.035), location: 0.45),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 10)
        .accessibilityHidden(true)
    }
#endif

    private var canShowMarkdownPreviewSplitPane: Bool {
#if os(iOS) || os(visionOS)
        canShowPreviewOnCurrentDevice
#else
        true
#endif
    }

    private var canShowWebPreviewSplitPane: Bool {
#if os(iOS) || os(visionOS)
        canShowPreviewOnCurrentDevice
#else
        true
#endif
    }

#if os(iOS) || os(visionOS)
    private var canShowPreviewOnCurrentDevice: Bool {
        horizontalSizeClass == .regular
    }

    private var shouldPresentMarkdownPreviewSheetOnIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone &&
        showMarkdownPreviewPane &&
        currentLanguage == "markdown" &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }
#endif

    @ViewBuilder
    private func previewSplitPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(minWidth: 280, idealWidth: 420, maxWidth: 680, maxHeight: .infinity)
            .background(editorSurfaceBackgroundStyle)
            .clipShape(previewSplitPaneShape)
            .overlay {
                previewSplitPaneShape
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
            .padding(.top, 4)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
    }

    private var previewSplitPaneShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 10,
            topTrailingRadius: 16,
            style: .continuous
        )
    }
}
