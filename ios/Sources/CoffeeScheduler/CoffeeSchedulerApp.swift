import SwiftUI

@main
struct CoffeeSchedulerApp: App {
    @State private var model = AppModel.forLaunch()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // BeanConqueror exports arrive here from the share sheet ("Open in").
                .onOpenURL { url in model.importExport(at: url) }
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
    }
}
