import CoachCore
import Foundation
import Observation

/// Saison (Renntermine, Testwerte) und KI-Datenschutz, gespeichert in den UserDefaults.
@Observable
final class CoachSettings {
  static let seasonKey = "coach.season"
  static let privacyKey = "coach.privacy"
  static let nutritionKey = "coach.nutrition"
  static let heartRateKey = "coach.heartRate"
  static let competitionKey = "coach.competitionDecisions"
  static let testsKey = "coach.tests"
  static let profileKey = "coach.profile"
  static let adjustmentsKey = "coach.planAdjustments"
  static let remindersKey = "coach.reminders"
  static let companionKey = "coach.companion"
  static let leagueKey = "coach.league"
  static let gymKey = "coach.gym"
  static let recipesKey = "coach.recipes"
  static let weightsKey = "coach.weights"
  static let sleepKey = "coach.sleep"

  private let defaults: UserDefaults

  var season: SeasonConfig {
    didSet { save(season, forKey: Self.seasonKey) }
  }

  var privacy: PrivacyMode {
    didSet { defaults.set(privacy.rawValue, forKey: Self.privacyKey) }
  }

  var nutrition: NutritionSettings {
    didSet { save(nutrition, forKey: Self.nutritionKey) }
  }

  /// Entscheidungen zu Wettkampf-Einheiten 🏁 im Plan (`wk-lauf-<Montag>-q|l`).
  var competitionDecisions: CompetitionDecisions {
    didSet { save(competitionDecisions, forKey: Self.competitionKey) }
  }

  /// Eingetragene Testwerte mit Datum (Verläufe und Aktualität der Benchmarks).
  var tests: [TestRecord] {
    didSet { save(tests, forKey: Self.testsKey) }
  }

  /// Wer die App ist und was sie erreichen will: Sportarten, Ziel, Wochenplan. Bestehende Nutzer behalten den
  /// Saisonplan, neue starten mit dem Einrichtungsassistenten.
  var profile: UserProfile {
    didSet { save(profile, forKey: Self.profileKey) }
  }

  /// Ausnahmen vom Wochenplan (auslassen, verschieben) für einzelne Wochen.
  var planAdjustments: PlanAdjustments {
    didSet { save(planAdjustments, forKey: Self.adjustmentsKey) }
  }

  /// Erinnerung an geplante Einheiten.
  var reminders: ReminderSettings {
    didSet { save(reminders, forKey: Self.remindersKey) }
  }

  /// Optionaler Begleiter (z. B. der eigene Hund).
  var companion: CompanionSettings {
    didSet { save(companion, forKey: Self.companionKey) }
  }

  /// Teilnahme an einer Rangliste.
  var league: LeagueSettings {
    didSet { save(league, forKey: Self.leagueKey) }
  }

  /// Routinen, eigene Übungen und Ausstattung fürs Gym.
  var gym: GymSettings {
    didSet { save(gym, forKey: Self.gymKey) }
  }

  /// Wünsche für die Rezeptideen.
  var recipes: RecipePreferences {
    didSet { save(recipes, forKey: Self.recipesKey) }
  }

  /// Eigene Wägungen (Garmin-Wägungen liegen beim Abruf).
  var weights: [WeightEntry] {
    didSet { save(weights, forKey: Self.weightsKey) }
  }

  /// Schlaf-Coach: Ziel, Weckzeit, Erinnerung.
  var sleep: SleepSettings {
    didSet { save(sleep, forKey: Self.sleepKey) }
  }

