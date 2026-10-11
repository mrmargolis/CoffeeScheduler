import CoffeeCore
import Foundation
import WidgetKit

/// Hands the schedule to the home screen widget.
enum WidgetBridge {
    /// Write the snapshot into the App Group container and ask the widget
    /// to redraw. Does nothing when the app was signed without the group.
    static func publish(_ snapshot: WidgetSnapshot) {
        guard
            let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup),
            let data = try? snapshot.encoded()
        else { return }
        try? data.write(to: folder.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
