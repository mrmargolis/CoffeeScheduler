import CoffeeCore
import SwiftUI

/// A cup as a diverging bar chart: one row per attribute on the shared
/// −2…+2 scale, a centre line for "ideal", bars out to how far off each
/// attribute is, a green marker for on target and a hollow one for not
/// evaluated.
struct CupChartView: View {
    let ratings: [SensoryAttribute: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Too little")
                Spacer()
                Text("Ideal")
                Spacer()
                Text("Too much")
            }
            .font(.caption2)
            .foregroundStyle(Theme.text3)
            .accessibilityHidden(true)
            ForEach(CupChart.rows(ratings), id: \.attribute) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.attribute.name).foregroundStyle(Theme.text2)
                        Spacer(minLength: 8)
                        Text(row.label).foregroundStyle(color(row.mark))
                    }
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    Track(mark: row.mark)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.attribute.name)
                .accessibilityValue(row.label)
            }
        }
    }

    private func color(_ mark: CupChart.Mark) -> Color {
        switch mark {
        case .unknown: Theme.text3
        case .onTarget: Palette.onTarget
        case .bar: Theme.text
        }
    }
}

/// One attribute's track, drawn from `CupChart`'s geometry.
private struct Track: View {
    let mark: CupChart.Mark

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centre = width * CupChart.centre
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised).frame(height: 8)
                switch mark {
                case .bar(let from, let to):
                    Capsule().fill(Palette.offTarget)
                        .frame(width: max(8, width * (to - from)), height: 8)
                        .offset(x: width * from)
                case .onTarget:
                    Circle().fill(Palette.onTarget).frame(width: 12, height: 12).offset(x: centre - 6)
                case .unknown:
                    Circle().strokeBorder(Palette.notEvaluated, lineWidth: 1.5).frame(width: 12, height: 12).offset(x: centre - 6)
                }
                Rectangle().fill(Theme.text3).frame(width: 1.5, height: 14).offset(x: centre - 0.75)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }
}
