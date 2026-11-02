import AppIntents
import CoachCore
import Observation
import UIKit

/// Gemeinsamer Navigationszustand: gewählter Reiter und eine offene Aktion aus Schnellaktion am App-Icon,
/// Kurzbefehl/Siri oder Link `coach://open/…`. Die Zielansicht übernimmt die Aktion mit `take` genau einmal.
@Observable
final class AppRouter {
  static let shared = AppRouter()

  struct Request: Equatable {
    let route: AppRoute
    let id = UUID()
  }

  var tab: AppTab = .today
  /// Angeforderte, noch nicht ausgeführte Route. Jede Anforderung ist neu (zweimal „Mahlzeit erfassen“ geht).
  private(set) var pending: Request?

  func open(_ route: AppRoute) {
    pending = Request(route: route)
  }

  /// Übernimmt die Aktion, wenn sie zur Route passt.
  func take(_ route: AppRoute) -> Bool {
    guard pending?.route == route else { return false }
    pending = nil
    return true
  }

  /// Reiter wählen; Aktionen, die es für die Person nicht gibt, verfallen statt später überraschend auszulösen.
  func resolve(trainsStrength: Bool, ready: Bool) {
    guard let route = pending?.route else { return }
    guard ready else {
      pending = nil
      return
    }
    tab = route.tab(trainsStrength: trainsStrength)
    if !route.hasAction || (route == .startWorkout && !trainsStrength) { pending = nil }
  }

  // MARK: Schnellaktionen am App-Icon

  /// Dynamische Einträge (statt fester in der Info.plist), damit nur Passendes erscheint. iOS zeigt sie nach dem
  /// ersten Start der App.
  static func updateQuickActions(trainsStrength: Bool, aiAvailable: Bool) {
    UIApplication.shared.shortcutItems = QuickActions.routes(trainsStrength: trainsStrength, aiAvailable: aiAvailable)
      .map { route in
        UIApplicationShortcutItem(
          type: route.rawValue, localizedTitle: route.title, localizedSubtitle: route.subtitle,
          icon: UIApplicationShortcutIcon(systemImageName: route.symbol))
      }
  }

  @discardableResult
  func handle(_ item: UIApplicationShortcutItem) -> Bool {
    guard let route = AppRoute(rawValue: item.type) else { return false }
    open(route)
    return true
  }
}

/// Nimmt Schnellaktionen am App-Icon an: beim Kaltstart über die Verbindungsoptionen, sonst über die Szene.
/// SwiftUI verwaltet Fenster und Links weiter selbst; die Szene ergänzt nur `performActionFor`.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    if let item = options.shortcutItem { AppRouter.shared.handle(item) }
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = QuickActionSceneDelegate.self
    return configuration
  }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async
    -> Bool
  {
    AppRouter.shared.handle(shortcutItem)
  }
}

// MARK: Kurzbefehle und Siri (App Shortcuts)

/// Öffnen die App an einer Route. `nonisolated` und ohne Parameter wie die Intents der Live-Aktivität
/// (`@Parameter` geht in `nonisolated`-Strukturen nicht); Titel als Konstanten, weil Xcode sie beim Bauen ausliest.
nonisolated struct StartWorkoutIntent: AppIntent {
  static let title: LocalizedStringResource = "Training starten"
  static let openAppWhenRun = true

  init() {}

  func perform() async throws -> some IntentResult {
    await AppRouter.shared.open(.startWorkout)
    return .result()
  }
}

nonisolated struct LogMealIntent: AppIntent {
  static let title: LocalizedStringResource = "Mahlzeit erfassen"
  static let openAppWhenRun = true

  init() {}

  func perform() async throws -> some IntentResult {
    await AppRouter.shared.open(.logMeal)
    return .result()
  }
}

nonisolated struct OpenHealthIntent: AppIntent {
  static let title: LocalizedStringResource = "Health öffnen"
  static let openAppWhenRun = true

  init() {}

  func perform() async throws -> some IntentResult {
    await AppRouter.shared.open(.health)
    return .result()
  }
}

nonisolated struct AIAnalysisIntent: AppIntent {
  static let title: LocalizedStringResource = "KI-Analyse starten"
  static let openAppWhenRun = true

  init() {}

  func perform() async throws -> some IntentResult {
    await AppRouter.shared.open(.aiAnalysis)
    return .result()
  }
}

/// Erscheinen ohne Einrichtung in Spotlight, der Kurzbefehle-App, bei Siri und auf der Aktionstaste.
nonisolated struct CoachShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartWorkoutIntent(),
      phrases: ["Training starten in \(.applicationName)", "\(.applicationName) Training starten"],
      shortTitle: "Training starten", systemImageName: "dumbbell")
    AppShortcut(
      intent: LogMealIntent(),
      phrases: ["Mahlzeit erfassen in \(.applicationName)", "\(.applicationName) Mahlzeit erfassen"],
      shortTitle: "Mahlzeit erfassen", systemImageName: "fork.knife")
    AppShortcut(
      intent: OpenHealthIntent(),
      phrases: ["Health öffnen in \(.applicationName)", "\(.applicationName) Morning Report"],
      shortTitle: "Health öffnen", systemImageName: "heart.text.square")
    AppShortcut(
      intent: AIAnalysisIntent(),
      phrases: ["KI-Analyse starten in \(.applicationName)", "\(.applicationName) analysieren"],
      shortTitle: "KI-Analyse", systemImageName: "sparkles")
  }
}
