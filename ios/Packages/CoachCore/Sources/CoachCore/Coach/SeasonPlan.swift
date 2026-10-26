import Foundation

/// Renntermine und Testwerte der Saison – in der App änderbar, Standardwerte aus dem Altbestand
/// (`garmin_ai_coach/plan.py`, Stand 21.10.2026).
public struct SeasonConfig: Codable, Hashable, Sendable {
  public var mainRaceName = "Challenge Almere"
  public var mainRaceDescription = "Challenge Almere-Amsterdam, Mitteldistanz (1,9 km / 94 km / 21,1 km)"
  public var mainRaceDate = CalendarDay(year: 2027, month: 9, day: 11)
  public var raceGoal = "Finish in 5:30–6:00 h"
  public var marathonDate = CalendarDay(year: 2027, month: 5, day: 2)
  public var baseStart = CalendarDay(year: 2026, month: 9, day: 1)
  public var marathonBlockStart = CalendarDay(year: 2027, month: 1, day: 4)
  /// Zwift-FTP in Watt (Ramp Test).
  public var ftpWatts = 178
  /// Critical Swim Speed in Sekunden je 100 m.
  public var cssSecondsPer100m = 130
  /// Lauf-Schwellenpace in Sekunden je km.
  public var thresholdPaceSecondsPerKm = 295
  /// Marathon-Zielpace in Sekunden je km.
  public var marathonPaceSecondsPerKm = 325
  /// Renn-Laufpace für den Halbmarathon nach dem Rad (Almere-Benchmark) in Sekunden je km.
  public var racePaceSecondsPerKm = 342
  /// Erwarteter Rad-Schnitt auf den 94 km in km/h (Benchmark für die Zielzeit).
  public var raceBikeSpeedKmh = 30.0

  public init() {}

  public static let standard = SeasonConfig()

  private enum CodingKeys: String, CodingKey {
    case mainRaceName, mainRaceDescription, mainRaceDate, raceGoal, marathonDate, baseStart, marathonBlockStart
    case ftpWatts, cssSecondsPer100m, thresholdPaceSecondsPerKm, marathonPaceSecondsPerKm, racePaceSecondsPerKm
    case raceBikeSpeedKmh
  }

  /// Tolerant: fehlende Felder (ältere gespeicherte Stände) bekommen den Standardwert.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = SeasonConfig()
    mainRaceName = try container.decodeIfPresent(String.self, forKey: .mainRaceName) ?? defaults.mainRaceName
    mainRaceDescription =
      try container.decodeIfPresent(String.self, forKey: .mainRaceDescription) ?? defaults.mainRaceDescription
    mainRaceDate = try container.decodeIfPresent(CalendarDay.self, forKey: .mainRaceDate) ?? defaults.mainRaceDate
    raceGoal = try container.decodeIfPresent(String.self, forKey: .raceGoal) ?? defaults.raceGoal
    marathonDate = try container.decodeIfPresent(CalendarDay.self, forKey: .marathonDate) ?? defaults.marathonDate
    baseStart = try container.decodeIfPresent(CalendarDay.self, forKey: .baseStart) ?? defaults.baseStart
    marathonBlockStart =
      try container.decodeIfPresent(CalendarDay.self, forKey: .marathonBlockStart) ?? defaults.marathonBlockStart
    ftpWatts = try container.decodeIfPresent(Int.self, forKey: .ftpWatts) ?? defaults.ftpWatts
    cssSecondsPer100m =
      try container.decodeIfPresent(Int.self, forKey: .cssSecondsPer100m) ?? defaults.cssSecondsPer100m
    thresholdPaceSecondsPerKm =
      try container.decodeIfPresent(Int.self, forKey: .thresholdPaceSecondsPerKm)
      ?? defaults.thresholdPaceSecondsPerKm
    marathonPaceSecondsPerKm =
      try container.decodeIfPresent(Int.self, forKey: .marathonPaceSecondsPerKm) ?? defaults.marathonPaceSecondsPerKm
    racePaceSecondsPerKm =
      try container.decodeIfPresent(Int.self, forKey: .racePaceSecondsPerKm) ?? defaults.racePaceSecondsPerKm
    raceBikeSpeedKmh =
      try container.decodeIfPresent(Double.self, forKey: .raceBikeSpeedKmh) ?? defaults.raceBikeSpeedKmh
  }
}

