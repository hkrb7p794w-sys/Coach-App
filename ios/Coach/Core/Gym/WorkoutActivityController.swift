import ActivityKit
import Foundation

/// Startet, aktualisiert und beendet die Live-Aktivität der laufenden Einheit.
enum WorkoutActivityController {
  /// Nach jeder Änderung der Einheit; `state == nil` oder ausgeschaltet beendet die Aktivität.
  static func update(_ state: WorkoutActivityAttributes.ContentState?, title: String, enabled: Bool) {
    let running = Activity<WorkoutActivityAttributes>.activities
    guard enabled, let state else {
      for activity in running {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
      return
    }
    let content = ActivityContent(state: state, staleDate: nil)
    if let activity = running.first {
      Task { await activity.update(content) }
    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
      _ = try? Activity.request(attributes: WorkoutActivityAttributes(title: title), content: content)
    }
  }

  /// Knöpfe der Live-Aktivität an die Einheit anbinden (auch wenn iOS die App dafür im Hintergrund startet).
  static func connect(_ viewModel: GymViewModel) {
    WorkoutActions.handler = { action in
      switch action {
      case .completeSet: viewModel.completeCurrent()
      case .skipRest: viewModel.skipRest()
      }
      update(viewModel.liveState, title: viewModel.active?.title ?? "", enabled: true)
    }
  }
}
