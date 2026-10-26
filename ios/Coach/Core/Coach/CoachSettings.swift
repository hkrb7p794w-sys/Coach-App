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
    heartRate =
      defaults.data(forKey: Self.heartRateKey).flatMap { try? JSONDecoder().decode(HeartRateOverrides.self, from: $0) }
      ?? HeartRateOverrides()
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
