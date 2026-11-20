import SwiftUI
import PictoCore

/// Show mode for a sentence: the cards of the sentence bar in a row in the centre of the screen,
/// read aloud with the spoken card highlighted, so the child can show the whole message to an adult.
struct SentenceOverlay: View {
    let namespace: Namespace.ID
    let containerSize: CGSize

    @Environment(BoardModel.self) private var board
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.showDismissMode) private var dismissRaw = DismissMode.tapOutside.rawValue
    @AppStorage(SettingsKey.showAutoCloseSeconds) private var autoCloseSeconds = SettingsDefault.showAutoCloseSeconds
    @AppStorage(SettingsKey.showCelebration) private var celebration = SettingsDefault.showCelebration
    @State private var bump = 0
    @State private var autoCloseTask: Task<Void, Never>?
    /// How far the sentence follows the child's finger while it is swiped.
    @State private var swipeOffset: CGSize = .zero
    /// The sentence was swiped away and is flying off the screen.
    @State private var isFlyingAway = false

    private var dismissMode: DismissMode { DismissMode(rawValue: dismissRaw) ?? .tapOutside }
    /// Swiping the sentence closes it, like tapping outside. With the adult-only setting it does not.
    private var canSwipe: Bool { dismissMode == .tapOutside }

    var body: some View {
        let items = board.sentence.items
        let count = max(1, items.count)
        let spacingRatio: CGFloat = 0.08
        let widthLimited = containerSize.width * 0.9 / (CGFloat(count) + spacingRatio * CGFloat(count - 1))
        let side = min(containerSize.height * 0.5, widthLimited)
        let spacing = side * spacingRatio

        ZStack {
            ShowScrim(dismissMode: dismissMode, canSwipeCard: canSwipe, onClose: close)

            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, placement in
                    if let pictogram = placement.pictogram {
                        let isReading = board.sentence.readingIndex == index
                        CardView(pictogram: pictogram)
                            // Once swiped away, the cards leave the screen instead of flying back to the bar.
                            .heroEffect(id: SentenceSlot(index: index), in: namespace, enabled: !reduceMotion && !isFlyingAway)
                            .frame(width: side, height: side)
                            .scaleEffect(isReading ? 1.08 : 1)
                            .shadow(
                                color: isReading ? Color.yellow.opacity(0.75) : Color.black.opacity(0.25),
                                radius: isReading ? side * 0.08 : side * 0.03
                            )
                    }
                }
            }
            .phaseAnimator([0, 1, 2], trigger: bump) { content, phase in
                content.scaleEffect(phase == 1 ? 1.04 : 1)
            } animation: { _ in
                .spring(response: 0.22, dampingFraction: 0.55)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                board.readSentence()
                if celebration && !reduceMotion { bump += 1 }
            }
            // Wins over the tap, so a swipe never reads the sentence again. Movements shorter than
            // `SwipeDismiss.startDistance` are not a drag, so a wobbly tap still reads it.
            .highPriorityGesture(swipe(side: side))
            .rotationEffect(.degrees(Double(swipeOffset.width / max(containerSize.width, 1)) * 12))
            .offset(swipeOffset)
            .opacity(swipeOpacity(side: side))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(board.sentence.spokenText)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(canSwipe ? "Touchez pour réécouter, glissez pour fermer" : "Touchez pour réécouter")
        }
        .task {
            // Let the cards land in the centre before reading.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 450))
            guard !Task.isCancelled else { return }
            board.readSentence()
            if celebration && !reduceMotion { bump += 1 }
        }
        .onChange(of: board.sentence.isReading) { _, isReading in
            autoCloseTask?.cancel()
            guard !isReading, autoCloseSeconds > 0 else { return }
            autoCloseTask = Task {
                try? await Task.sleep(for: .seconds(autoCloseSeconds))
                if !Task.isCancelled { close() }
            }
        }
        .onDisappear {
            autoCloseTask?.cancel()
        }
    }

    private func swipeOpacity(side: CGFloat) -> Double {
        guard !isFlyingAway, side > 0 else { return 1 }
        let distance = (swipeOffset.width * swipeOffset.width + swipeOffset.height * swipeOffset.height).squareRoot()
        return 1 - min(Double(distance / side), 1) * 0.35
    }

    /// The same swipe as on a single shown card: the whole sentence moves together and is thrown off
    /// the screen. Distances are measured against one card's side, so the feel matches a single card.
    private func swipe(side: CGFloat) -> some Gesture {
        // Global coordinates: the sentence moves under the finger, so its own space would shift.
        DragGesture(minimumDistance: SwipeDismiss.startDistance, coordinateSpace: .global)
            .onChanged { value in
                guard canSwipe, !isFlyingAway else { return }
                swipeOffset = value.translation
            }
            .onEnded { value in
                guard canSwipe, !isFlyingAway else { return }
                if SwipeDismiss.shouldDismiss(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    cardSide: side
                ) {
                    flyAway(value)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { swipeOffset = .zero }
                }
            }
    }

    private func flyAway(_ value: DragGesture.Value) {
        autoCloseTask?.cancel()
        if reduceMotion {
            close()
            return
        }
        // Stop reading straight away: the sentence is leaving.
        SpeechService.shared.stop()
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) { isFlyingAway = true }
        let target = SwipeDismiss.flyAwayOffset(
            translation: value.translation,
            predictedEndTranslation: value.predictedEndTranslation,
            containerSize: containerSize
        )
        withAnimation(.easeIn(duration: 0.22)) {
            swipeOffset = target
        } completion: {
            close()
        }
    }

    private func close() {
        board.closeSentenceShown(reduceMotion: reduceMotion)
    }
}
