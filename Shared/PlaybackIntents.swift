import AppIntents

// These intents are compiled into BOTH the app and the widget extension.
// AudioPlaybackIntent makes iOS run perform() inside the app process (and keep it alive
// for audio), so the code below only does real work when built into the app.

struct TogglePlayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        PlayerModel.shared.widgetTogglePlay()
        #endif
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Song"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        PlayerModel.shared.widgetNext()
        #endif
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Song"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        PlayerModel.shared.widgetPrevious()
        #endif
        return .result()
    }
}
