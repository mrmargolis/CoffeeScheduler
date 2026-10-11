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

        // Screens are captured without the tab bar: inside a TabView the
        // list screens render blank in this offscreen capture, though they
        // show fine in the app.
        let screens: [(String, AnyView)] = [
            ("1-schedule", AnyView(ScheduleView())),
            ("2-beans", AnyView(BeansView())),
            ("3-detail-in-progress", AnyView(NavigationStack { BeanDetailView(beanID: "guji") })),
            ("4-detail-resting", AnyView(NavigationStack { BeanDetailView(beanID: "huila") })),
            ("5-detail-frozen", AnyView(NavigationStack { BeanDetailView(beanID: "gesha") })),
            ("6-settings", AnyView(SettingsView())),
        ]

        for (name, view) in screens {
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
