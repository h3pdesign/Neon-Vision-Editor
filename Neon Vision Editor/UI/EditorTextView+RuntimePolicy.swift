import SwiftUI
import Foundation
import OSLog

nonisolated let syntaxHighlightSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "SyntaxHighlight")

#if os(macOS)
extension Notification.Name {
    static let editorPointerInteraction = Notification.Name("NeonEditorPointerInteraction")
}

enum MacEditorContentInstallRefreshPolicy {
    // A full TextKit pass repairs stale glyph maps after a document swap, but it is
    // disproportionately expensive for larger documents. Those use visible-range refreshes.
    static let fullLayoutMaxUTF16Length = 120_000

    static func shouldInvalidateFullRange(textLength: Int) -> Bool {
        textLength <= fullLayoutMaxUTF16Length
    }
}
#endif

enum EditorRuntimeLimits {
    // Above this, keep editing responsive by skipping regex-heavy syntax passes.
    static let syntaxMinimalUTF16Length = 1_200_000
    // HTML uses a bounded visible-range scanner, so it can keep structural
    // highlighting responsive well beyond the generic minimal-syntax cutoff.
    static let htmlResponsiveSyntaxUTF16Length = 8_000_000
    static let structuredResponsiveSyntaxUTF16Length = 4_000_000
    static let htmlFastProfileUTF16Length = 250_000
    static let csvFastProfileUTF16Length = 120_000
    static let jsonFastProfileUTF16Length = 120_000
    static let largeFileJSONVisiblePaddingUTF16 = 2_400
    static let largeFileJSONIncrementalPaddingUTF16 = 800
    nonisolated static let largeFileJSONTokenBudgetSeconds = 0.0035
    nonisolated static let largeFileCSVTokenBudgetSeconds = 0.0035
    static let csvFastProfileLongLineUTF16 = 4_000
    static let csvFastProfileScanLimitUTF16 = 120_000
    nonisolated static let generatedFileAutoDetectionUTF16Threshold = 100_000
    nonisolated static let generatedFileAutoDetectionScanUTF16 = 64_000
    nonisolated static let generatedFileMinifiedLineUTF16 = 1_200
    static let scopeComputationMaxUTF16Length = 300_000
    static let cursorRehighlightMaxUTF16Length = 220_000
    static let nonImmediateHighlightMaxUTF16Length = 220_000
    // Large programming files get a quick visible-range pass before the complete
    // document pass so the first screen is useful without sacrificing accuracy.
    static let initialProgrammingHighlightThresholdUTF16 = 120_000
    static let initialProgrammingHighlightPaddingUTF16 = 2_400
    // Keep ordinary programming documents responsive before they reach the
    // large-file policy. Only the visible region is recolored above this size.
    static let programmingViewportSyntaxUTF16Length = 400_000
    static let bindingDebounceUTF16Length = 250_000
    static let bindingDebounceDelay: TimeInterval = 0.18
    // Markdown syntax is stateful (fences, links, and headings can affect later
    // lines). Coalesce keystrokes before starting its full-document pass.
    static let markdownHighlightDebounce: TimeInterval = 0.28
    static let bracketScopeNearestFallbackWindowUTF16 = 8_000
}

nonisolated func isMarkdownSyntaxLanguage(_ language: String) -> Bool {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "markdown", "md", "mdown", "mkdn", "mdx": return true
    default: return false
    }
}

nonisolated func isProgrammingSyntaxLanguage(_ language: String) -> Bool {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "swift", "c", "cpp", "c++", "objective-c", "objective-c++", "objc", "java",
         "kotlin", "rust", "go", "python", "ruby", "php", "perl", "lua", "r",
         "javascript", "js", "typescript", "ts", "tsx", "jsx", "shell", "bash",
         "zsh", "fish", "powershell":
        return true
    default:
        return false
    }
}

