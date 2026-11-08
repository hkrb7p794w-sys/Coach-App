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
  let health: HealthImportService
  let sources: SourceStore
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
    health = HealthImportService(context: container.mainContext, defaults: defaults)
    sources = SourceStore(context: container.mainContext, defaults: defaults)
    ai = AIClient(secrets: secrets, defaults: defaults)
    settings = CoachSettings(defaults: defaults)
    // In Tests (inMemory) ohne Mitteilungszentrale.
    reminders = ReminderService(settings: settings, center: inMemory ? nil : .current())
    league = LeagueService(ai: ai, settings: settings)
    let current = self.settings
    sources.preferences = { current.sources }
    sync.sources = sources
    health.sources = sources
    if !isDemo { sources.migrateIfNeeded() }
    ai.userSources = { current.userSources }
    ai.settings = { current.ai }
    ai.onUsage = { entry in current.aiUsage = AIUsageLog.appending(entry, to: current.aiUsage) }
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
  /// Nach jedem Abruf und jeder Krafteinheit erneut: Erinnerungen für schon Erledigtes entfallen.
  func refreshReminders() async {
    guard settings.profile.onboardingDone, !isDemo else { return }
    await reminders.refresh(
      seasonSchedule: settings.profile.mode == .season ? seasonSchedule : nil, log: trainingLog(),
      loggedMeals: loggedMeals())
  }

  /// Heute und morgen schon erfasste Mahlzeiten (Wasser zählt nicht) – dafür keine Erinnerung.
  func loggedMeals(now: Date = .now) -> Set<String> {
    let today = CalendarDay(date: now)
    let start = today.iso
    let end = today.adding(days: 1).iso
    let query = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.dayKey >= start && $0.dayKey <= end })
    let meals = (try? container.mainContext.fetch(query)) ?? []
    return Set(
      meals.filter { !$0.isWater }.compactMap { meal in
        CalendarDay(iso: meal.dayKey).map { ReminderPlanner.loggedKey(day: $0, category: meal.category) }
      })
  }

  /// Aktivitäten und Krafteinheiten dieser und der letzten Woche.
  func trainingLog(now: Date = .now) -> TrainingLog {
    let today = CalendarDay(date: now)
    let start = today.adding(days: -today.weekdayIndex - 7).iso
    let context = container.mainContext
    let activityQuery = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.dayKey >= start })
    let gymQuery = FetchDescriptor<GymSessionRecord>(predicate: #Predicate { $0.dayKey >= start })
    let activities = (try? context.fetch(activityQuery)) ?? []
    let gym = (try? context.fetch(gymQuery)) ?? []
    var gymDays = Set(gym.compactMap { CalendarDay(iso: $0.dayKey) })
    // Laufende Einheit (mindestens ein Satz) zählt schon als trainiert; nur geöffnet zählt nicht.
    if let active = GymViewModel.shared.active, GymViewModel.shared.sessionState(now: now).countsAsTrained {
      gymDays.insert(active.day)
    }
    return TrainingLog(activities: activities.compactMap(\.activity), gymDays: gymDays)
  }

  var lastSync: Date? {
    lastReport?.finishedAt ?? sync.lastSync
  }

  /// Gewicht aus eigenen Eingaben, Garmin und Apple Health (Vorrang in `WeightTrend.merged`).
  var allWeights: [WeightEntry] {
    settings.weights + sync.weights + health.weights
  }

  /// Schutzgrenzen mit den neuesten Wägungen und Gesundheitsangaben abgleichen.
  func refreshGoalGuards() {
    settings.refreshGoalGuards(weights: allWeights, garmin: sync.profile)
  }

  /// Verbundene Quellen (für Vorrang und Doppelte).
  var connectedSources: Set<DataProvider> {
    var result = Set<DataProvider>()
    if garmin.isConfigured { result.insert(.garmin) }
    if health.isEnabled { result.insert(.appleHealth) }
    return result
  }

  /// Nach geänderten Quellen-Einstellungen: Tageswerte und Aktivitäten neu zusammenführen.
  func applySourcePreferences() {
    sources.rebuild()
    sources.deduplicateActivities(connected: connectedSources)
    try? container.mainContext.save()
  }

  /// Beim Öffnen der App: nur abrufen, wenn eine Quelle verbunden ist und der letzte Abruf länger her ist.
  /// Nach Fehlschlägen wartet der automatische Abruf länger (1 min … 6 h); manuell geht es immer.
  func syncIfDue() async {
    guard !isDemo else { return }
    refreshGoalGuards()
    // Nur geöffnete, nie begonnene Einheit von früher verwerfen (keine Live-Aktivität, zählt nicht).
    GymViewModel.shared.discardAbandoned()
    let states = sources.syncStates
    let garminDue = states[.garmin].map { $0.isDue(now: .now, minimumInterval: SyncPlan.minimumInterval) } ?? true
    if garmin.isConfigured, garminDue, SyncPlan.isDue(lastSync: sync.lastSync, now: .now) {
      await syncNow()
    } else if health.isEnabled, SyncPlan.isDue(lastSync: health.lastImport, now: .now) {
      await health.importNow(garminConnected: garmin.isConfigured)
    }
  }

  /// Erst Garmin, dann Apple Health: Health ergänzt nur, was Garmin nicht liefert.
  func syncNow() async {
    guard !isSyncing, !isDemo else { return }
    isSyncing = true
    defer { isSyncing = false }
    if garmin.isConfigured {
      do {
        lastReport = try await sync.sync()
        lastError = nil
        sources.recordSuccess(.garmin)
      } catch let error as GarminAPIError {
        lastError = error.message
        sources.recordFailure(.garmin, error: error.message)
      } catch {
        lastError = error.localizedDescription
        sources.recordFailure(.garmin, error: error.localizedDescription)
      }
    }
    await health.importNow(garminConnected: garmin.isConfigured)
    refreshGoalGuards()
    if health.isEnabled {
      if let problem = health.lastProblem {
        sources.recordFailure(.appleHealth, error: problem)
      } else {
        sources.recordSuccess(.appleHealth)
      }
    }
    sources.deduplicateActivities(connected: connectedSources)
    try? container.mainContext.save()
    // Wartende Gym-Einheiten: Sätze in die inzwischen geladene Aufzeichnung der Uhr schreiben.
    if settings.gym.uploadsToGarmin, let connect = garmin.connect, connect.isLoggedIn {
      await GarminStrengthService.reconcile(context: container.mainContext, garmin: connect, gym: settings.gym)
    }
    await refreshReminders()
  }

  /// Hintergrundaktualisierung: iOS entscheidet, wann (und ob) sie läuft.
  func backgroundRefresh() async {
    scheduleBackgroundRefresh()
    await syncIfDue()
    // Neue Nacht-/Tageswerte auch auf dem Homescreen.
    WidgetPublisher.publish(model: self)
  }

  func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3_600)
    // Im Simulator nicht verfügbar; ohne Planung holt die App die Daten beim nächsten Öffnen.
    try? BGTaskScheduler.shared.submit(request)
  }
}
