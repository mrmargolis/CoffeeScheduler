import CoffeeCore
import SwiftUI

extension AppModel {
    /// A roaster's rail colour: the schedule's collision-free assignment, or
    /// its hashed colour for a roaster not in the schedule.
    func rail(_ roaster: String) -> Color {
        Color(hex: (roasterColors[roaster] ?? RoasterColor.forRoaster(roaster)).border)
    }
}

/// The thin roaster-coloured bar beside a bag.
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
