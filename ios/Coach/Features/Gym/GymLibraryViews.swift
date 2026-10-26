import Charts
import CoachCore
import SwiftUI

/// Übungsbibliothek: nach Muskel sortiert, durchsuchbar, mit eigenen Übungen.
struct ExerciseLibraryView: View {
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model
  @State private var search = ""
  @State private var onlyAvailable = true
  @State private var newExercise = false

  var body: some View {
    let gym = model.settings.gym
    let items = ExerciseLibrary.search(
      search, custom: gym.customExercises, available: onlyAvailable ? gym.equipment : nil)
    List {
      Section {
        Toggle("Nur mit meiner Ausstattung", isOn: $onlyAvailable)
        NavigationLink("Meine Ausstattung") { EquipmentSettingsView() }
      }
      ForEach(MuscleGroup.allCases, id: \.self) { group in
        let inGroup = items.filter { $0.group == group }
        if !inGroup.isEmpty {
          Section(group.rawValue) {
            ForEach(inGroup) { exercise in
              NavigationLink {
                ExerciseDetailView(exerciseID: exercise.id, viewModel: viewModel)
              } label: {
                ExerciseLabel(exercise: exercise)
              }
            }
          }
        }
      }
    }
    .searchable(text: $search, prompt: "Übung oder Muskel suchen")
    .navigationTitle("Übungen")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Eigene Übung", systemImage: "plus") { newExercise = true }
      }
    }
    .sheet(isPresented: $newExercise) {
      CustomExerciseEditor(initialName: search) { _ in newExercise = false }
    }
  }
}

struct ExerciseLabel: View {
  let exercise: ExerciseInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(exercise.name)
      Text(
        ([exercise.equipment.map(\.label).joined(separator: " / ")] + (exercise.isCustom ? ["eigene Übung"] : []))
          .filter { !$0.isEmpty }.joined(separator: " · ")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

/// Eine Übung: Anleitung, Bestwerte, Verlauf und Empfehlung für die nächste Einheit.
struct ExerciseDetailView: View {
  let exerciseID: String
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model
  @State private var showOneRepMax = true

  var body: some View {
    let gym = model.settings.gym
    let exercise = gym.exercise(exerciseID)
    let history = viewModel.history(of: exerciseID)
    let records = GymStats.records(history)
    let progress = viewModel.progress.first { $0.exerciseID == exerciseID }
    List {
      if let progress {
        Section("Nächste Einheit") {
          Text(progress.headline).font(.headline)
          Text(progress.detail).font(.footnote)
          EvidenceDisclosure(ruleIDs: ["gym.progression", "gym.rir"])
        }
      }
      if let exercise {
        Section {
          LabeledContent(
            "Muskel", value: ([exercise.group] + exercise.secondary).map(\.rawValue).joined(separator: ", "))
          if !exercise.equipment.isEmpty {
            LabeledContent("Geräte", value: exercise.equipment.map(\.label).joined(separator: " / "))
          }
          LabeledContent(
            exercise.tracking == .time ? "Zielbereich" : "Wiederholungen",
            value: "\(exercise.lowerReps)–\(exercise.upperReps)\(exercise.tracking == .time ? " s" : "")")
        }
        if !exercise.instructions.isEmpty {
          Section("Ausführung") {
            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
              HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)").font(.caption.bold()).frame(width: 18, height: 18)
                  .background(Color.accentColor.opacity(0.15), in: Circle())
                Text(step).font(.subheadline)
              }
            }
          }
        }
      }
      if !history.isEmpty {
        Section("Bestwerte") {
          if let heaviest = records.heaviestKg {
            LabeledContent("Höchstgewicht", value: "\(GermanFormat.number(heaviest)) kg")
          }
          if let oneRepMax = records.bestOneRepMaxKg {
            LabeledContent("Geschätztes 1RM", value: "\(GermanFormat.number(oneRepMax.rounded())) kg")
          }
          if let reps = records.mostReps {
            LabeledContent("Meiste Wiederholungen", value: "\(reps)")
          }
          if let volume = records.bestVolumeKg {
            LabeledContent("Beste bewegte Last", value: "\(GermanFormat.number(volume.rounded())) kg")
          }
        }
        if history.count > 1 {
          Section {
            Picker("Anzeige", selection: $showOneRepMax) {
              Text("Geschätztes 1RM").tag(true)
              Text("Höchstgewicht").tag(false)
            }
            .pickerStyle(.segmented)
            Chart(history) { point in
              let value = showOneRepMax ? (point.oneRepMaxKg ?? point.topWeightKg) : point.topWeightKg
              LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("kg", value))
              PointMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("kg", value))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
          } header: {
            Text("Verlauf")
          } footer: {
            Text("1RM geschätzt nach Epley aus Sätzen mit bis zu 12 Wiederholungen.")
          }
        }
        Section("Einheiten") {
          ForEach(history.reversed()) { point in
            VStack(alignment: .leading, spacing: 2) {
              Text(Formatters.day(point.day)).font(.subheadline.bold())
              Text(
                point.sets.map { set in
                  (set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg)) kg × \(set.reps)" : "\(set.reps) Wdh.")
                    + (set.rir.map { " (RIR \($0))" } ?? "")
                }.joined(separator: " · ")
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }
      } else {
        Section { Text("Noch keine Sätze erfasst.").foregroundStyle(.secondary) }
      }
    }
    .navigationTitle(exercise?.name ?? progress?.name ?? "Übung")
  }
}

