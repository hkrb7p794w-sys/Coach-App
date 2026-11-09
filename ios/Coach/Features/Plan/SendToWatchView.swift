import CoachCore
import SwiftUI

/// Knopf „An die Uhr senden“: Tag wählen, Schritte prüfen, senden. Nur auf Wunsch je Einheit.
struct SendToWatchButton: View {
  let plan: GarminWorkout.Plan
  let day: CalendarDay
  @State private var showing = false

  var body: some View {
    Button("An die Uhr senden", systemImage: "applewatch.radiowaves.left.and.right") { showing = true }
      .sheet(isPresented: $showing) {
        NavigationStack {
          SendToWatchSheet(plan: plan, initialDay: day)
        }
      }
  }
}

struct SendToWatchSheet: View {
  let plan: GarminWorkout.Plan
  let initialDay: CalendarDay
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var date = Date.now
  @State private var sending = false
  @State private var message: String?

  var body: some View {
    let day = CalendarDay(date: date)
    let sentBefore = model.settings.sentWorkouts.ids[SentWorkouts.key(name: plan.name, day: day)] != nil
    Form {
      Section {
        DatePicker("Tag", selection: $date, in: Date.now.addingTimeInterval(-86_400)..., displayedComponents: .date)
      } footer: {
        if sentBefore {
          Text("Für diesen Tag schon gesendet – erneutes Senden ersetzt das Workout.")
        }
      }
      Section("Schritte auf der Uhr") {
        ForEach(Array(GarminWorkout.summary(plan.steps).enumerated()), id: \.offset) { _, line in
          Text(line)
        }
      }
      if let message {
        Section {
          Text(message)
        }
      }
      Section {
        Button(sending ? "Wird gesendet …" : "Senden") {
          sending = true
          Task {
            message = await GarminWorkoutService.send(plan, day: day, model: model)
            sending = false
          }
        }
        .disabled(sending)
      } footer: {
        Text(
          "Das Workout landet im Garmin-Connect-Kalender und beim nächsten Synchronisieren auf der Uhr. Ziele "
            + "(Pace, Puls) stehen als Notiz am Schritt. Garmin kann diese inoffizielle Schnittstelle jederzeit "
            + "ändern."
        )
      }
    }
    .navigationTitle(plan.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Fertig") { dismiss() }
      }
    }
    .onAppear { date = initialDay.localDate }
  }
}
