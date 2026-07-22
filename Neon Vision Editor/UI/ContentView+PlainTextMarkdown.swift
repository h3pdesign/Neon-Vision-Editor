import SwiftUI

extension ContentView {
    func convertTextToMarkdown() {
        guard !isConvertingTextToMarkdown else { return }
        let selection = currentSelectionSnapshotText
        let source = selection.isEmpty ? currentContentBinding.wrappedValue : selection
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            markdownConversionErrorMessage = PlainTextMarkdownConversionError.emptyDocument.localizedDescription
            return
        }

        markdownConversionTask?.cancel()
        markdownConversionTimeoutTask?.cancel()
        let requestID = UUID()
        let configuredClient = configuredMarkdownConversionClient()
        markdownConversionRequestID = requestID
        markdownConversionProviderName = configuredClient == nil ? "Apple Intelligence" : selectedModel.displayName
        isConvertingTextToMarkdown = true
        markdownConversionTask = Task { [source, requestID, configuredClient] in
            do {
                let proposal: PlainTextMarkdownProposal
                if let client = configuredClient {
                    proposal = try await PlainTextMarkdownConverter.convertWithConfiguredProvider(source, client: client)
                } else {
                    proposal = try await PlainTextMarkdownConverter.convertWithAppleIntelligence(source)
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
        markdownConversionTimeoutTask = Task { [requestID] in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                return
            }
            guard markdownConversionRequestID == requestID else { return }
            markdownConversionTask?.cancel()
            markdownConversionErrorMessage = PlainTextMarkdownConversionError.timedOut.localizedDescription
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
        isConvertingTextToMarkdown = false
    }

    private func configuredMarkdownConversionClient() -> AIClient? {
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
        currentContentBinding.wrappedValue = proposal.markdown
        if let tab = viewModel.selectedTab {
            viewModel.updateTabLanguage(tabID: tab.id, language: "markdown")
        } else {
            singleLanguage = "markdown"
        }
        markdownConversionProposal = nil
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
                        .accessibilityHint("Replaces the current document after this review.")
                    }
                }
            }
        }
    }
}
