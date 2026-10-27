import CoachCore
import SwiftUI
import UserNotifications

/// Mitteilung zum Pausenende, falls die App im Hintergrund ist (wie Strong oder Hevy).
enum RestAlarm {
  static let identifier = "coach.rest"

  static func schedule(at end: Date?) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard let end, end.timeIntervalSinceNow > 1 else { return }
    let content = UNMutableNotificationContent()
    content.title = "Pause vorbei"
    content.body = "Weiter mit dem nächsten Satz."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }
}

/// Welcher Wert gerade über den Ziffernblock eingegeben wird.
struct SetValueTarget: Identifiable, Equatable {
  enum Field { case weight, reps }

  var exerciseID: UUID
  var set: Int
  var field: Field
  var id: String { "\(exerciseID)-\(set)-\(field)" }
}

/// Laufende Einheit. Standard ist die Fokus-Karte: nur der nächste Satz, groß, mit einem Knopf zum Abhaken im
/// Daumenbereich. Die Liste zeigt alle Übungen auf einmal.
struct ActiveWorkoutView: View {
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @AppStorage("gym.showsList") private var showsList = false
  @State private var showCatalog = false
  @State private var confirmCancel = false
  @State private var showFinish = false
  @State private var editing: SetValueTarget?

  var body: some View {
    NavigationStack {
      Group {
        if let session = viewModel.active {
          content(session)
        } else if viewModel.finished == nil {
          ContentUnavailableView("Keine laufende Einheit", systemImage: "dumbbell")
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Ausblenden", systemImage: "chevron.down") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
          Picker("Ansicht", selection: $showsList) {
            Text("Fokus").tag(false)
            Text("Liste").tag(true)
          }
          .pickerStyle(.segmented)
          .frame(width: 170)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Beenden") { showFinish = true }
            .disabled(viewModel.active == nil)
        }
      }
      .overlay(alignment: .top) { UndoToast(viewModel: viewModel) }
      .confirmationDialog("Einheit verwerfen?", isPresented: $confirmCancel, titleVisibility: .visible) {
        Button("Verwerfen", role: .destructive) {
          viewModel.cancelActive()
          dismiss()
        }
      } message: {
        Text("Alle Sätze dieser Einheit gehen verloren.")
      }
      .sheet(isPresented: $showCatalog) {
        ExercisePickerView { exercise in
          viewModel.addExercise(exercise)
          showCatalog = false
        }
      }
      .sheet(item: $editing) { target in
        SetValuePad(target: target, viewModel: viewModel)
      }
      .sheet(
        isPresented: $showFinish,
        onDismiss: {
          if viewModel.finished != nil {
            viewModel.dismissFinished()
            dismiss()
          }
        }
      ) {
        FinishWorkoutSheet(viewModel: viewModel) {
          showFinish = false
        }
      }
      .alert(
        "Hinweis",
        isPresented: Binding(
          get: { viewModel.message != nil && viewModel.active != nil && !showFinish }, set: { _ in })
      ) {
        Button("OK") { viewModel.message = nil }
      } message: {
        Text(viewModel.message ?? "")
      }
      // Kurze Vibration beim Abhaken und am Ende der Pause.
      .sensoryFeedback(trigger: viewModel.active?.doneSetCount ?? 0) { old, new in new > old ? .success : nil }
      .task(id: viewModel.restEndsAt) {
        guard let end = viewModel.restEndsAt else { return }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        guard !Task.isCancelled, viewModel.restEndsAt == end else { return }
        viewModel.restFinished()
      }
      .sensoryFeedback(.warning, trigger: viewModel.restFinishedCount)
    }
  }

