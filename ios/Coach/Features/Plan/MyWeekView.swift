import CoachCore
import SwiftUI

/// Plan-Reiter für Profile ohne Saisonplan: die eigene Woche, Ziel und Hinweise zum Plan.
struct MyWeekView: View {
  @Environment(AppModel.self) private var model
  @State private var editing = false

  var body: some View {
    let profile = model.settings.profile
    let today = Weekday(day: CalendarDay(date: .now))
    NavigationStack {
      List {
        GoalHeader(profile: profile)

        Section {
          ForEach(Weekday.allCases) { weekday in
            WeekDayRow(weekday: weekday, slots: profile.schedule.slots(on: weekday), isToday: weekday == today)
          }
        } header: {
          Text("Meine Woche")
        } footer: {
          if profile.schedule.isEmpty {
            Text("Noch kein Wochenplan. Tippe oben auf „Bearbeiten“.")
          }
        }

        ScheduleHintsSection(hints: ScheduleCheck.hints(schedule: profile.schedule, profile: profile))
      }
      .navigationTitle("Plan")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Bearbeiten") { editing = true }
        }
      }
      .sheet(isPresented: $editing) { ScheduleEditorSheet() }
    }
  }
}

private struct GoalHeader: View {
  let profile: UserProfile

  var body: some View {
    Section {
      HStack(spacing: 12) {
        SportIcon(symbol: profile.goal.symbol, color: .accentColor, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(profile.goal.label).font(.headline)
          if let event = profile.event {
            let days = CalendarDay(date: .now).days(until: event.date)
            Text("\(event.name) · \(days > 0 ? "in \(days) Tagen" : days == 0 ? "heute" : "vorbei")")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          } else {
            Text(profile.sports.map(\.shortLabel).joined(separator: " · "))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

private struct WeekDayRow: View {
  let weekday: Weekday
  let slots: [SessionSlot]
  let isToday: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(weekday.short)
        .font(.subheadline.weight(isToday ? .bold : .semibold))
        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
        .frame(width: 28, alignment: .leading)
      if slots.isEmpty {
        Text("Frei").foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(slots) { slot in
            HStack(alignment: .top, spacing: 10) {
              SportIcon(symbol: slot.sport.symbol, color: slot.sport.color, size: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(slot.title).font(.subheadline.weight(.medium))
                Text(slot.guide).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

/// Wochenplan bearbeiten, mit Hinweisen und dem Zugang zum Profil.
struct ScheduleEditorSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var showProfile = false

  var body: some View {
    @Bindable var settings = model.settings
    NavigationStack {
      Form {
        Section {
          ScheduleEditor(
            schedule: $settings.profile.schedule, sports: settings.profile.sports,
            highlight: Weekday(day: CalendarDay(date: .now)))
        } footer: {
          Text("Tippe auf eine Einheit, um die Intensität zu ändern oder sie zu entfernen.")
        }
        ScheduleHintsSection(hints: ScheduleCheck.hints(schedule: settings.profile.schedule, profile: settings.profile))
        Section {
          Button("Sportarten, Ziel und Körperdaten ändern") { showProfile = true }
        }
      }
      .navigationTitle("Wochenplan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
      .fullScreenCover(isPresented: $showProfile) {
        OnboardingView(isEditing: true, initial: model.settings.profile)
      }
    }
  }
}