public enum TrainingPhase: String, Codable, Sendable, CaseIterable {
  case grundlage = "Grundlage"
  case marathonAufbau = "Marathon-Aufbau"
  case marathonTaper = "Marathon-Taper"
  case regeneration = "Regeneration"
  case almereAufbau = "Almere-Aufbau"
  case almerePeak = "Almere-Peak"
  case almereTaper = "Almere-Taper"

  public var focus: String {
    switch self {
    case .grundlage:
      "aerobe Basis, Sweet-Spot-Progression auf Zwift, CSS-Schwimmen, Z2-Lauf bis 90 min verlängern"
    case .marathonAufbau:
      "Longrun von 16 auf 32 km, Schwelle und Marathontempo im Wechsel, Rad und Schwimmen halten"
    case .marathonTaper: "Umfang -25/-40/-60 %, Tempo halten, Rennverpflegung festlegen"
    case .regeneration: "2 Wochen ohne Lauftempo, lockere Bewegung, Erholung vom Marathon"
    case .almereAufbau:
      "Rad wird Priorität (Almere: flach und windig – Aeroposition, gleichmäßige Watt): lange Ausfahrten mit "
        + "Renntempo und Koppellauf, Freiwasser"
    case .almerePeak: "Rennsimulation 94 km, Formtest, höchste spezifische Belastung"
    case .almereTaper: "Volumen -40 bis -60 %, Intensität und Häufigkeit halten, Rennwoche"
    }
  }

  public var next: TrainingPhase? {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
    return all[index + 1]
  }
}

public struct PhaseSpan: Equatable, Sendable {
  public let phase: TrainingPhase
  public let start: CalendarDay
  public let end: CalendarDay
}

public struct SportTarget: Equatable, Sendable {
  public let sport: GarminActivity.Sport
  public let label: String
  public let minimum: Int
  public let maximum: Int
  public let detail: String
}

public struct TargetProgress: Equatable, Sendable {
  public let target: SportTarget
  public let done: Int

  public var percent: Int {
    target.minimum == 0 ? 100 : min(100, Int((Double(done) / Double(target.minimum) * 100).rounded()))
  }
}

/// Fester Punkt der Musterwoche (z. B. „Push (Home-Gym)“ am Montag).
public struct TemplateItem: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case strength, swimOrLegs, bike, run, optional
  }

  public let kind: Kind
  public var text: String
  public var done = false
}

/// Kurzplan einer Phase je Disziplin.
public struct PhasePlanText: Equatable, Sendable {
  public let run: String
  public let swim: String
  public let bike: String
  public let strength: String

  /// Kompakter Plantext für KI-Prompts (wie `phase_detail_text` im Altbestand).
  public var promptText: String {
    "Lauf: \(run). Schwimmen: \(swim). Rad (Zwift): \(bike). Kraft: \(strength)."
  }
}

/// Planzustand für einen Tag: Phase, heutige Fixpunkte, was diese Woche noch offen ist, Soll/Ist.
public struct PlanState: Equatable, Sendable {
  public let today: CalendarDay
  public let weekday: String
  public let phase: TrainingPhase
  public let phaseEnd: CalendarDay
  public let nextPhase: TrainingPhase?
  public let daysToRace: Int
  public let daysToMarathon: Int
  public let todayFixed: [TemplateItem]
  public let weekOpen: [String]
  public let daysLeftInWeek: Int
  public let targets: [TargetProgress]
  public let plan: PhasePlanText
  public let phases: [PhaseSpan]
}

