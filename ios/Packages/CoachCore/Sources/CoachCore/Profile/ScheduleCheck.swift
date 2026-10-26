import Foundation

/// Hinweis zum Wochenplan. Hinweise ohne `evidenceIDs` sind Praxisregeln und so gekennzeichnet.
public struct ScheduleHint: Equatable, Sendable, Identifiable {
  public enum Severity: Int, Comparable, Sendable {
    case info = 0
    case tip
    case warning

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Gewicht für die Bewertung von Planvorschlägen.
    var penalty: Int {
      switch self {
      case .info: 0
      case .tip: 3
      case .warning: 10
      }
    }
  }

  public let id: String
  public let severity: Severity
  public let message: String
  public let evidenceIDs: [String]

  public var isPracticeRule: Bool { evidenceIDs.isEmpty }
}

/// Prüft, ob der selbst gewählte Wochenplan zu Ziel und Erfahrung passt, und erklärt Auffälligkeiten.
public enum ScheduleCheck {
  public static func hints(schedule: WeekSchedule, profile: UserProfile) -> [ScheduleHint] {
    var hints: [ScheduleHint] = []
    func add(_ id: String, _ severity: ScheduleHint.Severity, _ message: String, _ evidence: [String] = []) {
      hints.append(ScheduleHint(id: id, severity: severity, message: message, evidenceIDs: evidence))
    }

    guard !schedule.isEmpty else {
      add("empty", .info, "Noch keine Einheiten eingetragen. Wähle, an welchen Tagen du was trainierst.")
      return hints
    }

    let level = overallLevel(profile)
    let endurance = schedule.days.flatMap { $0 }.filter { $0.sport.isEndurance }
    let hardEndurance = endurance.filter { $0.intensity == .hard }.count

    // Ruhetage und Trainingsserien.
    if schedule.restDays.isEmpty {
      add(
        "rest", .warning,
        "Du trainierst an allen sieben Tagen. Plane mindestens einen freien Tag ein, damit "
          + "sich dein Körper anpassen kann."
      )
    } else {
      let limit = level == .beginner ? 3 : 5
      if schedule.longestStreak > limit {
        add(
          "streak", .tip,
          "\(schedule.longestStreak) Trainingstage hintereinander. "
            + (level == .beginner
              ? "Zum Einstieg ist ein freier Tag nach spätestens drei Tagen besser."
              : "Ein freier oder sehr lockerer Tag dazwischen hilft der Erholung."))
      }
    }

    // Zwei fordernde Ausdauertage direkt hintereinander.
    for weekday in Weekday.allCases {
      let next = weekday.next
      if schedule.slots(on: weekday).contains(where: \.isDemandingEndurance),
        schedule.slots(on: next).contains(where: \.isDemandingEndurance)
      {
        add(
          "back-to-back-\(weekday.rawValue)", .warning,
          "\(weekday.long) und \(next.long): zwei lange oder intensive Ausdauereinheiten direkt hintereinander. "
            + "Lege einen lockeren oder freien Tag dazwischen.",
          ["intensity.distribution"])
      }
    }

    // Intensitätsverteilung.
    if endurance.count >= 3, hardEndurance * 3 > endurance.count {
      add(
        "hard-share", .tip,
        "Mehr als ein Drittel deiner Ausdauereinheiten ist intensiv. Die meisten (rund 80 %) sollten locker sein.",
        ["intensity.distribution"])
    }
    if level == .beginner, hardEndurance >= 2 {
      add(
        "beginner-hard", .tip,
        "Zum Einstieg genügt höchstens eine intensive Einheit pro Woche. Baue zuerst eine lockere Grundlage auf.")
    }

    // Gewählte Sportarten ohne Termin.
    for sport in profile.sports where schedule.count(of: sport) == 0 {
      add(
        "missing-\(sport.rawValue)", .info,
        "Du hast \(sport.label) gewählt, aber noch keinen Tag dafür "
          + "eingeplant.")
    }

    // Krafttraining.
    let strength = schedule.count(of: .strength)
    if profile.trains(.strength) {
      if profile.goal == .buildMuscle || profile.goal == .loseAndBuild || profile.goal == .gainWeight,
        strength == 1
      {
        add(
          "strength-frequency", .tip,
          "Für Muskelaufbau sind mindestens zwei Krafttage pro Woche sinnvoll: So verteilst du die Sätze je Muskel.",
          ["gym.volume"])
      }
      if profile.goal == .loseWeight, strength == 0 {
        add(
          "strength-for-loss", .tip,
          "Krafttraining nimmt kaum zusätzlich ab, hilft aber, beim Abnehmen Muskelmasse zu behalten.",
          ["weightloss.exercise"])
      }
      if strength > 4 {
        add(
          "strength-many", .info,
          "Mehr als vier Krafttage: Achte darauf, dieselben Muskeln nicht an "
            + "aufeinanderfolgenden Tagen schwer zu belasten."
        )
      }
    }

    // Schweres Krafttraining am Vortag einer langen oder intensiven Laufeinheit.
    for weekday in Weekday.allCases {
      let heavyStrength = schedule.slots(on: weekday).contains { $0.sport == .strength && $0.intensity != .easy }
      let hardRunNext = schedule.slots(on: weekday.next).contains { $0.sport == .run && $0.intensity.isDemanding }
      if heavyStrength, hardRunNext {
        add(
          "strength-before-run-\(weekday.rawValue)", .tip,
          "Schweres Krafttraining am \(weekday.long), danach am \(weekday.next.long) ein langer oder intensiver Lauf: "
            + "Die Beine sind oft noch müde. Wenn möglich, tausche die Reihenfolge.")
      }
    }

    // Wettkampfvorbereitung.
    if let event = profile.event, event.kind.isRunning, profile.trains(.run) {
      let required = (event.kind == .marathon || event.kind == .halfMarathon) ? 3 : 2
      let runs = schedule.count(of: .run)
      if runs < required {
        add(
          "event-run-days", .tip,
          "Für \(event.kind.label) sind mindestens \(required) Lauftage pro Woche sinnvoll. Aktuell: \(runs).")
      }
      let isLong = event.kind == .marathon || event.kind == .halfMarathon
      if isLong, !schedule.days.flatMap({ $0 }).contains(where: { $0.sport == .run && $0.intensity == .long }) {
        add("event-long-run", .tip, "Plane einmal pro Woche einen langen, lockeren Lauf ein.")
      }
    }

    // Fitness und Ruhepuls.
    let aimsAtEndurance = profile.goal == .improveFitness || profile.targets.restingHeartRate != nil
    if aimsAtEndurance, profile.sports.contains(where: \.isEndurance), endurance.count < 2 {
      add(
        "endurance-frequency", .tip,
        "Für bessere Fitness und einen niedrigeren Ruhepuls zählt regelmäßiges "
          + "Ausdauertraining: besser mindestens zwei Einheiten pro Woche.",
        ["rhr.endurance"])
    }
    if schedule.sessionCount < 3 {
      add(
        "who-minimum", .info,
        "Die WHO empfiehlt 150–300 Minuten moderate Bewegung pro Woche. Mit weniger als drei "
          + "Einheiten wird das knapp.",
        ["activity.who"])
    }

    return hints.sorted { $0.severity > $1.severity }
  }

  /// Bewertung eines Plans (kleiner ist besser), für den Planvorschlag.
  public static func penalty(schedule: WeekSchedule, profile: UserProfile) -> Int {
    hints(schedule: schedule, profile: profile).reduce(0) { $0 + $1.severity.penalty }
  }

  static func overallLevel(_ profile: UserProfile) -> ExperienceLevel {
    let levels = profile.sports.map { profile.level(for: $0) }
    return levels.max { UserProfile.rank($0) < UserProfile.rank($1) } ?? .beginner
  }
}
