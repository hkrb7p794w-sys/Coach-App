import ActivityKit
import CoachCore
import Foundation
import UIKit

/// Startet und aktualisiert die Live-Aktivität „Mahlzeiten heute“ aus dem Stand der Widgets.
enum MealsActivityController {
  /// Schalter in den Einstellungen (Ernährung); aus, solange ihn niemand einschaltet.
  static let settingKey = "mealsLiveActivity"
  /// iOS beendet Live-Aktivitäten nach etwa acht Stunden. Beim Öffnen der App beginnt die Zeit deshalb neu, sobald
  /// die laufende Aktivität älter ist als das hier.
  static let restartAfter: TimeInterval = 2 * 3600

  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: settingKey) }

  static func state(from snapshot: WidgetSnapshot, now: Date = .now) -> MealsActivityAttributes.ContentState? {
    guard let nutrition = snapshot.nutrition else { return nil }
    let parts = nutrition.meals ?? MealSplit.order.map { WidgetSnapshot.MealPart(category: $0, kcal: 0, target: nil) }
    return MealsActivityAttributes.ContentState(
      meals: parts.map {
        .init(id: $0.category.rawValue, title: $0.category.label, kcal: Int($0.kcal.rounded()), fraction: $0.fraction)
      },
      streakDays: snapshot.mealStreak?.days ?? 0, streakActive: snapshot.mealStreak?.activeToday ?? false,
      kcalRemaining: nutrition.kcalRemaining.map { Int($0.rounded()) },
      headline: MealHeadline.text(snapshot, hour: Calendar.current.component(.hour, from: now)))
  }

  /// Nach jedem neuen Widget-Stand. Starten darf iOS nur, solange die App sichtbar ist; im Hintergrund wird eine
  /// laufende Aktivität nur aktualisiert.
  static func update(_ snapshot: WidgetSnapshot?, now: Date = .now) {
    let running = Activity<MealsActivityAttributes>.activities.filter {
      $0.activityState == .active || $0.activityState == .stale
    }
    guard isEnabled, let state = snapshot.flatMap({ state(from: $0, now: now) }) else {
      for activity in running {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
      return
    }
    // Ab Mitternacht gilt der Stand als veraltet; die Anzeige zeigt dann einen leeren Tag.
    let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
    let content = ActivityContent(state: state, staleDate: midnight)
    let canStart =
      UIApplication.shared.applicationState != .background && ActivityAuthorizationInfo().areActivitiesEnabled
    if let activity = running.first {
      guard canStart, now.timeIntervalSince(activity.attributes.startedAt) > restartAfter else {
        Task { await activity.update(content) }
        return
      }
      for old in running {
        Task { await old.end(nil, dismissalPolicy: .immediate) }
      }
    }
    guard canStart else { return }
    _ = try? Activity.request(attributes: MealsActivityAttributes(startedAt: now), content: content)
  }
}
