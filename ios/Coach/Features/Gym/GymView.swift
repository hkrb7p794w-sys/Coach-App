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
  @State private var viewModel = GymViewModel.shared
  @State private var showWorkout = false
  /// Fokus wurde für die laufende Einheit eingeschaltet.

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
          } footer: {
            switch viewModel.sessionState() {
            case .unfinished:
              Text(
                "Diese Einheit vom \(Formatters.shortDate(active.day)) wurde nicht beendet. Öffnen und „Beenden“ "
                  + "tippen, damit sie gespeichert, für die Woche gezählt und an Garmin übertragen wird.")
            case .notStarted:
              Text("Noch kein Satz abgehakt – erst mit dem ersten Satz gilt die Einheit als gestartet.")
            default:
              EmptyView()
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

        // Planen und Auswerten direkt unter dem Start – Trainingspläne zuerst.
        Section {
          NavigationLink {
            RoutinesView(viewModel: viewModel) { routine in
              viewModel.start(routine)
              showWorkout = true
            }
          } label: {
            HubLabel(
              title: "Trainingspläne", symbol: "list.bullet.rectangle.portrait",
              caption: model.settings.gym.routines.isEmpty
                ? "Plan anlegen oder Vorlage übernehmen"
                : "\(model.settings.gym.routines.count) Pläne · bearbeiten, neu anlegen")
          }
          NavigationLink {
            ExerciseLibraryView(viewModel: viewModel)
          } label: {
            HubLabel(title: "Übungen", symbol: "books.vertical", caption: "Suchen, nach Muskel filtern, Anleitung")
          }
          NavigationLink {
            GymAnalysisView(viewModel: viewModel)
          } label: {
            HubLabel(
              title: "Auswertung", symbol: "figure.strengthtraining.traditional",
              caption: "Muskel-Heatmap, Erholung, Fortschritt")
          }
        } header: {
          Text("Planen und auswerten")
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
        update()
        if !viewModel.hintSource.hasPrefix("KI") {
          await viewModel.loadHints(ai: model.ai, goal: model.settings.profile.goal, trigger: .automatic)
        }
      }
      // Schnellaktion / Kurzbefehl „Training starten“.
      .onChange(of: AppRouter.shared.pending, initial: true) {
        guard AppRouter.shared.take(.startWorkout) else { return }
        startFromShortcut()
      }
      .fullScreenCover(isPresented: $showWorkout) {
        ActiveWorkoutView(viewModel: viewModel)
      }
      // Start oder Ende einer Einheit: Erinnerungen für heute neu planen (keine Start-Erinnerung im Training).
      .onChange(of: viewModel.active?.id) { _, _ in
        Task { await model.refreshReminders() }
      }
      // Live-Aktivität: Pause und nächster Satz auf dem Sperrbildschirm.
      .onChange(of: viewModel.liveState, initial: true) { _, state in
        WorkoutActivityController.update(
          state, title: viewModel.active?.title ?? "", enabled: model.settings.gym.liveActivity)
      }
      // Bildschirm an, solange eine Einheit läuft – auch wenn sie gerade ausgeblendet ist.
      .onChange(of: viewModel.active != nil && model.settings.gym.keepsScreenOn, initial: true) { _, on in
        UIApplication.shared.isIdleTimerDisabled = on
      }
    }
  }
}

extension GymView {
  fileprivate func update() {
    viewModel.update(
      sessions: records.compactMap(\.session),
      activities: activities.compactMap(\.activity),
      days: days.prefix(3).compactMap(\.metrics),
      gym: model.settings.gym
    )
  }

  /// Laufende Einheit öffnen, sonst die nächste geplante starten. Gibt es keine, bleibt es beim Reiter.
  fileprivate func startFromShortcut() {
    if viewModel.active != nil {
      showWorkout = true
      return
    }
    update()
    if model.settings.profile.mode == .personal {
      guard let next = RoutineRotation.next(routines: model.settings.gym.routines, sessions: viewModel.sessions)
      else { return }
      viewModel.start(next)
    } else {
      guard let workout = viewModel.todayWorkout else { return }
      viewModel.start(workout)
    }
    showWorkout = true
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
        Text("Lege unter „Trainingspläne“ deine Einheiten an oder übernimm einen Vorschlag passend zu deinem Plan.")
      } else {
        Text("Die nächste Einheit folgt der Reihenfolge deiner Trainingspläne nach dem zuletzt trainierten.")
      }
    }
  }
}

