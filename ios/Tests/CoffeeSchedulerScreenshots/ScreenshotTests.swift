import CoffeeCore
import SwiftUI
import UIKit
import XCTest

@testable import CoffeeScheduler

/// Renders each screen over `SampleData` and writes PNGs to `$SCREENSHOT_DIR/screenshots` (CI uploads them as an artifact).
/// Run on an iOS Simulator: `xcodebuild test` with an iPhone destination.
/// Pass the directory as TEST_RUNNER_SCREENSHOT_DIR; xcodebuild strips the
/// prefix for the test process.
@MainActor
final class ScreenshotTests: XCTestCase {
    /// iPhone 16/17 screen, in points.
    static let screenSize = CGSize(width: 393, height: 852)

    private func outputDirectory() throws -> URL {
        let base = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
        let outDir = URL(fileURLWithPath: base).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        return outDir
    }

    /// The pictures the share buttons send, as they'd arrive: the month, a
    /// day with its own amount, and a skipped day.
    func testSharedPictures() throws {
        let outDir = try outputDirectory()
        let model = AppModel(store: try SampleData.store(), today: SampleData.today, folderName: "Coffee")
        let pictures: [(String, ScheduleSnapshot.Subject)] = [
            ("14-share-month", .month("2026-10-01")),
            ("14-share-month-bags", .bags("2026-10-01")),
            ("15-share-day", .day("2026-10-14")),
            ("16-share-skipped-day", .day("2026-10-17")),
        ]

        for (name, subject) in pictures {
            let data = try ScheduleSnapshot(subject, model: model).png()
            let image = try XCTUnwrap(UIImage(data: data))
            // Drawn at 3x, and tall enough to hold more than its heading
            XCTAssertGreaterThan(image.size.width, 1000, name)
            XCTAssertGreaterThan(image.size.height, 400, name)
            // 3 wide by 4 tall, to post to Instagram as it is
            XCTAssertEqual(image.size.width * 4, image.size.height * 3, name)
            try data.write(to: outDir.appendingPathComponent("\(name).png"))

            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name).png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// The picture the Beans screen's share button sends.
    func testSharedBeans() throws {
        let model = AppModel(store: try SampleData.store(), today: SampleData.today, folderName: "Coffee")
        let data = try BeansSnapshot(model: model).png()
        let image = try XCTUnwrap(UIImage(data: data))
        // Drawn at 3x, and at least as tall as a 4:5 post
        XCTAssertGreaterThan(image.size.width, 1000)
        XCTAssertGreaterThanOrEqual(image.size.height, image.size.width * 5 / 4)
        try data.write(to: try outputDirectory().appendingPathComponent("17-share-beans.png"))

        let attachment = XCTAttachment(image: image)
        attachment.name = "17-share-beans.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScreenshots() throws {
        let model = AppModel(store: try SampleData.store(), today: SampleData.today, folderName: "Coffee")
        XCTAssertNil(model.message, "Sample data failed to load: \(model.message?.body ?? "")")
        let kenya = try XCTUnwrap(model.detail(forBean: "kenya")?.bean)
        let gesha = try XCTUnwrap(model.detail(forBean: "gesha")?.bean)

        // The same data with the queue dragged into a manual order
        let reorderedStore = try SampleData.store()
        try reorderedStore.reorderQueue(["kenya", "guji", "huila"])
        let reordered = AppModel(store: reorderedStore, today: SampleData.today, folderName: "Coffee")

        // The same data with a break in La Esperanza, its rest after the next bag
        let breakStore = try SampleData.store()
        try breakStore.addBreak(beanID: "huila", afterGrams: 100)
        let withBreak = AppModel(store: breakStore, today: SampleData.today, folderName: "Coffee")

        // Screens are captured without the tab bar: inside a TabView the
        // list screens render blank in this offscreen capture, though they
        // show fine in the app.
        let screens: [(String, AnyView, AppModel)] = [
            ("1-schedule", AnyView(ScheduleView(layout: .list)), model),
            ("2-beans", AnyView(BeansView()), model),
            ("3-detail-in-progress", AnyView(NavigationStack { BeanDetailView(beanID: "guji") }), model),
            ("4-detail-resting", AnyView(NavigationStack { BeanDetailView(beanID: "huila") }), model),
            ("5-detail-frozen", AnyView(NavigationStack { BeanDetailView(beanID: "gesha") }), model),
            ("6-settings", AnyView(SettingsView()), model),
            ("7-edit-bag", AnyView(NavigationStack { BeanSettingsForm(bean: kenya, today: SampleData.today) }), model),
            ("8-edit-frozen-bag", AnyView(NavigationStack { BeanSettingsForm(bean: gesha, today: SampleData.today) }), model),
            ("9-reorder-queue", AnyView(BeansView(reordering: true)), reordered),
            ("10-day-options", AnyView(NavigationStack { DayOptionsSheet(date: "2026-10-17") }), model),
            ("11-day-override", AnyView(NavigationStack { DayOptionsSheet(date: "2026-10-14") }), model),
            ("12-month", AnyView(ScheduleView(layout: .month)), model),
            ("13-skip-days", AnyView(NavigationStack { SkipRangeForm(range: model.skipRanges.first, today: SampleData.today) }), model),
            ("14-add-bag", AnyView(AddBagView()), model),
            ("15-add-bag-photos", AnyView(AddBagView(intake: AddBagSamples.photos(), showsOrigin: false)), model),
            ("16-add-bag-page", AnyView(AddBagView(intake: AddBagSamples.photosAndPage())), model),
            ("18-add-bag-pick-text", AnyView(AddBagSamples.picker()), model),
            ("19-beans-break", AnyView(BeansView()), withBreak),
            ("20-detail-break", AnyView(NavigationStack { BeanDetailView(beanID: "huila") }), withBreak),
        ]
        try capture(screens)
    }

    /// The Guji's dial-in history and the evaluation sheet, folded and open.
    func testDialInScreenshots() throws {
        let model = AppModel(store: try SampleData.store(), today: SampleData.today, folderName: "Coffee")
        let rated = ratedCup(model)
        let dialed = try dialedIn()
        let roasterStart = try roasterStartingPoint()
        let form = { (recipe: Bool, tags: Bool) in
            AnyView(NavigationStack { CupEvaluationForm(evaluation: rated, isNew: true, editsRecipe: recipe, editsTags: tags) })
        }
        try capture([
            ("21-dial-in", AnyView(dialIn(model)), model),
            ("22-evaluate-cup", form(false, false), model),
            ("23-evaluate-cup-recipe", form(true, false), model),
            ("24-evaluate-cup-tags", form(false, true), model),
            ("25-dial-in-settings", AnyView(NavigationStack { DialInSettingsView() }), model),
            ("26-dial-in-advice", AnyView(advice(model)), model),
            ("27-dial-in-dialed-in", AnyView(dialIn(dialed)), dialed),
            ("28-evaluation-brew-link", AnyView(brewLink(model)), model),
            ("29-dial-in-roaster-start", AnyView(dialIn(roasterStart, bean: "kenya")), roasterStart),
        ])
    }

    /// Render each screen and write it to the output directory.
    private func capture(_ screens: [(String, AnyView, AppModel)]) throws {
        let outDir = try outputDirectory()
        for (name, view, model) in screens {
            // The app is dark only, so the screens are too
            let image = render(view.environment(model).coffeeTheme(), style: .dark)
            let file = "\(name).png"
            try XCTUnwrap(image.pngData()).write(to: outDir.appendingPathComponent(file))

            let attachment = XCTAttachment(image: image)
            attachment.name = file
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// A cup part rated, from the Guji's current recipe.
    private func ratedCup(_ model: AppModel) -> CupEvaluation {
        var rated = model.newEvaluation(forBean: "guji")
        rated.ratings = [.acidity: 0, .sweetness: -1, .intensity: -1, .finish: -1]
        rated.verdict = .same
        rated.drawdown = .normal
        rated.character = [.sharp: .user]
        rated.flavours = ["Blueberry"]
        return rated
    }

    /// The second Guji cup's link to its brew, which recorded a step finer
    /// than typed.
    private func brewLink(_ model: AppModel) -> some View {
        let cup = model.evaluations(forBean: "guji").first { $0.id == "sample-2" } ?? ratedCup(model)
        return VStack {
            BrewLinkCard(evaluation: .constant(cup), brews: model.brews(near: cup))
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.ground)
    }

    /// The sample data with the archived Brazil dialed in, for the Kenya
    /// from the same roaster to start from.
    private func roasterStartingPoint() throws -> AppModel {
        let store = try SampleData.store()
        var cup = try XCTUnwrap(store.evaluations(beanID: "guji").first)
        cup.id = "brazil-1"
        cup.beanID = "brazil"
        cup.verdict = .dialedIn
        try store.saveEvaluation(cup)
        return AppModel(store: store, today: SampleData.today, folderName: "Coffee")
    }

    /// The sample data with a third Guji cup marked dialed in.
    private func dialedIn() throws -> AppModel {
        let store = try SampleData.store()
        var cup = try XCTUnwrap(store.evaluations(beanID: "guji").first)
        cup.id = "sample-3"
        cup.timestamp += 86_400
        cup.date = "2026-10-12"
        cup.ratings = [.acidity: 0, .sweetness: 0, .clarity: 0, .body: 0, .finish: 0]
        cup.verdict = .dialedIn
        try store.saveEvaluation(cup)
        return AppModel(store: store, today: SampleData.today, folderName: "Coffee")
    }

    /// What the advisor says about a cup with a slow drawdown and a short finish.
    private func advice(_ model: AppModel) -> some View {
        var cup = model.newEvaluation(forBean: "guji")
        cup.ratings = [.acidity: 0, .sweetness: -1, .clarity: 0, .finish: -2]
        cup.drawdown = .slow
        return ScrollView {
            DialInAdviceView(evaluation: cup, advice: model.advice(for: cup)).padding(20)
        }
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
    }

    /// The Guji's dial-in section on its own: on the bag's screen it's
    /// below the fold.
    private func dialIn(_ model: AppModel, bean: String = "guji") -> some View {
        ScrollView {
            DialInSection(
                evaluations: model.evaluations(forBean: bean), experiments: model.experiments(forBean: bean),
                dialedIn: model.dialedInCup(forBean: bean), startingPoint: model.roasterStartingPoint(forBean: bean), start: {},
                edit: { _ in }
            )
            .padding(20)
        }
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
    }

    private func render(_ view: some View, style: UIUserInterfaceStyle) -> UIImage {
        // A window attached to the simulator's scene, when the test host has
        // one, gets the same traits and safe areas as a real app window.
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: Self.screenSize)
        window.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // Give SwiftUI and UIKit several run loop turns to lay out, fill
        // lists and finish any appearance animations.
        for _ in 0..<6 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            window.layoutIfNeeded()
        }

        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}
