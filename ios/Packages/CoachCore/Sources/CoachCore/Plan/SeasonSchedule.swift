import Foundation

/// Ein Schritt einer Schwimmeinheit (`swim_plan.json` im Altbestand), auch verschachtelt (Wiederholungen).
public struct SwimStep: Codable, Equatable, Sendable {
  /// `warmup`, `int`, `rest`, `rec`, `rep`, `cool`
  public var t: String
  /// Meter
  public var m: Int?
  /// Sekunden (Pause)
  public var s: Int?
  /// Wiederholungen bei `rep`
  public var n: Int?
  public var note: String?
  /// Tempo relativ zur CSS in Sekunden je 100 m (untere/obere Grenze).
  public var lo: Int?
  public var hi: Int?
  /// Ausrüstung, z. B. `pull_buoy`
  public var eq: String?
  public var steps: [SwimStep]?
}

/// Eine Woche des Saisonplans (Felder wie in `coach_plan.jinja`).
public struct PlanWeek: Codable, Equatable, Sendable, Identifiable {
  public var w: String
  public var ph: String
  /// Hinweis zur Woche (z. B. „Entlastungswoche“)
  public var f: String
  /// Zwift-Einheit (Text mit Platzhaltern) und Kürzel
  public var z: String
  public var zc: String
  /// Optionale zweite Zwift-Einheit
  public var z2: String
  /// Schwimmeinheit und Name
  public var s: String
  public var sc: String
  /// Qualitätslauf und Name
  public var q: String
  public var qc: String
  /// Z2-Lauf
  public var e: String
  /// Longrun und Länge in km (0 = keiner)
  public var l: String
  public var lr: Double
  /// Wettkampfspezifischer Qualitätslauf/Longrun (zum Annehmen/Ablehnen) mit Alternative
  public var qw: Int?
  public var qa: String?
  public var qca: String?
  public var lw: Int?
  public var la: String?
  /// Schwimmschritte und Gesamtmeter (`swim_plan.json`)
  public var ss: [SwimStep]?
  public var sm: Int?

  public var id: String { w }
  public var monday: CalendarDay? { CalendarDay(iso: w) }
}

public struct PlanPhaseInfo: Codable, Equatable, Sendable {
  /// Musterwoche
  public var mw: String
  /// Priorität, wenn die Zeit knapp ist
  public var prio: String
}

public struct ZwiftWorkout: Codable, Equatable, Sendable, Identifiable {
  public var c: String
  public var n: String
  public var t: String
  public var id: String { c }
}

/// Der komplette Saisonplan aus dem Altbestand (48 Wochen, 12.10.2026–11.09.2027).
public struct SeasonSchedule: Codable, Equatable, Sendable {
  public var weeks: [PlanWeek]
  public var zw: [ZwiftWorkout]
  public var phases: [String: PlanPhaseInfo]

  public static func load() -> SeasonSchedule? {
    guard let url = Bundle.module.url(forResource: "season-plan", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(SeasonSchedule.self, from: data)
  }

  /// Woche, die `day` enthält (Plan-Wochen beginnen montags).
  public func week(containing day: CalendarDay) -> PlanWeek? {
    let monday = day.adding(days: -day.weekdayIndex)
    return weeks.first { $0.monday == monday }
  }

  public func index(of day: CalendarDay) -> Int? {
    let monday = day.adding(days: -day.weekdayIndex)
    return weeks.firstIndex { $0.monday == monday }
  }
}

/// Setzt die Testwerte in die Platzhalter ein, wie `coach_plan()` im Altbestand:
/// `§S±n§` CSS + n s/100 m, `§Wnn§` nn % FTP in Watt, `§T§` Schwelle, `§I§` Intervallband (Schwelle −23 bis
/// −18 s/km), `§E§` locker (Schwelle +65 bis +100 s/km), `§MP§` Marathonpace, `§R§` Renn-Laufpace.
public struct PlanTokens: Sendable {
  public let config: SeasonConfig

  public init(config: SeasonConfig) {
    self.config = config
  }

