import BackgroundTasks
import CoachCore
import Foundation
import Observation
import SwiftData

/// Zentrale Abhängigkeiten der App und Status des Garmin-Abrufs.
@Observable
final class AppModel {
  static let refreshTaskID = "io.github.hkrb7p794w.coach.refresh"

  let container: ModelContainer
  let garmin: GarminClient
  let sync: GarminSyncService
  let ai: AIClient
  let settings: CoachSettings
  let reminders: ReminderService
  let league: LeagueService
  @ObservationIgnored private lazy var seasonSchedule = SeasonSchedule.load()

  private(set) var isSyncing = false
  private(set) var lastReport: SyncReport?
  private(set) var lastError: String?

  /// Screenshot-Modus mit Beispieldaten: kein Abruf, keine Mitteilungen.
  let isDemo: Bool

  init(
    inMemory: Bool = false, secrets: any SecretStore = KeychainStore(), defaults: UserDefaults = .standard,
    isDemo: Bool = false
  ) {
    self.isDemo = isDemo
    container = CoachSchema.makeContainer(inMemory: inMemory)
    garmin = GarminClient(secrets: secrets, connect: GarminConnectSession(secrets: secrets, defaults: defaults))
    sync = GarminSyncService(client: garmin, context: container.mainContext, defaults: defaults)
    ai = AIClient(secrets: secrets, defaults: defaults)
    settings = CoachSettings(defaults: defaults)
    // In Tests (inMemory) ohne Mitteilungszentrale.
    reminders = ReminderService(settings: settings, center: inMemory ? nil : .current())
    league = LeagueService(ai: ai, settings: settings)
  }

  /// Planerfüllung für Begleiter und Rangliste. Im Saisonplan gelten die festen Einheiten als geplant.
  func motivation(trainingDays: Set<CalendarDay>, today: CalendarDay = CalendarDay(date: .now)) -> MotivationSummary {
    let settings = settings
    let season = settings.profile.mode == .season ? seasonSchedule : nil
    return MotivationSummary.compute(
      schedule: { monday in
        guard let season else { return settings.schedule(inWeekOf: monday) }
        var week = WeekSchedule()
        let reminders = ReminderPlanner.season(
          schedule: season, config: settings.season, decisions: settings.competitionDecisions, today: monday,
          includeToday: true, days: 7)
        for reminder in reminders { week.set([SessionSlot(.other)], on: Weekday(day: reminder.day)) }
        return week
      }, trainingDays: trainingDays, today: today)
  }

  /// Erinnerungen der nächsten 14 Tage neu planen (nach Änderungen am Plan und beim Öffnen der App).
  func refreshReminders() async {
    guard settings.profile.onboardingDone, !isDemo else { return }
    await reminders.refresh(seasonSchedule: settings.profile.mode == .season ? seasonSchedule : nil)
  }

  var lastSync: Date? {
    lastReport?.finishedAt ?? sync.lastSync
  }

  /// Beim Öffnen der App: nur abrufen, wenn ein Key da ist und der letzte Abruf länger her ist.
  func syncIfDue() async {
    guard !isDemo, garmin.isConfigured, SyncPlan.isDue(lastSync: sync.lastSync, now: .now) else { return }
    await syncNow()
  }

  func syncNow() async {
    guard !isSyncing, !isDemo else { return }
    isSyncing = true
    defer { isSyncing = false }
    do {
      lastReport = try await sync.sync()
      lastError = nil
    } catch let error as GarminAPIError {
      lastError = error.message
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// Hintergrundaktualisierung: iOS entscheidet, wann (und ob) sie läuft.
  func backgroundRefresh() async {
    scheduleBackgroundRefresh()
    await syncIfDue()
  }

  func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3_600)
    // Im Simulator nicht verfügbar; ohne Planung holt die App die Daten beim nächsten Öffnen.
    try? BGTaskScheduler.shared.submit(request)
  }
}