  @ViewBuilder private func content(_ session: GymSession) -> some View {
    Group {
      if showsList {
        WorkoutListView(session: session, viewModel: viewModel, editing: $editing) { showCatalog = true }
      } else {
        FocusCard(session: session, viewModel: viewModel, editing: $editing)
      }
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 10) {
        RestPanel(viewModel: viewModel)
        if !showsList {
          DoneButton(session: session, viewModel: viewModel) { showFinish = true }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 8)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Übung hinzufügen", systemImage: "plus") { showCatalog = true }
          Button("Einheit verwerfen", systemImage: "trash", role: .destructive) { confirmCancel = true }
        } label: {
          Label("Mehr", systemImage: "ellipsis.circle")
        }
      }
    }
  }
}

// MARK: - Fokus-Karte

/// Welche Übung und welcher Satz auf der Fokus-Karte stehen.
private struct FocusTarget {
  var exerciseIndex: Int
  /// `nil` = alle Sätze dieser Übung erledigt.
  var set: Int?

  init?(session: GymSession, focus: UUID?) {
    if let focus, let index = session.exercises.firstIndex(where: { $0.id == focus }) {
      exerciseIndex = index
      set = session.exercises[index].sets.firstIndex { !$0.done }
    } else if let position = WorkoutFlow.current(in: session) {
      exerciseIndex = position.exercise
      set = position.set
    } else {
      return nil
    }
  }
}

private struct FocusCard: View {
  let session: GymSession
  let viewModel: GymViewModel
  @Binding var editing: SetValueTarget?
  @State private var showDetail = false

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        ExerciseStrip(session: session, viewModel: viewModel)
        if let target = FocusTarget(session: session, focus: viewModel.focusExerciseID) {
          let exercise = session.exercises[target.exerciseIndex]
          header(exercise, target: target)
          if let set = target.set {
            SetEditor(exercise: exercise, index: set, viewModel: viewModel, editing: $editing)
          } else {
            exerciseDone(exercise)
          }
          ExerciseNotes(exercise: exercise, viewModel: viewModel)
          if let set = target.set,
            let next = WorkoutFlow.upcoming(after: .init(exercise: target.exerciseIndex, set: set), in: session)
          {
            upcoming(next)
          }
          sheetHost(exercise)
        } else {
          allDone
        }
      }
      .padding()
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private func header(_ exercise: LoggedExercise, target: FocusTarget) -> some View {
    VStack(spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(session.start, style: .timer).monospacedDigit().font(.footnote).foregroundStyle(.secondary)
        Spacer()
        Menu {
          Button("Anleitung und Verlauf", systemImage: "info.circle") { showDetail = true }
          Button("Satz hinzufügen", systemImage: "plus.circle") { viewModel.addSet(to: exercise.id) }
          Button("Übung entfernen", systemImage: "trash", role: .destructive) {
            viewModel.removeExercise(exercise.id)
          }
        } label: {
          Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Optionen für \(exercise.name)")
      }
      Text(exercise.name).font(.title.bold()).multilineTextAlignment(.center)
      if let set = target.set {
        Text("Satz \(set + 1) von \(exercise.sets.count)").font(.headline).foregroundStyle(.secondary)
      }
    }
  }

  private func exerciseDone(_ exercise: LoggedExercise) -> some View {
    VStack(spacing: 12) {
      Label("Alle Sätze erledigt", systemImage: "checkmark.circle.fill")
        .font(.title3.bold())
        .foregroundStyle(.green)
      Button("Noch einen Satz", systemImage: "plus.circle") { viewModel.addSet(to: exercise.id) }
        .buttonStyle(.bordered)
        .controlSize(.large)
      if WorkoutFlow.current(in: session, preferring: exercise.id) != nil {
        Button("Zur nächsten Übung", systemImage: "arrow.right") { viewModel.focusExerciseID = nil }
          .buttonStyle(.bordered)
          .controlSize(.large)
      }
    }
    .padding(.vertical)
  }

  private func upcoming(_ next: WorkoutFlow.Position) -> some View {
    let exercise = session.exercises[next.exercise]
    let set = exercise.sets[next.set]
    let values = set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg)) kg × \(set.reps)" : "\(set.reps) Wdh."
    return Text("Als Nächstes: \(exercise.name), Satz \(next.set + 1) · \(values)")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
  }

  private var allDone: some View {
    VStack(spacing: 14) {
      Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(.yellow)
      Text("Alle Sätze erledigt").font(.title2.bold())
      Text("\(session.doneSetCount) Sätze · \(GermanFormat.number(session.volumeKg.rounded())) kg bewegt")
        .foregroundStyle(.secondary)
    }
    .padding(.top, 40)
  }

  private func sheetHost(_ exercise: LoggedExercise) -> some View {
    Color.clear.frame(height: 0)
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

/// Übungen als Leiste mit Fortschritt; Tippen wählt die Übung für die Fokus-Karte.
private struct ExerciseStrip: View {
  let session: GymSession
  let viewModel: GymViewModel

  var body: some View {
    let shown = FocusTarget(session: session, focus: viewModel.focusExerciseID)?.exerciseIndex
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
            let progress = WorkoutFlow.progress(of: exercise)
            let complete = progress.total > 0 && progress.done == progress.total
            Button {
              viewModel.focusExerciseID = exercise.id
            } label: {
              HStack(spacing: 4) {
                if complete { Image(systemName: "checkmark") }
                Text(exercise.name).lineLimit(1)
                Text("\(progress.done)/\(progress.total)").monospacedDigit().foregroundStyle(.secondary)
              }
              .font(.subheadline)
              .padding(.horizontal, 12)
              .frame(minHeight: 40)
              .background(
                index == shown ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.tertiary), in: Capsule())
            }
            .buttonStyle(.plain)
            .id(exercise.id)
          }
        }
      }
      .onChange(of: shown) { _, index in
        guard let index, session.exercises.indices.contains(index) else { return }
        withAnimation { proxy.scrollTo(session.exercises[index].id, anchor: .center) }
      }
    }
  }
}

