import CoachCore
import Foundation
import HealthKit

/// Speichert eine Krafteinheit als Workout in Apple Health.
@MainActor
protocol WorkoutSaving {
  var isAvailable: Bool { get }
  func save(_ session: GymSession) async throws
}

enum WorkoutWriterError: LocalizedError {
  case unavailable
  case notAuthorized

  var errorDescription: String? {
    switch self {
    case .unavailable: "Apple Health ist auf diesem Gerät nicht verfügbar."
    case .notAuthorized:
      "Keine Schreibberechtigung für Workouts. Einstellungen › Health › Datenzugriff › Coach prüfen."
    }
  }
}

/// HealthKit ist optional (SideStore kann das Entitlement entfernen); Fehler landen als Text in der App.
@MainActor
final class HealthWorkoutWriter: WorkoutSaving {
  private let store = HKHealthStore()

  var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func save(_ session: GymSession) async throws {
    guard isAvailable else { throw WorkoutWriterError.unavailable }
    let workoutType = HKObjectType.workoutType()
    if store.authorizationStatus(for: workoutType) == .notDetermined {
      try await store.requestAuthorization(toShare: HealthKitProbe.shareTypes, read: HealthKitProbe.readTypes)
    }
    guard store.authorizationStatus(for: workoutType) == .sharingAuthorized else {
      throw WorkoutWriterError.notAuthorized
    }

    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .traditionalStrengthTraining
    configuration.locationType = .indoor
    let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
    let end = session.end ?? .now
    try await builder.beginCollection(at: session.start)
    try await builder.addMetadata([
      HKMetadataKeyExternalUUID: session.id.uuidString,
      HKMetadataKeyWorkoutBrandName: session.title,
      HKMetadataKeyIndoorWorkout: true,
    ])
    try await builder.endCollection(at: end)
    _ = try await builder.finishWorkout()
  }
}
