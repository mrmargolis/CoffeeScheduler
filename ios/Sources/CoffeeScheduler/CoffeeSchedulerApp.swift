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
    var body: some View {
        TabView {
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            BeansView()
                .tabItem { Label("Beans", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .coffeeTheme()
    }
}
