import CoachCore
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

  private(set) var isImporting = false
  private(set) var lastResult: String?

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

  static var readTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis)]
    for identifier in quantityTypes { types.insert(HKQuantityType(identifier)) }
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
      let fresh = HealthImport.newActivities(
        workouts, existing: existing, ownBundle: Bundle.main.bundleIdentifier ?? "io.github.hkrb7p794w.coach")
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
    defaults.set(now, forKey: Self.lastImportKey)
    var text = "\(daysUpdated) Tage, \(added) neue Workouts aus Apple Health"
    if !problems.isEmpty { text += " · nicht lesbar: \(problems.joined(separator: ", "))" }
    lastResult = text
  }

  // MARK: - Speichern

  private func saveMetrics(_ map: [CalendarDay: DailyMetrics]) -> Int {
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
