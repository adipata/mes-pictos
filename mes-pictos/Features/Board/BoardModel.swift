import SwiftUI
import UIKit
import PictoCore

/// What the board is showing and which sheet is open.
@MainActor
@Observable
final class BoardModel {
    var isParentMode = false
    var selectedPageID: UUID?

    /// The card shown in the centre of the screen (show mode).
    var shown: Placement?
    /// Brief highlight when show mode is off, or when a word joins the sentence.
    var highlightedID: UUID?
    /// The sentence being composed on the sentence bar.
    let sentence = SentenceModel()

    var editor: EditorRequest?
    var pageSettings: Page?
    var pageToDelete: Page?
    var showSettings = false
    var alertMessage: String?

    @ObservationIgnored private var debouncer = TapDebouncer()

    /// A card or a sentence is in the centre of the screen.
    var isOverlayPresented: Bool { shown != nil || sentence.isShown }

    private var defaults: UserDefaults { .standard }
    private var showModeEnabled: Bool { defaults.bool(forKey: SettingsKey.showModeEnabled, default: SettingsDefault.showModeEnabled) }
    private var sentenceBarEnabled: Bool { defaults.bool(forKey: SettingsKey.sentenceBarEnabled, default: SettingsDefault.sentenceBarEnabled) }
    private var clearAfterReading: Bool { defaults.bool(forKey: SettingsKey.sentenceClearAfterReading, default: SettingsDefault.sentenceClearAfterReading) }

    // MARK: Taps

    /// The child tapped a card.
    func select(_ placement: Placement, reduceMotion: Bool) {
        let interval = defaults.double(forKey: SettingsKey.tapInterval, default: SettingsDefault.tapInterval)
        guard debouncer.shouldAccept(at: Date(), minimumInterval: interval) else { return }
        guard let pictogram = placement.pictogram else { return }

        if sentenceBarEnabled {
            sentence.builder.maxWords = defaults.integer(forKey: SettingsKey.sentenceMaxWords, default: SettingsDefault.sentenceMaxWords)

            // An action ("Je veux", "Ouvre", "J'ai besoin d'aide") always begins a new sentence.
            if pictogram.isSentenceStarter {
                SpeechService.shared.speak(pictogram)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(Self.showAnimation(reduceMotion: reduceMotion)) {
                    _ = sentence.builder.tapStarter(placement)
                    sentence.readingIndex = nil
                }
                flashHighlight(placement.id)
                return
            }

            // A word from a page joins the sentence in progress. Cards of the permanent bar never do.
            if sentence.isComposing, placement.page?.kind == .normal {
                var effect = SentenceBuilder<Placement>.Effect.ignored
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    effect = sentence.builder.tapWord(placement)
                }
                switch effect {
                case .appended, .repeated:
                    SpeechService.shared.speak(pictogram)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    flashHighlight(placement.id)
                case .full:
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                case .started, .ignored:
                    break
                }
                return
            }
        }

        // Direct choice: the card is spoken and shown.
        SpeechService.shared.speak(pictogram)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if showModeEnabled {
            withAnimation(Self.showAnimation(reduceMotion: reduceMotion)) {
                shown = placement
            }
        } else {
            flashHighlight(placement.id)
        }
    }

    private func flashHighlight(_ id: UUID) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            highlightedID = id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.2)) {
                if highlightedID == id { highlightedID = nil }
            }
        }
    }

    func closeShown(reduceMotion: Bool) {
        guard shown != nil else { return }
        withAnimation(Self.showAnimation(reduceMotion: reduceMotion)) {
            shown = nil
        }
    }

    // MARK: Sentence

    /// The child pressed "Dire": the sentence is shown in the centre (show mode) and read.
    func speakSentence(reduceMotion: Bool) {
        guard sentence.canSpeak else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if showModeEnabled {
            withAnimation(Self.showAnimation(reduceMotion: reduceMotion)) {
                sentence.isShown = true
            }
            // The overlay starts the reading once it is on screen.
        } else {
            readSentence(thenClear: true)
        }
    }

    /// Reads the sentence, highlighting each card as it is spoken.
    func readSentence(thenClear: Bool = false) {
        guard sentence.canSpeak else { return }
        sentence.isReading = true
        SpeechService.shared.speakSequence(sentence.contents) { [weak self] index in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                self?.sentence.readingIndex = index
            }
        } onEnd: { [weak self] completed in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.sentence.readingIndex = nil
                self.sentence.isReading = false
            }
            if thenClear, completed, self.clearAfterReading {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !self.sentence.isReading, !self.sentence.isShown else { return }
                    self.clearSentence(reduceMotion: false)
                }
            }
        }
    }

    /// The adult closed the shown sentence.
    func closeSentenceShown(reduceMotion: Bool) {
        guard sentence.isShown else { return }
        SpeechService.shared.stop()
        withAnimation(Self.showAnimation(reduceMotion: reduceMotion)) {
            sentence.isShown = false
            if clearAfterReading {
                sentence.builder.clear()
            }
        }
    }

    /// The child tapped a card on the sentence bar: it is taken off the strip.
    func removeFromSentence(at index: Int, reduceMotion: Bool) {
        guard !sentence.isShown, !sentence.isReading else { return }
        SpeechService.shared.stop()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(index == 0 ? Self.showAnimation(reduceMotion: reduceMotion) : .spring(response: 0.3, dampingFraction: 0.8)) {
            sentence.readingIndex = nil
            _ = sentence.builder.remove(at: index)
        }
    }

    func clearSentence(reduceMotion: Bool) {
        guard sentence.isComposing || sentence.isShown else { return }
        SpeechService.shared.stop()
        withAnimation(Self.showAnimation(reduceMotion: reduceMotion)) {
            sentence.isShown = false
            sentence.readingIndex = nil
            sentence.builder.clear()
        }
    }

    static func showAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.82)
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let page: Page
    let slot: Int
    /// nil when creating a new pictogram.
    let placement: Placement?
}

extension View {
    /// The flying-card effect between the grid (or the sentence bar) and the centre of the screen.
    @ViewBuilder
    func heroEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