/// Eigene Übung anlegen.
struct CustomExerciseEditor: View {
  var initialName = ""
  let done: (ExerciseInfo?) -> Void
  @Environment(AppModel.self) private var model
  @State private var name = ""
  @State private var group = MuscleGroup.chest
  @State private var equipment = Equipment.dumbbell
  @State private var tracking = ExerciseTracking.weightReps

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
        Picker("Muskel", selection: $group) {
          ForEach(MuscleGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Gerät", selection: $equipment) {
          ForEach(Equipment.allCases) { Text($0.label).tag($0) }
        }
        Picker("Erfassung", selection: $tracking) {
          Text("Gewicht × Wiederholungen").tag(ExerciseTracking.weightReps)
          Text("Nur Wiederholungen").tag(ExerciseTracking.reps)
          Text("Haltezeit (Sekunden)").tag(ExerciseTracking.time)
        }
      }
      .navigationTitle("Eigene Übung")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { done(nil) } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") {
            let exercise = ExerciseInfo.custom(name: name, group: group, equipment: equipment, tracking: tracking)
            model.settings.gym.addCustom(exercise)
            done(exercise)
          }
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear { if name.isEmpty { name = initialName } }
    }
  }
}

/// Übung auswählen (für Training und Routinen).
struct ExercisePickerView: View {
  let pick: (ExerciseInfo) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var newExercise = false

  var body: some View {
    let gym = model.settings.gym
    let items = ExerciseLibrary.search(search, custom: gym.customExercises, available: gym.equipment)
    NavigationStack {
      List {
        ForEach(MuscleGroup.allCases, id: \.self) { group in
          let inGroup = items.filter { $0.group == group }
          if !inGroup.isEmpty {
            Section(group.rawValue) {
              ForEach(inGroup) { exercise in
                Button {
                  pick(exercise)
                } label: {
                  ExerciseLabel(exercise: exercise).foregroundStyle(.primary)
                }
              }
            }
          }
        }
        Section {
          Button("Eigene Übung anlegen", systemImage: "plus") { newExercise = true }
        }
      }
      .searchable(text: $search, prompt: "Übung suchen")
      .navigationTitle("Übung wählen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
      }
      .sheet(isPresented: $newExercise) {
        CustomExerciseEditor(initialName: search) { exercise in
          newExercise = false
          if let exercise { pick(exercise) }
        }
      }
    }
  }
}

/// Vorhandene Geräte: bestimmt Vorschläge und die Auswahl in der Bibliothek.
struct EquipmentSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    Form {
      Section {
        Button("Fitnessstudio (alles)") { settings.gym.equipment = Equipment.gym }
        Button("Zuhause mit Kurzhanteln") { settings.gym.equipment = Equipment.homeDumbbells }
        Button("Ohne Geräte") { settings.gym.equipment = Equipment.none }
      } header: {
        Text("Schnellauswahl")
      }
      Section("Geräte") {
        ForEach(Equipment.allCases) { item in
          Toggle(
            item.label,
            isOn: Binding(
              get: { settings.gym.equipment.contains(item) },
              set: { on in
                if on { settings.gym.equipment.insert(item) } else { settings.gym.equipment.remove(item) }
              }))
        }
      }
      Section {
        Toggle("Wiederholungen in Reserve abfragen", isOn: $settings.gym.tracksRIR)
      } footer: {
        Text(
          "Nach jedem Satz kurz schätzen, wie viele Wiederholungen noch gegangen wären (RIR). Bleiben in allen "
            + "Sätzen 4 oder mehr übrig, schlägt die App sofort mehr Gewicht vor.")
      }
    }
    .navigationTitle("Ausstattung")
  }
}

/// Eigene Routinen und Vorschläge passend zu Profil und Ausstattung.
struct RoutinesView: View {
  let viewModel: GymViewModel
  let start: (Routine) -> Void
  @Environment(AppModel.self) private var model
  @State private var editing: Routine?

