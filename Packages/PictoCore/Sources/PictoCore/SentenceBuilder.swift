import Foundation

/// The sentence being composed on the sentence bar: a starter ("Je veux") followed by words ("une pomme").
///
/// One rule per gesture, so the child can learn it:
/// - tapping a starter always begins a new sentence
/// - tapping a word adds it once, while there is room
public struct SentenceBuilder<Item: Hashable>: Equatable {
    public enum Effect: Equatable {
        /// A new sentence began with this starter.
        case started
        /// The item is already in the sentence; it is only spoken again.
        case repeated
        /// The word was added.
        case appended
        /// No room left for another word.
        case full
        /// No sentence in progress: the tap is not for the sentence bar.
        case ignored
    }

    public private(set) var starter: Item?
    public private(set) var words: [Item] = []
    /// Maximum number of words after the starter.
    public var maxWords: Int {
        didSet { maxWords = max(1, maxWords) }
    }

    public init(maxWords: Int) {
        self.maxWords = max(1, maxWords)
    }

    public var isComposing: Bool { starter != nil }
    /// A sentence can be said as soon as it has a starter ("J'ai besoin d'aide" stands alone).
    public var canSpeak: Bool { starter != nil }
    public var isFull: Bool { words.count >= maxWords }
    public var all: [Item] { (starter.map { [$0] } ?? []) + words }

    public mutating func tapStarter(_ item: Item) -> Effect {
        let repeated = starter == item && words.isEmpty
        starter = item
        words = []
        return repeated ? .repeated : .started
    }

    public mutating func tapWord(_ item: Item) -> Effect {
        guard isComposing else { return .ignored }
        if starter == item || words.contains(item) { return .repeated }
        guard !isFull else { return .full }
        words.append(item)
        return .appended
    }

    /// Takes a card off the strip. Removing the starter clears the sentence, because the words
    /// cannot stand without it. Returns false when the card was not in the sentence.
    @discardableResult
    public mutating func remove(_ item: Item) -> Bool {
        if starter == item {
            clear()
            return true
        }
        guard let index = words.firstIndex(of: item) else { return false }
        words.remove(at: index)
        return true
    }

    /// Takes the card at this position of `all` off the strip (0 is the starter).
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        let items = all
        guard items.indices.contains(index) else { return false }
        return remove(items[index])
    }

    public mutating func clear() {
        starter = nil
        words = []
    }
}
