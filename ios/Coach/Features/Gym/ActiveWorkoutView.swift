import AVFoundation
import AudioToolbox
import CoachCore
import SwiftUI
import UserNotifications

/// Mitteilung zum Pausenende, falls die App im Hintergrund ist (wie Strong oder Hevy).
enum RestAlarm {
  static let identifier = "coach.rest"
  /// Die Einheit ist auf dem Bildschirm und gibt das Signal selbst.
  static var workoutIsOpen = false

  static func isHandledByOpenWorkout(_ id: String) -> Bool { id == identifier && workoutIsOpen }

  /// `body` nennt die nächste Übung („Weiter mit Schulterdrücken“).
  static func schedule(at end: Date?, body: String? = nil, sound: RestSound = .system) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard let end, end.timeIntervalSinceNow > 1 else { return }
    let content = UNMutableNotificationContent()
    content.title = "Pause vorbei"
    content.body = body.map { "\($0)." } ?? "Weiter mit dem nächsten Satz."
    switch sound {
    case .off: content.sound = nil
    case .system: content.sound = .default
    default: content.sound = sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
    }
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }
}

/// Ton bei geöffneter App. `ambient` folgt Stummschalter und Lautstärke und unterbricht keine laufende Musik.
enum RestSoundPlayer {
  private static var player: AVAudioPlayer?

