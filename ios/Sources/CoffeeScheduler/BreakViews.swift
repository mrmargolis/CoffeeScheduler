import CoffeeCore
import SwiftUI

/// The rest of a bag after a break, at its own place in the queue: drag it
/// to choose when the bag comes back.
struct RestCard: View {
    @Environment(AppModel.self) private var model
    let part: QueuePart<Bean>

    private var bean: Bean { part.bean }
    private var run: BagRun? { model.partRuns[part.id] }

    var body: some View {
        let color = model.rail(part.bean.roaster)
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius)
        HStack(spacing: 12) {
            RestTile(order: part.displayOrder, color: color)
            BagTitle(name: bean.name, subtitle: subtitle)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(run.map { "Back \(Format.shortDay($0.start))" } ?? "Not scheduled")
                    .font(.subheadline.bold())
                if let age { Text(age).font(.caption).foregroundStyle(Theme.text2) }
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.45), in: shape)
        .overlay(shape.strokeBorder(color.opacity(0.7), style: Theme.dash))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("The rest of the bag after its break. Drag it in Reorder to change when it comes back.")
    }

    /// "Rest after 150 g · 100 g", or for one before another break, "After 150 g · 50 g".
    private var subtitle: String {
        let grams = Format.grams((bean.weightGrams - part.floorGrams - part.startGrams).rounded())
        return "\(part.until == nil ? "Rest after" : "After") \(Format.grams(part.startGrams)) g · \(grams) g"
    }

    /// "at day 72", or "day 72–80" across the rest's run.
    private var age: String? {
        guard let run, let ages = bean.ageRange(start: run.start, finish: run.end, today: model.today) else { return nil }
        return ages.start == ages.finish ? "at day \(ages.start)" : "day \(ages.start)–\(ages.finish)"
    }
}

/// A rest's square: its number when the queue is ordered by hand, a pause
/// sign otherwise, dashed in its roaster's colour.
private struct RestTile: View {
    let order: Int?
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        ZStack {
            shape.strokeBorder(color, style: Theme.dash)
            if let order {
                Text("\(order)").font(.callout.bold()).monospacedDigit().accessibilityLabel("Position \(order)")
            } else {
                Image(systemName: "pause.fill").font(.caption.weight(.bold)).foregroundStyle(color)
            }
        }
        .frame(width: 36, height: 36)
    }
}

/// A break being taken or moved, for the dialog asking how much to drink first.
struct BreakDraft: Identifiable {
    let id = UUID()
    let bean: Bean
    /// The break being moved; nil for a new one.
    let breakID: Int?
    /// Where it starts out: grams used from the full bag.
    let grams: Double

    /// A new break: from what's been drunk, so it's from now, or halfway
    /// through what's left after the bag's last break.
    static func new(for bean: Bean) -> BreakDraft {
        let used = max(0, bean.totalBrewedGrams)
        let last = bean.breaks.last?.afterGrams ?? 0
        let base = max(last, used)
        let grams = used > last ? used : base + (bean.weightGrams - base) / 2
        let rounded = min(max(5, (grams / 5).rounded() * 5), bean.weightGrams - 5)
        return BreakDraft(bean: bean, breakID: nil, grams: rounded)
    }

    static func moving(_ part: QueuePart<Bean>) -> BreakDraft? {
        part.after.map { BreakDraft(bean: part.bean, breakID: $0.id, grams: $0.afterGrams) }
    }
}

extension View {
    /// Asks how much of the bag to drink before the break, and saves it.
    func breakDialog(_ draft: Binding<BreakDraft?>) -> some View {
        modifier(BreakDialog(draft: draft))
    }
}

private struct BreakDialog: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var draft: BreakDraft?
    @State private var grams = ""

    func body(content: Content) -> some View {
        let shown = Binding {
            draft != nil
        } set: {
            if !$0 { draft = nil }
        }
        content
            .alert(draft?.breakID == nil ? "Take a break" : "Move the break", isPresented: shown, presenting: draft) { draft in
                TextField("Grams", text: $grams).keyboardType(.decimalPad)
                Button("Save") { save(draft) }
                Button("Cancel", role: .cancel) {}
            } message: { draft in
                Text(message(draft))
            }
            .onChange(of: draft?.id, initial: true) {
                grams = draft.map { Format.grams($0.grams) } ?? ""
            }
    }

    private func message(_ draft: BreakDraft) -> String {
        let bean = draft.bean
        let used = "\(Format.grams(max(0, bean.totalBrewedGrams).rounded())) g of its \(Format.grams(bean.weightGrams)) g used so far."
        if draft.breakID != nil {
            return "Break \(bean.name) after how many grams? \(used) The rest keeps its place in the queue."
        }
        return """
            Drink \(bean.name) to how many grams? \(used) The rest of the bag waits after the next one in the queue: \
            drag it in Reorder to change when it comes back.
            """
    }

    private func save(_ draft: BreakDraft) {
        guard let value = Double(grams.replacingOccurrences(of: ",", with: ".")) else {
            model.message = AppModel.Message(title: "Couldn't save the break", body: "\(grams) isn't a number of grams.")
            return
        }
        model.saveBreak(beanID: draft.bean.id, id: draft.breakID, afterGrams: value)
    }
}
