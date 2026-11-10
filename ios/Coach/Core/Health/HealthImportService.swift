import CoachCore
import CoreLocation
import Foundation
import HealthKit
import Observation
import SwiftData

/// Liest Tageswerte, Schlaf, Workouts und Gewicht aus Apple Health (Apple Watch, iPhone, andere Apps) und
/// ergänzt damit die Garmin-Daten. Garmin hat Vorrang; Health füllt nur Lücken (`HealthImport`).
/// HealthKit ist optional: Ohne Entitlement oder Berechtigung bleibt es bei einer Meldung.
@Observable
final class HealthImportService {
  static let enabledKey = "health.importEnabled"
  static let lastImportKey = "health.lastImport"
  static let weightsKey = "health.weights"
  static let firstImportDays = 120

  @ObservationIgnored private let store = HKHealthStore()
  @ObservationIgnored private let context: ModelContext
  @ObservationIgnored private let defaults: UserDefaults
  /// Gemeinsame Ablage aller Quellen (Herkunft, Vorrang je Datenart).
  @ObservationIgnored var sources: SourceStore?
  /// Ablage der vollständigen Aktivitätsberichte (gemeinsam mit dem Garmin-Abruf).
  @ObservationIgnored var reportStore: ActivityReportStore?
  static let failedRecordingsKey = "health.recordingFailures"
  /// Workouts je Import, deren Verlauf nachgeladen wird (der Rest folgt beim nächsten Import).
  static let maxRecordingsPerImport = 8

  private(set) var isImporting = false
  private(set) var lastResult: String?
  /// Fehler des letzten Imports (`nil` = alles lesbar), für den Synchronisierungsstatus.
  private(set) var lastProblem: String?

  init(context: ModelContext, defaults: UserDefaults = .standard) {
    self.context = context
    self.defaults = defaults
  }

  var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  var isEnabled: Bool {
    get {
      access(keyPath: \.isEnabled)
      return defaults.bool(forKey: Self.enabledKey)
    }
    set {
      withMutation(keyPath: \.isEnabled) { defaults.set(newValue, forKey: Self.enabledKey) }
    }
  }

  var lastImport: Date? { defaults.object(forKey: Self.lastImportKey) as? Date }

  /// Wägungen aus Apple Health (letzte 120 Tage).
  var weights: [WeightEntry] {
    defaults.data(forKey: Self.weightsKey).flatMap { try? JSONDecoder().decode([WeightEntry].self, from: $0) } ?? []
  }

  static let quantityTypes: [HKQuantityTypeIdentifier] = [
    .stepCount, .activeEnergyBurned, .basalEnergyBurned, .restingHeartRate, .heartRateVariabilitySDNN,
    .respiratoryRate, .oxygenSaturation, .vo2Max, .bodyMass, .heartRate, .distanceWalkingRunning,
    .distanceCycling, .distanceSwimming,
  ]

  /// Für den Verlauf eines Workouts: Strecke und Leistung (Puls und Distanz stehen schon oben).
  static let recordingTypes: [HKQuantityTypeIdentifier] = [.runningPower, .cyclingPower]

