import Foundation
import SwiftUI

struct AIChatReplacementPreview: Identifiable {
    let id = UUID()
    let tabID: UUID
    let range: NSRange
    let source: String
    let replacement: String

    var sourceCharacterCount: Int { source.count }
    var replacementCharacterCount: Int { replacement.count }
}

extension ContentView {
    var utilitySidebarMode: UtilitySidebarMode {
        get { UtilitySidebarMode(rawValue: utilitySidebarModeRaw) ?? .project }
        nonmutating set { utilitySidebarModeRaw = newValue.rawValue }
    }

    var aiChatSidebarBody: some View {
        AIChatSidebarView(
            conversation: aiChatConversation,
            providerName: selectedModel.displayName,
            documentName: viewModel.selectedTab?.name,
            documentLanguage: currentLanguage,
            selectionCharacterCount: aiChatSelection?.count ?? 0,
            currentFileCharacterCount: viewModel.selectedTab?.document.utf16Length ?? currentContent.count,
            projectStructureCharacterCount: aiChatProjectStructure?.count ?? 0,
            containsPotentialSensitiveContent: AIChatSensitiveContentDetector.containsPotentialSecret(aiChatSelection ?? ""),
            isOnDeviceProvider: selectedModel == .appleIntelligence,
            hasSelection: aiChatSelection != nil,
            hasCurrentFile: viewModel.selectedTab != nil || !singleContent.isEmpty,
            hasProjectStructure: aiChatProjectStructure != nil,
            onSend: { prompt, scopes in
                sendAIChat(prompt: prompt, scopes: scopes)
            },
            onInsert: { response in
                insertAIChatResponse(response)
            },
            onReplaceSelection: { response in
                requestAIChatSelectionReplacement(with: response)
            },
            onReviewReplacement: { response in
                reviewAIChatReplacement(response)
            },
            onOpenSettings: openAPISettings
        )
    }

