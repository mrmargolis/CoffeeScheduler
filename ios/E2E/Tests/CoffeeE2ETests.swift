import XCTest

/// End-to-end tests: launch the app on a simulator over the sample data
/// (`-sample-data`, today pinned to Mon 2026-10-12, held in memory so every
/// test starts fresh) and drive it the way a person would.
///
/// Sample bags: Guji Hambela (in progress), La Esperanza and Gichathaini AA
/// (resting), Janson Gesha (frozen, thaws Oct 27), Daterra (finished), with a
/// trip Oct 16-18 and a 60 g day on Oct 14.
@MainActor
final class CoffeeE2ETests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-sample-data"]
        app.launch()
    }

    // MARK: Helpers

    /// The first element of any kind whose label contains `text`. SwiftUI
    /// often merges a row's texts into one label, so exact matches miss.
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    private func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing: \(element)", file: file, line: line)
    }

    private func day(_ date: String) -> XCUIElement {
        app.buttons["day-\(date)"]
    }

    /// The schedule opens on the month grid; the day rows are in the list.
    private func showList() {
        let list = app.buttons["List"]
        waitFor(list)
        list.tap()
    }

    private func value(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    /// Wait for an element's accessibility value; "" also matches no value.
    private func expectValue(_ element: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate =
            expected.isEmpty
            ? NSPredicate(format: "value == nil OR value == ''")
            : NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "value is '\(value(of: element))', expected '\(expected)'", file: file, line: line)
    }

    /// Flip a SwiftUI Toggle. Tapping the row's middle doesn't, so tap the switch itself.
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    /// Replace a text field's contents: double-tap selects the number already
    /// there (a single tap can leave the cursor before it), then type over it.
    private func replaceText(in field: XCUIElement, with text: String) {
        field.doubleTap()
        field.typeText(text)
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        waitFor(tab)
        tab.tap()
    }

    // MARK: Schedule

    func testSkipADayFromItsOptions() {
        showList()
        let tuesday = day("2026-10-13")
        waitFor(tuesday)
        expectValue(tuesday, "")

        tuesday.tap()
        let skip = app.switches["Skip this day"]
        waitFor(skip)
        flip(skip)
        app.buttons["Done"].tap()

        expectValue(tuesday, "Skipped")
    }

    func testSwipeToSkipAndBack() {
        showList()
        let thursday = day("2026-10-15")
        waitFor(thursday)

        thursday.swipeRight()
        let skip = app.buttons["Skip"]
        waitFor(skip)
        skip.tap()
        expectValue(thursday, "Skipped")

        thursday.swipeRight()
        let unskip = app.buttons["Don't skip"]
        waitFor(unskip)
        unskip.tap()
        expectValue(thursday, "")
    }

    func testOverrideADaysCoffee() {
        showList()
        let tuesday = day("2026-10-13")
        waitFor(tuesday)
        tuesday.tap()

        let total = app.textFields.firstMatch
        waitFor(total)
        replaceText(in: total, with: "70")
        app.buttons["Set override"].tap()

        expectValue(tuesday, "70g day")

        // Clearing it takes the day back to normal
        tuesday.tap()
        let clear = app.buttons["Clear override"]
        waitFor(clear)
        clear.tap()
        expectValue(tuesday, "")
    }

    func testMonthViewStepsBetweenMonthsAndOpensADay() {
        // The month grid is the layout the schedule opens on
        waitFor(app.staticTexts["October 2026"])

        app.buttons["Next month"].tap()
        waitFor(app.staticTexts["November 2026"])
        app.buttons["Previous month"].tap()
        waitFor(app.staticTexts["October 2026"])

        let tuesday = app.buttons["month-day-2026-10-13"]
        waitFor(tuesday)
        tuesday.tap()
        waitFor(app.switches["Skip this day"])
    }

    // MARK: Beans

    func testFreezeABagFromTheList() {
        openTab("Beans")
        let kenya = element(containing: "Gichathaini AA")
        waitFor(kenya)

        kenya.swipeLeft()
        let freeze = app.buttons["Freeze"]
        waitFor(freeze)
        freeze.tap()
        let confirm = app.buttons["Freeze today"]
        waitFor(confirm)
        confirm.tap()

        // A frozen bag with no planned thaw says so in the Frozen section
        waitFor(element(containing: "No thaw date"))
    }

    func testThawABagFromItsDetailScreen() {
        openTab("Beans")
        let gesha = element(containing: "Janson Gesha")
        waitFor(gesha)
        gesha.tap()
        waitFor(app.navigationBars["Janson Gesha"])

        let thaw = app.buttons["Thaw bag"]
        for _ in 0..<4 where !thaw.isHittable { app.swipeUp() }
        thaw.tap()
        let confirm = app.buttons["Thaw today"]
        waitFor(confirm)
        confirm.tap()

        // The freezer history now ends with a thaw, and the button offers a freeze
        waitFor(element(containing: "Thawed"))
        waitFor(app.buttons["Freeze bag"])
    }

    func testEditABagsRestDays() {
        openTab("Beans")
        let kenya = element(containing: "Gichathaini AA")
        waitFor(kenya)
        kenya.tap()

        let edit = app.buttons["Edit"]
        waitFor(edit)
        edit.tap()

        let restDays = app.textFields.firstMatch
        waitFor(restDays)
        restDays.tap()
        restDays.typeText("21")
        app.buttons["Save"].tap()

        waitFor(element(containing: "21 d"))
    }

    // MARK: Settings

    func testAddARoasterDefault() {
        openTab("Settings")
        let add = app.buttons["Add a roaster"]
        waitFor(add)
        XCTAssertFalse(element(containing: "Square Mile").exists)

        add.tap()
        let squareMile = app.buttons["Square Mile"]
        waitFor(squareMile)
        squareMile.tap()

        // Back in Settings, the roaster has its own row at the default rest
        waitFor(app.buttons["More rest days for Square Mile"])
    }
}
