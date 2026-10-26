import CoachCore
import Foundation
import Observation

/// Saison (Renntermine, Testwerte) und KI-Datenschutz, gespeichert in den UserDefaults.
@Observable
final class CoachSettings {
  static let seasonKey = "coach.season"
  static let privacyKey = "coach.privacy"
  static let nutritionKey = "coach.nutrition"

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

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    season =
      defaults.data(forKey: Self.seasonKey).flatMap { try? JSONDecoder().decode(SeasonConfig.self, from: $0) }
      ?? .standard
    privacy = defaults.string(forKey: Self.privacyKey).flatMap(PrivacyMode.init(rawValue:)) ?? .reduced
    nutrition =
      defaults.data(forKey: Self.nutritionKey).flatMap { try? JSONDecoder().decode(NutritionSettings.self, from: $0) }
      ?? NutritionSettings()
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
