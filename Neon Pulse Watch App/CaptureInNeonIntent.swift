import AppIntents
import WidgetKit

struct CaptureInNeonIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture in Neon"
    static let description = IntentDescription("Adds a note, TODO, or bug idea to Neon Inbox.")
    @available(watchOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Text", requestValueDialog: "What should Neon capture?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) in Neon")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await NeonPulseStore().addCapture(text: text) != nil else {
            return .result(dialog: "Nothing was captured.")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "NeonPulseStatus")
        return .result(dialog: "Captured in Neon Inbox.")
    }
}