/// Gewicht und Wiederholungen groß, mit großen ± Knöpfen; Tippen auf die Zahl öffnet den Ziffernblock.
private struct SetEditor: View {
  let exercise: LoggedExercise
  let index: Int
  let viewModel: GymViewModel
  @Binding var editing: SetValueTarget?
  @Environment(AppModel.self) private var model

  var body: some View {
    let gym = model.settings.gym
    let isTime = gym.exercise(exercise.exerciseID)?.tracking == .time
    let step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step
    let set = exercise.sets[index]
    VStack(spacing: 14) {
      ValueControl(
        text: set.weightKg > 0 ? GermanFormat.number(set.weightKg) : "Körpergewicht",
        unit: set.weightKg > 0 ? "kg" : "", label: "Gewicht", value: set.weightKg,
        minus: { viewModel.setWeight(max(0, set.weightKg - step), set: index, of: exercise.id) },
        plus: { viewModel.setWeight(set.weightKg + step, set: index, of: exercise.id) },
        edit: { editing = SetValueTarget(exerciseID: exercise.id, set: index, field: .weight) })
      ValueControl(
        text: "\(set.reps)", unit: isTime ? "s" : "Wdh.", label: isTime ? "Sekunden" : "Wiederholungen",
        value: Double(set.reps),
        minus: { viewModel.setReps(set.reps - (isTime ? 5 : 1), set: index, of: exercise.id) },
        plus: { viewModel.setReps(set.reps + (isTime ? 5 : 1), set: index, of: exercise.id) },
        edit: { editing = SetValueTarget(exerciseID: exercise.id, set: index, field: .reps) })
    }
  }
}

private struct ValueControl: View {
  let text: String
  let unit: String
  let label: String
  let value: Double
  let minus: () -> Void
  let plus: () -> Void
  let edit: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      RoundButton(systemImage: "minus", label: "\(label) verringern", action: minus)
      Button(action: edit) {
        VStack(spacing: 0) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text)
              .font(.system(size: text.count > 6 ? 30 : 52, weight: .bold, design: .rounded))
              .monospacedDigit()
              .minimumScaleFactor(0.5)
              .lineLimit(1)
            Text(unit).font(.title3.bold()).foregroundStyle(.secondary)
          }
          Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label): \(text) \(unit)")
      .accessibilityHint("Tippen zum Eintippen")
      RoundButton(systemImage: "plus", label: "\(label) erhöhen", action: plus)
    }
    .sensoryFeedback(.selection, trigger: value)
  }
}

