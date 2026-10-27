import CoffeeCore
import SwiftUI

extension BagField {
    /// The field's name on the form.
    var title: String {
        switch self {
        case .coffee: "Coffee"
        case .roaster: "Roaster"
        case .roastDate: "Roasted"
        case .weight: "Weight"
        case .notes: "Tasting notes"
        case .country: "Country"
        case .region: "Region"
        case .producer: "Producer"
        case .variety: "Variety"
        case .process: "Process"
        case .url: "Link"
        }
    }

    /// The fields Next and Previous step through: all but the roast date,
    /// which is a picker.
    static let typed: [BagField] = allCases.filter { $0 != .roastDate }
}

/// A field's name, with a gold dot when the last photo or page just changed
/// it and, under it, a badge when its value is a guess. It keeps its width;
/// the value beside it gives way.
struct BagFieldName: View {
    let field: BagField
    let intake: BagIntake

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if intake.lastFill?.fields.contains(field) == true {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        .accessibilityLabel("Just filled")
                }
                Text(field.title).font(.callout.weight(.semibold)).lineLimit(1)
            }
            if intake.draft.isGuess(field) {
                GuessBadge()
            }
        }
        .fixedSize()
        .padding(.vertical, intake.draft.isGuess(field) ? 4 : 0)
    }
}

/// "GUESS", in a gold capsule.
struct GuessBadge: View {
    var body: some View {
        Text("Guess")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
            .lineLimit(1)
            .fixedSize()
    }
}

/// The camera or globe by a value read from a photo or page.
private struct SourceIcon: View {
    let source: BagSource?

    var body: some View {
        if let source {
            Image(systemName: source.symbol)
                .font(.caption)
                .foregroundStyle(Theme.text3)
                .accessibilityLabel(source.isPhoto ? "From a photo" : "From the page")
        }
    }
}

/// A text field of the bag: its name on the left and its value, editable,
/// on the right, with where it came from and a button to empty it. With
/// the field empty, `accessory` takes the clear button's place.
struct BagTextRow<Accessory: View>: View {
    let field: BagField
    @Bindable var intake: BagIntake
    var focus: FocusState<BagField?>.Binding
    /// Return was pressed: a field that wraps types it as a newline.
    var onReturn: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            BagFieldName(field: field, intake: intake)
            Spacer(minLength: 8)
            SourceIcon(source: intake.fieldSources[field])
            TextField(field.title, text: text, prompt: Text("Empty").foregroundStyle(Theme.text3), axis: .vertical)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.text2)
                .lineLimit(1...3)
                .submitLabel(.next)
                .focused(focus, equals: field)
            if intake.draft.has(field) {
                ClearButton(title: field.title) { intake.type("", in: field) }
            } else {
                accessory
            }
        }
        .frame(minHeight: 48)
        .id(field)
    }

    private var text: Binding<String> {
        Binding {
            field.text.map { intake.draft[keyPath: $0] } ?? ""
        } set: { typed in
            intake.type(typed.filter { !$0.isNewline }, in: field)
            if typed.contains(where: \.isNewline) { onReturn() }
        }
    }
}

/// The roast date and the weight, a row each: a picker once there's a
/// date, and the weight in whole grams, as BeanConqueror keeps it.
struct BagDateWeightRows: View {
    @Bindable var intake: BagIntake
    var focus: FocusState<BagField?>.Binding

    var body: some View {
        date.frame(minHeight: 48).id(BagField.roastDate)
        weight.frame(minHeight: 48).id(BagField.weight)
    }

    private var date: some View {
        HStack(spacing: 6) {
            BagFieldName(field: .roastDate, intake: intake)
            Spacer(minLength: 4)
            if let iso = intake.draft.roastDate {
                DatePicker("Roasted", selection: binding(iso), in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                ClearButton(title: "the roast date") { intake.set(.roastDate, to: nil) }
            } else {
                Button("Add date") { intake.set(.roastDate, to: DateUtils.today()) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var weight: some View {
        HStack(spacing: 4) {
            BagFieldName(field: .weight, intake: intake)
            Spacer(minLength: 4)
            TextField("Weight", text: grams, prompt: Text("Empty").foregroundStyle(Theme.text3))
                .numberEntry(.numberPad)
                .foregroundStyle(Theme.text2)
                .focused(focus, equals: .weight)
            Text("g").foregroundStyle(Theme.text3)
        }
    }

    private var grams: Binding<String> {
        Binding {
            intake.draft.weightGrams.map(String.init) ?? ""
        } set: { typed in
            let digits = typed.filter(\.isNumber)
            intake.set(.weight, to: digits.isEmpty ? nil : digits)
        }
    }

    /// The picker's date: the ISO day's start where the phone is.
    private func binding(_ iso: String) -> Binding<Date> {
        Binding {
            let parts = iso.split(separator: "-").compactMap { Int($0) }
            let components = DateComponents(year: parts.first, month: parts.dropFirst().first, day: parts.last)
            return Calendar.current.date(from: components) ?? Date()
        } set: { picked in
            intake.set(.roastDate, to: DateUtils.isoString(picked))
        }
    }
}

/// A field's button that empties it.
struct ClearButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button("Clear \(title)", systemImage: "xmark.circle.fill", action: action)
            .labelStyle(.iconOnly)
            .foregroundStyle(Theme.text3)
            .buttonStyle(.borderless)
    }
}
