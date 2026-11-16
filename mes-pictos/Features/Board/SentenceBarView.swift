import SwiftUI
import PictoCore

/// The sentence bar (*bande phrase*), just above the permanent bar: the starter the child tapped,
/// the words added from the page, empty slots for the words still to come, and the "Dire" button.
struct SentenceBarView: View {
    let namespace: Namespace.ID
    let isCompact: Bool

    @Environment(BoardModel.self) private var board
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barHeight: CGFloat { isCompact ? 76 : 120 }
    private var spacing: CGFloat { isCompact ? 8 : 14 }
    private var clearWidth: CGFloat { isCompact ? 36 : 44 }
    private var speakWidth: CGFloat { isCompact ? 64 : 100 }

    var body: some View {
        let sentence = board.sentence
        let items = sentence.items
        let slotCount = sentence.builder.maxWords + 1

        GeometryReader { geometry in
            let available = geometry.size.width - clearWidth - speakWidth - spacing * CGFloat(slotCount + 1)
            let side = max(40, min(barHeight, available / CGFloat(slotCount)))

            HStack(spacing: spacing) {
                clearButton
                    .frame(width: clearWidth, height: barHeight)

                ForEach(0..<slotCount, id: \.self) { index in
                    slot(index, items: items, side: side)
                        .frame(width: side, height: side)
                }

                Spacer(minLength: 0)

                speakButton
                    .frame(width: speakWidth, height: barHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: barHeight)
        .padding(.horizontal, isCompact ? 12 : 24)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sentence.isEmpty ? "Bande phrase" : "Phrase : \(sentence.spokenText)")
    }

    // MARK: Pieces

    @ViewBuilder
    private func slot(_ index: Int, items: [Placement], side: CGFloat) -> some View {
        if index < items.count, let pictogram = items[index].pictogram {
            if board.sentence.isShown {
                // The card is in the centre of the screen; keep its place empty.
                Color.clear
            } else {
                let isReading = board.sentence.readingIndex == index
                CardView(pictogram: pictogram)
                    .heroEffect(id: SentenceSlot(index: index), in: namespace, enabled: !reduceMotion)
                    .scaleEffect(isReading ? 1.1 : 1)
                    .shadow(color: isReading ? Color.yellow.opacity(0.7) : .clear, radius: side * 0.1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        board.removeFromSentence(at: index, reduceMotion: reduceMotion)
                    }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(index == 0 ? "Touchez pour effacer la phrase" : "Touchez pour retirer ce mot")
            }
        } else {
            RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .accessibilityHidden(true)
        }
    }

    private var clearButton: some View {
        Button {
            board.clearSentence(reduceMotion: reduceMotion)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: isCompact ? 16 : 20, weight: .bold))
                .foregroundStyle(Color.secondary)
                .frame(width: clearWidth, height: clearWidth)
                .background(Color(.systemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effacer la phrase")
    }

    private var speakButton: some View {
        let enabled = board.sentence.canSpeak && !board.sentence.isReading
        return Button {
            board.speakSentence(reduceMotion: reduceMotion)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: isCompact ? 22 : 32, weight: .bold))
                Text("Dire")
                    .font(.system(size: isCompact ? 13 : 18, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green, in: RoundedRectangle(cornerRadius: isCompact ? 12 : 18, style: .continuous))
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Dire la phrase")
    }
}
