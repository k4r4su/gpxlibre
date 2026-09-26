import XCTest
@testable import GPXlibre

/// It31, point 3 — tutoriel intégré : une page par onglet, dans l'ordre de la barre d'onglets,
/// aucune page ni rubrique vide. (La justesse du CONTENU se vérifie à la main en fin d'itération :
/// voir la règle permanente dans CLAUDE.md.)
final class TutorialContentTests: XCTestCase {
    func testOnePagePerTabInTabBarOrder() {
        XCTAssertEqual(TutorialContent.pages.map(\.id), ["ride", "goTo", "roadBook", "library", "settings"])
        XCTAssertEqual(TutorialContent.pages.count, AppTab.allCasesForTutorial.count)
    }

    func testNoEmptyPageOrTopic() {
        for page in TutorialContent.pages {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.summary.isEmpty)
            XCTAssertFalse(page.topics.isEmpty, page.id)
            for topic in page.topics {
                XCTAssertFalse(topic.points.isEmpty, "\(page.id) / \(topic.title)")
                XCTAssertTrue(topic.points.allSatisfy { !$0.isEmpty })
            }
        }
    }
}

private extension AppTab {
    /// Onglets de la barre (ride, search, roadBook, library, settings).
    static var allCasesForTutorial: [AppTab] { [.ride, .search, .roadBook, .library, .settings] }
}
