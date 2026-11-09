import CoachCore
import Foundation
import Observation
import SwiftData

/// Trainingsplan, laufende Einheit, Progression und Wochenvolumen.
///
/// Die laufende Einheit liegt zusätzlich in den UserDefaults – beendet iOS die App im Gym, ist nichts verloren.
@Observable
final class GymViewModel {
  static let activeKey = "gym.activeSession"

  private(set) var plan = GymPlan.standard
  private(set) var today = CalendarDay(date: .now)
  /// Einheit laut Plan für heute (nil = kein Gym-Tag oder schon erledigt).
  private(set) var todayWorkout: Workout?
  private(set) var weekPlan: [(day: CalendarDay, workout: Workout, done: Bool)] = []
  private(set) var progress: [ExerciseProgress] = []
  private(set) var volume: [MuscleGroup: Int] = [:]
  private(set) var daysSinceLegs: Int?
  private(set) var recovered: Bool?
  private(set) var active: GymSession?
  /// Pausenende nach dem letzten abgehakten Satz.
  private(set) var restEndsAt: Date?
  /// Länge der laufenden Pause (für den Fortschrittsring).
  private(set) var restSeconds = 0
  /// Zuletzt abgehakter Satz – in der Pause wird dafür RIR abgefragt.
  private(set) var lastDone: (exercise: UUID, set: Int)?
  /// Übung, die die Person auf der Fokus-Karte gewählt hat (`nil` = automatisch der nächste offene Satz).
  var focusExerciseID: UUID?
  /// Rückgängig für die letzte Änderung, die etwas wegnimmt (Ent-Haken, Satz oder Übung löschen).
  private(set) var undoLabel: String?
  private var undoSession: GymSession?
  /// Ergebnis der zuletzt beendeten Einheit (Abschluss-Bildschirm).
  private(set) var finished: FinishedWorkout?
  var message: String?
  private(set) var isSaving = false
  /// KI-Hinweise zur Gewichtssteigerung (oder regelbasierter Ersatz).
  private(set) var hints: [String] = []
  private(set) var hintSource = ""
  private(set) var hintEvidence: [String] = []
  private(set) var isLoadingHints = false

  /// Zielbereiche je Übung: Saisonplan und eigene Routinen.
  private(set) var ranges: [String: ClosedRange<Int>] = [:]
  private(set) var gym = GymSettings()
  private(set) var sessions: [GymSession] = []
  private let defaults: UserDefaults

