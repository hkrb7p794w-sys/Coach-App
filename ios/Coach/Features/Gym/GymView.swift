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
    "\(records.count)-\(records.first?.savedToHealth ?? false)-\(activities.count)-\(days.first?.dayKey ?? "")"
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
        } else {
          TodaySection(viewModel: viewModel) { workout in
            if let workout { viewModel.start(workout) } else { viewModel.startEmpty() }
            showWorkout = true
          }
        }

        if let message = viewModel.message {
          Section { Text(message).font(.footnote) }
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
          days: days.prefix(3).compactMap(\.metrics)
        )
      }
      .fullScreenCover(isPresented: $showWorkout) {
        ActiveWorkoutView(viewModel: viewModel)
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
      EvidenceDisclosure(ruleIDs: ["gym.progression"])
    } header: {
      Text("Gewichts-Progression")
    } footer: {
      Text(
        "Regel: alle Arbeitssätze an der Obergrenze → +2,5–5 % und wieder unten im Bereich anfangen (ACSM 2009). "
          + "Die Tagesampel verschiebt nur den Zeitpunkt.")
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
      ExerciseHistoryView(item: item, history: viewModel.history(of: item.exerciseID))
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

private struct ExerciseHistoryView: View {
  let item: ExerciseProgress
  let history: [DayValue]

  var body: some View {
    List {
      Section {
        Text(item.headline).font(.headline)
        Text(item.detail).font(.footnote)
      }
      if history.count > 1 {
        Section("Arbeitsgewicht") {
          Chart(history) { point in
            LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("kg", point.value))
            PointMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("kg", point.value))
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .frame(height: 160)
        }
      }
      Section("Einheiten") {
        ForEach(history.reversed()) { point in
          LabeledContent(Formatters.day(point.day), value: "\(GermanFormat.number(point.value)) kg")
        }
      }
    }
    .navigationTitle(item.name)
  }
}
