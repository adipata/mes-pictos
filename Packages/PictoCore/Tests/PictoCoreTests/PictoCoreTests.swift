import XCTest
import CoreGraphics
@testable import PictoCore

final class GridMathTests: XCTestCase {
    func testGridSizeIsClamped() {
        let size = GridSize(columns: 0, rows: 99)
        XCTAssertEqual(size.columns, 1)
        XCTAssertEqual(size.rows, 6)
    }

    func testFirstFreeSlot() {
        XCTAssertEqual(GridMath.firstFreeSlot(occupied: [], capacity: 4), 0)
        XCTAssertEqual(GridMath.firstFreeSlot(occupied: [0, 1, 3], capacity: 4), 2)
        XCTAssertNil(GridMath.firstFreeSlot(occupied: [0, 1, 2, 3], capacity: 4))
    }

    func testResizeKeepsVisualPositions() {
        // 2×2: a at (0,0), b at (1,1) → 3×2: a stays (0,0)=0, b stays (1,1)=4.
        let result = GridMath.resize(["a": 0, "b": 3], from: GridSize(columns: 2, rows: 2), to: GridSize(columns: 3, rows: 2))
        XCTAssertEqual(result, ["a": 0, "b": 4])
    }

    func testResizeMovesOverflowIntoFreeSlots() {
        // 3×1: a=0, b=1, c=2 → 2×2: c at column 2 no longer exists, goes to first free slot (2).
        let result = GridMath.resize(["a": 0, "b": 1, "c": 2], from: GridSize(columns: 3, rows: 1), to: GridSize(columns: 2, rows: 2))
        XCTAssertEqual(result, ["a": 0, "b": 1, "c": 2])

        // 2×2: d at (1,1)=3 → 2×1: row 1 is gone, d goes to free slot 1.
        let shrunk = GridMath.resize(["a": 0, "d": 3], from: GridSize(columns: 2, rows: 2), to: GridSize(columns: 2, rows: 1))
        XCTAssertEqual(shrunk, ["a": 0, "d": 1])
    }

    func testResizeFailsWhenTooManyItems() {
        XCTAssertNil(GridMath.resize(["a": 0, "b": 1, "c": 2], from: GridSize(columns: 2, rows: 2), to: GridSize(columns: 2, rows: 1)))
    }
}

final class SpeechResolverTests: XCTestCase {
    func testRecordingWins() {
        let data = Data([1, 2, 3])
        XCTAssertEqual(SpeechResolver.resolve(label: "pomme", spokenText: "une pomme", recording: data), .recording(data))
    }

    func testSpokenTextBeforeLabel() {
        XCTAssertEqual(SpeechResolver.resolve(label: "pomme", spokenText: " une pomme ", recording: nil), .text("une pomme"))
    }

    func testFallsBackToLabel() {
        XCTAssertEqual(SpeechResolver.resolve(label: "pomme", spokenText: "  ", recording: Data()), .text("pomme"))
        XCTAssertEqual(SpeechResolver.resolve(label: " ", spokenText: nil, recording: nil), .none)
    }
}

final class LabelStyleTests: XCTestCase {
    func testFrenchUppercase() {
        XCTAssertEqual(LabelStyle.uppercase.format("gâteau"), "GÂTEAU")
        XCTAssertEqual(LabelStyle.lowercase.format("Élodie"), "élodie")
        XCTAssertEqual(LabelStyle.asTyped.format(" Lait "), "Lait")
        XCTAssertNil(LabelStyle.hidden.format("lait"))
        XCTAssertNil(LabelStyle.uppercase.format("  "))
    }
}

final class TapDebouncerTests: XCTestCase {
    func testIgnoresFastRepeats() {
        var debouncer = TapDebouncer()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(debouncer.shouldAccept(at: start, minimumInterval: 0.5))
        XCTAssertFalse(debouncer.shouldAccept(at: start.addingTimeInterval(0.2), minimumInterval: 0.5))
        XCTAssertTrue(debouncer.shouldAccept(at: start.addingTimeInterval(0.6), minimumInterval: 0.5))
    }
}