    func showAIChat() {
        utilitySidebarMode = .assistant
#if os(iOS) || os(visionOS)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        if isPhone || horizontalSizeClass == .compact || horizontalSizeClass == nil {
            showCompactProjectSidebarSheet = true
            return
        }
#endif
        showProjectStructureSidebar = true
    }

    private var aiChatSelection: String? {
        guard let tab = viewModel.selectedTab,
              currentSelectionSnapshotTabID == tab.id else { return nil }
        let selection = currentSelectionSnapshotText.trimmingCharacters(in: .whitespacesAndNewlines)
        return selection.isEmpty ? nil : selection
    }

    private func sendAIChat(prompt: String, scopes: Set<AIChatContextScope>) {
        if scopes.contains(.currentFile), viewModel.selectedTab?.usesFileBackedStorage == true {
            aiChatConversation.reportError("Current-file AI context is unavailable for large virtual documents until a bounded context reader is available.")
            return
        }
        guard let client = configuredAIChatClient() else {
            aiChatConversation.reportError(aiChatConfigurationError)
            return
        }

        let context = AIChatContext(
            selection: scopes.contains(.selection) ? aiChatSelection : nil,
            documentName: scopes.contains(.selection) || scopes.contains(.currentFile)
                ? (viewModel.selectedTab?.name ?? "Untitled")
                : nil,
            documentLanguage: scopes.contains(.selection) || scopes.contains(.currentFile) ? currentLanguage : nil,
            documentText: scopes.contains(.currentFile) && viewModel.selectedTab?.usesFileBackedStorage != true
                ? currentContent
                : nil,
            projectStructure: scopes.contains(.projectStructure) ? aiChatProjectStructure : nil
        )
        aiChatConversation.start(
            prompt: prompt,
            context: context,
            providerName: selectedModel.displayName,
            client: client
        )
    }

    private var aiChatConfigurationError: String {
        switch selectedModel {
        case .appleIntelligence:
            return AppleFM.availabilityMessage ?? "Apple Intelligence is unavailable in this build or on this device."
        case .customProvider:
            return "Configure a secure custom provider URL and model in AI Settings before starting a chat."
        default:
            return "Add a \(selectedModel.displayName) API key in AI Settings before starting a chat."
        }
    }

    private var aiChatProjectStructure: String? {
        guard !projectTreeNodes.isEmpty,
              let projectRootFolderURL else { return nil }
        let rootPath = projectRootFolderURL.standardizedFileURL.path
        var lines: [String] = []

        func append(_ nodes: [ProjectTreeNode], depth: Int) {
            for node in nodes {
                guard lines.count < 300 else { return }
                let path = node.url.standardizedFileURL.path
                let relativePath: String
                if path == rootPath {
                    relativePath = node.url.lastPathComponent
                } else if path.hasPrefix(rootPath + "/") {
                    relativePath = String(path.dropFirst(rootPath.count + 1))
                } else {
                    relativePath = node.url.lastPathComponent
                }
                lines.append(String(repeating: "  ", count: depth) + relativePath + (node.isDirectory ? "/" : ""))
                if node.isDirectory {
                    append(node.children, depth: depth + 1)
                }
            }
        }

        append(projectTreeNodes, depth: 0)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private func configuredAIChatClient() -> AIClient? {
        switch selectedModel {
        case .appleIntelligence:
            return appleModelAvailable ? AppleIntelligenceAIClient() : nil
        case .grok:
            let key = resolvedAIChatToken(grokAPIToken, key: .grok)
            return key.isEmpty ? nil : GrokAIClientStreaming(apiKey: key)
        case .openAI:
            let key = resolvedAIChatToken(openAIAPIToken, key: .openAI)
            return key.isEmpty ? nil : OpenAIAIClient(apiKey: key)
        case .gemini:
            let key = resolvedAIChatToken(geminiAPIToken, key: .gemini)
            return key.isEmpty ? nil : GeminiAIClient(apiKey: key)
        case .anthropic:
            let key = resolvedAIChatToken(anthropicAPIToken, key: .anthropic)
            return key.isEmpty ? nil : AnthropicAIClient(apiKey: key)
        case .openCodeGo:
            let key = resolvedAIChatToken(openCodeGoAPIToken, key: .openCodeGo)
            guard !key.isEmpty else { return nil }
            let model = openCodeGoModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenAICompatibleAIClient(
                apiKey: key,
                baseURL: OpenCodeGoConfig.baseURL,
                model: model.isEmpty ? OpenCodeGoConfig.defaultModel : model
            )
        case .customProvider:
            let key = SecureTokenStore.token(for: .customProvider).trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = (UserDefaults.standard.string(forKey: CustomProviderConfig.baseURLDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (UserDefaults.standard.string(forKey: CustomProviderConfig.modelDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSecureOpenAICompatibleBaseURL(baseURL), !model.isEmpty else { return nil }
            return OpenAICompatibleAIClient(apiKey: key, baseURL: baseURL, model: model)
        }
    }

    private func resolvedAIChatToken(_ enteredToken: String, key: APITokenKey) -> String {
        let entered = enteredToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? SecureTokenStore.token(for: key).trimmingCharacters(in: .whitespacesAndNewlines) : entered
    }

    private func insertAIChatResponse(_ response: String) {
        let replacement = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }
        guard let tab = viewModel.selectedTab else {
            singleContent.insert(contentsOf: replacement, at: singleContent.index(singleContent.startIndex, offsetBy: min(lastCaretLocation, singleContent.count)))
            return
        }
        guard !tab.isReadOnlyPreview else {
            aiChatConversation.reportError("The current document is read-only.")
            return
        }
        let location = min(max(0, lastCaretLocation), tab.document.utf16Length)
        NotificationCenter.default.post(
            name: .replaceEditorRangeRequested,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: tab.id.uuidString,
                EditorCommandUserInfo.rangeLocation: location,
                EditorCommandUserInfo.rangeLength: 0,
                EditorCommandUserInfo.replacementText: replacement
            ]
        )
    }

    private func requestAIChatSelectionReplacement(with response: String) {
        guard let tab = viewModel.selectedTab,
              !tab.isReadOnlyPreview,
              currentSelectionSnapshotTabID == tab.id,
              let range = currentSelectionSnapshotRange,
              range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= tab.document.utf16Length,
              (try? tab.document.text(inUTF16Range: range)) == currentSelectionSnapshotText else {
            aiChatConversation.reportError("Select unchanged text in an editable document before replacing it.")
            return
        }
        pendingAIChatReplacement = AIChatReplacementPreview(
            tabID: tab.id,
            range: range,
            source: currentSelectionSnapshotText,
            replacement: response
        )
    }

    func applyAIChatReplacement(_ preview: AIChatReplacementPreview) {
        guard let tab = viewModel.selectedTab,
              tab.id == preview.tabID,
              !tab.isReadOnlyPreview,
              NSMaxRange(preview.range) <= tab.document.utf16Length,
              (try? tab.document.text(inUTF16Range: preview.range)) == preview.source else {
            aiChatConversation.reportError("The selected text changed. Review the AI proposal again before applying it.")
            return
        }
        NotificationCenter.default.post(
            name: .replaceEditorRangeRequested,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: tab.id.uuidString,
                EditorCommandUserInfo.rangeLocation: preview.range.location,
                EditorCommandUserInfo.rangeLength: preview.range.length,
                EditorCommandUserInfo.replacementText: preview.replacement
            ]
        )
    }

    private func reviewAIChatReplacement(_ response: String) {
        guard let tab = viewModel.selectedTab,
              currentSelectionSnapshotTabID == tab.id,
              let range = currentSelectionSnapshotRange,
              range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= tab.document.utf16Length else {
            aiChatConversation.reportError("Select text before reviewing a proposed replacement.")
            return
        }
        guard let source = try? tab.document.text(inUTF16Range: range) else {
            aiChatConversation.reportError("The selected text could not be read. Select it again and retry.")
            return
        }
        utilitySidebarMode = .project
        showProjectStructureSidebar = true
        Task { @MainActor in
            let diff = await Task.detached(priority: .userInitiated) {
                DocumentDiffBuilder.build(leftContent: source, rightContent: response)
            }.value
            sidebarCompareDiffPresentation = DocumentDiffPresentation(
                title: "Review AI Replacement",
                leftTitle: "Selected Text",
                rightTitle: "AI Proposal",
                diff: diff
            )
        }
    }
}
