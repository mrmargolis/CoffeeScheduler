import CoffeeCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    // One file importer for the whole screen: SwiftUI mishandles several in one hierarchy.
    @State private var showingImporter = false
    @State private var picking = Picking.export
    private enum Picking { case export, folder }
    @State private var skipForm: SkipRangeRoute?

    var body: some View {
        NavigationStack {
            List {
                ScreenHeader(eyebrow: "Coffee Scheduler", title: "Settings")
                    // Top inset: the section's rounded corner would clip the first line
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                Group {
                    scheduleSection
                    roasterSection
                    skipDaysSection
                    RemindersSection()
                    dataSection
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.hairline)
            }
            .listSectionSpacing(16)
            .contentMargins(.top, 0, for: .scrollContent)
            .themedList()
            .statusBarCover()
            // The title is drawn in the list; this one names the back button
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $skipForm) { route in
                NavigationStack { SkipRangeForm(range: route.range, today: model.today) }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: picking == .folder ? [.folder] : [.zip]
            ) { result in
                guard case .success(let url) = result else { return }
                if picking == .folder {
                    model.chooseFolder(url)
                } else {
                    model.importExport(at: url)
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            SettingRow(title: "Daily coffee", subtitle: "In \(Format.grams(Scheduler.doseSizeGrams)) g doses") {
                StepperWell(
                    text: "\(Format.grams(model.settings.dailyConsumptionGrams)) g", subject: "daily coffee",
                    value: Binding(
                        get: { Int(model.settings.dailyConsumptionGrams) },
                        set: { update(\.dailyConsumptionGrams, to: Double($0)) }
                    ),
                    range: 15...150, step: 5
                )
            }
            SettingRow(title: "Default rest", subtitle: "From roast to first cup") {
                StepperWell(
                    text: "\(model.settings.defaultRestDays) d", subject: "rest days",
                    value: Binding(get: { model.settings.defaultRestDays }, set: { update(\.defaultRestDays, to: $0) }),
                    range: 0...90
                )
            }
        } header: {
            SectionLabel(title: "Schedule").listRowInsets(Theme.labelInsets)
        }
    }

    private var roasterSection: some View {
        Section {
            ForEach(model.roasterDefaults) { entry in
                SettingRow(title: entry.roaster, dot: model.rail(entry.roaster)) {
                    StepperWell(
                        text: "\(entry.restDays) d", subject: "rest days for \(entry.roaster)",
                        value: Binding(get: { entry.restDays }, set: { model.setRoasterRestDays(entry.roaster, $0) }),
                        range: 0...90
                    )
                }
            }
            .onDelete { offsets in
                for roaster in offsets.map({ model.roasterDefaults[$0].roaster }) {
                    model.setRoasterRestDays(roaster, nil)
                }
            }
            let unset = model.roasters.filter { name in !model.roasterDefaults.contains { $0.matches(name) } }
            if !unset.isEmpty {
                // A pushed list, not a Menu: iOS 26 menus can't be
                // reached by UI tests. Picking a roaster adds it at the
                // default rest and comes back here.
                NavigationLink {
                    AddRoasterList(roasters: unset)
                } label: {
                    Label("Add a roaster", systemImage: "plus")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            SectionLabel(title: "Rest by roaster").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    A bag rests for its own days if set, else its roaster's, else the default rest above. \
                    Swipe a roaster to remove it.
                    """)
        }
    }

    private var skipDaysSection: some View {
        Section {
            if model.skipRanges.isEmpty {
                Text("None").foregroundStyle(Theme.text2)
            }
            ForEach(model.skipRanges) { range in
                let dates =
                    range.startDate == range.endDate
                    ? Format.mediumDay(range.startDate)
                    : "\(Format.shortDay(range.startDate)) – \(Format.mediumDay(range.endDate))"
                Button {
                    skipForm = .edit(range)
                } label: {
                    SettingRow(title: dates, subtitle: range.reason.flatMap { $0.isEmpty ? nil : $0 }) {
                        Badge(
                            text: Format.days(DateUtils.daysBetween(range.startDate, range.endDate) + 1),
                            color: Theme.text2, background: Theme.raised
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for id in offsets.map({ model.skipRanges[$0].id }) {
                    model.deleteSkipRange(id: id)
                }
            }
            Button {
                skipForm = .new
            } label: {
                Label("Add skip days", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            SectionLabel(title: "Skip days").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    For one day, tap its date in the schedule or swipe it right. \
                    Tap a stretch here to change it, or swipe it to delete it.
                    """)
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                pick(.export)
            } label: {
                IconRow(
                    icon: "square.and.arrow.down", color: Theme.accent,
                    title: "Import from BeanConqueror",
                    subtitle: model.lastImportDate.map { "Last imported \(Format.daysAgo($0, today: model.today))" }
                        ?? "Or share the export ZIP to this app"
                )
            }
            .buttonStyle(.plain)
            FolderPrompt { pick(.folder) }
        } header: {
            SectionLabel(title: "Data").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    The database is saved as \(DatabaseLocation.fileName) in the folder and synced by iCloud Drive.
                    """)
        }
    }

    private func pick(_ target: Picking) {
        picking = target
        showingImporter = true
    }

    private func update<Value>(_ keyPath: WritableKeyPath<ScheduleSettings, Value>, to newValue: Value) {
        var settings = model.settings
        settings[keyPath: keyPath] = newValue
        model.updateSettings(settings)
    }
}

/// Shows the chosen iCloud Drive folder, or asks for one.
struct FolderPrompt: View {
    @Environment(AppModel.self) private var model
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            IconRow(
                icon: "icloud", color: Theme.frozenText,
                title: "iCloud Drive folder",
                subtitle: model.folderName.map { "\(DatabaseLocation.fileName) is kept in “\($0)”" }
                    ?? "Choose a folder to keep your data in"
            )
        }
        .buttonStyle(.plain)
    }
}

/// The roasters in the beans that have no default yet; tapping one adds it.
private struct AddRoasterList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let roasters: [String]

    var body: some View {
        List(roasters, id: \.self) { roaster in
            Button {
                model.setRoasterRestDays(roaster, model.settings.defaultRestDays)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(model.rail(roaster)).frame(width: 10, height: 10)
                    Text(roaster).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                }
                .frame(minHeight: 36)
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
        .navigationTitle("Add a roaster")
        .navigationBarTitleDisplayMode(.inline)
    }
}
