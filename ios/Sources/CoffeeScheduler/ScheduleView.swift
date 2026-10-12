import CoffeeCore
import SwiftUI
import UniformTypeIdentifiers

/// A month grid with the bag key, or a list of upcoming days, a week per
/// card starting with the current week.
struct ScheduleView: View {
    enum Layout: Hashable { case month, list }

    @Environment(AppModel.self) private var model
    @State private var pickingFolder = false
    @State private var path: [BeanRoute] = []
    @State private var dayOptions: DayRoute?
    @State private var layout: Layout
    /// First of the month the grid shows; nil for the current month.
    @State private var month: String?

    init(layout: Layout = .month) {
        _layout = State(initialValue: layout)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ScreenHeader(eyebrow: Format.longDay(model.today), title: "Schedule")
                        // Top inset: the section's rounded corner would clip the first line
                        .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 14, trailing: 0))
                    if !model.schedule.isEmpty {
                        LayoutSwitch(layout: $layout)
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !model.hasFolder {
                    Section {
                        FolderPrompt { pickingFolder = true }
                    }
                    .listRowBackground(Theme.card)
                }
                if layout == .month && !model.schedule.isEmpty {
                    monthSections
                } else {
                    WeekList(
                        openBean: { path.append(BeanRoute(id: $0)) },
                        openDay: { dayOptions = DayRoute(date: $0) }
                    )
                }
            }
            .listSectionSpacing(16)
            .contentMargins(.top, 0, for: .scrollContent)
            .themedList()
            .statusBarCover()
            // The title is drawn in the list; this one names the back button
            .navigationTitle("Schedule")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
            .sheet(item: $dayOptions) { day in
                NavigationStack { DayOptionsSheet(date: day.date) }
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.chooseFolder(url) }
            }
            .overlay {
                if model.schedule.isEmpty {
                    ContentUnavailableView(
                        "No beans yet",
                        systemImage: "cup.and.saucer",
                        description: Text("Share a BeanConqueror export to this app, or import one from Settings.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var monthSections: some View {
        let shown = Binding(
            get: { month ?? DateUtils.firstOfMonth(model.today) },
            set: { month = $0 }
        )
        Section {
            MonthView(
                month: shown,
                openBean: { path.append(BeanRoute(id: $0)) },
                openDay: { dayOptions = DayRoute(date: $0) }
            )
            .listRowInsets(EdgeInsets(top: 12, leading: 10, bottom: 10, trailing: 10))
        }
        .listRowBackground(Theme.card)
        let runs = model.bagRuns(inMonth: shown.wrappedValue)
        if !runs.isEmpty {
            Section {
                BagKey(runs: runs) { path.append(BeanRoute(id: $0)) }
            } header: {
                SectionLabel(title: "Bags this month").listRowInsets(Theme.labelInsets)
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        RunwaySection()
    }
}

/// Month or List, with Month first because the schedule opens on it.
private struct LayoutSwitch: View {
    @Binding var layout: ScheduleView.Layout

    var body: some View {
        HStack(spacing: 4) {
            option("Month", .month)
            option("List", .list)
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func option(_ title: String, _ value: ScheduleView.Layout) -> some View {
        let isSelected = layout == value
        return Button {
            layout = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.ground : Theme.text2)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isSelected ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        // Plain, so each half takes its own taps inside the list row
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