func shouldUseCSVFastProfile(_ nsText: NSString) -> Bool {
    if nsText.length >= EditorRuntimeLimits.csvFastProfileUTF16Length {
        return true
    }
    let scanLimit = min(nsText.length, EditorRuntimeLimits.csvFastProfileScanLimitUTF16)
    guard scanLimit > 0 else { return false }
    var currentLineLength = 0
    for idx in 0..<scanLimit {
        let codeUnit = nsText.character(at: idx)
        if codeUnit == 10 {
            currentLineLength = 0
            continue
        }
        currentLineLength += 1
        if currentLineLength >= EditorRuntimeLimits.csvFastProfileLongLineUTF16 {
            return true
        }
    }
    return false
}

nonisolated func isJSONLikeLanguage(_ language: String) -> Bool {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "json", "jsonc", "json5", "ipynb":
        return true
    default:
        return false
    }
}

nonisolated func isCSVLikeSyntaxLanguage(_ language: String) -> Bool {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "csv", "tsv": return true
    default: return false
    }
}

func syntaxProfile(for language: String, text: NSString) -> SyntaxPatternProfile {
    let lower = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if isHTMLLikeSyntaxLanguage(lower) && text.length >= EditorRuntimeLimits.htmlFastProfileUTF16Length {
        return .htmlFast
    }
    if lower == "csv" && shouldUseCSVFastProfile(text) {
        return .csvFast
    }
    if isJSONLikeLanguage(lower) && text.length >= EditorRuntimeLimits.jsonFastProfileUTF16Length {
        return .jsonFast
    }
    return .full
}

enum SyntaxFontEmphasis: Sendable {
    case keyword
    case comment
    case markdownHeading
}

#if os(macOS)
func fontWithSymbolicTrait(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
    // Always derive emphasis from the base font's non-emphasis face. NSTextView can
    // report the selected character's font as its default font after a row click;
    // carrying that trait forward makes subsequent passes alternate emphasis.
    let emphasisTraits: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
    let traits = font.fontDescriptor.symbolicTraits.subtracting(emphasisTraits).union(trait)
    let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
    guard let adjustedFont = NSFont(descriptor: descriptor, size: font.pointSize) else {
        return font
    }
    return adjustedFont
}
#else
func fontWithSymbolicTrait(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
    let emphasisTraits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
    let traits = font.fontDescriptor.symbolicTraits.subtracting(emphasisTraits).union(trait)
    guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
        return font
    }
    return UIFont(descriptor: descriptor, size: font.pointSize)
}
#endif

func supportsResponsiveLargeFileHighlight(language: String) -> Bool {
    (isJSONLikeLanguage(language) || isHTMLLikeSyntaxLanguage(language) || isCSVLikeSyntaxLanguage(language)) &&
        currentLargeFileSyntaxHighlightMode() == .minimal &&
        currentLargeFileOpenMode() != .plainText
}

func supportsResponsiveLargeFileHighlight(language: String, textLength: Int) -> Bool {
    guard supportsResponsiveLargeFileHighlight(language: language) else { return false }
    if isHTMLLikeSyntaxLanguage(language) {
        return textLength <= EditorRuntimeLimits.htmlResponsiveSyntaxUTF16Length
    }
    return textLength <= EditorRuntimeLimits.structuredResponsiveSyntaxUTF16Length
}

func supportsViewportSyntaxHighlighting(language: String, textLength: Int) -> Bool {
    if supportsResponsiveLargeFileHighlight(language: language, textLength: textLength) {
        return true
    }
    return textLength >= EditorRuntimeLimits.programmingViewportSyntaxUTF16Length &&
        isProgrammingSyntaxLanguage(language) &&
        currentLargeFileOpenMode() != .plainText
}

enum LargeFileSyntaxHighlightMode: String {
    case off
    case minimal
}

enum LargeFileOpenMode: String {
    case standard
    case deferred
    case plainText
}

