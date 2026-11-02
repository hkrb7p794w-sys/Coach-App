import Foundation

/// Gewohnte Essenszeiten und je Mahlzeit ein eigener Schalter (Standard: aus).
public struct MealReminderSettings: Codable, Equatable, Hashable, Sendable {
  public struct Slot: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int

    public init(enabled: Bool = false, hour: Int, minute: Int) {
      self.enabled = enabled
      self.hour = min(max(hour, 0), 23)
      self.minute = min(max(minute, 0), 59)
    }

    public var minutes: Int { hour * 60 + minute }
  }

  public var breakfast = Slot(hour: 8, minute: 0)
  public var lunch = Slot(hour: 12, minute: 30)
  public var dinner = Slot(hour: 19, minute: 0)
  public var snack = Slot(hour: 16, minute: 0)

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = MealReminderSettings()
    breakfast = (try? container.decode(Slot.self, forKey: .breakfast)) ?? defaults.breakfast
    lunch = (try? container.decode(Slot.self, forKey: .lunch)) ?? defaults.lunch
    dinner = (try? container.decode(Slot.self, forKey: .dinner)) ?? defaults.dinner
    snack = (try? container.decode(Slot.self, forKey: .snack)) ?? defaults.snack
  }

  public static let categories: [MealCategory] = [.breakfast, .lunch, .snack, .dinner]

  public subscript(category: MealCategory) -> Slot? {
    get {
      switch category {
      case .breakfast: breakfast
      case .lunch: lunch
      case .dinner: dinner
      case .snack: snack
      case .other: nil
      }
    }
    set {
      guard let newValue else { return }
      switch category {
      case .breakfast: breakfast = newValue
      case .lunch: lunch = newValue
      case .dinner: dinner = newValue
      case .snack: snack = newValue
      case .other: break
      }
    }
  }

  public var anyEnabled: Bool { Self.categories.contains { self[$0]?.enabled == true } }
}

extension ReminderPlanner {
  /// Erinnerungen an Mahlzeiten für heute und die nächsten Tage. Keine Mitteilung, wenn die Mahlzeit an dem Tag schon
  /// erfasst ist oder die Zeit heute vorbei ist. Uhrzeiten gelten in der jeweils aktuellen Zeitzone (die App plant
  /// bei jeder Änderung von Zeiten, Mahlzeiten oder Zeitzone neu).
  public static func meals(
    _ settings: MealReminderSettings, today: CalendarDay, minutesNow: Int, logged: Set<String>, days: Int = 2
  ) -> [ScheduledNote] {
    (0..<max(days, 1)).flatMap { offset -> [ScheduledNote] in
      let day = today.adding(days: offset)
      return MealReminderSettings.categories.compactMap { category in
        guard let slot = settings[category], slot.enabled else { return nil }
        if offset == 0, minutesNow >= slot.minutes { return nil }
        if logged.contains(loggedKey(day: day, category: category)) { return nil }
        var note = ScheduledNote(
          kind: .meal, day: day, hour: slot.hour, minute: slot.minute, title: "\(category.label) eintragen",
          body: mealBody(category))
        note.tag = category.rawValue
        return note
      }
    }
  }

  /// Schlüssel für „an diesem Tag schon erfasst“.
  public static func loggedKey(day: CalendarDay, category: MealCategory) -> String {
    "\(day.iso)|\(category.rawValue)"
  }

  static func mealBody(_ category: MealCategory) -> String {
    switch category {
    case .breakfast: "Was gab es zum Frühstück? Ein Tipp auf „Zuletzt“ reicht oft."
    case .lunch: "Mittagessen eintragen – Foto, Text oder aus deinen Favoriten."
    case .dinner: "Abendessen eintragen, dann stimmt die Tagesbilanz."
    case .snack, .other: "Snack eintragen?"
    }
  }
}
