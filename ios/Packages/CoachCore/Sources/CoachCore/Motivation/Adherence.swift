import Foundation

/// Wie gut eine Woche zum eigenen Plan passt. Gezählt werden geplante Trainingstage, an denen trainiert wurde;
/// zusätzliches Training bringt nichts extra (kein Anreiz zum Übertraining), ausgelassene Tage zählen nicht als
/// geplant (ehrliches Auslassen statt Durchziehen trotz schlechter Erholung).
public struct WeekAdherence: Equatable, Sendable {
  public enum DayState: String, Equatable, Sendable {
    /// Geplant und trainiert.
    case done
    /// Geplant, Tag vorbei, nicht trainiert.
    case missed
    /// Geplant, heute oder später.
    case open
    /// Frei (oder diese Woche ausgelassen).
    case rest
    /// Frei, aber trainiert.
    case extra
  }

  public var monday: CalendarDay
  public var days: [DayState]

  public var planned: Int { days.filter { $0 == .done || $0 == .missed || $0 == .open }.count }
  public var done: Int { days.filter { $0 == .done }.count }
  public var missed: Int { days.filter { $0 == .missed }.count }
  /// Alles Geplante erledigt (nur sinnvoll, wenn etwas geplant war).
  public var isComplete: Bool { planned > 0 && done == planned }
  /// Anteil erledigt an allem, was bis heute fällig war oder schon erledigt ist.
  public var shareSoFar: Double {
    let due = done + missed
    return due == 0 ? 1 : Double(done) / Double(due)
  }

  public static func compute(
    schedule: WeekSchedule, trainingDays: Set<CalendarDay>, weekOf day: CalendarDay, today: CalendarDay
  ) -> WeekAdherence {
    let monday = PlanAdjustments.monday(of: day)
    let states = Weekday.allCases.map { weekday -> DayState in
      let date = monday.adding(days: weekday.rawValue)
      let planned = !schedule.slots(on: weekday).isEmpty
      let trained = trainingDays.contains(date)
      switch (planned, trained) {
      case (true, true): return .done
      case (true, false): return date < today ? .missed : .open
      case (false, true): return .extra
      case (false, false): return .rest
      }
    }
    return WeekAdherence(monday: monday, days: states)
  }
}

/// Punkte für die Rangliste. Belohnt wird das Erreichen der eigenen Ziele (Punkte und Stufen für erreichte Ziele
/// wie in Patel et al. 2017 und 2019), nicht die Menge: Wer wenig plant, kann genauso gewinnen wie wer viel plant.
public enum ScoreRules {
  public static let pointsPerSession = 10
  public static let completeWeekBonus = 20
  /// Ab diesem Anteil zählt eine Woche für die Serie.
  public static let streakShare = 0.8

  public static func points(_ week: WeekAdherence) -> Int {
    week.done * pointsPerSession + (week.isComplete ? completeWeekBonus : 0)
  }

  /// Woche zählt für die Serie: mindestens 80 % des Geplanten erledigt. Laufende Wochen zählen erst, wenn sie
  /// vorbei sind.
  public static func countsForStreak(_ week: WeekAdherence) -> Bool {
    week.planned > 0 && Double(week.done) / Double(week.planned) >= streakShare
  }

  /// Serie abgeschlossener Wochen vor der aktuellen (neueste zuerst übergeben).
  public static func streak(_ finishedWeeksNewestFirst: [WeekAdherence]) -> Int {
    var count = 0
    for week in finishedWeeksNewestFirst {
      if week.planned == 0 { continue }  // Woche ohne Plan (Urlaub) unterbricht die Serie nicht
      guard countsForStreak(week) else { break }
      count += 1
    }
    return count
  }

  /// Stufe aus allen gesammelten Punkten: alle 100 Punkte eine Stufe.
  public static func level(totalPoints: Int) -> Int {
    max(totalPoints, 0) / 100 + 1
  }
}
