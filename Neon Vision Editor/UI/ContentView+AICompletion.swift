import SwiftUI
import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

// MARK: - AI Completion Actions

extension ContentView {
    // MARK: - Provider Token Prompts

    var selectedModel: AIModel {
        get { AIModel(rawValue: selectedModelRaw) ?? .appleIntelligence }
        set { selectedModelRaw = newValue.rawValue }
    }

    func promptForGrokTokenIfNeeded() -> Bool {
        if !grokAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Grok API Token Required"
        alert.informativeText = "Enter your Grok API token to enable suggestions. You can obtain this from your Grok account."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            grokAPIToken = token
            SecureTokenStore.setToken(token, for: .grok)
            return true
        }
#endif
        return false
    }

    func promptForOpenAITokenIfNeeded() -> Bool {
        if !openAIAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "OpenAI API Token Required"
        alert.informativeText = "Enter your OpenAI API token to enable suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            openAIAPIToken = token
            SecureTokenStore.setToken(token, for: .openAI)
            return true
        }
#endif
        return false
    }

    func promptForGeminiTokenIfNeeded() -> Bool {
        if !geminiAPIToken.isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Gemini API Key Required"
        alert.informativeText = "Enter your Gemini API key to enable suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "AIza..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            geminiAPIToken = token
            SecureTokenStore.setToken(token, for: .gemini)
            return true
        }
#endif
        return false
    }

    func promptForAnthropicTokenIfNeeded() -> Bool {
        if !anthropicAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Anthropic API Token Required"
        alert.informativeText = "Enter your Anthropic API token to enable suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-ant-..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            anthropicAPIToken = token
            SecureTokenStore.setToken(token, for: .anthropic)
            return true
        }
