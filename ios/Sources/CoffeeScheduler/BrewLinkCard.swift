import CoffeeCore
import SwiftUI

/// The BeanConqueror brew an evaluation describes: where what it recorded
/// differs from the recipe typed, with a button to take it, and a menu to
/// link another of the bag's brews from around then, or none.
struct BrewLinkCard: View {
    @Binding var evaluation: CupEvaluation
    /// The bag's brews around the cup, newest first, with the linked one.
    let brews: [LoggedBrew]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("BeanConqueror brew").font(.subheadline.weight(.semibold))
                Spacer()
                menu
            }
            Text(status).font(.footnote).foregroundStyle(Theme.text2)
            if let brew = linked {
                let differences = evaluation.recipe.brew.differences(from: brew.recipe)
                if differences.isEmpty {
                    Text("Matches the recipe above.").font(.footnote).foregroundStyle(Theme.text3)
                } else {
                    ForEach(differences, id: \.field) { difference in
                        Text("\(difference.field): \(difference.typed ?? "not entered") here, \(difference.imported) in BeanConqueror")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    }
                    Button("Use imported recipe") {
                        evaluation.recipe.brew = evaluation.recipe.brew.usingImported(brew.recipe)
                    }
                    .font(.footnote.weight(.semibold))
                    .accessibilityHint("Takes what BeanConqueror recorded into this cup's recipe when you save")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
    }

    private var linked: LoggedBrew? {
        brews.first { $0.id == evaluation.brewID }
    }

    private var status: String {
        if let linked {
            return "Brewed \(Self.time(linked)), linked \(evaluation.linkedByHand ? "by hand" : "automatically")."
        }
        if evaluation.linkedByHand { return "Not linked to a brew." }
        return evaluation.brewID == nil
            ? "Links to the bag's last brew before this cup, within 3 hours, once it's imported."
            : "Links automatically when you save."
    }

    private var menu: some View {
        Menu("Change") {
            Button("Link automatically") {
                evaluation.brewID = nil
                evaluation.linkedByHand = false
            }
            Section("Brews around then") {
                ForEach(brews) { brew in
                    Button {
                        evaluation.brewID = brew.id
                        evaluation.linkedByHand = true
                    } label: {
                        if brew.id == evaluation.brewID {
                            Label(Self.label(brew), systemImage: "checkmark")
                        } else {
                            Text(Self.label(brew))
                        }
                    }
                }
            }
            Button("Don't link", role: .destructive) {
                evaluation.brewID = nil
                evaluation.linkedByHand = true
            }
        }
        .font(.footnote.weight(.semibold))
        .accessibilityHint("Links this cup to another brew, or to none")
    }

    /// "Thu 1 Feb 8:02 · 1.6 · 93 °C"
    private static func label(_ brew: LoggedBrew) -> String {
        let date = Date(timeIntervalSince1970: brew.timestamp).formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
        let parts = [brew.recipe.grindSetting, brew.recipe.temperatureC.map { "\(BrewRecipe.number($0)) °C" }].compactMap { $0 }
        return ([date] + parts).joined(separator: " · ")
    }

    private static func time(_ brew: LoggedBrew) -> String {
        Date(timeIntervalSince1970: brew.timestamp).formatted(date: .omitted, time: .shortened)
    }
}
