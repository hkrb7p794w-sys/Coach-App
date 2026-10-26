import Foundation

/// Schlägt einen Wochenplan vor: Wie viele Einheiten je Sportart zum Ziel passen und auf welche der verfügbaren
/// Tage sie sich am besten verteilen. Alles ist ein Vorschlag, den man in der App frei ändern kann.
public enum SchedulePlanner {
  /// Gewünschte Anzahl Einheiten je Sportart aus Ziel, Wettkampf und Erfahrung (vor dem Kürzen auf die Tage).
  public static func wantedCounts(profile: UserProfile) -> [TrainingSport: Int] {
    var wanted: [TrainingSport: Int] = [:]
    let level = ScheduleCheck.overallLevel(profile)
    func want(_ sport: TrainingSport, _ count: Int) {
      if profile.trains(sport) { wanted[sport] = count }
    }

    switch profile.goal {
    case .loseWeight:
      want(.strength, 2)
      want(.run, 3)
      want(.bike, 2)
      want(.swim, 2)
    case .loseAndBuild:
      want(.strength, 3)
      want(.run, 2)
      want(.bike, 1)
      want(.swim, 1)
    case .buildMuscle:
      want(.strength, level == .beginner ? 3 : 4)
      want(.run, 1)
      want(.bike, 1)
      want(.swim, 1)
    case .gainWeight:
      want(.strength, 3)
      want(.run, 1)
      want(.bike, 1)
      want(.swim, 1)
    case .improveFitness:
      want(.run, 3)
      want(.bike, 2)
      want(.swim, 2)
      want(.strength, 2)
    case .maintain:
      want(.run, 2)
      want(.bike, 1)
      want(.swim, 1)
      want(.strength, 2)
    }
    want(.other, 1)

    if let event = profile.event {
      switch event.kind {
      case .marathon: want(.run, level == .beginner ? 3 : 4)
      case .halfMarathon, .run10k: want(.run, 3)
      case .run5k: want(.run, level == .beginner ? 2 : 3)
      case .triathlon:
        want(.swim, 2)
        want(.bike, 2)
        want(.run, 2)
      case .other: break
      }
      if profile.trains(.strength) { wanted[.strength] = min(wanted[.strength] ?? 2, 2) }
    }

    // Einsteiger:innen starten mit weniger Einheiten je Sportart.
    if level == .beginner {
      for sport in TrainingSport.allCases where sport.isEndurance {
        if let count = wanted[sport] { wanted[sport] = min(count, 3) }
      }
    }
    return wanted
  }

  /// Sportarten in der Reihenfolge ihrer Wichtigkeit für das Ziel (zuerst kürzen, was hinten steht).
  static func priority(profile: UserProfile) -> [TrainingSport] {
    if let event = profile.event {
      switch event.kind {
      case .triathlon: return [.run, .bike, .swim, .strength, .other]
      case .marathon, .halfMarathon, .run10k, .run5k: return [.run, .strength, .bike, .swim, .other]
      case .other: break
      }
    }
    switch profile.goal {
    case .buildMuscle, .gainWeight, .loseAndBuild: return [.strength, .run, .bike, .swim, .other]
    case .loseWeight, .improveFitness, .maintain: return [.run, .strength, .bike, .swim, .other]
    }
  }

  /// Höchstens so viele Einheiten pro Woche, dass mindestens ein Tag frei bleibt.
  public static let maxSessionsPerWeek = 6

  /// Untergrenze je Sportart beim Kürzen: Kernsportarten eines Wettkampfs bleiben möglichst erhalten.
  static func minimumCount(for sport: TrainingSport, profile: UserProfile) -> Int {
    guard let event = profile.event else { return 1 }
    switch event.kind {
    case .triathlon: return sport.isEndurance ? 2 : 1
    case .marathon, .halfMarathon: return sport == .run ? 3 : 1
    case .run10k, .run5k: return sport == .run ? 2 : 1
    case .other: return 1
    }
  }