  public static func mmss(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  public var easyRange: String {
    "\(Self.mmss(config.thresholdPaceSecondsPerKm + 65))–\(Self.mmss(config.thresholdPaceSecondsPerKm + 100))"
  }

  public var intervalRange: String {
    "\(Self.mmss(config.thresholdPaceSecondsPerKm - 23))–\(Self.mmss(config.thresholdPaceSecondsPerKm - 18))"
  }

  public func watts(_ percent: Int) -> Int {
    Int((Double(config.ftpWatts) * Double(percent) / 100).rounded())
  }

  public func swimPace(_ offset: Int) -> String {
    Self.mmss(config.cssSecondsPer100m + offset)
  }

  public func fill(_ text: String) -> String {
    var result = ""
    var rest = Substring(text)
    while let start = rest.firstIndex(of: "§") {
      result += rest[..<start]
      let afterStart = rest.index(after: start)
      guard let end = rest[afterStart...].firstIndex(of: "§") else {
        rest = rest[start...]
        break
      }
      let token = String(rest[afterStart..<end])
      result += replacement(token) ?? "§\(token)§"
      rest = rest[rest.index(after: end)...]
    }
    return result + rest
  }

  func replacement(_ token: String) -> String? {
    switch token {
    case "T": return Self.mmss(config.thresholdPaceSecondsPerKm)
    case "I": return intervalRange
    case "E": return easyRange
    case "MP": return Self.mmss(config.marathonPaceSecondsPerKm)
    case "R": return Self.mmss(config.racePaceSecondsPerKm)
    default: break
    }
    if token.hasPrefix("S"), let offset = Int(token.dropFirst()) { return swimPace(offset) }
    if token.hasPrefix("W"), let percent = Int(token.dropFirst()) { return String(watts(percent)) }
    return nil
  }
}

/// Eine Einheit der Woche, fertig zum Anzeigen.
public struct PlannedUnit: Equatable, Sendable, Identifiable {
  public enum Kind: String, Sendable, CaseIterable {
    case bike, bikeOptional, swim, quality, easyRun, longRun, gym

    public var sport: GarminActivity.Sport {
      switch self {
      case .bike, .bikeOptional: .bike
      case .swim: .swim
      case .quality, .easyRun, .longRun: .run
      case .gym: .strength
      }
    }

    public var label: String {
      switch self {
      case .bike: "Rad (Zwift)"
      case .bikeOptional: "Rad optional"
      case .swim: "Schwimmen"
      case .quality: "Qualitätslauf"
      case .easyRun: "Lauf locker"
      case .longRun: "Longrun"
      case .gym: "Kraft"
      }
    }
  }

  /// Entscheidung zu einer Wettkampf-Einheit 🏁 (Marathon-/Renntempo).
  public enum Decision: String, Codable, Sendable {
    case open = "offen"
    case accepted = "angenommen"
    case rejected = "abgelehnt"
  }

  public var kind: Kind
  public var title: String
  public var detail: String
  /// Wettkampf-Einheit: lässt sich ablehnen (dann gilt die Alternative).
  public var isCompetition = false
  public var decision: Decision?
  public var alternative: String?
  public var swimSteps: [SwimStep] = []
  public var swimMeters: Int?
  /// Kürzel des Zwift-Workouts (`Z01` … `Z15`, `RAMP`)
  public var zwiftCode: String?
  public var gymWorkout: Workout?
  public var done = false
  public var id: String { "\(kind.rawValue)-\(title)" }

  /// Regeln aus `Evidence`, die diese Einheit begründen.
  public var evidenceIDs: [String] {
    switch kind {
    case .quality where title.contains("4×4"): ["run.4x4", "intensity.distribution"]
    case .quality, .longRun, .easyRun, .bike, .bikeOptional, .swim: ["intensity.distribution"]
    case .gym: ["strength.economy", "strength.interference", "gym.progression"]
    }
  }
}

/// Entscheidungen zu Wettkampf-Einheiten, Schlüssel `wk-lauf-<Montag>-q` bzw. `-l` (wie im Altbestand).
public typealias CompetitionDecisions = [String: PlannedUnit.Decision]

extension SeasonSchedule {
  public static func decisionKey(week: PlanWeek, kind: PlannedUnit.Kind) -> String {
    "wk-lauf-\(week.w)-\(kind == .longRun ? "l" : "q")"
  }

