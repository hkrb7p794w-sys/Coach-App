import CoachCore
import SwiftData
import SwiftUI

/// Plan-Reiter für Profile ohne Saisonplan: die eigene Woche, Ziel und Hinweise zum Plan.
struct MyWeekView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymSessions: [GymSessionRecord]
  @Environment(\.modelContext) private var context
  @State private var editing = false
  @State private var addingManual = false
  @State private var planningNextWeek = false
  @State private var guideSlot: SessionSlot?

  var body: some View {
    let profile = model.settings.profile
    let day = CalendarDay(date: .now)
    let today = Weekday(day: day)
    let thisWeek = model.settings.schedule(inWeekOf: day)
    let adjustments = model.settings.planAdjustments
    let monday = PlanAdjustments.monday(of: day)
    let all = activities.compactMap(\.activity)
    let runWeek = RunPlanner.week(profile: profile, schedule: thisWeek, monday: monday, activities: all)
    let sessions = TodayViewModel.sessionWeek(
      settings: model.settings, activities: all, gymDays: gymSessions.compactMap { $0.session?.day }, today: day)
    NavigationStack {
      List {
        GoalHeader(profile: profile)

        Section {
          ForEach(Weekday.allCases) { weekday in
            let date = monday.adding(days: weekday.rawValue)
            WeekDayRow(
              weekday: weekday, slots: thisWeek.slots(on: weekday), isToday: weekday == today,
              note: adjustments.note(for: weekday, inWeekOf: day),
              runs: runWeek?.sessions.filter { $0.weekday == weekday } ?? [],
              results: sessions.results(on: date), select: { guideSlot = $0 }
            ) {
              if weekday.rawValue >= today.rawValue {
                PlanDayMenu(day: date)
              }
            }
            .swipeActions(edge: .trailing) {
              if weekday.rawValue >= today.rawValue, !thisWeek.slots(on: weekday).isEmpty,
                !sessions.allCounted(on: date)
              {
                Button("Auslassen", systemImage: "forward.end", role: .destructive) { model.reminders.skip(date) }
                if let target = PlanMoveAdvisor.options(
                  for: weekday, schedule: thisWeek, profile: profile, today: day, limit: 1
                ).first {
                  Button("Auf \(target.short)", systemImage: "arrow.turn.down.right") {
                    model.reminders.move(date, to: target)
                  }
                  .tint(.blue)
                }
              }
            }
          }
        } header: {
          if let runWeek {
            Text("Diese Woche · \(runWeek.phase.label) · \(runWeek.totalMinutes) min Laufen")
          } else {
            Text("Diese Woche")
          }
        } footer: {
          if profile.schedule.isEmpty {
            Text("Noch kein Wochenplan. Tippe oben auf „Bearbeiten“.")
          } else if !adjustments.changes(inWeekOf: day).isEmpty {
            Text("Änderungen gelten nur für diese Woche; danach gilt wieder dein Wochenplan.")
          } else if let runWeek {
            Text(
              "Laufminuten aus deinem Schnitt der letzten vier Wochen (\(runWeek.baselineMinutes) min): höchstens "
                + "10 % mehr, jede vierte Woche leichter, vor einem Wettkampf weniger.")
          }
        }

        WeekTotalsSection(
          totals: SessionMatcher.totals(
            planned: sessions.results.map(\.planned), activities: all, monday: monday),
          counts: sessions.results)

        ExtraActivitiesSection(
          records: activities.filter { record in
            sessions.extraIDs.contains(record.garminID)
              || (ManualActivity.isManual(record.garminID) && (CalendarDay(iso: record.dayKey).map { $0 >= monday } ?? false))
          },
          delete: { record in
            context.delete(record)
            try? context.save()
          })

        ScheduleHintsSection(hints: ScheduleCheck.hints(schedule: profile.schedule, profile: profile))
      }
      .navigationTitle("Plan")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Nächste Woche", systemImage: "calendar.badge.plus") { planningNextWeek = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Training nachtragen", systemImage: "plus") { addingManual = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Bearbeiten") { editing = true }
        }
      }
      .sheet(isPresented: $editing) { ScheduleEditorSheet() }
      .sheet(isPresented: $addingManual) { ManualActivitySheet() }
      .sheet(isPresented: $planningNextWeek) { NextWeekPlanSheet() }
      .navigationDestination(item: $guideSlot) { slot in SessionGuideView(slot: slot) }
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