  static var readTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [
      HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis), HKSeriesType.workoutRoute(),
    ]
    for identifier in quantityTypes + recordingTypes { types.insert(HKQuantityType(identifier)) }
    return types
  }

  /// Einmal Berechtigung anfragen (iOS zeigt die Abfrage nur für neue Datentypen).
  func requestAccess() async throws {
    guard isAvailable else { throw WorkoutWriterError.unavailable }
    try await store.requestAuthorization(
      toShare: HealthKitProbe.shareTypes, read: Self.readTypes.union(HealthKitProbe.readTypes))
  }

  /// Import seit dem letzten Mal (mit drei Tagen Überlappung, weil Schlaf und Werte nachträglich eintreffen).
  /// `garminConnected`: HRV aus Health nur ohne Garmin (SDNN statt RMSSD, siehe `HealthImport`).
  func importNow(garminConnected: Bool, now: Date = .now) async {
    guard isEnabled, isAvailable, !isImporting else { return }
    isImporting = true
    defer { isImporting = false }
    let calendar = Calendar.current
    let start =
      lastImport.flatMap { calendar.date(byAdding: .day, value: -3, to: $0) }
      ?? calendar.date(byAdding: .day, value: -Self.firstImportDays, to: now) ?? now
    let dayStart = calendar.startOfDay(for: start)
    var problems: [String] = []
    do {
      try await requestAccess()
    } catch {
      lastResult = "Keine Berechtigung: \(error.localizedDescription)"
      lastProblem = lastResult
      return
    }

    // Tageswerte
    var days: [CalendarDay: HealthImport.DayValues] = [:]
    func record(
      _ identifier: HKQuantityTypeIdentifier, _ options: HKStatisticsOptions, unit: HKUnit,
      _ assign: (inout HealthImport.DayValues, Double) -> Void
    ) async {
      do {
        let values = try await statistics(identifier, options: options, unit: unit, from: dayStart, to: now)
        for (day, value) in values {
          assign(&days[day, default: HealthImport.DayValues(day: day)], value)
        }
      } catch {
        problems.append(identifier.rawValue.replacingOccurrences(of: "HKQuantityTypeIdentifier", with: ""))
      }
    }
    let perMinute = HKUnit.count().unitDivided(by: .minute())
    await record(.stepCount, .cumulativeSum, unit: .count()) { $0.steps = $1 }
    await record(.activeEnergyBurned, .cumulativeSum, unit: .kilocalorie()) { $0.activeKilocalories = $1 }
    await record(.basalEnergyBurned, .cumulativeSum, unit: .kilocalorie()) { $0.basalKilocalories = $1 }
    await record(.restingHeartRate, .discreteAverage, unit: perMinute) { $0.restingHeartRate = $1 }
    await record(.heartRateVariabilitySDNN, .discreteAverage, unit: .secondUnit(with: .milli)) {
      $0.hrvSDNN = $1
    }
    await record(.respiratoryRate, .discreteAverage, unit: perMinute) { $0.respiratoryRate = $1 }
    await record(.oxygenSaturation, .discreteAverage, unit: .percent()) { $0.oxygenSaturation = $1 }
    await record(.oxygenSaturation, .discreteMin, unit: .percent()) { $0.oxygenSaturationLowest = $1 }
    let vo2Unit = HKUnit.literUnit(with: .milli)
      .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    await record(.vo2Max, .discreteAverage, unit: vo2Unit) { $0.vo2Max = $1 }

    var map: [CalendarDay: DailyMetrics] = [:]
    for (day, values) in days { map[day] = HealthImport.metrics(values, includeHRV: !garminConnected) }
    do {
      let samples = try await sleepSamples(from: dayStart.addingTimeInterval(-86_400), to: now)
      for (day, night) in HealthImport.sleep(samples) {
        map[day] = map[day].map { $0.merging(night) } ?? night
      }
    } catch {
      problems.append("Schlaf")
    }
    let daysUpdated = saveMetrics(map)

    // Workouts
    var added = 0
    do {
      let workouts = try await workouts(from: dayStart, to: now)
      let existing = ((try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []).compactMap(\.activity)
      let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let ownBundle = Bundle.main.bundleIdentifier ?? "io.github.hkrb7p794w.coach"
      // Herkunft aller gelesenen Workouts (vollständiger Zeitraum: fehlende gelten als in Health gelöscht).
      let all = workouts.filter { $0.sourceBundle != ownBundle && !$0.sourceBundle.hasPrefix(ownBundle + ".") }
        .map { HealthImport.activity($0) }
      let allowed = sources?.recordActivities(
        all, from: .appleHealth, window: DateRange(start: CalendarDay(date: dayStart), end: CalendarDay(date: now)),
        complete: true)
      let fresh = HealthImport.newActivities(workouts, existing: existing, ownBundle: ownBundle)
        .filter { allowed?.contains($0.id) ?? true }
      let records = (try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []
      for activity in fresh {
        if byID[activity.id] != nil {
          records.first { $0.garminID == activity.id }?.update(activity)
        } else {
          context.insert(ActivityRecord(activity: activity))
          added += 1
        }
      }
    } catch {
      problems.append("Workouts")
    }

    // Gewicht
    do {
      let samples = try await bodyMass(from: calendar.date(byAdding: .day, value: -120, to: now) ?? now, to: now)
      let entries = HealthImport.weights(samples)
      defaults.set(try? JSONEncoder().encode(entries), forKey: Self.weightsKey)
    } catch {
      problems.append("Gewicht")
    }

    try? context.save()
    let detailed = await detailWorkouts(now: now)
    defaults.set(now, forKey: Self.lastImportKey)
    var text = "\(daysUpdated) Tage, \(added) neue Workouts aus Apple Health"
    if detailed > 0 { text += ", \(detailed) mit Verlauf" }
    if !problems.isEmpty { text += " · nicht lesbar: \(problems.joined(separator: ", "))" }
    lastResult = text
    lastProblem = problems.isEmpty ? nil : "Nicht lesbar: \(problems.joined(separator: ", "))"
  }

  // MARK: - Speichern

  private func saveMetrics(_ map: [CalendarDay: DailyMetrics]) -> Int {
    if let sources {
      let useful = map.filter { !$0.value.presentFields.isEmpty || $0.value.sleepSeconds != nil }
      sources.ingestDays(useful, from: .appleHealth)
      return useful.count
    }
    let existing = (try? context.fetch(FetchDescriptor<DailyMetricsRecord>())) ?? []
    let byKey = Dictionary(existing.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
    var count = 0
    for (day, health) in map where !health.presentFields.isEmpty || health.sleepSeconds != nil {
      if let record = byKey[day.iso] {
        let filled = HealthImport.fill(record.metrics, with: health)
        if filled != record.metrics {
          record.update(filled)
          count += 1
        }
      } else {
        context.insert(DailyMetricsRecord(metrics: health))
        count += 1
      }
    }
    return count
  }

  // MARK: - HealthKit-Abfragen

  private func statistics(
    _ identifier: HKQuantityTypeIdentifier, options: HKStatisticsOptions, unit: HKUnit, from start: Date,
    to end: Date
  ) async throws -> [CalendarDay: Double] {
    let type = HKQuantityType(identifier)
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let query = HKStatisticsCollectionQueryDescriptor(
      predicate: .quantitySample(type: type, predicate: predicate), options: options, anchorDate: start,
      intervalComponents: DateComponents(day: 1))
    let collection = try await query.result(for: store)
    var result: [CalendarDay: Double] = [:]
    collection.enumerateStatistics(from: start, to: end) { statistics, _ in
      let quantity: HKQuantity? =
        switch options {
        case .cumulativeSum: statistics.sumQuantity()
        case .discreteMin: statistics.minimumQuantity()
        default: statistics.averageQuantity()
        }
      if let quantity {
        result[CalendarDay(date: statistics.startDate)] = quantity.doubleValue(for: unit)
      }
    }
    return result
  }

  private func sleepSamples(from start: Date, to end: Date) async throws -> [HealthImport.SleepSample] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let query = HKSampleQueryDescriptor(
      predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
      sortDescriptors: [])
    return try await query.result(for: store).compactMap { sample in
      let stage: HealthImport.SleepStage? =
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: .inBed
        case .asleepUnspecified: .asleep
        case .awake: .awake
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        default: nil
        }
      guard let stage else { return nil }
      return HealthImport.SleepSample(
        start: sample.startDate, end: sample.endDate, stage: stage,
        source: sample.sourceRevision.source.bundleIdentifier)
    }
  }

  private func workouts(from start: Date, to end: Date) async throws -> [HealthImport.Workout] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
    let perMinute = HKUnit.count().unitDivided(by: .minute())
    return try await query.result(for: store).map { workout in
      let typeKey = Self.typeKey(workout)
      let distanceType: HKQuantityTypeIdentifier =
        switch workout.workoutActivityType {
        case .cycling: .distanceCycling
        case .swimming: .distanceSwimming
        default: .distanceWalkingRunning
        }
      let distance = workout.statistics(for: HKQuantityType(distanceType))?.sumQuantity()?
        .doubleValue(for: .meter())
      let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
        .doubleValue(for: .kilocalorie())
      let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
      let elevation = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
        .doubleValue(for: .meter())
      return HealthImport.Workout(
        uuid: workout.uuid, typeKey: typeKey, start: workout.startDate, end: workout.endDate,
        distanceMeters: distance, kilocalories: energy,
        averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: perMinute),
        maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: perMinute), elevationGain: elevation,
        sourceName: workout.sourceRevision.source.name,
        sourceBundle: workout.sourceRevision.source.bundleIdentifier)
    }
  }

  private func bodyMass(from start: Date, to end: Date) async throws -> [(date: Date, kilograms: Double)] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    let query = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)], sortDescriptors: [])
    return try await query.result(for: store).map {
      (date: $0.startDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
    }
  }

  // MARK: - Verlauf je Workout (Apple Watch)

  /// Für Workouts der letzten Wochen den Verlauf lesen und als Bericht speichern (Runden, Splits, Diagramme,
  /// Auswertung) – wie beim Garmin-Abruf, nur aus HealthKit statt aus der Datei der Uhr.
  private func detailWorkouts(now: Date) async -> Int {
    guard let reportStore else { return 0 }
    let today = CalendarDay(date: now)
    let activities = ((try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []).compactMap(\.activity)
    var reports = reportStore.load()
    var failed = Set((defaults.array(forKey: Self.failedRecordingsKey) as? [Int64]) ?? [])
    let pending = ActivityReportPlanner.pending(
      activities, known: reports, failed: failed, today: today, health: true)
    guard !pending.isEmpty else { return 0 }
    let start = Calendar.current.date(byAdding: .day, value: -(ActivityReportPlanner.days + 1), to: now) ?? now
    guard let workouts = try? await rawWorkouts(from: start, to: now) else { return 0 }
    let byID = Dictionary(
      workouts.map { (HealthImport.activityID($0.uuid), $0) }, uniquingKeysWith: { first, _ in first })
    var count = 0
    for activity in pending {
      guard count < Self.maxRecordingsPerImport else { break }
      // Nicht in Health (von Hand nachgetragen oder dort gelöscht): nicht erneut versuchen.
      guard let workout = byID[activity.id] else {
        failed.insert(activity.id)
        continue
      }
      guard let input = try? await recordingInput(workout) else { continue }
      // Ohne Puls und ohne Distanz (z. B. von Hand eingetragen) gibt es nichts auszuwerten.
      guard !input.heartRate.isEmpty || !input.distance.isEmpty else {
        failed.insert(activity.id)
        continue
      }
      reports[activity.id] = ActivityReportBuilder.build(activity, fit: HealthRecording.fit(input))
      count += 1
    }
    reportStore.save(reports, today: today)
    defaults.set(Array(failed.suffix(200)), forKey: Self.failedRecordingsKey)
    return count
  }

  /// Aufzeichnung eines Workouts für die Detailansicht (mit Strecke für die Karte); `nil`, wenn nicht lesbar.
  func recording(for activityID: Int64, around day: CalendarDay?) async -> FitActivity? {
    guard isEnabled, isAvailable, activityID < 0 else { return nil }
    let center = day?.referenceDate ?? .now
    let start = center.addingTimeInterval(-2 * 86_400)
    let end = center.addingTimeInterval(2 * 86_400)
    guard let workouts = try? await rawWorkouts(from: start, to: end),
      let workout = workouts.first(where: { HealthImport.activityID($0.uuid) == activityID }),
      let input = try? await recordingInput(workout)
    else { return nil }
    let fit = HealthRecording.fit(input)
    return fit.records.isEmpty ? nil : fit
  }

  private func rawWorkouts(from start: Date, to end: Date) async throws -> [HKWorkout] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
    return try await HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
      .result(for: store)
  }

  /// Puls, Distanz, Leistung, Strecke, Runden und Pausen eines Workouts.
  private func recordingInput(_ workout: HKWorkout) async throws -> HealthRecording.Input {
    func seconds(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate }
    var input = HealthRecording.Input(start: seconds(workout.startDate), end: seconds(workout.endDate))
    let attached = HKQuery.predicateForObjects(from: workout)
    let range = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
    let perMinute = HKUnit.count().unitDivided(by: .minute())

    // Puls: zum Workout gehörende Werte, sonst alle im Zeitraum (manche Uhren verknüpfen sie nicht).
    var heartRate = try await quantities(.heartRate, predicate: attached)
    if heartRate.isEmpty { heartRate = try await quantities(.heartRate, predicate: range) }
    input.heartRate = heartRate.map {
      HealthRecording.Sample(time: seconds($0.startDate), value: $0.quantity.doubleValue(for: perMinute))
    }

    // Distanz nur aus dem Workout selbst: Im Zeitraum zählen iPhone und Uhr sonst doppelt.
    let distanceType: HKQuantityTypeIdentifier =
      switch workout.workoutActivityType {
      case .cycling, .handCycling: .distanceCycling
      case .swimming: .distanceSwimming
      default: .distanceWalkingRunning
      }
    input.distance = try await quantities(distanceType, predicate: attached).map {
      HealthRecording.Amount(
        start: seconds($0.startDate), end: seconds($0.endDate), value: $0.quantity.doubleValue(for: .meter()))
    }

    let powerType: HKQuantityTypeIdentifier =
      workout.workoutActivityType == .cycling ? .cyclingPower : .runningPower
    input.power = ((try? await quantities(powerType, predicate: attached)) ?? []).map {
      HealthRecording.Sample(time: seconds($0.startDate), value: $0.quantity.doubleValue(for: .watt()))
    }

    // Strecke: fehlt die Berechtigung oder gibt es keine (Halle), bleibt sie leer.
    let routes =
      (try? await HKSampleQueryDescriptor(predicates: [.workoutRoute(attached)], sortDescriptors: [])
        .result(for: store)) ?? []
    for route in routes {
      guard let locations = try? await routeLocations(route) else { continue }
      input.locations += locations
    }

    var pauseStart: Date?
    for event in workout.workoutEvents ?? [] {
      switch event.type {
      case .lap:
        let interval = event.dateInterval
        if interval.duration > 0 {
          input.laps.append(HealthRecording.Interval(start: seconds(interval.start), end: seconds(interval.end)))
        }
      case .pause, .motionPaused:
        pauseStart = pauseStart ?? event.dateInterval.start
      case .resume, .motionResumed:
        if let begin = pauseStart {
          input.pauses.append(
            HealthRecording.Interval(start: seconds(begin), end: seconds(event.dateInterval.start)))
          pauseStart = nil
        }
      default: break
      }
    }
    return input
  }

  private func quantities(_ identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async throws
    -> [HKQuantitySample]
  {
    try await HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
      sortDescriptors: [SortDescriptor(\.startDate)]
    ).result(for: store)
  }

  /// Punkte einer Strecke, auf etwa einen je 5 s ausgedünnt.
  private func routeLocations(_ route: HKWorkoutRoute) async throws -> [HealthRecording.Location] {
    var result: [HealthRecording.Location] = []
    var last = -Double.infinity
    for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
      let time = location.timestamp.timeIntervalSinceReferenceDate
      guard time - last >= HealthRecording.step else { continue }
      last = time
      result.append(
        HealthRecording.Location(
          time: time, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
          altitude: location.verticalAccuracy >= 0 ? location.altitude : nil))
    }
    return result
  }

  /// Apple-Sportart als Garmin-Schlüssel, damit Wochen-Soll/Ist, Belastung und Ernährung gleich rechnen.
  static func typeKey(_ workout: HKWorkout) -> String {
    switch workout.workoutActivityType {
    case .running: "running"
    case .cycling, .handCycling: "cycling"
    case .swimming:
      (workout.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber)?.intValue
        == HKWorkoutSwimmingLocationType.openWater.rawValue ? "open_water_swimming" : "lap_swimming"
    case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: "strength_training"
    case .walking: "walking"
    case .hiking: "hiking"
    case .highIntensityIntervalTraining, .mixedCardio, .crossTraining: "hiit"
    case .yoga, .pilates, .flexibility, .mindAndBody: "yoga"
    case .rowing: "indoor_rowing"
    case .elliptical: "elliptical"
    default: "other"
    }
  }
}