final class CropMathTests: XCTestCase {
    func testSquareImageFullCrop() {
        let rect = CropMath.cropRect(imageSize: CGSize(width: 1000, height: 1000), side: 500, zoom: 1, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    func testLandscapeImageCentreCrop() {
        let rect = CropMath.cropRect(imageSize: CGSize(width: 2000, height: 1000), side: 500, zoom: 1, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: 500, y: 0, width: 1000, height: 1000))
    }

    func testZoomAndOffset() {
        // Zoom 2 on a 1000×1000 image in a 500 square: scale is 1, the visible area is 500×500
        // image points, centred at (250, 250). Moving the image 100 points right shows 100 points further left.
        let rect = CropMath.cropRect(imageSize: CGSize(width: 1000, height: 1000), side: 500, zoom: 2, offset: CGSize(width: 100, height: 0))
        XCTAssertEqual(rect, CGRect(x: 150, y: 250, width: 500, height: 500))
    }

    func testOffsetIsClamped() {
        let clamped = CropMath.clampedOffset(CGSize(width: 900, height: -900), imageSize: CGSize(width: 2000, height: 1000), side: 500, zoom: 1)
        XCTAssertEqual(clamped, CGSize(width: 250, height: 0))
    }
}

final class ParentCodeTests: XCTestCase {
    func testValidation() {
        XCTAssertTrue(ParentCode.isValid("1234"))
        XCTAssertTrue(ParentCode.isValid("123456"))
        XCTAssertFalse(ParentCode.isValid("123"))
        XCTAssertFalse(ParentCode.isValid("12a4"))
        XCTAssertFalse(ParentCode.isValid("１２３４"))
    }
}

final class ArasaacTests: XCTestCase {
    /// Recorded from GET https://api.arasaac.org/v1/pictograms/fr/bestsearch/pomme (trimmed).
    private let fixture = """
    [{"_id":2462,"created":"2007-12-14T12:34:03.000Z","tags":["feeding","food"],"sex":false,"schematic":false,
      "keywords":[{"type":2,"keyword":"pomme","hasLocution":true,"plural":"pommes"}],"categories":["fruit"],"aac":true},
     {"_id":13644,"keywords":[{"type":2,"keyword":"pomme"},{"keyword":"fruit"}],"aac":false},
     {"_id":99,"keywords":[]}]
    """

    func testDecodesSearchResults() throws {
        let results = try ArasaacAPI.decodeSearch(Data(fixture.utf8))
        XCTAssertEqual(results.map(\.id), [2462, 13644, 99])
        XCTAssertEqual(results[0].title, "pomme")
        XCTAssertEqual(results[1].keywords, ["pomme", "fruit"])
        XCTAssertEqual(results[2].title, "#99", "A pictogram without keywords still has a title")
    }

    func testURLs() {
        XCTAssertEqual(ArasaacAPI.searchURL("  jus d'orange ")?.absoluteString, "https://api.arasaac.org/v1/pictograms/fr/search/jus%20d'orange")
        XCTAssertNil(ArasaacAPI.searchURL("   "))
        XCTAssertEqual(ArasaacAPI.imageURL(id: 2462).absoluteString, "https://static.arasaac.org/pictograms/2462/2462_500.png")
        XCTAssertEqual(ArasaacAPI.imageURL(id: 7, resolution: 300).lastPathComponent, "7_300.png")
    }
}

final class SentenceBuilderTests: XCTestCase {
    func testStarterBeginsNewSentence() {
        var builder = SentenceBuilder<String>(maxWords: 2)
        XCTAssertFalse(builder.isComposing)
        XCTAssertEqual(builder.tapWord("pomme"), .ignored)

        XCTAssertEqual(builder.tapStarter("je veux"), .started)
        XCTAssertTrue(builder.canSpeak, "A starter alone can be said")
        XCTAssertEqual(builder.tapWord("pomme"), .appended)
        XCTAssertEqual(builder.all, ["je veux", "pomme"])

        XCTAssertEqual(builder.tapStarter("ouvre"), .started, "Another starter replaces everything")
        XCTAssertEqual(builder.all, ["ouvre"])
        XCTAssertEqual(builder.tapStarter("ouvre"), .repeated)
    }

    func testWordsAreAddedOnceUpToTheLimit() {
        var builder = SentenceBuilder<String>(maxWords: 2)
        _ = builder.tapStarter("je veux")
        XCTAssertEqual(builder.tapWord("pomme"), .appended)
        XCTAssertEqual(builder.tapWord("pomme"), .repeated)
        XCTAssertEqual(builder.tapWord("je veux"), .repeated)
        XCTAssertEqual(builder.tapWord("lait"), .appended)
        XCTAssertTrue(builder.isFull)
        XCTAssertEqual(builder.tapWord("pain"), .full)
        XCTAssertEqual(builder.all, ["je veux", "pomme", "lait"])

        builder.clear()
        XCTAssertFalse(builder.isComposing)
        XCTAssertTrue(builder.all.isEmpty)
    }

    func testRemovingCards() {
        var builder = SentenceBuilder<String>(maxWords: 3)
        _ = builder.tapStarter("je veux")
        _ = builder.tapWord("pomme")
        _ = builder.tapWord("lait")

        XCTAssertTrue(builder.remove(at: 1))
        XCTAssertEqual(builder.all, ["je veux", "lait"])
        XCTAssertFalse(builder.remove("pain"))
        XCTAssertFalse(builder.remove(at: 5))
        XCTAssertEqual(builder.tapWord("pomme"), .appended, "A removed word can be added again")

        XCTAssertTrue(builder.remove(at: 0), "Removing the starter clears the sentence")
        XCTAssertFalse(builder.isComposing)
        XCTAssertTrue(builder.all.isEmpty)
    }

