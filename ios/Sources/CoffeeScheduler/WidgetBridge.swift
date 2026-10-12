import CoffeeCore
import Foundation
import WidgetKit
import os

/// Hands the schedule to the home screen widget.
enum WidgetBridge {
    /// Write the snapshot into the App Group container and ask the widget
    /// to redraw. Does nothing when the app was signed without the group.
    static func publish(_ snapshot: WidgetSnapshot) {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) else {
            Log.widget.debug("No App Group container: the app was signed without the group")
            return
        }
        do {
            try snapshot.encoded().write(to: folder.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
        } catch {
            Log.widget.error("Couldn't write the widget's snapshot: \(String(describing: error), privacy: .public)")
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
