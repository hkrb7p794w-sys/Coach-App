import CoachCore
import Foundation
import SwiftData

/// Merkt, welches eigene Training zu welchem Beitrag gehört (nur auf diesem Gerät).
enum SharedPostStore {
  static let key = "social.sharedPosts"
  /// Ältere Zuordnungen fallen weg, damit die Liste nicht wächst.
  static let limit = 400

  static func load(_ defaults: UserDefaults = .standard) -> [String: String] {
    defaults.dictionary(forKey: key) as? [String: String] ?? [:]
  }

  static func remember(_ localKeys: [String], post: String, defaults: UserDefaults = .standard) {
    guard !localKeys.isEmpty else { return }
    var map = load(defaults)
    if map.count > limit { map = [:] }
    for localKey in localKeys { map[localKey] = post }
    defaults.set(map, forKey: key)
  }
}

/// „Trainings automatisch mit Freunden teilen“: neue Trainings (Uhr und Gym) erscheinen von selbst im Feed der
/// Freunde – ohne Körperwerte, wie beim Teilen von Hand (`WorkoutShare`). Standard: aus.
enum SocialAutoShare {
  static let enabledKey = "social.autoShare"
  /// Zeitpunkt des Einschaltens: Ältere Trainings bleiben privat.
  static let sinceKey = "social.autoShareSince"

  private static var isRunning = false

  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

  /// Beim Umschalten in den Einstellungen bzw. im Reiter.
  static func setEnabled(_ enabled: Bool, now: Date = .now) {
    UserDefaults.standard.set(enabled, forKey: enabledKey)
    if enabled { UserDefaults.standard.set(now.timeIntervalSince1970, forKey: sinceKey) }
  }

  /// Nach dem Abgleich und beim Öffnen des Reiters. Fehler (offline, abgemeldet) bleiben still; der nächste
  /// Durchlauf holt es nach.
  static func run(model: AppModel, now: Date = .now) async {
    guard isEnabled, !isRunning, !model.isDemo, model.social.isAvailable else { return }
    let since = UserDefaults.standard.double(forKey: sinceKey)
    guard since > 0 else { return }
    isRunning = true
    defer { isRunning = false }
    let context = model.container.mainContext
    let earliest = CalendarDay(date: now).adding(days: -4).iso
    let activities =
      ((try? context.fetch(FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.dayKey >= earliest }))) ?? [])
      .compactMap(\.activity)
    let sessions =
      ((try? context.fetch(FetchDescriptor<GymSessionRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)])))
      ?? []).prefix(20).compactMap(\.session)
    let entries = ActivityFeed.entries(activities: activities, gym: sessions.map(ActivityFeed.GymItem.init))
    let candidates = SocialTimeline.autoShareCandidates(
      entries: entries, shared: SharedPostStore.load(), since: Date(timeIntervalSince1970: since), now: now)
    for entry in candidates {
      let share: WorkoutShare
      if let gym = entry.gym, let session = sessions.first(where: { $0.id == gym.id }) {
        share = WorkoutShare.gym(session, now: now)
      } else if let activity = entry.activity {
        share = WorkoutShare.activity(activity)
      } else {
        continue
      }
      guard (try? await model.social.share(workout: share, localKeys: SocialTimeline.keys(entry))) != nil else {
        return
      }
    }
  }
}
