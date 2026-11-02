import Foundation
import Testing

@testable import CoachCore

private let day = CalendarDay(year: 2026, month: 11, day: 2)
private let utc = TimeZone(identifier: "UTC")!

private func activity(
  _ id: Int64, provider: DataProvider? = nil, start: String, minutes: Double, type: String = "running",
  calories: Double = 500
) -> GarminActivity {
  var activity = GarminActivity(id: id)
  activity.provider = provider
  activity.typeKey = type
  activity.startLocal = start
  activity.durationSeconds = minutes * 60
  activity.calories = calories
  return activity
}

struct SourcePreferenceTests {
  @Test func overrideThenPrimaryStrengthThenDefault() {
    let connected: Set<DataProvider> = [.garmin, .whoop, .appleHealth]
    var preferences = SourcePreferences(primary: .garmin)
    // Garmin ist primär, aber Schlaf gehört nicht zu Garmins Stärken: WHOOP vorne (allgemeine Rangfolge).
    #expect(preferences.preferred(for: .sleep, connected: connected) == .whoop)
    #expect(preferences.preferred(for: .activities, connected: connected) == .garmin)
    preferences.overrides[.sleep] = .garmin
    #expect(preferences.order(for: .sleep, connected: connected) == [.garmin, .whoop, .appleHealth])
    // WHOOP primär: Erholung und HRV von WHOOP, Aktivitäten trotzdem von Garmin.
    let whoop = SourcePreferences(primary: .whoop)
    #expect(whoop.preferred(for: .hrv, connected: connected) == .whoop)
    #expect(whoop.preferred(for: .activities, connected: connected) == .garmin)
  }

  @Test func onlyConnectedAndCapableProviders() {
    let preferences = SourcePreferences(primary: .whoop, overrides: [.stress: .whoop])
    // WHOOP liefert keinen Stress und ist nicht verbunden.
    #expect(preferences.order(for: .stress, connected: [.garmin]) == [.garmin])
    #expect(preferences.order(for: .steps, connected: [.whoop]).isEmpty)
  }

  @Test func decodingSkipsUnknownValues() throws {
    let json = #"{"primary": "oura", "overrides": {"sleep": "whoop", "laune": "garmin", "hrv": "oura"}}"#
    let decoded = try JSONDecoder().decode(SourcePreferences.self, from: Data(json.utf8))
    #expect(decoded.primary == nil)
    #expect(decoded.overrides == [.sleep: .whoop])
    let roundTrip = try JSONDecoder().decode(
      SourcePreferences.self, from: JSONEncoder().encode(SourcePreferences(primary: .garmin, overrides: [.hrv: .whoop])))
    #expect(roundTrip == SourcePreferences(primary: .garmin, overrides: [.hrv: .whoop]))
  }

  @Test func catalogIsHonest() {
    #expect(DataProvider.garmin.availability == .available)
    #expect(DataProvider.appleHealth.availability == .available)
    #expect(DataProvider.whoop.availability == .planned)
    #expect(DataProvider.polar.availability == .planned)
    #expect(DataProvider.fitbit.availability == .unavailable)
    for provider in DataProvider.allCases {
      #expect(provider.strengths.isSubset(of: provider.capabilities))
      #expect(!provider.availabilityNote.isEmpty)
    }
    for kind in DataKind.allCases {
      #expect(Set(DataProvider.defaultOrder(for: kind)) == Set(DataProvider.allCases))
    }
  }
}

