import SwiftUI

@main
struct CoachApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    let appModel = model
    WindowGroup {
      RootView()
        .environment(appModel)
    }
    .modelContainer(appModel.container)
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        Task {
          await appModel.syncIfDue()
          await appModel.refreshReminders()
        }
      case .background: appModel.scheduleBackgroundRefresh()
      default: break
      }
    }
    .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
      await appModel.backgroundRefresh()
    }
  }
}
