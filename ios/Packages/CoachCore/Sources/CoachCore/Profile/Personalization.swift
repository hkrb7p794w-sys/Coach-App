import Foundation

/// Trainingsziele für Haupt- und Nebenziele.
public enum TrainingGoal: String, Codable, CaseIterable, Sendable, Identifiable {
  case muscleGain, fatLoss, strength, endurance, generalFitness, recovery, health, competition

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .muscleGain: "Muskelaufbau"
    case .fatLoss: "Fettabbau"
    case .strength: "Kraftsteigerung"
    case .endurance: "Ausdauer verbessern"
    case .generalFitness: "Allgemeine Fitness"
    case .recovery: "Bessere Regeneration"
    case .health: "Gesundheit"
    case .competition: "Wettkampfvorbereitung"
    }
  }

  public var symbol: String {
    switch self {
    case .muscleGain: "dumbbell.fill"
    case .fatLoss: "flame.fill"
    case .strength: "figure.strengthtraining.traditional"
    case .endurance: "figure.run"
    case .generalFitness: "figure.mixed.cardio"
    case .recovery: "bed.double.fill"
    case .health: "heart.fill"
    case .competition: "flag.checkered"
    }
  }

  /// Was die App daraus macht (im Onboarding unter dem Ziel).
  public var effect: String {
    switch self {
    case .muscleGain: "Mehr Krafteinheiten, Fortschritt nach Volumen, leichter Kalorienüberschuss."
    case .fatLoss: "Moderates Defizit mit viel Protein, Kraft zum Muskelerhalt."
    case .strength: "Schwere Grundübungen, Fortschritt nach Gewicht, genug Pausen."
    case .endurance: "Mehr Ausdauereinheiten, überwiegend locker, Fortschritt nach Pace und Puls."
    case .generalFitness: "Ausgewogener Mix aus Kraft und Ausdauer."
    case .recovery: "Vorsichtigere Steigerung, Schlaf und Erholung stehen vorne."
    case .health: "Regelmäßigkeit vor Leistung, Ruhepuls und Schlaf im Blick."
    case .competition: "Plan auf das Rennen ausgerichtet, Steigerung und Tapering."
    }
  }
}

/// Bereiche, die der Person besonders wichtig sind. Sie steuern Reihenfolge und Gewichtung, nicht die Regeln selbst.
public enum FocusArea: String, Codable, CaseIterable, Sendable, Identifiable {
  case muscle, endurance, bodyComposition, sleep, recovery, nutrition, performance, health

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .muscle: "Muskelaufbau"
    case .endurance: "Ausdauer"
    case .bodyComposition: "Körperkomposition"
    case .sleep: "Schlaf"
    case .recovery: "Recovery"
    case .nutrition: "Ernährung"
    case .performance: "Leistungssteigerung"
    case .health: "Gesundheit"
    }
  }

  public var symbol: String {
    switch self {
    case .muscle: "dumbbell"
    case .endurance: "figure.run"
    case .bodyComposition: "scalemass"
    case .sleep: "moon.zzz"
    case .recovery: "battery.75percent"
    case .nutrition: "fork.knife"
    case .performance: "chart.line.uptrend.xyaxis"
    case .health: "heart"
    }
  }
}

/// Fitness-Tracker der Person (aus dem Onboarding; ändert sich in Einstellungen › Datenquellen).
public struct TrackerSetup: Codable, Equatable, Hashable, Sendable {
  /// `nil` = nicht beantwortet (übersprungen).
  public var usesTracker: Bool?
  public var providers: [DataProvider]

  public init(usesTracker: Bool? = nil, providers: [DataProvider] = []) {
    self.usesTracker = usesTracker
    self.providers = providers
  }
}

/// Ziele und Prioritäten zu einem Zeitpunkt. Änderungen gelten ab `since`; ältere Stände bleiben im Verlauf, damit
/// Auswertungen früherer Zeiträume nicht nachträglich anders aussehen.
public struct PersonalGoals: Codable, Equatable, Hashable, Sendable {
  public var primary: TrainingGoal
  /// Höchstens `maxSecondary`, ohne das Hauptziel.
  public var secondary: [TrainingGoal]
  /// Wichtigste zuerst, höchstens `maxPriorities`.
  public var priorities: [FocusArea]
  public var since: CalendarDay

