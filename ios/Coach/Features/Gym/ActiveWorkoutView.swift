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
  @State private var restWarnings = 0

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
        // 10 Sekunden vorher kurz antippen, damit man rechtzeitig unter der Stange ist.
        if end.timeIntervalSinceNow > 10 {
          try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow - 10))
          guard !Task.isCancelled, viewModel.restEndsAt == end else { return }
          restWarnings += 1
        }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        guard !Task.isCancelled, viewModel.restEndsAt == end else { return }
        viewModel.restFinished()
      }
      .sensoryFeedback(.impact(weight: .light), trigger: restWarnings)
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
          ExerciseNotes(exercise: exercise, viewModel: viewModel, set: target.set, offersWarmUp: true)
          if let set = target.set,
            let next = WorkoutFlow.upcoming(after: .init(exercise: target.exerciseIndex, set: set), in: session)
          {
            upcoming(next)
          }
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
        ExerciseMenu(exercise: exercise, session: session, viewModel: viewModel)
      }
      if let label = WorkoutFlow.supersetLabels(in: session)[exercise.id] {
        Text("Supersatz \(label)").font(.caption.bold()).foregroundStyle(.tint)
      }
      Text(exercise.name).font(.title.bold()).multilineTextAlignment(.center)
      if let set = target.set {
        SetKindMenu(set: exercise.sets[set], index: set, total: exercise.sets.count) { kind in
          viewModel.setKind(kind, set: set, of: exercise.id)
        }
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
    let values = set.weightKg != 0 ? "\(GermanFormat.number(set.weightKg)) kg × \(set.reps)" : "\(set.reps) Wdh."
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
}

/// Übungen als Leiste mit Fortschritt; Tippen wählt die Übung für die Fokus-Karte.
private struct ExerciseStrip: View {
  let session: GymSession
  let viewModel: GymViewModel