/// Portierung von `garmin_ai_coach/plan.py`: einzige Quelle für Phasen, Wochen-Soll und Musterwoche.
public enum SeasonPlan {
  public static let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
  /// Taper Almere 14 Tage: Volumenreduktion um 41–60 % bei gleicher Intensität über 8–14 Tage
  /// (Bosquet et al. 2007; Wang et al. 2023, PLOS One, doi:10.1371/journal.pone.0282838).
  public static let taperDays = 14
  public static let marathonTaperDays = 21
  public static let regenerationDays = 14
  public static let peakDays = 21

  public static func phaseBounds(_ config: SeasonConfig) -> [PhaseSpan] {
    let marathonTaperStart = config.marathonDate.adding(days: -(marathonTaperDays - 1))
    let regenerationEnd = config.marathonDate.adding(days: regenerationDays)
    // Taper beginnt am Montag der vorletzten Rennwoche (Rennen Sa 11.09. → Taper ab Mo 30.08.).
    let raceMonday = config.mainRaceDate.adding(days: -config.mainRaceDate.weekdayIndex)
    let taperStart = raceMonday.adding(days: -(taperDays - 7))
    let peakStart = taperStart.adding(days: -peakDays)
    return [
      PhaseSpan(phase: .grundlage, start: config.baseStart, end: config.marathonBlockStart.adding(days: -1)),
      PhaseSpan(phase: .marathonAufbau, start: config.marathonBlockStart, end: marathonTaperStart.adding(days: -1)),
      PhaseSpan(phase: .marathonTaper, start: marathonTaperStart, end: config.marathonDate),
      PhaseSpan(phase: .regeneration, start: config.marathonDate.adding(days: 1), end: regenerationEnd),
      PhaseSpan(phase: .almereAufbau, start: regenerationEnd.adding(days: 1), end: peakStart.adding(days: -1)),
      PhaseSpan(phase: .almerePeak, start: peakStart, end: taperStart.adding(days: -1)),
      PhaseSpan(phase: .almereTaper, start: taperStart, end: config.mainRaceDate),
    ]
  }

  public static func phase(on day: CalendarDay, config: SeasonConfig) -> TrainingPhase {
    if let span = phaseBounds(config).first(where: { $0.start <= day && day <= $0.end }) { return span.phase }
    return day > config.mainRaceDate ? .almereTaper : .grundlage
  }

  public static func targets(for phase: TrainingPhase) -> [SportTarget] {
    let swim = SportTarget(sport: .swim, label: "Schwimmen", minimum: 1, maximum: 1, detail: "")
    let strength = SportTarget(
      sport: .strength, label: "Kraft", minimum: 4, maximum: 4,
      detail: "1x Beine + 3x Home-Gym (Push, Pull, Push+Pull)")
    func run(_ minimum: Int, _ maximum: Int, _ detail: String) -> SportTarget {
      SportTarget(sport: .run, label: "Laufen", minimum: minimum, maximum: maximum, detail: detail)
    }
    func bike(_ minimum: Int, _ maximum: Int, _ detail: String) -> SportTarget {
      SportTarget(sport: .bike, label: "Rad", minimum: minimum, maximum: maximum, detail: detail)
    }
    func strengthTarget(_ minimum: Int, _ maximum: Int, _ detail: String) -> SportTarget {
      SportTarget(sport: .strength, label: "Kraft", minimum: minimum, maximum: maximum, detail: detail)
    }
    switch phase {
    case .grundlage:
      return [
        swim, run(2, 2, "1x Zone 2, 1x Schwelle/Intervall im Wechsel"), strength,
        bike(1, 2, "1x Zwift-Intervall, optional 1x locker"),
      ]
    case .marathonAufbau:
      return [swim, run(3, 3, "Qualität, locker, Longrun"), strength, bike(1, 1, "1x Zwift")]
    case .marathonTaper:
      return [
        swim, run(3, 3, "kürzer, Tempo halten"), strengthTarget(2, 4, "Beine nur bis 10 Tage vor dem Rennen"),
        bike(0, 1, "kurz und locker"),
      ]
    case .regeneration:
      return [
        SportTarget(sport: .swim, label: "Schwimmen", minimum: 0, maximum: 1, detail: ""),
        run(0, 2, "nur sehr locker"), strengthTarget(0, 3, "leicht"), bike(0, 2, "locker"),
      ]
    case .almereAufbau:
      return [
        swim, run(2, 2, "1x Qualität, 1x Zone 2 (+ Koppellauf)"), strength,
        bike(2, 2, "Zwift-Intervall + lange Ausfahrt"),
      ]
    case .almerePeak:
      return [
        swim, run(2, 2, "1x Qualität, 1x Zone 2 (+ Koppellauf)"),
        strengthTarget(2, 4, "Erhalt, 1-2 Sätze pro Übung"), bike(2, 2, "Renntempo + Rennsimulation"),
      ]
    case .almereTaper:
      return [
        swim, run(2, 2, "kurz mit Renntempo"), strengthTarget(0, 2, "letzte Einheit ca. 5 Tage vor dem Rennen"),
        bike(1, 2, "kurz mit Renntempo"),
      ]
    }
  }

