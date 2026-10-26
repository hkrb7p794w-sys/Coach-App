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
        ExercisePickerView { exercise in
          viewModel.addExercise(exercise)
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
  @Environment(AppModel.self) private var model
  @State private var showDetail = false

  var body: some View {
    let gym = model.settings.gym
    let info = gym.exercise(exercise.exerciseID)
    let step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step
    Section {
      if let last = viewModel.lastTime(of: exercise.exerciseID) {
        Text(last).font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
        SetRow(
          index: index, set: set, step: step, isTime: info?.tracking == .time, asksRIR: gym.tracksRIR
        ) { change in
          switch change {
          case .reps(let reps): viewModel.setReps(reps, set: index, of: exercise.id)
          case .weight(let weight): viewModel.setWeight(weight, set: index, of: exercise.id)
          case .rir(let rir): viewModel.setRIR(rir, set: index, of: exercise.id)
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
          Button("Anleitung und Verlauf", systemImage: "info.circle") { showDetail = true }
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
    .sheet(isPresented: $showDetail) {
      NavigationStack {
        ExerciseDetailView(exerciseID: exercise.exerciseID, viewModel: viewModel)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showDetail = false } }
          }
      }
    }
  }
}

private struct SetRow: View {
  enum Change {
    case reps(Int)
    case weight(Double)
    case rir(Int?)
    case toggle
  }

  let index: Int
  let set: LoggedSet
  let step: Double
  var isTime = false
  var asksRIR = false
  let change: (Change) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      row
      // Nach dem Abhaken: Wiederholungen in Reserve schätzen.
      if asksRIR, set.done, !isTime {
        HStack(spacing: 6) {
          Text("Noch drin:").font(.caption).foregroundStyle(.secondary)
          ForEach(0..<5) { value in
            Button(value == 4 ? "4+" : "\(value)") { change(.rir(set.rir == value ? nil : value)) }
              .font(.caption.bold())
              .buttonStyle(.bordered)
              .tint(set.rir == value ? .accentColor : .secondary)
              .controlSize(.mini)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wiederholungen in Reserve")
      }
    }
  }

  private var row: some View {
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
        Text(isTime ? "\(set.reps) s" : "\(set.reps) Wdh.").monospacedDigit().font(.caption)
        Stepper(
          isTime ? "Sekunden" : "Wiederholungen", value: Binding(get: { set.reps }, set: { change(.reps($0)) }),
          in: 0...600, step: isTime ? 5 : 1
        )
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