  /// Eine Einheit für App und Live-Aktivität (deren Knöpfe laufen auch ohne geöffnete Gym-Ansicht).
  static let shared = GymViewModel()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    active = defaults.data(forKey: Self.activeKey).flatMap { try? JSONDecoder().decode(GymSession.self, from: $0) }
      .map(ExerciseAliases.normalized)
    discardAbandoned()
  }

  /// Zustand der offenen Einheit: erst der erste Satz macht sie zum Training (Live-Aktivität, zählt als gemacht).
  func sessionState(now: Date = .now) -> ActiveSessionState {
    ActiveSessionState.of(active, now: now)
  }

  /// Nur geöffnet, nie ein Satz und schon alt (z. B. gestern): still verwerfen, damit sie nicht als laufend gilt.
  func discardAbandoned(now: Date = .now) {
    guard sessionState(now: now) == .abandoned else { return }
    setActive(nil)
  }

  func update(
    sessions: [GymSession], activities: [GarminActivity], days: [DailyMetrics], gym: GymSettings = GymSettings(),
    now: Date = .now
  ) {
    let today = CalendarDay(date: now)
    self.today = today
    self.sessions = sessions
    self.gym = gym
    ranges = plan.repRanges.merging(gym.routines.repRanges) { _, routine in routine }
    // Dieselbe Ampel wie unter „Heute“.
    let state = RecoveryEvaluator.today(days: days, activities: activities, today: today)
    recovered = state.level.map { $0 == .normal }

    // Erledigt: eigene Einheiten und Krafttrainings von Garmin.
    let doneDays = Set(sessions.map(\.day)).union(activities.filter { $0.sport == .strength }.compactMap(\.day))
    let monday = today.adding(days: -today.weekdayIndex)
    let planned = plan.plannedDays(monday: monday, today: today, doneDays: doneDays)
    weekPlan = planned.keys.sorted().compactMap { day in
      plan.workout(planned[day] ?? "").map { (day, $0, doneDays.contains(day)) }
    }
    todayWorkout = doneDays.contains(today) ? nil : planned[today].flatMap(plan.workout)

    progress = GymProgression.evaluate(
      sessions: sessions, ranges: ranges, custom: gym.customExercises, today: today, recovered: recovered)
    if hints.isEmpty { showFallbackHints() }
    volume = MuscleVolume.setsPerGroup(sessions: sessions, today: today)
    daysSinceLegs = MuscleVolume.daysSinceLegs(sessions: sessions, today: today)
  }

  // MARK: - Laufende Einheit

  /// Startet eine Einheit aus dem Plan, vorbefüllt mit den letzten Werten bzw. der Progression.
  func start(_ workout: Workout, now: Date = .now) {
    let exercises = workout.exercises.map { planned -> LoggedExercise in
      let rule = planned.rule
      let suggestion = prefill(for: rule.id, planned: planned)
      return LoggedExercise(
        exerciseID: rule.id, name: planned.name, group: rule.group,
        sets: (0..<max(planned.sets, 1)).map { index in
          let reps = suggestion.reps[safe: index] ?? suggestion.reps.last ?? 0
          return LoggedSet(reps: reps, weightKg: suggestion.weight, done: false)
        },
        restSeconds: gym.rest(
          for: rule.id, compound: gym.exercise(rule.id)?.compound ?? false, planned: planned.restSeconds))
    }
    setActive(GymSession(workoutKey: workout.key, title: workout.name, start: now, exercises: exercises))
  }

  /// Startet eine eigene Routine, vorbefüllt mit den letzten Werten bzw. der Progression.
  func start(_ routine: Routine, now: Date = .now) {
    var exercises = routine.items.map { item -> LoggedExercise in
      let info = gym.exercise(item.exerciseID)
      let suggestion = prefill(for: item.exerciseID, range: item.repRange, startWeight: item.weightKg)
      return LoggedExercise(
        exerciseID: item.exerciseID, name: item.name, group: info?.group ?? .other,
        sets: (0..<item.sets).map { index in
          LoggedSet(
            reps: suggestion.reps[safe: index] ?? suggestion.reps.last ?? item.upperReps,
            weightKg: suggestion.weight, done: false)
        },
        restSeconds: gym.rest(for: item.exerciseID, compound: info?.compound ?? false, planned: item.restSeconds))
    }
    // „Supersatz mit nächster Übung“ aus der Routine: Ketten bekommen eine gemeinsame Kennung.
    var group: UUID?
    for (index, item) in routine.items.enumerated() where exercises.indices.contains(index) {
      let linked = index > 0 && routine.items[index - 1].supersetWithNext
      if item.supersetWithNext || linked {
        if !linked { group = UUID() }
        exercises[index].supersetID = group
      } else {
        group = nil
      }
    }
    setActive(GymSession(workoutKey: "routine-\(routine.id)", title: routine.name, start: now, exercises: exercises))
  }

  func startEmpty(now: Date = .now) {
    setActive(GymSession(workoutKey: nil, title: "Krafttraining", start: now, exercises: []))
  }

  /// Gewicht und Wiederholungen für den nächsten Besuch: Steigerung nur, wenn die Regel es sagt und die Tagesampel
  /// nicht dagegen spricht; sonst wie beim letzten Mal; ohne Verlauf wie im Plan.
  func prefill(for exerciseID: String, planned: PlannedExercise?) -> (weight: Double, reps: [Int]) {
    let range = planned?.planRepRange ?? ranges[exerciseID] ?? gym.exercise(exerciseID)?.repRange ?? 8...12
    return prefill(
      for: exerciseID, range: range, startWeight: planned?.weightKg, plannedReps: planned?.reps)
  }

  func prefill(for exerciseID: String, range: ClosedRange<Int>, startWeight: Double?, plannedReps: Int? = nil)
    -> (weight: Double, reps: [Int])
  {
    // Mit Unterstützung (negatives Gewicht) wie beim letzten Mal; die Progression rechnet nur mit Last.
    if let last = GymStats.history(of: exerciseID, sessions: sessions).last,
      let assisted = last.sets.first(where: { $0.weightKg < 0 })
    {
      return (assisted.weightKg, last.sets.map(\.reps))
    }
    if let item = progress.first(where: { $0.exerciseID == exerciseID }) {
      switch item.status {
      case .increase where recovered != false:
        return (item.nextWeightKg ?? item.weightKg, [range.lowerBound])
      case .restart:
        return (item.nextWeightKg ?? item.weightKg, [range.lowerBound])
      default:
        return (item.weightKg, item.reps)
      }
    }
    return (startWeight ?? 0, [plannedReps ?? range.upperBound])
  }

  func addExercise(_ exercise: ExerciseInfo) {
    guard var session = active else { return }
    let suggestion = prefill(for: exercise.id, planned: nil)
    let sets = (0..<3).map { _ in
      LoggedSet(reps: suggestion.reps.last ?? exercise.upperReps, weightKg: suggestion.weight, done: false)
    }
    session.exercises.append(
      LoggedExercise(
        exerciseID: exercise.id, name: exercise.name, group: exercise.group, sets: sets,
        restSeconds: gym.rest(for: exercise.id, compound: exercise.compound)))
    setActive(session)
  }

  /// Wiederholungen in Reserve für einen Satz. Für den gerade erledigten Satz einer Grundübung mit RIR 0–1
  /// verlängert sich die laufende Pause einmal (`RestAdvisor`).
  func setRIR(_ rir: Int?, set index: Int, of exerciseID: UUID, now: Date = .now) {
    mutate(exerciseID) { exercise in
      if exercise.sets.indices.contains(index) { exercise.sets[index].rir = rir }
    }
    guard lastDone?.exercise == exerciseID, lastDone?.set == index, !restExtended, let end = restEndsAt, end > now,
      let exercise = active?.exercises.first(where: { $0.id == exerciseID })
    else { return }
    let compound = gym.exercise(exercise.exerciseID)?.compound ?? false
    let extra = RestAdvisor.seconds(base: restSeconds, compound: compound, rir: rir) - restSeconds
    guard extra > 0 else { return }
    restExtended = true
    adjustRest(by: TimeInterval(extra), now: now)
  }

  /// Pause wurde für den letzten Satz schon wegen RIR verlängert.
  private var restExtended = false

  // MARK: - Ablauf ändern (Gerät belegt, Supersatz, Aufwärmen, Satzart)

  func moveToEnd(_ exerciseID: UUID) {
    guard var session = active else { return }
    WorkoutEdits.moveToEnd(exerciseID, in: &session)
    if focusExerciseID == exerciseID { focusExerciseID = nil }
    setActive(session)
  }

  func moveExercises(fromOffsets source: IndexSet, toOffset destination: Int) {
    guard var session = active else { return }
    WorkoutEdits.move(fromOffsets: source, toOffset: destination, in: &session)
    setActive(session)
  }

  func toggleSuperset(_ exerciseID: UUID) {
    guard var session = active else { return }
    WorkoutEdits.toggleSuperset(exerciseID, in: &session)
    setActive(session)
  }

  /// Übung tauschen; das Gewicht kommt aus dem Verlauf der neuen Übung.
  func replace(_ exerciseID: UUID, with info: ExerciseInfo) {
    guard var session = active else { return }
    rememberUndo("Übung ersetzt")
    let suggestion = prefill(for: info.id, planned: nil)
    WorkoutEdits.replace(exerciseID, with: info, weightKg: suggestion.weight, in: &session)
    if focusExerciseID == exerciseID {
      focusExerciseID = session.exercises.first { $0.exerciseID == info.id && $0.sets.contains { !$0.done } }?.id
    }
    setActive(session)
  }

  /// Aufwärmvorschlag für eine Übung; berücksichtigt Niveau und ob der Muskel heute schon gearbeitet hat.
  func warmUpSteps(for exercise: LoggedExercise, level: ExperienceLevel) -> [WarmUp.Step] {
    guard gym.suggestsWarmUp, let session = active, let info = gym.exercise(exercise.exerciseID) else { return [] }
    return WarmUp.suggestion(
      for: exercise, info: info, bar: gym.bar(for: info.id), level: level,
      warmedUp: WarmUp.isWarmedUp(exercise, info: info, in: session))
  }

  func insertWarmUp(into exerciseID: UUID, level: ExperienceLevel) {
    guard var session = active, let exercise = session.exercises.first(where: { $0.id == exerciseID }) else { return }
    WorkoutEdits.insertWarmUp(warmUpSteps(for: exercise, level: level), into: exerciseID, in: &session)
    setActive(session)
  }

  func setKind(_ kind: SetKind, set index: Int, of exerciseID: UUID) {
    mutate(exerciseID) { exercise in
      if exercise.sets.indices.contains(index) { exercise.sets[index].kind = kind }
    }
  }

  /// „Letztes Mal: 60 kg × 10/10/9 (Mo, 12.10.)“.
  func lastTime(of exerciseID: String) -> String? {
    guard let point = GymStats.history(of: exerciseID, sessions: sessions).last else { return nil }
    let sets = point.sets.map { set in
      set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg))×\(set.reps)" : "\(set.reps)"
    }
    return "Letztes Mal (\(Formatters.day(point.day))): \(sets.joined(separator: ", "))"
  }

  // MARK: - KI-Hinweise

  /// Stillstand, Volumen und Häufigkeit je Muskel aus dem Verlauf (Regeln, ohne KI).
  var observations: [String] { GymCoach.observations(sessions: sessions, today: today) }

  /// Hinweise zur Gewichtssteigerung von der KI; ohne Worker bleiben die Regeln stehen.
  func loadHints(ai: AIClient, goal: FitnessGoal?, trigger: AITrigger = .user) async {
    guard ai.isConfigured, !isLoadingHints, !progress.isEmpty else { return }
    guard ai.allows("gym_hints", trigger: trigger) else {
      showFallbackHints()
      return
    }
    isLoadingHints = true
    defer { isLoadingHints = false }
    do {
      let response = try await ai.run(
        task: "gym_hints",
        input: GymHints.input(
          progress: progress, recovered: recovered, volume: volume, goal: goal, observations: observations),
        trigger: trigger)
      let points = CoachingNote.points(from: response.output)
      guard !points.isEmpty else { return }
      hints = points
      hintSource = "KI · \(response.model)"
      hintEvidence = ["gym.progression"] + CoachingNote.sources(from: response.output)
    } catch {
      showFallbackHints()
      hintSource = "Regeln (KI nicht erreichbar)"
    }
  }

  private func showFallbackHints() {
    hints = GymHints.fallback(progress, observations: observations)
    hintSource = "Regeln (ohne KI)"
    hintEvidence = ["gym.progression", "gym.rir"]
  }

  func removeExercise(_ id: UUID) {
    guard var session = active, let exercise = session.exercises.first(where: { $0.id == id }) else { return }
    rememberUndo("\(exercise.name) entfernt")
    session.exercises.removeAll { $0.id == id }
    if focusExerciseID == id { focusExerciseID = nil }
    setActive(session)
  }

  func addSet(to exerciseID: UUID) {
    mutate(exerciseID) { exercise in
      let last = exercise.sets.last ?? LoggedSet(reps: 10, weightKg: 0, done: false)
      exercise.sets.append(LoggedSet(reps: last.reps, weightKg: last.weightKg, done: false))
    }
  }

  func removeSet(_ index: Int, from exerciseID: UUID) {
    rememberUndo("Satz \(index + 1) gelöscht")
    mutate(exerciseID) { exercise in
      if exercise.sets.indices.contains(index) { exercise.sets.remove(at: index) }
    }
  }

  func setReps(_ reps: Int, set index: Int, of exerciseID: UUID) {
    mutate(exerciseID) { exercise in
      if exercise.sets.indices.contains(index) { exercise.sets[index].reps = max(0, reps) }
    }
  }

  /// Nur dieser Satz; andere Sätze behalten ihr Gewicht.
  func setWeight(_ weight: Double, set index: Int, of exerciseID: UUID) {
    guard var session = active, let exercise = session.exercises.first(where: { $0.id == exerciseID }) else {
      return
    }
    let assisted = ExerciseUnits.allowsAssistance(gym.exercise(exercise.exerciseID))
    WorkoutEdits.setWeight(weight, set: index, of: exerciseID, allowsNegative: assisted, in: &session)
    setActive(session)
  }

  /// Übung überspringen: Der Ablauf geht weiter zur nächsten; offene Sätze werden nicht gespeichert.
  func skip(_ exerciseID: UUID) {
    guard var session = active, let exercise = session.exercises.first(where: { $0.id == exerciseID }) else {
      return
    }
    rememberUndo("\(exercise.name) übersprungen")
    WorkoutEdits.setSkipped(true, exerciseID: exerciseID, in: &session)
    if focusExerciseID == exerciseID { focusExerciseID = nil }
    setActive(session)
    if WorkoutFlow.isComplete(session) { planCompleteCount += 1 }
  }

  /// Übersprungene Übung wieder aufnehmen und direkt zeigen.
  func resume(_ exerciseID: UUID) {
    guard var session = active else { return }
    WorkoutEdits.setSkipped(false, exerciseID: exerciseID, in: &session)
    focusExerciseID = exerciseID
    setActive(session)
  }

  /// Zählt hoch, sobald der letzte offene Satz des Plans erledigt (oder übersprungen) ist – die Ansicht fragt dann
  /// „Training beenden“ oder „fortsetzen“.
  private(set) var planCompleteCount = 0

  /// Die letzten Leistungen einer Übung als Orientierung unter der Eingabe (neueste zuerst).
  func recentPerformances(of exerciseID: String, limit: Int = 5) -> [GymStats.Performance] {
    GymStats.recentPerformances(of: exerciseID, sessions: sessions, limit: limit)
  }

  /// Abhaken startet die Pause; Ent-Haken lässt eine laufende Pause in Ruhe und lässt sich rückgängig machen.
  func toggleDone(set index: Int, of exerciseID: UUID, now: Date = .now) {
    guard let exercise = active?.exercises.first(where: { $0.id == exerciseID }),
      exercise.sets.indices.contains(index)
    else { return }
    if exercise.sets[index].done {
      rememberUndo("Satz \(index + 1) wieder offen")
      mutate(exerciseID) { $0.sets[index].done = false }
      if lastDone?.exercise == exerciseID, lastDone?.set == index { lastDone = nil }
    } else {
      complete(set: index, of: exerciseID, now: now)
    }
  }

  /// „Satz erledigt“: abhaken, Pause starten, Fokus bleibt bei der Übung.
  func complete(set index: Int, of exerciseID: UUID, now: Date = .now) {
    var rest: Int?
    let warmupRest = gym.restWarmup
    mutate(exerciseID) { exercise in
      guard exercise.sets.indices.contains(index), !exercise.sets[index].done else { return }
      exercise.sets[index].done = true
      // Nach Aufwärmsätzen die Aufwärmpause aus den Einstellungen, sonst die Pause der Übung.
      rest = exercise.sets[index].kind == .warmup ? warmupRest : exercise.restSeconds
    }
    guard let rest, let session = active,
      let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID })
    else { return }
    lastDone = (exerciseID, index)
    restExtended = false
    // Übung fertig: weiter mit der nächsten offenen ab hier; im Supersatz ohne Pause zur Partnerübung.
    let next = WorkoutFlow.afterCompleting(exercise: exerciseIndex, in: session)
    focusExerciseID = next.focus.map { session.exercises[$0].id }
    restSeconds = rest
    // Letzter Satz des Plans: keine Pause, sondern die Frage „beenden oder fortsetzen“.
    if WorkoutFlow.isComplete(session) {
      restEndsAt = nil
      pendingRest = nil
      RestAlarm.schedule(at: nil)
      planCompleteCount += 1
      return
    }
    // Ohne automatische Pause startet sie über „Pause starten“ (`startRest`).
    guard next.rest, gym.autoStartsRest else {
      restEndsAt = nil
      RestAlarm.schedule(at: nil)
      pendingRest = next.rest ? rest : nil
      return
    }
    pendingRest = nil
    restEndsAt = now.addingTimeInterval(TimeInterval(rest))
    RestAlarm.schedule(at: restEndsAt, body: nextText, sound: gym.restSound)
  }

  /// „Weiter mit Schulterdrücken“ bzw. „Weiter mit Satz 3 · Bankdrücken“ – für Pausenende und Sperrbildschirm.
  var nextText: String? {
    active.flatMap { WorkoutFlow.nextText(in: $0, focus: focusExerciseID, previous: lastDone?.exercise) }
  }

  // MARK: Halteübungen (Stoppuhr)

  /// Laufende Stoppuhr einer Halteübung: Satz und Startzeit.
  private(set) var hold: (exercise: UUID, set: Int, start: Date)?

  func startHold(set index: Int, of exerciseID: UUID, now: Date = .now) {
    // Eine laufende Pause endet mit dem Start des nächsten Satzes.
    restEndsAt = nil
    pendingRest = nil
    RestAlarm.schedule(at: nil)
    hold = (exerciseID, index, now)
  }

  /// Stopp: gemessene Sekunden übernehmen, Satz abhaken, Pause starten. Korrektur danach über `correctHold`.
  func stopHold(now: Date = .now) {
    guard let hold else { return }
    self.hold = nil
    setReps(HoldTimer.seconds(from: hold.start, to: now), set: hold.set, of: hold.exercise)
    complete(set: hold.set, of: hold.exercise, now: now)
  }

  func cancelHold() {
    hold = nil
  }

  /// Zuletzt gestoppte Zeit nachträglich korrigieren (zu spät gestoppt usw.).
  func correctHold(by delta: Int) {
    guard let last = lastDone,
      let seconds = active?.exercises.first(where: { $0.id == last.exercise })?.sets[safe: last.set]?.reps
    else { return }
    setReps(HoldTimer.corrected(seconds, by: delta), set: last.set, of: last.exercise)
  }

  /// Pause, die bei abgeschaltetem Automatismus auf „Pause starten“ wartet.
  private(set) var pendingRest: Int?

  func startRest(now: Date = .now) {
    guard let rest = pendingRest else { return }
    pendingRest = nil
    restEndsAt = now.addingTimeInterval(TimeInterval(rest))
    RestAlarm.schedule(at: restEndsAt, body: nextText, sound: gym.restSound)
  }

  /// Pause einer Übung für diese Einheit und – in den Einstellungen gemerkt – für das nächste Mal.
  func setRest(_ seconds: Int, of exerciseID: UUID) -> (exerciseID: String, seconds: Int)? {
    let rest = min(max(seconds, 15), RestAdvisor.maximumSeconds)
    var key: String?
    mutate(exerciseID) { exercise in
      exercise.restSeconds = rest
      key = exercise.exerciseID
    }
    return key.map { ($0, rest) }
  }

  /// Nächster offener Satz wie auf der Fokus-Karte.
  var currentPosition: WorkoutFlow.Position? {
    active.flatMap { WorkoutFlow.current(in: $0, preferring: focusExerciseID) }
  }

  /// „Satz erledigt“ aus der Live-Aktivität.
  func completeCurrent(now: Date = .now) {
    guard let position = currentPosition, let session = active else { return }
    complete(set: position.set, of: session.exercises[position.exercise].id, now: now)
  }

  /// Gewicht bzw. Wiederholungen des aktuellen Satzes ändern (Knöpfe auf dem Sperrbildschirm).
  func adjustCurrent(weightBy steps: Int = 0, repsBy reps: Int = 0) {
    guard let position = currentPosition, let session = active else { return }
    let exercise = session.exercises[position.exercise]
    let set = exercise.sets[position.set]
    if steps != 0 {
      let step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step
      setWeight(set.weightKg + Double(steps) * step, set: position.set, of: exercise.id)
    }
    if reps != 0 {
      let isTime = gym.exercise(exercise.exerciseID)?.tracking == .time
      setReps(set.reps + reps * (isTime ? 5 : 1), set: position.set, of: exercise.id)
    }
  }

  /// Inhalt der Live-Aktivität; `nil` ohne laufende Einheit.
  var liveState: WorkoutActivityAttributes.ContentState? {
    // Keine Live-Aktivität („Los“ in der Dynamic Island), solange nur geöffnet und noch kein Satz gemacht ist.
    guard let session = active, sessionState().showsLiveActivity else { return nil }
    guard let position = currentPosition else {
      return .init(
        exercise: "Plan geschafft", detail: "\(session.doneSetCount) Sätze – beenden oder fortsetzen",
        restEndsAt: restEndsAt, doneSets: session.doneSetCount, allDone: true)
    }
    let exercise = session.exercises[position.exercise]
    let set = exercise.sets[position.set]
    let info = gym.exercise(exercise.exerciseID)
    let isTime = info?.tracking == .time
    let weight = ExerciseUnits.weightText(set.weightKg, info: info)
    let reps = isTime ? "\(set.reps) s" : "\(set.reps) Wdh."
    let step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step
    // Während der Pause steht, was danach kommt („Weiter mit Schulterdrücken“).
    let heading = restEndsAt != nil ? (nextText ?? exercise.name) : exercise.name
    let following = WorkoutFlow.nextExercise(after: position.exercise, in: session).map {
      "Danach: \(session.exercises[$0].name)"
    }
    return .init(
      exercise: heading,
      detail: "Satz \(position.set + 1) von \(exercise.sets.count)",
      restEndsAt: restEndsAt, doneSets: session.doneSetCount, allDone: false,
      weight: weight.unit.isEmpty ? weight.value : "\(weight.value) \(weight.unit)",
      reps: reps, weightStep: GermanFormat.number(step), repsStep: isTime ? "5 s" : "1", next: following)
  }

  func undo() {
    guard let undoSession else { return }
    setActive(undoSession)
    clearUndo()
  }

  func clearUndo() {
    undoLabel = nil
    undoSession = nil
  }

  private func rememberUndo(_ label: String) {
    undoSession = active
    undoLabel = label
  }

  func skipRest() {
    restEndsAt = nil
    RestAlarm.schedule(at: nil)
  }

  /// Zählt hoch, wenn eine Pause im Vordergrund abläuft (Vibration).
  private(set) var restFinishedCount = 0

  /// Pause bei geöffneter Einheit abgelaufen. Das Signal kommt nur pünktlich: War die App im Hintergrund, hat dort
  /// schon die Mitteilung geklingelt, und beim Zurückkehren soll es nicht noch einmal tönen.
  func restFinished(end: Date, now: Date = .now) {
    restEndsAt = nil
    RestAlarm.schedule(at: nil)
    guard now.timeIntervalSince(end) < 2 else { return }
    restFinishedCount += 1
    RestSoundPlayer.play(gym.restSound)
  }

  /// ±15 s während der Pause: gilt für die laufende Pause, die weiteren Sätze dieser Übung und – über den
  /// Rückgabewert, den die Ansicht in den Einstellungen speichert – für das nächste Mal.
  func adjustRestAndRemember(by seconds: TimeInterval, now: Date = .now) -> (exerciseID: String, seconds: Int)? {
    adjustRest(by: seconds, now: now)
    guard let last = lastDone, var session = active,
      let index = session.exercises.firstIndex(where: { $0.id == last.exercise })
    else { return nil }
    let rest = min(max(session.exercises[index].restSeconds + Int(seconds), 15), RestAdvisor.maximumSeconds)
    session.exercises[index].restSeconds = rest
    setActive(session)
    return (session.exercises[index].exerciseID, rest)
  }

  /// Laufende Pause verlängern oder verkürzen (z. B. ±15 Sekunden).
  func adjustRest(by seconds: TimeInterval, now: Date = .now) {
    guard let end = restEndsAt else { return }
    let adjusted = end.addingTimeInterval(seconds)
    restEndsAt = adjusted > now ? adjusted : nil
    restSeconds = max(0, restSeconds + Int(seconds))
    RestAlarm.schedule(at: restEndsAt, body: nextText, sound: gym.restSound)
  }

  func cancelActive() {
    setActive(nil)
    resetFlow()
    RestAlarm.schedule(at: nil)
  }

  private func resetFlow() {
    restEndsAt = nil
    pendingRest = nil
    hold = nil
    lastDone = nil
    focusExerciseID = nil
    clearUndo()
  }

  /// Nach dem Abschluss-Bildschirm.
  func dismissFinished() {
    finished = nil
  }

  /// Speichert die Einheit lokal und – wenn möglich – in Apple Health.
  @discardableResult
  func finish(
    context: ModelContext, writer: any WorkoutSaving, garmin: GarminConnectSession? = nil,
    completingOpenSets: Bool = false, now: Date = .now
  ) async -> GymSessionRecord? {
    guard var session = active else { return nil }
    if completingOpenSets { session = WorkoutFlow.completingOpenSets(session) }
    session.exercises = session.exercises.compactMap { exercise in
      var exercise = exercise
      exercise.sets = exercise.loggedSets
      return exercise.sets.isEmpty ? nil : exercise
    }
    guard session.doneSetCount > 0 else {
      message = "Noch kein Satz abgehakt – nichts zu speichern."
      return nil
    }
    session.end = now
    // Garmin: erst die Aufzeichnung der Uhr suchen und dort die Sätze ergänzen (`GarminStrengthService`).
    // Immer vormerken, wenn der Abgleich an ist – auch ohne Anmeldung gerade jetzt. Der nächste Abruf mit
    // Garmin-Konto holt es nach (vorher ging die Einheit dann nie zu Garmin).
    let syncsGarmin = gym.uploadsToGarmin
    if syncsGarmin { session.garmin = GarminLink(status: .pending, updatedAt: now) }
    isSaving = true
    defer { isSaving = false }

    let record = GymSessionRecord(session: session)
    context.insert(record)
    do {
      try context.save()
    } catch {
      message = "Speichern fehlgeschlagen: \(error.localizedDescription)"
      return nil
    }
    let records = GymStats.newRecords(in: session, before: sessions)
    // Erst die Zusammenfassung, dann die laufende Einheit leeren: Zwischen beidem gäbe es nichts anzuzeigen, und
    // Apple Health und Garmin können Sekunden dauern.
    finished = FinishedWorkout(
      title: session.title, summary: WorkoutFlow.summary(of: session, now: now), records: records,
      status: "Gespeichert. Apple Health und Garmin werden abgeglichen …",
      exerciseIDs: session.exercises.map(\.exerciseID),
      muscles: MuscleLoad.session(session, custom: gym.customExercises),
      volumeChange: SessionComparison.volumeChangePercent(
        session, previous: SessionComparison.previous(of: session, in: sessions)),
      share: WorkoutShare.gym(session, records: records, now: now))
    setActive(nil)
    resetFlow()
    RestAlarm.schedule(at: nil)
    var status = await Self.saveToHealth(record, session: session, context: context, writer: writer)
    if syncsGarmin, let garmin, garmin.isLoggedIn,
      let garminStatus = await GarminStrengthService.reconcile(context: context, garmin: garmin, gym: gym, now: now)
    {
      status += "\n" + garminStatus
    } else if syncsGarmin {
      status += "\nGarmin: wird übertragen, sobald du mit dem Garmin-Konto angemeldet bist (Einstellungen)."
    }
    finished?.status = status
    message = records.isEmpty ? status : "🏆 " + records.joined(separator: "\n🏆 ") + "\n\n" + status
    return record
  }

  /// Überträgt die Einheit als FIT-Krafttraining (Übung, Wiederholungen, Gewicht je Satz) nach Garmin Connect.
  static func uploadToGarmin(
    _ record: GymSessionRecord, session: GymSession, context: ModelContext, garmin: GarminConnectSession
  ) async -> String {
    let fit = StrengthFitExport.fit(session)
    let name = "coach-kraft-\(session.day.iso)-\(session.id.uuidString.prefix(8)).fit"
    do {
      let created = try await garmin.upload(fit: fit, fileName: name)
      record.uploadedToGarmin = true
      try? context.save()
      return created ? "Nach Garmin Connect übertragen." : "War in Garmin Connect schon vorhanden."
    } catch let error as GarminAPIError {
      return "Garmin: \(error.message)"
    } catch {
      return "Garmin: \(error.localizedDescription)"
    }
  }

  /// Gibt eine Meldung für die Anzeige zurück.
  static func saveToHealth(
    _ record: GymSessionRecord, session: GymSession, context: ModelContext, writer: any WorkoutSaving
  ) async -> String {
    guard writer.isAvailable else { return "Gespeichert. Apple Health ist auf diesem Gerät nicht verfügbar." }
    do {
      try await writer.save(session)
      record.savedToHealth = true
      try? context.save()
      return "Gespeichert und in Apple Health eingetragen."
    } catch {
      return "Gespeichert. Apple Health: \(error.localizedDescription)"
    }
  }

  // MARK: - Hilfen

  private func mutate(_ exerciseID: UUID, _ change: (inout LoggedExercise) -> Void) {
    guard var session = active, let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      return
    }
    change(&session.exercises[index])
    setActive(session)
  }

  private func setActive(_ session: GymSession?) {
    active = session
    if let session, let data = try? JSONEncoder().encode(session) {
      defaults.set(data, forKey: Self.activeKey)
    } else {
      defaults.removeObject(forKey: Self.activeKey)
    }
  }

  /// Verlauf einer Übung je Tag (Höchstgewicht, geschätztes 1RM, Sätze).
  func history(of exerciseID: String) -> [GymStats.Point] {
    GymStats.history(of: exerciseID, sessions: sessions)
  }
}

/// Was der Abschluss-Bildschirm nach dem Speichern zeigt.
struct FinishedWorkout: Equatable {
  var title: String
  var summary: WorkoutFlow.Summary
  var records: [String]
  var status: String
  /// Für „Nächstes Mal“ (Progression nach dem Speichern).
  var exerciseIDs: [String] = []
  /// Effektive Sätze je Muskel dieser Einheit (Heatmap im Abschluss).
  var muscles: [Muscle: Double] = [:]
  /// Volumen gegenüber der letzten gleichen Einheit in %.
  var volumeChange: Int?
  /// Was „Mit Freunden teilen“ senden würde (ohne Körperwerte).
  var share: WorkoutShare?
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
