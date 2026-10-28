import Charts
import CoachCore
import SwiftUI
import UniformTypeIdentifiers

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
        NavigationLink("Gym-Einstellungen") { GymSettingsView() }
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
          ExerciseHistoryCharts(history: history)
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
        Picker("Langhantelstange", selection: $settings.gym.barKg) {
          ForEach([20.0, 15, 10, 7.5], id: \.self) { weight in Text("\(GermanFormat.number(weight)) kg").tag(weight) }
        }
        ForEach(Self.plateOptions, id: \.self) { plate in
          Toggle(
            "Scheibe \(GermanFormat.number(plate)) kg",
            isOn: Binding(
              get: { settings.gym.plates.contains(plate) },
              set: { on in
                settings.gym.plates.removeAll { $0 == plate }
                if on { settings.gym.plates = (settings.gym.plates + [plate]).sorted(by: >) }
              }))
        }
      } header: {
        Text("Stange und Scheiben")
      } footer: {
        Text(
          "Für den Scheibenrechner und die Aufwärmsätze. Eine andere Stange je Übung (z. B. SZ-Stange) stellst du "
            + "unter Einstellungen › Gym › Je Übung oder während der Einheit im Menü der Übung ein.")
      }
    }
    .navigationTitle("Ausstattung")
  }

  static let plateOptions: [Double] = [25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5]
}

/// Eigene Routinen und Vorschläge passend zu Profil und Ausstattung.
struct RoutinesView: View {
  let viewModel: GymViewModel
  let start: (Routine) -> Void
  @Environment(AppModel.self) private var model
  @State private var editing: Routine?
  @State private var showsPlanner = false
  @State private var importingGymBook = false
  @State private var gymBookResult: String?
  @Environment(\.modelContext) private var context

