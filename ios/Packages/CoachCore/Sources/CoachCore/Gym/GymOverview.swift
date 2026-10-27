import Foundation

/// Was vor und nach dem Training angezeigt wird: Ziel für heute, nächste Routine, Vergleich mit dem letzten Mal,
/// Trainingskalender. Die Entscheidungen bleiben bei `GymProgression` – hier wird nur verständlich formuliert.
public enum GymTarget {
  /// „Ziel heute: 62,5 kg × 6–10 (+2,5 kg) – letztes Mal 60 × 10/10/10“.
  public static func text(for progress: ExerciseProgress, recovered: Bool?) -> String {
    let range = "\(progress.target.lowerBound)–\(progress.target.upperBound)"
    let last = "letztes Mal \(GermanFormat.number(progress.weightKg)) × \(repsText(progress.reps))"
    switch progress.status {
    case .increase where recovered != false:
      guard let next = progress.nextWeightKg, progress.weightKg > 0 else {
        return "Ziel heute: mit kleinem Zusatzgewicht starten – \(last)"
      }
      let plus = GermanFormat.number(next - progress.weightKg)
      return "Ziel heute: \(GermanFormat.number(next)) kg × \(range) (+\(plus) kg) – \(last)"
    case .restart:
      let weight = GermanFormat.number(progress.nextWeightKg ?? progress.weightKg)
      return "Wiedereinstieg: \(weight) kg × \(range) – \(last)"
    case .noWeight:
      return "Ziel heute: Haltezeit steigern"
    default:
      guard progress.weightKg > 0 else { return "Ziel heute: mehr Wiederholungen als letztes Mal (\(range))" }
      return "Ziel heute: \(GermanFormat.number(progress.weightKg)) kg, mehr Wiederholungen (\(range)) – \(last)"
    }
  }

  static func repsText(_ reps: [Int]) -> String {
    reps.map(String.init).joined(separator: "/")
  }
}

public enum RoutineRotation {
  public static func key(_ routine: Routine) -> String { "routine-\(routine.id)" }

  /// Nächste Routine in der Reihenfolge nach der zuletzt trainierten (A → B → A …); ohne Verlauf die erste.
  public static func next(routines: [Routine], sessions: [GymSession]) -> Routine? {
    guard !routines.isEmpty else { return nil }
    let keys = routines.map(key)
    let last = sessions.filter { keys.contains($0.workoutKey ?? "") }.max { $0.start < $1.start }
    guard let last, let index = keys.firstIndex(of: last.workoutKey ?? "") else { return routines.first }
    return routines[(index + 1) % routines.count]
  }

  /// Grobe Dauer: je Satz 40 s Arbeit plus Pause, auf 5 Minuten gerundet.
  public static func estimatedMinutes(_ routine: Routine) -> Int {
    let seconds = routine.items.reduce(0) { $0 + $1.sets * (40 + $1.restSeconds) }
    return max(5, Int((Double(seconds) / 60 / 5).rounded()) * 5)
  }
}

public enum SessionComparison {
  /// Letzte frühere Einheit derselben Routine bzw. desselben Plans.
  public static func previous(of session: GymSession, in sessions: [GymSession]) -> GymSession? {
    guard let key = session.workoutKey else { return nil }
    return sessions.filter { $0.id != session.id && $0.workoutKey == key && $0.start < session.start }
      .max { $0.start < $1.start }
  }

  /// Volumen gegenüber der letzten gleichen Einheit in Prozent (gerundet), `nil` ohne Vergleich.
  public static func volumeChangePercent(_ session: GymSession, previous: GymSession?) -> Int? {
    guard let previous, previous.volumeKg > 0 else { return nil }
    return Int(((session.volumeKg / previous.volumeKg - 1) * 100).rounded())
  }
}

/// Trainingskalender: Einheiten je Woche und Serie (Wochen in Folge mit mindestens einer Einheit).
public enum GymCalendar {
  public struct Week: Equatable, Sendable, Identifiable {
    public var monday: CalendarDay
    public var sessions: Int
    public var id: CalendarDay { monday }
  }

  /// Die letzten `count` Wochen, älteste zuerst.
  public static func weeks(sessions: [GymSession], today: CalendarDay, count: Int = 8) -> [Week] {
    let monday = today.adding(days: -today.weekdayIndex)
    return (0..<count).reversed().map { offset in
      let start = monday.adding(days: -7 * offset)
      let end = start.adding(days: 6)
      let days = Set(sessions.map(\.day).filter { start <= $0 && $0 <= end })
      return Week(monday: start, sessions: days.count)
    }
  }

  /// Wochen in Folge mit Training; die laufende Woche zählt erst, wenn sie eine Einheit hat.
  public static func streak(sessions: [GymSession], today: CalendarDay) -> Int {
    var weeks = self.weeks(sessions: sessions, today: today, count: 104)
    if weeks.last?.sessions == 0 { weeks.removeLast() }
    var count = 0
    for week in weeks.reversed() {
      guard week.sessions > 0 else { break }
      count += 1
    }
    return count
  }
}
