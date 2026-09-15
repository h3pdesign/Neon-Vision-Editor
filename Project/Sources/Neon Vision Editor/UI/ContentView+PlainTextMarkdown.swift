import SwiftUI

extension ContentView {
    func convertTextToMarkdown() {
        guard !isConvertingTextToMarkdown else { return }
        guard let tab = viewModel.selectedTab else { return }
        let selectedRange: NSRange? = {
            guard currentSelectionSnapshotTabID == tab.id,
                  let range = currentSelectionSnapshotRange,
                  range.location != NSNotFound,
                  range.length > 0,
                  NSMaxRange(range) <= tab.document.utf16Length else {
                return nil
            }
            return range
        }()
        let source: String
        if let selectedRange {
            guard let selectedText = try? tab.document.text(inUTF16Range: selectedRange) else {
                markdownConversionErrorMessage = "The selected text could not be read. Select it again and retry."
                return
            }
            source = selectedText
        } else {
            source = tab.document.string()
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            markdownConversionErrorMessage = PlainTextMarkdownConversionError.emptyDocument.localizedDescription
            return
        }

        markdownConversionTask?.cancel()
        markdownConversionTimeoutTask?.cancel()
        let requestID = UUID()
        let configuredClient = configuredMarkdownConversionClient()
        markdownConversionRequestID = requestID
        markdownConversionTargetTabID = tab.id
        markdownConversionTargetRange = selectedRange
        markdownConversionProviderName = configuredClient == nil ? "Apple Intelligence" : selectedModel.displayName
        let timeoutSeconds = markdownConversionTimeoutSeconds(for: source)
        markdownConversionTimeoutSeconds = timeoutSeconds
        markdownConversionCompletedChunkCount = 0
        markdownConversionTotalChunkCount = 0
        isConvertingTextToMarkdown = true
        markdownConversionTask = Task { [source, requestID, configuredClient] in
            do {
                let proposal: PlainTextMarkdownProposal
                if let client = configuredClient {
                    proposal = try await PlainTextMarkdownConverter.convertWithConfiguredProvider(
                        source,
                        client: client,
                        onChunkCompleted: { completed, total in
                            guard markdownConversionRequestID == requestID else { return }
                            markdownConversionCompletedChunkCount = completed
                            markdownConversionTotalChunkCount = total
                        }
                    )
                } else {
                    proposal = try await PlainTextMarkdownConverter.convertWithAppleIntelligence(
                        source,
                        onChunkCompleted: { completed, total in
                            guard markdownConversionRequestID == requestID else { return }
                            markdownConversionCompletedChunkCount = completed
                            markdownConversionTotalChunkCount = total
                        }
                    )
                }
                try Task.checkCancellation()
                guard proposal.preservesSourceText else {
                    throw PlainTextMarkdownConversionError.invalidPlan
                }
                guard markdownConversionRequestID == requestID else { return }
                markdownConversionProposal = proposal
            } catch is CancellationError {
            } catch {
                guard markdownConversionRequestID == requestID else { return }
                markdownConversionErrorMessage = error.localizedDescription
            }
            finishMarkdownConversion(requestID: requestID)
        }
        markdownConversionTimeoutTask = Task { [requestID, timeoutSeconds] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            } catch {
                return
            }
            guard markdownConversionRequestID == requestID else { return }
            markdownConversionTask?.cancel()
            markdownConversionErrorMessage = PlainTextMarkdownConversionError.timedOut(seconds: timeoutSeconds).localizedDescription
            finishMarkdownConversion(requestID: requestID)
        }
    }

    func cancelTextToMarkdownConversion() {
        markdownConversionTask?.cancel()
        markdownConversionTimeoutTask?.cancel()
        guard let requestID = markdownConversionRequestID else { return }
        finishMarkdownConversion(requestID: requestID)
    }

    private func finishMarkdownConversion(requestID: UUID) {
        guard markdownConversionRequestID == requestID else { return }
        markdownConversionRequestID = nil
        markdownConversionTask = nil
        markdownConversionTimeoutTask?.cancel()
        markdownConversionTimeoutTask = nil
        markdownConversionProviderName = nil
        markdownConversionTimeoutSeconds = 60
        markdownConversionCompletedChunkCount = 0
        markdownConversionTotalChunkCount = 0
        isConvertingTextToMarkdown = false
    }

    private func markdownConversionTimeoutSeconds(for source: String) -> Int {
        let lineCount = source.components(separatedBy: "\n").count
        let chunkCount = max(1, (lineCount + 199) / 200)
        return min(300, 60 + max(0, chunkCount - 1) * 15)
    }

    var markdownConversionProgressBanner: some View {
        let progress = markdownConversionTotalChunkCount > 1
            ? " • \(markdownConversionCompletedChunkCount) of \(markdownConversionTotalChunkCount) sections complete"
            : ""
        return HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Converting text to Markdown with \(markdownConversionProviderName ?? "Apple Intelligence")… up to \(markdownConversionTimeoutSeconds) seconds\(progress)")
                .font(.callout)
            Button("Cancel") { cancelTextToMarkdownConversion() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Converting text to Markdown with \(markdownConversionProviderName ?? "Apple Intelligence")")
    }

    func configuredMarkdownConversionClient() -> AIClient? {
        switch selectedModel {
        case .appleIntelligence:
            return nil
        case .grok:
            let token = resolvedMarkdownConversionToken(grokAPIToken, key: .grok)
            return token.isEmpty ? nil : GrokAIClientStreaming(apiKey: token)
        case .openAI:
            let token = resolvedMarkdownConversionToken(openAIAPIToken, key: .openAI)
            return token.isEmpty ? nil : OpenAIAIClient(apiKey: token)
        case .gemini:
            let token = resolvedMarkdownConversionToken(geminiAPIToken, key: .gemini)
            return token.isEmpty ? nil : GeminiAIClient(apiKey: token)
        case .anthropic:
            let token = resolvedMarkdownConversionToken(anthropicAPIToken, key: .anthropic)
            return token.isEmpty ? nil : AnthropicAIClient(apiKey: token)
        case .openCodeGo:
            let token = resolvedMarkdownConversionToken(openCodeGoAPIToken, key: .openCodeGo)
            guard !token.isEmpty else { return nil }
            let model = openCodeGoModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenAICompatibleAIClient(
                apiKey: token,
                baseURL: OpenCodeGoConfig.baseURL,
                model: model.isEmpty ? OpenCodeGoConfig.defaultModel : model
            )
        case .customProvider:
            let token = SecureTokenStore.token(for: .customProvider).trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = (UserDefaults.standard.string(forKey: CustomProviderConfig.baseURLDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (UserDefaults.standard.string(forKey: CustomProviderConfig.modelDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, isSecureOpenAICompatibleBaseURL(baseURL), !model.isEmpty else { return nil }
            return OpenAICompatibleAIClient(apiKey: token, baseURL: baseURL, model: model)
        }
    }

    private func resolvedMarkdownConversionToken(_ enteredToken: String, key: APITokenKey) -> String {
        let entered = enteredToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? SecureTokenStore.token(for: key).trimmingCharacters(in: .whitespacesAndNewlines) : entered
    }

    func createMarkdownDocument(from proposal: PlainTextMarkdownProposal) {
        let sourceName = viewModel.selectedTab?.name ?? "Untitled"
        viewModel.addNewTab()
        guard let tab = viewModel.selectedTab else { return }
        let baseName = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        viewModel.renameTab(tabID: tab.id, newName: "\(baseName).md")
        viewModel.updateTabLanguage(tabID: tab.id, language: "markdown")
        viewModel.updateTabContent(tabID: tab.id, content: proposal.markdown)
        markdownConversionProposal = nil
    }

    func replaceCurrentDocument(with proposal: PlainTextMarkdownProposal) {
        guard let targetTabID = markdownConversionTargetTabID,
              viewModel.tabs.contains(where: { $0.id == targetTabID }) else {
            markdownConversionErrorMessage = "The source document is no longer open."
            markdownConversionProposal = nil
            return
        }
        if let targetRange = markdownConversionTargetRange {
            guard viewModel.selectedTabID == targetTabID else {
                markdownConversionErrorMessage = "Return to the source tab and convert the selection again."
                markdownConversionProposal = nil
                return
            }
            guard let targetTab = viewModel.tabs.first(where: { $0.id == targetTabID }),
                  targetRange.location != NSNotFound,
                  NSMaxRange(targetRange) <= targetTab.document.utf16Length,
                  (try? targetTab.document.text(inUTF16Range: targetRange)) == proposal.source else {
                markdownConversionErrorMessage = "The selected text changed while the proposal was open. Convert it again to avoid replacing newer edits."
                markdownConversionProposal = nil
                return
            }
            NotificationCenter.default.post(
                name: .replaceEditorRangeRequested,
                object: nil,
                userInfo: [
                    EditorCommandUserInfo.documentID: targetTabID.uuidString,
                    EditorCommandUserInfo.rangeLocation: targetRange.location,
                    EditorCommandUserInfo.rangeLength: targetRange.length,
                    EditorCommandUserInfo.replacementText: proposal.markdown
                ]
            )
        } else {
            viewModel.updateTabContent(tabID: targetTabID, content: proposal.markdown)
            viewModel.updateTabLanguage(tabID: targetTabID, language: "markdown")
        }
        markdownConversionProposal = nil
        markdownConversionTargetTabID = nil
        markdownConversionTargetRange = nil
    }

    var markdownConversionReviewSheet: some View {
        Group {
            if let proposal = markdownConversionProposal {
                DiffComparisonView(
                    title: "Review Markdown Conversion",
                    leftTitle: "Original Text",
                    rightTitle: "Markdown Preview",
                    diff: DocumentDiffBuilder.build(leftContent: proposal.source, rightContent: proposal.markdown),
                    onClose: { markdownConversionProposal = nil }
                ) {
                    HStack {
                        Button("Create Markdown Document") {
                            createMarkdownDocument(from: proposal)
                        }
                        .accessibilityHint("Creates a new Markdown tab and leaves the current document unchanged.")
                        Spacer()
                        Button("Replace Current Document", role: .destructive) {
                            replaceCurrentDocument(with: proposal)
                        }
                        .accessibilityHint(
                            markdownConversionTargetRange == nil
                                ? "Replaces the current document after this review."
                                : "Replaces only the selected text after this review."
                        )
                    }
                }
            }
        }
    }
}