  var body: some View {
    let settings = model.settings
    let suggestions = RoutineTemplates.suggest(profile: settings.profile, equipment: settings.gym.equipment)
    List {
      Section {
        Button("KI-Trainingsplan erstellen", systemImage: "sparkles") { showsPlanner = true }
          .font(.headline)
      } footer: {
        Text(
          "Ein paar Fragen zu Ziel, Tagen und Beschwerden, dann ein Plan aus deinem Verlauf und deiner Ausstattung – "
            + "von den Regeln geprüft.")
      }
      Section {
        if settings.gym.routines.isEmpty {
          Text("Noch keine eigene Routine. Übernimm einen Vorschlag oder lege selbst eine an.")
            .foregroundStyle(.secondary)
        }
        ForEach(settings.gym.routines) { routine in
          RoutineRow(routine: routine, start: { start(routine) }, edit: { editing = routine })
            .contextMenu {
              Button("Duplizieren", systemImage: "plus.square.on.square") {
                var copy = routine
                copy.id = UUID()
                copy.name += " (Kopie)"
                copy.items = copy.items.map { item in
                  var item = item
                  item.id = UUID()
                  return item
                }
                model.settings.gym.routines.append(copy)
              }
            }
        }
        .onDelete { offsets in model.settings.gym.routines.remove(atOffsets: offsets) }
        .onMove { from, to in model.settings.gym.routines.move(fromOffsets: from, toOffset: to) }
        Button("Eigene Routine anlegen", systemImage: "plus") {
          editing = Routine(name: "Neue Routine", items: [])
        }
      } header: {
        Text("Meine Routinen")
      }
      Section {
        let gymBook = RoutineTemplates.gymBook
        ForEach(gymBook) { routine in
          VStack(alignment: .leading, spacing: 4) {
            Text(routine.name).font(.headline)
            Text(routine.items.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
          }
        }
        Button("Alle GymBook-Pläne übernehmen", systemImage: "square.and.arrow.down") {
          let existing = Set(model.settings.gym.routines.map(\.name))
          model.settings.gym.routines += gymBook.filter { !existing.contains($0.name) }
        }
        .disabled(gymBook.allSatisfy { routine in settings.gym.routines.contains { $0.name == routine.name } })
        Button("Verlauf aus GymBook-Backup importieren", systemImage: "clock.arrow.circlepath") {
          importingGymBook = true
        }
        if let gymBookResult {
          Text(gymBookResult).font(.footnote).foregroundStyle(.secondary)
        }
      } header: {
        Text("Aus GymBook")
      } footer: {
        Text(
          "Deine vier Pläne aus GymBook mit den zuletzt genutzten Gewichten als Startwert. Für den Verlauf die "
            + "Backup-Datei aus GymBook (….database) in „Dateien“ sichern und hier auswählen. Mehrfaches Importieren "
            + "legt nichts doppelt an.")
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
    .sheet(isPresented: $showsPlanner) { GymPlanView(viewModel: viewModel) }
    .fileImporter(isPresented: $importingGymBook, allowedContentTypes: [.item]) { result in
      switch result {
      case .success(let url):
        do {
          gymBookResult = try GymBookReader.importBackup(at: url, context: context, settings: model.settings)
        } catch {
          gymBookResult = error.localizedDescription
        }
      case .failure(let error):
        gymBookResult = error.localizedDescription
      }
    }
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

/// Routine bearbeiten: Übungen, Reihenfolge, Sätze, Wiederholungs- bzw. Sekundenbereich, Pause und Startgewicht.
struct RoutineEditor: View {
  @State var routine: Routine
  let save: (Routine) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var picking = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $routine.name)
        } footer: {
          Text(
            "Eigener Plan: Übungen, Reihenfolge, Sätze, Ziel-Wiederholungen, Pausen und Startgewicht frei "
              + "wählbar. Im Supersatz wechseln sich die Übungen ab, die Pause kommt nach der Runde.")
        }
        ForEach(Array($routine.items.enumerated()), id: \.element.id) { index, $item in
          let isTime =
            ExerciseLibrary.info(item.exerciseID, custom: model.settings.gym.customExercises)?.tracking == .time
          let unit = isTime ? "s" : "Wdh."
          Section("\(index + 1). \(item.name)") {
            Stepper("\(item.sets) Sätze", value: $item.sets, in: 1...10)
            Stepper(
              "ab \(item.lowerReps) \(unit)", value: $item.lowerReps, in: 1...max(item.upperReps, 1),
              step: isTime ? 5 : 1)
            Stepper(
              "bis \(item.upperReps) \(unit)", value: $item.upperReps, in: item.lowerReps...(isTime ? 600 : 100),
              step: isTime ? 5 : 1)
            Stepper("Pause \(item.restSeconds) s", value: $item.restSeconds, in: 30...300, step: 15)
            if index < routine.items.count - 1 {
              Toggle("Supersatz mit \(routine.items[index + 1].name)", isOn: $item.supersetWithNext)
            }
            if !isTime {
              LabeledContent("Startgewicht") {
                TextField("aus Verlauf", value: $item.weightKg, format: .number.precision(.fractionLength(0...2)))
                  .keyboardType(.decimalPad)
                  .multilineTextAlignment(.trailing)
                Text("kg").foregroundStyle(.secondary)
              }
            }
            HStack {
              Button("Nach oben", systemImage: "arrow.up") { move(index, by: -1) }
                .disabled(index == 0)
              Spacer()
              Button("Nach unten", systemImage: "arrow.down") { move(index, by: 1) }
                .disabled(index == routine.items.count - 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Button("Entfernen", role: .destructive) { routine.items.removeAll { $0.id == item.id } }
          }
        }
        Section {
          Button("Übung hinzufügen", systemImage: "plus") { picking = true }
        } footer: {
          Text(
            "Das Startgewicht gilt, solange es für die Übung noch keinen Verlauf gibt; danach schlägt die Progression "
              + "das Gewicht vor. Eigene Übungen legst du in der Übungsauswahl an.")
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

  private func move(_ index: Int, by offset: Int) {
    let target = index + offset
    guard routine.items.indices.contains(index), routine.items.indices.contains(target) else { return }
    withAnimation { routine.items.swapAt(index, target) }
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
