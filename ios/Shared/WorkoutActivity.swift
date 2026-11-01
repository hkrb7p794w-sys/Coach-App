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
    /// Werte des aktuellen Satzes zum Ändern auf dem Sperrbildschirm („80 kg“, „10 Wdh.“) und die Schrittweiten.
    var weight: String? = nil
    var reps: String? = nil
    var weightStep: String? = nil
    var repsStep: String? = nil
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
    /// Gewicht um ganze Schritte der Übung (z. B. ±2,5 kg) ändern.
    case weight(Int)
    /// Wiederholungen um ±1 (Halteübungen ±5 s) ändern.
    case reps(Int)
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

/// Gewicht des aktuellen Satzes vom Sperrbildschirm aus ändern (ohne Entsperren).
nonisolated struct AdjustWeightIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Gewicht ändern"

  @Parameter(title: "Schritte") var steps: Int

  init() {}

  init(steps: Int) {
    self.steps = steps
  }

  func perform() async throws -> some IntentResult {
    await WorkoutActions.run(.weight(steps))
    return .result()
  }
}

/// Wiederholungen des aktuellen Satzes vom Sperrbildschirm aus ändern.
nonisolated struct AdjustRepsIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Wiederholungen ändern"

  @Parameter(title: "Änderung") var delta: Int

  init() {}

  init(delta: Int) {
    self.delta = delta
  }

  func perform() async throws -> some IntentResult {
    await WorkoutActions.run(.reps(delta))
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
