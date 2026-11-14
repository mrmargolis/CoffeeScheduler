import AppIntents
import SwiftUI
import UIKit

@main
struct CoffeeSchedulerApp: App {
    @State private var model = AppModel.forLaunch()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Besides refreshing the Siri phrases, this is the only reference to
        // the intents from the app's own code. Without one the linker leaves
        // them out of the binary, and running the shortcut fails with "an
        // internal error occurred".
        CoffeeShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // BeanConqueror exports arrive here from the share sheet ("Open in").
                .onOpenURL { url in model.importExport(at: url) }
                .selectsNumbersOnTap()
                // Midnight with the app open: today has moved on
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    model.reloadFromICloud()
                }
                .alert(
                    model.message?.title ?? "",
                    isPresented: Binding(
                        get: { model.message != nil },
                        set: { if !$0 { model.message = nil } }
                    ),
                    presenting: model.message
                ) { _ in
                    Button("OK") {}
                } message: { message in
                    Text(message.body)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reloadFromICloud() }
        }
    }
}

struct RootView: View {
    enum Tab: Hashable { case schedule, beans, settings }

    @State private var tab = Tab.schedule
    /// Counts taps on the tab already showing, which take it back to its top.
    @State private var retaps: [Tab: Int] = [:]

    var body: some View {
        let selection = Binding {
            tab
        } set: { tapped in
            if tapped == tab { retaps[tapped, default: 0] += 1 }
            tab = tapped
        }
        TabView(selection: selection) {
            ScheduleView(retaps: retaps[.schedule, default: 0])
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Tab.schedule)
            BeansView(retaps: retaps[.beans, default: 0])
                .tabItem { Label("Beans", systemImage: "list.bullet") }
                .tag(Tab.beans)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .coffeeTheme()
    }
}

extension View {
    /// Back to the top when the tab bar's button for this screen is tapped
    /// again: first out of a bag's page, if one's open, then up the list to
    /// the row marked `ScrollTop.id`.
    func scrollsToTop(on retaps: Int, path: Binding<[BeanRoute]>, proxy: ScrollViewProxy) -> some View {
        onChange(of: retaps) {
            if path.wrappedValue.isEmpty {
                withAnimation { proxy.scrollTo(ScrollTop.id, anchor: .top) }
            } else {
                path.wrappedValue.removeAll()
            }
        }
    }
}

/// The id of the first row of a tab's list.
enum ScrollTop {
    static let id = "top"
}
