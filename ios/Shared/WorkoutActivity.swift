import ActivityKit
import AppIntents
import Foundation

/// Live-Aktivität der laufenden Krafteinheit (Sperrbildschirm, Dynamic Island). Die Datei gehört zur App und zur
/// Widget-Erweiterung; deshalb ohne CoachCore und ohne Bindung an den MainActor.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
  nonisolated struct ContentState: Codable, Hashable, Sendable {
    /// Übung des nächsten offenen Satzes.
    var exercise: String
    /// „Satz 2 von 4 · 62,5 kg × 8“.
    var detail: String
    var restEndsAt: Date?
    var doneSets: Int
    /// Alle Sätze erledigt – nur noch beenden.
    var allDone: Bool
  }

  var title: String
}

/// Was die Knöpfe der Live-Aktivität auslösen. Die App setzt `handler` beim Start; in der Erweiterung bleibt er leer.
/// Intents mit `LiveActivityIntent` laufen im Prozess der App (Apple: „perform() runs in the app's process“).
@MainActor
enum WorkoutActions {
  enum Action: Sendable {
    case completeSet
    case skipRest
  }

  static var handler: (@MainActor (Action) -> Void)?

  static func run(_ action: Action) {
    handler?(action)
  }
}

nonisolated struct CompleteSetIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Satz erledigt"

  init() {}

  func perform() async throws -> some IntentResult {
    await WorkoutActions.run(.completeSet)
    return .result()
  }
}

nonisolated struct SkipRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Pause überspringen"

  init() {}

  func perform() async throws -> some IntentResult {
    await WorkoutActions.run(.skipRest)
    return .result()
  }
}
