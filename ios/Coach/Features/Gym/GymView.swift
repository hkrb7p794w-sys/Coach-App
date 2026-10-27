import Charts
import CoachCore
import SwiftData
import SwiftUI

/// Gym: Einheit von heute starten, Progression je Übung, Sätze je Muskel, Verlauf.
struct GymView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.modelContext) private var context
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var records: [GymSessionRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]
  @State private var viewModel = GymViewModel()
  @State private var showWorkout = false
  /// Fokus wurde für die laufende Einheit eingeschaltet.
  @State private var focusOn = false

  private var refreshKey: String {
    "\(records.count)-\(records.first?.savedToHealth ?? false)-\(activities.count)-\(days.first?.dayKey ?? "")-"
      + "\(model.settings.gym.hashValue)"
  }

  var body: some View {
    NavigationStack {
      List {
        if let active = viewModel.active {
          Section {
            Button {
              showWorkout = true
            } label: {
              Label("\(active.title) fortsetzen · \(active.doneSetCount) Sätze", systemImage: "play.circle.fill")
                .font(.headline)
            }
          }
        } else if model.settings.profile.mode == .personal {
          PersonalGymSection(viewModel: viewModel) { routine in
            if let routine { viewModel.start(routine) } else { viewModel.startEmpty() }
            showWorkout = true
          }
        } else {
          TodaySection(viewModel: viewModel) { workout in
            if let workout { viewModel.start(workout) } else { viewModel.startEmpty() }
            showWorkout = true
          }
        }

        if let message = viewModel.message {
          Section { Text(message).font(.footnote) }
        }

        Section {
          NavigationLink {
            GymAnalysisView(viewModel: viewModel)
          } label: {
            Label("Auswertung", systemImage: "chart.bar.xaxis")
          }
          NavigationLink {
            RoutinesView(viewModel: viewModel) { routine in
              viewModel.start(routine)
              showWorkout = true
            }
          } label: {
            Label("Routinen", systemImage: "list.bullet.rectangle")
          }
          NavigationLink {
            ExerciseLibraryView(viewModel: viewModel)
          } label: {
            Label("Übungen", systemImage: "books.vertical")
          }
        }

        if !records.isEmpty {
          Section("Letzte Einheiten") {
            ForEach(records.prefix(3)) { record in
              if let session = record.session {
                NavigationLink {
                  SessionDetailView(record: record, session: session)
                } label: {
                  SessionRow(session: session, savedToHealth: record.savedToHealth)
                }
              }
            }
            if records.count > 3 {
              NavigationLink("Alle \(records.count) Einheiten") { GymHistoryView() }
            }
          }
        }
      }
      .navigationTitle("Gym")
      .task(id: refreshKey) {
        viewModel.update(
          sessions: records.compactMap(\.session),
          activities: activities.compactMap(\.activity),
          days: days.prefix(3).compactMap(\.metrics),
          gym: model.settings.gym
        )
        if !viewModel.hintSource.hasPrefix("KI") {
          await viewModel.loadHints(ai: model.ai, goal: model.settings.profile.goal)
        }
      }
      .fullScreenCover(isPresented: $showWorkout) {
        ActiveWorkoutView(viewModel: viewModel)
      }
      // Fokus während der Einheit (Kurzbefehle der Person): an nach dem ersten Satz – der kurze Wechsel in die
      // Kurzbefehle-App fällt dann in die Pause statt in den Start –, aus nach Beenden oder Verwerfen.
      .onChange(of: viewModel.active?.doneSetCount ?? -1) { _, count in
        guard model.settings.gym.focusShortcuts else { return }
        let wanted = count > 0 || (focusOn && count >= 0)
        guard wanted != focusOn, let url = WorkoutFocus.url(turningOn: wanted) else { return }
        focusOn = wanted
        UIApplication.shared.open(url)
      }
      // Bildschirm an, solange eine Einheit läuft – auch wenn sie gerade ausgeblendet ist.
      .onChange(of: viewModel.active != nil && model.settings.gym.keepsScreenOn, initial: true) { _, on in
        UIApplication.shared.isIdleTimerDisabled = on
      }
    }
  }
}

