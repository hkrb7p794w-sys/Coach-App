import CoachCore
import SwiftUI

/// Laufende Einheit: Sätze abhaken, Gewicht und Wiederholungen anpassen, Pausen-Timer.
struct ActiveWorkoutView: View {
  let viewModel: GymViewModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var showCatalog = false
  @State private var confirmCancel = false

  var body: some View {
    NavigationStack {
      Group {
        if let session = viewModel.active {
          List {
            Section {
              HStack {
                Text(session.start, style: .timer).monospacedDigit().font(.title3.bold())
                Spacer()
                Text("\(session.doneSetCount) Sätze").foregroundStyle(.secondary)
              }
            }
            ForEach(session.exercises) { exercise in
              ExerciseCard(exercise: exercise, viewModel: viewModel)
            }
            Section {
              Button("Übung hinzufügen", systemImage: "plus") { showCatalog = true }
            }
          }
          .safeAreaInset(edge: .bottom) { RestBanner(viewModel: viewModel) }
          .navigationTitle(session.title)
        } else {
          ContentUnavailableView("Keine laufende Einheit", systemImage: "dumbbell")
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Schließen") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Beenden") {
            Task {
              await viewModel.finish(context: context, writer: HealthWorkoutWriter())
              if viewModel.active == nil { dismiss() }
            }
          }
          .disabled(viewModel.isSaving || viewModel.active == nil)
        }
        ToolbarItem(placement: .bottomBar) {
          Button("Einheit verwerfen", role: .destructive) { confirmCancel = true }
            .disabled(viewModel.active == nil)
        }
      }
      .confirmationDialog("Einheit verwerfen?", isPresented: $confirmCancel, titleVisibility: .visible) {
        Button("Verwerfen", role: .destructive) {
          viewModel.cancelActive()
          dismiss()
        }
      }
      .sheet(isPresented: $showCatalog) {
        ExercisePicker { rule in
          viewModel.addExercise(rule)
          showCatalog = false
        }
      }
      .alert(
        "Hinweis",
        isPresented: Binding(get: { viewModel.message != nil && viewModel.active != nil }, set: { _ in })
      ) {
        Button("OK") { viewModel.message = nil }
      } message: {
        Text(viewModel.message ?? "")
      }
    }
  }
}

private struct ExerciseCard: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel

  private var step: Double {
    ExerciseCatalog.rulesByID[exercise.exerciseID]?.step ?? 2.5
  }

  var body: some View {
    Section {
      ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
        SetRow(index: index, set: set, step: step) { change in
          switch change {
          case .reps(let reps): viewModel.setReps(reps, set: index, of: exercise.id)
          case .weight(let weight): viewModel.setWeight(weight, set: index, of: exercise.id)
          case .toggle: viewModel.toggleDone(set: index, of: exercise.id)
          }
        }
        .swipeActions {
          Button("Löschen", role: .destructive) { viewModel.removeSet(index, from: exercise.id) }
        }
      }
      Button("Satz hinzufügen", systemImage: "plus.circle") { viewModel.addSet(to: exercise.id) }
        .font(.footnote)
    } header: {
      HStack {
        Text(exercise.name)
        Spacer()
        Menu {
          Button("Übung entfernen", role: .destructive) { viewModel.removeExercise(exercise.id) }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    } footer: {
      if let progress = viewModel.progress.first(where: { $0.exerciseID == exercise.exerciseID }) {
        Text(progress.headline)
      }
    }
  }
}

private struct SetRow: View {
  enum Change {
    case reps(Int)
    case weight(Double)
    case toggle
  }

  let index: Int
  let set: LoggedSet
  let step: Double
  let change: (Change) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg)) kg" : "Körpergewicht")
          .monospacedDigit()
          .font(.caption)
        Stepper("Gewicht", value: Binding(get: { set.weightKg }, set: { change(.weight($0)) }), in: 0...500, step: step)
          .labelsHidden()
      }
      VStack(alignment: .leading, spacing: 2) {
        Text("\(set.reps) Wdh.").monospacedDigit().font(.caption)
        Stepper("Wiederholungen", value: Binding(get: { set.reps }, set: { change(.reps($0)) }), in: 0...100)
          .labelsHidden()
      }
      Spacer(minLength: 0)
      Button {
        change(.toggle)
      } label: {
        Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(set.done ? .green : .secondary)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(set.done ? "Satz erledigt" : "Satz abhaken")
    }
    .font(.subheadline)
  }
}

private struct RestBanner: View {
  let viewModel: GymViewModel

  var body: some View {
    if let end = viewModel.restEndsAt, end > .now {
      HStack {
        Image(systemName: "timer")
        Text("Pause")
        Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().bold()
        Spacer()
        Button("Weiter") { viewModel.skipRest() }
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
      .padding(.horizontal)
    }
  }
}

private struct ExercisePicker: View {
  let pick: (ExerciseRule) -> Void
  @State private var search = ""
  @Environment(\.dismiss) private var dismiss

  private var rules: [ExerciseRule] {
    var seen = Set<String>()
    let unique = ExerciseCatalog.rules.filter { seen.insert($0.id).inserted }
    let filtered = search.isEmpty ? unique : unique.filter { $0.name.localizedCaseInsensitiveContains(search) }
    return filtered
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(MuscleVolume.groups + [.forearms], id: \.self) { group in
          let items = rules.filter { $0.group == group }
          if !items.isEmpty {
            Section(group.rawValue) {
              ForEach(items, id: \.id) { rule in
                Button(rule.name) { pick(rule) }
              }
            }
          }
        }
        if !search.isEmpty {
          Section {
            Button("„\(search)“ als eigene Übung") { pick(.fallback(name: search)) }
          }
        }
      }
      .searchable(text: $search, prompt: "Übung suchen")
      .navigationTitle("Übung hinzufügen")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
      }
    }
  }
}
