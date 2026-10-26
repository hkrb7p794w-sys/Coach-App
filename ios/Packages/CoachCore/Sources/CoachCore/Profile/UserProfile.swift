import Foundation

/// Sportarten, aus denen Nutzer:innen wählen.
public enum TrainingSport: String, Codable, CaseIterable, Sendable, Identifiable {
  case run, strength, bike, swim, other

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .run: "Laufen"
    case .strength: "Krafttraining"
    case .bike: "Radfahren"
    case .swim: "Schwimmen"
    case .other: "Anderes (Yoga, Wandern …)"
    }
  }

  public var symbol: String {
    switch self {
    case .run: "figure.run"
    case .strength: "dumbbell.fill"
    case .bike: "figure.outdoor.cycle"
    case .swim: "figure.pool.swim"
    case .other: "figure.yoga"
    }
  }

  public var garminSport: GarminActivity.Sport {
    switch self {
    case .run: .run
    case .strength: .strength
    case .bike: .bike
    case .swim: .swim
    case .other: .other
    }
  }

  /// Ausdauersportart (für Intensitätsverteilung und Ruhepuls-Ziel).
  public var isEndurance: Bool {
    self == .run || self == .bike || self == .swim
  }
}

/// Hauptziel. Aus ihm folgen Ernährungsziel, Trainingsverteilung und Hinweise.
public enum FitnessGoal: String, Codable, CaseIterable, Sendable, Identifiable {
  case loseWeight, loseAndBuild, buildMuscle, gainWeight, improveFitness, maintain

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .loseWeight: "Abnehmen"
    case .loseAndBuild: "Abnehmen und Muskeln aufbauen"
    case .buildMuscle: "Muskeln aufbauen"
    case .gainWeight: "Zunehmen"
    case .improveFitness: "Fitter werden"
    case .maintain: "Fit bleiben, Gewicht halten"
    }
  }

  public var detail: String {
    switch self {
    case .loseWeight: "Langsam und gesund Gewicht verlieren, Muskeln erhalten."
    case .loseAndBuild: "Körperfett senken und gleichzeitig Kraft aufbauen."
    case .buildMuscle: "Mehr Muskelmasse und Kraft mit leichtem Überschuss."
    case .gainWeight: "Gesund zunehmen, vor allem als Muskelmasse."
    case .improveFitness: "Ausdauer, Tempo oder Ruhepuls verbessern."
    case .maintain: "Das aktuelle Niveau halten und regelmäßig trainieren."
    }
  }

  public var symbol: String {
    switch self {
    case .loseWeight: "arrow.down.right.circle.fill"
    case .loseAndBuild: "arrow.triangle.2.circlepath.circle.fill"
    case .buildMuscle: "dumbbell.fill"
    case .gainWeight: "arrow.up.right.circle.fill"
    case .improveFitness: "heart.circle.fill"
    case .maintain: "equal.circle.fill"
    }
  }

  /// Ziele, die das Körpergewicht senken sollen.
  public var losesWeight: Bool { self == .loseWeight || self == .loseAndBuild }
  public var gainsWeight: Bool { self == .gainWeight || self == .buildMuscle }
}

public enum ExperienceLevel: String, Codable, CaseIterable, Sendable, Identifiable {
  case beginner, intermediate, advanced

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .beginner: "Einsteiger:in"
    case .intermediate: "Fortgeschritten"
    case .advanced: "Erfahren"
    }
  }

  public var detail: String {
    switch self {
    case .beginner: "Neu dabei oder nach langer Pause wieder eingestiegen."
    case .intermediate: "Seit über 6 Monaten regelmäßig dabei."
    case .advanced: "Seit Jahren strukturiert unterwegs."
    }
  }
}

public enum EventKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case run5k, run10k, halfMarathon, marathon, triathlon, other

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .run5k: "5-km-Lauf"
    case .run10k: "10-km-Lauf"
    case .halfMarathon: "Halbmarathon"
    case .marathon: "Marathon"
    case .triathlon: "Triathlon"
    case .other: "Anderer Wettkampf"
    }
  }

  public var distanceKilometers: Double? {
    switch self {
    case .run5k: 5
    case .run10k: 10
    case .halfMarathon: 21.0975
    case .marathon: 42.195
    case .triathlon, .other: nil
    }
  }

  public var isRunning: Bool { distanceKilometers != nil }
}

