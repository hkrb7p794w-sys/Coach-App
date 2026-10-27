import Foundation

/// Einstellungen des Schlaf-Coaches: gewünschte Schlafdauer, Weckzeit und Erinnerung vor dem Zubettgehen.
public struct SleepSettings: Codable, Equatable, Hashable, Sendable {
  /// Gewünschte Schlafdauer in Stunden (7–9, Empfehlung für Erwachsene).
  public var targetHours: Double = 8
  public var wakeHour = 6
  public var wakeMinute = 30
  /// Mitteilung 30 Minuten vor der empfohlenen Schlafenszeit.
  public var reminder = false

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    targetHours = min(max((try? container.decodeIfPresent(Double.self, forKey: .targetHours)) ?? 8, 7), 9)
    wakeHour = min(max((try? container.decodeIfPresent(Int.self, forKey: .wakeHour)) ?? 6, 0), 23)
    wakeMinute = min(max((try? container.decodeIfPresent(Int.self, forKey: .wakeMinute)) ?? 30, 0), 59)
    reminder = (try? container.decodeIfPresent(Bool.self, forKey: .reminder)) ?? false
  }

  public var wakeMinutes: Int { wakeHour * 60 + wakeMinute }
}

/// Schlaf-Coach wie bei Whoop, aber mit offenen Regeln: Schlafbedarf für heute Nacht, empfohlene Schlafenszeit,
/// Regelmäßigkeit und Hinweise. Grundlage: 7–9 Stunden für Erwachsene (Watson et al. 2015), mehr Schlaf
/// verbesserte Leistung bei Sportlern (Mah et al. 2011), regelmäßige Schlafzeiten (Windred et al. 2024).
public enum SleepCoach {
  /// Zeit zum Einschlafen, die zur Bettzeit dazukommt (Praxiswert).
  public static let latencyMinutes = 15
  /// Nachholen nach kurzen Nächten: ein Viertel des Defizits der letzten 7 Nächte, höchstens 60 Minuten
  /// (Praxiswert, kein Studienergebnis).
  public static let maxExtraMinutes = 60.0
  /// Ab dieser Streuung der Einschlafzeit (Standardabweichung in Minuten) gilt der Schlaf als unregelmäßig.
  public static let irregularMinutes = 60.0

  public struct Tip: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var evidenceIDs: [String]
  }

  public struct Report: Equatable, Sendable {
    public var nights: Int
    public var averageHours: Double
    public var shortNights: Int
    /// Fehlende Stunden der letzten 7 Nächte gegenüber dem Ziel.
    public var debtHours: Double
    /// Schlafbedarf heute Nacht in Minuten.
    public var tonightMinutes: Int
    /// Empfohlene Zeit zum Hinlegen, Minuten nach Mitternacht.
    public var bedtimeMinutes: Int
    /// Streuung der Einschlafzeit in Minuten (nur mit mindestens 4 bekannten Zeiten).
    public var bedtimeSpreadMinutes: Double?
    public var tips: [Tip]
  }

  /// Bericht aus den letzten 7 Nächten bis einschließlich `today` (Garmin ordnet die Nacht dem Aufwachtag zu).
  public static func report(
    days: [DailyMetrics], settings: SleepSettings, goal: FitnessGoal?, today: CalendarDay
  ) -> Report? {
    let start = today.adding(days: -6)
    let nights = days.filter { $0.day >= start && $0.day <= today && ($0.sleepSeconds ?? 0) > 0 }
    guard nights.count >= 3 else { return nil }
    let hours = nights.map { ($0.sleepSeconds ?? 0) / 3_600 }
    let average = hours.reduce(0, +) / Double(hours.count)
    let debt = hours.reduce(0) { $0 + max(0, settings.targetHours - $1) }
    let extra = min(debt * 60 / 4, maxExtraMinutes)
    let tonight = Int(((settings.targetHours * 60 + extra) / 5).rounded()) * 5
    let bedtime = ((settings.wakeMinutes - tonight - latencyMinutes) % 1_440 + 1_440) % 1_440

    // Einschlafzeiten relativ zu 12 Uhr, damit 23:30 und 0:30 nah beieinander liegen.
    let starts = nights.compactMap(\.sleepStartMinutes).map { ($0 + 720).truncatingRemainder(dividingBy: 1_440) }
    var spread: Double?
    if starts.count >= 4 {
      let mean = starts.reduce(0, +) / Double(starts.count)
      spread = (starts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(starts.count)).squareRoot().rounded()
    }

    var tips: [Tip] = []
    let shortNights = hours.filter { $0 < 7 }.count
    if average < 7 {
      tips.append(
        Tip(
          id: "short",
          text:
            "Im Schnitt \(GermanFormat.decimal(average)) Stunden – weniger als die empfohlenen 7. Gehe heute um "
            + "\(clock(bedtime)) ins Bett, um wieder auf \(GermanFormat.decimal(Double(tonight) / 60)) Stunden "
            + "zu kommen.",
          evidenceIDs: ["recovery.sleep", "sleep.extension"]))
      if goal?.losesWeight == true {
        tips.append(
          Tip(
            id: "weight",
            text: "Gerade beim Abnehmen hilft ausreichend Schlaf, Muskeln zu erhalten.",
            evidenceIDs: ["weightloss.sleep"]))
      }
    } else if extra >= 15 {
      tips.append(
        Tip(
          id: "catch-up",
          text:
            "Einige Nächte waren kürzer als dein Ziel. Heute etwa \(Int(extra)) Minuten früher ins Bett hilft beim "
            + "Aufholen.",
          evidenceIDs: ["sleep.extension"]))
    } else {
      tips.append(
        Tip(
          id: "good",
          text: "Dein Schlaf passt zu deinem Ziel. Bleib bei deinen Zeiten.",
          evidenceIDs: ["recovery.sleep"]))
    }
    if let spread, spread > irregularMinutes {
      tips.append(
        Tip(
          id: "regular",
          text:
            "Deine Einschlafzeit schwankt um etwa \(Int(spread)) Minuten. Feste Zeiten – auch am Wochenende – "
            + "machen den Schlaf erholsamer.",
          evidenceIDs: ["sleep.regularity"]))
    }
    return Report(
      nights: nights.count, averageHours: (average * 10).rounded() / 10, shortNights: shortNights,
      debtHours: (debt * 10).rounded() / 10, tonightMinutes: tonight, bedtimeMinutes: bedtime,
      bedtimeSpreadMinutes: spread, tips: tips)
  }

  /// „22:15“
  public static func clock(_ minutes: Int) -> String {
    let value = (minutes % 1_440 + 1_440) % 1_440
    return String(format: "%d:%02d", value / 60, value % 60)
  }
}
