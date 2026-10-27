import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CoachWidgetsBundle: WidgetBundle {
  var body: some Widget {
    WorkoutLiveActivity()
  }
}

/// Pause und nächster Satz auf dem Sperrbildschirm und in der Dynamic Island, mit „Satz erledigt“ zum Antippen –
/// ohne Entsperren mit verschwitzten Händen.
struct WorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      LockScreenView(state: context.state, title: context.attributes.title)
        .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.exercise).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          RestTimer(end: context.state.restEndsAt).font(.title3.bold())
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            Text(context.state.detail).font(.subheadline).foregroundStyle(.secondary)
            ActionButtons(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "dumbbell.fill")
      } compactTrailing: {
        RestTimer(end: context.state.restEndsAt).frame(maxWidth: 48)
      } minimal: {
        Image(systemName: "dumbbell.fill")
      }
    }
  }
}

private struct LockScreenView: View {
  let state: WorkoutActivityAttributes.ContentState
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.caption).foregroundStyle(.secondary)
          Text(state.exercise).font(.headline).lineLimit(1)
          Text(state.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        RestTimer(end: state.restEndsAt).font(.system(size: 34, weight: .bold, design: .rounded))
      }
      ActionButtons(state: state)
    }
  }
}

/// Restzeit der Pause; ohne Pause „Los“.
private struct RestTimer: View {
  let end: Date?

  var body: some View {
    if let end, end > .now {
      Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
    } else {
      Text("Los").bold()
    }
  }
}

private struct ActionButtons: View {
  let state: WorkoutActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 10) {
      if !state.allDone {
        Button(intent: CompleteSetIntent()) {
          Label("Satz erledigt", systemImage: "checkmark").frame(maxWidth: .infinity)
        }
        .tint(.green)
      }
      if let end = state.restEndsAt, end > .now {
        Button(intent: SkipRestIntent()) {
          Label("Weiter", systemImage: "forward.fill")
        }
      }
    }
    .font(.headline)
  }
}
