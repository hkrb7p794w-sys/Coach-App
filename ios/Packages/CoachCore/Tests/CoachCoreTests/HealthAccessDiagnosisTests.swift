import CoachCore
import Testing

struct HealthAccessDiagnosisTests {
  private let missingEntitlement = HealthErrorInfo(
    domain: "com.apple.healthkit",
    code: 4,
    message: "Missing com.apple.developer.healthkit entitlement."
  )

  @Test func unavailableDeviceWins() {
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: false,
      authorizationError: missingEntitlement,
      workoutShareStatus: .authorized,
      readableWorkouts: 3
    )
    #expect(result == .unavailable)
  }

  @Test func missingEntitlementFromAuthorization() {
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: missingEntitlement,
      workoutShareStatus: nil,
      readableWorkouts: nil
    )
    #expect(result == .missingEntitlement)
    #expect(!result.isUsable)
  }

  @Test func missingEntitlementFromQuery() {
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: nil,
      workoutShareStatus: .notDetermined,
      readableWorkouts: nil,
      queryError: missingEntitlement
    )
    #expect(result == .missingEntitlement)
  }

  @Test func otherAuthorizationErrorIsReported() {
    let error = HealthErrorInfo(domain: "com.apple.healthkit", code: 3, message: "Invalid argument")
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: error,
      workoutShareStatus: nil,
      readableWorkouts: nil
    )
    #expect(result == .failed("Invalid argument (com.apple.healthkit 3)"))
  }

  @Test func authorizedWithWorkouts() {
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: nil,
      workoutShareStatus: .authorized,
      readableWorkouts: 12
    )
    #expect(result == .working(readableWorkouts: 12))
    #expect(result.isUsable)
    #expect(result.detail.contains("12 Workouts"))
  }

  @Test func authorizedButQueryFailedHidesCount() {
    let error = HealthErrorInfo(domain: "com.apple.healthkit", code: 5, message: "Not determined")
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: nil,
      workoutShareStatus: .authorized,
      readableWorkouts: 7,
      queryError: error
    )
    #expect(result == .working(readableWorkouts: nil))
  }

  @Test(arguments: [
    (WorkoutShareStatus.denied, HealthAccessDiagnosis.denied),
    (WorkoutShareStatus.notDetermined, HealthAccessDiagnosis.notDetermined),
  ])
  func shareStatusMapping(status: WorkoutShareStatus, expected: HealthAccessDiagnosis) {
    let result = HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: nil,
      workoutShareStatus: status,
      readableWorkouts: nil
    )
    #expect(result == expected)
  }
}