  /// Musterwoche (Stand 14.10.2026): Mo Push · Di/Do Schwimmen und Beine · Mi Pull · Fr Push+Pull ·
  /// Wochenende Zwift bzw. lange Einheiten. Läufe ohne festen Tag erscheinen über „offen“.
  public static func template(for phase: TrainingPhase, weekday: Int) -> [TemplateItem] {
    if phase == .regeneration { return [TemplateItem(kind: .optional, text: "Regeneration: nur locker, nach Gefühl")] }
    switch weekday {
    case 0: return [TemplateItem(kind: .strength, text: "Push (Home-Gym)")]
    case 1:
      return [
        TemplateItem(
          kind: .swimOrLegs, text: "Schwimmen oder Beine vor der Arbeit (das andere am Donnerstag)")
      ]
    case 2: return [TemplateItem(kind: .strength, text: "Pull (Home-Gym)")]
    case 3:
      return [
        TemplateItem(
          kind: .swimOrLegs, text: "Schwimmen oder Beine vor der Arbeit (was am Dienstag nicht dran war)")
      ]
    case 4: return [TemplateItem(kind: .strength, text: "Push + Pull kombiniert (Home-Gym)")]
    default: break
    }
    let saturday = weekday == 5
    switch phase {
    case .marathonAufbau, .marathonTaper:
      return saturday
        ? [TemplateItem(kind: .bike, text: "Zwift oder Longrun (auf Sa/So verteilen)")]
        : [TemplateItem(kind: .run, text: "Longrun oder Zwift (was Samstag nicht dran war)")]
    case .almereAufbau, .almerePeak, .almereTaper:
      return saturday
        ? [TemplateItem(kind: .bike, text: "Lange Radeinheit + Koppellauf (Sa oder So)")]
        : [TemplateItem(kind: .bike, text: "Lange Radeinheit, falls Samstag nicht geklappt hat")]
    case .grundlage, .regeneration:
      return saturday
        ? [TemplateItem(kind: .bike, text: "Zwift-Einheit (Sa oder So)")]
        : [TemplateItem(kind: .bike, text: "Zwift-Einheit, falls Samstag nicht geklappt hat")]
    }
  }

  public static func testValuesText(_ config: SeasonConfig) -> String {
    let pace = TestPaces(config)
    return "Testwerte: FTP \(config.ftpWatts) W (Zwift), CSS \(pace.swim()) /100 m, Lauf-Schwellenpace "
      + "\(pace.run()) /km, lockere Läufe \(pace.run(65))–\(pace.run(100)) /km bzw. HF Zone 2, Marathon-Zielpace "
      + "\(GermanFormat.minutesSeconds(config.marathonPaceSecondsPerKm)) /km, Renn-Zielwatt Almere "
      + "\(pace.watts(75))–\(pace.watts(78)) W"
  }

  public static func planText(for phase: TrainingPhase, config: SeasonConfig) -> PhasePlanText {
    PhasePlanTexts.text(for: phase, pace: TestPaces(config))
  }