  public static let maxSecondary = 2
  public static let maxPriorities = 3

  public init(
    primary: TrainingGoal, secondary: [TrainingGoal] = [], priorities: [FocusArea] = [], since: CalendarDay
  ) {
    self.primary = primary
    self.since = since
    var seen: Set<TrainingGoal> = [primary]
    self.secondary = Array(secondary.filter { seen.insert($0).inserted }.prefix(Self.maxSecondary))
    var seenAreas = Set<FocusArea>()
    self.priorities = Array(priorities.filter { seenAreas.insert($0).inserted }.prefix(Self.maxPriorities))
  }

  public var all: [TrainingGoal] { [primary] + secondary }

  public func has(_ goal: TrainingGoal) -> Bool { all.contains(goal) }

  /// Prioritäten, ohne Angabe aus den Zielen abgeleitet (sinnvoller Standard).
  public var effectivePriorities: [FocusArea] {
    priorities.isEmpty ? Personalization.defaultPriorities(for: all) : priorities
  }

  private enum CodingKeys: String, CodingKey { case primary, secondary, priorities, since }

  /// Tolerant: unbekannte Ziele oder Prioritäten (neuere Version) werden übersprungen.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let primary = try container.decode(TrainingGoal.self, forKey: .primary)
    let secondary = ((try? container.decodeIfPresent([String].self, forKey: .secondary)) ?? [])
      .compactMap(TrainingGoal.init(rawValue:))
    let priorities = ((try? container.decodeIfPresent([String].self, forKey: .priorities)) ?? [])
      .compactMap(FocusArea.init(rawValue:))
    let since =
      (try? container.decodeIfPresent(CalendarDay.self, forKey: .since)) ?? CalendarDay(year: 2000, month: 1, day: 1)
    self.init(primary: primary, secondary: secondary, priorities: priorities, since: since)
  }
}

/// Eine Stelle für alles, was aus Zielen und Prioritäten folgt. Regeln entscheiden, die KI formuliert: Die KI
/// bekommt Ziele und Prioritäten als Kontext; was die App selbst ändert (Plan, Belastungsgrenze, Reihenfolge), steht
/// hier und ist getestet.
public enum Personalization {
  /// Ziele aus dem bisherigen Einzelziel (`FitnessGoal`) und einem Wettkampf – für Profile von vor Paket 6.
  public static func derived(from profile: UserProfile, since: CalendarDay) -> PersonalGoals {
    if profile.mode == .season {
      return PersonalGoals(
        primary: .competition, secondary: [.endurance, .strength], priorities: [.performance, .endurance, .recovery],
        since: since)
    }
    var secondary: [TrainingGoal] = []
    let primary: TrainingGoal
    switch profile.goal {
    case .loseWeight: primary = .fatLoss
    case .loseAndBuild:
      primary = .fatLoss
      secondary = [.muscleGain]
    case .buildMuscle, .gainWeight: primary = .muscleGain
    case .improveFitness: primary = .endurance
    case .maintain: primary = .generalFitness
    }
    if profile.event != nil {
      secondary.insert(primary, at: 0)
      return PersonalGoals(primary: .competition, secondary: secondary, since: since)
    }
    return PersonalGoals(primary: primary, secondary: secondary, since: since)
  }

  /// Richtung für Ernährung und Gewicht (`FitnessGoal`, steuert Kalorienziel und Schutzgrenzen) aus den Zielen.
  public static func fitnessGoal(for goals: PersonalGoals) -> FitnessGoal {
    let builds = goals.has(.muscleGain) || goals.has(.strength)
    switch goals.primary {
    case .fatLoss: return builds ? .loseAndBuild : .loseWeight
    case .muscleGain: return .buildMuscle
    case .strength: return goals.has(.fatLoss) ? .loseAndBuild : .buildMuscle
    case .endurance, .competition: return goals.has(.fatLoss) ? .loseWeight : .improveFitness
    case .generalFitness: return goals.has(.fatLoss) ? .loseWeight : .maintain
    case .recovery, .health: return goals.has(.fatLoss) ? .loseWeight : .maintain
    }
  }

