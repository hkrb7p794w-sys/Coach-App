import Foundation

/// Konkrete Laufwoche für persönliche Profile: Minuten je Einheit und Inhalt der Qualitätseinheit, mit vorsichtiger
/// Steigerung aus dem tatsächlichen Umfang der letzten Wochen (Garmin). Regeln:
/// - Ausgangspunkt ist der Wochenschnitt der letzten vier Wochen, nicht der Plan: Wer weniger geschafft hat, startet
///   von dort (passt sich an wie Runna).
/// - Höchstens 10 % mehr als dieser Schnitt; die feste 10-%-Regel schützt zwar nicht nachweislich (Buist 2007), über
///   30 % Steigerung wurden aber mehr Verletzungen beobachtet (Nielsen 2014) – 10 % hält großen Abstand.
/// - Jede vierte Woche ist eine Entlastungswoche mit 70 % (Bell et al. 2023: übliche Praxis, kein festes Maß).
/// - Vor einem Wettkampf zwei Wochen Tapering: 70 %, dann 50 % (Umfang um 40–60 % senken, Wang et al. 2023).
/// - Der lange Lauf ist etwa 1,4-mal so lang wie ein lockerer, die Qualitätseinheit (mit Ein- und Auslaufen) etwa
///   0,9-mal (Praxiswerte).
public enum RunPlanner {
  public enum Phase: String, Sendable {
    case build, deload, taper, race

    public var label: String {
      switch self {
      case .build: "Aufbauwoche"
      case .deload: "Entlastungswoche"
      case .taper: "Tapering"
      case .race: "Wettkampfwoche"
      }
    }
  }

  public struct Session: Equatable, Sendable {
    public var weekday: Weekday
    public var slot: SessionSlot
    public var minutes: Int
    /// Inhalt in einem Satz, z. B. „5 × 3 Minuten zügig, 2 Minuten Trabpause“.
    public var detail: String
  }

  public struct Week: Equatable, Sendable {
    public var monday: CalendarDay
    public var phase: Phase
    /// Wochenschnitt der letzten vier Wochen (Minuten), Grundlage der Steigerung.
    public var baselineMinutes: Int
    public var totalMinutes: Int
    public var sessions: [Session]
  }

  public static let maxIncrease = 0.10
  public static let deloadShare = 0.70
  public static let minimumSessionMinutes = 20

  /// Startumfang ohne Garmin-Verlauf (Minuten pro Woche) nach Erfahrung.
  static func startMinutes(_ level: ExperienceLevel) -> Double {
    switch level {
    case .beginner: 60
    case .intermediate: 120
    case .advanced: 180
    }
  }

  /// Obergrenze pro Woche nach Erfahrung (Minuten).
  static func capMinutes(_ level: ExperienceLevel) -> Double {
    switch level {
    case .beginner: 180
    case .intermediate: 330
    case .advanced: 480
    }
  }

  /// Lauf-Minuten pro Woche im Schnitt der vier vollen Wochen vor `monday`; `nil` ohne Läufe.
  public static func baseline(activities: [GarminActivity], before monday: CalendarDay) -> Double? {
    let start = monday.adding(days: -28)
    let runs = activities.filter { activity in
      guard activity.sport == .run, let day = activity.day else { return false }
      return start <= day && day < monday
    }
    guard !runs.isEmpty else { return nil }
    return runs.reduce(0) { $0 + ($1.durationSeconds ?? 0) } / 60 / 4
  }

  public static func phase(monday: CalendarDay, event: EventGoal?) -> Phase {
    if let event {
      let days = monday.days(until: event.date)
      if days >= 0 && days < 7 { return .race }
      if days >= 7 && days < 14 { return .taper }
    }
    // Feste Zählung ab Montag, 5.1.2026: jede vierte Woche entlastet.
    let anchor = CalendarDay(year: 2026, month: 1, day: 5)
    let index = ((anchor.days(until: monday) / 7) % 4 + 4) % 4
    return index == 3 ? .deload : .build
  }

