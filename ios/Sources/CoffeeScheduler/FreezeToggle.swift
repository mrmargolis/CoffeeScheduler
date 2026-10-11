import CoffeeCore
import SwiftUI

extension View {
    /// Asks before freezing or thawing `bean` (set it to ask), as the web
    /// app's Freeze/Thaw button does: toggling clears plans that can't be
    /// recovered, so the dialog names them.
    func freezeConfirmation(for bean: Binding<Bean?>) -> some View {
        modifier(FreezeConfirmation(bean: bean))
    }
}

private struct FreezeConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var bean: Bean?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            bean.map { $0.isFrozen ? "Thaw \($0.name)?" : "Freeze \($0.name)?" } ?? "",
            isPresented: Binding(get: { bean != nil }, set: { if !$0 { bean = nil } }),
            titleVisibility: .visible,
            presenting: bean
        ) { bean in
            Button(bean.isFrozen ? "Thaw today" : "Freeze today") {
                model.toggleFreeze(id: bean.id)
            }
        } message: { bean in
            Text(Self.message(for: bean))
        }
    }

    static func message(for bean: Bean) -> String {
        if bean.isFrozen {
            var text = "It goes back into the schedule from today."
            if let thaw = bean.plannedThawDate {
                text += " The planned thaw on \(Format.mediumDay(thaw)) is cleared."
            }
            return text
        }
        var text = "Frozen days don't count toward its age, and it leaves the schedule until it's thawed."
        if bean.freezeAfterGrams != nil {
            text += " The freeze-after target is cleared."
        }
        return text
    }
}

/// Snowflake swipe action for a bag in a list.
struct FreezeSwipeButton: View {
    let bean: Bean
    @Binding var confirming: Bean?

    var body: some View {
        Button {
            confirming = bean
        } label: {
            Label(bean.isFrozen ? "Thaw" : "Freeze", systemImage: bean.isFrozen ? "sun.max" : "snowflake")
        }
        .tint(bean.isFrozen ? Theme.accent : Theme.frozen)
    }
}
