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

  var halfMarathonSeconds: Int? {
    TestHistory.latest(.halfMarathon, in: tests).map { Int($0.value) }
  }

  private func save(_ value: some Encodable, forKey key: String) {
    if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
  }
}

extension CalendarDay {
  /// Mittag in der lokalen Zeitzone – für DatePicker.
  var localDate: Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
  }
}
