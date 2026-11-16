import SwiftUI

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

    private var dismissMode: DismissMode { DismissMode(rawValue: dismissRaw) ?? .tapOutside }

    var body: some View {
        let items = board.sentence.items
        let count = max(1, items.count)
        let spacingRatio: CGFloat = 0.08
        let widthLimited = containerSize.width * 0.9 / (CGFloat(count) + spacingRatio * CGFloat(count - 1))
        let side = min(containerSize.height * 0.5, widthLimited)
        let spacing = side * spacingRatio

        ZStack {
            ShowScrim(dismissMode: dismissMode, onClose: close)

            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, placement in
                    if let pictogram = placement.pictogram {
                        let isReading = board.sentence.readingIndex == index
                        CardView(pictogram: pictogram)
                            .heroEffect(id: SentenceSlot(index: index), in: namespace, enabled: !reduceMotion)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(board.sentence.spokenText)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Touchez pour réécouter")
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

    private func close() {
        board.closeSentenceShown(reduceMotion: reduceMotion)
    }
}
