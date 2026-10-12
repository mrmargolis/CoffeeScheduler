// The one piece of SwiftUI in this package, so it is left out on Linux. The
// app and the widget are separate targets that both import CoffeeCore and
// nothing else of each other's, which makes this the place for what the two
// must draw alike.
#if canImport(SwiftUI)
    import SwiftUI

    /// The colours the app and its widget share. The app's `Theme` adds the
    /// ones only it uses.
    public enum Palette {
        /// Screen and widget background.
        public static let ground = Color(hex: "#15110D")
        /// The line over each week of the month grid: a step lighter than a
        /// hairline, which is hard to see across the full width of the grid.
        public static let weekLine = Color(hex: "#5E4E3B")
        public static let text = Color(hex: "#F4ECDD")
        public static let text2 = Color(hex: "#BBAA92")
        /// Section labels.
        public static let text3 = Color(hex: "#94836C")
        /// Dates outside the month and dashed outlines.
        public static let dim = Color(hex: "#6E5F4C")
        /// Gold: the selected tab, today, links and early-start notes.
        public static let accent = Color(hex: "#E0AA45")
        public static let gap = Color(hex: "#E5766A")
        public static let gapText = Color(hex: "#F0A096")
    }

    extension Color {
        /// A colour from "#rrggbb".
        public init(hex: String) {
            let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
            self.init(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255
            )
        }
    }
#endif