  var body: some View {
    let shown = FocusTarget(session: session, focus: viewModel.focusExerciseID)?.exerciseIndex
    let labels = WorkoutFlow.supersetLabels(in: session)
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
                if let label = labels[exercise.id] { Text(label).bold().foregroundStyle(.tint) }
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
    let info = gym.exercise(exercise.exerciseID)
    let isTime = info?.tracking == .time
    let step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step
    let set = exercise.sets[index]
    let weight = ExerciseUnits.weightText(set.weightKg, info: info)
    // Mit Unterstützung darf das Gewicht unter 0 gehen (−20 kg = 20 kg Hilfe).
    let lowest = ExerciseUnits.allowsAssistance(info) ? -200.0 : 0
    VStack(spacing: 14) {
      ValueControl(
        text: weight.value, unit: weight.unit, label: "Gewicht", value: set.weightKg,
        minus: { viewModel.setWeight(max(lowest, set.weightKg - step), set: index, of: exercise.id) },
        plus: { viewModel.setWeight(set.weightKg + step, set: index, of: exercise.id) },
        edit: { editing = SetValueTarget(exerciseID: exercise.id, set: index, field: .weight) })
      ValueControl(
        text: "\(set.reps)", unit: ExerciseUnits.repsUnit(exercise.exerciseID, isTime: isTime),
        label: isTime ? "Sekunden" : "Wiederholungen",
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
  /// Wächst mit der Schriftgröße der Person (Dynamic Type).
  @ScaledMetric(relativeTo: .largeTitle) private var size = 52
  @ScaledMetric(relativeTo: .largeTitle) private var height = 84

  var body: some View {
    HStack(spacing: 12) {
      RoundButton(systemImage: "minus", label: "\(label) verringern", action: minus)
      Button(action: edit) {
        VStack(spacing: 0) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text)
              .font(.system(size: text.count > 6 ? size * 0.6 : size, weight: .bold, design: .rounded))
              .monospacedDigit()
              .minimumScaleFactor(0.5)
              .lineLimit(1)
            Text(unit).font(.title3.bold()).foregroundStyle(.secondary)
          }
          Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: height)
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
  @ScaledMetric(relativeTo: .title2) private var size = 60

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title2.bold())
        .frame(width: size, height: size)
        .background(.fill.tertiary, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// Notiz, letztes Mal, Progression, Aufwärmen und Scheiben – klein unter dem Satz.
private struct ExerciseNotes: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel
  /// Satz der Fokus-Karte (Scheiben für genau dieses Gewicht); `nil` = schwerster Satz.
  var set: Int?
  var offersWarmUp = false
  var centered = true
  @Environment(AppModel.self) private var model

  var body: some View {
    let gym = model.settings.gym
    let info = gym.exercise(exercise.exerciseID)
    VStack(alignment: centered ? .center : .leading, spacing: 6) {
      if let note = gym.notes[exercise.exerciseID], !note.isEmpty {
        Label(note, systemImage: "note.text").foregroundStyle(.primary)
      }
      if let last = viewModel.lastTime(of: exercise.exerciseID) {
        Text(last)
      }
      // Was die Progression für heute vorschlägt – sichtbar statt nur vorbefüllt.
      if let progress = viewModel.progress.first(where: { $0.exerciseID == exercise.exerciseID }) {
        Text(GymTarget.text(for: progress, recovered: viewModel.recovered))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
      }
      let working = exercise.sets.filter { $0.kind != .warmup }.map(\.weightKg).max() ?? 0
      let shown = set.flatMap { exercise.sets[safe: $0]?.weightKg } ?? working
      if let info {
        let bar = gym.bar(for: info.id)
        let warmUp = WarmUp.steps(working: working, equipment: info.equipment, compound: info.compound, bar: bar)
        let started = exercise.sets.contains { $0.done || $0.kind == .warmup }
        if !warmUp.isEmpty, !started {
          Text(WarmUp.text(warmUp))
          if offersWarmUp {
            Button("Aufwärmsätze einfügen", systemImage: "flame") { viewModel.insertWarmUp(into: exercise.id) }
              .buttonStyle(.bordered)
              .controlSize(.small)
          }
        }
        if info.equipment.first == .barbell,
          let plates = PlateCalculator.plates(total: shown, bar: bar, available: gym.plates)
        {
          let total = "\(GermanFormat.number(shown)) kg · Stange \(GermanFormat.number(bar)) kg"
          Text("\(total) · \(PlateCalculator.text(plates))")
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
  @Environment(AppModel.self) private var model

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
          Button("−15 s") { adjust(by: -15) }
            .accessibilityLabel("Pause 15 Sekunden kürzer")
          Button("+15 s") { adjust(by: 15) }
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

  /// Die neue Pause gilt auch für die nächsten Male dieser Übung.
  private func adjust(by seconds: TimeInterval) {
    guard let remembered = viewModel.adjustRestAndRemember(by: seconds) else { return }
    model.settings.gym.restOverrides[remembered.exerciseID] = remembered.seconds
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
        ExerciseCard(exercise: exercise, session: session, viewModel: viewModel, editing: $editing)
      }
      Section {
        Button("Übung hinzufügen", systemImage: "plus", action: addExercise)
      }
    }
  }
}

private struct ExerciseCard: View {
  let exercise: LoggedExercise
  let session: GymSession
  let viewModel: GymViewModel
  @Binding var editing: SetValueTarget?
  @Environment(AppModel.self) private var model

  var body: some View {
    let info = model.settings.gym.exercise(exercise.exerciseID)
    Section {
      ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
        SetRow(index: index, set: set, info: info, exerciseID: exercise.id, viewModel: viewModel) { field in
          editing = SetValueTarget(exerciseID: exercise.id, set: index, field: field)
        }
        .swipeActions {
          Button("Löschen", role: .destructive) { viewModel.removeSet(index, from: exercise.id) }
        }
      }
      Button("Satz hinzufügen", systemImage: "plus.circle") { viewModel.addSet(to: exercise.id) }
    } header: {
      HStack {
        if let label = WorkoutFlow.supersetLabels(in: session)[exercise.id] {
          Text(label).font(.headline).foregroundStyle(.tint)
        }
        Text(exercise.name).font(.headline)
        Spacer()
        ExerciseMenu(exercise: exercise, session: session, viewModel: viewModel, showsFocus: true)
      }
    } footer: {
      ExerciseNotes(exercise: exercise, viewModel: viewModel, centered: false)
    }
  }
}

/// Ein Satz in der Liste: Werte groß und antippbar (Ziffernblock), Abhaken mit großem Tippziel.
private struct SetRow: View {
  let index: Int
  let set: LoggedSet
  let info: ExerciseInfo?
  let exerciseID: UUID
  let viewModel: GymViewModel
  let edit: (SetValueTarget.Field) -> Void

  /// In der Liste kurz: „je Hantel“ steht auf der Fokus-Karte.
  private func shortUnit(_ unit: String) -> String {
    unit.replacingOccurrences(of: " je Hantel", with: "")
  }

  var body: some View {
    let isTime = info?.tracking == .time
    let weight = ExerciseUnits.weightText(set.weightKg, info: info)
    HStack(spacing: 12) {
      Text(set.kind.badge ?? "\(index + 1)")
        .font(.subheadline.bold())
        .foregroundStyle(set.kind == .working ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        .frame(width: 18)
        .accessibilityLabel(set.kind == .working ? "Satz \(index + 1)" : set.kind.label)
      Button {
        edit(.weight)
      } label: {
        Text(set.weightKg == 0 ? "Körpergew." : "\(weight.value) \(shortUnit(weight.unit))")
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
      let kind = Binding(get: { set.kind }, set: { viewModel.setKind($0, set: index, of: exerciseID) })
      Picker("Satzart", selection: kind) {
        ForEach(SetKind.allCases) { kind in Text(kind.label).tag(kind) }
      }
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

// MARK: - Übung anpassen

/// „Satz 2 von 4“ mit Satzart (Aufwärmen, Drop-Satz …) zum Umstellen.
private struct SetKindMenu: View {
  let set: LoggedSet
  let index: Int
  let total: Int
  let change: (SetKind) -> Void

  var body: some View {
    Menu {
      Picker("Satzart", selection: Binding(get: { set.kind }, set: change)) {
        ForEach(SetKind.allCases) { kind in Text(kind.label).tag(kind) }
      }
    } label: {
      HStack(spacing: 6) {
        Text("Satz \(index + 1) von \(total)")
        if set.kind != .working {
          Text(set.kind.label).foregroundStyle(.orange)
        }
        Image(systemName: "chevron.up.chevron.down").font(.caption)
      }
      .font(.headline)
      .foregroundStyle(.secondary)
      .frame(minHeight: 44)
    }
    .accessibilityLabel("Satz \(index + 1) von \(total), \(set.kind.label). Satzart ändern")
  }
}

/// Menü einer Übung: später, ersetzen, Supersatz, Reihenfolge, Notiz, Stange, Anleitung, entfernen.
private struct ExerciseMenu: View {
  let exercise: LoggedExercise
  let session: GymSession
  let viewModel: GymViewModel
  var showsFocus = false
  @Environment(AppModel.self) private var model
  @State private var sheet: Sheet?
  @State private var editsNote = false
  @State private var note = ""

  enum Sheet: String, Identifiable {
    case detail, replace, reorder
    var id: String { rawValue }
  }

  var body: some View {
    let gym = model.settings.gym
    let info = gym.exercise(exercise.exerciseID)
    let index = session.exercises.firstIndex { $0.id == exercise.id } ?? 0
    Menu {
      if showsFocus {
        Button("Auf der Fokus-Karte zeigen", systemImage: "scope") { viewModel.focusExerciseID = exercise.id }
      }
      Section {
        if index < session.exercises.count - 1 {
          Button("Später (Gerät belegt)", systemImage: "arrow.uturn.down") { viewModel.moveToEnd(exercise.id) }
        }
        Button("Ersetzen …", systemImage: "arrow.left.arrow.right") { sheet = .replace }
        Button("Reihenfolge ändern …", systemImage: "arrow.up.arrow.down") { sheet = .reorder }
        if exercise.supersetID != nil {
          Button("Supersatz auflösen", systemImage: "link.badge.plus") { viewModel.toggleSuperset(exercise.id) }
        } else if index < session.exercises.count - 1 {
          Button("Supersatz mit \(session.exercises[index + 1].name)", systemImage: "link") {
            viewModel.toggleSuperset(exercise.id)
          }
        }
      }
      Section {
        Button("Satz hinzufügen", systemImage: "plus.circle") { viewModel.addSet(to: exercise.id) }
        Button(gym.notes[exercise.exerciseID] == nil ? "Notiz …" : "Notiz ändern …", systemImage: "note.text") {
          note = gym.notes[exercise.exerciseID] ?? ""
          editsNote = true
        }
        if info?.equipment.first == .barbell {
          Picker("Stange", selection: barBinding) {
            ForEach(Self.bars, id: \.weight) { bar in Text(bar.label).tag(bar.weight) }
          }
        }
        Button("Anleitung und Verlauf", systemImage: "info.circle") { sheet = .detail }
      }
      Button("Übung entfernen", systemImage: "trash", role: .destructive) { viewModel.removeExercise(exercise.id) }
    } label: {
      Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
    }
    .accessibilityLabel("Optionen für \(exercise.name)")
    .sheet(item: $sheet) { sheet in
      NavigationStack {
        switch sheet {
        case .detail:
          ExerciseDetailView(exerciseID: exercise.exerciseID, viewModel: viewModel)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("Fertig") { self.sheet = nil } }
            }
        case .replace:
          ReplaceExerciseView(exercise: exercise, viewModel: viewModel) { self.sheet = nil }
        case .reorder:
          ReorderExercisesView(viewModel: viewModel) { self.sheet = nil }
        }
      }
    }
    .alert("Notiz zu \(exercise.name)", isPresented: $editsNote) {
      TextField("z. B. Sitz 4, Griff weit", text: $note)
      Button("Sichern") {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.settings.gym.notes[exercise.exerciseID] = text.isEmpty ? nil : text
      }
      Button("Abbrechen", role: .cancel) {}
    } message: {
      Text("Steht ab jetzt bei jeder Einheit unter der Übung.")
    }
  }

  static let bars: [(weight: Double, label: String)] = [
    (20, "Langhantel 20 kg"), (15, "Langhantel 15 kg"), (10, "SZ-Stange 10 kg"), (25, "Trap Bar 25 kg"),
    (7.5, "Kurze Stange 7,5 kg"),
  ]

  private var barBinding: Binding<Double> {
    Binding(
      get: { model.settings.gym.bar(for: exercise.exerciseID) },
      set: { model.settings.gym.bars[exercise.exerciseID] = $0 })
  }
}

/// Alternativen für dieselbe Muskelgruppe mit der eigenen Ausstattung.
private struct ReplaceExerciseView: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel
  let close: () -> Void
  @Environment(AppModel.self) private var model
  @State private var showsAll = false

  var body: some View {
    let gym = model.settings.gym
    let options = WorkoutEdits.alternatives(
      for: exercise.exerciseID, custom: gym.customExercises, equipment: gym.equipment)
    List {
      Section {
        ForEach(options) { option in
          Button {
            viewModel.replace(exercise.id, with: option)
            close()
          } label: {
            ExerciseLabel(exercise: option)
          }
          .buttonStyle(.plain)
        }
      } footer: {
        Text(
          exercise.sets.contains(where: \.done)
            ? "Erledigte Sätze bleiben bei \(exercise.name); die offenen übernimmt die neue Übung."
            : "Satzzahl und Wiederholungen bleiben, das Gewicht kommt aus deinem Verlauf.")
      }
      Section {
        Button("Andere Übung wählen …") { showsAll = true }
      }
    }
    .navigationTitle("\(exercise.name) ersetzen")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: close) }
    }
    .sheet(isPresented: $showsAll) {
      ExercisePickerView { option in
        viewModel.replace(exercise.id, with: option)
        showsAll = false
        close()
      }
    }
  }
}

private struct ReorderExercisesView: View {
  let viewModel: GymViewModel
  let close: () -> Void

  var body: some View {
    let exercises = viewModel.active?.exercises ?? []
    List {
      ForEach(exercises) { exercise in
        let progress = WorkoutFlow.progress(of: exercise)
        HStack {
          Text(exercise.name)
          Spacer()
          Text("\(progress.done)/\(progress.total)").monospacedDigit().foregroundStyle(.secondary)
        }
      }
      .onMove { viewModel.moveExercises(fromOffsets: $0, toOffset: $1) }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle("Reihenfolge")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: close) }
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
  /// Unterstützung statt Zusatzgewicht (negatives Gewicht), nur bei Körpergewichtsübungen.
  @State private var assisted = false
  @State private var warning: String?

  private var exercise: LoggedExercise? {
    viewModel.active?.exercises.first { $0.id == target.exerciseID }
  }

  var body: some View {
    let gym = model.settings.gym
    let isWeight = target.field == .weight
    let isTime = exercise.flatMap { gym.exercise($0.exerciseID) }?.tracking == .time
    let step = exercise.map { ExerciseLibrary.rule($0.exerciseID, name: $0.name, custom: gym.customExercises).step }
    let deltas = Self.deltas(isWeight: isWeight, isTime: isTime, step: step ?? 2.5)
    let info = exercise.flatMap { gym.exercise($0.exerciseID) }
    let unit = isWeight ? (assisted ? "kg Hilfe" : "kg") : isTime ? "s" : "Wdh."
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
      if isWeight, ExerciseUnits.allowsAssistance(info) {
        Picker("Art", selection: $assisted) {
          Text("Zusatzgewicht").tag(false)
          Text("Unterstützung").tag(true)
        }
        .pickerStyle(.segmented)
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
      assisted = set.weightKg < 0
      text = isWeight ? NumberPad.text(for: abs(set.weightKg)) : set.reps > 0 ? "\(set.reps)" : ""
    }
    .alert(
      "Wirklich?", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } }),
      presenting: warning
    ) { _ in
      Button("Übernehmen") { apply() }
      Button("Korrigieren", role: .cancel) {}
    } message: { text in
      Text(text)
    }
  }

