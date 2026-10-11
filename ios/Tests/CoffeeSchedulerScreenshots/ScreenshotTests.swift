import CoffeeCore
import SwiftUI
import UIKit
import XCTest
@testable import CoffeeScheduler

/// Renders each screen over `SampleData` in light and dark mode and writes
/// PNGs to `$SCREENSHOT_DIR/screenshots` (CI uploads them as an artifact).
/// Run on an iOS Simulator: `xcodebuild test` with an iPhone destination.
/// Pass the directory as TEST_RUNNER_SCREENSHOT_DIR; xcodebuild strips the
/// prefix for the test process.
@MainActor
final class ScreenshotTests: XCTestCase {
    /// iPhone 16/17 screen, in points.
    static let screenSize = CGSize(width: 393, height: 852)

    func testScreenshots() throws {
        let base = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
        let outDir = URL(fileURLWithPath: base).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let model = AppModel(store: try SampleData.store(), today: SampleData.today, folderName: "Coffee")
        XCTAssertNil(model.message, "Sample data failed to load: \(model.message?.body ?? "")")
        let kenya = try XCTUnwrap(model.detail(forBean: "kenya")?.bean)
        let gesha = try XCTUnwrap(model.detail(forBean: "gesha")?.bean)

        // The same data with the queue dragged into a manual order
        let reorderedStore = try SampleData.store()
        try reorderedStore.reorderQueue(["kenya", "guji", "huila"])
        let reordered = AppModel(store: reorderedStore, today: SampleData.today, folderName: "Coffee")

        // Screens are captured without the tab bar: inside a TabView the
        // list screens render blank in this offscreen capture, though they
        // show fine in the app.
        let screens: [(String, AnyView, AppModel)] = [
            ("1-schedule", AnyView(ScheduleView()), model),
            ("2-beans", AnyView(BeansView()), model),
            ("3-detail-in-progress", AnyView(NavigationStack { BeanDetailView(beanID: "guji") }), model),
            ("4-detail-resting", AnyView(NavigationStack { BeanDetailView(beanID: "huila") }), model),
            ("5-detail-frozen", AnyView(NavigationStack { BeanDetailView(beanID: "gesha") }), model),
            ("6-settings", AnyView(SettingsView()), model),
            ("7-edit-bag", AnyView(NavigationStack { BeanSettingsForm(bean: kenya, today: SampleData.today) }), model),
            ("8-edit-frozen-bag", AnyView(NavigationStack { BeanSettingsForm(bean: gesha, today: SampleData.today) }), model),
            ("9-reorder-queue", AnyView(BeansView().environment(\.editMode, .constant(.active))), reordered),
            ("10-day-options", AnyView(NavigationStack { DayOptionsSheet(date: "2026-10-17") }), model),
            ("11-day-override", AnyView(NavigationStack { DayOptionsSheet(date: "2026-10-14") }), model),
        ]

        for (name, view, model) in screens {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let image = render(view.environment(model), style: style)
                let file = "\(name)-\(style == .dark ? "dark" : "light").png"
                try XCTUnwrap(image.pngData()).write(to: outDir.appendingPathComponent(file))

                let attachment = XCTAttachment(image: image)
                attachment.name = file
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
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