  static func play(_ sound: RestSound) {
    guard sound != .off else { return }
    guard let name = sound.fileName, let url = Bundle.main.url(forResource: name, withExtension: nil) else {
      AudioServicesPlaySystemSound(1007)
      return
    }
    try? AVAudioSession.sharedInstance().setCategory(.ambient)
    try? AVAudioSession.sharedInstance().setActive(true)
    player = try? AVAudioPlayer(contentsOf: url)
    player?.play()
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
  @State private var showsPlanComplete = false

  var body: some View {
    NavigationStack {
      Group {
        if let session = viewModel.active {
          content(session)
        } else if let finished = viewModel.finished {
          WorkoutResultView(finished: finished, viewModel: viewModel) { dismiss() }
            .onDisappear { viewModel.dismissFinished() }
        } else {
          ContentUnavailableView("Keine laufende Einheit", systemImage: "dumbbell")
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Ausblenden", systemImage: "chevron.down") { dismiss() }
        }
        if viewModel.active != nil {
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
          }
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
      .sheet(isPresented: $showFinish) {
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
        viewModel.restFinished(end: end)
      }
      .sensoryFeedback(.impact(weight: .light), trigger: restWarnings)
      // Letzter Satz des Plans: fragen, ob beendet oder weiter trainiert wird.
      .onChange(of: viewModel.planCompleteCount) { _, _ in
        guard viewModel.active != nil, !showFinish else { return }
        showsPlanComplete = true
      }
      .sheet(isPresented: $showsPlanComplete) {
        if let session = viewModel.active {
          PlanCompleteSheet(
            session: session,
            finish: {
              showsPlanComplete = false
              Task {
                try? await Task.sleep(for: .milliseconds(450))
                showFinish = true
              }
            },
            addExercise: {
              showsPlanComplete = false
              Task {
                try? await Task.sleep(for: .milliseconds(450))
                showCatalog = true
              }
            },
            close: { showsPlanComplete = false })
        }
      }
      .sensoryFeedback(trigger: viewModel.restFinishedCount) { _, _ in
        model.settings.gym.restHaptic ? .warning : nil
      }
      .onAppear { RestAlarm.workoutIsOpen = true }
      .onDisappear { RestAlarm.workoutIsOpen = false }
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
        HoldCorrection(session: session, viewModel: viewModel)
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
            let next = WorkoutFlow.upcoming(after: .init(exercise: target.exerciseIndex, set: set), in: session),
            next.exercise == target.exerciseIndex
          {
            upcoming(next)
          }
          if let following = WorkoutFlow.nextExercise(after: target.exerciseIndex, in: session) {
            NextExercisePreview(exercise: session.exercises[following], viewModel: viewModel)
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
        .foregroundStyle(exercise.skipped ? .secondary : .primary)
      if exercise.skipped {
        Text("Übersprungen").font(.caption.bold()).foregroundStyle(.secondary)
      }
      if let set = target.set {
        HStack(spacing: 12) {
          SetKindMenu(set: exercise.sets[set], index: set, total: exercise.sets.count) { kind in
            viewModel.setKind(kind, set: set, of: exercise.id)
          }
          if exercise.skipped {
            Button("Wieder aufnehmen", systemImage: "arrow.uturn.backward") { viewModel.resume(exercise.id) }
              .font(.subheadline)
          } else {
            Button("Überspringen", systemImage: "forward.end") { viewModel.skip(exercise.id) }
              .font(.subheadline)
              .accessibilityHint("Weiter mit der nächsten Übung, offene Sätze werden nicht gespeichert")
          }
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

  /// Nächster Satz derselben Übung, klein.
  private func upcoming(_ next: WorkoutFlow.Position) -> some View {
    let set = session.exercises[next.exercise].sets[next.set]
    let values = set.weightKg != 0 ? "\(GermanFormat.number(set.weightKg)) kg × \(set.reps)" : "\(set.reps) Wdh."
    return Text("Als Nächstes: Satz \(next.set + 1) · \(values)")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
  }

  /// Plan geschafft: beenden oder fortsetzen (Übung dazu, übersprungene wieder aufnehmen).
  private var allDone: some View {
    VStack(spacing: 14) {
      Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(.yellow)
      Text("Plan geschafft").font(.title2.bold())
      Text("\(session.doneSetCount) Sätze · \(GermanFormat.number(session.volumeKg.rounded())) kg bewegt")
        .foregroundStyle(.secondary)
      let skipped = session.exercises.filter { $0.skipped && $0.sets.contains { !$0.done } }
      if !skipped.isEmpty {
        VStack(spacing: 8) {
          Text("Übersprungen").font(.subheadline.bold())
          ForEach(skipped) { exercise in
            Button("\(exercise.name) nachholen", systemImage: "arrow.uturn.backward") {
              viewModel.resume(exercise.id)
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
    .padding(.top, 30)
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
                if exercise.skipped && !complete { Image(systemName: "forward.end").foregroundStyle(.secondary) }
                if let label = labels[exercise.id] { Text(label).bold().foregroundStyle(.tint) }
                Text(exercise.name).lineLimit(1)
                Text("\(progress.done)/\(progress.total)").monospacedDigit().foregroundStyle(.secondary)
              }
              .font(.subheadline)
              .opacity(exercise.skipped && !complete ? 0.5 : 1)
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

/// Ein Eingabebereich für den Satz: Gewicht und Wiederholungen nebeneinander, je groß mit − und +. Tippen auf eine
/// Zahl öffnet den Ziffernblock für beide Werte. Jede Änderung betrifft nur diesen Satz.
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
    VStack(spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        ValueColumn(
          text: weight.value, unit: weight.unit, label: "Gewicht", value: set.weightKg,
          minus: { viewModel.setWeight(max(lowest, set.weightKg - step), set: index, of: exercise.id) },
          plus: { viewModel.setWeight(set.weightKg + step, set: index, of: exercise.id) },
          edit: { editing = SetValueTarget(exerciseID: exercise.id, set: index, field: .weight) })
        ValueColumn(
          text: "\(set.reps)", unit: ExerciseUnits.repsUnit(exercise.exerciseID, isTime: isTime),
          label: isTime ? "Sekunden" : "Wiederholungen", value: Double(set.reps),
          minus: { viewModel.setReps(set.reps - (isTime ? 5 : 1), set: index, of: exercise.id) },
          plus: { viewModel.setReps(set.reps + (isTime ? 5 : 1), set: index, of: exercise.id) },
          edit: { editing = SetValueTarget(exerciseID: exercise.id, set: index, field: .reps) })
      }
      RecentPerformances(exercise: exercise, viewModel: viewModel)
    }
    .padding(12)
    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 20))
  }
}

/// Eine Spalte des Eingabebereichs: Zahl (Tippen = Ziffernblock), darunter − und +.
private struct ValueColumn: View {
  let text: String
  let unit: String
  let label: String
  let value: Double
  let minus: () -> Void
  let plus: () -> Void
  let edit: () -> Void
  /// Wächst mit der Schriftgröße der Person (Dynamic Type).
  @ScaledMetric(relativeTo: .largeTitle) private var size = 46
  @ScaledMetric(relativeTo: .largeTitle) private var height = 92

  var body: some View {
    VStack(spacing: 8) {
      Button(action: edit) {
        VStack(spacing: 0) {
          Text(text)
            .font(.system(size: text.count > 5 ? size * 0.62 : size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
          Text(unit.isEmpty ? label : unit).font(.subheadline.bold()).foregroundStyle(.secondary).lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label): \(text) \(unit)")
      .accessibilityHint("Tippen zum Eintippen")
      HStack(spacing: 8) {
        RoundButton(systemImage: "minus", label: "\(label) verringern", action: minus)
        RoundButton(systemImage: "plus", label: "\(label) erhöhen", action: plus)
      }
    }
    .frame(maxWidth: .infinity)
    .sensoryFeedback(.selection, trigger: value)
  }
}

private struct RoundButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void
  @ScaledMetric(relativeTo: .title2) private var height = 52

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title2.bold())
        .frame(maxWidth: .infinity, minHeight: height)
        .background(.fill.tertiary, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// Die letzten Leistungen der Übung, klein unter der Eingabe: „80 kg × 10“, neueste zuerst.
private struct RecentPerformances: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    let info = model.settings.gym.exercise(exercise.exerciseID)
    let items = viewModel.recentPerformances(of: exercise.exerciseID)
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 3) {
        Text("Zuletzt").font(.caption2.bold()).foregroundStyle(.secondary)
        ForEach(items) { item in
          HStack {
            Text(item.text(isTime: info?.tracking == .time, allowsAssistance: ExerciseUnits.allowsAssistance(info)))
              .monospacedDigit()
            Spacer()
            Text(Formatters.shortDate(item.day)).foregroundStyle(.tertiary)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Letzte Leistungen")
    }
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
      // Auf der Fokus-Karte stehen die letzten Leistungen unter der Eingabe; in der Liste hier.
      if !centered, let last = viewModel.lastTime(of: exercise.exerciseID) {
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
        let level = model.settings.profile.level(for: .strength)
        let warmUp = viewModel.warmUpSteps(for: exercise, level: level)
        if !warmUp.isEmpty {
          Label(WarmUp.text(warmUp), systemImage: "flame").foregroundStyle(.primary)
          if offersWarmUp {
            Button("Aufwärmsätze einfügen", systemImage: "plus") {
              viewModel.insertWarmUp(into: exercise.id, level: level)
            }
            .buttonStyle(.bordered)
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
  @Environment(AppModel.self) private var model

  var body: some View {
    let target = FocusTarget(session: session, focus: viewModel.focusExerciseID)
    Group {
      if let target, let set = target.set,
        model.settings.gym.exercise(session.exercises[target.exerciseIndex].exerciseID)?.tracking == .time
      {
        HoldControls(exercise: session.exercises[target.exerciseIndex], set: set, viewModel: viewModel)
      } else if let target, let set = target.set {
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

// MARK: - Halteübungen

/// Stoppuhr für Plank & Co.: Start, live mitlaufende Zeit gegen das Ziel, Stopp übernimmt die Zeit und hakt ab.
private struct HoldControls: View {
  let exercise: LoggedExercise
  let set: Int
  let viewModel: GymViewModel

  var body: some View {
    let target = exercise.sets[safe: set]?.reps ?? 0
    if let hold = viewModel.hold, hold.exercise == exercise.id, hold.set == set {
      TimelineView(.periodic(from: hold.start, by: 1)) { context in
        let elapsed = max(0, Int(context.date.timeIntervalSince(hold.start)))
        VStack(spacing: 8) {
          Text(hold.start, style: .timer)
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .monospacedDigit()
          if target > 0 {
            Text(HoldTimer.targetText(elapsed: elapsed, target: target))
              .font(.subheadline.weight(.medium))
              .foregroundStyle(elapsed >= target ? Color.green : Color.secondary)
          }
          Button {
            viewModel.stopHold()
          } label: {
            Label("Stopp – Zeit übernehmen", systemImage: "stop.fill")
              .font(.title3.bold())
              .frame(maxWidth: .infinity, minHeight: 60)
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          Button("Abbrechen") { viewModel.cancelHold() }.font(.footnote)
        }
        .sensoryFeedback(.success, trigger: target > 0 && elapsed >= target)
      }
    } else {
      HStack(spacing: 10) {
        Button {
          viewModel.startHold(set: set, of: exercise.id)
        } label: {
          Label(target > 0 ? "Start · Ziel \(target) s" : "Stoppuhr starten", systemImage: "timer")
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        Button {
          viewModel.complete(set: set, of: exercise.id)
        } label: {
          Image(systemName: "checkmark").font(.title3.bold()).frame(width: 60, height: 60)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Ohne Stoppuhr erledigt (\(target) s)")
      }
    }
  }
}

/// Nach dem Stopp: gemessene Zeit korrigieren, falls zu spät oder zu früh gestoppt.
private struct HoldCorrection: View {
  let session: GymSession
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    if viewModel.hold == nil, viewModel.restEndsAt != nil || viewModel.pendingRest != nil,
      let last = viewModel.lastDone,
      let exercise = session.exercises.first(where: { $0.id == last.exercise }),
      model.settings.gym.exercise(exercise.exerciseID)?.tracking == .time,
      let seconds = exercise.sets[safe: last.set]?.reps
    {
      HStack(spacing: 8) {
        Text("Gehalten \(seconds) s").font(.subheadline.weight(.semibold)).monospacedDigit()
        Spacer(minLength: 4)
        ForEach([-5, -1, 1, 5], id: \.self) { delta in
          Button(delta > 0 ? "+\(delta)" : "−\(-delta)") { viewModel.correctHold(by: delta) }
            .accessibilityLabel("\(abs(delta)) Sekunden \(delta > 0 ? "mehr" : "weniger")")
        }
      }
      .buttonStyle(.bordered)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
      .sensoryFeedback(.selection, trigger: seconds)
    }
  }
}

// MARK: - Pause

/// Pause groß mit Fortschrittsbalken; darunter freiwillig RIR für den gerade erledigten Satz.
private struct RestPanel: View {
  let viewModel: GymViewModel
  @Environment(AppModel.self) private var model
  /// Klein gemacht: nur Restzeit und „Weiter“ – mehr Platz für Satz und Notizen. Bleibt für die nächsten Pausen.
  @AppStorage("gym.restPanelCollapsed") private var collapsed = false

  var body: some View {
    if let end = viewModel.restEndsAt, end > .now, collapsed {
      HStack(spacing: 12) {
        Image(systemName: "timer").foregroundStyle(.secondary).accessibilityHidden(true)
        Text(timerInterval: Date.now...end, countsDown: true)
          .font(.title3.bold().monospacedDigit())
        Spacer()
        Button("Weiter") { viewModel.skipRest() }.bold()
        Button {
          withAnimation { collapsed = false }
        } label: {
          Image(systemName: "chevron.up").frame(width: 32, height: 32)
        }
        .accessibilityLabel("Pause groß anzeigen")
      }
      .buttonStyle(.bordered)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: Capsule())
    } else if let end = viewModel.restEndsAt, end > .now {
      VStack(spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Label("Pause", systemImage: "timer").font(.headline)
          Button {
            withAnimation { collapsed = true }
          } label: {
            Image(systemName: "chevron.down").frame(width: 32, height: 32)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Pause klein machen")
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
        // Übersprungen: leicht ausgegraut, offene Sätze bleiben bedienbar (Wieder aufnehmen im Menü).
        .opacity(Self.dimmed(exercise, set: set) ? 0.45 : 1)
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
          .foregroundStyle(exercise.skipped ? .secondary : .primary)
        if exercise.skipped {
          Text("übersprungen").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        ExerciseMenu(exercise: exercise, session: session, viewModel: viewModel, showsFocus: true)
      }
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        if let hint = ComplaintArea.hint(
          for: ComplaintArea.loaded(
            byExercise: exercise.exerciseID, group: exercise.group, custom: model.settings.gym.customExercises,
            complaints: model.settings.mobility.complaints))
        {
          Label(hint, systemImage: "exclamationmark.bubble").font(.caption).foregroundStyle(.orange)
        }
        ExerciseNotes(exercise: exercise, viewModel: viewModel, centered: false)
      }
    }
  }

  /// Offene Sätze einer übersprungenen Übung (erledigte bleiben normal sichtbar).
  static func dimmed(_ exercise: LoggedExercise, set: LoggedSet) -> Bool {
    exercise.skipped && !set.done
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

/// Vorschau der nächsten Übung: Name, Sätze und Startwerte – mit „Überspringen“, falls sie heute ausfällt.
private struct NextExercisePreview: View {
  let exercise: LoggedExercise
  let viewModel: GymViewModel

  var body: some View {
    let open = exercise.sets.filter { !$0.done }
    let first = open.first
    let values = first.map { set in
      set.weightKg != 0 ? "\(GermanFormat.number(set.weightKg)) kg × \(set.reps)" : "\(set.reps) Wdh."
    }
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Danach").font(.caption2.bold()).foregroundStyle(.secondary)
        Text(exercise.name).font(.subheadline.bold()).lineLimit(1)
        Text("\(open.count) Sätze" + (values.map { " · \($0)" } ?? ""))
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
      Button("Überspringen", systemImage: "forward.end") { viewModel.skip(exercise.id) }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(width: 44, height: 44)
        .accessibilityLabel("\(exercise.name) überspringen")
    }
    .padding(12)
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
  }
}

/// Erscheint, sobald der letzte Satz des Plans erledigt ist: beenden oder weiter trainieren.
private struct PlanCompleteSheet: View {
  let session: GymSession
  let finish: () -> Void
  let addExercise: () -> Void
  let close: () -> Void

  var body: some View {
    let summary = WorkoutFlow.summary(of: session)
    VStack(spacing: 16) {
      Image(systemName: "flag.checkered").font(.system(size: 40)).foregroundStyle(.tint)
      Text("Plan geschafft").font(.title2.bold())
      Text("\(summary.doneSets) Sätze · \(summary.minutes) min · \(GermanFormat.number(summary.volumeKg.rounded())) kg")
        .foregroundStyle(.secondary)
        .monospacedDigit()
      if WorkoutFlow.skippedCount(session) > 0 {
        Text("\(WorkoutFlow.skippedCount(session)) Übung(en) übersprungen – beim Fortsetzen nachholbar.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Button(action: finish) {
        Label("Training beenden", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
      }
      .buttonStyle(.borderedProminent)
      Button(action: addExercise) {
        Label("Übung hinzufügen", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
      }
      .buttonStyle(.bordered)
      Button("Training fortsetzen", action: close)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonBorderShape(.roundedRectangle(radius: 14))
    .padding()
    .presentationDetents([.medium])
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
        if exercise.skipped {
          Button("Wieder aufnehmen", systemImage: "arrow.uturn.backward") { viewModel.resume(exercise.id) }
        } else if exercise.sets.contains(where: { !$0.done }) {
          Button("Überspringen", systemImage: "forward.end") { viewModel.skip(exercise.id) }
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
        Picker(selection: restBinding) {
          ForEach(RestText.options, id: \.self) { seconds in Text(RestText.format(seconds)).tag(seconds) }
        } label: {
          Label("Pause \(RestText.format(exercise.restSeconds))", systemImage: "timer")
        }
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

  /// Pause der Übung; gilt sofort und – gemerkt – auch beim nächsten Mal.
  private var restBinding: Binding<Int> {
    Binding(
      get: { RestText.options.min { abs($0 - exercise.restSeconds) < abs($1 - exercise.restSeconds) } ?? 90 },
      set: { seconds in
        if let remembered = viewModel.setRest(seconds, of: exercise.id) {
          model.settings.gym.restOverrides[remembered.exerciseID] = remembered.seconds
        }
      })
  }

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
  /// Gerade bearbeiteter Wert; der andere bleibt sichtbar und ist mit einem Tipp gewählt.
  @State private var field = SetValueTarget.Field.weight
  @State private var weightText = ""
  @State private var repsText = ""
  /// Die erste Taste ersetzt den alten Wert (statt anzuhängen) – kein versehentliches „808“ aus 80 und einer 8.
  @State private var replacesWeight = true
  @State private var replacesReps = true
  /// Unterstützung statt Zusatzgewicht (negatives Gewicht), nur bei Körpergewichtsübungen.
  @State private var assisted = false
  @State private var warning: String?

  private var exercise: LoggedExercise? {
    viewModel.active?.exercises.first { $0.id == target.exerciseID }
  }

  var body: some View {
    let gym = model.settings.gym
    let info = exercise.flatMap { gym.exercise($0.exerciseID) }
    let isTime = info?.tracking == .time
    let isWeight = field == .weight
    let step = exercise.map { ExerciseLibrary.rule($0.exerciseID, name: $0.name, custom: gym.customExercises).step }
    let deltas = Self.deltas(isWeight: isWeight, isTime: isTime, step: step ?? 2.5)
    VStack(spacing: 14) {
      Text("Satz \(target.set + 1)" + (exercise.map { " · \($0.name)" } ?? ""))
        .font(.headline)
        .lineLimit(1)
        .padding(.top)
      HStack(spacing: 10) {
        valueBox(
          .weight, text: weightText, unit: assisted ? "kg Hilfe" : "kg", label: "Gewicht", replacing: replacesWeight)
        valueBox(
          .reps, text: repsText, unit: isTime ? "s" : "Wdh.", label: isTime ? "Dauer" : "Wiederholungen",
          replacing: replacesReps)
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
            let value = max(0, (NumberPad.value(current) ?? 0) + delta)
            setCurrent(isWeight ? NumberPad.text(for: value) : value > 0 ? "\(Int(value))" : "")
          }
          .frame(maxWidth: .infinity)
        }
        if let previous = previousValue {
          Button("wie Satz \(target.set)") { setCurrent(previous) }
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
    .sensoryFeedback(.selection, trigger: weightText + "|" + repsText)
    .onAppear {
      field = target.field
      guard let set = exercise?.sets[safe: target.set] else { return }
      assisted = set.weightKg < 0
      weightText = NumberPad.text(for: abs(set.weightKg))
      repsText = set.reps > 0 ? "\(set.reps)" : ""
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

  /// Wertefeld zum Antippen; das gewählte ist hervorgehoben.
  private func valueBox(
    _ box: SetValueTarget.Field, text: String, unit: String, label: String, replacing: Bool
  ) -> some View {
    let selected = field == box
    return Button {
      field = box
    } label: {
      VStack(spacing: 2) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(text.isEmpty ? "0" : text)
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            // Wird beim ersten Tippen ersetzt: leicht markiert wie ausgewählter Text.
            .foregroundStyle(text.isEmpty || (selected && replacing) ? .secondary : .primary)
          Text(unit).font(.headline).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(
        selected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
        in: RoundedRectangle(cornerRadius: 16)
      )
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(label): \(text.isEmpty ? "0" : text) \(unit)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var current: String { field == .weight ? weightText : repsText }

  private func setCurrent(_ text: String) {
    if field == .weight {
      weightText = text
      replacesWeight = false
    } else {
      repsText = text
      replacesReps = false
    }
  }

  private static func deltas(isWeight: Bool, isTime: Bool, step: Double) -> [Double] {
    if isWeight { return [-step, step, 5, 10] }
    return isTime ? [-5, 5, 15] : [-1, 1, 2]
  }

  /// Wert des vorherigen Satzes für „wie Satz n“ (nur auf ausdrücklichen Tipp).
  private var previousValue: String? {
    guard target.set > 0, let set = exercise?.sets[safe: target.set - 1] else { return nil }
    return field == .weight ? NumberPad.text(for: abs(set.weightKg)) : "\(set.reps)"
  }

  private func key(_ title: String, _ key: NumberPad.Key, isWeight: Bool) -> some View {
    Button {
      let replacing = isWeight ? replacesWeight : replacesReps
      // Erste Ziffer ersetzt den alten Wert; Löschen nimmt beim ersten Mal den ganzen Wert weg.
      let base = replacing ? "" : current
      setCurrent(NumberPad.apply(key, to: base, allowsDecimals: isWeight))
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
    guard let exercise else { return dismiss() }
    let isTime = model.settings.gym.exercise(exercise.exerciseID)?.tracking == .time
    let best = viewModel.history(of: exercise.exerciseID).map(\.topWeightKg).max()
    let weight = NumberPad.value(weightText) ?? 0
    let reps = Int(NumberPad.value(repsText) ?? 0)
    warning =
      SetCheck.warning(weightKg: assisted ? 0 : weight, reps: 0, isTime: isTime, previousBestKg: best)
      ?? SetCheck.warning(weightKg: 0, reps: reps, isTime: isTime, previousBestKg: nil)
    if warning == nil, exercise.sets[safe: target.set] != nil { apply() }
  }

  /// Übernimmt nur Werte, die sich geändert haben – ein unberührtes Feld bleibt, wie es war.
  private func apply() {
    guard let set = exercise?.sets[safe: target.set] else { return dismiss() }
    let weight = (NumberPad.value(weightText) ?? 0) * (assisted ? -1 : 1)
    let reps = Int(NumberPad.value(repsText) ?? 0)
    let weightChanged = abs(weight - set.weightKg) >= 0.001
    let repsChanged = reps != set.reps
    if weightChanged { viewModel.setWeight(weight, set: target.set, of: target.exerciseID) }
    if repsChanged { viewModel.setReps(reps, set: target.set, of: target.exerciseID) }
    // Einstellung „Satz nach Eingabe abhaken“: abhaken und Pause starten, als hätte man „Satz erledigt“ getippt.
    if model.settings.gym.completeOnEdit.completes(afterEditingReps: repsChanged || target.field == .reps),
      !set.done
    {
      viewModel.complete(set: target.set, of: target.exerciseID)
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
          if let session = viewModel.active {
            review(session)
          } else {
            ProgressView("Speichern …").frame(maxWidth: .infinity, minHeight: 200)
          }
        }
        .padding()
      }
      .navigationTitle("Einheit beenden")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(viewModel.isSaving)
    // Gespeichert: Die Zusammenfassung erscheint in der Einheit selbst, das Blatt geht zu.
    .onChange(of: viewModel.finished != nil, initial: true) { _, saved in
      if saved { close() }
    }
  }

  private func review(_ session: GymSession) -> some View {
    let summary = WorkoutFlow.summary(of: session)
    let skipped = WorkoutFlow.skippedCount(session)
    return VStack(spacing: 16) {
      SummaryGrid(summary: summary)
      if skipped > 0 {
        Label(
          skipped == 1
            ? "1 Übung übersprungen – ihre offenen Sätze werden nicht gespeichert."
            : "\(skipped) Übungen übersprungen – ihre offenen Sätze werden nicht gespeichert.",
          systemImage: "forward.end"
        )
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
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

/// Abschluss nach dem Speichern. Steht in der Einheit selbst, damit nie ein leerer Bildschirm bleibt.
private struct WorkoutResultView: View {
  let finished: FinishedWorkout
  let viewModel: GymViewModel
  let close: () -> Void
  @State private var sharing: WorkoutShare?

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
        Text(finished.title).font(.title2.bold())
        SummaryGrid(summary: finished.summary)
        if let change = finished.volumeChange {
          Label(
            "\(abs(change)) % \(change >= 0 ? "mehr" : "weniger") Volumen als beim letzten Mal",
            systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
          )
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
        if finished.muscles.values.contains(where: { $0 > 0 }) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Beanspruchte Muskeln").font(.headline)
            BodyMapView(values: finished.muscles, full: 6)
            Text(
              finished.muscles.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(5)
                .map { "\($0.key.label) \(GermanFormat.decimal($0.value))" }.joined(separator: " · ")
                + " Sätze. Hauptmuskel zählt voll, mitarbeitende halb – eine Schätzung."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
        if let share = finished.share {
          Button {
            sharing = share
          } label: {
            Label("Mit Freunden teilen", systemImage: "person.2").frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.roundedRectangle(radius: 14))
        }
        Button {
          close()
        } label: {
          Text("Fertig").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
      }
      .padding()
    }
    .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
      if let sharing { ShareWithFriendsSheet(content: .workout(sharing)) }
    }
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
