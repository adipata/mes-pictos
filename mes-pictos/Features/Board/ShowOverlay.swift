import SwiftUI
import PictoCore

/// Show mode: the selected card in the centre of the screen, so the child can show it to an adult.
struct ShowOverlay: View {
    let placement: Placement
    let namespace: Namespace.ID
    let containerSize: CGSize

    @Environment(BoardModel.self) private var board
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.showDismissMode) private var dismissRaw = DismissMode.tapOutside.rawValue
    @AppStorage(SettingsKey.showAutoCloseSeconds) private var autoCloseSeconds = SettingsDefault.showAutoCloseSeconds
    @AppStorage(SettingsKey.showCelebration) private var celebration = SettingsDefault.showCelebration
    @State private var bump = 0
    @State private var glow = false
    /// How far the card follows the child's finger while it is swiped.
    @State private var swipeOffset: CGSize = .zero
    /// The card was swiped away and is flying off the screen.
    @State private var isFlyingAway = false

    private var dismissMode: DismissMode { DismissMode(rawValue: dismissRaw) ?? .tapOutside }
    private var side: CGFloat { min(containerSize.width, containerSize.height) * 0.72 }
    /// Swiping the card closes it, like tapping outside. With the adult-only setting it does not.
    private var canSwipe: Bool { dismissMode == .tapOutside }

    var body: some View {
        ZStack {
            ShowScrim(dismissMode: dismissMode, canSwipeCard: canSwipe, onClose: close)

            if let pictogram = placement.pictogram {
                CardView(pictogram: pictogram)
                    // Once swiped away, the card leaves the screen instead of flying back to the grid.
                    .heroEffect(id: placement.id, in: namespace, enabled: !reduceMotion && !isFlyingAway)
                    .frame(width: side, height: side)
                    .shadow(
                        color: glow ? Color.yellow.opacity(0.7) : Color.black.opacity(0.25),
                        radius: glow ? side * 0.08 : side * 0.03
                    )
                    .phaseAnimator([0, 1, 2], trigger: bump) { content, phase in
                        content.scaleEffect(phase == 1 ? 1.06 : 1)
                    } animation: { _ in
                        .spring(response: 0.22, dampingFraction: 0.55)
                    }
                    .onTapGesture {
                        SpeechService.shared.speak(pictogram)
                        if celebration && !reduceMotion { bump += 1 }
                    }
                    // Wins over the tap, so a swipe never speaks the card again. Movements shorter than
                    // `SwipeDismiss.startDistance` are not a drag, so a wobbly tap still speaks it.
                    .highPriorityGesture(swipe)
                    .rotationEffect(.degrees(Double(swipeOffset.width / side) * 12))
                    .offset(swipeOffset)
                    .opacity(swipeOpacity)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(canSwipe ? "Touchez pour réécouter, glissez pour fermer" : "Touchez pour réécouter")
            }
        }
        .task(id: placement.id) {
            if celebration && !reduceMotion {
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(.easeOut(duration: 0.4)) { glow = true }
                bump += 1
            }
            if autoCloseSeconds > 0 {
                try? await Task.sleep(for: .seconds(autoCloseSeconds))
                if !Task.isCancelled { close() }
            }
        }
    }

    private var swipeOpacity: Double {
        guard !isFlyingAway else { return 1 }
        let distance = (swipeOffset.width * swipeOffset.width + swipeOffset.height * swipeOffset.height).squareRoot()
        return 1 - min(Double(distance / side), 1) * 0.35
    }

    private var swipe: some Gesture {
        // Global coordinates: the card moves under the finger, so its own space would shift.
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
        if reduceMotion {
            close()
            return
        }
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
        glow = false
        board.closeShown(reduceMotion: reduceMotion)
    }
}