/// Krafttraining für Profile ohne Saisonplan: eine Karte „Nächste Einheit“ (Rotation der eigenen Routinen) mit
/// großem Start-Knopf, darunter die übrigen Routinen als Leiste.
private struct PersonalGymSection: View {
  let viewModel: GymViewModel
  let start: (Routine?) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let day = CalendarDay(date: .now)
    let today = model.settings.schedule(inWeekOf: day).slots(on: Weekday(day: day)).filter { $0.sport == .strength }
    let routines = model.settings.gym.routines
    let next = RoutineRotation.next(routines: routines, sessions: viewModel.sessions)
    Section {
      if let next {
        VStack(alignment: .leading, spacing: 6) {
          Text(today.isEmpty ? "Nächste Einheit" : "Heute laut Wochenplan").font(.caption).foregroundStyle(.secondary)
          Text(next.name).font(.title2.bold())
          Text("\(next.items.count) Übungen · ca. \(RoutineRotation.estimatedMinutes(next)) min")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(next.items.map(\.name).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
          if let days = viewModel.daysSinceLegs, days >= 7, !next.setsPerGroup.keys.contains(.legs) {
            Label("Beine seit \(days) Tagen nicht trainiert", systemImage: "figure.walk")
              .font(.footnote)
              .foregroundStyle(.orange)
          }
          if viewModel.recovered == false {
            Label(
              "Erholung heute eingeschränkt: Gewichte halten, ggf. weniger Sätze.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
          }
          Button {
            start(next)
          } label: {
            Label("Starten", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.roundedRectangle(radius: 14))
          .padding(.top, 4)
        }
        .padding(.vertical, 4)
      } else if let slot = today.first {
        VStack(alignment: .leading, spacing: 4) {
          Text(slot.title).font(.title3.bold())
          Text(slot.guide).font(.footnote).foregroundStyle(.secondary)
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(routines.filter { $0.id != next?.id }) { routine in
            Button(routine.name, systemImage: "play.circle") { start(routine) }
              .buttonStyle(.bordered)
          }
          Button("Freies Training", systemImage: "plus") { start(nil) }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
      }
    } footer: {
      if routines.isEmpty {
        Text("Lege unter „Routinen“ deine Einheiten an oder übernimm einen Vorschlag passend zu deinem Plan.")
      } else {
        Text("Die nächste Einheit folgt der Reihenfolge deiner Routinen nach der zuletzt trainierten.")
      }
    }
  }
}

private struct TodaySection: View {
  let viewModel: GymViewModel
  let start: (Workout?) -> Void

  var body: some View {
    Section {
      if let workout = viewModel.todayWorkout {
        VStack(alignment: .leading, spacing: 4) {
          Text(workout.name).font(.title3.bold())
          Text(workout.exercises.map(\.name).joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
          if viewModel.recovered == false {
            Label(
              "Erholung heute eingeschränkt: Gewichte halten, ggf. ⅓ weniger Sätze.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
          }
        }
        Button {
          start(workout)
        } label: {
          Label("Einheit starten", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
      } else {
        Text("Heute steht laut Plan kein Krafttraining an.").foregroundStyle(.secondary)
      }
      Menu("Andere Einheit starten") {
        ForEach(viewModel.plan.workouts) { workout in
          Button(workout.name) { start(workout) }
        }
        Button("Freies Training") { start(nil) }
      }
    } header: {
      Text("Heute")
    } footer: {
      let week = viewModel.weekPlan.map { item in
        "\(Formatters.day(item.day)): \(item.workout.name)\(item.done ? " ✓" : "")"
      }
      if !week.isEmpty { Text("Diese Woche: " + week.joined(separator: " · ")) }
    }
  }
}

private struct ProgressSection: View {
  let viewModel: GymViewModel
  @State private var showAll = false

  var body: some View {
    let active = viewModel.progress.filter { [.increase, .restart, .check].contains($0.status) }
    let rest = viewModel.progress.filter { ![.increase, .restart, .check].contains($0.status) }
    Section {
      if viewModel.progress.isEmpty {
        Text("Noch keine Einheiten mit Gewicht im Verlauf.").foregroundStyle(.secondary)
      } else if active.isEmpty {
        Text("Gerade keine Übung an der Obergrenze – Gewichte halten, Wiederholungen steigern.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      ForEach(active) { item in ProgressRow(item: item, viewModel: viewModel) }
      if !rest.isEmpty {
        DisclosureGroup("\(rest.count) weitere Übungen", isExpanded: $showAll) {
          ForEach(rest) { item in ProgressRow(item: item, viewModel: viewModel) }
        }
      }
      EvidenceDisclosure(ruleIDs: ["gym.progression", "gym.rir"])
    } header: {
      Text("Gewichts-Progression")
    } footer: {
      Text(
        "Regel: alle Arbeitssätze an der Obergrenze → +2,5–5 % und wieder unten im Bereich anfangen (ACSM 2009). "
          + "Bleiben in allen Sätzen 4 oder mehr Wiederholungen in Reserve, sofort steigern. Die Tagesampel "
          + "verschiebt nur den Zeitpunkt.")
    }
  }
}

private struct ProgressRow: View {
  let item: ExerciseProgress
  let viewModel: GymViewModel

  private var tag: (String, Color)? {
    switch item.status {
    case .increase: (item.nextWeightKg.map { "↑ \(GermanFormat.number($0)) kg" } ?? "↑", .green)
    case .check: ("prüfen", .red)
    case .restart: ("Wiedereinstieg", .orange)
    default: nil
    }
  }

  var body: some View {
    NavigationLink {
      ExerciseDetailView(exerciseID: item.exerciseID, viewModel: viewModel)
    } label: {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name).font(.subheadline.bold())
          Text(
            "\(item.weightKg > 0 ? "\(GermanFormat.number(item.weightKg)) kg" : "Körpergewicht") × "
              + "\(item.reps.map(String.init).joined(separator: "/")) · Ziel \(item.target.lowerBound)–"
              + "\(item.target.upperBound)"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        if let tag {
          Text(tag.0)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tag.1.opacity(0.2), in: Capsule())
        }
      }
    }
  }
}

private struct VolumeSection: View {
  let viewModel: GymViewModel

  var body: some View {
    Section {
      if (viewModel.daysSinceLegs ?? 99) > 10 {
        Label(
          viewModel.daysSinceLegs.map { "Beine zuletzt vor \($0) Tagen." } ?? "Beine bisher nicht erfasst.",
          systemImage: "exclamationmark.circle"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
      }
      ForEach(MuscleVolume.groups, id: \.self) { group in
        let count = viewModel.volume[group] ?? 0
        HStack {
          Text(group.rawValue).frame(width: 90, alignment: .leading)
          ProgressView(value: Double(min(count, 14)), total: 14)
            .tint(count == 0 ? .red : (count >= MuscleVolume.goodRange.lowerBound ? .green : .orange))
          Text("\(count)").monospacedDigit().frame(width: 28, alignment: .trailing)
        }
        .font(.subheadline)
      }
      EvidenceDisclosure(ruleIDs: ["gym.volume", "strength.economy", "strength.interference"])
    } header: {
      Text("Sätze je Muskel · 7 Tage")
    } footer: {
      Text(
        "Grün ab 5 Sätzen pro Woche: solider Kraftaufbau neben dem Ausdauertraining. Mehr Sätze bringen mehr, "
          + "aber mit abnehmendem Ertrag (Schoenfeld 2017, Pelland 2025). Für Lauf- und Radökonomie zählt "
          + "Beintraining am meisten.")
    }
  }
}

private struct SessionRow: View {
  let session: GymSession
  let savedToHealth: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(session.title).font(.headline)
        Spacer()
        if savedToHealth { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
      }
      Text(
        "\(Formatters.day(session.day)) · \(session.doneSetCount) Sätze · "
          + "\(GermanFormat.number((session.volumeKg / 100).rounded() / 10)) t"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private struct SessionDetailView: View {
  let record: GymSessionRecord
  let session: GymSession
  @Environment(\.modelContext) private var context
  @Environment(AppModel.self) private var model
  @State private var message: String?

  var body: some View {
    List {
      Section {
        LabeledContent("Datum", value: Formatters.day(session.day))
        if let end = session.end {
          LabeledContent("Dauer", value: Formatters.duration(end.timeIntervalSince(session.start)))
        }
        LabeledContent("Bewegte Last", value: "\(GermanFormat.number(session.volumeKg)) kg")
        if record.savedToHealth {
          Label("In Apple Health gespeichert", systemImage: "heart.fill").foregroundStyle(.pink)
        } else {
          Button("In Apple Health speichern") {
            Task {
              message = await GymViewModel.saveToHealth(
                record, session: session, context: context, writer: HealthWorkoutWriter())
            }
          }
        }
        if record.uploadedToGarmin {
          Label("In Garmin Connect übertragen", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
        } else if let connect = model.garmin.connect, connect.isLoggedIn {
          Button("Zu Garmin Connect übertragen") {
            Task {
              message = await GymViewModel.uploadToGarmin(
                record, session: session, context: context, garmin: connect)
            }
          }
        }
        if let message { Text(message).font(.footnote) }
      }
      ForEach(session.exercises) { exercise in
        Section(exercise.name) {
          ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
            LabeledContent(
              "Satz \(index + 1)",
              value: set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg)) kg × \(set.reps)" : "\(set.reps) Wdh.")
          }
        }
      }
    }
    .navigationTitle(session.title)
  }
}

/// Auswertung: Hinweise, Trainingskalender, Fortschritt je Übung, Sätze je Muskel.
private struct GymAnalysisView: View {
  let viewModel: GymViewModel

  var body: some View {
    List {
      CalendarSection(viewModel: viewModel)
      GymHintsSection(viewModel: viewModel)
      ProgressSection(viewModel: viewModel)
      VolumeSection(viewModel: viewModel)
    }
    .navigationTitle("Auswertung")
  }
}

/// Einheiten je Woche (8 Wochen) und Serie.
private struct CalendarSection: View {
  let viewModel: GymViewModel

  var body: some View {
    let weeks = GymCalendar.weeks(sessions: viewModel.sessions, today: viewModel.today)
    let streak = GymCalendar.streak(sessions: viewModel.sessions, today: viewModel.today)
    Section {
      Chart(weeks) { week in
        BarMark(x: .value("Woche", Formatters.day(week.monday)), y: .value("Einheiten", week.sessions))
          .foregroundStyle(.tint)
      }
      .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
      .frame(height: 140)
      .accessibilityLabel("Einheiten je Woche, letzte 8 Wochen")
      Label(
        streak == 1 ? "1 Woche in Folge trainiert" : "\(streak) Wochen in Folge trainiert",
        systemImage: streak > 0 ? "flame.fill" : "flame")
    } header: {
      Text("Kalender")
    }
  }
}

/// Alle Einheiten; Löschen erst nach Rückfrage – eine Einheit ist Verlauf und Grundlage der Progression.
private struct GymHistoryView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var records: [GymSessionRecord]
  @State private var pendingDelete: IndexSet?

  var body: some View {
    List {
      ForEach(records) { record in
        if let session = record.session {
          NavigationLink {
            SessionDetailView(record: record, session: session)
          } label: {
            SessionRow(session: session, savedToHealth: record.savedToHealth)
          }
        }
      }
      .onDelete { offsets in pendingDelete = offsets }
    }
    .navigationTitle("Verlauf")
    .confirmationDialog(
      "Einheit löschen?",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Löschen", role: .destructive) {
        for index in pendingDelete ?? [] where records.indices.contains(index) { context.delete(records[index]) }
        try? context.save()
        pendingDelete = nil
      }
    } message: {
      Text("Sätze, Bestleistungen und die Progression dieser Einheit gehen verloren.")
    }
  }
}
