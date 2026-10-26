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

  private(set) var isSyncing = false
  private(set) var lastReport: SyncReport?
  private(set) var lastError: String?

  init(inMemory: Bool = false, secrets: any SecretStore = KeychainStore(), defaults: UserDefaults = .standard) {
    container = CoachSchema.makeContainer(inMemory: inMemory)
    garmin = GarminClient(secrets: secrets, connect: GarminConnectSession(secrets: secrets, defaults: defaults))
    sync = GarminSyncService(client: garmin, context: container.mainContext, defaults: defaults)
    ai = AIClient(secrets: secrets, defaults: defaults)
    settings = CoachSettings(defaults: defaults)
  }

  var lastSync: Date? {
    lastReport?.finishedAt ?? sync.lastSync
  }

  /// Beim Öffnen der App: nur abrufen, wenn ein Key da ist und der letzte Abruf länger her ist.
  func syncIfDue() async {
    guard garmin.isConfigured, SyncPlan.isDue(lastSync: sync.lastSync, now: .now) else { return }
    await syncNow()
  }

  func syncNow() async {
    guard !isSyncing else { return }
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
