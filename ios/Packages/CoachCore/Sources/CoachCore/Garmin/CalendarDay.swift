import Foundation

/// Kalendertag ohne Uhrzeit und Zeitzone (Garmins `calendarDate`, z. B. `2026-10-23`).
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Liest `yyyy-MM-dd`, auch mit angehängter Uhrzeit (`2026-10-23T00:00:00.0`).
  public init?(iso text: String) {
    let parts = text.prefix(10).split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      (1...12).contains(month), (1...31).contains(day)
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  public init(date: Date, timeZone: TimeZone = .current) {
    let components = Self.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
    self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
  }

  public var iso: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  public var description: String { iso }

  /// Mittag UTC des Tages – stabil für Datumsrechnung ohne Sommerzeit-Effekte.
  public var referenceDate: Date {
    let components = DateComponents(year: year, month: month, day: day, hour: 12)
    let utc = TimeZone(identifier: "UTC") ?? .current
    return Self.calendar(utc).date(from: components) ?? Date(timeIntervalSince1970: 0)
  }

  public func adding(days: Int) -> CalendarDay {
    let utc = TimeZone(identifier: "UTC") ?? .current
    let date = Self.calendar(utc).date(byAdding: .day, value: days, to: referenceDate) ?? referenceDate
    return CalendarDay(date: date, timeZone: utc)
  }

  /// Anzahl Tage von `self` bis `other` (positiv, wenn `other` später liegt).
  public func days(until other: CalendarDay) -> Int {
    let seconds = other.referenceDate.timeIntervalSince(referenceDate)
    return Int((seconds / 86_400).rounded())
  }

  public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  private static func calendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
}

/// Geschlossener Datumsbereich (beide Tage inklusive), wie ihn die Garmin-Endpunkte erwarten.
public struct DateRange: Equatable, Sendable {
  public let start: CalendarDay
  public let end: CalendarDay

  public init(start: CalendarDay, end: CalendarDay) {
    self.start = min(start, end)
    self.end = max(start, end)
  }

  /// Die letzten `days` Tage bis einschließlich `end`.
  public static func last(_ days: Int, endingOn end: CalendarDay) -> DateRange {
    DateRange(start: end.adding(days: -(max(days, 1) - 1)), end: end)
  }

  public var dayCount: Int { start.days(until: end) + 1 }

  /// Teilt den Bereich in Blöcke von höchstens `maxDays` Tagen (neueste zuerst), weil Garmin
  /// größere Bereiche mit 400/500 ohne Inhalt ablehnt.
  public func chunks(maxDays: Int) -> [DateRange] {
    guard maxDays > 0 else { return [self] }
    var result: [DateRange] = []
    var chunkEnd = end
    while chunkEnd >= start {
      let chunkStart = max(start, chunkEnd.adding(days: -(maxDays - 1)))
      result.append(DateRange(start: chunkStart, end: chunkEnd))
      chunkEnd = chunkStart.adding(days: -1)
    }
    return result
  }
}