  /// Einheiten einer Woche in fester Reihenfolge, mit eingesetzten Testwerten.
  public func units(
    for week: PlanWeek, config: SeasonConfig, gym: GymPlan = .standard, decisions: CompetitionDecisions = [:]
  ) -> [PlannedUnit] {
    let tokens = PlanTokens(config: config)
    var units: [PlannedUnit] = []

    if !week.z.isEmpty {
      let (title, detail) = Self.split(tokens.fill(week.z), fallbackTitle: week.zc)
      var unit = PlannedUnit(kind: .bike, title: title, detail: detail)
      unit.zwiftCode = week.zc
      units.append(unit)
    }
    if !week.z2.isEmpty {
      units.append(PlannedUnit(kind: .bikeOptional, title: "Zweite Zwift-Einheit", detail: week.z2))
    }
    if !week.s.isEmpty {
      let (title, detail) = Self.split(tokens.fill(week.s), fallbackTitle: week.sc)
      var unit = PlannedUnit(kind: .swim, title: title, detail: detail)
      unit.swimSteps = week.ss ?? []
      unit.swimMeters = week.sm
      units.append(unit)
    }
    if !week.q.isEmpty {
      units.append(
        competitionAware(
          kind: .quality, text: week.q, isCompetition: week.qw != nil, alternative: week.qa, week: week,
          tokens: tokens, decisions: decisions))
    }
    if !week.e.isEmpty {
      units.append(PlannedUnit(kind: .easyRun, title: "Lauf Zone 2", detail: tokens.fill(week.e)))
    }
    if !week.l.isEmpty {
      units.append(
        competitionAware(
          kind: .longRun, text: week.l, isCompetition: week.lw != nil, alternative: week.la, week: week,
          tokens: tokens, decisions: decisions))
    }
    for key in ["push", "legs", "pull", "pp"] {
      guard let workout = gym.workout(key) else { continue }
      var unit = PlannedUnit(
        kind: .gym, title: workout.name, detail: workout.exercises.map(\.name).joined(separator: " · "))
      unit.gymWorkout = workout
      units.append(unit)
    }
    return units
  }

  /// „Name: Beschreibung“ → Titel und Detail.
  static func split(_ text: String, fallbackTitle: String) -> (String, String) {
    guard let colon = text.firstIndex(of: ":") else { return (fallbackTitle, text) }
    let title = text[..<colon].trimmingCharacters(in: .whitespaces)
    let detail = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    return (title.isEmpty ? fallbackTitle : title, detail)
  }