struct MetricsMergeTests {
  @Test func eachKindFromOneProviderAsWholeGroup() {
    var garmin = DailyMetrics(day: day)
    garmin.sleepSeconds = 7 * 3_600
    garmin.deepSleepSeconds = 4_000
    garmin.restingHeartRate = 48
    garmin.steps = 12_000
    garmin.activeKilocalories = 700
    garmin.hrvLastNightAverage = 55
    var whoop = DailyMetrics(day: day)
    whoop.sleepSeconds = 7.5 * 3_600
    whoop.hrvLastNightAverage = 62
    whoop.activeKilocalories = 900
    var health = DailyMetrics(day: day)
    health.steps = 11_500
    health.activeKilocalories = 650

    let result = MetricsMerge.merge(
      [.garmin: garmin, .whoop: whoop, .appleHealth: health], day: day, preferences: SourcePreferences(primary: .garmin))
    // Schlaf als ganze Gruppe von WHOOP: keine Tiefschlafphase von Garmin dazugemischt.
    #expect(result.metrics.sleepSeconds == 7.5 * 3_600)
    #expect(result.metrics.deepSleepSeconds == nil)
    #expect(result.sources[.sleep] == .whoop)
    #expect(result.metrics.hrvLastNightAverage == 62)
    // Kalorien und Schritte nur aus einer Quelle – nicht addiert.
    #expect(result.metrics.activeKilocalories == 700)
    #expect(result.metrics.steps == 12_000)
    #expect(result.sources[.calories] == .garmin)
    #expect(result.metrics.restingHeartRate == 48)
  }

  @Test func fallsBackWhenPreferredHasNoValues() {
    var garmin = DailyMetrics(day: day)
    garmin.steps = 9_000
    var health = DailyMetrics(day: day)
    health.sleepSeconds = 6 * 3_600
    let result = MetricsMerge.merge(
      [.garmin: garmin, .appleHealth: health], day: day, preferences: SourcePreferences(overrides: [.sleep: .garmin]))
    #expect(result.sources[.sleep] == .appleHealth)
    #expect(result.metrics.sleepSeconds == 21_600.0)
    #expect(result.sources[.steps] == .garmin)
    #expect(result.sources[.hrv] == nil)
  }

  @Test func everyFieldBelongsToAKind() {
    // Ein voll befüllter Tag muss nach dem Zusammenführen gleich bleiben – sonst fehlt ein Feld in den Gruppen.
    var full = DailyMetrics(day: day)
    full.restingHeartRate = 1
    full.hrvLastNightAverage = 1
    full.hrvWeeklyAverage = 1
    full.hrvStatus = "BALANCED"
    full.hrvBaselineLow = 1
    full.hrvBaselineHigh = 1
    full.sleepSeconds = 1
    full.sleepScore = 1
    full.bodyBatteryHigh = 1
    full.bodyBatteryLow = 1
    full.bodyBatteryLatest = 1
    full.stressAverage = 1
    full.steps = 1
    full.activeKilocalories = 1
    full.totalKilocalories = 1
    full.respirationWaking = 1
    full.respirationSleep = 1
    full.spo2Average = 1
    full.spo2Lowest = 1
    full.bodyBatteryCharged = 1
    full.bodyBatteryDrained = 1
    full.deepSleepSeconds = 1
    full.lightSleepSeconds = 1
    full.remSleepSeconds = 1
    full.awakeSleepSeconds = 1
    full.sleepStress = 1
    full.fitnessAge = 1
    full.vo2Max = 1
    full.trainingReadiness = 1
    full.trainingReadinessLevel = "HIGH"
    full.trainingStatus = "PRODUCTIVE"
    full.enduranceScore = 1
    full.sleepStartMinutes = 1
    full.sleepEndMinutes = 1
    full.bodyBatteryAtWake = 1
    full.bodyBatteryCurve = [BodyBatterySample(minute: 0, value: 1)]
    full.restingKilocalories = 1
    full.minHeartRate = 1
    full.maxHeartRate = 1
    full.recoveryHours = 1
    full.acuteLoad = 1
    full.chronicLoad = 1
    let result = MetricsMerge.merge([.garmin: full], day: day, preferences: SourcePreferences())
    #expect(result.metrics == full)
  }
}