  /// Woche ab `monday` (Montag) für die Laufeinheiten des Wochenplans; `nil`, wenn keine Laufeinheit geplant ist.
  public static func week(
    profile: UserProfile, schedule: WeekSchedule, monday: CalendarDay, activities: [GarminActivity]
  ) -> Week? {
    let runDays = Weekday.allCases.flatMap { weekday in
      schedule.slots(on: weekday).filter { $0.sport == .run }.map { (weekday, $0) }
    }
    guard !runDays.isEmpty else { return nil }
    let level = profile.level(for: .run)
    let fallback = profile.currentRunKilometersPerWeek.map { $0 * 6.5 } ?? startMinutes(level)
    let baseline = baseline(activities: activities, before: monday) ?? fallback
    let phase = phase(monday: monday, event: profile.event)
    // Steigerung nur in Aufbauwochen; nie über die Obergrenze der Erfahrungsstufe (außer man läuft schon mehr).
    let cap = max(capMinutes(level), baseline)
    let build = min(baseline * (1 + maxIncrease), cap)
    let total: Double =
      switch phase {
      case .build: build
      case .deload: baseline * deloadShare
      case .taper: baseline * 0.7
      case .race: baseline * 0.5
      }
    let sessions = distribute(
      total: total, runDays: runDays, level: level, monday: monday, phase: phase, event: profile.event)
    return Week(
      monday: monday, phase: phase, baselineMinutes: Int(baseline.rounded()),
      totalMinutes: sessions.reduce(0) { $0 + $1.minutes }, sessions: sessions)
  }

  static func distribute(
    total: Double, runDays: [(Weekday, SessionSlot)], level: ExperienceLevel, monday: CalendarDay, phase: Phase,
    event: EventGoal?
  ) -> [Session] {
    // Mit nur einer Laufeinheit ist sie die ganze Woche; sonst Anteile nach Gewicht (locker 1, Qualität 0,9, lang 1,4).
    let single = runDays.count == 1
    func role(_ slot: SessionSlot) -> SessionIntensity { single ? .easy : slot.intensity }
    func weight(_ intensity: SessionIntensity) -> Double {
      switch intensity {
      case .easy: 1
      case .hard: 0.9
      case .long: 1.4
      }
    }
    let unit = total / runDays.reduce(0) { $0 + weight(role($1.1)) }
    let week = (CalendarDay(year: 2026, month: 1, day: 5).days(until: monday) / 7 % 4 + 4) % 4
    return runDays.map { weekday, slot in
      let minutes: Double
      var detail: String
      let intensity = role(slot)
      minutes = unit * weight(intensity)
      switch intensity {
      case .long: detail = "Ruhig und gleichmäßig, du kannst dich dabei unterhalten."
      case .hard: detail = quality(level: level, week: week, phase: phase)
      case .easy: detail = "Locker im Gesprächstempo."
      }
      if phase == .race, let event, Weekday(day: event.date) == weekday {
        detail = "Wettkampf: \(event.name). Viel Erfolg!"
      }
      let rounded = max(Int((minutes / 5).rounded()) * 5, minimumSessionMinutes)
      return Session(weekday: weekday, slot: slot, minutes: rounded, detail: detail)
    }
  }

  /// Inhalt der Qualitätseinheit, wöchentlich leicht steigend (Praxiswerte); ohne Pace, nach Gefühl und Puls.
  static func quality(level: ExperienceLevel, week: Int, phase: Phase) -> String {
    if phase == .taper || phase == .race {
      return "Kurz und zügig: 4 × 1 Minute flott, 2 Minuten locker – frisch bleiben."
    }
    if phase == .deload {
      return "Locker mit 6 kurzen Steigerungen (20 Sekunden) zum Schluss."
    }
    switch level {
    case .beginner:
      return ["6 × 1 Minute zügig, 2 Minuten gehen oder traben.", "8 × 1 Minute zügig, 2 Minuten traben.",
        "5 × 2 Minuten zügig, 2 Minuten traben."][min(week, 2)]
    case .intermediate:
      return ["5 × 3 Minuten zügig, 2 Minuten Trabpause.", "4 × 4 Minuten zügig, 3 Minuten Trabpause.",
        "3 × 8 Minuten an der Schwelle, 2 Minuten Trabpause."][min(week, 2)]
    case .advanced:
      return ["6 × 3 Minuten zügig, 2 Minuten Trabpause.", "5 × 4 Minuten zügig, 3 Minuten Trabpause.",
        "3 × 10 Minuten an der Schwelle, 2 Minuten Trabpause."][min(week, 2)]
    }
  }
}