  /// Einheiten mit Intensität für `dayCount` verfügbare Tage.
  public static func sessions(profile: UserProfile, dayCount: Int) -> [SessionSlot] {
    var counts = wantedCounts(profile: profile)
    let order = priority(profile: profile)
    let capacity = min(dayCount, maxSessionsPerWeek)
    func total() -> Int { counts.values.reduce(0, +) }

    // Kürzen: zuerst bei der unwichtigsten Sportart, die über ihrer Untergrenze liegt; sonst fällt die
    // unwichtigste Sportart weg.
    while total() > capacity {
      let ascending = order.reversed()
      if let sport = ascending.first(where: { (counts[$0] ?? 0) > minimumCount(for: $0, profile: profile) }) {
        counts[sport, default: 0] -= 1
      } else if let sport = ascending.first(where: { (counts[$0] ?? 0) > 0 }) {
        counts[sport] = nil
      } else {
        break
      }
    }

    let level = ScheduleCheck.overallLevel(profile)
    let needsLongRun = profile.event.map { $0.kind == .marathon || $0.kind == .halfMarathon } ?? false
    var result: [SessionSlot] = []
    for sport in order {
      let count = counts[sport] ?? 0
      guard count > 0 else { continue }
      if sport.isEndurance {
        let intensities = enduranceIntensities(
          count: count, level: sport == .run ? level : profile.level(for: sport),
          longRun: needsLongRun && sport == .run)
        result += intensities.map { SessionSlot(sport, $0) }
      } else if sport == .strength {
        result += [SessionSlot](repeating: SessionSlot(.strength, .hard), count: count)
      } else {
        result += [SessionSlot](repeating: SessionSlot(sport, .easy), count: count)
      }
    }
    return result
  }

  /// Intensitäten für `count` Einheiten einer Ausdauersportart: überwiegend locker, höchstens eine intensive,
  /// eine lange. Einsteiger:innen laufen locker; eine lange Einheit nur, wenn der Wettkampf sie braucht.
  static func enduranceIntensities(count: Int, level: ExperienceLevel, longRun: Bool) -> [SessionIntensity] {
    switch (count, level) {
    case (1, _): return [.easy]
    case (2, .beginner): return longRun ? [.easy, .long] : [.easy, .easy]
    case (2, _): return [.easy, .long]
    case (3, .beginner): return longRun ? [.easy, .easy, .long] : [.easy, .easy, .easy]
    case (3, _): return [.easy, .hard, .long]
    case (_, .beginner): return padded([.easy, .easy, .easy, .long], to: count)
    default: return padded([.easy, .hard, .easy, .long], to: count)
    }
  }

  /// Füllt eine Liste mit lockeren Einheiten auf `count` auf.
  static func padded(_ base: [SessionIntensity], to count: Int) -> [SessionIntensity] {
    base + [SessionIntensity](repeating: .easy, count: max(0, count - base.count))
  }

  /// Verteilt die Einheiten so auf die verfügbaren Tage, dass die Regeln der Wochenprüfung möglichst wenig
  /// verletzt werden. Bei Gleichstand gewinnt die erste Möglichkeit (deterministisch).
  public static func suggest(profile: UserProfile, availableDays: [Weekday]) -> WeekSchedule {
    let days = Array(Set(availableDays)).sorted { $0.rawValue < $1.rawValue }
    let sessions = self.sessions(profile: profile, dayCount: days.count)
    guard !sessions.isEmpty, !days.isEmpty else { return WeekSchedule() }

    var best = WeekSchedule()
    var bestScore = Int.max
    var used = [Bool](repeating: false, count: days.count)
    var assignment = [Int](repeating: 0, count: sessions.count)

    func evaluate() {
      var schedule = WeekSchedule()
      for (sessionIndex, dayIndex) in assignment.enumerated() {
        let weekday = days[dayIndex]
        schedule.set(schedule.slots(on: weekday) + [sessions[sessionIndex]], on: weekday)
      }
      let score = ScheduleCheck.penalty(schedule: schedule, profile: profile) + preferencePenalty(schedule)
      if score < bestScore {
        bestScore = score
        best = schedule
      }
    }

    func place(_ sessionIndex: Int) {
      if sessionIndex == sessions.count {
        evaluate()
        return
      }
      for dayIndex in days.indices where !used[dayIndex] {
        used[dayIndex] = true
        assignment[sessionIndex] = dayIndex
        place(sessionIndex + 1)
        used[dayIndex] = false
      }
    }
    place(0)
    return best
  }

  /// Weiche Vorlieben: lange Einheiten am Wochenende, gleiche Sportart nicht an zwei Tagen hintereinander.
  static func preferencePenalty(_ schedule: WeekSchedule) -> Int {
    var penalty = 0
    for weekday in Weekday.allCases {
      let slots = schedule.slots(on: weekday)
      if slots.contains(where: { $0.intensity == .long }), weekday != .saturday, weekday != .sunday { penalty += 1 }
      for sport in TrainingSport.allCases where sport != .other {
        let today = slots.contains { $0.sport == sport }
        let tomorrow = schedule.slots(on: weekday.next).contains { $0.sport == sport }
        if today, tomorrow { penalty += 1 }
      }
    }
    return penalty
  }
}
