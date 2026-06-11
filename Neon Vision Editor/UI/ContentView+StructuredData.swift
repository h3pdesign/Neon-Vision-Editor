import SwiftUI
import Foundation

extension ContentView {
    @ViewBuilder
    var structuredDataModeControl: some View {
        if isDelimitedFileLanguage {
            delimitedModeControl
        } else if isPlistDocument {
            plistModeControl
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
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(snapshot.rows.enumerated()), id: \.offset) { index, row in
                                delimitedRowView(cells: row, isHeader: false, rowIndex: index)
                            }
                        } header: {
                            delimitedRowView(cells: snapshot.header, isHeader: true, rowIndex: nil)
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

    private func delimitedRowView(cells: [String], isHeader: Bool, rowIndex: Int?) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(size: 12, weight: isHeader ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, isHeader ? 7 : 6)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 1)
                    }
            }
        }
        .background(
            isHeader
            ? Color.secondary.opacity(0.12)
            : ((rowIndex ?? 0).isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear)
        )
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
