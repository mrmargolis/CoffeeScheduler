import CoffeeCore
import SwiftUI

/// A break as the Edit screen holds it: the grams may be cleared while typing.
struct EditableBreak: Identifiable {
    let id = UUID()
    var afterGrams: Double?
    var resumeDate: Date

    init(afterGrams: Double?, resumeDate: Date) {
        self.afterGrams = afterGrams
        self.resumeDate = resumeDate
    }

    init(_ pause: BagBreak) {
        self.init(afterGrams: pause.afterGrams, resumeDate: Format.date(pause.resumeDate))
    }

    /// Nil until it has an amount.
    var saved: BagBreak? {
        afterGrams.map { BagBreak(afterGrams: $0, resumeDate: Format.iso(resumeDate)) }
    }
}

/// The bag's planned breaks on the Edit screen, a card each, and a button to
/// add one: it starts at what's been drunk so far, so the break starts today.
struct BagBreaksSection: View {
    let bean: Bean
    let today: String
    @Binding var breaks: [EditableBreak]

    var body: some View {
        ForEach($breaks) { $pause in
            Section {
                LabeledContent("Break after") {
                    HStack(spacing: 4) {
                        TextField("Grams", value: $pause.afterGrams, format: .number, prompt: Text("e.g. 150"))
                            .numberEntry()
                        Text("g used").foregroundStyle(.secondary)
                    }
                }
                DatePicker("Back on", selection: $pause.resumeDate, in: Format.date(DateUtils.addDays(today, 1))..., displayedComponents: .date)
                Button("Remove break", role: .destructive) { breaks.removeAll { $0.id == pause.id } }
            } header: {
                SectionLabel(title: breaks.count == 1 ? "Break" : "Break \((breaks.firstIndex { $0.id == pause.id } ?? 0) + 1)")
                    .listRowInsets(Theme.labelInsets)
            } footer: {
                Text(note(pause))
            }
        }
        Section {
            Button("Add a break", systemImage: "pause.circle", action: add)
        } footer: {
            Text(
                """
                Drink the bag down to an amount, set it aside without freezing it, and come back to it on a day. \
                Other bags fill in meanwhile. \(Format.grams(used)) g of \(Format.grams(bean.weightGrams)) g used so far.
                """)
        }
    }

    private var used: Double { max(0, bean.totalBrewedGrams).rounded() }

    /// "Keeps 100 g for then. Back at day 72."
    private func note(_ pause: EditableBreak) -> String {
        var parts: [String] = []
        if let grams = pause.afterGrams, grams > 0, grams < bean.weightGrams {
            parts.append("Keeps \(Format.grams(bean.weightGrams - grams)) g for then.")
        }
        if let age = effectiveAge(roastDate: bean.roastDate, asOf: Format.iso(pause.resumeDate), frozenDays: bean.frozenDays) {
            parts.append("Back at day \(age).")
        }
        return parts.joined(separator: " ")
    }

    /// From what's been drunk, or halfway through what's left after the last
    /// break; back a fortnight after today or the last break.
    private func add() {
        let last = breaks.last
        let base = max(last?.afterGrams ?? 0, used)
        let grams = last == nil && used > 0 ? used : base + (bean.weightGrams - base) / 2
        let from = last.map { Format.iso($0.resumeDate) } ?? today
        breaks.append(EditableBreak(afterGrams: (grams / 5).rounded() * 5, resumeDate: Format.date(DateUtils.addDays(from, 14))))
    }
}
