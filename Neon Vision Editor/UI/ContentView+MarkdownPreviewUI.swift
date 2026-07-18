import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Markdown Preview UI

extension ContentView {
#if os(macOS) || os(iOS) || os(visionOS)
    @ViewBuilder
    var markdownPreviewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            markdownPreviewPaneHeader
            markdownPreviewWebViewHost
        }
        .onAppear {
            scheduleMarkdownPreviewRender()
        }
        .onDisappear {
            markdownPreviewRenderTask?.cancel()
            markdownPreviewRenderTask = nil
            isMarkdownPreviewRendering = false
            markdownPreviewRenderedHTML = ""
            markdownPreviewRenderSignature = ""
        }
        .onChange(of: currentContent) { _, _ in
            scheduleMarkdownPreviewRender()
        }
        .onChange(of: viewModel.selectedTab?.id) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .onChange(of: markdownPreviewTemplateRaw) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .onChange(of: markdownPreviewBackgroundStyleRaw) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .onChange(of: markdownPreviewDialectRaw) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .onChange(of: markdownPreviewPreferDarkMode) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .onChange(of: enableTranslucentWindow) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .onChange(of: editorFontSize) { _, _ in
            scheduleMarkdownPreviewRender(immediate: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(editorSurfaceBackgroundStyle)
#if canImport(UIKit)
        .fileExporter(
            isPresented: $showMarkdownPDFExporter,
            document: markdownPDFExportDocument,
            contentType: .pdf,
            defaultFilename: markdownPDFExportFilename
        ) { result in
            if case .failure(let error) = result {
                markdownPDFExportErrorMessage = error.localizedDescription
            }
        }
#endif
    }
#endif

    private var markdownPreviewPaneHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text("Markdown Preview")
                .font(.headline)
            Spacer(minLength: 0)
            Button(action: closeCurrentPreview) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Markdown Preview")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(editorSurfaceBackgroundStyle)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
        }
    }

    private var iPhoneMarkdownPreviewWebViewHorizontalInset: CGFloat { 12 }
    @ViewBuilder
    private var markdownPreviewWebViewHost: some View {
#if os(iOS) || os(visionOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            markdownPreviewWebViewContent
                .padding(.horizontal, iPhoneMarkdownPreviewWebViewHorizontalInset)
                .padding(.bottom, 8)
        } else {
            markdownPreviewWebViewContent
        }
#else
        markdownPreviewWebViewContent
