import XCTest
import SwiftData
import PictoCore
@testable import MesPictos

@MainActor
final class StarterKitTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() -> PictoStore {
        let container = Persistence.makeInMemoryContainer()
        self.container = container
        return PictoStore(context: container.mainContext)
    }

    private func loadKit() throws -> StarterKit {
        try XCTUnwrap(StarterKit.load(), "StarterKit.json must be bundled with the app")
    }

    func testKitCoversTheStarterVocabulary() throws {
        let kit = try loadKit()
        XCTAssertEqual(kit.bar.items.map(\.label), ["Aide", "Je veux", "Ouvre"])
        XCTAssertTrue(kit.bar.items.allSatisfy(\.isStarter), "The actions on the bar open the sentence bar")
        XCTAssertEqual(
            kit.pages.map(\.title),
            ["Cartes critiques", "Débuts de phrase", "Manger", "Jouer", "Corps et soins", "Personnes", "Émotions", "École", "Animaux", "Lieux et sorties"]
        )
        let critical = try XCTUnwrap(kit.page(titled: "Cartes critiques"))
        XCTAssertEqual(critical.items.map(\.label), ["Non", "Oui", "Attends", "Fini", "Encore", "Pause"])
        XCTAssertFalse(critical.items.contains(where: \.isStarter))
        let starters = try XCTUnwrap(kit.page(titled: "Débuts de phrase"))
        XCTAssertTrue(starters.items.allSatisfy(\.isStarter))
        XCTAssertFalse(try XCTUnwrap(kit.page(titled: "Manger")).items.contains(where: \.isStarter))
        XCTAssertTrue(kit.starterLabels.isSuperset(of: ["aide", "je veux", "ouvre", "je vois"]))
        XCTAssertTrue(kit.starterSourceRefs.contains("5441"))
        let food = try XCTUnwrap(kit.pages.first { $0.title == "Manger" })
        XCTAssertEqual(food.items.count, 18)
        for page in kit.pages + [kit.bar] {
            XCTAssertLessThanOrEqual(page.items.count, page.columns * page.rows, "\(page.title) has more items than slots")
        }
    }

    func testEveryKitImageIsBundled() throws {
        let kit = try loadKit()
        for item in kit.allItems {
            let data = kit.imageData(for: item)
            XCTAssertNotNil(data, "Missing image for \(item.label) (\(item.imageName))")
            XCTAssertGreaterThan(data?.count ?? 0, 500, "\(item.imageName) looks empty")
        }
    }

    func testInstallCreatesBarAndPagesOnce() throws {
        let kit = try loadKit()
        let store = makeStore()

        let added = store.installStarterKit(kit)
        XCTAssertEqual(added, kit.pictogramCount)
        XCTAssertEqual(store.normalPages().map(\.title), kit.pages.map(\.title))

        let bar = try XCTUnwrap(store.permanentBar())
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.label, "Aide")
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.spokenText, "J'ai besoin d'aide")
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.source, .arasaac)
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.licence, ArasaacAPI.licence)
        XCTAssertEqual(bar.placement(at: 1)?.pictogram?.label, "Je veux")
        XCTAssertEqual(bar.placement(at: 1)?.pictogram?.wordType, .starter)
        XCTAssertEqual((bar.placements ?? []).count, 3)
        let apple = try XCTUnwrap(store.normalPages().first { $0.title == "Manger" }?.placement(at: 0)?.pictogram)
        XCTAssertFalse(apple.isSentenceStarter)

        // A second install changes nothing.
        XCTAssertEqual(store.installStarterKit(kit), 0)
        XCTAssertEqual(store.normalPages().count, kit.pages.count)
        XCTAssertEqual((bar.placements ?? []).count, 3)
    }

    func testInstallCompletesAnExistingBar() throws {
        let kit = try loadKit()
        let store = makeStore()
        store.seedStarterContent() // "Mes choses" + "Cartes critiques" + bar with Aide, Je veux, Ouvre

        let added = store.installStarterKit(kit)

        XCTAssertEqual(added, kit.pictogramCount - 3 - 6, "The bar and the critical cards were already there")
        let bar = try XCTUnwrap(store.permanentBar())
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.label, "Aide", "Existing cards keep their slot")
        XCTAssertEqual((bar.placements ?? []).count, 3)
        XCTAssertEqual(store.normalPages().map(\.title).prefix(2), ["Mes choses", "Cartes critiques"])
        XCTAssertEqual(store.normalPages().count, 1 + kit.pages.count)
    }

    func testInstallAddsActionsToAnOldBar() throws {
        // A bar from the first version: Non and Aide, Aide not yet a starter.
        let kit = try loadKit()
        let store = makeStore()
        let bar = Page(title: "Barre permanente", columns: 6, rows: 1, sortIndex: 0, kind: .permanentBar)
        store.context.insert(bar)
        store.createPictogram(label: "Non", on: bar, slot: 0)
        store.createPictogram(label: "Aide", spokenText: "J'ai besoin d'aide", on: bar, slot: 1)

        store.installStarterKit(kit)

        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.label, "Non")
        XCTAssertEqual(bar.placement(at: 1)?.pictogram?.label, "Aide")
        XCTAssertEqual(bar.placement(at: 1)?.pictogram?.isSentenceStarter, true, "Upgraded by label")
        XCTAssertEqual(bar.placement(at: 2)?.pictogram?.label, "Je veux")
        XCTAssertEqual(bar.placement(at: 3)?.pictogram?.label, "Ouvre")
        XCTAssertEqual(bar.placement(at: 3)?.pictogram?.isSentenceStarter, true)
    }

    func testSeedUsesArasaacCardsWhenBundled() throws {
        let store = makeStore()
        store.seedStarterContent()
        let bar = try XCTUnwrap(store.permanentBar())
        XCTAssertEqual((0..<3).map { bar.placement(at: $0)?.pictogram?.label }, ["Aide", "Je veux", "Ouvre"])
        XCTAssertTrue((0..<3).allSatisfy { bar.placement(at: $0)?.pictogram?.isSentenceStarter == true })
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.source, .arasaac)
        XCTAssertEqual(bar.placement(at: 0)?.pictogram?.sourceRef, "12252")

        let critical = try XCTUnwrap(store.normalPages().first { $0.title == "Cartes critiques" })
        XCTAssertEqual(critical.placement(at: 0)?.pictogram?.label, "Non")
        XCTAssertEqual(critical.placement(at: 0)?.pictogram?.sourceRef, "5526")
        XCTAssertEqual((critical.placements ?? []).count, 6)
    }

    func testUpgradeStartersIsIdempotentAndNeverDowngrades() throws {
        let kit = try loadKit()
        let store = makeStore()
        let page = store.addPage(title: "Mes choses")
        store.createPictogram(label: "je veux", on: page) // a parent's photo card, not yet a starter
        store.createPictogram(label: "pomme", on: page)
        store.createPictogram(label: "ma phrase", wordType: .starter, on: page)

        XCTAssertEqual(store.upgradeStarters(using: kit), 1)
        XCTAssertEqual(page.placement(at: 0)?.pictogram?.isSentenceStarter, true)
        XCTAssertEqual(page.placement(at: 1)?.pictogram?.isSentenceStarter, false)
        XCTAssertEqual(page.placement(at: 2)?.pictogram?.isSentenceStarter, true, "Custom starters are kept")
        XCTAssertEqual(store.upgradeStarters(using: kit), 0)
    }
}