  /// Standard-Prioritäten zu den Zielen (wenn die Person keine wählt).
  public static func defaultPriorities(for goals: [TrainingGoal]) -> [FocusArea] {
    var result: [FocusArea] = []
    func add(_ areas: FocusArea...) {
      for area in areas where !result.contains(area) { result.append(area) }
    }
    for goal in goals {
      switch goal {
      case .muscleGain: add(.muscle, .nutrition)
      case .fatLoss: add(.bodyComposition, .nutrition)
      case .strength: add(.muscle, .performance)
      case .endurance: add(.endurance, .recovery)
      case .generalFitness: add(.health, .endurance)
      case .recovery: add(.recovery, .sleep)
      case .health: add(.health, .sleep)
      case .competition: add(.performance, .recovery)
      }
    }
    return Array(result.prefix(PersonalGoals.maxPriorities))
  }

  // MARK: - Trainingsplanung

  /// Höchste Steigerung der Wochenbelastung, ab der gewarnt wird: vorsichtiger bei Regeneration oder Gesundheit als
  /// Haupt- oder Prioritätsziel (20 statt 30 %).
  public static func maxLoadIncrease(_ goals: PersonalGoals) -> Double {
    let careful =
      goals.primary == .recovery || goals.primary == .health
      || goals.effectivePriorities.prefix(2).contains(where: { $0 == .recovery || $0 == .health })
    return careful ? 0.20 : WeekLoad.maxIncrease
  }

  /// Gewünschte Einheiten je Sportart, angepasst an Haupt- und Nebenziele (nach `SchedulePlanner.wantedCounts`).
  public static func adjustCounts(
    _ counts: [TrainingSport: Int], goals: PersonalGoals, profile: UserProfile
  ) -> [TrainingSport: Int] {
    var result = counts
    let beginner = ScheduleCheck.overallLevel(profile) == .beginner
    func atLeast(_ sport: TrainingSport, _ count: Int) {
      guard profile.trains(sport) else { return }
      result[sport] = max(result[sport] ?? 0, count)
    }
    switch goals.primary {
    case .muscleGain, .strength: atLeast(.strength, beginner ? 3 : 4)
    case .endurance:
      for sport in profile.sports where sport.isEndurance { atLeast(sport, beginner ? 2 : 3) }
    default: break
    }
    if goals.secondary.contains(.muscleGain) || goals.secondary.contains(.strength) { atLeast(.strength, 2) }
    if goals.secondary.contains(.endurance) {
      if let main = profile.sports.first(where: \.isEndurance) { atLeast(main, 2) }
    }
    if goals.primary == .recovery || goals.primary == .health {
      // Regelmäßig, aber nicht viel: höchstens 2 je Sportart.
      for (sport, count) in result { result[sport] = min(count, 2) }
    }
    return result
  }

  // MARK: - Darstellung

  /// Reihenfolge der Health-Widgets für ein neues bzw. nicht angepasstes Dashboard.
  public static func healthWidgets(_ goals: PersonalGoals) -> [HealthWidget] {
    var order: [HealthWidget] = []
    func add(_ widgets: HealthWidget...) {
      for widget in widgets where !order.contains(widget) { order.append(widget) }
    }
    for area in goals.effectivePriorities {
      switch area {
      case .sleep: add(.sleep, .hrv)
      case .recovery: add(.bodyBattery, .hrv, .recoveryTime)
      case .health: add(.restingHeartRate, .steps)
      case .endurance: add(.vo2Max, .trainingLoad)
      case .performance: add(.trainingLoad, .vo2Max)
      case .bodyComposition: add(.weight, .activeCalories)
      case .muscle: add(.weight, .trainingLoad)
      case .nutrition: add(.weight, .restingCalories)
      }
    }
    for widget in HealthDashboard.standard { add(widget) }
    return order
  }

