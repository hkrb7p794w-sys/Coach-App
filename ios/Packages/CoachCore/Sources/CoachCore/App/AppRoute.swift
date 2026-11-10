import Foundation

/// Reiter der App. Gym liegt im Reiter Training, die KI-Empfehlungen sind von „Heute“ aus erreichbar
/// (Entscheidung vom 10.11.2026: Platz für den Reiter „Aktivitäten“).
public enum AppTab: String, Codable, CaseIterable, Sendable {
  case today, activities, training, nutrition
}

/// Ziele, die von außen angesprungen werden: Schnellaktionen am App-Icon, Kurzbefehle/Siri und (später)
/// Homescreen-Widgets. Eine Route wählt den Reiter und optional eine Aktion darin; als Link `coach://open/<route>`.
public enum AppRoute: String, Codable, CaseIterable, Sendable, Identifiable {
  case today
  /// Gesundheitsbereich (Morning Report, Widgets, Body Battery) im Reiter Training.
  case health
  case nutrition
  /// Erfassen-Bildschirm der Ernährung öffnen.
  case logMeal
  case gym
  /// Laufende Einheit öffnen, sonst die nächste geplante starten (zählt erst mit dem ersten Satz).
  case startWorkout
  case ai
  /// KI-Analyse über alle Themen anstoßen (nur wenn die KI eingerichtet und erlaubt ist).
  case aiAnalysis

  public static let scheme = "coach"
  public static let host = "open"

  public var id: String { rawValue }

  public init?(url: URL) {
    guard url.scheme == Self.scheme, url.host() == Self.host else { return nil }
    let name = url.pathComponents.first { $0 != "/" } ?? ""
    self.init(rawValue: name)
  }

  public var url: URL {
    URL(string: "\(Self.scheme)://\(Self.host)/\(rawValue)") ?? URL(fileURLWithPath: "/")
  }

  /// „Mahlzeit erfassen“ für eine bestimmte Mahlzeit (Mahlzeiten-Widget): `coach://open/logMeal?mahlzeit=…`.
  public static func logMealURL(_ category: MealCategory) -> URL {
    URL(string: "\(AppRoute.logMeal.url.absoluteString)?mahlzeit=\(category.rawValue)") ?? AppRoute.logMeal.url
  }

  /// Mahlzeit aus einem Link (`?mahlzeit=mittagessen`), sonst `nil`.
  public static func mealCategory(from url: URL) -> MealCategory? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "mahlzeit" }?.value.flatMap(MealCategory.init(rawValue:))
  }

  /// Reiter der Route. Gym-Ziele öffnen den Gym-Bereich im Reiter Training, KI-Ziele die Empfehlungen über „Heute“.
  public var tab: AppTab {
    switch self {
    case .today, .ai, .aiAnalysis: .today
    case .health, .gym, .startWorkout: .training
    case .nutrition, .logMeal: .nutrition
    }
  }

  /// Aktion im Reiter, die die Zielansicht einmal ausführt (danach gilt die Route als erledigt).
  public var hasAction: Bool {
    switch self {
    case .health, .logMeal, .gym, .startWorkout, .ai, .aiAnalysis: true
    default: false
    }
  }

  /// Bereich, den der Reiter zuerst öffnen muss, bevor die Zielansicht die Aktion übernimmt
  /// („Training starten“ öffnet erst den Gym-Bereich, „KI-Analyse“ erst die Empfehlungen).
  public var opensArea: AppRoute? {
    switch self {
    case .gym, .startWorkout: .gym
    case .ai, .aiAnalysis: .ai
    default: nil
    }
  }

  public var title: String {
    switch self {
    case .today: "Heute"
    case .health: "Health öffnen"
    case .nutrition: "Ernährung"
    case .logMeal: "Mahlzeit erfassen"
    case .gym: "Gym"
    case .startWorkout: "Training starten"
    case .ai: "AI"
    case .aiAnalysis: "KI-Analyse starten"
    }
  }

  public var subtitle: String? {
    switch self {
    case .health: "Morning Report, Body Battery, Schlaf"
    case .logMeal: "Foto, Text, Barcode oder Suche"
    case .startWorkout: "Nächste Einheit oder laufende fortsetzen"
    case .aiAnalysis: "Alle Themen auswerten"
    default: nil
    }
  }

  /// SF-Symbol.
  public var symbol: String {
    switch self {
    case .today: "sun.max"
    case .health: "heart.text.square"
    case .nutrition: "fork.knife"
    case .logMeal: "plus.circle"
    case .gym, .startWorkout: "dumbbell"
    case .ai, .aiAnalysis: "sparkles"
    }
  }
}

/// Schnellaktionen beim langen Drücken auf das App-Icon. iOS zeigt höchstens vier eigene Einträge; angeboten wird
/// nur, was für die Person auch funktioniert (kein „Training starten“ ohne Krafttraining, keine KI ohne Worker).
public enum QuickActions {
  public static let limit = 4

  public static func routes(trainsStrength: Bool, aiAvailable: Bool) -> [AppRoute] {
    var routes: [AppRoute] = []
    if trainsStrength { routes.append(.startWorkout) }
    routes.append(.logMeal)
    routes.append(.health)
    if aiAvailable { routes.append(.aiAnalysis) }
    return Array(routes.prefix(limit))
  }
}
