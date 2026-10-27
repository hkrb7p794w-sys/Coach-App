import CoachCore
import SwiftUI

/// „Nächste Woche planen“ (aus der Sonntags-Erinnerung oder dem Plan-Reiter). Eigener Wochenplan: die Tage der
/// nächsten Woche nur für diese Woche anpassen; der Wochenplan bleibt. Saisonplan: die Einheiten der nächsten
/// Woche mit Ausrüstung im Überblick.
struct NextWeekPlanSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var schedule = WeekSchedule()
  @State private var loaded = false

  private var nextMonday: CalendarDay {
    PlanAdjustments.monday(of: CalendarDay(date: .now)).adding(days: 7)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Woche ab \(GermanFormat.date(nextMonday))").font(.headline)
        }
        if model.settings.profile.mode == .personal {
          personal
        } else {
          season
        }
      }
      .navigationTitle("Nächste Woche planen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if model.settings.profile.mode == .personal {
          ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Sichern") {
              model.settings.planAdjustments.setWeekPlan(
                schedule, base: model.settings.profile.schedule, inWeekOf: nextMonday)
              dismiss()
            }
          }
        } else {
          ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
        }
      }
      .onAppear {
        guard !loaded else { return }
        loaded = true
        schedule = model.settings.schedule(inWeekOf: nextMonday)
      }
    }
  }

  // MARK: - Eigener Wochenplan

  @ViewBuilder private var personal: some View {
    let profile = model.settings.profile
    Section {
      ScheduleEditor(schedule: $schedule, sports: profile.sports, highlight: nil)
    } footer: {
      Text(
        "Gilt nur für diese Woche – Termine, Urlaub oder Wetter. Dein Wochenplan bleibt unverändert; die "
          + "Erinnerungen richten sich nach diesem Plan.")
    }
    ScheduleHintsSection(hints: ScheduleCheck.hints(schedule: schedule, profile: profile))
    if schedule != profile.schedule {
      Section {
        Button("Wie im Wochenplan", systemImage: "arrow.uturn.backward") { schedule = profile.schedule }
      }
    }
  }

  // MARK: - Saisonplan

  @ViewBuilder private var season: some View {
    if let plan = SeasonSchedule.load(), let week = plan.week(containing: nextMonday) {
      let settings = model.settings
      let units = plan.units(for: week, config: settings.season, decisions: settings.competitionDecisions)
      Section {
        ForEach(units) { unit in
          VStack(alignment: .leading, spacing: 2) {
            Text(unit.title).font(.subheadline.weight(.medium))
            if !unit.detail.isEmpty {
              Text(unit.detail).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Einheiten · \(week.ph)")
      } footer: {
        if !week.f.isEmpty { Text(week.f) }
      }
      let equipment = SwimStepText.equipment(in: week.ss ?? [])
      if !equipment.isEmpty {
        Section("Fürs Schwimmen einpacken") {
          Label(equipment.joined(separator: ", "), systemImage: "bag")
        }
      }
    } else {
      Text("Für die nächste Woche gibt es keinen Saisonplan mehr.").foregroundStyle(.secondary)
    }
  }
}