  public static func state(today: CalendarDay, config: SeasonConfig, week: WeeklyVolume) -> PlanState {
    let phase = Self.phase(on: today, config: config)
    let bounds = phaseBounds(config)
    let targets = Self.targets(for: phase)
    let progress = targets.map { TargetProgress(target: $0, done: week.sessions[$0.sport] ?? 0) }

    var open: [String] = []
    for item in progress where item.done < item.target.minimum {
      let missing = item.target.minimum - item.done
      let detail = item.target.sport == .run && !item.target.detail.isEmpty ? " (\(item.target.detail))" : ""
      open.append("\(missing)× \(item.target.label)\(detail)")
    }

    let weekday = today.weekdayIndex
    let bikeMinimum = max(targets.first { $0.sport == .bike }?.minimum ?? 1, 1)
    // Wochenende: Ist das Rad-Soll schon erreicht, ist die Ersatzeinheit hinfällig (sonst verordnete die
    // KI-Notiz sie sonntags erneut, Befund 18.10.2026).
    let fixed = template(for: phase, weekday: weekday).map { item -> TemplateItem in
      var item = item
      if item.kind == .bike, weekday >= 5, (week.sessions[.bike] ?? 0) >= bikeMinimum {
        item.done = true
        item.text += " – diese Woche schon erledigt"
      }
      return item
    }

    return PlanState(
      today: today,
      weekday: weekdayNames[weekday],
      phase: phase,
      phaseEnd: bounds.first { $0.phase == phase }?.end ?? config.mainRaceDate,
      nextPhase: phase.next,
      daysToRace: today.days(until: config.mainRaceDate),
      daysToMarathon: today.days(until: config.marathonDate),
      todayFixed: fixed,
      weekOpen: open,
      daysLeftInWeek: 6 - weekday,
      targets: progress,
      plan: planText(for: phase, config: config),
      phases: bounds
    )
  }
}

/// Wochenvolumen je Disziplin (Kalenderwoche Mo–So).
public struct WeeklyVolume: Equatable, Sendable {
  public var sessions: [GarminActivity.Sport: Int] = [:]
  public var kilometers: [GarminActivity.Sport: Double] = [:]
  public var minutes: [GarminActivity.Sport: Double] = [:]

  public init() {}

  /// Wie `_window_totals` im Altbestand. Rad ohne Distanz zählt nicht: Neben der Zwift-Fahrt läuft oft eine
  /// zweite Aufzeichnung auf der Uhr („Indoor Radfahren“ ohne km), die sonst doppelt zählen würde.
  public init(activities: [GarminActivity], weekContaining day: CalendarDay) {
    let monday = day.adding(days: -day.weekdayIndex)
    let sunday = monday.adding(days: 6)
    for activity in activities {
      guard let activityDay = activity.day, monday <= activityDay, activityDay <= sunday else { continue }
      let sport = activity.sport
      guard sport != .other else { continue }
      let kilometers = (activity.distanceMeters ?? 0) / 1000
      if sport == .bike, kilometers <= 0 { continue }
      sessions[sport, default: 0] += 1
      self.kilometers[sport, default: 0] += kilometers
      minutes[sport, default: 0] += (activity.durationSeconds ?? 0) / 60
    }
  }
}

extension CalendarDay {
  /// Montag = 0 … Sonntag = 6.
  public var weekdayIndex: Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let weekday = calendar.component(.weekday, from: referenceDate)  // Sonntag = 1
    return (weekday + 5) % 7
  }
}

/// Watt- und Pace-Angaben aus den Testwerten.
struct TestPaces {
  let config: SeasonConfig

  init(_ config: SeasonConfig) {
    self.config = config
  }

  /// Watt bei `percent` % der FTP.
  func watts(_ percent: Double) -> Int {
    Int((Double(config.ftpWatts) * percent / 100).rounded())
  }

  func swim(_ offset: Int = 0) -> String {
    GermanFormat.minutesSeconds(config.cssSecondsPer100m + offset)
  }

  func run(_ offset: Int = 0) -> String {
    GermanFormat.minutesSeconds(config.thresholdPaceSecondsPerKm + offset)
  }

  var marathon: String {
    GermanFormat.minutesSeconds(config.marathonPaceSecondsPerKm)
  }
}