private struct WeekDayRow<Actions: View>: View {
  let weekday: Weekday
  let slots: [SessionSlot]
  let isToday: Bool
  let note: String?
  var runs: [RunPlanner.Session] = []
  var results: [SessionResult] = []
  let select: (SessionSlot) -> Void
  @ViewBuilder let actions: () -> Actions
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    // Bei sehr großer Schrift steht der Tag über den Einheiten statt in einer schmalen Spalte.
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    layout {
      Text(typeSize.isAccessibilitySize ? weekday.long : weekday.short)
        .font(.subheadline.weight(isToday ? .bold : .semibold))
        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
        .frame(minWidth: 28, alignment: .leading)
        .fixedSize()
      if slots.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          Text("Frei").foregroundStyle(.secondary)
          if let note {
            Text(note).font(.caption).foregroundStyle(.orange)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          if let note {
            Text(note).font(.caption).foregroundStyle(.orange)
          }
          ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
            let result = results.first { $0.planned.index == index }
            Button {
              select(slot)
            } label: {
              HStack(alignment: .top, spacing: 10) {
                SportIcon(symbol: slot.sport.symbol, color: slot.sport.color, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                  if let run = runs.first(where: { $0.slot == slot }) {
                    Text("\(slot.title) · \(run.minutes) min").font(.subheadline.weight(.medium))
                    Text(run.detail).font(.caption).foregroundStyle(.secondary)
                  } else {
                    Text(slot.title).font(.subheadline.weight(.medium))
                    Text(slot.guide).font(.caption).foregroundStyle(.secondary)
                  }
                  if let result {
                    HStack(spacing: 8) {
                      SessionStatusBadge(status: result.status)
                      if result.actualMinutes != nil || result.status != .planned {
                        Text(result.compareText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                      }
                    }
                    if let note = result.intensityNote {
                      Text(note).font(.caption).foregroundStyle(.orange)
                    }
                  }
                  Label("Ausführlich", systemImage: "info.circle").font(.caption).foregroundStyle(Color.accentColor)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Zeigt die ausführliche Erklärung der Einheit")
          }
        }
      }
      Spacer(minLength: 0)
      actions()
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .contain)
  }
}

/// Soll gegen Ist je Sportart und wie viele Einheiten geschafft sind.
private struct WeekTotalsSection: View {
  let totals: [(sport: TrainingSport, planned: Int, actual: Int)]
  let counts: [SessionResult]

  var body: some View {
    if !totals.isEmpty {
      let done = counts.filter(\.status.counts).count
      Section {
        ForEach(totals.indices, id: \.self) { index in
          let total = totals[index]
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Label(total.sport.label, systemImage: total.sport.symbol)
              Spacer()
              Text("\(total.actual) / \(total.planned) min").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)
            if total.planned > 0 {
              ProgressView(value: min(Double(total.actual) / Double(total.planned), 1))
                .tint(total.sport.color)
            }
          }
          .accessibilityElement(children: .combine)
        }
      } header: {
        Text("Soll / Ist · \(done) von \(counts.count) Einheiten")
      } footer: {
        Text(
          "Erledigt heißt: gleiche Sportart, mindestens \(Int(SessionMatcher.doneShare * 100)) % der geplanten "
            + "Dauer. Rad statt Lauf zählt als „anders gemacht“, ein Spaziergang hakt keinen Lauf ab.")
      }
    }
  }
}

/// Training ohne Platz im Plan und nachgetragene Einheiten (die sich hier wieder löschen lassen).
private struct ExtraActivitiesSection: View {
  let records: [ActivityRecord]
  let delete: (ActivityRecord) -> Void

  var body: some View {
    if !records.isEmpty {
      Section("Außerplanmäßig und nachgetragen") {
        ForEach(records) { record in
          if let activity = record.activity {
            NavigationLink {
              ActivityDetailView(record: record)
            } label: {
              ActivitySummaryRow(activity: activity)
            }
            .swipeActions {
              if ManualActivity.isManual(record.garminID) {
                Button("Löschen", role: .destructive) { delete(record) }
              }
            }
          }
        }
      }
    }
  }
}

/// Menü je Tag: verschieben, diese Woche auslassen, rückgängig.
private struct PlanDayMenu: View {
  let day: CalendarDay
  @Environment(AppModel.self) private var model

  var body: some View {
    let settings = model.settings
    let weekday = Weekday(day: day)
    let schedule = settings.schedule(inWeekOf: day)
    let hasSlots = !schedule.slots(on: weekday).isEmpty
    let note = settings.planAdjustments.note(for: weekday, inWeekOf: day)
    let options = PlanMoveAdvisor.options(
      for: weekday, schedule: schedule, profile: settings.profile, today: CalendarDay(date: .now), limit: 6)
    if hasSlots || note != nil {
      Menu {
        if hasSlots {
          if !options.isEmpty {
            Section("Verschieben auf") {
              ForEach(options) { target in
                Button(target.long) { model.reminders.move(day, to: target) }
              }
            }
          }
          Button("Diese Woche auslassen", systemImage: "forward.end", role: .destructive) {
            model.reminders.skip(day)
          }
        }
        if note != nil {
          Button("Rückgängig", systemImage: "arrow.uturn.backward") {
            model.settings.planAdjustments.undo(weekday, inWeekOf: day)
          }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.title3)
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("\(weekday.long) anpassen")
    }
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