  /// Empfehlungs-Themen in der Reihenfolge der Prioritäten (für den Reiter „AI“).
  public static func insightTopics(_ goals: PersonalGoals) -> [InsightTopic] {
    var order: [InsightTopic] = []
    func add(_ topics: InsightTopic...) {
      for topic in topics where !order.contains(topic) { order.append(topic) }
    }
    for area in goals.effectivePriorities {
      switch area {
      case .muscle: add(.training, .progress, .stagnation)
      case .endurance: add(.training, .performance)
      case .bodyComposition: add(.nutrition, .progress)
      case .sleep, .recovery, .health: add(.recovery)
      case .nutrition: add(.nutrition)
      case .performance: add(.performance, .progress)
      }
    }
    return order
  }

  // MARK: - KI-Kontext

  /// Zeilen für den KI-Kontext (Chat, Analyse, Tagesnotiz): Ziele, Prioritäten und worauf Empfehlungen achten sollen.
  public static func contextLines(_ goals: PersonalGoals) -> [String] {
    var lines = [
      "Hauptziel: \(goals.primary.label)"
        + (goals.secondary.isEmpty ? "" : "; Nebenziele: \(goals.secondary.map(\.label).joined(separator: ", "))")
        + ".",
      "Prioritäten der Person: \(goals.effectivePriorities.map(\.label).joined(separator: ", ")).",
    ]
    lines.append("Empfehlungen daran ausrichten: \(guidance(goals.primary))")
    return lines
  }

  static func guidance(_ goal: TrainingGoal) -> String {
    switch goal {
    case .muscleGain:
      "Kraftvolumen und Progression bewerten, Protein und leichter Überschuss; Ausdauer nur ergänzend."
    case .fatLoss: "Muskelerhalt durch Kraft und Protein, moderates Defizit; kein Crash-Defizit."
    case .strength: "Fortschritt der Grundübungen nach Gewicht, ausreichend Pausen zwischen schweren Einheiten."
    case .endurance: "Umfang überwiegend locker (Zone 2), wenige harte Einheiten; Pace und Puls im Verlauf."
    case .generalFitness: "Ausgewogenheit und Regelmäßigkeit vor Höchstleistung."
    case .recovery: "Schlaf, HRV und Ruhepuls zuerst; Belastung nur vorsichtig steigern."
    case .health: "Regelmäßige moderate Bewegung, Schlaf und Ruhepuls; keine Leistungsziele erzwingen."
    case .competition: "Auf das Rennen hin periodisieren (Aufbau, Spitze, Tapering); Schlüsseleinheiten schützen."
    }
  }
}

extension UserProfile {
  /// Aktuelle Ziele; ältere Profile ohne Angabe bekommen abgeleitete Ziele.
  public func effectiveGoals(today: CalendarDay) -> PersonalGoals {
    goals ?? Personalization.derived(from: self, since: today)
  }

  /// Ziele, die an einem Tag galten (für Auswertungen früherer Zeiträume).
  public func goals(on day: CalendarDay) -> PersonalGoals {
    let history = (goalHistory + (goals.map { [$0] } ?? [])).sorted { $0.since < $1.since }
    return history.last { $0.since <= day } ?? history.first ?? Personalization.derived(from: self, since: day)
  }

  /// Neue Ziele ab `day`: Der bisherige Stand wandert in den Verlauf (gleicher Tag wird ersetzt).
  public mutating func updateGoals(_ new: PersonalGoals, on day: CalendarDay) {
    var updated = new
    updated.since = day
    // Ohne gespeicherte Ziele galt bisher das Abgeleitete – seit jeher (sonst sähen alte Zeiträume die neuen Ziele).
    let current = goals ?? Personalization.derived(from: self, since: CalendarDay(year: 2000, month: 1, day: 1))
    if current != updated {
      goalHistory.removeAll { $0.since >= day }
      if current.since < day { goalHistory.append(current) }
    }
    goals = updated
    goal = Personalization.fitnessGoal(for: updated)
  }
}