    func testMaxWordsIsAtLeastOne() {
        var builder = SentenceBuilder<String>(maxWords: 0)
        XCTAssertEqual(builder.maxWords, 1)
        builder.maxWords = -3
        XCTAssertEqual(builder.maxWords, 1)
    }
}

final class SentenceTextTests: XCTestCase {
    func testJoinCapitalisesAndTracksRanges() {
        let result = SentenceText.join([" je veux ", "une pomme"])
        XCTAssertEqual(result.text, "Je veux une pomme")
        XCTAssertEqual(result.utf16Ranges, [0..<7, 8..<17])
        XCTAssertEqual(SentenceText.pieceIndex(forUTF16Location: 0, in: result.utf16Ranges), 0)
        XCTAssertEqual(SentenceText.pieceIndex(forUTF16Location: 7, in: result.utf16Ranges), 0, "The space belongs to the previous piece")
        XCTAssertEqual(SentenceText.pieceIndex(forUTF16Location: 12, in: result.utf16Ranges), 1)
    }

    func testJoinHandlesAccentsAndEmptyPieces() {
        let result = SentenceText.join(["ouvre", "  ", "l'école"])
        XCTAssertEqual(result.text, "Ouvre l'école")
        XCTAssertEqual(result.utf16Ranges, [0..<5, 5..<5, 6..<13])
        XCTAssertEqual(SentenceText.pieceIndex(forUTF16Location: 6, in: result.utf16Ranges), 2, "Empty pieces are skipped")
        XCTAssertEqual(SentenceText.join(["Élodie"]).text, "Élodie")
        XCTAssertEqual(SentenceText.join([]).text, "")
    }
}

final class SpeechPlannerTests: XCTestCase {
    func testConsecutiveTextIsOneUtterance() {
        let recording = Data([1, 2, 3])
        let segments = SpeechPlanner.segments(from: [.text("je veux"), .text("une pomme"), .recording(recording), .none, .text("et du lait")])
        XCTAssertEqual(segments, [
            .utterance(text: "Je veux une pomme", pieces: [.init(index: 0, utf16Range: 0..<7), .init(index: 1, utf16Range: 8..<17)]),
            .recording(recording, index: 2),
            .utterance(text: "Et du lait", pieces: [.init(index: 4, utf16Range: 0..<10)]),
        ])
        XCTAssertTrue(SpeechPlanner.segments(from: [.none]).isEmpty)
    }
}

final class SilentAudioTests: XCTestCase {
    func testWavLayout() {
        let data = SilentAudio.wavData(seconds: 0.5, sampleRate: 8000)
        XCTAssertEqual(data.count, SilentAudio.headerSize + 8000)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        let dataSize = data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: dataSize), 8000)
        let riffSize = data[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: riffSize), 36 + 8000)
        XCTAssertTrue(data[44...].allSatisfy { $0 == 0 }, "Silence")
    }
}

final class SwipeDismissTests: XCTestCase {
    private let side: CGFloat = 500

    func testSmallMovementDoesNotClose() {
        // A wobbly tap or a slow, short drag: the card stays.
        XCTAssertFalse(SwipeDismiss.shouldDismiss(translation: CGSize(width: 12, height: -8),
                                                  predictedEndTranslation: CGSize(width: 30, height: -20),
                                                  cardSide: side))
        XCTAssertFalse(SwipeDismiss.shouldDismiss(translation: CGSize(width: 60, height: 0),
                                                  predictedEndTranslation: CGSize(width: 70, height: 0),
                                                  cardSide: side))
    }

    func testLongDragClosesInAnyDirection() {
        let distance = SwipeDismiss.dismissDistance(cardSide: side)
        XCTAssertEqual(distance, 110)
        for translation in [CGSize(width: distance, height: 0), CGSize(width: -distance, height: 0),
                            CGSize(width: 0, height: distance), CGSize(width: 0, height: -distance)] {
            XCTAssertTrue(SwipeDismiss.shouldDismiss(translation: translation, predictedEndTranslation: translation, cardSide: side))
        }
    }

    func testFlickCloses() {
        XCTAssertTrue(SwipeDismiss.shouldDismiss(translation: CGSize(width: 50, height: 0),
                                                 predictedEndTranslation: CGSize(width: 300, height: 0),
                                                 cardSide: side))
        // Too short a movement, even if fast: still not a swipe.
        XCTAssertFalse(SwipeDismiss.shouldDismiss(translation: CGSize(width: 25, height: 0),
                                                  predictedEndTranslation: CGSize(width: 300, height: 0),
                                                  cardSide: side))
    }

    func testSmallCardsUseTheMinimumDistance() {
        XCTAssertEqual(SwipeDismiss.dismissDistance(cardSide: 200), SwipeDismiss.minimumDismissDistance)
    }

    func testFlyAwayFollowsTheSwipe() {
        let screen = CGSize(width: 800, height: 600)
        let offset = SwipeDismiss.flyAwayOffset(translation: CGSize(width: -120, height: 0),
                                                predictedEndTranslation: CGSize(width: -400, height: 0),
                                                containerSize: screen)
        XCTAssertLessThan(offset.width, -screen.width)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
    }
}
