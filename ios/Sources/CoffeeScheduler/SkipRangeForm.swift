import CoffeeCore
import SwiftUI

/// Which stretch of skipped days the form is showing.
enum SkipRangeRoute: Identifiable, Hashable {
    case new
    case edit(SkipRange)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let range): "edit-\(range.id)"
        }
    }

    var range: SkipRange? {
        if case .edit(let range) = self { return range }
        return nil
    }
}

/// Skip a stretch of days and say what it's for: a new stretch, or one
/// already there to change.
struct SkipRangeForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The stretch being changed; nil for a new one.
    let range: SkipRange?

    @State private var start: Date
    @State private var end: Date
    @State private var reason: String
    @State private var error: String?

    init(range: SkipRange?, today: String) {
        self.range = range
        _start = State(initialValue: Format.date(range?.startDate ?? today))
        _end = State(initialValue: Format.date(range?.endDate ?? today))
        _reason = State(initialValue: range?.reason ?? "")
    }

    var body: some View {
        Form {
            Group {
                Section {
                    DatePicker("First day", selection: $start, displayedComponents: .date)
                    DatePicker("Last day", selection: $end, in: start..., displayedComponents: .date)
                } footer: {
                    Text("No coffee is planned from the first day to the last, so the bags after them are pushed back.")
                }

                Section {
                    TextField("Reason", text: $reason, prompt: Text("e.g. Lisbon"))
                } footer: {
                    Text("Shown in the schedule in place of “Skipped”.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.gapText)
                    }
                }
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
        // Dates are calendar days; pick them in UTC so they can't shift.
        .environment(\.timeZone, Format.utc)
        .onChange(of: start) { _, first in
            if end < first { end = first }
        }
        .navigationTitle(range == nil ? "Skip days" : "Edit skip days")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        error = model.saveSkipRange(replacing: range?.id, start: Format.iso(start), end: Format.iso(end), reason: reason)
        if error == nil { dismiss() }
    }
}

extension AppModel {
    /// What the skip covering `date` is for, when it has a reason.
    func skipReason(on date: String) -> String? {
        let reason = skipRanges.first { $0.startDate <= date && date <= $0.endDate }?.reason
        return reason.flatMap { $0.isEmpty ? nil : $0 }
    }
}
