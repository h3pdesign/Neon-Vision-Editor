import SwiftUI

extension ContentView {
    func prepareTextToJSONStructuring() {
        guard !isStructuringTextAsJSON else { return }
        guard let tab = viewModel.selectedTab else { return }
        guard !tab.isReadOnlyPreview else {
            jsonStructuringErrorMessage = "The current document is read-only."
            return
        }
        let isLargeFile = tab.isLargeFileCandidate || tab.document.utf16Length >= ContentView.EditorPerformanceThresholds.heavyFeatureUTF16Length
        if tab.usesFileBackedStorage && isLargeFile && currentSelectionSnapshotText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jsonStructuringErrorMessage = "Select a section of this large file before structuring it as JSON."
            return
        }
        showJSONStructuringOptions = true
    }

    func startTextToJSONStructuring() {
        showJSONStructuringOptions = false
        guard let tab = viewModel.selectedTab else { return }
        let selectedRange: NSRange? = {
            guard currentSelectionSnapshotTabID == tab.id,
                  let range = currentSelectionSnapshotRange,
                  range.location != NSNotFound,
                  range.length > 0,
                  NSMaxRange(range) <= tab.document.utf16Length else { return nil }
            return range
        }()
        let source: String
        if selectedRange != nil {
            source = currentSelectionSnapshotText
        } else {
            let isLargeFile = tab.isLargeFileCandidate || tab.document.utf16Length >= ContentView.EditorPerformanceThresholds.heavyFeatureUTF16Length
            guard !(tab.usesFileBackedStorage && isLargeFile) else {
                jsonStructuringErrorMessage = "Select a section of this large file before structuring it as JSON."
                return
            }
            source = tab.document.string()
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            jsonStructuringErrorMessage = PlainTextJSONStructureError.emptyDocument.localizedDescription
            return
        }
        jsonStructuringTask?.cancel()
        jsonStructuringTimeoutTask?.cancel()
        let requestID = UUID()
        let usesAppleIntelligence = selectedModel == .appleIntelligence
        let configuredClient = usesAppleIntelligence ? nil : configuredMarkdownConversionClient()
        guard !usesAppleIntelligence || appleModelAvailable else {
            jsonStructuringErrorMessage = PlainTextJSONStructureError.appleIntelligenceUnavailable.localizedDescription
            return
        }
        guard usesAppleIntelligence || configuredClient != nil else {
            jsonStructuringErrorMessage = "Configure the selected AI provider before structuring text as JSON."
            return
        }
        jsonStructuringRequestID = requestID
        jsonStructuringTargetTabID = tab.id
        jsonStructuringTargetRange = selectedRange
        jsonStructuringProviderName = selectedModel.displayName
        isStructuringTextAsJSON = true
        jsonStructuringTask = Task { [source, requestID, configuredClient, mode = jsonStructuringMode, usesAppleIntelligence] in
            do {
                let proposal: PlainTextJSONProposal
                if usesAppleIntelligence {
                    proposal = try await PlainTextJSONConverter.convertWithAppleIntelligence(source, mode: mode)
                } else if let configuredClient {
                    proposal = try await PlainTextJSONConverter.convertWithConfiguredProvider(
                        source,
                        mode: mode,
                        client: configuredClient
                    )
                } else {
                    return
                }
                try Task.checkCancellation()
                guard jsonStructuringRequestID == requestID,
                      viewModel.selectedTabID == tab.id else { return }
                jsonStructuringProposal = proposal
            } catch is CancellationError {
            } catch {
                guard jsonStructuringRequestID == requestID else { return }
                jsonStructuringErrorMessage = error.localizedDescription
            }
            finishTextToJSONStructuring(requestID: requestID)
        }
        jsonStructuringTimeoutTask = Task { [requestID] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000_000)
            } catch { return }
            guard jsonStructuringRequestID == requestID else { return }
            jsonStructuringTask?.cancel()
            jsonStructuringErrorMessage = "JSON structuring timed out after 120 seconds."
            finishTextToJSONStructuring(requestID: requestID)
        }
    }

    func cancelTextToJSONStructuring() {
        jsonStructuringTask?.cancel()
        jsonStructuringTimeoutTask?.cancel()
        if let requestID = jsonStructuringRequestID {
            finishTextToJSONStructuring(requestID: requestID)
        }
    }

    private func finishTextToJSONStructuring(requestID: UUID) {
        guard jsonStructuringRequestID == requestID else { return }
        jsonStructuringRequestID = nil
        jsonStructuringTask = nil
        jsonStructuringTimeoutTask?.cancel()
        jsonStructuringTimeoutTask = nil
        jsonStructuringProviderName = nil
        isStructuringTextAsJSON = false
    }

    func createJSONDocument(from proposal: PlainTextJSONProposal) {
        let sourceName = viewModel.selectedTab?.name ?? "Untitled"
        viewModel.addNewTab()
        guard let tab = viewModel.selectedTab else { return }
        let baseName = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        viewModel.renameTab(tabID: tab.id, newName: "\(baseName).json")
        viewModel.updateTabLanguage(tabID: tab.id, language: "json")
        viewModel.updateTabContent(tabID: tab.id, content: proposal.json)
        jsonStructuringProposal = nil
    }

    func replaceCurrentDocumentWithJSON(from proposal: PlainTextJSONProposal) {
        guard let targetTabID = jsonStructuringTargetTabID,
              viewModel.tabs.contains(where: { $0.id == targetTabID }) else {
            jsonStructuringErrorMessage = "The source document is no longer open."
            jsonStructuringProposal = nil
            return
        }
        if let targetRange = jsonStructuringTargetRange {
            guard viewModel.selectedTabID == targetTabID else {
                jsonStructuringErrorMessage = "Return to the source tab before replacing the selected text."
                return
            }
            NotificationCenter.default.post(
                name: .replaceEditorRangeRequested,
                object: nil,
                userInfo: [
                    EditorCommandUserInfo.documentID: targetTabID.uuidString,
                    EditorCommandUserInfo.rangeLocation: targetRange.location,
                    EditorCommandUserInfo.rangeLength: targetRange.length,
                    EditorCommandUserInfo.replacementText: proposal.json
                ]
            )
        } else {
            viewModel.updateTabContent(tabID: targetTabID, content: proposal.json)
            viewModel.updateTabLanguage(tabID: targetTabID, language: "json")
        }
        jsonStructuringProposal = nil
        jsonStructuringTargetTabID = nil
        jsonStructuringTargetRange = nil
    }

    var jsonStructuringOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Structure Text as JSON")
                .font(.title2.weight(.semibold))
            Text("Choose the categories that best fit the source. The result will be validated JSON and reviewed before it changes your document.")
                .foregroundStyle(.secondary)
            Picker("Structure", selection: $jsonStructuringMode) {
                ForEach(PlainTextJSONStructureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("JSON structure type")
            HStack {
                Button("Cancel", role: .cancel) { showJSONStructuringOptions = false }
                Spacer()
                Button("Structure") { startTextToJSONStructuring() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    @ViewBuilder
    var jsonStructuringProgressBanner: some View {
        if isStructuringTextAsJSON {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Structuring text as JSON with \(jsonStructuringProviderName ?? "AI")…")
                    .font(.callout)
                Button("Cancel") { cancelTextToJSONStructuring() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Structuring text as JSON")
        }
    }

    @ViewBuilder
    var jsonStructuringReviewSheet: some View {
        if let proposal = jsonStructuringProposal {
            DiffComparisonView(
                title: "Review JSON Structure",
                leftTitle: "Original Text",
                rightTitle: "Structured JSON",
                diff: DocumentDiffBuilder.build(leftContent: proposal.source, rightContent: proposal.json),
                onClose: { jsonStructuringProposal = nil }
            ) {
                HStack {
                    Button("Create JSON Document") {
                        createJSONDocument(from: proposal)
                    }
                    .accessibilityHint("Creates a new JSON tab and leaves the source document unchanged.")
                    Spacer()
                    Button("Replace Current Document", role: .destructive) {
                        replaceCurrentDocumentWithJSON(from: proposal)
                    }
                    .accessibilityHint("Replaces the source after review.")
                }
            }
        }
    }
}
