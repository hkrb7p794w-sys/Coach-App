import CoachCore
import SwiftUI

/// KI-Trainingsplan: erst ein kurzer Fragebogen, dann ein Vorschlag aus Profil, Ausstattung und Verlauf. Die Regeln
/// prüfen den Vorschlag (bekannte Übungen, eigene Ausstattung, Grenzen für Sätze und Pausen, Wochenvolumen).
struct GymPlanView: View {
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var request = GymCoach.PlanRequest()
  @State private var result: GymCoach.PlanResult?
  @State private var source = ""
  @State private var isLoading = false
  @State private var error: String?
  @State private var replaceExisting = false
  @State private var prepared = false

  var body: some View {
    NavigationStack {
      Form {
        if let result {
          preview(result)
        } else {
          questions
        }
      }
      .navigationTitle(result == nil ? "KI-Trainingsplan" : "Vorschlag")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
      }
      .onAppear {
        // Nur beim ersten Öffnen vorbelegen, sonst würden eigene Eingaben überschrieben.
        guard !prepared else { return }
        prepared = true
        request.daysPerWeek = max(model.settings.profile.schedule.count(of: .strength), 2)
        request.experience = model.settings.profile.level(for: .strength)
        request.equipment = model.settings.gym.equipment
      }
    }
  }

  // MARK: - Fragebogen

  @ViewBuilder private var questions: some View {
    Section("Ziel") {
      Picker("Ziel", selection: $request.goal) {
        ForEach(GymCoach.PlanGoal.allCases) { Text($0.label).tag($0) }
      }
      Stepper("\(request.daysPerWeek) Tage pro Woche", value: $request.daysPerWeek, in: 1...6)
      Stepper(
        "\(request.minutesPerSession) Minuten je Einheit", value: $request.minutesPerSession, in: 30...120, step: 15)
    }
    Section {
      ForEach(GymCoach.majorGroups + [.biceps, .triceps, .core], id: \.self) { group in
        Toggle(
          group.rawValue,
          isOn: Binding(
            get: { request.focus.contains(group) },
            set: { isOn in
              if isOn { request.focus.append(group) } else { request.focus.removeAll { $0 == group } }
            }))
      }
    } header: {
      Text("Schwerpunkt (optional)")
    }
    Section {
      TextField("z. B. Schulter links, Knie", text: $request.limitations, axis: .vertical)
    } header: {
      Text("Beschwerden oder Einschränkungen")
    } footer: {
      Text("Übungen, die das belasten, lässt die KI weg. Bei Schmerzen bitte ärztlich abklären.")
    }
    Section {
      Toggle("Übungen aus meinen Trainingsplänen bevorzugen", isOn: $request.keepFavorites)
    } footer: {
      Text(
        "Außerdem fließen deine letzten Gewichte, die Beobachtungen aus dem Verlauf und deine anderen Sportarten ein.")
    }
    Section("Erfahrung") {
      Picker("Erfahrung im Krafttraining", selection: experience) {
        ForEach(ExperienceLevel.allCases) { Text($0.label).tag($0) }
      }
    }
    Section {
      ForEach(Equipment.allCases, id: \.self) { item in
        Toggle(item.label, isOn: equipmentBinding(item))
      }
    } header: {
      Text("Ausstattung für diesen Plan")
    } footer: {
      Text("Gilt nur für diesen Plan. Deine Standard-Ausstattung bleibt in den Einstellungen unverändert.")
    }
    Section("Zusammenfassung") {
      Text(summary).font(.footnote)
      ForEach(issues.blocking, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
      ForEach(issues.hints, id: \.self) { Label($0, systemImage: "info.circle").font(.footnote) }
    }
    Section {
      Button {
        Task { await generate() }
      } label: {
        if isLoading {
          HStack {
            ProgressView()
            Text("Plan wird erstellt …")
          }
        } else {
          Label("Plan erstellen", systemImage: "sparkles")
        }
      }
      .disabled(isLoading || !issues.blocking.isEmpty)
      if let error { Text(error).foregroundStyle(.red).font(.footnote) }
    } footer: {
      if !model.ai.isConfigured {
        Text("Ohne KI-Worker gibt es den Regel-Vorschlag passend zu deinen Krafttagen.")
      }
    }
  }

  private var usableEquipment: Set<Equipment> { request.equipment ?? model.settings.gym.equipment }

  private var issues: (blocking: [String], hints: [String]) {
    GymCoach.planIssues(request, equipment: model.settings.gym.equipment)
  }

  private var experience: Binding<ExperienceLevel> {
    Binding(
      get: { request.experience ?? model.settings.profile.level(for: .strength) },
      set: { request.experience = $0 })
  }

  private func equipmentBinding(_ item: Equipment) -> Binding<Bool> {
    Binding(
      get: { usableEquipment.contains(item) },
      set: { isOn in
        var value = usableEquipment
        if isOn { value.insert(item) } else { value.remove(item) }
        request.equipment = value
      })
  }

  /// Genau das, was an die KI geht.
  private var summary: String {
    let focus = request.focus.isEmpty ? "ohne Schwerpunkt" : request.focus.map(\.rawValue).joined(separator: ", ")
    let equipment = Equipment.allCases.filter { usableEquipment.contains($0) }.map(\.label).joined(separator: ", ")
    return "\(request.goal.label), \(request.daysPerWeek) Tage pro Woche, \(request.minutesPerSession) Minuten. "
      + "Schwerpunkt: \(focus). Erfahrung: \(experience.wrappedValue.label). Ausstattung: \(equipment)."
      + (request.limitations.isEmpty ? "" : " Einschränkungen: \(request.limitations).")
  }

  // MARK: - Vorschau

  @ViewBuilder private func preview(_ result: GymCoach.PlanResult) -> some View {
    ForEach(result.routines) { routine in
      Section(routine.name) {
        ForEach(routine.items) { item in
          VStack(alignment: .leading, spacing: 2) {
            Text(item.name).font(.subheadline.bold())
            Text(itemText(item)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    if !result.notes.isEmpty {
      Section("Hinweise") {
        ForEach(result.notes, id: \.self) { Text($0).font(.subheadline) }
      }
    }
    if !result.corrections.isEmpty {
      Section {
        ForEach(result.corrections, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
      } header: {
        Text("Von den Regeln korrigiert")
      }
    }
    Section {
      Toggle("Bisherige Trainingspläne ersetzen", isOn: $replaceExisting)
      Button("Plan übernehmen", systemImage: "checkmark.circle.fill") { adopt(result) }
        .font(.headline)
      Button("Neu erstellen", systemImage: "arrow.clockwise") { self.result = nil }
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text("Quelle: \(source). Ohne „Ersetzen“ kommen die Pläne zu deinen bestehenden hinzu.")
        EvidenceDisclosure(ruleIDs: ["gym.frequency", "gym.volume", "gym.load"])
      }
    }
  }

  private func itemText(_ item: RoutineItem) -> String {
    let isTime = ExerciseLibrary.info(item.exerciseID, custom: model.settings.gym.customExercises)?.tracking == .time
    let unit = isTime ? "s" : "Wdh."
    var text = "\(item.sets) × \(item.lowerReps)–\(item.upperReps) \(unit) · Pause \(item.restSeconds) s"
    if let weight = item.weightKg { text += " · Start \(GermanFormat.number(weight)) kg" }
    return text
  }

  // MARK: - Aktionen

  private func generate() async {
    let settings = model.settings
    let lastWeights = GymCoach.lastSets(viewModel.sessions).mapValues(\.weightKg)
    error = nil
    guard model.ai.isConfigured else {
      result = fallback(lastWeights: lastWeights)
      source = "Regeln (ohne KI)"
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let input = GymCoach.planInput(
        request: request, profile: settings.profile, equipment: settings.gym.equipment,
        routines: settings.gym.routines, sessions: viewModel.sessions, custom: settings.gym.customExercises,
        today: CalendarDay(date: .now), notes: settings.gym.notes)
      let response = try await model.ai.run(task: "gym_plan", input: input)
      let checked = GymCoach.validatePlan(
        response.output, request: request, equipment: usableEquipment,
        custom: settings.gym.customExercises, lastWeights: lastWeights)
      if checked.routines.isEmpty {
        result = fallback(lastWeights: lastWeights)
        source = "Regeln (KI-Vorschlag unbrauchbar)"
      } else {
        result = checked
        source = "KI · \(response.model), geprüft von den Regeln"
      }
    } catch {
      result = fallback(lastWeights: lastWeights)
      source = "Regeln (KI nicht erreichbar)"
    }
  }

  /// Regel-Vorschlag mit den letzten Gewichten als Startwert.
  private func fallback(lastWeights: [String: Double]) -> GymCoach.PlanResult {
    let suggestions = RoutineTemplates.suggest(
      profile: model.settings.profile, equipment: usableEquipment)
    let routines = suggestions.map { routine in
      var routine = routine
      for index in routine.items.indices {
        routine.items[index].weightKg = lastWeights[routine.items[index].exerciseID]
      }
      return routine
    }
    return GymCoach.PlanResult(
      routines: routines, notes: ["Jeder große Muskel kommt mindestens zweimal pro Woche dran."], corrections: [])
  }

  private func adopt(_ result: GymCoach.PlanResult) {
    if replaceExisting {
      model.settings.gym.routines = result.routines
    } else {
      let existing = Set(model.settings.gym.routines.map(\.name))
      model.settings.gym.routines += result.routines.map { routine in
        var routine = routine
        if existing.contains(routine.name) { routine.name += " (KI)" }
        return routine
      }
    }
    dismiss()
  }
}
