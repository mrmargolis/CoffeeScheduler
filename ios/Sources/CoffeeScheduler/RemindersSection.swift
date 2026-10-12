import CoffeeCore
import SwiftUI

/// Settings' switches for the reminders. Turning the first one on asks for
/// permission to send notifications.
struct RemindersSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Reminder.Kind.thaw.defaultsKey) private var thaw = false
    @AppStorage(Reminder.Kind.newBag.defaultsKey) private var newBag = false
    @AppStorage(Reminder.Kind.buy.defaultsKey) private var buy = false

    var body: some View {
        Section {
            row("Thaw a bag", "On its planned thaw date", isOn: $thaw)
            row("New bag", "The day an unopened bag starts", isOn: $newBag)
            row("Buy coffee", "The last day a new bag would be rested in time", isOn: $buy)
        } header: {
            SectionLabel(title: "Reminders").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    Sent at \(ReminderScheduler.hour) in the morning, on this device, \
                    from the schedule as it was when the app was last open.
                    """)
        }
    }

    private func row(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        // Acts on the switch itself: a modifier on the section would run once per row
        let flipped = Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                Task { await changed(turnedOn: newValue) }
            }
        )
        return Toggle(isOn: flipped) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Theme.text2).lineLimit(2)
            }
        }
        .frame(minHeight: 48)
    }

    private func changed(turnedOn: Bool) async {
        if turnedOn, await !ReminderScheduler.requestPermission() {
            thaw = false
            newBag = false
            buy = false
            model.message = AppModel.Message(
                title: "Notifications are off",
                body: "Allow notifications for Coffee Scheduler in the Settings app, then turn the reminder on again."
            )
            return
        }
        model.scheduleReminders()
    }
}
