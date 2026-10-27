import SwiftUI

@main
struct CoachApp: App {
  @State private var model = DemoData.isRequested ? DemoData.makeModel() : AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    let appModel = model
    WindowGroup {
      RootView()
        .environment(appModel)
        .preferredColorScheme(DemoData.colorScheme.map { $0 == "dark" ? ColorScheme.dark : ColorScheme.light })
    }
    .modelContainer(appModel.container)
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        Task {
          await appModel.syncIfDue()
          await appModel.refreshReminders()
        }
      case .background: if !appModel.isDemo { appModel.scheduleBackgroundRefresh() }
      default: break
      }
    }
    .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
      await appModel.backgroundRefresh()
    }
  }
}
