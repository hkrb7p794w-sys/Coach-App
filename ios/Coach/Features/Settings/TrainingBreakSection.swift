import CoachCore
import SwiftUI

/// Urlaub oder Trainingspause: Zeitraum ohne Erinnerungen und ohne „verpasst“ (`TrainingBreak`).
struct TrainingBreakSection: View {
  @Environment(AppModel.self) private var model
  @State private var start = Date.now
  @State private var end = Date.now.addingTimeInterval(7 * 86_400)

  var body: some View {
    let today = CalendarDay(date: .now)
    Section {
      if let pause = model.settings.activeBreak(today: today) {
        LabeledContent("Pause", value: pause.label)
        Button("Pause beenden", role: .destructive) { model.settings.trainingBreak = nil }
      } else {
        DatePicker("Von", selection: $start, displayedComponents: .date)
        DatePicker("Bis", selection: $end, in: start..., displayedComponents: .date)
        Button("Pause eintragen", systemImage: "suitcase") {
          model.settings.trainingBreak = TrainingBreak(start: CalendarDay(date: start), end: CalendarDay(date: end))
          Task { await model.refreshReminders() }
        }
      }
    } header: {
      Text("Urlaub oder Pause")
    } footer: {
      Text(
        "Im Zeitraum keine Erinnerungen an Einheiten, nichts gilt als verpasst, und Begleiter und Rangliste zählen "
          + "die Tage nicht. Training, das du trotzdem machst, wird normal erfasst."
      )
    }
  }
}