/// Zeile mit Symbol, Titel und kurzer Beschreibung.
private struct HubLabel: View {
  let title: String
  let symbol: String
  let caption: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body.weight(.medium))
        Text(caption).font(.caption).foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: symbol).foregroundStyle(.tint)
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

struct SessionDetailView: View {
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
        if let message { Text(message).font(.footnote) }
      }
      GarminLinkSection(record: record, session: session) { message = $0 }
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

/// Abgleich mit Garmin: Status, Sätze in die Uhr-Aufzeichnung schreiben, als eigene Aktivität hochladen,
/// ursprüngliche Sätze der Uhr wiederherstellen.
private struct GarminLinkSection: View {
  let record: GymSessionRecord
  let session: GymSession
  let report: (String) -> Void
  @Environment(\.modelContext) private var context
  @Environment(AppModel.self) private var model
  @State private var working = false

  /// Aus dem gespeicherten Datensatz, damit der Status nach dem Abgleich sofort stimmt.
  private var link: GarminLink? { record.session?.garmin }

  var body: some View {
    if let connect = model.garmin.connect, connect.isLoggedIn {
      Section {
        status
        if working { ProgressView() }
        switch link?.status {
        case .enriched?:
          if let id = link?.activityID {
            // Z. B. nach besserer Übungszuordnung: neu aus der gesicherten Uhr-Aufzeichnung schreiben.
            Button("Sätze erneut übertragen", systemImage: "arrow.clockwise") {
              run {
                await GarminStrengthService.enrich(
                  record, session: session, activityID: id, garmin: connect, gym: model.settings.gym, now: .now)
              }
            }
          }
          if let id = link?.activityID, GarminStrengthService.hasBackup(activityID: id) {
            Button("Ursprüngliche Sätze der Uhr wiederherstellen", role: .destructive) {
              run { await GarminStrengthService.restore(record, activityID: id, garmin: connect) }
            }
          }
        case .uploaded?:
          EmptyView()
        default:
          if !record.uploadedToGarmin {
            Button("Mit Aufzeichnung der Uhr abgleichen", systemImage: "arrow.triangle.2.circlepath") {
              record.setGarmin(GarminLink(status: .pending, updatedAt: .now))
              run {
                await GarminStrengthService.reconcile(context: context, garmin: connect, gym: model.settings.gym)
                  ?? "Nichts zu tun."
              }
            }
            Button("Als eigene Aktivität hochladen", systemImage: "square.and.arrow.up") {
              run {
                let text = await GymViewModel.uploadToGarmin(
                  record, session: session, context: context, garmin: connect)
                if record.uploadedToGarmin {
                  record.setGarmin(GarminLink(status: .uploaded, note: text, updatedAt: .now))
                  try? context.save()
                }
                return text
              }
            }
          }
        }
      } header: {
        Text("Garmin Connect")
      } footer: {
        Text(
          "Abgleichen schreibt die Sätze in die Krafttraining-Aufzeichnung der Uhr (Start höchstens 2 Stunden "
            + "entfernt) – Kalorien und Puls der Uhr bleiben, es entsteht keine zweite Aktivität. Hochladen legt eine "
            + "eigene Aktivität an; nur, wenn die Uhr nicht dabei war.")
      }
    }
  }

  @ViewBuilder private var status: some View {
    switch link?.status {
    case .enriched?:
      Label("Sätze in der Aufzeichnung der Uhr", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
    case .uploaded?:
      Label("Als eigene Aktivität hochgeladen", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
    case .pending?:
      Label("Wartet auf die Aufzeichnung der Uhr", systemImage: "hourglass").foregroundStyle(.secondary)
    case .failed?:
      Label(link?.note ?? "Abgleich fehlgeschlagen", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
    case nil:
      if record.uploadedToGarmin {
        Label("Als eigene Aktivität hochgeladen", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
      } else {
        Label("Noch nicht in Garmin Connect", systemImage: "circle.dashed").foregroundStyle(.secondary)
      }
    }
  }

  private func run(_ action: @escaping () async -> String) {
    working = true
    Task {
      let text = await action()
      try? context.save()
      working = false
      report(text)
    }
  }
}

/// Auswertung: Hinweise, Trainingskalender, Fortschritt je Übung, Sätze je Muskel.
private struct GymAnalysisView: View {
  let viewModel: GymViewModel

  var body: some View {
    List {
      CalendarSection(viewModel: viewModel)
      GymHintsSection(viewModel: viewModel)
      MuscleOverviewSection(sessions: viewModel.sessions)
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
