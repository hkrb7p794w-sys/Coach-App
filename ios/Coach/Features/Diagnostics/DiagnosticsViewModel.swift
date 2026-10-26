import CoachCore
import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsViewModel {
  private(set) var healthDiagnosis: HealthAccessDiagnosis = .notDetermined
  private(set) var isChecking = false

  private let probe: any HealthAccessProbing
  private let bundle: Bundle

  init(probe: any HealthAccessProbing = HealthKitProbe(), bundle: Bundle = .main) {
    self.probe = probe
    self.bundle = bundle
  }

  var versionText: String {
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "\(version) (\(build))"
  }

  func checkHealthKit() async {
    guard !isChecking else { return }
    isChecking = true
    healthDiagnosis = await probe.run()
    isChecking = false
  }
}