#endif
    }

    private var markdownPreviewWebViewContent: some View {
        MarkdownPreviewWebView(
            html: markdownPreviewRenderedHTML.isEmpty
                ? markdownPreviewLoadingHTML(preferDarkMode: markdownPreviewPreferDarkMode)
                : markdownPreviewRenderedHTML,
            baseURL: localPreviewBaseURL,
            allowsContentJavaScript: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Markdown Preview Content")
    }

    private var localPreviewBaseURL: URL? {
        guard let fileURL = viewModel.selectedTab?.fileURL, fileURL.isFileURL else { return nil }
        return fileURL.deletingLastPathComponent()
    }

    @ViewBuilder
    private var markdownPreviewHeader: some View {
#if os(iOS) || os(visionOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            markdownPreviewIPadHeader
        } else {
            markdownPreviewRegularHeader
        }
#else
        markdownPreviewRegularHeader
#endif
    }

    private var markdownPreviewRegularHeader: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("Markdown Preview", comment: ""))
                .font(.headline)

            VStack(spacing: 10) {
                markdownPreviewCombinedPickerCard

                markdownPreviewPrimaryActionRow
                    .padding(.top, 2)

                markdownPreviewSecondaryActionRow
                    .padding(.top, 2)

                Text(markdownPreviewExportSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(NSLocalizedString("Markdown preview export summary", comment: ""))

                markdownPreviewActionStatusView
            }
#if os(iOS) || os(visionOS)
            .frame(minWidth: 320, maxWidth: 420)
#else
            .frame(minWidth: 520, idealWidth: 640, maxWidth: 760)
#endif
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var markdownPreviewIPadHeader: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("Markdown Preview", comment: ""))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 10) {
                markdownPreviewPrimaryActionRow
                    .padding(.top, 2)

                markdownPreviewCombinedPickerCard

                markdownPreviewSecondaryActionRow
                    .padding(.top, 2)

                Text(markdownPreviewExportSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(NSLocalizedString("Markdown preview export summary", comment: ""))

                markdownPreviewActionStatusView
            }
            .frame(maxWidth: 460)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Preview Pickers and Actions

#if os(iOS) || os(visionOS)
    @ViewBuilder
    var markdownPreviewPhoneSettingsMenu: some View {
        Menu {
            Menu {
                ForEach(Self.markdownPreviewTemplateOptions) { option in
                    Button {
                        markdownPreviewTemplateRaw = option.id
                    } label: {
                        if markdownPreviewTemplateRaw == option.id {
                            Label(NSLocalizedString(option.title, comment: ""), systemImage: "checkmark")
                        } else {
                            Text(NSLocalizedString(option.title, comment: ""))
                        }
                    }
                }
            } label: {
                Label(NSLocalizedString("Template", comment: ""), systemImage: "paintbrush")
            }

            Menu {
                Button {
                    markdownPDFExportModeRaw = MarkdownPDFExportMode.paginatedFit.rawValue
                } label: {
                    if markdownPDFExportModeRaw == MarkdownPDFExportMode.paginatedFit.rawValue {
                        Label(NSLocalizedString("Paginated Fit", comment: ""), systemImage: "checkmark")
                    } else {
                        Text(NSLocalizedString("Paginated Fit", comment: ""))
                    }
                }
                Button {
                    markdownPDFExportModeRaw = MarkdownPDFExportMode.onePageFit.rawValue
                } label: {
                    if markdownPDFExportModeRaw == MarkdownPDFExportMode.onePageFit.rawValue {
                        Label(NSLocalizedString("One Page Fit", comment: ""), systemImage: "checkmark")
                    } else {
                        Text(NSLocalizedString("One Page Fit", comment: ""))
                    }
                }
            } label: {
                Label(NSLocalizedString("PDF Mode", comment: ""), systemImage: "doc.text")
            }

            Divider()

            Button {
                exportMarkdownPreviewPDF()
            } label: {
                Label(NSLocalizedString("Export PDF", comment: ""), systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel(NSLocalizedString("Markdown Preview Settings", comment: ""))
    }
#endif

    private var markdownPreviewTemplatePicker: some View {
        Picker(NSLocalizedString("Template", comment: ""), selection: $markdownPreviewTemplateRaw) {
            ForEach(Self.markdownPreviewTemplateOptions) { option in
                Text(NSLocalizedString(option.title, comment: "")).tag(option.id)
            }
        }
        .neonSettingsDropdown(maxWidth: nil)
        .accessibilityLabel(NSLocalizedString("Template", comment: ""))
#if os(iOS) || os(visionOS)
        .frame(maxWidth: .infinity, alignment: .center)
#else
        .frame(minWidth: 120, idealWidth: 190, maxWidth: 220)
#endif
    }

    private var markdownPreviewPDFModePicker: some View {
        Picker(NSLocalizedString("PDF Mode", comment: ""), selection: $markdownPDFExportModeRaw) {
            Text(NSLocalizedString("Paginated Fit", comment: "")).tag(MarkdownPDFExportMode.paginatedFit.rawValue)
            Text(NSLocalizedString("One Page Fit", comment: "")).tag(MarkdownPDFExportMode.onePageFit.rawValue)
        }
        .neonSettingsDropdown(maxWidth: nil)
        .accessibilityLabel(NSLocalizedString("PDF Mode", comment: ""))
#if os(iOS) || os(visionOS)
        .frame(maxWidth: .infinity, alignment: .center)
#else
        .frame(minWidth: 128, idealWidth: 160, maxWidth: 180)
#endif
    }

    private var markdownPreviewExportButton: some View {
        Button {
            exportMarkdownPreviewPDF()
        } label: {
            Label(NSLocalizedString("Export PDF", comment: ""), systemImage: "square.and.arrow.down")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
        .tint(NeonUIStyle.accentBlue)
        .controlSize(.regular)
        .layoutPriority(1)
        .accessibilityLabel(NSLocalizedString("Export Markdown preview as PDF", comment: ""))
    }

    private var markdownPreviewShareButton: some View {
        ShareLink(
            item: markdownPreviewShareHTML,
            preview: SharePreview("\(suggestedMarkdownPreviewBaseName()).html")
        ) {
            Label(NSLocalizedString("Share", comment: ""), systemImage: "square.and.arrow.up")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .layoutPriority(1)
        .accessibilityLabel(NSLocalizedString("Share Markdown preview HTML", comment: ""))
    }

    private var markdownPreviewCopyHTMLButton: some View {
        Button {
            copyMarkdownPreviewHTML()
        } label: {
            Label(NSLocalizedString("Copy HTML", comment: ""), systemImage: "doc.on.doc")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .layoutPriority(1)
        .accessibilityLabel(NSLocalizedString("Copy Markdown preview HTML", comment: ""))
    }

    private var markdownPreviewCopyMarkdownButton: some View {
        Button {
            copyMarkdownPreviewMarkdown()
        } label: {
            Label(NSLocalizedString("Copy Markdown", comment: ""), systemImage: "doc.on.clipboard")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .layoutPriority(1)
        .accessibilityLabel(NSLocalizedString("Copy Markdown source", comment: ""))
    }

    private var markdownPreviewExportSummaryText: String {
        "\(suggestedMarkdownPDFFilename()) • \(suggestedMarkdownPreviewBaseName()).html"
    }

    @ViewBuilder
    private var markdownPreviewActionStatusView: some View {
        if !markdownPreviewActionStatusMessage.isEmpty {
            Text(markdownPreviewActionStatusMessage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NeonUIStyle.accentBlue)
                .multilineTextAlignment(.center)
                .accessibilityLabel(NSLocalizedString("Markdown preview action status", comment: ""))
                .accessibilityValue(markdownPreviewActionStatusMessage)
        }
    }

    @ViewBuilder
    private var markdownPreviewMoreActionsMenu: some View {
        Menu {
            Button {
                copyMarkdownPreviewHTML()
            } label: {
                Label(NSLocalizedString("Copy HTML", comment: ""), systemImage: "doc.on.doc")
            }

            Button {
                copyMarkdownPreviewMarkdown()
            } label: {
                Label(NSLocalizedString("Copy Markdown", comment: ""), systemImage: "doc.on.clipboard")
            }
        } label: {
            Label(NSLocalizedString("More", comment: ""), systemImage: "ellipsis.circle")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .layoutPriority(1)
        .accessibilityLabel(NSLocalizedString("More Markdown preview actions", comment: ""))
    }

    @ViewBuilder
    private var markdownPreviewCombinedPickerCard: some View {
        Group {
            if markdownPreviewUsesStackedIPadPickerLayout {
                HStack(alignment: .top, spacing: markdownPreviewPickerCardSpacing) {
                    markdownPreviewPickerColumn("Template") {
                        markdownPreviewTemplatePicker
                    }

                    markdownPreviewPickerColumn("PDF Mode") {
                        markdownPreviewPDFModePicker
                    }
                }
            } else {
                HStack(alignment: .top, spacing: markdownPreviewPickerCardSpacing) {
                    markdownPreviewPickerColumn("Template") {
                        markdownPreviewTemplatePicker
                    }

                    if markdownPreviewShowsInlineExportControl {
                        markdownPreviewPickerColumn("Export") {
                            markdownPreviewExportButton
                        }
                    }

                    markdownPreviewPickerColumn("PDF Mode") {
                        markdownPreviewPDFModePicker
                    }
                }
            }
        }
        .padding(.horizontal, markdownPreviewPickerCardHorizontalPadding)
        .padding(.vertical, 16)
#if os(iOS) || os(visionOS)
        .frame(maxWidth: markdownPreviewPickerCardMaxWidth, alignment: .center)
#else
        .frame(minWidth: 460, maxWidth: 560, alignment: .center)
#endif
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    // MARK: - Preview Header Layout Helpers

#if os(iOS) || os(visionOS)
    private var markdownPreviewPickerCardSpacing: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 12
        }
        if markdownPreviewUsesStackedIPadPickerLayout {
            return 14
        }
        return markdownPreviewShowsInlineExportControl ? 10 : 12
    }

    private var markdownPreviewPickerCardHorizontalPadding: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 12
        }
        if markdownPreviewUsesStackedIPadPickerLayout {
            return 16
        }
        return markdownPreviewShowsInlineExportControl ? 10 : 12
    }

    private var markdownPreviewPickerCardMaxWidth: CGFloat? {
        UIDevice.current.userInterfaceIdiom == .phone ? nil : 420
    }
#else
    private var markdownPreviewPickerCardSpacing: CGFloat { markdownPreviewShowsInlineExportControl ? 16 : 18 }
    private var markdownPreviewPickerCardHorizontalPadding: CGFloat { markdownPreviewShowsInlineExportControl ? 16 : 18 }
#endif

    private var markdownPreviewShowsInlineExportControl: Bool {
#if os(iOS) || os(visionOS)
        false
#else
        true
#endif
    }

    private var markdownPreviewUsesStackedIPadPickerLayout: Bool {
#if os(iOS) || os(visionOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    @ViewBuilder
    private func markdownPreviewPickerColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            content()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func markdownPreviewActionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var markdownPreviewPrimaryActionRow: some View {
        markdownPreviewActionRow {
            if !markdownPreviewShowsInlineExportControl {
                markdownPreviewExportButton
            }
        }
    }

    @ViewBuilder
    private var markdownPreviewSecondaryActionRow: some View {
#if os(iOS) || os(visionOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            EmptyView()
        } else {
            markdownPreviewActionRow {
                markdownPreviewSecondaryButtons
            }
        }
#else
        markdownPreviewActionRow {
            markdownPreviewSecondaryButtons
        }
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var markdownPreviewSecondaryButtons: some View {
        HStack(spacing: 20) {
            markdownPreviewShareButton
                .frame(maxWidth: .infinity, alignment: .trailing)

            markdownPreviewCopyHTMLButton
                .frame(maxWidth: .infinity, alignment: .center)

            markdownPreviewCopyMarkdownButton
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 620, maxWidth: 680)
    }
#else
    @ViewBuilder
    private var markdownPreviewSecondaryButtons: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    markdownPreviewShareButton
                    markdownPreviewMoreActionsMenu
                }

                VStack(spacing: 10) {
                    markdownPreviewShareButton
                    markdownPreviewMoreActionsMenu
                }
            }
        } else {
            HStack(spacing: 10) {
                markdownPreviewShareButton
                markdownPreviewMoreActionsMenu
            }
        }
    }
#endif
}
