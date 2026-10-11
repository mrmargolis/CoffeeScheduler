import CoffeeCore
import SwiftUI

extension Color {
    /// A colour from "#rrggbb".
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

extension AppModel {
    /// A roaster's rail colour: the schedule's collision-free assignment, or
    /// its hashed colour for a roaster not in the schedule.
    func rail(_ roaster: String) -> Color {
        Color(hex: (roasterColors[roaster] ?? RoasterColor.forRoaster(roaster)).border)
    }
}

/// The thin roaster-coloured bar beside a bag, as in the web app.
struct RoasterRail: View {
    let color: Color
    var width: CGFloat = 3
    var height: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(color)
            .frame(width: width, height: height)
    }
}
