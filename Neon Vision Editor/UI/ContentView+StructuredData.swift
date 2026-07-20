import SwiftUI
import Foundation

extension ContentView {
    @ViewBuilder
    var structuredDataModeControl: some View {
        if isDelimitedFileLanguage {
            delimitedModeControl
        } else if isPlistDocument {
            plistModeControl
        } else if isAppleCrashReportDocument {
            crashReportModeControl
        } else {
            EmptyView()
        }
    }

    private var delimitedModeControl: some View {
        Group {
#if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .phone && liveContainerWidth < 430 {
                VStack(alignment: .leading, spacing: 8) {
                    delimitedModePicker
                        .frame(maxWidth: .infinity)
                    structuredDelimitedStatus
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    delimitedModePicker
                    structuredDelimitedStatus
                    Spacer(minLength: 0)
                }
            }
#else
            HStack(spacing: 10) {
                delimitedModePicker
                structuredDelimitedStatus
                Spacer(minLength: 0)
            }
#endif
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            structuredHeaderBackgroundShape
                .fill(delimitedHeaderBackgroundColor)
        }
    }

    private var plistModeControl: some View {
        Group {
#if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .phone && liveContainerWidth < 430 {
                VStack(alignment: .leading, spacing: 8) {
                    plistModePicker
                        .frame(maxWidth: .infinity)
                    structuredPlistStatus
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    plistModePicker
                    structuredPlistStatus
                    Spacer(minLength: 0)
                }
            }
#else
            HStack(spacing: 10) {
                plistModePicker
                structuredPlistStatus
                Spacer(minLength: 0)
            }
#endif
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            structuredHeaderBackgroundShape
                .fill(delimitedHeaderBackgroundColor)
        }
    }

    private var crashReportModeControl: some View {
        HStack(spacing: 10) {
            crashReportModePicker
            structuredCrashReportStatus
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            structuredHeaderBackgroundShape
                .fill(delimitedHeaderBackgroundColor)
        }
    }

    private var delimitedModePicker: some View {
        Picker("CSV/TSV View Mode", selection: $delimitedViewMode) {
            Text("Table").tag(DelimitedViewMode.table)
            Text("Text").tag(DelimitedViewMode.text)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 210)
        .accessibilityLabel("CSV or TSV view mode")
        .accessibilityHint("Switch between table mode and raw text mode")
    }

    @ViewBuilder
    private var structuredDelimitedStatus: some View {
        if shouldShowDelimitedTable {
            if isBuildingDelimitedTable {
                ProgressView()
                    .scaleEffect(0.85)
            } else if let snapshot = delimitedTableSnapshot {
                Text(
                    snapshot.truncated
                    ? "Showing \(snapshot.displayedRows) / \(snapshot.totalRows) rows"
                    : "\(snapshot.totalRows) rows"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !delimitedTableStatus.isEmpty {
                Text(delimitedTableStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var plistModePicker: some View {
        Picker("Plist View Mode", selection: $plistViewMode) {
            Text("Structure").tag(PlistViewMode.structure)
            Text("Text").tag(PlistViewMode.text)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .accessibilityLabel("plist view mode")
        .accessibilityHint("Switch between structured plist mode and raw text mode")
    }

    private var crashReportModePicker: some View {
        Picker("Crash Report View Mode", selection: $crashReportViewMode) {
            Text("Summary").tag(CrashReportViewMode.structure)
            Text("Text").tag(CrashReportViewMode.text)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .accessibilityLabel("Apple crash report view mode")
        .accessibilityHint("Switch between a categorized crash summary and raw text")
    }

    @ViewBuilder
    private var structuredPlistStatus: some View {
        if shouldShowPlistStructure {
            if isBuildingPlistStructure {
                ProgressView()
                    .scaleEffect(0.85)
            } else if !plistStructureNodes.isEmpty {
                Text("\(plistStructureNodes.count) root items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !plistStructureStatus.isEmpty {
                Text(plistStructureStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var structuredHeaderBackgroundShape: UnevenRoundedRectangle {
#if os(macOS)
        if shouldUseSplitView {
            return UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        }
#endif
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var delimitedHeaderBackgroundColor: Color {
#if os(macOS)
        currentEditorTheme(colorScheme: colorScheme).background
#else
        Color(.systemBackground)
#endif
    }

    var delimitedTableView: some View {
        Group {
            if isBuildingDelimitedTable {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Building table view…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = delimitedTableSnapshot {
                let isEditable = !snapshot.truncated && viewModel.selectedTab?.isReadOnlyPreview != true
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(snapshot.rows.enumerated()), id: \.offset) { index, row in
                                delimitedRowView(cells: row, isHeader: false, rowIndex: index, isEditable: isEditable)
                            }
                        } header: {
                            delimitedRowView(cells: snapshot.header, isHeader: true, rowIndex: nil, isEditable: isEditable)
                                .zIndex(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(delimitedTableStatus.isEmpty ? "No rows found." : delimitedTableStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            Group {
                if enableTranslucentWindow {
                    Color.clear.background(editorSurfaceBackgroundStyle)
                } else {
                    #if os(iOS) || os(visionOS)
                    iOSNonTranslucentSurfaceColor
                    #else
                    Color.clear
                    #endif
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CSV or TSV table")
    }

    var plistStructureView: some View {
        Group {
            if isBuildingPlistStructure {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Parsing plist structure…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !plistStructureNodes.isEmpty {
                List(plistStructureNodes, children: \.optionalChildren) { node in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(node.key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(node.kind.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(plistKindColor(node.kind))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(plistKindColor(node.kind).opacity(0.16))
                            )
                        if !node.value.isEmpty {
                            Text(node.value)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(node.key), \(node.kind)")
                    .accessibilityValue(node.value)
                }
                .listStyle(.inset)
            } else {
                Text(plistStructureStatus.isEmpty ? "No plist data found." : plistStructureStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            Group {
                if enableTranslucentWindow {
                    Color.clear.background(editorSurfaceBackgroundStyle)
                } else {
                    #if os(iOS) || os(visionOS)
                    iOSNonTranslucentSurfaceColor
                    #else
                    Color.clear
                    #endif
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("plist structure")
    }

    var crashReportStructureView: some View {
        Group {
            if isBuildingCrashReportStructure {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reading crash report…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !crashReportSections.isEmpty {
                List {
                    ForEach(crashReportSections) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.key)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .frame(minWidth: 110, alignment: .leading)
                                    Text(entry.value)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(3)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    Text(entry.severity.rawValue.uppercased())
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(crashReportSeverityColor(entry.severity))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(crashReportSeverityColor(entry.severity).opacity(0.16))
                                        )
                                }
                                .accessibilityLabel("\(entry.key), \(entry.severity.rawValue)")
                                .accessibilityValue(entry.value)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                Text(crashReportStatus.isEmpty ? "No Apple crash report data found." : crashReportStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            Group {
                if enableTranslucentWindow {
                    Color.clear.background(editorSurfaceBackgroundStyle)
                } else {
                    #if os(iOS) || os(visionOS)
                    iOSNonTranslucentSurfaceColor
                    #else
                    Color.clear
                    #endif
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Apple crash report summary")
    }

    private func crashReportSeverityColor(_ severity: AppleCrashReportSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func plistKindColor(_ kind: String) -> Color {
        switch kind {
        case "dictionary": return .blue
        case "array": return .purple
        case "string": return .green
        case "number": return .orange
        case "bool": return .teal
        case "date": return .pink
        case "data": return .indigo
        default: return .secondary
        }
    }

    private func delimitedRowView(cells: [String], isHeader: Bool, rowIndex: Int?, isEditable: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { columnIndex, cell in
                delimitedCellView(
                    cell,
                    isHeader: isHeader,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    isEditable: isEditable
                )
            }
        }
        .background(
            isHeader
            ? delimitedTableHeaderBackgroundColor
            : ((rowIndex ?? 0).isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if isHeader {
                Rectangle()
                    .fill(Color.secondary.opacity(0.26))
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var structuredCrashReportStatus: some View {
        if shouldShowCrashReportStructure {
            if isBuildingCrashReportStructure {
                ProgressView()
                    .scaleEffect(0.85)
            } else if !crashReportSections.isEmpty {
                Text("\(crashReportSections.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !crashReportStatus.isEmpty {
                Text(crashReportStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func delimitedCellView(
        _ cell: String,
        isHeader: Bool,
        rowIndex: Int?,
        columnIndex: Int,
        isEditable: Bool
    ) -> some View {
        let columnWidth = delimitedColumnWidth(for: columnIndex)
        return Group {
            if isEditable {
                DelimitedTableCellEditor(
                    value: cell,
                    isHeader: isHeader,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    onCommit: { value in
                        commitDelimitedTableCellEdit(
                            rowIndex: rowIndex,
                            columnIndex: columnIndex,
                            value: value
                        )
                    }
                )
            } else {
                Text(cell)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 12, weight: isHeader ? .semibold : .regular, design: .monospaced))
        .frame(width: columnWidth, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, isHeader ? 7 : 6)
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 1)
                if isHeader {
                    DelimitedColumnWidthHandle(
                        columnIndex: columnIndex,
                        width: columnWidth,
                        minWidth: delimitedMinimumColumnWidth,
                        maxWidth: delimitedMaximumColumnWidth,
                        onResize: { newWidth in
                            setDelimitedColumnWidth(newWidth, for: columnIndex)
                        },
                        onReset: {
                            resetDelimitedColumnWidth(for: columnIndex)
                        }
                    )
                }
            }
        }
    }

    private var delimitedDefaultColumnWidth: CGFloat { 220 }
    private var delimitedMinimumColumnWidth: CGFloat { 120 }
    private var delimitedMaximumColumnWidth: CGFloat { 520 }

    private func delimitedColumnWidth(for columnIndex: Int) -> CGFloat {
        let storedWidth = delimitedColumnWidths[columnIndex].map { CGFloat($0) } ?? delimitedDefaultColumnWidth
        return min(max(storedWidth, delimitedMinimumColumnWidth), delimitedMaximumColumnWidth)
    }

    private func setDelimitedColumnWidth(_ width: CGFloat, for columnIndex: Int) {
        let boundedWidth = min(max(width, delimitedMinimumColumnWidth), delimitedMaximumColumnWidth)
        delimitedColumnWidths[columnIndex] = Double(boundedWidth.rounded())
    }

    private func resetDelimitedColumnWidth(for columnIndex: Int) {
        delimitedColumnWidths.removeValue(forKey: columnIndex)
    }

    private var delimitedTableHeaderBackgroundColor: Color {
#if os(macOS)
        currentEditorTheme(colorScheme: colorScheme).background
#else
        Color(.systemBackground)
#endif
    }

    private func commitDelimitedTableCellEdit(rowIndex: Int?, columnIndex: Int, value: String) {
        guard var snapshot = delimitedTableSnapshot, !snapshot.truncated else { return }
        let trimmedColumnIndex = max(0, columnIndex)
        if let rowIndex {
            guard snapshot.rows.indices.contains(rowIndex),
                  snapshot.rows[rowIndex].indices.contains(trimmedColumnIndex),
                  snapshot.rows[rowIndex][trimmedColumnIndex] != value else { return }
            snapshot.rows[rowIndex][trimmedColumnIndex] = value
        } else {
            guard snapshot.header.indices.contains(trimmedColumnIndex),
                  snapshot.header[trimmedColumnIndex] != value else { return }
            snapshot.header[trimmedColumnIndex] = value
        }
        delimitedTableSnapshot = snapshot
        currentContentBinding.wrappedValue = serializedDelimitedTable(snapshot)
    }

    private func serializedDelimitedTable(_ snapshot: DelimitedTableSnapshot) -> String {
        let separator = delimitedSeparator
        let separatorString = String(separator)
        let source = currentContentBinding.wrappedValue
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        let hasTrailingLineBreak = source.hasSuffix("\n") || source.hasSuffix("\r")
        let allRows = [snapshot.header] + snapshot.rows
        var output = allRows
            .map { row in
                row.map { serializedDelimitedField($0, separator: separator) }
                    .joined(separator: separatorString)
            }
            .joined(separator: newline)
        if hasTrailingLineBreak {
            output += newline
        }
        return output
    }

    private func serializedDelimitedField(_ field: String, separator: Character) -> String {
        if field.contains(separator) || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    func scheduleDelimitedTableRebuild() {
        guard isDelimitedFileLanguage else {
            delimitedParseTask?.cancel()
            isBuildingDelimitedTable = false
            delimitedTableSnapshot = nil
            delimitedTableStatus = ""
            return
        }
        guard shouldShowDelimitedTable else { return }

        delimitedParseTask?.cancel()
        isBuildingDelimitedTable = true
        let source = currentDelimitedTableSource()
        delimitedTableStatus = source.isLarge ? "Scanning large file…" : "Parsing…"
        let separator = delimitedSeparator
        let expectedTabID = viewModel.selectedTabID
        let expectedContentRevision = viewModel.selectedTab?.contentRevision
        delimitedParseTask = Task {
            let parsed = await Task.detached(priority: .utility) {
                Self.buildDelimitedTableSnapshot(from: source.text, separator: separator, maxRows: 5000, maxColumns: 60)
            }.value
            guard !Task.isCancelled else { return }
            guard viewModel.selectedTabID == expectedTabID else { return }
            if let expectedContentRevision,
               viewModel.selectedTab?.contentRevision != expectedContentRevision {
                return
            }
            isBuildingDelimitedTable = false
            switch parsed {
            case .success(let snapshot):
                delimitedTableSnapshot = snapshot
                delimitedTableStatus = ""
            case .failure(let error):
                delimitedTableSnapshot = nil
                delimitedTableStatus = error.localizedDescription
            }
        }
    }

    private func currentDelimitedTableSource() -> (text: String, isLarge: Bool) {
        if let selectedTab = viewModel.selectedTab {
            return (
                text: selectedTab.content,
                isLarge: selectedTab.isLargeFileCandidate || selectedTab.contentUTF16Length >= ContentView.EditorPerformanceThresholds.heavyFeatureUTF16Length
            )
        }
        let text = currentContentBinding.wrappedValue
        return (
            text: text,
            isLarge: (text as NSString).length >= ContentView.EditorPerformanceThresholds.heavyFeatureUTF16Length
        )
    }

    func scheduleCrashReportStructureRebuild(for text: String) {
        guard isAppleCrashReportDocument else {
            crashReportParseTask?.cancel()
            isBuildingCrashReportStructure = false
            crashReportSections = []
            crashReportStatus = ""
            return
        }
        guard shouldShowCrashReportStructure else { return }

        crashReportParseTask?.cancel()
        isBuildingCrashReportStructure = true
        crashReportStatus = "Reading…"
        let expectedTabID = viewModel.selectedTabID
        let expectedContentRevision = viewModel.selectedTab?.contentRevision
        crashReportParseTask = Task {
            let source = text
            let sections = await Task.detached(priority: .utility) {
                AppleCrashReportParser.sections(from: source)
            }.value
            guard !Task.isCancelled else { return }
            guard viewModel.selectedTabID == expectedTabID else { return }
            if let expectedContentRevision,
               viewModel.selectedTab?.contentRevision != expectedContentRevision {
                return
            }
            isBuildingCrashReportStructure = false
            crashReportSections = sections
            crashReportStatus = sections.isEmpty ? "No recognizable Apple crash details found." : ""
        }
    }

    func schedulePlistStructureRebuild(for text: String) {
        guard isPlistDocument else {
            plistParseTask?.cancel()
            isBuildingPlistStructure = false
            plistStructureNodes = []
            plistStructureStatus = ""
            return
        }
        guard shouldShowPlistStructure else { return }

        plistParseTask?.cancel()
        isBuildingPlistStructure = true
        plistStructureStatus = "Parsing…"
        let expectedTabID = viewModel.selectedTabID
        let expectedContentRevision = viewModel.selectedTab?.contentRevision
        plistParseTask = Task {
            let source = text
            let parsed = await Task.detached(priority: .utility) {
                Self.buildPlistStructureNodes(from: source)
            }.value
            guard !Task.isCancelled else { return }
            guard viewModel.selectedTabID == expectedTabID else { return }
            if let expectedContentRevision,
               viewModel.selectedTab?.contentRevision != expectedContentRevision {
                return
            }
            isBuildingPlistStructure = false
            switch parsed {
            case .success(let nodes):
                plistStructureNodes = nodes
                plistStructureStatus = nodes.isEmpty ? "No plist nodes." : ""
            case .failure(let error):
                plistStructureNodes = []
                plistStructureStatus = error.localizedDescription
            }
        }
    }

    private nonisolated static func buildPlistStructureNodes(from text: String) -> Result<[PlistStructureNode], NSError> {
        let data = Data(text.utf8)
        guard !data.isEmpty else {
            return .failure(
                NSError(domain: "PlistStructure", code: 1, userInfo: [NSLocalizedDescriptionKey: "No plist data in file."])
            )
        }
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return .failure(
                NSError(domain: "PlistStructure", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid plist format."])
            )
        }
        let nodes = plistNodes(from: object, key: "Root", path: "root")
        if nodes.kind == "dictionary" || nodes.kind == "array" {
            return .success(nodes.children)
        }
        return .success([nodes])
    }

    private nonisolated static func plistNodes(from object: Any, key: String, path: String) -> PlistStructureNode {
        if let dict = object as? [String: Any] {
            let sortedKeys = dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let children = sortedKeys.map { childKey in
                plistNodes(from: dict[childKey] as Any, key: childKey, path: "\(path).\(childKey)")
            }
            return PlistStructureNode(
                id: path,
                key: key,
                kind: "dictionary",
                value: "\(dict.count) keys",
                children: children
            )
        }
        if let array = object as? [Any] {
            let children = array.enumerated().map { index, item in
                plistNodes(from: item, key: "[\(index)]", path: "\(path)[\(index)]")
            }
            return PlistStructureNode(
                id: path,
                key: key,
                kind: "array",
                value: "\(array.count) items",
                children: children
            )
        }
        if let stringValue = object as? String {
            return PlistStructureNode(
                id: path,
                key: key,
                kind: "string",
                value: stringValue,
                children: []
            )
        }
        if let numberValue = object as? NSNumber {
            let kind = CFGetTypeID(numberValue) == CFBooleanGetTypeID() ? "bool" : "number"
            return PlistStructureNode(
                id: path,
                key: key,
                kind: kind,
                value: numberValue.stringValue,
                children: []
            )
        }
        if let dateValue = object as? Date {
            return PlistStructureNode(
                id: path,
                key: key,
                kind: "date",
                value: Self.plistISO8601String(from: dateValue),
                children: []
            )
        }
        if let dataValue = object as? Data {
            return PlistStructureNode(
                id: path,
                key: key,
                kind: "data",
                value: "\(dataValue.count) bytes",
                children: []
            )
        }
        return PlistStructureNode(
            id: path,
            key: key,
            kind: "value",
            value: String(describing: object),
            children: []
        )
    }

    private nonisolated static func buildDelimitedTableSnapshot(
        from text: String,
        separator: Character,
        maxRows: Int,
        maxColumns: Int
    ) -> Result<DelimitedTableSnapshot, DelimitedTableParseError> {
        guard !text.isEmpty else { return .failure(DelimitedTableParseError(message: "No data in file.")) }
        var rows: [[String]] = []
        rows.reserveCapacity(min(maxRows, 512))
        var totalRows = 0
        var stoppedEarly = false
        let nsText = text as NSString
        let textLength = nsText.length
        var lineStart = 0
        var idx = 0
        while idx < textLength {
            if nsText.character(at: idx) == 10 {
                let lineEnd = (idx > lineStart && nsText.character(at: idx - 1) == 13) ? (idx - 1) : idx
                let lineLength = max(0, lineEnd - lineStart)
                let line = nsText.substring(with: NSRange(location: lineStart, length: lineLength))
                totalRows += 1
                if rows.count < maxRows {
                    rows.append(parseDelimitedLine(line[...], separator: separator, maxColumns: maxColumns))
                }
                lineStart = idx + 1
                if rows.count >= maxRows {
                    stoppedEarly = lineStart < textLength
                    break
                }
            }
            idx += 1
        }
        if !stoppedEarly && (lineStart < textLength || (textLength > 0 && nsText.character(at: textLength - 1) == 10)) {
            let line = nsText.substring(with: NSRange(location: lineStart, length: max(0, textLength - lineStart)))
            totalRows += 1
            if rows.count < maxRows {
                rows.append(parseDelimitedLine(line[...], separator: separator, maxColumns: maxColumns))
            }
        }
        guard !rows.isEmpty else { return .failure(DelimitedTableParseError(message: "No rows found.")) }
        let rawHeader = rows.removeFirst()
        let visibleColumns = max(rawHeader.count, rows.first?.count ?? 0)
        let header: [String] = {
            if rawHeader.isEmpty {
                return (0..<visibleColumns).map { "Column \($0 + 1)" }
            }
            return rawHeader.enumerated().map { idx, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Column \(idx + 1)" : trimmed
            }
        }()
        let normalizedRows = rows.map { row in
            if row.count >= visibleColumns { return row }
            return row + Array(repeating: "", count: visibleColumns - row.count)
        }
        return .success(
            DelimitedTableSnapshot(
                header: header,
                rows: normalizedRows,
                totalRows: totalRows,
                displayedRows: rows.count,
                truncated: stoppedEarly || totalRows > maxRows
            )
        )
    }

    private nonisolated static func parseDelimitedLine(
        _ line: Substring,
        separator: Character,
        maxColumns: Int
    ) -> [String] {
        if line.isEmpty { return [""] }
        var result: [String] = []
        result.reserveCapacity(min(32, maxColumns))
        var field = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            if next == separator {
                                result.append(field)
                                field.removeAll(keepingCapacity: true)
                            } else {
                                field.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
                continue
            }
            if char == separator && !inQuotes {
                result.append(field)
                field.removeAll(keepingCapacity: true)
                if result.count >= maxColumns {
                    return result
                }
                continue
            }
            field.append(char)
        }
        result.append(field)
        if result.count > maxColumns {
            return Array(result.prefix(maxColumns))
        }
        return result
    }

}

private struct DelimitedTableCellEditor: View {
    let value: String
    let isHeader: Bool
    let rowIndex: Int?
    let columnIndex: Int
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        value: String,
        isHeader: Bool,
        rowIndex: Int?,
        columnIndex: Int,
        onCommit: @escaping (String) -> Void
    ) {
        self.value = value
        self.isHeader = isHeader
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .focused($isFocused)
            .onSubmit(commitIfNeeded)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitIfNeeded()
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    draft = newValue
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(draft)
    }

    private var accessibilityLabel: String {
        if isHeader {
            return "CSV header column \(columnIndex + 1)"
        }
        return "CSV row \((rowIndex ?? 0) + 1) column \(columnIndex + 1)"
    }

    private func commitIfNeeded() {
        guard draft != value else { return }
        onCommit(draft)
    }
}

private struct DelimitedColumnWidthHandle: View {
    let columnIndex: Int
    let width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let onResize: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var dragStartWidth: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.001))
            .frame(width: 14)
            .overlay(alignment: .center) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.36))
                    .frame(width: 2, height: 18)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let startWidth = dragStartWidth ?? width
                        dragStartWidth = startWidth
                        onResize(startWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .contextMenu {
                Button("Reset Column Width", action: onReset)
            }
            .accessibilityElement()
            .accessibilityLabel("Column \(columnIndex + 1) width")
            .accessibilityValue("\(Int(width.rounded())) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onResize(min(width + 20, maxWidth))
                case .decrement:
                    onResize(max(width - 20, minWidth))
                @unknown default:
                    break
                }
            }
    }
}
