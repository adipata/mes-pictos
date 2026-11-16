import SwiftUI
import PictoCore

/// The sentence bar (*bande phrase*): a starter card ("Je veux") and the words the child adds.
/// State only, never stored: it lives in `BoardModel` for the time of a sentence.
@MainActor
@Observable
final class SentenceModel {
    var builder = SentenceBuilder<Placement>(maxWords: SettingsDefault.sentenceMaxWords)
    /// The sentence is in the centre of the screen (show mode).
    var isShown = false
    var isReading = false
    /// Index in `items` of the card being spoken.
    var readingIndex: Int?

    /// The cards of the sentence, starter first. Cards whose pictogram disappeared (sync) are skipped.
    var items: [Placement] { builder.all.filter { $0.pictogram != nil } }
    var isComposing: Bool { builder.isComposing }
    var canSpeak: Bool { builder.canSpeak && !items.isEmpty }
    var isEmpty: Bool { !isComposing }

    var contents: [SpeechContent] {
        items.compactMap(\.pictogram).map {
            SpeechResolver.resolve(label: $0.label, spokenText: $0.spokenText, recording: $0.recordingData)
        }
    }

    /// The sentence as text, for VoiceOver and logs.
    var spokenText: String {
        SentenceText.join(items.compactMap(\.pictogram).map { $0.spokenText ?? $0.label }).text
    }
}

/// Hero ids of the sentence cards, distinct from the grid placements (a card can be in both).
struct SentenceSlot: Hashable {
    let index: Int
}