  /// Eigene HFmax und Schwellen-HF (0 = automatisch).
  var heartRate: HeartRateOverrides {
    didSet { save(heartRate, forKey: Self.heartRateKey) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    season =
      defaults.data(forKey: Self.seasonKey).flatMap { try? JSONDecoder().decode(SeasonConfig.self, from: $0) }
      ?? .standard
    privacy = defaults.string(forKey: Self.privacyKey).flatMap(PrivacyMode.init(rawValue:)) ?? .reduced
    nutrition =
      defaults.data(forKey: Self.nutritionKey).flatMap { try? JSONDecoder().decode(NutritionSettings.self, from: $0) }
      ?? NutritionSettings()
    competitionDecisions =
      defaults.data(forKey: Self.competitionKey).flatMap {
        try? JSONDecoder().decode(CompetitionDecisions.self, from: $0)
      } ?? [:]
    tests =
      defaults.data(forKey: Self.testsKey).flatMap { try? JSONDecoder().decode([TestRecord].self, from: $0) } ?? []
    heartRate =
      defaults.data(forKey: Self.heartRateKey).flatMap { try? JSONDecoder().decode(HeartRateOverrides.self, from: $0) }
      ?? HeartRateOverrides()
    var adjustments =
      defaults.data(forKey: Self.adjustmentsKey).flatMap { try? JSONDecoder().decode(PlanAdjustments.self, from: $0) }
      ?? PlanAdjustments()
    adjustments.prune(before: CalendarDay(date: .now))
    planAdjustments = adjustments
    reminders =
      defaults.data(forKey: Self.remindersKey).flatMap { try? JSONDecoder().decode(ReminderSettings.self, from: $0) }
      ?? ReminderSettings()
    companion =
      defaults.data(forKey: Self.companionKey).flatMap { try? JSONDecoder().decode(CompanionSettings.self, from: $0) }
      ?? CompanionSettings()
    let storedLeague = defaults.data(forKey: Self.leagueKey).flatMap {
      try? JSONDecoder().decode(LeagueSettings.self, from: $0)
    }
    league = storedLeague ?? LeagueSettings()
    gym =
      defaults.data(forKey: Self.gymKey).flatMap { try? JSONDecoder().decode(GymSettings.self, from: $0) }
      ?? GymSettings()
    recipes =
      defaults.data(forKey: Self.recipesKey).flatMap { try? JSONDecoder().decode(RecipePreferences.self, from: $0) }
      ?? RecipePreferences()
    sleep =
      defaults.data(forKey: Self.sleepKey).flatMap { try? JSONDecoder().decode(SleepSettings.self, from: $0) }
      ?? SleepSettings()
    weights =
      defaults.data(forKey: Self.weightsKey).flatMap { try? JSONDecoder().decode([WeightEntry].self, from: $0) } ?? []
    var migrated = false
    if let stored = defaults.data(forKey: Self.profileKey).flatMap({
      try? JSONDecoder().decode(UserProfile.self, from: $0)
    }) {
      profile = stored
    } else {
      let existing =
        defaults.object(forKey: GarminSyncService.lastSyncKey) != nil || defaults.data(forKey: Self.seasonKey) != nil
      profile = ProfileMigration.initialProfile(hasExistingData: existing)
      migrated = existing
    }
    if migrated { save(profile, forKey: Self.profileKey) }
    // Die Mitglieds-ID muss stabil bleiben, sonst entstehen doppelte Einträge in der Rangliste.
    if storedLeague == nil { save(league, forKey: Self.leagueKey) }
  }

  /// Überträgt das Ziel des Profils auf die Ernährung (Tempo, Schutzgrenzen) und liefert die Hinweise dazu.
  /// Im Saisonplan bleibt die Ernährung unverändert.
  @discardableResult
  func applyProfileToNutrition(garmin: GarminProfile?, day: CalendarDay = CalendarDay(date: .now)) -> GoalAssessment {
    let body = nutrition.profile(garmin: garmin, on: day)
    let assessment = GoalRules.assess(profile: profile, body: body)
    guard profile.mode == .personal else { return assessment }
    var updated = nutrition
    GoalRules.apply(assessment, to: &updated)
    nutrition = updated
    return assessment
  }

  /// Wochenplan der Woche, die `day` enthält, mit Ausnahmen.
  func schedule(inWeekOf day: CalendarDay) -> WeekSchedule {
    planAdjustments.schedule(profile.schedule, inWeekOf: day)
  }

  /// Testwert übernehmen: Saisonwerte setzen und im Verlauf festhalten.
  func record(_ kind: TestRecord.Kind, value: Double, on day: CalendarDay = CalendarDay(date: .now)) {
    switch kind {
    case .css: season.cssSecondsPer100m = Int(value.rounded())
    case .ftp: season.ftpWatts = Int(value.rounded())
    case .threshold: season.thresholdPaceSecondsPerKm = Int(value.rounded())
    case .racePace: season.racePaceSecondsPerKm = Int(value.rounded())
    case .bikeSpeed: season.raceBikeSpeedKmh = value
    case .halfMarathon: break
    }
    tests = TestHistory.adding(TestRecord(kind: kind, value: value, day: day), to: tests)
  }

  /// Wägung eintragen; ein Eintrag je Tag, der neue ersetzt den alten.
  func logWeight(_ kilograms: Double, on day: CalendarDay = CalendarDay(date: .now)) {
    let cutoff = day.adding(days: -365)
    weights =
      (weights.filter { $0.day != day && $0.day >= cutoff } + [
        WeightEntry(day: day, kilograms: kilograms, source: .manual)
      ])
      .sorted { $0.day < $1.day }
  }

  var halfMarathonSeconds: Int? {
    TestHistory.latest(.halfMarathon, in: tests).map { Int($0.value) }
  }

  private func save(_ value: some Encodable, forKey key: String) {
    if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
  }
}

/// Rangliste: Code (leer = nicht dabei), eigene ID und Anzeigename. Nur Name und Punkte verlassen das iPhone.
struct LeagueSettings: Codable, Equatable, Hashable {
  var code = ""
  var memberID = UUID().uuidString.lowercased()
  var name = ""

  var isJoined: Bool { LeagueCode.isValid(code) }
}

/// Erinnerung an geplante Einheiten: an oder aus und Uhrzeit.
struct ReminderSettings: Codable, Equatable, Hashable {
  var enabled = true
  var hour = 7
  var minute = 30

  init() {}

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
    hour = min(max((try? container.decodeIfPresent(Int.self, forKey: .hour)) ?? 7, 0), 23)
    minute = min(max((try? container.decodeIfPresent(Int.self, forKey: .minute)) ?? 30, 0), 59)
  }

  /// Uhrzeit als Datum (heute) für den DatePicker.
  var time: Date {
    get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now }
    set {
      let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
      hour = components.hour ?? 7
      minute = components.minute ?? 30
    }
  }
}

extension CalendarDay {
  /// Mittag in der lokalen Zeitzone – für DatePicker.
  var localDate: Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
  }
}
