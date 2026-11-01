import Foundation

/// Kennzahlen je Übung: geschätztes 1RM, Bestwerte und Verlauf (wie die Statistik in GymBook).
public enum GymStats {
  /// Geschätztes Maximalgewicht für eine Wiederholung nach Epley: Gewicht × (1 + Wdh./30). Über 12 Wiederholungen
  /// wird die Schätzung ungenau und nicht ausgewiesen.
  public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
    guard weightKg > 0, reps > 0, reps <= 12 else { return nil }
    return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
  }

  public struct Point: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    /// Schwerstes Gewicht des Tages.
    public var topWeightKg: Double
    /// Bestes geschätztes 1RM des Tages.
    public var oneRepMaxKg: Double?
    /// Meiste Wiederholungen in einem Satz.
    public var bestReps: Int
    public var volumeKg: Double
    public var sets: [LoggedSet]
    public var id: CalendarDay { day }
  }

  public struct Records: Equatable, Sendable {
    public var heaviestKg: Double?
    public var bestOneRepMaxKg: Double?
    public var mostReps: Int?
    public var bestVolumeKg: Double?
  }

  /// Verlauf einer Übung, alt → neu; mehrere Einheiten am selben Tag zusammengelegt.
  public static func history(of exerciseID: String, sessions: [GymSession]) -> [Point] {
    var byDay: [CalendarDay: [LoggedSet]] = [:]
    for session in sessions {
      for exercise in session.exercises where exercise.exerciseID == exerciseID {
        byDay[session.day, default: []].append(contentsOf: exercise.doneSets)
      }
    }
    return byDay.keys.sorted().compactMap { day in
      let sets = byDay[day] ?? []
      guard !sets.isEmpty else { return nil }
      return Point(
        day: day, topWeightKg: sets.map(\.weightKg).max() ?? 0,
        oneRepMaxKg: sets.compactMap { estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max(),
        bestReps: sets.map(\.reps).max() ?? 0,
        volumeKg: sets.reduce(0) { $0 + $1.loadKg * Double($1.reps) }, sets: sets)
    }
  }

  /// Beste Leistung einer früheren Einheit: der Arbeitssatz mit der höchsten Last, bei Gleichstand mit den meisten
  /// Wiederholungen (bei Körpergewicht bzw. Halteübungen die meisten Wiederholungen bzw. Sekunden).
  public struct Performance: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    public var weightKg: Double
    public var reps: Int
    public var id: CalendarDay { day }

    /// „80 kg × 10“, „× 12“ (Körpergewicht), „+10 kg × 8“ (Zusatz), „45 s“ (Halteübung).
    public func text(isTime: Bool = false, allowsAssistance: Bool = false) -> String {
      let amount = isTime ? "\(reps) s" : "× \(reps)"
      guard weightKg != 0 else { return isTime ? amount : "\(reps) Wdh." }
      let weight =
        allowsAssistance
        ? (weightKg > 0 ? "+\(GermanFormat.number(weightKg)) kg" : "\(GermanFormat.number(-weightKg)) kg Hilfe")
        : "\(GermanFormat.number(weightKg)) kg"
      return "\(weight) \(amount)"
    }
  }

  /// Die letzten `limit` Einheiten einer Übung, neueste zuerst – als Orientierung unter der Eingabe.
  public static func recentPerformances(of exerciseID: String, sessions: [GymSession], limit: Int = 5)
    -> [Performance]
  {
    history(of: exerciseID, sessions: sessions).suffix(limit).reversed().compactMap { point in
      point.sets.max { lhs, rhs in
        (lhs.weightKg, lhs.reps) < (rhs.weightKg, rhs.reps)
      }
      .map { Performance(day: point.day, weightKg: $0.weightKg, reps: $0.reps) }
    }
  }

  public static func records(_ points: [Point]) -> Records {
    Records(
      heaviestKg: points.map(\.topWeightKg).filter { $0 > 0 }.max(),
      bestOneRepMaxKg: points.compactMap(\.oneRepMaxKg).max(),
      mostReps: points.map(\.bestReps).max(),
      bestVolumeKg: points.map(\.volumeKg).filter { $0 > 0 }.max())
  }

  /// Neue Bestwerte einer gerade beendeten Einheit gegenüber allen früheren Einheiten.
  public static func newRecords(in session: GymSession, before sessions: [GymSession]) -> [String] {
    var result: [String] = []
    let earlier = sessions.filter { $0.id != session.id && $0.start < session.start }
    for exercise in session.exercises {
      let sets = exercise.doneSets
      guard !sets.isEmpty else { continue }
      let old = records(history(of: exercise.exerciseID, sessions: earlier))
      guard old.heaviestKg != nil || old.mostReps != nil else { continue }  // erste Einheit ist kein Rekord
      let top = sets.map(\.weightKg).max() ?? 0
      let best = sets.compactMap { estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max()
      if top > 0, top > (old.heaviestKg ?? 0) {
        result.append("\(exercise.name): neues Höchstgewicht \(GermanFormat.number(top)) kg")
      } else if let best, best > (old.bestOneRepMaxKg ?? 0) + 0.01 {
        result.append("\(exercise.name): bestes geschätztes 1RM \(GermanFormat.number(best.rounded())) kg")
      } else if top == 0, let reps = sets.map(\.reps).max(), reps > (old.mostReps ?? 0) {
        result.append("\(exercise.name): \(reps) Wiederholungen – Bestwert")
      }
    }
    return result
  }
}
