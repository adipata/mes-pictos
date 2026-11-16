import Foundation

/// Builds the text of a sentence from the spoken text of each card.
public enum SentenceText {
    /// Pieces joined with single spaces, trimmed, first letter upper-cased.
    /// Returns the UTF-16 range of each piece in the result, so `AVSpeechSynthesizer` ranges
    /// (which are UTF-16 `NSRange`s) can be mapped back to a card.
    public static func join(_ pieces: [String]) -> (text: String, utf16Ranges: [Range<Int>]) {
        var text = ""
        var ranges: [Range<Int>] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                ranges.append(text.utf16.count..<text.utf16.count)
                continue
            }
            if !text.isEmpty { text += " " }
            let start = text.utf16.count
            text += trimmed
            ranges.append(start..<text.utf16.count)
        }
        if let first = text.first, first.isLowercase {
            text = String(first).uppercased(with: Locale(identifier: "fr_FR")) + text.dropFirst()
        }
        return (text, ranges)
    }

    /// The piece containing a UTF-16 location: the last range that starts at or before it.
    public static func pieceIndex(forUTF16Location location: Int, in ranges: [Range<Int>]) -> Int? {
        ranges.lastIndex { !$0.isEmpty && $0.lowerBound <= location }
    }
}

/// One step of a read-aloud sequence.
public enum SpeechSegment: Equatable {
    public struct Piece: Equatable {
        /// Index of the card in the original list.
        public let index: Int
        public let utf16Range: Range<Int>

        public init(index: Int, utf16Range: Range<Int>) {
            self.index = index
            self.utf16Range = utf16Range
        }
    }

    /// Consecutive text cards, read as one utterance for natural prosody.
    case utterance(text: String, pieces: [Piece])
    /// A parent's recording for one card.
    case recording(Data, index: Int)
}

public enum SpeechPlanner {
    /// Groups consecutive `.text` cards into one utterance, keeps recordings separate, drops `.none`.
    public static func segments(from contents: [SpeechContent]) -> [SpeechSegment] {
        var segments: [SpeechSegment] = []
        var pending: [(index: Int, text: String)] = []

        func flush() {
            guard !pending.isEmpty else { return }
            let joined = SentenceText.join(pending.map(\.text))
            let pieces = zip(pending, joined.utf16Ranges).map { SpeechSegment.Piece(index: $0.index, utf16Range: $1) }
            segments.append(.utterance(text: joined.text, pieces: pieces))
            pending = []
        }

        for (index, content) in contents.enumerated() {
            switch content {
            case .text(let text):
                pending.append((index, text))
            case .recording(let data):
                flush()
                segments.append(.recording(data, index: index))
            case .none:
                break
            }
        }
        flush()
        return segments
    }
}
