import Foundation
#if os(macOS)
import AppKit
import CoreText
#elseif canImport(UIKit)
import UIKit
#endif
#if os(macOS) || os(iOS)
import WebKit
#endif

final class MarkdownPreviewPDFRenderer: NSObject, WKNavigationDelegate {
    enum ExportMode {
        case paginatedFit
        case onePageFit
    }

    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?
    private var retainedSelf: MarkdownPreviewPDFRenderer?
    private var sourceHTML: String = ""
    private var exportMode: ExportMode = .paginatedFit
    private var measuredBlockBottoms: [CGFloat] = []
    private static let exportMeasurementPadding: CGFloat = 28
    private static let onePageExportPadding: CGFloat = 8
    private static let exportBottomSafetyMargin: CGFloat = 1024
    private static let onePageBottomSafetyMargin: CGFloat = 24
    private static let onePageMinimumHeight: CGFloat = 120
    private static let a4PaperRect = CGRect(x: 0, y: 0, width: 595, height: 842)

    @MainActor
    static func render(html: String, mode: ExportMode) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let renderer = MarkdownPreviewPDFRenderer()
            renderer.retainedSelf = renderer
            renderer.continuation = continuation
            renderer.exportMode = mode
            renderer.sourceHTML = html
            renderer.start(html: html)
        }
    }

    @MainActor
    private func start(html: String) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