  private func competitionAware(
    kind: PlannedUnit.Kind, text: String, isCompetition: Bool, alternative: String?, week: PlanWeek,
    tokens: PlanTokens, decisions: CompetitionDecisions
  ) -> PlannedUnit {
    let decision = isCompetition ? decisions[Self.decisionKey(week: week, kind: kind)] ?? .open : nil
    let chosen = tokens.fill(decision == .rejected ? (alternative ?? text) : text)
    var title: String
    var detail: String
    if kind == .longRun {
      title = "Longrun" + (week.lr > 0 ? " \(GermanFormat.decimal(week.lr)) km" : "")
      detail = chosen
    } else {
      (title, detail) = Self.split(chosen, fallbackTitle: "Qualitätslauf")
    }
    if isCompetition, decision != .rejected { title = "🏁 " + title }
    var unit = PlannedUnit(kind: kind, title: title, detail: detail)
    unit.isCompetition = isCompetition
    unit.decision = decision
    unit.alternative = alternative.map(tokens.fill)
    return unit
  }
}

/// Erledigt-Status einer Woche: Garmin-Aktivitäten und eigene Krafteinheiten werden den Einheiten zugeordnet.
public enum PlanProgress {
  /// Longrun zählt ab 80 % der geplanten Länge; übrige Läufe füllen erst den Qualitätslauf, dann den lockeren Lauf.
  public static func mark(
    _ units: [PlannedUnit], week: PlanWeek, activities: [GarminActivity], gymDays: [CalendarDay]
  ) -> [PlannedUnit] {
    guard let monday = week.monday else { return units }
    let sunday = monday.adding(days: 6)
    let inWeek = activities.filter { activity in
      guard let day = activity.day else { return false }
      return monday <= day && day <= sunday
    }
    var runs = inWeek.filter { $0.sport == .run }.sorted { ($0.distanceMeters ?? 0) > ($1.distanceMeters ?? 0) }
    // Rad nur mit Distanz: Neben Zwift läuft oft eine zweite Aufzeichnung ohne km (Altbestand, 0.11.x).
    var bikes = inWeek.filter { $0.sport == .bike && ($0.distanceMeters ?? 0) > 0 }.count
    var swims = inWeek.filter { $0.sport == .swim }.count
    let strengthDays = Set(
      inWeek.filter { $0.sport == .strength }.compactMap(\.day) + gymDays.filter { monday <= $0 && $0 <= sunday })
    var gyms = strengthDays.count

    var result = units
    if let index = result.firstIndex(where: { $0.kind == .longRun }), let longest = runs.first,
      (longest.distanceMeters ?? 0) / 1000 >= week.lr * 0.8
    {
      result[index].done = true
      runs.removeFirst()
    }
    for index in result.indices where !result[index].done {
      switch result[index].kind {
      case .quality, .easyRun:
        if !runs.isEmpty {
          result[index].done = true
          runs.removeFirst()
        }
      case .bike, .bikeOptional:
        if bikes > 0 {
          result[index].done = true
          bikes -= 1
        }
      case .swim:
        if swims > 0 {
          result[index].done = true
          swims -= 1
        }
      case .gym:
        if gyms > 0 {
          result[index].done = true
          gyms -= 1
        }
      case .longRun:
        break
      }
    }
    return result
  }
}

/// Lesbare Schwimmschritte mit Tempo aus der CSS.
public enum SwimStepText {
  static let equipment = ["pull_buoy": "Pull-Buoy", "paddles": "Paddles", "fins": "Flossen", "snorkel": "Schnorchel"]

  public static func lines(_ steps: [SwimStep], tokens: PlanTokens, indent: Int = 0) -> [String] {
    steps.flatMap { step -> [String] in
      let prefix = String(repeating: "  ", count: indent)
      switch step.t {
      case "rep":
        let inner = lines(step.steps ?? [], tokens: tokens, indent: indent + 1)
        return ["\(prefix)\(step.n ?? 1)×"] + inner
      case "rest", "rec":
        return ["\(prefix)\(step.s.map { "\($0) s Pause" } ?? "Pause")"]
      default:
        var parts: [String] = []
        let label = ["warmup": "Ein", "cool": "Aus"][step.t]
        if let meters = step.m { parts.append([label, "\(meters) m"].compactMap { $0 }.joined(separator: " ")) }
        if let low = step.lo, let high = step.hi {
          parts.append(
            low == high
              ? "@ \(tokens.swimPace(low)) /100 m" : "@ \(tokens.swimPace(low))–\(tokens.swimPace(high)) /100 m")
        }
        if let note = step.note, !note.isEmpty { parts.append(note) }
        if let equipment = step.eq { parts.append("(\(Self.equipment[equipment] ?? equipment))") }
        return ["\(prefix)\(parts.joined(separator: " · "))"]
      }
    }
  }

  public static func equipment(in steps: [SwimStep]) -> [String] {
    var result: [String] = []
    func walk(_ steps: [SwimStep]) {
      for step in steps {
        if let item = step.eq.map({ Self.equipment[$0] ?? $0 }), !result.contains(item) { result.append(item) }
        walk(step.steps ?? [])
      }
    }
    walk(steps)
    return result
  }
}
