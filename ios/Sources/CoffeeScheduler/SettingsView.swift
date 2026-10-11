import CoffeeCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    // One file importer for the whole screen: SwiftUI mishandles several in one hierarchy.
    @State private var showingImporter = false
    @State private var picking = Picking.export
    private enum Picking { case export, folder }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Daily coffee") {
                        Stepper(
                            "\(Format.grams(model.settings.dailyConsumptionGrams))g",
                            value: setting(\.dailyConsumptionGrams),
                            in: 15...150,
                            step: 5
                        )
                    }
                    LabeledContent("Default rest") {
                        Stepper(
                            "\(model.settings.defaultRestDays) days",
                            value: setting(\.defaultRestDays),
                            in: 0...90
                        )
                    }
                } header: {
                    Text("Schedule")
                }

                Section {
                    ForEach(model.roasterDefaults) { entry in
                        LabeledContent(entry.roaster) {
                            Stepper(
                                "\(entry.restDays) days",
                                value: Binding(
                                    get: { entry.restDays },
                                    set: { model.setRoasterRestDays(entry.roaster, $0) }
                                ),
                                in: 0...90
                            )
                        }
                    }
                    .onDelete { offsets in
                        for roaster in offsets.map({ model.roasterDefaults[$0].roaster }) {
                            model.setRoasterRestDays(roaster, nil)
                        }
                    }
                    let unset = model.roasters.filter { name in !model.roasterDefaults.contains { $0.roaster == name } }
                    if !unset.isEmpty {
                        // A pushed list, not a Menu: iOS 26 menus can't be
                        // reached by UI tests. Picking a roaster adds it at the
                        // default rest and comes back here.
                        NavigationLink {
                            AddRoasterList(roasters: unset)
                        } label: {
                            Label("Add a roaster", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Rest by roaster")
                } footer: {
                    Text("A bag rests for its own days if set, else its roaster's, else the default rest above. Swipe a roaster to remove it.")
                }

                Section {
                    if model.skipRanges.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(model.skipRanges) { range in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(range.startDate == range.endDate
                                 ? Format.mediumDay(range.startDate)
                                 : "\(Format.shortDay(range.startDate)) – \(Format.mediumDay(range.endDate))")
                            if let reason = range.reason, !reason.isEmpty {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for id in offsets.map({ model.skipRanges[$0].id }) {
                            model.deleteSkipRange(id: id)
                        }
                    }
                } header: {
                    Text("Skip days")
                } footer: {
                    Text("Tap a day's date in the schedule, or swipe it right, to skip it. Swipe a stretch here to delete it.")
                }

                Section {
                    Button("Import BeanConqueror export…") { pick(.export) }
                } footer: {
                    Text("You can also share the export ZIP from BeanConqueror straight to this app.")
                }

                Section {
                    FolderPrompt { pick(.folder) }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("The database is saved as \(DatabaseLocation.fileName) in this folder and synced by iCloud Drive. The web app's data/coffee.db can be dropped in here too.")
                }
            }
            .navigationTitle("Settings")
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

    private func pick(_ target: Picking) {
        picking = target
        showingImporter = true
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<ScheduleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.settings
                settings[keyPath: keyPath] = newValue
                model.updateSettings(settings)
            }
        )
    }
}

/// Shows the chosen iCloud Drive folder, or asks for one.
struct FolderPrompt: View {
    @Environment(AppModel.self) private var model
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            if let name = model.folderName {
                LabeledContent("iCloud Drive folder", value: name)
            } else {
                Label("Choose an iCloud Drive folder to keep your data in", systemImage: "icloud")
            }
        }
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
                HStack(spacing: 8) {
                    RoasterRail(color: model.rail(roaster))
                    Text(roaster).foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Add a roaster")
        .navigationBarTitleDisplayMode(.inline)
    }
}