#endif
        return false
    }

    #if os(macOS)
    // MARK: - Inline Completion Flow

    @MainActor
    func performInlineCompletion(for textView: NSTextView) {
        completionTask?.cancel()
        completionTask = Task(priority: .utility) {
            await performInlineCompletionAsync(for: textView)
        }
    }

    @MainActor
    func performInlineCompletionAsync(for textView: NSTextView) async {
        let completionInterval = Self.completionSignposter.beginInterval("inline_completion")
        defer { Self.completionSignposter.endInterval("inline_completion", completionInterval) }

        let sel = textView.selectedRange()
        guard sel.length == 0 else { return }
        let loc = sel.location
        guard loc > 0, loc <= (textView.string as NSString).length else { return }
        let nsText = textView.string as NSString
        if Task.isCancelled { return }
        if shouldThrottleHeavyEditorFeatures(in: nsText) { return }

        let prevChar = nsText.substring(with: NSRange(location: loc - 1, length: 1))
        var nextChar: String? = nil
        if loc < nsText.length {
            nextChar = nsText.substring(with: NSRange(location: loc, length: 1))
        }

        // Auto-close braces/brackets/parens if not already closed
        let pairs: [String: String] = ["{": "}", "(": ")", "[": "]"]
        if let closing = pairs[prevChar] {
            if nextChar != closing {
                // Insert closing and move caret back between pair
                let insertion = closing
                textView.insertText(insertion, replacementRange: sel)
                textView.setSelectedRange(NSRange(location: loc, length: 0))
                return
            }
        }

        // If previous char is '{' and language is swift, javascript, c, or cpp, insert code block scaffold
        if prevChar == "{" && ["swift", "javascript", "c", "cpp"].contains(currentLanguage) {
            // Get current line indentation
            let fullText = textView.string as NSString
            let lineRange = fullText.lineRange(for: NSRange(location: loc - 1, length: 0))
            let lineText = fullText.substring(with: lineRange)
            let indentPrefix = lineText.prefix(while: { $0 == " " || $0 == "\t" })

            let indentString = String(indentPrefix)
            let indentLevel = indentString.count
            let indentSpaces = "    " // 4 spaces

            // Build scaffold string
            let scaffold = "\n\(indentString)\(indentSpaces)\n\(indentString)}"

            // Insert scaffold at caret position
            textView.insertText(scaffold, replacementRange: NSRange(location: loc, length: 0))

            // Move caret to indented empty line
            let newCaretLocation = loc + 1 + indentLevel + indentSpaces.count
            textView.setSelectedRange(NSRange(location: newCaretLocation, length: 0))
            return
        }

        // Prefer cheap local matches before model-backed completion.
        let doc = textView.string
        let nsDoc = doc as NSString
        if let localSuggestion = CompletionHeuristics.localSuggestion(
            in: nsDoc,
            caretLocation: loc,
            language: currentLanguage,
            includeDocumentWords: completionFromDocument,
            includeSyntaxKeywords: completionFromSyntax
        ) {
            applyInlineSuggestion(localSuggestion, textView: textView, selection: sel)
            return
        }

        // Limit completion context by both recent lines and UTF-16 length for lower latency.
        let tokenContext = CompletionHeuristics.tokenContext(in: nsDoc, caretLocation: loc)
        let contextPrefix = completionContextPrefix(in: nsDoc, caretLocation: loc)
        let cacheKey = completionCacheKey(prefix: contextPrefix, language: currentLanguage, caretLocation: loc)

        if let cached = cachedCompletion(for: cacheKey) {
            Self.completionSignposter.emitEvent("completion_cache_hit")
            applyInlineSuggestion(cached, textView: textView, selection: sel)
            return
        }

        let modelInterval = Self.completionSignposter.beginInterval("model_completion")
        let suggestion = await generateModelCompletion(prefix: contextPrefix, language: currentLanguage)
        Self.completionSignposter.endInterval("model_completion", modelInterval)
        if Task.isCancelled { return }
        let sanitizedSuggestion = CompletionHeuristics.sanitizeModelSuggestion(
            suggestion,
            currentTokenPrefix: tokenContext.prefix,
            nextDocumentText: tokenContext.nextDocumentText
        )
        storeCompletionInCache(sanitizedSuggestion, for: cacheKey)
        applyInlineSuggestion(sanitizedSuggestion, textView: textView, selection: sel)
    }

    // MARK: - Completion Context and Cache

    func completionContextPrefix(in nsDoc: NSString, caretLocation: Int, maxUTF16: Int = 3000, maxLines: Int = 120) -> String {
        let startByChars = max(0, caretLocation - maxUTF16)

        var cursor = caretLocation
        var seenLines = 0
        while cursor > 0 && seenLines < maxLines {
            let searchRange = NSRange(location: 0, length: cursor)
            let found = nsDoc.range(of: "\n", options: .backwards, range: searchRange)
            if found.location == NSNotFound {
                cursor = 0
                break
            }
            cursor = found.location
            seenLines += 1
        }
        let startByLines = cursor
        let start = max(startByChars, startByLines)
        return nsDoc.substring(with: NSRange(location: start, length: caretLocation - start))
    }

    func completionCacheKey(prefix: String, language: String, caretLocation: Int) -> String {
        let normalizedPrefix = String(prefix.suffix(320))
        var hasher = Hasher()
        hasher.combine(language)
        hasher.combine(caretLocation / 32)
        hasher.combine(normalizedPrefix)
        return "\(language):\(caretLocation / 32):\(hasher.finalize())"
    }

    func cachedCompletion(for key: String) -> String? {
        pruneCompletionCacheIfNeeded()
        guard let entry = completionCache[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > 20 {
            completionCache.removeValue(forKey: key)
            return nil
        }
        return entry.suggestion
    }

    func storeCompletionInCache(_ suggestion: String, for key: String) {
        completionCache[key] = CompletionCacheEntry(suggestion: suggestion, createdAt: Date())
        pruneCompletionCacheIfNeeded()
    }

    func pruneCompletionCacheIfNeeded() {
        if completionCache.count <= 220 { return }
        let cutoff = Date().addingTimeInterval(-20)
        completionCache = completionCache.filter { $0.value.createdAt >= cutoff }
        if completionCache.count <= 200 { return }
        let sorted = completionCache.sorted { $0.value.createdAt > $1.value.createdAt }
        completionCache = Dictionary(uniqueKeysWithValues: sorted.prefix(200).map { ($0.key, $0.value) })
    }

    func applyInlineSuggestion(_ suggestion: String, textView: NSTextView, selection: NSRange) {
        guard let accepting = textView as? AcceptingTextView else { return }
        let currentText = textView.string as NSString
        let currentSelection = textView.selectedRange()
        guard currentSelection.length == 0, currentSelection.location == selection.location else { return }
        let nextRangeLength = min(suggestion.count, currentText.length - selection.location)
        let nextText = nextRangeLength > 0 ? currentText.substring(with: NSRange(location: selection.location, length: nextRangeLength)) : ""
        if suggestion.isEmpty || nextText.starts(with: suggestion) {
            accepting.clearInlineSuggestion()
            return
        }
        accepting.showInlineSuggestion(suggestion, at: selection.location)
    }

    // MARK: - Completion Scheduling

    func shouldThrottleHeavyEditorFeatures(in nsText: NSString? = nil) -> Bool {
        if effectiveLargeFileModeEnabled { return true }
        let length = nsText?.length ?? currentDocumentUTF16Length
        return length >= EditorPerformanceThresholds.heavyFeatureUTF16Length
    }

    func shouldScheduleCompletion(for textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let location = selection.location
        guard location > 0, location <= nsText.length else { return false }
        if shouldThrottleHeavyEditorFeatures(in: nsText) { return false }

        let prevChar = nsText.substring(with: NSRange(location: location - 1, length: 1))
        let triggerChars: Set<String> = [".", "(", ")", "{", "}", "[", "]", ":", ",", "\n", "\t"]
        if triggerChars.contains(prevChar) { return true }
        if prevChar == " " {
            return CompletionHeuristics.shouldTriggerAfterWhitespace(
                in: nsText,
                caretLocation: location,
                language: currentLanguage
            )
        }

        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if prevChar.rangeOfCharacter(from: wordChars) == nil { return false }

        if location >= nsText.length { return true }
        let nextChar = nsText.substring(with: NSRange(location: location, length: 1))
        let separator = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return nextChar.rangeOfCharacter(from: separator) != nil
    }

    func completionDebounceInterval(for textView: NSTextView) -> TimeInterval {
        let docLength = (textView.string as NSString).length
        if docLength >= 80_000 { return 0.9 }
        if docLength >= 25_000 { return 0.7 }
        return 0.45
    }

    func completionTriggerSignature(for textView: NSTextView) -> String {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return "" }
        let location = selection.location
        guard location > 0, location <= nsText.length else { return "" }

        let prevChar = nsText.substring(with: NSRange(location: location - 1, length: 1))
        let nextChar: String
        if location < nsText.length {
            nextChar = nsText.substring(with: NSRange(location: location, length: 1))
        } else {
            nextChar = ""
        }
        // Keep signature cheap while specific enough to skip duplicate notifications.
        return "\(location)|\(prevChar)|\(nextChar)|\(nsText.length)"
    }
    #endif

    // MARK: - Provider Requests

    func appleModelCompletion(prefix: String, language: String) async -> String {
        let client = AppleIntelligenceAIClient()
        var aggregated = ""
        for await chunk in client.streamSuggestions(prompt: "Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.\n\n\(prefix)\n\nCompletion:") {
            aggregated += chunk
            // Keep completion latency low while still capturing more than a single token/chunk.
            if aggregated.count >= 96 { break }
        }
        let candidate = sanitizeCompletion(aggregated)
        await MainActor.run { lastProviderUsed = "Apple" }
        return candidate
    }

    func generateModelCompletion(prefix: String, language: String) async -> String {
        switch selectedModel {
        case .appleIntelligence:
            return await appleModelCompletion(prefix: prefix, language: language)
        case .grok:
            if grokAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                return res
            }
            do {
                guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(grokAPIToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "grok-2-latest",
                    "messages": [["role": "user", "content": prompt]],
                    "temperature": 0.5,
                    "max_tokens": 64,
                    "n": 1,
                    "stop": [""]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    await MainActor.run { lastProviderUsed = "Grok" }
                    return sanitizeCompletion(content)
                }
                // If no content, fallback to Apple
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][Grok] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                return res
            }
        case .openAI:
            if openAIAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                return res
            }
            do {
                guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(openAIAPIToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": [["role": "user", "content": prompt]],
                    "temperature": 0.5,
                    "max_tokens": 64,
                    "n": 1,
                    "stop": [""]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    await MainActor.run { lastProviderUsed = "OpenAI" }
                    return sanitizeCompletion(content)
                }
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][OpenAI] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                return res
            }
        case .gemini:
            if geminiAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                return res
            }
            do {
                let model = "gemini-1.5-flash-latest"
                let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
                guard let url = URL(string: endpoint) else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(geminiAPIToken, forHTTPHeaderField: "x-goog-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "contents": [["parts": [["text": prompt]]]],
                    "generationConfig": ["temperature": 0.5, "maxOutputTokens": 64]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    await MainActor.run { lastProviderUsed = "Gemini" }
                    return sanitizeCompletion(text)
                }
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][Gemini] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                return res
            }
        case .anthropic:
            if anthropicAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                return res
            }
            do {
                guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(anthropicAPIToken, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "claude-3-5-haiku-latest",
                    "max_tokens": 64,
                    "temperature": 0.5,
                    "messages": [["role": "user", "content": prompt]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let contentArr = json["content"] as? [[String: Any]],
                   let first = contentArr.first,
                   let text = first["text"] as? String {
                    await MainActor.run { lastProviderUsed = "Anthropic" }
                    return sanitizeCompletion(text)
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? [String: Any],
                   let contentArr = message["content"] as? [[String: Any]],
                   let first = contentArr.first,
                   let text = first["text"] as? String {
                    await MainActor.run { lastProviderUsed = "Anthropic" }
                    return sanitizeCompletion(text)
                }
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][Anthropic] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                return res
            }
        }
    }

    // MARK: - Completion Sanitizing and Logging

    func sanitizeCompletion(_ raw: String) -> String {
        CompletionHeuristics.sanitizeModelSuggestion(raw, currentTokenPrefix: "", nextDocumentText: "")
    }

    func debugLog(_ message: String) {
        if message.contains("[Completion]") || message.contains("AI ") || message.contains("[AI]") {
            AIActivityLog.record(message, source: "Completion")
        }
#if DEBUG
        print(message)
#endif
    }
}
