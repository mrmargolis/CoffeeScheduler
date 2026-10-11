import CoffeeCore
import SwiftUI

/// Identifies the day whose options are showing.
struct DayRoute: Identifiable, Hashable {
    let date: String
    var id: String { date }
}

/// Options for one schedule day, opened by tapping its date. Mirrors
/// `src/components/DayOptionsModal.tsx`; for now that's skipping the day.
struct DayOptionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let date: String

    var body: some View {
        // Read from the model so the toggle follows the saved state
        let isSkip = model.schedule.first { $0.date == date }?.isSkip ?? false
        let range = model.skipRanges.first { $0.startDate <= date && date <= $0.endDate }
        Form {
            Section {
                Toggle("Skip this day", isOn: Binding(
                    get: { isSkip },
                    set: { _ in model.toggleSkipDay(date) }
                ))
            } footer: {
                if isSkip, let range, range.startDate != range.endDate {
                    Text("Part of a skip from \(Format.shortDay(range.startDate)) to \(Format.shortDay(range.endDate)). Turning it off here un-skips just this day.")
                } else {
                    Text("For days away from home: no coffee is planned that day, so the bags after it are pushed back a day.")
                }
            }
        }
        .navigationTitle(Format.longDay(date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
