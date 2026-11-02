import Foundation

/// Aufstehzeit für den Wecker: aus der Weckzeit des Schlaf-Coaches oder „jetzt ins Bett“ plus Schlafbedarf.
/// Gestellt wird eine Uhrzeit (Ortszeit), kein fester Zeitpunkt – so bleibt der Wecker nach einem Zeitzonenwechsel
/// oder der Zeitumstellung auf derselben Uhrzeit.
public enum WakePlan {
  public struct Time: Codable, Equatable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
      self.hour = min(max(hour, 0), 23)
      self.minute = min(max(minute, 0), 59)
    }

    public init(minutes: Int) {
      let value = (minutes % 1_440 + 1_440) % 1_440
      self.init(hour: value / 60, minute: value % 60)
    }

    public var minutes: Int { hour * 60 + minute }
    public var text: String { SleepCoach.clock(minutes) }
  }

  public enum Repeat: String, Codable, CaseIterable, Sendable {
    case once, weekdays, daily

    public var label: String {
      switch self {
      case .once: "Einmalig"
      case .weekdays: "Mo–Fr"
      case .daily: "Täglich"
      }
    }

    /// Wochentage nach `Calendar` (1 = Sonntag … 7 = Samstag); leer = einmalig.
    public var weekdays: [Int] {
      switch self {
      case .once: []
      case .weekdays: [2, 3, 4, 5, 6]
      case .daily: [1, 2, 3, 4, 5, 6, 7]
      }
    }
  }

  /// Wer jetzt ins Bett geht: jetzt + Einschlafzeit + Schlafbedarf, auf 5 Minuten aufgerundet.
  public static func wakeIfSleepingNow(
    nowMinutes: Int, sleepMinutes: Int, latency: Int = SleepCoach.latencyMinutes
  ) -> Time {
    let raw = nowMinutes + latency + sleepMinutes
    return Time(minutes: Int((Double(raw) / 5).rounded(.up)) * 5)
  }

  /// Schlafdauer bis zur Weckzeit, wenn man um `bedtimeMinutes` ins Bett geht (ohne Einschlafzeit).
  public static func sleepMinutes(bedtimeMinutes: Int, wake: Time, latency: Int = SleepCoach.latencyMinutes) -> Int {
    ((wake.minutes - bedtimeMinutes - latency) % 1_440 + 1_440) % 1_440
  }

  /// Nächster Zeitpunkt mit dieser Uhrzeit nach `now` (für „morgen 6:30“), berücksichtigt Zeitumstellungen.
  public static func nextDate(_ time: Time, after now: Date, calendar: Calendar = .current) -> Date? {
    calendar.nextDate(
      after: now, matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
      matchingPolicy: .nextTime)
  }

  /// „heute 23:00“, „morgen 6:30“ oder Wochentag.
  public static func dayLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "heute" }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
      return "morgen"
    }
    let names = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    return "am " + names[(calendar.component(.weekday, from: date) - 1) % 7]
  }
}