private struct RoundButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title2.bold())
        .frame(width: 60, height: 60)
        .background(.fill.tertiary, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// Letztes Mal, Progression, Aufwärmen und Scheiben – klein unter dem Satz.
private struct ExerciseNotes: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel
  var centered = true
  @Environment(AppModel.self) private var model

  var body: some View {
    let gym = model.settings.gym
    let info = gym.exercise(exercise.exerciseID)
    VStack(alignment: centered ? .center : .leading, spacing: 6) {
      if let last = viewModel.lastTime(of: exercise.exerciseID) {
        Text(last)
      }
      if let progress = viewModel.progress.first(where: { $0.exerciseID == exercise.exerciseID }) {
        Text(progress.headline)
      }
      let working = exercise.sets.map(\.weightKg).max() ?? 0
      if let info {
        let warmUp = WarmUp.steps(working: working, equipment: info.equipment, compound: info.compound)
        if !warmUp.isEmpty, !exercise.sets.contains(where: \.done) {
          Text(WarmUp.text(warmUp))
        }
        if info.equipment.first == .barbell, let plates = PlateCalculator.plates(total: working) {
          Text("\(GermanFormat.number(working)) kg · \(PlateCalculator.text(plates))")
        }
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .multilineTextAlignment(centered ? .center : .leading)
  }
}

/// Großer Knopf im Daumenbereich: hakt den Satz der Fokus-Karte ab.
private struct DoneButton: View {
  let session: GymSession
  let viewModel: GymViewModel
  let finish: () -> Void

  var body: some View {
    let target = FocusTarget(session: session, focus: viewModel.focusExerciseID)
    Group {
      if let target, let set = target.set {
        Button {
          viewModel.complete(set: set, of: session.exercises[target.exerciseIndex].id)
        } label: {
          Label("Satz erledigt", systemImage: "checkmark")
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
      } else if target == nil {
        Button(action: finish) {
          Label("Einheit beenden", systemImage: "flag.checkered")
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .buttonBorderShape(.roundedRectangle(radius: 18))
  }
}

// MARK: - Pause

/// Pause groß mit Fortschrittsbalken; darunter freiwillig RIR für den gerade erledigten Satz.
private struct RestPanel: View {
  let viewModel: GymViewModel

  var body: some View {
    if let end = viewModel.restEndsAt, end > .now {
      VStack(spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Label("Pause", systemImage: "timer").font(.headline)
          Spacer()
          Text(timerInterval: Date.now...end, countsDown: true)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .monospacedDigit()
        }
        let start = end.addingTimeInterval(-TimeInterval(max(viewModel.restSeconds, 1)))
        if start < end {
          ProgressView(timerInterval: start...end, countsDown: true) {
            EmptyView()
          } currentValueLabel: {
            EmptyView()
          }
        }
        HStack(spacing: 10) {
          Button("−15 s") { viewModel.adjustRest(by: -15) }
            .accessibilityLabel("Pause 15 Sekunden kürzer")
          Button("+15 s") { viewModel.adjustRest(by: 15) }
            .accessibilityLabel("Pause 15 Sekunden länger")
          Spacer()
          Button("Weiter") { viewModel.skipRest() }.bold()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        ReserveQuestion(viewModel: viewModel)
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
  }
}

/// „Wie viele wären noch gegangen?“ – fünf große Knöpfe statt eines zweiten Pflicht-Tipps pro Satz.
private struct ReserveQuestion: View {
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    if model.settings.gym.tracksRIR, let last = viewModel.lastDone,
      let exercise = viewModel.active?.exercises.first(where: { $0.id == last.exercise }),
      exercise.sets.indices.contains(last.set),
      model.settings.gym.exercise(exercise.exerciseID)?.tracking != .time
    {
      let current = exercise.sets[last.set].rir
      VStack(alignment: .leading, spacing: 6) {
        Text("\(exercise.name), Satz \(last.set + 1): wie viele wären noch gegangen?")
          .font(.footnote)
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          ForEach(0..<5) { value in
            Button {
              viewModel.setRIR(current == value ? nil : value, set: last.set, of: exercise.id)
            } label: {
              Text(value == 4 ? "4+" : "\(value)")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(current == value ? .accentColor : .secondary)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wiederholungen in Reserve")
      }
    }
  }
}

private struct UndoToast: View {
  let viewModel: GymViewModel

  var body: some View {
    if let label = viewModel.undoLabel {
      HStack {
        Text(label).font(.subheadline)
        Spacer()
        Button("Rückgängig") { viewModel.undo() }.bold()
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 48)
      .background(.regularMaterial, in: Capsule())
      .padding(.horizontal)
      .transition(.move(edge: .top).combined(with: .opacity))
      .task(id: label) {
        try? await Task.sleep(for: .seconds(5))
        if !Task.isCancelled { viewModel.clearUndo() }
      }
    }
  }
}

// MARK: - Liste

private struct WorkoutListView: View {
  let session: GymSession
  let viewModel: GymViewModel
  @Binding var editing: SetValueTarget?
  let addExercise: () -> Void

  var body: some View {
    List {
      Section {
        HStack {
          Text(session.start, style: .timer).monospacedDigit().font(.title3.bold())
          Spacer()
          Text("\(session.doneSetCount) Sätze").foregroundStyle(.secondary)
        }
      }
      ForEach(session.exercises) { exercise in
        ExerciseCard(exercise: exercise, viewModel: viewModel, editing: $editing)
      }
      Section {
        Button("Übung hinzufügen", systemImage: "plus", action: addExercise)
      }
    }
  }
}

private struct ExerciseCard: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel
  @Binding var editing: SetValueTarget?
  @Environment(AppModel.self) private var model
  @State private var showDetail = false

  var body: some View {
    let isTime = model.settings.gym.exercise(exercise.exerciseID)?.tracking == .time
    Section {
      ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
        SetRow(index: index, set: set, isTime: isTime, exerciseID: exercise.id, viewModel: viewModel) { field in
          editing = SetValueTarget(exerciseID: exercise.id, set: index, field: field)
        }
        .swipeActions {
          Button("Löschen", role: .destructive) { viewModel.removeSet(index, from: exercise.id) }
        }
      }
      Button("Satz hinzufügen", systemImage: "plus.circle") { viewModel.addSet(to: exercise.id) }
    } header: {
      HStack {
        Text(exercise.name).font(.headline)
        Spacer()
        Menu {
          Button("Auf der Fokus-Karte zeigen", systemImage: "scope") { viewModel.focusExerciseID = exercise.id }
          Button("Anleitung und Verlauf", systemImage: "info.circle") { showDetail = true }
          Button("Übung entfernen", systemImage: "trash", role: .destructive) {
            viewModel.removeExercise(exercise.id)
          }
        } label: {
          Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
      }
    } footer: {
      ExerciseNotes(exercise: exercise, viewModel: viewModel, centered: false)
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

/// Ein Satz in der Liste: Werte groß und antippbar (Ziffernblock), Abhaken mit großem Tippziel.
private struct SetRow: View {
  let index: Int
  let set: LoggedSet
  let isTime: Bool
  let exerciseID: UUID
  let viewModel: GymViewModel
  let edit: (SetValueTarget.Field) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("\(index + 1)").font(.subheadline.bold()).foregroundStyle(.secondary).frame(width: 18)
      Button {
        edit(.weight)
      } label: {
        Text(set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg)) kg" : "Körpergew.")
          .font(.title3.bold())
          .monospacedDigit()
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      }
      .buttonStyle(.borderless)
      Button {
        edit(.reps)
      } label: {
        Text(isTime ? "\(set.reps) s" : "× \(set.reps)")
          .font(.title3.bold())
          .monospacedDigit()
          .frame(minWidth: 64, minHeight: 44, alignment: .leading)
      }
      .buttonStyle(.borderless)
      if let rir = set.rir, set.done {
        Text("RIR \(rir == 4 ? "4+" : "\(rir)")").font(.caption).foregroundStyle(.secondary)
      }
      Button {
        viewModel.toggleDone(set: index, of: exerciseID)
      } label: {
        Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
          .font(.title)
          .foregroundStyle(set.done ? .green : .secondary)
          .frame(width: 48, height: 48)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(set.done ? "Satz erledigt, tippen für wieder offen" : "Satz abhaken")
    }
    .contextMenu {
      if set.done, !isTime {
        Menu("Wiederholungen in Reserve") {
          ForEach(0..<5) { value in
            Button(value == 4 ? "4 oder mehr" : "\(value)") { viewModel.setRIR(value, set: index, of: exerciseID) }
          }
          Button("Keine Angabe") { viewModel.setRIR(nil, set: index, of: exerciseID) }
        }
      }
    }
  }
}

// MARK: - Ziffernblock

/// Großer Ziffernblock mit Schnelltasten statt vieler Stepper-Tipps (60 → 80 kg: 3 Tipps statt 8).
private struct SetValuePad: View {
  let target: SetValueTarget
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""

  private var exercise: LoggedExercise? {
    viewModel.active?.exercises.first { $0.id == target.exerciseID }
  }

  var body: some View {
    let gym = model.settings.gym
    let isWeight = target.field == .weight
    let isTime = exercise.flatMap { gym.exercise($0.exerciseID) }?.tracking == .time
    let step = exercise.map { ExerciseLibrary.rule($0.exerciseID, name: $0.name, custom: gym.customExercises).step }
    let deltas = Self.deltas(isWeight: isWeight, isTime: isTime, step: step ?? 2.5)
    let unit = isWeight ? "kg" : isTime ? "s" : "Wdh."
    VStack(spacing: 14) {
      Text("\(isWeight ? "Gewicht" : isTime ? "Dauer" : "Wiederholungen") · Satz \(target.set + 1)")
        .font(.headline)
        .padding(.top)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(text.isEmpty ? "0" : text)
          .font(.system(size: 56, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(text.isEmpty ? .secondary : .primary)
        Text(unit).font(.title2.bold()).foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        ForEach(deltas, id: \.self) { delta in
          Button((delta > 0 ? "+" : "−") + GermanFormat.number(abs(delta))) {
            let value = max(0, (NumberPad.value(text) ?? 0) + delta)
            text = isWeight ? NumberPad.text(for: value) : value > 0 ? "\(Int(value))" : ""
          }
          .frame(maxWidth: .infinity)
        }
        if let previous = previousValue {
          Button("wie Satz \(target.set)") { text = previous }
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
        ForEach(1..<10) { digit in key("\(digit)", .digit(digit), isWeight: isWeight) }
        if isWeight { key(",", .comma, isWeight: true) } else { Color.clear.frame(height: 56) }
        key("0", .digit(0), isWeight: isWeight)
        key("⌫", .delete, isWeight: isWeight).accessibilityLabel("Löschen")
      }
      Button {
        save()
      } label: {
        Text("Übernehmen").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.roundedRectangle(radius: 16))
    }
    .padding(.horizontal)
    .presentationDetents([.large])
    .sensoryFeedback(.selection, trigger: text)
    .onAppear {
      guard let set = exercise?.sets[safe: target.set] else { return }
      text = isWeight ? NumberPad.text(for: set.weightKg) : set.reps > 0 ? "\(set.reps)" : ""
    }
  }

  private static func deltas(isWeight: Bool, isTime: Bool, step: Double) -> [Double] {
    if isWeight { return [-step, step, 5, 10] }
    return isTime ? [-5, 5, 15] : [-1, 1, 2]
  }

  /// Wert des vorherigen Satzes für „wie Satz n“.
  private var previousValue: String? {
    guard target.set > 0, let set = exercise?.sets[safe: target.set - 1] else { return nil }
    return target.field == .weight ? NumberPad.text(for: set.weightKg) : "\(set.reps)"
  }

  private func key(_ title: String, _ key: NumberPad.Key, isWeight: Bool) -> some View {
    Button {
      text = NumberPad.apply(key, to: text, allowsDecimals: isWeight)
    } label: {
      Text(title)
        .font(.title.bold())
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }

  private func save() {
    let value = NumberPad.value(text) ?? 0
    switch target.field {
    case .weight: viewModel.setWeight(value, set: target.set, of: target.exerciseID)
    case .reps: viewModel.setReps(Int(value), set: target.set, of: target.exerciseID)
    }
    dismiss()
  }
}

// MARK: - Abschluss

/// Vor dem Speichern: Zusammenfassung und vergessene Sätze; danach Bestleistungen und Status.
private struct FinishWorkoutSheet: View {
  let viewModel: GymViewModel
  let close: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.modelContext) private var context

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          if let finished = viewModel.finished {
            result(finished)
          } else if let session = viewModel.active {
            review(session)
          }
        }
        .padding()
      }
      .navigationTitle(viewModel.finished == nil ? "Einheit beenden" : "Gespeichert")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(viewModel.isSaving)
  }

  private func review(_ session: GymSession) -> some View {
    let summary = WorkoutFlow.summary(of: session)
    return VStack(spacing: 16) {
      SummaryGrid(summary: summary)
      if summary.openSets > 0 {
        Label(
          summary.openSets == 1
            ? "1 Satz ist eingetragen, aber nicht abgehakt."
            : "\(summary.openSets) Sätze sind eingetragen, aber nicht abgehakt.",
          systemImage: "exclamationmark.circle"
        )
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        bigButton("Mit offenen Sätzen speichern", prominent: true) { await save(completing: true) }
        if summary.doneSets > 0 {
          bigButton("Nur abgehakte speichern", prominent: false) { await save(completing: false) }
        }
      } else if summary.doneSets > 0 {
        bigButton("Speichern", prominent: true) { await save(completing: false) }
      } else {
        Text("Noch kein Satz erledigt – nichts zu speichern.").foregroundStyle(.secondary)
      }
      Button("Weiter trainieren", action: close)
        .frame(maxWidth: .infinity, minHeight: 44)
      if viewModel.isSaving { ProgressView("Speichern …") }
    }
    .disabled(viewModel.isSaving)
  }

  private func result(_ finished: FinishedWorkout) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
      Text(finished.title).font(.title2.bold())
      SummaryGrid(summary: finished.summary)
      if !finished.records.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Bestleistungen").font(.headline)
          ForEach(finished.records, id: \.self) { record in
            Label(record, systemImage: "trophy.fill").foregroundStyle(.primary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Text(finished.status).font(.footnote).foregroundStyle(.secondary)
      bigButton("Fertig", prominent: true) { close() }
    }
  }

  @ViewBuilder
  private func bigButton(_ title: String, prominent: Bool, action: @escaping () async -> Void) -> some View {
    let button = Button {
      Task { await action() }
    } label: {
      Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
    }
    .buttonBorderShape(.roundedRectangle(radius: 14))
    if prominent {
      button.buttonStyle(.borderedProminent)
    } else {
      button.buttonStyle(.bordered)
    }
  }

  private func save(completing: Bool) async {
    await viewModel.finish(
      context: context, writer: HealthWorkoutWriter(), garmin: model.garmin.connect, completingOpenSets: completing)
    await model.refreshReminders()
  }
}

private struct SummaryGrid: View {
  let summary: WorkoutFlow.Summary

  var body: some View {
    HStack {
      cell("\(summary.minutes) min", "Dauer")
      cell("\(summary.doneSets)", "Sätze")
      cell("\(GermanFormat.number(summary.volumeKg.rounded())) kg", "Volumen")
    }
  }

  private func cell(_ value: String, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text(value).font(.title3.bold()).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 64)
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
  }
}
