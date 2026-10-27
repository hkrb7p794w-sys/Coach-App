import CoachCore
import SwiftUI

/// Auslassen, Verschieben und Rückgängig für die Einheiten eines Tages – nur für diese Woche.
struct PlanDayActions: View {
  let day: CalendarDay
  /// Vom Tagesampel vorgeschlagener Zieltag (zuerst angeboten).
  var suggested: Weekday?
  @Environment(AppModel.self) private var model

  var body: some View {
    let settings = model.settings
    let weekday = Weekday(day: day)
    let schedule = settings.schedule(inWeekOf: day)
    let options = moveOptions(schedule: schedule)
    let note = settings.planAdjustments.note(for: weekday, inWeekOf: day)
    // Nebeneinander, wenn genug Platz ist; sonst untereinander (kleines iPhone, große Schrift).
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) { buttons(schedule: schedule, weekday: weekday, options: options, note: note) }
      VStack(alignment: .leading, spacing: 8) {
        buttons(schedule: schedule, weekday: weekday, options: options, note: note)
      }
    }
    .font(.subheadline)
    .labelStyle(.titleAndIcon)
  }

  @ViewBuilder
  private func buttons(schedule: WeekSchedule, weekday: Weekday, options: [Weekday], note: String?) -> some View {
    if !schedule.slots(on: weekday).isEmpty {
      if !options.isEmpty {
        Menu {
          ForEach(options) { target in
            Button(target == suggested ? "\(target.long) (empfohlen)" : target.long) {
              model.reminders.move(day, to: target)
            }
          }
        } label: {
          Label("Verschieben", systemImage: "arrow.turn.down.right")
        }
        .buttonStyle(.bordered)
      }
      Button("Diese Woche auslassen", systemImage: "forward.end") {
        model.reminders.skip(day)
      }
      .buttonStyle(.bordered)
    }
    if note != nil {
      Button("Rückgängig", systemImage: "arrow.uturn.backward") {
        model.settings.planAdjustments.undo(weekday, inWeekOf: day)
      }
      .buttonStyle(.bordered)
    }
  }

  private func moveOptions(schedule: WeekSchedule) -> [Weekday] {
    let options = PlanMoveAdvisor.options(
      for: Weekday(day: day), schedule: schedule, profile: model.settings.profile, today: day)
    guard let suggested, options.contains(suggested) else { return options }
    return [suggested] + options.filter { $0 != suggested }
  }
}

/// Aus einer Mitteilung geöffnet: Einheit des Tages verschieben oder auslassen.
struct AdjustDaySheet: View {
  let day: CalendarDay
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let settings = model.settings
    let weekday = Weekday(day: day)
    let schedule = settings.schedule(inWeekOf: day)
    let slots = schedule.slots(on: weekday)
    let options = PlanMoveAdvisor.options(
      for: weekday, schedule: schedule, profile: settings.profile, today: CalendarDay(date: .now), limit: 6)
    NavigationStack {
      List {
        if slots.isEmpty {
          Section {
            Text(
              settings.planAdjustments.note(for: weekday, inWeekOf: day).map { "\(weekday.long): \($0)." }
                ?? "Für \(weekday.long) ist nichts geplant.")
          }
        } else {
          Section("\(weekday.long)") {
            ForEach(slots) { slot in
              Label(slot.title, systemImage: slot.sport.symbol)
            }
          }
          Section {
            ForEach(options) { target in
              Button {
                model.reminders.move(day, to: target)
                dismiss()
              } label: {
                LabeledContent(target.long, value: dayDescription(schedule.slots(on: target)))
              }
            }
          } header: {
            Text("Verschieben auf")
          } footer: {
            Text(
              options.isEmpty
                ? "Diese Woche ist kein späterer Tag mehr frei."
                : "Die besten Tage stehen oben: möglichst kein harter Tag direkt neben einem anderen.")
          }
          Section {
            Button("Diese Woche auslassen", role: .destructive) {
              model.reminders.skip(day)
              dismiss()
            }
          } footer: {
            Text("Der Wochenplan selbst bleibt unverändert; nächste Woche gilt er wieder.")
          }
        }
      }
      .navigationTitle("Einheit anpassen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
      }
    }
  }

  private func dayDescription(_ slots: [SessionSlot]) -> String {
    slots.isEmpty ? "frei" : slots.map(\.chipLabel).joined(separator: ", ")
  }
}