  private static func deltas(isWeight: Bool, isTime: Bool, step: Double) -> [Double] {
    if isWeight { return [-step, step, 5, 10] }
    return isTime ? [-5, 5, 15] : [-1, 1, 2]
  }

  /// Wert des vorherigen Satzes für „wie Satz n“.
  private var previousValue: String? {
    guard target.set > 0, let set = exercise?.sets[safe: target.set - 1] else { return nil }
    return target.field == .weight ? NumberPad.text(for: abs(set.weightKg)) : "\(set.reps)"
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

  /// Unplausible Werte (625 statt 62,5 kg) erst nach Rückfrage übernehmen.
  private func save() {
    let value = NumberPad.value(text) ?? 0
    guard let exercise else { return dismiss() }
    let isTime = model.settings.gym.exercise(exercise.exerciseID)?.tracking == .time
    let best = viewModel.history(of: exercise.exerciseID).map(\.topWeightKg).max()
    let set = exercise.sets[safe: target.set]
    warning =
      target.field == .weight
      ? SetCheck.warning(weightKg: assisted ? 0 : value, reps: 0, isTime: isTime, previousBestKg: best)
      : SetCheck.warning(weightKg: 0, reps: Int(value), isTime: isTime, previousBestKg: nil)
    if warning == nil, set != nil { apply() }
  }

  private func apply() {
    let value = NumberPad.value(text) ?? 0
    switch target.field {
    case .weight: viewModel.setWeight(assisted ? -value : value, set: target.set, of: target.exerciseID)
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
      if let change = finished.volumeChange {
        Label(
          "\(abs(change)) % \(change >= 0 ? "mehr" : "weniger") Volumen als beim letzten Mal",
          systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
        .font(.subheadline)
      }
      if !finished.records.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Bestleistungen").font(.headline)
          ForEach(finished.records, id: \.self) { record in
            Label(record, systemImage: "trophy.fill").foregroundStyle(.primary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      NextTimeList(exerciseIDs: finished.exerciseIDs, viewModel: viewModel)
      if !viewModel.hints.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Hinweise").font(.headline)
          ForEach(viewModel.hints, id: \.self) { hint in
            Text("• \(hint)").font(.subheadline)
          }
          Text(viewModel.hintSource).font(.caption).foregroundStyle(.secondary)
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

/// „Nächstes Mal“ je Übung: die Entscheidung der Progression, sobald die neue Einheit eingerechnet ist.
private struct NextTimeList: View {
  let exerciseIDs: [String]
  let viewModel: GymViewModel

  var body: some View {
    let items = exerciseIDs.compactMap { id in viewModel.progress.first { $0.exerciseID == id } }
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Nächstes Mal").font(.headline)
        ForEach(items) { item in
          VStack(alignment: .leading, spacing: 2) {
            Text(item.name).font(.subheadline.bold())
            Text(item.headline).font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
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
