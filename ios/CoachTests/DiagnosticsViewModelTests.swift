import CoachCore
import Testing

@testable import Coach

@MainActor
private final class FakeProbe: HealthAccessProbing {
  let result: HealthAccessDiagnosis
  private(set) var runs = 0

  init(result: HealthAccessDiagnosis) {
    self.result = result
  }

  func run() async -> HealthAccessDiagnosis {
    runs += 1
    return result
  }
}

@MainActor
struct DiagnosticsViewModelTests {
  @Test func startsUndetermined() {
    let viewModel = DiagnosticsViewModel(probe: FakeProbe(result: .missingEntitlement))
    #expect(viewModel.healthDiagnosis == .notDetermined)
    #expect(!viewModel.isChecking)
  }

  @Test func checkStoresProbeResult() async {
    let probe = FakeProbe(result: .missingEntitlement)
    let viewModel = DiagnosticsViewModel(probe: probe)

    await viewModel.checkHealthKit()

    #expect(viewModel.healthDiagnosis == .missingEntitlement)
    #expect(!viewModel.isChecking)
    #expect(probe.runs == 1)
  }
}