struct ActivityMergeTests {
  @Test func sameSessionKeepsPreferredProviderOnly() {
    let garmin = activity(101, start: "2026-11-02 07:00:00", minutes: 50)
    let health = activity(-5, start: "2026-11-02 07:03:00", minutes: 48)
    let whoop = activity(-9, provider: .whoop, start: "2026-11-02 07:01:00", minutes: 51, type: "other")
    let other = activity(102, start: "2026-11-02 18:00:00", minutes: 30, type: "cycling")
    let plan = ActivityMerge.plan(
      [health, whoop, garmin, other], preferences: SourcePreferences(), connected: [.garmin, .appleHealth, .whoop],
      timeZone: utc)
    #expect(plan.kept.map(\.id).sorted() == [101, 102])
    #expect(plan.superseded == [-5: 101, -9: 101])
    // Kalorien zählen nur einmal.
    #expect(plan.kept.compactMap(\.calories).reduce(0, +) == 1_000)
  }

  @Test func preferenceDecidesWhichCopyStays() {
    let garmin = activity(101, start: "2026-11-02 07:00:00", minutes: 50)
    let polar = activity(-3, provider: .polar, start: "2026-11-02 07:00:30", minutes: 50)
    let plan = ActivityMerge.plan(
      [garmin, polar], preferences: SourcePreferences(overrides: [.activities: .polar]),
      connected: [.garmin, .polar], timeZone: utc)
    #expect(plan.kept.map(\.id) == [-3])
    #expect(plan.superseded == [101: -3])
  }

  @Test func differentSportsOrTimesStaySeparate() {
    let run = activity(1, start: "2026-11-02 07:00:00", minutes: 30)
    let bike = activity(-1, start: "2026-11-02 07:05:00", minutes: 30, type: "cycling")
    let later = activity(-2, start: "2026-11-02 07:40:00", minutes: 30)
    let plan = ActivityMerge.plan(
      [run, bike, later], preferences: SourcePreferences(), connected: [.garmin, .appleHealth], timeZone: utc)
    #expect(plan.kept.count == 3)
    #expect(plan.superseded.isEmpty)
  }

  @Test func sameProviderIsNeverMergedAway() {
    // Zwei Garmin-Aktivitäten kurz hintereinander (z. B. Ein- und Auslaufen) sind echte Einheiten.
    let a = activity(1, start: "2026-11-02 07:00:00", minutes: 10)
    let b = activity(2, start: "2026-11-02 07:05:00", minutes: 40)
    let plan = ActivityMerge.plan([a, b], preferences: SourcePreferences(), connected: [.garmin], timeZone: utc)
    #expect(plan.kept.count == 2)
  }

  @Test func providerInferenceAndLocalIDs() {
    #expect(ActivityMerge.provider(of: GarminActivity(id: 5)) == .garmin)
    #expect(ActivityMerge.provider(of: GarminActivity(id: -5)) == .appleHealth)
    let a = ActivityMerge.localID(provider: .whoop, externalID: "abc")
    #expect(a < 0)
    #expect(a == ActivityMerge.localID(provider: .whoop, externalID: "abc"))
    #expect(a != ActivityMerge.localID(provider: .polar, externalID: "abc"))
  }
}

struct SyncLedgerTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func newChangedUnchangedDeleted() {
    let window = DateRange(start: day.adding(days: -2), end: day)
    let known = [
      SourceEntry(provider: .garmin, kind: .activities, externalID: "1", day: day, importedAt: now, contentHash: "a"),
      SourceEntry(provider: .garmin, kind: .activities, externalID: "2", day: day, importedAt: now, contentHash: "b"),
      SourceEntry(
        provider: .garmin, kind: .activities, externalID: "3", day: day.adding(days: -1), importedAt: now,
        contentHash: "c"),
      SourceEntry(
        provider: .garmin, kind: .activities, externalID: "old", day: day.adding(days: -10), importedAt: now,
        contentHash: "d"),
      SourceEntry(provider: .appleHealth, kind: .activities, externalID: "x", day: day, importedAt: now, contentHash: "e"),
    ]
    let incoming = [
      SyncLedger.Incoming(externalID: "1", day: day, contentHash: "a"),
      SyncLedger.Incoming(externalID: "2", day: day, contentHash: "B"),
      SyncLedger.Incoming(externalID: "4", day: day, contentHash: "f"),
      SyncLedger.Incoming(externalID: "4", day: day, contentHash: "f"),
    ]
    let later = now.addingTimeInterval(60)
    let changes = SyncLedger.reconcile(
      known: known, incoming: incoming, provider: .garmin, kind: .activities, window: window, complete: true, now: later)
    #expect(changes.new.map(\.externalID) == ["4"])
    #expect(changes.changed.map(\.externalID) == ["2"])
    #expect(changes.changed.first?.updatedAt == later)
    #expect(changes.unchanged == ["1"])
    // „3“ fehlt im vollständigen Zeitraum → gelöscht; „old“ liegt davor, Apple Health ist ein anderer Anbieter.
    #expect(changes.deleted.map(\.externalID) == ["3"])
    #expect(changes.deleted.first?.status == .deleted)

