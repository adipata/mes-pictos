import XCTest
import SwiftUI
import SwiftData
import PictoCore
@testable import MesPictos

/// Opt-in visual check of the board: renders the real `BoardView` with the starter kit, composes a
/// sentence and saves screenshots. Skipped unless the environment variable `SMOKE_SCREENSHOT_DIR`
/// is set, for example:
///
///     TEST_RUNNER_SMOKE_SCREENSHOT_DIR=/tmp/shots xcodebuild test ... -only-testing:mes-pictosTests/VisualSmokeTests
@MainActor
final class VisualSmokeTests: XCTestCase {
    func testSentenceBarAndOverlayScreenshots() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SMOKE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set SMOKE_SCREENSHOT_DIR to render screenshots")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let container = Persistence.makeInMemoryContainer()
        let store = PictoStore(context: container.mainContext)
        let kit = try XCTUnwrap(StarterKit.load())
        store.seedStarterContent()
        store.installStarterKit(kit)

        let board = BoardModel()
        let food = try XCTUnwrap(store.normalPages().first { $0.title == "Manger" })
        board.selectedPageID = food.id

        let window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
        let host = UIHostingController(rootView: BoardView(board: board).modelContainer(container))
        window.rootViewController = host
        try await Task.sleep(for: .milliseconds(800))
        try save(window, "1-board", in: directory)

        // The child taps "Je veux" on the bar, then "pomme" on the page.
        let bar = try XCTUnwrap(store.permanentBar())
        let jeVeux = try XCTUnwrap(bar.placement(at: 1))
        let pomme = try XCTUnwrap(food.placement(at: 0))
        board.select(jeVeux, reduceMotion: true)
        try await Task.sleep(for: .milliseconds(1200))
        board.select(pomme, reduceMotion: true)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(board.sentence.items.count, 2)
        XCTAssertEqual(board.sentence.spokenText, "Je veux une pomme")
        try save(window, "2-sentence-bar", in: directory)

        // "Dire": the sentence comes to the centre and is read.
        board.speakSentence(reduceMotion: true)
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertTrue(board.sentence.isShown)
        try save(window, "3-sentence-shown", in: directory)

        board.closeSentenceShown(reduceMotion: true)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(board.sentence.isComposing, "Closing clears the sentence")
        try save(window, "4-after-close", in: directory)

        // A direct tap still shows the card alone.
        board.select(pomme, reduceMotion: true)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertNotNil(board.shown)
        XCTAssertFalse(board.sentence.isComposing)
        board.closeShown(reduceMotion: true)
    }

    private func save(_ window: UIWindow, _ name: String, in directory: String) throws {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
    }
}
