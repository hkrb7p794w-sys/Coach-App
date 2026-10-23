import CoachCore
import Foundation
import HealthKit

/// Prüft, ob HealthKit in dieser Installation funktioniert.
@MainActor
protocol HealthAccessProbing {
  func run() async -> HealthAccessDiagnosis
}

/// Fragt die Rechte an, die die App später braucht (lesen: Workouts, Schlaf,
/// Herzfrequenz; schreiben: Workouts für Krafttraining), und bewertet das
/// Ergebnis mit `HealthAccessDiagnosis.evaluate`.
@MainActor
final class HealthKitProbe: HealthAccessProbing {
  static let readTypes: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    HKCategoryType(.sleepAnalysis),
    HKQuantityType(.heartRate),
    HKQuantityType(.restingHeartRate),
    HKQuantityType(.heartRateVariabilitySDNN),
  ]
  static let shareTypes: Set<HKSampleType> = [
    HKObjectType.workoutType(),
    HKQuantityType(.activeEnergyBurned),
  ]

  private let store = HKHealthStore()

  func run() async -> HealthAccessDiagnosis {
    guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }

    var authorizationError: HealthErrorInfo?
    do {
      try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    } catch {
      authorizationError = HealthErrorInfo(error)
    }

    var readableWorkouts: Int?
    var queryError: HealthErrorInfo?
    if authorizationError == nil {
      do {
        readableWorkouts = try await workoutCount(lastDays: 30)
      } catch {
        queryError = HealthErrorInfo(error)
      }
    }

    return .evaluate(
      isHealthDataAvailable: true,
      authorizationError: authorizationError,
      workoutShareStatus: WorkoutShareStatus(store.authorizationStatus(for: .workoutType())),
      readableWorkouts: readableWorkouts,
      queryError: queryError
    )
  }

  private func workoutCount(lastDays days: Int) async throws -> Int {
    let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.workout(predicate)],
      sortDescriptors: []
    )
    return try await descriptor.result(for: store).count
  }
}

extension HealthErrorInfo {
  init(_ error: any Error) {
    let nsError = error as NSError
    self.init(domain: nsError.domain, code: nsError.code, message: nsError.localizedDescription)
  }
}

extension WorkoutShareStatus {
  init(_ status: HKAuthorizationStatus) {
    switch status {
    case .sharingAuthorized: self = .authorized
    case .sharingDenied: self = .denied
    case .notDetermined: self = .notDetermined
    @unknown default: self = .notDetermined
    }
  }
}