  var body: some View {
    let settings = model.settings
    let suggestions = RoutineTemplates.suggest(profile: settings.profile, equipment: settings.gym.equipment)
    List {
      Section {
        if settings.gym.routines.isEmpty {
          Text("Noch keine eigene Routine. Übernimm einen Vorschlag oder lege selbst eine an.")
            .foregroundStyle(.secondary)
        }
        ForEach(settings.gym.routines) { routine in
          RoutineRow(routine: routine, start: { start(routine) }, edit: { editing = routine })
        }
        .onDelete { offsets in model.settings.gym.routines.remove(atOffsets: offsets) }
        .onMove { from, to in model.settings.gym.routines.move(fromOffsets: from, toOffset: to) }
        Button("Neue Routine", systemImage: "plus") { editing = Routine(name: "Neue Routine", items: []) }
      } header: {
        Text("Meine Routinen")
      }
      Section {
        ForEach(suggestions) { routine in
          VStack(alignment: .leading, spacing: 4) {
            Text(routine.name).font(.headline)
            Text(routine.items.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            Button("Übernehmen") { model.settings.gym.routines.append(routine) }
              .font(.subheadline.bold())
              .disabled(settings.gym.routines.contains { $0.name == routine.name })
          }
        }
        if suggestions.count > 1 {
          Button("Alle übernehmen") {
            let existing = Set(model.settings.gym.routines.map(\.name))
            model.settings.gym.routines += suggestions.filter { !existing.contains($0.name) }
          }
        }
      } header: {
        Text("Vorschläge für \(max(settings.profile.schedule.count(of: .strength), 1)) Krafttage pro Woche")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "Jeder große Muskel kommt mindestens zweimal pro Woche dran. Die Übungen passen zu deiner Ausstattung "
              + "und lassen sich nach dem Übernehmen frei ändern.")
          EvidenceDisclosure(ruleIDs: ["gym.frequency", "gym.load", "gym.volume"])
        }
      }
    }
    .navigationTitle("Routinen")
    .toolbar { EditButton() }
    .sheet(item: $editing) { routine in
      RoutineEditor(routine: routine) { saved in
        if let index = model.settings.gym.routines.firstIndex(where: { $0.id == saved.id }) {
          model.settings.gym.routines[index] = saved
        } else {
          model.settings.gym.routines.append(saved)
        }
        editing = nil
      }
    }
  }
}

private struct RoutineRow: View {
  let routine: Routine
  let start: () -> Void
  let edit: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(routine.name).font(.headline)
        Text("\(routine.items.count) Übungen · \(routine.items.reduce(0) { $0 + $1.sets }) Sätze")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Bearbeiten", systemImage: "pencil", action: edit).labelStyle(.iconOnly).buttonStyle(.borderless)
      Button("Starten", systemImage: "play.fill", action: start).labelStyle(.iconOnly).buttonStyle(.borderless)
        .padding(.leading, 8)
    }
  }
}

/// Routine bearbeiten: Übungen, Sätze, Wiederholungsbereich, Pause.
struct RoutineEditor: View {
  @State var routine: Routine
  let save: (Routine) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var picking = false

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $routine.name)
        ForEach($routine.items) { $item in
          Section(item.name) {
            Stepper("\(item.sets) Sätze", value: $item.sets, in: 1...10)
            Stepper("ab \(item.lowerReps) Wdh.", value: $item.lowerReps, in: 1...max(item.upperReps, 1))
            Stepper("bis \(item.upperReps) Wdh.", value: $item.upperReps, in: item.lowerReps...100)
            Stepper("Pause \(item.restSeconds) s", value: $item.restSeconds, in: 30...300, step: 15)
            Button("Entfernen", role: .destructive) { routine.items.removeAll { $0.id == item.id } }
          }
        }
        Section {
          Button("Übung hinzufügen", systemImage: "plus") { picking = true }
        }
      }
      .navigationTitle("Routine")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") { save(routine) }
            .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty || routine.items.isEmpty)
        }
      }
      .sheet(isPresented: $picking) {
        ExercisePickerView { exercise in
          routine.items.append(RoutineItem(exercise: exercise))
          picking = false
        }
      }
    }
  }
}

/// KI-Hinweise zur Gewichtssteigerung.
struct GymHintsSection: View {
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    if !viewModel.progress.isEmpty {
      Section {
        ForEach(Array(viewModel.hints.enumerated()), id: \.offset) { _, hint in
          Label(hint, systemImage: "arrow.up.right.circle").font(.subheadline)
        }
        if viewModel.isLoadingHints { ProgressView() }
        EvidenceDisclosure(ruleIDs: viewModel.hintEvidence)
      } header: {
        HStack {
          Text("Tipps für die nächste Einheit")
          Spacer()
          if model.ai.isConfigured {
            Button("Neu", systemImage: "sparkles") {
              Task { await viewModel.loadHints(ai: model.ai, goal: model.settings.profile.goal) }
            }
            .labelStyle(.iconOnly)
            .disabled(viewModel.isLoadingHints)
          }
        }
      } footer: {
        Text("Quelle: \(viewModel.hintSource). Die Gewichte bestimmen die Regeln; die KI formuliert nur.")
      }
    }
  }
}
