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

        let screens: [(String, AnyView)] = [
            ("1-schedule", AnyView(RootView(tab: .schedule))),
            ("2-beans", AnyView(RootView(tab: .beans))),
            ("3-detail-in-progress", AnyView(NavigationStack { BeanDetailView(beanID: "guji") })),
            ("4-detail-resting", AnyView(NavigationStack { BeanDetailView(beanID: "huila") })),
            ("5-detail-frozen", AnyView(NavigationStack { BeanDetailView(beanID: "gesha") })),
            ("6-settings", AnyView(RootView(tab: .settings))),
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
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // Give SwiftUI a few run loop turns to lay out and fill its lists.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        window.layoutIfNeeded()

        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}