#if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
#else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
#endif
        webView.navigationDelegate = self
        let initialWidth: CGFloat
        switch exportMode {
        case .paginatedFit:
            initialWidth = Self.a4PaperRect.width
        case .onePageFit:
            initialWidth = Self.a4PaperRect.width
        }
        webView.frame = CGRect(x: 0, y: 0, width: initialWidth, height: 1800)
        self.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resetWebViewScrollPosition(webView)
        let script = """
        (async () => {
          window.scrollTo(0, 0);
          const body = document.body;
          const html = document.documentElement;
          const root = document.querySelector('.content') || body;
          const scrolling = document.scrollingElement || html;
          const exportPadding = \(Int(exportMode == .onePageFit ? Self.onePageExportPadding : Self.exportMeasurementPadding));
          const bottomSafetyMargin = \(Int(exportMode == .onePageFit ? Self.onePageBottomSafetyMargin : Self.exportBottomSafetyMargin));
          const minimumHeight = \(Int(exportMode == .onePageFit ? Self.onePageMinimumHeight : 900));
          if (document.fonts && document.fonts.ready) {
            try { await document.fonts.ready; } catch (_) {}
          }
          body.style.margin = '0';
          body.style.padding = `${exportPadding}px`;
          body.style.overflow = 'visible';
          html.style.overflow = 'visible';
          body.style.height = 'auto';
          html.style.height = 'auto';
          await new Promise(resolve =>
            requestAnimationFrame(() =>
              requestAnimationFrame(resolve)
            )
          );
          const rootRect = root.getBoundingClientRect();
          const bodyRect = body.getBoundingClientRect();
          const range = document.createRange();
          range.selectNodeContents(root);
          const rangeRect = range.getBoundingClientRect();
          const blockBottoms = Array.from(root.children)
            .map(node => Math.ceil(node.getBoundingClientRect().bottom - bodyRect.top))
            .filter(value => Number.isFinite(value) && value > 0);
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
          let lastElement = root;
          while (walker.nextNode()) {
            lastElement = walker.currentNode;
          }
          const lastElementRect = lastElement.getBoundingClientRect();
          const measuredBottom = Math.max(
            rootRect.bottom,
            rangeRect.bottom,
            lastElementRect.bottom
          );
          const width = Math.max(
            Math.ceil(body.scrollWidth),
            Math.ceil(html.scrollWidth),
            Math.ceil(scrolling.scrollWidth),
            Math.ceil(root.scrollWidth),
            Math.ceil(root.getBoundingClientRect().width) + exportPadding * 2,
            \(Int(Self.a4PaperRect.width))
          );
          const height = Math.max(
            Math.ceil(body.scrollHeight),
            Math.ceil(html.scrollHeight),
            Math.ceil(scrolling.scrollHeight),
            Math.ceil(scrolling.offsetHeight),
            Math.ceil(root.scrollHeight),
            Math.ceil(root.getBoundingClientRect().height) + exportPadding * 2,
            Math.ceil(measuredBottom - Math.min(bodyRect.top, rootRect.top)) + exportPadding * 2 + bottomSafetyMargin,
            minimumHeight
          );
          return [width, height, blockBottoms];
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            self.measuredBlockBottoms = self.blockBottoms(from: value)
            let rect = self.bestEffortPDFRect(javaScriptValue: value, webView: webView, error: error)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    self.resetWebViewScrollPosition(webView)
                    let output: Data
                    switch self.exportMode {
                    case .onePageFit:
                        try await self.prepareWebViewForPDFCapture(webView, rect: rect)
                        let fullData = try await self.createPDFData(from: webView, rect: rect)
                        output = self.flexibleSinglePagePDFData(from: fullData)
                    case .paginatedFit:
                        output = try await self.paginatedPDFData(from: webView, fullRect: rect)
                    }
                    self.finish(with: .success(output))
                } catch {
                    self.finish(with: .failure(error))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func pdfRect(from javaScriptValue: Any?) -> CGRect? {
        guard let values = javaScriptValue as? [Any], values.count >= 2,
              let widthNumber = values[0] as? NSNumber,
              let heightNumber = values[1] as? NSNumber else { return nil }
        let width = max(640.0, min(8192.0, widthNumber.doubleValue))
        let minimumHeight = exportMode == .onePageFit ? Self.onePageMinimumHeight : 900.0
        let height = max(minimumHeight, heightNumber.doubleValue)
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private func blockBottoms(from javaScriptValue: Any?) -> [CGFloat] {
        guard let values = javaScriptValue as? [Any], values.count >= 3 else { return [] }
        guard let numbers = values[2] as? [NSNumber] else { return [] }
        return numbers.map { CGFloat($0.doubleValue) }.filter { $0.isFinite && $0 > 0 }.sorted()
    }

    private func bestEffortPDFRect(javaScriptValue: Any?, webView: WKWebView, error: Error?) -> CGRect {
        let jsRect = pdfRect(from: javaScriptValue)
        let contentSize: CGSize
#if os(macOS)
        contentSize = webView.enclosingScrollView?.documentView?.frame.size ?? .zero
#else
        contentSize = webView.scrollView.contentSize
#endif
        let scrollRect = CGRect(
            x: 0,
            y: 0,
            width: max(640.0, min(8192.0, contentSize.width)),
            height: max(900.0, contentSize.height)
        )
        let fallbackRect = CGRect(x: 0, y: 0, width: 1024, height: 3000)
        if let jsRect {
            let mergedRect = CGRect(
                x: 0,
                y: 0,
                width: max(jsRect.width, scrollRect.width),
                height: max(jsRect.height, scrollRect.height)
            )
            if error == nil {
                return mergedRect
            }
            return mergedRect
        }
        if scrollRect.height > 1200 {
            return scrollRect
        }
        return fallbackRect
    }

    @MainActor
    private func resetWebViewScrollPosition(_ webView: WKWebView) {
#if os(macOS)
        if let clipView = webView.enclosingScrollView?.contentView {
            clipView.scroll(to: .zero)
            webView.enclosingScrollView?.reflectScrolledClipView(clipView)
        }
#else
        webView.scrollView.setContentOffset(.zero, animated: false)
#endif
    }

    private func finish(with result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        webView?.navigationDelegate = nil
        webView = nil
        retainedSelf = nil
    }

    @MainActor
    private func createPDFData(from webView: WKWebView, rect: CGRect) async throws -> Data {
#if os(macOS)
        let data = webView.dataWithPDF(inside: rect)
        if isUsablePDFData(data) {
            return data
        }
#endif
        return try await withCheckedThrowingContinuation { continuation in
            let config = WKPDFConfiguration()
            config.rect = rect
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    private func prepareWebViewForPDFCapture(_ webView: WKWebView, rect: CGRect) async throws {
        webView.frame = rect
        resetWebViewScrollPosition(webView)
#if os(macOS)
        webView.layoutSubtreeIfNeeded()
#else
        webView.layoutIfNeeded()
#endif
        try? await Task.sleep(nanoseconds: 50_000_000)
#if os(macOS)
        webView.layoutSubtreeIfNeeded()
#else
        webView.layoutIfNeeded()
#endif
    }

    @MainActor
    private func paginatedPDFData(from webView: WKWebView, fullRect: CGRect) async throws -> Data {
        try await prepareWebViewForPDFCapture(webView, rect: fullRect)
        if let sliced = try await paginatedA4PDFDataByCapturingSlices(
            from: webView,
            fullRect: fullRect,
            preferredBlockBottoms: measuredBlockBottoms
        ) {
            return sliced
        }
#if os(macOS)
        if let attributedPaginated = macPaginatedAttributedPDFData(fromHTML: sourceHTML),
           isUsablePDFData(attributedPaginated) {
            return attributedPaginated
        }
        if let nativePaginated = macPaginatedPDFData(from: webView, rect: fullRect),
           isUsablePDFData(nativePaginated) {
            return nativePaginated
        }
#endif
        let fullData = try await createPDFData(from: webView, rect: fullRect)
        if let paginated = paginatedA4PDFData(
            fromSinglePagePDF: fullData,
            preferredBlockBottoms: measuredBlockBottoms
        ) {
            return paginated
        }
        return fullData
    }

    @MainActor
    private func paginatedA4PDFDataByCapturingSlices(
        from webView: WKWebView,
        fullRect: CGRect,
        preferredBlockBottoms: [CGFloat]
    ) async throws -> Data? {
        guard fullRect.width > 1, fullRect.height > 1 else { return nil }

        let paperRect = Self.a4PaperRect
        let printableRect = paperRect.insetBy(dx: 36, dy: 36)
        let scale = max(0.001, min(printableRect.width / fullRect.width, 1.0))
        let sourceSliceHeight = max(printableRect.height / scale, 1.0)
        let pageRanges = Self.paginatedSourceRanges(
            sourceHeight: fullRect.height,
            preferredBlockBottoms: preferredBlockBottoms,
            sliceHeight: sourceSliceHeight
        )

        let outputData = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: outputData as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            return nil
        }

        let mediaBoxInfo: [CFString: Any] = [kCGPDFContextMediaBox: paperRect]
        for range in pageRanges {
            let captureHeight = max(range.bottom - range.top, 1.0)
            let captureRect = CGRect(
                x: fullRect.minX,
                y: fullRect.minY + range.top,
                width: fullRect.width,
                height: captureHeight
            )
            let sliceData = try await createPDFData(from: webView, rect: captureRect)
            guard
                let provider = CGDataProvider(data: sliceData as CFData),
                let sliceDocument = CGPDFDocument(provider),
                sliceDocument.numberOfPages >= 1,
                let slicePage = sliceDocument.page(at: 1)
            else {
                context.closePDF()
                return nil
            }

            let sliceRect = slicePage.getBoxRect(.cropBox).standardized
            guard sliceRect.width > 1, sliceRect.height > 1 else {
                context.closePDF()
                return nil
            }

            let scaledHeight = min(sliceRect.height * scale, printableRect.height)
            let contentRect = CGRect(
                x: printableRect.minX,
                y: printableRect.maxY - scaledHeight,
                width: printableRect.width,
                height: scaledHeight
            )

            context.beginPDFPage(mediaBoxInfo as CFDictionary)
            context.saveGState()
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            context.fill(paperRect)
            let transform = slicePage.getDrawingTransform(
                .cropBox,
                rect: contentRect,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.concatenate(transform)
            context.drawPDFPage(slicePage)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()

        let result = outputData as Data
        return isUsablePDFData(result) ? result : nil
    }

#if os(macOS)
    private func macPaginatedAttributedPDFData(fromHTML html: String) -> Data? {
        guard let htmlData = html.data(using: .utf8) else { return nil }
        let readingOptions: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attributed = try? NSMutableAttributedString(
            data: htmlData,
            options: readingOptions,
            documentAttributes: nil
        ) else {
            return nil
        }

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let outputData = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: outputData as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            return nil
        }

        let paperRect = Self.a4PaperRect
        let printableRect = paperRect.insetBy(dx: 36, dy: 36)
        let textFrameRect = printableRect.insetBy(dx: 0, dy: 14)
        let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: paperRect]
        var currentRange = CFRange(location: 0, length: 0)

        repeat {
            context.beginPDFPage(pageInfo as CFDictionary)
            context.saveGState()
            context.setFillColor(NSColor.white.cgColor)
            context.fill(paperRect)
            context.textMatrix = .identity

            let path = CGMutablePath()
            path.addRect(textFrameRect)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)
            context.restoreGState()
            context.endPDFPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else {
                context.closePDF()
                return nil
            }
            currentRange.location += visibleRange.length
        } while currentRange.location < attributed.length

        context.closePDF()
        let result = outputData as Data
        return isUsablePDFData(result) ? result : nil
    }

    @MainActor
    private func macPaginatedPDFData(from webView: WKWebView, rect: CGRect) -> Data? {
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        printInfo.paperSize = NSSize(width: Self.a4PaperRect.width, height: Self.a4PaperRect.height)
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let outputData = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(
            with: webView,
            inside: CGRect(origin: .zero, size: rect.size),
            to: outputData,
            printInfo: printInfo
        )
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { return nil }

        let result = outputData as Data
        return isUsablePDFData(result) ? result : nil
    }
#endif

    private func isUsablePDFData(_ data: Data) -> Bool {
        guard data.count > 2_000,
              let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0,
              let firstPage = document.page(at: 1)
        else {
            return false
        }
        let rect = firstPage.getBoxRect(.cropBox).standardized
        return rect.width > 0 && rect.height > 0
    }

    private func paginatedA4PDFData(fromSinglePagePDF data: Data, preferredBlockBottoms: [CGFloat]) -> Data? {
        let normalizedData = stitchedSinglePagePDFDataIfNeeded(from: data) ?? data
        guard
            let provider = CGDataProvider(data: normalizedData as CFData),
            let sourceDocument = CGPDFDocument(provider),
            sourceDocument.numberOfPages >= 1,
            let sourcePage = sourceDocument.page(at: 1)
        else {
            return nil
        }

        let sourceRect = sourcePage.getBoxRect(.cropBox).standardized
        guard sourceRect.width > 1, sourceRect.height > 1 else {
            return nil
        }

        let paperRect = Self.a4PaperRect
        let printableRect = paperRect.insetBy(dx: 36, dy: 36)
        let scale = max(0.001, min(printableRect.width / sourceRect.width, 1.0))
        let sourceSliceHeight = max(printableRect.height / scale, 1.0)
        let pageRanges = Self.paginatedSourceRanges(
            sourceHeight: sourceRect.height,
            preferredBlockBottoms: preferredBlockBottoms,
            sliceHeight: sourceSliceHeight
        )

        let outputData = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: outputData as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            return nil
        }

        let mediaBoxInfo: [CFString: Any] = [kCGPDFContextMediaBox: paperRect]
        for range in pageRanges {
            let sliceBottomY = max(sourceRect.minY, min(sourceRect.maxY, sourceRect.maxY - range.bottom))
            let sliceHeight = max((range.bottom - range.top) * scale, 1.0)
            let contentRect = CGRect(
                x: printableRect.minX,
                y: printableRect.maxY - min(sliceHeight, printableRect.height),
                width: printableRect.width,
                height: min(sliceHeight, printableRect.height)
            )

            context.beginPDFPage(mediaBoxInfo as CFDictionary)
            context.saveGState()
            context.clip(to: contentRect)
            context.translateBy(
                x: printableRect.minX - (sourceRect.minX * scale),
                y: contentRect.minY - (sliceBottomY * scale)
            )
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(sourcePage)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()

        let result = outputData as Data
        return isUsablePDFData(result) ? result : nil
    }

    static func paginatedSourceRanges(
        sourceHeight: CGFloat,
        preferredBlockBottoms: [CGFloat],
        sliceHeight: CGFloat
    ) -> [(top: CGFloat, bottom: CGFloat)] {
        let sortedBottoms = preferredBlockBottoms
            .filter { $0 > 0 && $0 < sourceHeight }
            .sorted()

        let minimumFill = max(sliceHeight * 0.55, 1.0)
        var ranges: [(top: CGFloat, bottom: CGFloat)] = []
        var pageTop: CGFloat = 0

        while pageTop < sourceHeight - 0.5 {
            let tentativeBottom = min(pageTop + sliceHeight, sourceHeight)
            let minimumBottom = min(sourceHeight, pageTop + minimumFill)
            let preferredBottom = sortedBottoms.last(where: { $0 >= minimumBottom && $0 <= tentativeBottom }) ?? tentativeBottom
            let pageBottom = max(preferredBottom, min(tentativeBottom, sourceHeight))

            ranges.append((top: pageTop, bottom: pageBottom))

            if pageBottom >= sourceHeight - 0.5 {
                break
            }

            pageTop = pageBottom
        }

        if ranges.isEmpty {
            return [(top: 0, bottom: sourceHeight)]
        }
        return ranges
    }

    private func flexibleSinglePagePDFData(from data: Data) -> Data {
        stitchedSinglePagePDFDataIfNeeded(from: data) ?? data
    }

    private func stitchedSinglePagePDFDataIfNeeded(from data: Data) -> Data? {
        guard
            let provider = CGDataProvider(data: data as CFData),
            let sourceDocument = CGPDFDocument(provider),
            sourceDocument.numberOfPages > 1
        else {
            return nil
        }

        var pages: [(page: CGPDFPage, rect: CGRect)] = []
        var maxWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for index in 1...sourceDocument.numberOfPages {
            guard let page = sourceDocument.page(at: index) else { continue }
            let rect = page.getBoxRect(.cropBox).standardized
            guard rect.width > 0, rect.height > 0 else { continue }
            pages.append((page, rect))
            maxWidth = max(maxWidth, rect.width)
            totalHeight += rect.height
        }

        guard !pages.isEmpty, maxWidth > 0, totalHeight > 0 else {
            return nil
        }

        let outputRect = CGRect(x: 0, y: 0, width: maxWidth, height: totalHeight)
        let outputData = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: outputData as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            return nil
        }

        let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: outputRect]
        context.beginPDFPage(pageInfo as CFDictionary)

        var currentTop = outputRect.maxY
        for entry in pages {
            currentTop -= entry.rect.height
            context.saveGState()
            context.translateBy(
                x: -entry.rect.minX,
                y: currentTop - entry.rect.minY
            )
            context.drawPDFPage(entry.page)
            context.restoreGState()
        }

        context.endPDFPage()
        context.closePDF()

        let result = outputData as Data
        return isUsablePDFData(result) ? result : nil
    }
}
