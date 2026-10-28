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
  static let planningCategory = "coach.weekPlanning"
  static let identifierPrefix = "coach.reminder."

  enum Permission: Equatable {
    case unknown, allowed, denied
  }

  private(set) var permission: Permission = .unknown
  /// Tag, für den die App das Verschieben anbieten soll (aus einer Mitteilung geöffnet).
  var pendingDay: CalendarDay?
  /// „Nächste Woche planen“ aus der Sonntags-Mitteilung geöffnet.
  var showsWeekPlanning = false

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
      UNNotificationCategory(identifier: Self.planningCategory, actions: [], intentIdentifiers: []),
    ])
  }

  /// Fragt beim ersten Mal nach der Erlaubnis und plant die Erinnerungen der nächsten 14 Tage neu.
  func refresh(seasonSchedule: SeasonSchedule?, log: TrainingLog = TrainingLog(), now: Date = .now) async {
    guard let center else { return }
    let status = await center.notificationSettings().authorizationStatus
    var allowed = status == .authorized || status == .provisional || status == .ephemeral
    let config = settings.reminders
    let wanted = config.enabled || config.equipment || config.weekPlanning || config.nutritionReview
    if status == .notDetermined, wanted {
      allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    permission = allowed ? .allowed : (status == .notDetermined ? .unknown : .denied)

    let pending = await center.pendingNotificationRequests().map(\.identifier)
    center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(Self.identifierPrefix) })
    guard allowed else { return }

    for reminder in config.enabled ? reminders(seasonSchedule: seasonSchedule, log: log, now: now) : [] {
      let content = UNMutableNotificationContent()
      content.title = reminder.title
      content.body = ReminderPlanner.body(for: reminder, lead: CompanionVoice.reminderLead(settings.companion))
      content.sound = .default
      content.categoryIdentifier = reminder.canAdjust ? Self.adjustableCategory : Self.plainCategory
      content.userInfo = ["day": reminder.day.iso]
      var components = DateComponents(year: reminder.day.year, month: reminder.day.month, day: reminder.day.day)
      components.hour = settings.reminders.hour
      components.minute = settings.reminders.minute
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    // Ausrüstung am Vorabend und Wochenplanung am Sonntag (iOS erlaubt höchstens 64 geplante Mitteilungen).
    for note in notes(seasonSchedule: seasonSchedule, log: log, now: now) {
      let content = UNMutableNotificationContent()
      content.title = note.title
      content.body = note.body
      content.sound = .default
      if note.kind == .weekPlanning { content.categoryIdentifier = Self.planningCategory }
      content.userInfo = ["day": note.day.iso, "kind": note.kind.rawValue]
      var components = DateComponents(year: note.day.year, month: note.day.month, day: note.day.day)
      components.hour = note.hour
      components.minute = note.minute
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      try? await center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: trigger))
    }
  }

  func notes(seasonSchedule: SeasonSchedule?, log: TrainingLog = TrainingLog(), now: Date = .now) -> [ScheduledNote] {
    let today = CalendarDay(date: now)
    let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
    let minutesNow = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    let config = settings.reminders
    var result: [ScheduledNote] = []
    if config.equipment, settings.profile.mode == .season, let seasonSchedule {
      result += ReminderPlanner.swimEquipment(
        schedule: seasonSchedule, config: settings.season, decisions: settings.competitionDecisions, today: today,
        minutesNow: minutesNow, log: log)
    }
    if config.weekPlanning {
      result += ReminderPlanner.weekPlanning(
        mode: settings.profile.mode, today: today, minutesNow: minutesNow, hour: config.planningHour,
        minute: config.planningMinute)
    }
    if config.nutritionReview {
      result += ReminderPlanner.nutritionReview(today: today, minutesNow: minutesNow)
    }
    return result
  }

  func reminders(
    seasonSchedule: SeasonSchedule?, log: TrainingLog = TrainingLog(), now: Date = .now
  ) -> [TrainingReminder] {
    let today = CalendarDay(date: now)
    let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
    let minutesNow = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    let includeToday = minutesNow < settings.reminders.hour * 60 + settings.reminders.minute
    switch settings.profile.mode {
    case .personal:
      return ReminderPlanner.personal(
        profile: settings.profile, adjustments: settings.planAdjustments, today: today, includeToday: includeToday,
        log: log)
    case .season:
      guard let seasonSchedule else { return [] }
      return ReminderPlanner.season(
        schedule: seasonSchedule, config: settings.season, decisions: settings.competitionDecisions, today: today,
        includeToday: includeToday, log: log)
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

  private func handle(action: String, dayText: String, kind: String?) {
    if kind == ScheduledNote.Kind.weekPlanning.rawValue {
      showsWeekPlanning = true
      return
    }
    // Ausrüstungs-Erinnerung: nur die App öffnen.
    guard kind == nil, let day = CalendarDay(iso: dayText) else { return }
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
    let info = response.notification.request.content.userInfo
    let day = info["day"] as? String ?? ""
    await handle(action: action, dayText: day, kind: info["kind"] as? String)
  }

  /// Auch bei geöffneter App als Banner zeigen.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
