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

    /// Tap until `shown` appears: on a stalled simulator a tap can be
    /// dropped, and the screen it opens never comes.
    private func tap(_ element: XCUIElement, until shown: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 where !shown.exists {
            if element.isHittable { element.tap() }
            _ = shown.waitForExistence(timeout: 5)
        }
        waitFor(shown, file: file, line: line)
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

    /// Drag a day's row right to show its swipe action. The date itself is
    /// too narrow for `swipeRight()` to travel far enough.
    private func revealSwipeAction(on day: XCUIElement) {
        let start = day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 130, dy: 0)))
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
    private func replaceText(in field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        focus(field, file: file, line: line) { $0.doubleTap() }
        field.typeText(text)
    }

    /// Tap a text field until it has the keyboard. A tap can land while its
    /// screen is still sliding in, and typing into a field without the
    /// keyboard fails the test.
    private func focus(
        _ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line, by tap: (XCUIElement) -> Void = { $0.tap() }
    ) {
        let hasKeyboard = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            if field.isHittable { tap(field) }
            let focused = XCTNSPredicateExpectation(predicate: hasKeyboard, object: field)
            if XCTWaiter().wait(for: [focused], timeout: 3) == .completed { return }
        }
        XCTFail("Never got the keyboard: \(field)", file: file, line: line)
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

        revealSwipeAction(on: thursday)
        let skip = app.buttons["Skip"]
        waitFor(skip)
        skip.tap()
        expectValue(thursday, "Skipped")

        revealSwipeAction(on: thursday)
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
        focus(restDays)
        restDays.typeText("21")
        app.buttons["Save"].tap()

        waitFor(element(containing: "21 d"))
    }

    // MARK: Accessibility

    /// What iOS's accessibility audit is asked to check on each screen: that
    /// VoiceOver has something to say about every element, and says the
    /// right kind of thing. Left out, as choices the design makes: contrast
    /// (dates outside the month and section labels are dim so that they
    /// recede), Dynamic Type and clipping (a cell of the month grid can't
    /// grow, so its text is a fixed size), and hit regions (a date in the
    /// grid is 32 points tall).
    private static let audited: XCUIAccessibilityAuditType = [.sufficientElementDescription, .elementDetection, .trait]

    /// Audits the screen, again if the audit runs out of time: on a slow
    /// CI machine the first one after launch can, every time the test is
    /// retried, while the next one in the same run finishes.
    private func audit(_ screen: String) throws {
        try XCTContext.runActivity(named: "Accessibility audit: \(screen)") { _ in
            for attempt in 1...3 {
                do {
                    try app.performAccessibilityAudit(for: Self.audited)
                    return
                } catch let error as NSError where Self.ranOutOfTime(error) && attempt < 3 {
                    sleep(2)
                }
            }
        }
    }

    /// "Audit failed to complete in time".
    private static func ranOutOfTime(_ error: NSError) -> Bool {
        error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    }

    func testScreensPassTheAccessibilityAudit() throws {
        waitFor(app.staticTexts["October 2026"])
        try audit("month")

        showList()
        waitFor(day("2026-10-13"))
        try audit("week list")

        openTab("Beans")
        let gesha = element(containing: "Janson Gesha")
        waitFor(gesha)
        try audit("beans")

        gesha.tap()
        waitFor(app.navigationBars["Janson Gesha"])
        try audit("bag detail")

        openTab("Settings")
        waitFor(app.buttons["Add a roaster"])
        try audit("settings")
    }

    // MARK: Settings

    func testAddARoasterDefault() {
        openTab("Settings")
        let add = app.buttons["Add a roaster"]
        waitFor(add)
        XCTAssertFalse(element(containing: "Square Mile").exists)

        tap(add, until: app.navigationBars["Add a roaster"])
        let squareMile = app.buttons["Square Mile"]
        waitFor(squareMile)
        squareMile.tap()

        // Back in Settings, the roaster has its own row at the default rest
        waitFor(app.buttons["More rest days for Square Mile"])
    }

    func testAddSkipDaysWithAReason() {
        openTab("Settings")
        let add = app.buttons["Add skip days"]
        waitFor(add)
        add.tap()

        // Both dates start on today; the reason is the form's only text field
        let reason = app.textFields.firstMatch
        waitFor(reason)
        focus(reason)
        reason.typeText("Lisbon")
        app.buttons["Save"].tap()
        waitFor(element(containing: "Lisbon"))

        openTab("Schedule")
        showList()
        let today = day("2026-10-12")
        waitFor(today)
        expectValue(today, "Skipped")
    }
}
