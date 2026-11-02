import Foundation

/// Zustand einer gespeicherten, noch nicht beendeten Einheit. Erst der erste abgehakte Satz macht aus „geöffnet“ ein
/// echtes Training: Vorher gibt es keine Live-Aktivität, die Einheit zählt nicht als gemacht, und Erinnerungen bleiben
/// nur kurz aus (für den Fall, dass man gerade loslegt).
public enum ActiveSessionState: Equatable, Sendable {
  /// Keine Einheit offen.
  case none
  /// Gestartet, aber noch kein Satz abgehakt – und vor höchstens `startGrace` Stunden heute.
  case notStarted
  /// Mindestens ein Satz abgehakt, seit Beginn höchstens `runningHours`.
  case running
  /// Mit Sätzen, aber länger her (vergessen zu beenden): nicht verwerfen, beim Öffnen zum Speichern anbieten.
  case unfinished
  /// Ohne Satz und alt (z. B. gestern nur geöffnet): kann verworfen werden.
  case abandoned

  /// So lange gilt eine Einheit ohne Satz als „gerade gestartet“.
  public static let startGrace: TimeInterval = 2 * 3_600
  /// So lange gilt eine Einheit mit Sätzen als laufend.
  public static let runningHours: TimeInterval = 5 * 3_600

  public static func of(_ session: GymSession?, now: Date, calendar: Calendar = .current) -> ActiveSessionState {
    guard let session else { return .none }
    let age = now.timeIntervalSince(session.start)
    let sameDay = calendar.isDate(session.start, inSameDayAs: now)
    if session.doneSetCount == 0 {
      return sameDay && age >= -60 && age <= startGrace ? .notStarted : .abandoned
    }
    return age <= runningHours ? .running : .unfinished
  }

  /// Live-Aktivität und Dynamic Island nur während eines echten Trainings.
  public var showsLiveActivity: Bool { self == .running }

  /// Keine Trainingserinnerung für heute, solange man in der Einheit ist (auch kurz vor dem ersten Satz).
  public var suppressesReminders: Bool { self == .running || self == .notStarted }

  /// Zählt als heute trainiert (Wochenübersicht, Erinnerungen), bevor die Einheit gespeichert ist.
  public var countsAsTrained: Bool { self == .running }
}