    let partial = SyncLedger.reconcile(
      known: known, incoming: incoming, provider: .garmin, kind: .activities, window: window, complete: false, now: later)
    #expect(partial.deleted.isEmpty)
  }

  @Test func supersededStaysSupersededAndDeletedComesBack() {
    let known = [
      SourceEntry(
        provider: .appleHealth, kind: .activities, externalID: "s", day: day, importedAt: now, contentHash: "a",
        status: .superseded),
      SourceEntry(
        provider: .appleHealth, kind: .activities, externalID: "d", day: day, importedAt: now, contentHash: "a",
        status: .deleted),
    ]
    let changes = SyncLedger.reconcile(
      known: known,
      incoming: [
        .init(externalID: "s", day: day, contentHash: "z"), .init(externalID: "d", day: day, contentHash: "a"),
      ], provider: .appleHealth, kind: .activities, window: nil, complete: false, now: now)
    #expect(changes.skipped == ["s"])
    #expect(changes.changed.map(\.externalID) == ["d"])
    #expect(changes.changed.first?.status == .active)
  }

  @Test func hashChangesWithContent() {
    var a = DailyMetrics(day: day)
    a.steps = 1
    var b = a
    #expect(SyncLedger.hash(a) == SyncLedger.hash(b))
    b.steps = 2
    #expect(SyncLedger.hash(a) != SyncLedger.hash(b))
  }
}

struct ProviderSyncStateTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func backoffAfterFailuresAndResetOnSuccess() {
    var state = ProviderSyncState()
    #expect(state.isDue(now: now, minimumInterval: 900))
    state.recordFailure(now: now, error: "Netz")
    #expect(!state.isDue(now: now.addingTimeInterval(30), minimumInterval: 900))
    #expect(state.isDue(now: now.addingTimeInterval(61), minimumInterval: 900))
    state.recordFailure(now: now, error: "Netz")
    state.recordFailure(now: now, error: "Netz")
    #expect(!state.isDue(now: now.addingTimeInterval(10 * 60), minimumInterval: 900))
    #expect(ProviderSyncState.backoff(failures: 9) == 6 * 3_600)
    state.recordSuccess(now: now, day: day)
    #expect(state.failures == 0)
    #expect(state.lastError == nil)
    #expect(!state.isDue(now: now.addingTimeInterval(60), minimumInterval: 900))
  }

  @Test func windowCatchesUpAfterFailedSyncs() {
    var state = ProviderSyncState()
    #expect(state.window(today: day, initialDays: 28) == DateRange.last(28, endingOn: day))
    state.recordSuccess(now: now, day: day.adding(days: -5))
    state.recordFailure(now: now, error: "Server")
    // Erfolg vor 5 Tagen, danach nur Fehler: Abruf ab Tag −8 (3 Tage Überlappung).
    #expect(state.window(today: day, initialDays: 28) == DateRange(start: day.adding(days: -8), end: day))
    state.recordSuccess(now: now, day: day.adding(days: -400))
    #expect(state.window(today: day, initialDays: 28, maxDays: 180).start == day.adding(days: -179))
  }
}
