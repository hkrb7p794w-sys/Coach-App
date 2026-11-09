import Foundation

/// Urlaub oder Trainingspause über mehrere Tage (Anregung: MCI, Paket 13). Im Zeitraum gibt es keine Erinnerungen
/// an Einheiten, nichts zählt als verpasst, und Begleiter und Rangliste werten die Tage nicht als geplant.
public struct TrainingBreak: Codable, Equatable, Hashable, Sendable {
  public var start: CalendarDay
  public var end: CalendarDay

  public init(start: CalendarDay, end: CalendarDay) {
    self.start = min(start, end)
    self.end = max(start, end)
  }

  public func contains(_ day: CalendarDay) -> Bool { day >= start && day <= end }

  /// Vorbei: danach nicht mehr anzeigen.
  public func isOver(today: CalendarDay) -> Bool { today > end }

  /// Wochenplan ohne die Tage im Zeitraum (`monday` = Montag der Woche).
  public func removing(from schedule: WeekSchedule, monday: CalendarDay) -> WeekSchedule {
    var result = schedule
    for weekday in Weekday.allCases where contains(monday.adding(days: weekday.rawValue)) {
      result.set([], on: weekday)
    }
    return result
  }

  public var label: String {
    "\(GermanFormat.date(start)) bis \(GermanFormat.date(end))"
  }
}
