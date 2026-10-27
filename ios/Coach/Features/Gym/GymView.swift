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

        GymHintsSection(viewModel: viewModel)

        Section {
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

        ProgressSection(viewModel: viewModel)
        VolumeSection(viewModel: viewModel)

        if !records.isEmpty {
          Section("Verlauf") {
            ForEach(records.prefix(30)) { record in
              if let session = record.session {
                NavigationLink {
                  SessionDetailView(record: record, session: session)
                } label: {
                  SessionRow(session: session, savedToHealth: record.savedToHealth)
                }
              }
            }
            .onDelete { offsets in
              for index in offsets { context.delete(records[index]) }
              try? context.save()
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
    }
  }
}

/// Krafttraining für Profile ohne Saisonplan: laut Wochenplan heute dran? Start mit einer eigenen Routine.
private struct PersonalGymSection: View {
  let viewModel: GymViewModel
  let start: (Routine?) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let day = CalendarDay(date: .now)
    let today = model.settings.schedule(inWeekOf: day).slots(on: Weekday(day: day)).filter { $0.sport == .strength }
    let routines = model.settings.gym.routines
    Section {
      if let slot = today.first {
        VStack(alignment: .leading, spacing: 4) {
          Text(slot.title).font(.title3.bold())
          Text(slot.guide).font(.footnote).foregroundStyle(.secondary)
        }
      } else {
        Text("Heute steht laut deinem Wochenplan kein Krafttraining an.").foregroundStyle(.secondary)
      }
      if viewModel.recovered == false {
        Label(
          "Erholung heute eingeschränkt: Gewichte halten, ggf. weniger Sätze.", systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
      }
      ForEach(routines) { routine in
        Button {
          start(routine)
        } label: {
          Label(routine.name, systemImage: "play.circle")
        }
      }
      Button("Freies Training") { start(nil) }
    } header: {
      Text("Heute")
    } footer: {
      if routines.isEmpty {
        Text("Lege unter „Routinen“ deine Einheiten an oder übernimm einen Vorschlag passend zu deinem Plan.")
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
        Button("Einheit starten") { start(workout) }.bold()
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