/// Ein Wettkampf oder Lauf, auf den sich jemand vorbereitet.
public struct EventGoal: Codable, Equatable, Hashable, Sendable {
  public var name: String
  public var date: CalendarDay
  public var kind: EventKind
  /// Zielzeit in Sekunden (optional).
  public var targetSeconds: Int?

  public init(name: String, date: CalendarDay, kind: EventKind, targetSeconds: Int? = nil) {
    self.name = name
    self.date = date
    self.kind = kind
    self.targetSeconds = targetSeconds
  }
}

/// Persönliche Verbesserungsziele ohne Wettkampf.
public struct ImprovementTargets: Codable, Equatable, Hashable, Sendable {
  /// Strecke, die am Stück gelaufen werden soll (km).
  public var runDistanceKilometers: Double?
  /// Ziel-Pace über diese Strecke (s/km).
  public var runPaceSecondsPerKilometer: Int?
  public var restingHeartRate: Int?
  public var targetWeightKilograms: Double?
  /// In wie vielen Wochen das Zielgewicht erreicht sein soll.
  public var weeksToTargetWeight: Int?

  public init(
    runDistanceKilometers: Double? = nil, runPaceSecondsPerKilometer: Int? = nil, restingHeartRate: Int? = nil,
    targetWeightKilograms: Double? = nil, weeksToTargetWeight: Int? = nil
  ) {
    self.runDistanceKilometers = runDistanceKilometers
    self.runPaceSecondsPerKilometer = runPaceSecondsPerKilometer
    self.restingHeartRate = restingHeartRate
    self.targetWeightKilograms = targetWeightKilograms
    self.weeksToTargetWeight = weeksToTargetWeight
  }

  public var isEmpty: Bool {
    runDistanceKilometers == nil && runPaceSecondsPerKilometer == nil && restingHeartRate == nil
      && targetWeightKilograms == nil
  }
}

/// Angaben, bei denen die App vorsichtiger ist oder zum Arztbesuch rät.
public enum HealthFlag: String, Codable, CaseIterable, Sendable, Identifiable {
  case pregnantOrPostpartum, eatingDisorder, medicalCondition, injury

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .pregnantOrPostpartum: "Schwanger oder nach der Geburt"
    case .eatingDisorder: "Essstörung (aktuell oder früher)"
    case .medicalCondition: "Herz-Kreislauf- oder andere ärztlich behandelte Erkrankung"
    case .injury: "Akute Verletzung oder Beschwerden"
    }
  }
}

/// Alles, was die App über die Person wissen muss, um sich anzupassen.
public struct UserProfile: Codable, Equatable, Hashable, Sendable {
  /// `season`: der bisherige Saisonplan (Triathlon Almere). `personal`: Plan aus Profil und Wochenplan.
  public enum Mode: String, Codable, Sendable {
    case season, personal
  }

  public var mode: Mode
  public var onboardingDone: Bool
  public var sports: [TrainingSport]
  public var goal: FitnessGoal
  /// `nil` = kein Wettkampf, sondern allgemeine Verbesserung.
  public var event: EventGoal?
  public var targets: ImprovementTargets
  /// Erfahrung je Sportart (Schlüssel: `TrainingSport.rawValue`).
  public var levels: [String: ExperienceLevel]
  public var schedule: WeekSchedule
  public var health: [HealthFlag]
  /// Selbstauskunft, wie viel aktuell gelaufen wird; ohne Angabe zählt Garmin.
  public var currentRunKilometersPerWeek: Double?

