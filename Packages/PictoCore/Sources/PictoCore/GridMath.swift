import Foundation
import CoreGraphics

/// Size of a page grid. Slots are numbered row by row: `slot = row * columns + column`.
public struct GridSize: Equatable, Sendable {
    public static let columnRange = 1...10
    public static let rowRange = 1...10

    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        self.rows = min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
    }

    public var capacity: Int { columns * rows }

    public func row(of slot: Int) -> Int { slot / columns }
    public func column(of slot: Int) -> Int { slot % columns }
    public func contains(_ slot: Int) -> Bool { slot >= 0 && slot < capacity }
}

public enum GridMath {
    /// The lowest slot that is not occupied, or nil when the page is full.
    public static func firstFreeSlot(occupied: Set<Int>, capacity: Int) -> Int? {
        (0..<max(capacity, 0)).first { !occupied.contains($0) }
    }

    /// New slots after a grid resize.
    ///
    /// Items keep their visual position (row, column) when it still exists in the new grid.
    /// The others are placed in the free slots, in their previous order.
    /// Returns nil when there are more items than slots in the new grid.
    public static func resize<ID: Hashable>(
        _ slots: [ID: Int],
        from old: GridSize,
        to new: GridSize
    ) -> [ID: Int]? {
        guard slots.count <= new.capacity else { return nil }

        var result: [ID: Int] = [:]
        var overflow: [(ID, Int)] = []
        var taken = Set<Int>()

        for (id, slot) in slots.sorted(by: { $0.value < $1.value }) {
            let row = old.row(of: slot)
            let column = old.column(of: slot)
            let candidate = row * new.columns + column
            if row < new.rows, column < new.columns, !taken.contains(candidate) {
                result[id] = candidate
                taken.insert(candidate)
            } else {
                overflow.append((id, slot))
            }
        }

        for (id, _) in overflow {
            guard let free = firstFreeSlot(occupied: taken, capacity: new.capacity) else { return nil }
            result[id] = free
            taken.insert(free)
        }
        return result
    }
}

/// Size of the cards of a page grid on screen.
///
/// Cards fill the available space. When that would make them smaller than `minimumSide`
/// (a big grid on a small screen), they keep `minimumSide` and the grid scrolls instead,
/// so every card stays big enough to see and tap.
public struct CardGridLayout: Equatable, Sendable {
    public let side: CGFloat
    public let contentSize: CGSize
    public let scrollsHorizontally: Bool
    public let scrollsVertically: Bool

    public init(columns: Int, rows: Int, available: CGSize, spacing: CGFloat, minimumSide: CGFloat) {
        let columns = max(columns, 1)
        let rows = max(rows, 1)
        let fitWidth = (available.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let fitHeight = (available.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        let side = max(minimumSide, min(fitWidth, fitHeight), 1)
        let size = CGSize(
            width: side * CGFloat(columns) + spacing * CGFloat(columns - 1),
            height: side * CGFloat(rows) + spacing * CGFloat(rows - 1)
        )
        self.side = side
        self.contentSize = size
        // Half a point of tolerance for rounding.
        self.scrollsHorizontally = size.width > available.width + 0.5
        self.scrollsVertically = size.height > available.height + 0.5
    }

    public var scrolls: Bool { scrollsHorizontally || scrollsVertically }
}