enum GeneratedFileSyntaxHighlightingMode: String {
    case automatic
    case full
    case off
}

func currentLargeFileSyntaxHighlightMode() -> LargeFileSyntaxHighlightMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsLargeFileSyntaxHighlighting") ?? "minimal"
    return LargeFileSyntaxHighlightMode(rawValue: raw) ?? .minimal
}

func currentLargeFileOpenMode() -> LargeFileOpenMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsLargeFileOpenMode") ?? "deferred"
    return LargeFileOpenMode(rawValue: raw) ?? .deferred
}

func currentGeneratedFileSyntaxHighlightingMode() -> GeneratedFileSyntaxHighlightingMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsGeneratedFileSyntaxHighlighting") ?? "automatic"
    return GeneratedFileSyntaxHighlightingMode(rawValue: raw) ?? .automatic
}

/// Bounded prefix scan that keeps generated bundles out of expensive regex passes.
nonisolated func isLikelyGeneratedOrMinifiedSyntaxText(_ text: NSString) -> Bool {
    guard text.length >= EditorRuntimeLimits.generatedFileAutoDetectionUTF16Threshold else { return false }
    let scanLength = min(text.length, EditorRuntimeLimits.generatedFileAutoDetectionScanUTF16)
    let prefix = text.substring(with: NSRange(location: 0, length: scanLength)).lowercased()
    if prefix.contains("do not edit") || prefix.contains("@generated") || prefix.contains("sourcemappingurl=") {
        return true
    }

    var lineLength = 0
    var longestLine = 0
    var lineCount = 1
    for index in 0..<scanLength {
        if text.character(at: index) == 10 {
            longestLine = max(longestLine, lineLength)
            lineLength = 0
            lineCount += 1
        } else {
            lineLength += 1
        }
    }
    longestLine = max(longestLine, lineLength)
    return longestLine >= EditorRuntimeLimits.generatedFileMinifiedLineUTF16 && lineCount <= 8
}

func shouldSuppressGeneratedFileSyntaxHighlighting(text: NSString, language: String) -> Bool {
    guard isProgrammingSyntaxLanguage(language) || isJSONLikeLanguage(language) || isHTMLLikeSyntaxLanguage(language) else {
        return false
    }
    switch currentGeneratedFileSyntaxHighlightingMode() {
    case .full:
        return false
    case .off:
        return isLikelyGeneratedOrMinifiedSyntaxText(text)
    case .automatic:
        guard isLikelyGeneratedOrMinifiedSyntaxText(text) else { return false }
        return !supportsResponsiveLargeFileHighlight(language: language, textLength: text.length)
    }
}

func shouldUseChunkedLargeFileInstall(isLargeFileMode: Bool, textLength: Int) -> Bool {
    guard isLargeFileMode else { return false }
    guard currentLargeFileOpenMode() != .standard else { return false }
    return textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length
}

func editorCaretLineColumn(in text: NSString, location rawLocation: Int) -> (line: Int, column: Int) {
    let location = min(max(0, rawLocation), text.length)
    var line = 1
    var lineStart = 0
    if location > 0 {
        for index in 0..<location where text.character(at: index) == 10 {
            line += 1
            lineStart = index + 1
        }
    }
    return (line, location - lineStart + 1)
}

nonisolated func isJSONWhitespace(_ codeUnit: unichar) -> Bool {
    codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13
}

nonisolated func isJSONDigit(_ codeUnit: unichar) -> Bool {
    codeUnit >= 48 && codeUnit <= 57
}

nonisolated func isJSONLetter(_ codeUnit: unichar) -> Bool {
    (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122)
}

nonisolated func isJSONLiteral(_ text: NSString, range: NSRange, literal: [unichar]) -> Bool {
    guard range.length == literal.count else { return false }
    for offset in 0..<literal.count where text.character(at: range.location + offset) != literal[offset] {
        return false
    }
    return true
}