  public init(
    mode: Mode = .personal, onboardingDone: Bool = false, sports: [TrainingSport] = [.run, .strength],
    goal: FitnessGoal = .improveFitness, event: EventGoal? = nil, targets: ImprovementTargets = ImprovementTargets(),
    levels: [String: ExperienceLevel] = [:], schedule: WeekSchedule = WeekSchedule(), health: [HealthFlag] = [],
    currentRunKilometersPerWeek: Double? = nil
  ) {
    self.mode = mode
    self.onboardingDone = onboardingDone
    self.sports = sports
    self.goal = goal
    self.event = event
    self.targets = targets
    self.levels = levels
    self.schedule = schedule
    self.health = health
    self.currentRunKilometersPerWeek = currentRunKilometersPerWeek
  }

  public func level(for sport: TrainingSport) -> ExperienceLevel {
    levels[sport.rawValue] ?? .beginner
  }

  public mutating func setLevel(_ level: ExperienceLevel, for sport: TrainingSport) {
    levels[sport.rawValue] = level
  }

  public func trains(_ sport: TrainingSport) -> Bool {
    sports.contains(sport)
  }

  /// Höchste Erfahrung unter den gewählten Ausdauersportarten (Beginner, wenn keine gewählt).
  public var enduranceLevel: ExperienceLevel {
    let levels = sports.filter(\.isEndurance).map { level(for: $0) }
    return levels.max { Self.rank($0) < Self.rank($1) } ?? .beginner
  }

  static func rank(_ level: ExperienceLevel) -> Int {
    ExperienceLevel.allCases.firstIndex(of: level) ?? 0
  }

  /// Der bisherige Saisonplan als Profil (Triathlon Almere, alle vier Disziplinen).
  public static var seasonPlan: UserProfile {
    UserProfile(
      mode: .season, onboardingDone: true, sports: [.swim, .bike, .run, .strength], goal: .improveFitness,
      levels: [
        TrainingSport.swim.rawValue: .intermediate, TrainingSport.bike.rawValue: .intermediate,
        TrainingSport.run.rawValue: .advanced, TrainingSport.strength.rawValue: .advanced,
      ])
  }

  // MARK: - Tolerantes Dekodieren (neue Felder dürfen in älteren Daten fehlen)

  private enum CodingKeys: String, CodingKey {
    case mode, onboardingDone, sports, goal, event, targets, levels, schedule, health, currentRunKilometersPerWeek
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? .personal
    onboardingDone = (try? container.decodeIfPresent(Bool.self, forKey: .onboardingDone)) ?? false
    sports = (try? container.decodeIfPresent([TrainingSport].self, forKey: .sports)) ?? [.run, .strength]
    goal = (try? container.decodeIfPresent(FitnessGoal.self, forKey: .goal)) ?? .improveFitness
    event = try? container.decodeIfPresent(EventGoal.self, forKey: .event)
    targets = (try? container.decodeIfPresent(ImprovementTargets.self, forKey: .targets)) ?? ImprovementTargets()
    levels = (try? container.decodeIfPresent([String: ExperienceLevel].self, forKey: .levels)) ?? [:]
    schedule = (try? container.decodeIfPresent(WeekSchedule.self, forKey: .schedule)) ?? WeekSchedule()
    health = (try? container.decodeIfPresent([HealthFlag].self, forKey: .health)) ?? []
    currentRunKilometersPerWeek = try? container.decodeIfPresent(Double.self, forKey: .currentRunKilometersPerWeek)
  }
}

extension UserProfile {
  /// Entwurf für den Wechsel vom Saisonplan zu einem persönlichen Profil: Sportarten und Hauptrennen bleiben.
  public static func personalDraft(from config: SeasonConfig) -> UserProfile {
    var profile = UserProfile.seasonPlan
    profile.mode = .personal
    profile.onboardingDone = false
    profile.event = EventGoal(name: config.mainRaceName, date: config.mainRaceDate, kind: .triathlon)
    return profile
  }
}

/// Startzustand beim ersten Start nach einem Update.
public enum ProfileMigration {
  /// Wer die App schon mit Garmin-Daten oder Saison nutzt, behält den Saisonplan; alle anderen starten mit dem
  /// Einrichtungsassistenten.
  public static func initialProfile(hasExistingData: Bool) -> UserProfile {
    hasExistingData ? .seasonPlan : UserProfile()
  }
}
