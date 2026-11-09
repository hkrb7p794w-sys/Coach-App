import CoachCore
import SwiftUI

@main
struct CoachApp: App {
  @State private var model = DemoData.isRequested ? DemoData.makeModel() : AppModel()
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
  @AppStorage("privacy.coverSwitcher") private var coversSwitcher = false
  /// Schnellaktionen am App-Icon (`AppRouter`).
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  init() {
    // Früh anbinden: Tippt man „Satz erledigt“ auf dem Sperrbildschirm, startet iOS die App ggf. im Hintergrund.
    WorkoutActivityController.connect(GymViewModel.shared)
    // Exportdateien mit Gesundheitsdaten nicht unbefristet im Temp-Ordner lassen.
    try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "ki-export"))
  }

  var body: some Scene {
    let appModel = model
    WindowGroup {
      RootView()
        .environment(appModel)
        .preferredColorScheme(DemoData.colorScheme.map { $0 == "dark" ? ColorScheme.dark : ColorScheme.light })
        // Im App-Umschalter nichts Lesbares zeigen.
        .overlay {
          if coversSwitcher && scenePhase != .active { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea() }
        }
    }
    .modelContainer(appModel.container)
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // Gewählte Darstellung (Einstellungen) auf alle Fenster anwenden; die Demo-Screenshots steuern sie selbst.
        if DemoData.colorScheme == nil { AppearanceController.apply(AppAppearance(stored: appearance)) }
        // Wasser aus dem Homescreen-Widget übernehmen, dann Widgets mit dem aktuellen Stand versorgen.
        WidgetPublisher.takeQueuedActions(model: appModel)
        WidgetPublisher.publish(model: appModel)
        Task {
          await appModel.syncIfDue()
          await appModel.refreshReminders()
          WidgetPublisher.publish(model: appModel)
        }
      case .background:
        if !appModel.isDemo { appModel.scheduleBackgroundRefresh() }
        WidgetPublisher.publish(model: appModel)
        let profile = appModel.settings.profile
        AppRouter.updateQuickActions(
          trainsStrength: profile.onboardingDone && profile.trains(.strength),
          aiAvailable: appModel.ai.allows("ai_insights"))
      default: break
      }
    }
    .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
      await appModel.backgroundRefresh()
    }
  }
}
