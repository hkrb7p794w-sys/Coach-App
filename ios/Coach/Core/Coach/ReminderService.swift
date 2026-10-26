import CoachCore
import Foundation
import Observation
import UserNotifications

/// Erinnerungen an geplante Einheiten als lokale Mitteilungen – funktioniert ohne Server und ohne
/// Push-Berechtigung, also auch mit SideStore. In der Mitteilung lässt sich die Einheit auslassen oder (in der App)
/// verschieben. Ohne Erlaubnis zeigt die App die Erinnerung als Karte unter „Heute“.
@Observable
final class ReminderService: NSObject {
  static let adjustableCategory = "coach.training.adjustable"
  static let plainCategory = "coach.training"
  static let doneAction = "coach.done"
  static let moveAction = "coach.move"
  static let skipAction = "coach.skip"
  static let identifierPrefix = "coach.reminder."

  enum Permission: Equatable {
    case unknown, allowed, denied
  }

  private(set) var permission: Permission = .unknown
  /// Tag, für den die App das Verschieben anbieten soll (aus einer Mitteilung geöffnet).
  var pendingDay: CalendarDay?

  private let settings: CoachSettings
  private let center: UNUserNotificationCenter?

  init(settings: CoachSettings, center: UNUserNotificationCenter? = .current()) {
    self.settings = settings
    self.center = center
    super.init()
    guard let center else { return }
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.adjustableCategory,
        actions: [
          UNNotificationAction(identifier: Self.doneAction, title: "Erledigt", options: []),
          UNNotificationAction(identifier: Self.moveAction, title: "Verschieben …", options: [.foreground]),
          UNNotificationAction(identifier: Self.skipAction, title: "Diese Woche auslassen", options: [.destructive]),
        ], intentIdentifiers: []),
      UNNotificationCategory(
        identifier: Self.plainCategory,
        actions: [UNNotificationAction(identifier: Self.doneAction, title: "Erledigt", options: [])],
        intentIdentifiers: []),
    ])
  }

  /// Fragt beim ersten Mal nach der Erlaubnis und plant die Erinnerungen der nächsten 14 Tage neu.
  func refresh(seasonSchedule: SeasonSchedule?, now: Date = .now) async {
    guard let center else { return }
    let status = await center.notificationSettings().authorizationStatus
    var allowed = status == .authorized || status == .provisional || status == .ephemeral
    if status == .notDetermined, settings.reminders.enabled {
      allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    permission = allowed ? .allowed : (status == .notDetermined ? .unknown : .denied)

    let pending = await center.pendingNotificationRequests().map(\.identifier)
    center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(Self.identifierPrefix) })
    guard allowed, settings.reminders.enabled else { return }

    for reminder in reminders(seasonSchedule: seasonSchedule, now: now) {
      let content = UNMutableNotificationContent()
      content.title = reminder.title
      content.body = ReminderPlanner.body(for: reminder)
      content.sound = .default
      content.categoryIdentifier = reminder.canAdjust ? Self.adjustableCategory : Self.plainCategory
      content.userInfo = ["day": reminder.day.iso]
      var components = DateComponents(year: reminder.day.year, month: reminder.day.month, day: reminder.day.day)
      components.hour = settings.reminders.hour
      components.minute = settings.reminders.minute
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }
  }

  func reminders(seasonSchedule: SeasonSchedule?, now: Date = .now) -> [TrainingReminder] {
    let today = CalendarDay(date: now)
    let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
    let minutesNow = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    let includeToday = minutesNow < settings.reminders.hour * 60 + settings.reminders.minute
    switch settings.profile.mode {
    case .personal:
      return ReminderPlanner.personal(
        profile: settings.profile, adjustments: settings.planAdjustments, today: today, includeToday: includeToday)
    case .season:
      guard let seasonSchedule else { return [] }
      return ReminderPlanner.season(
        schedule: seasonSchedule, config: settings.season, decisions: settings.competitionDecisions, today: today,
        includeToday: includeToday)
    }
  }

  /// Einheiten eines Tages diese Woche auslassen.
  func skip(_ day: CalendarDay) {
    settings.planAdjustments.skip(Weekday(day: day), inWeekOf: day)
    center?.removeDeliveredNotifications(withIdentifiers: [Self.identifierPrefix + day.iso])
  }

  /// Einheiten eines Tages auf einen anderen Tag derselben Woche verschieben.
  func move(_ day: CalendarDay, to target: Weekday) {
    settings.planAdjustments.move(Weekday(day: day), to: target, inWeekOf: day)
    center?.removeDeliveredNotifications(withIdentifiers: [Self.identifierPrefix + day.iso])
  }

  private func handle(action: String, dayText: String) {
    guard let day = CalendarDay(iso: dayText) else { return }
    switch action {
    case Self.skipAction: skip(day)
    case Self.doneAction: break
    default: pendingDay = settings.profile.mode == .personal ? day : nil
    }
  }
}

extension ReminderService: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let action = response.actionIdentifier
    let day = response.notification.request.content.userInfo["day"] as? String ?? ""
    await handle(action: action, dayText: day)
  }

  /// Auch bei geöffneter App als Banner zeigen.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
