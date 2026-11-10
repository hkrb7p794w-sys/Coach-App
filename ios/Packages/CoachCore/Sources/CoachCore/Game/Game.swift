import Foundation

/// Tages-Serie: Tage in Folge mit etwas Erfasstem (Training oder Mahlzeit). Ein Joker je Woche überbrückt einen
/// fehlenden Tag, damit ein Ruhetag oder ein voller Tag die Serie nicht gleich beendet – Pausen sollen sich nicht wie
/// Versagen anfühlen. Heute zählt erst, wenn etwas erfasst ist; bis dahin läuft die Serie von gestern weiter.
public struct DailyStreak: Equatable, Sendable {
  public var current: Int
  public var best: Int
  /// Mit Joker überbrückte Tage der laufenden Serie.
  public var jokerDays: [CalendarDay]
  /// Ist heute schon etwas erfasst?
  public var activeToday: Bool

  public static let jokersPerWeek = 1

  /// `jokers`: fehlende Tage, die je Woche überbrückt werden; 0 zählt nur lückenlose Tage.
  public static func compute(
    activeDays: Set<CalendarDay>, today: CalendarDay, lookback: Int = 400, jokers: Int = jokersPerWeek
  ) -> DailyStreak {
    let activeToday = activeDays.contains(today)
    let current = run(
      from: activeToday ? today : today.adding(days: -1), activeDays: activeDays, limit: lookback, jokers: jokers)
    // Beste Serie: jede Serie, die an einem aktiven Tag endet (vorwärts betrachtet).
    var best = current.length
    let sorted = activeDays.filter { $0 <= today && $0 >= today.adding(days: -lookback) }.sorted()
    for day in sorted where !activeDays.contains(day.adding(days: 1)) {
      best = max(best, run(from: day, activeDays: activeDays, limit: lookback, jokers: jokers).length)
    }
    return DailyStreak(current: current.length, best: best, jokerDays: current.jokers, activeToday: activeToday)
  }

  /// Rückwärts ab `start`: aktive Tage zählen, je Woche (Montag bis Sonntag) ein fehlender Tag per Joker.
  /// Ein Joker gilt nur zwischen zwei aktiven Tagen; die Serie beginnt und endet mit einem aktiven Tag.
  private static func run(from start: CalendarDay, activeDays: Set<CalendarDay>, limit: Int, jokers allowed: Int) -> (
    length: Int, jokers: [CalendarDay]
  ) {
    var day = start
    var length = 0
    var jokers: [CalendarDay] = []
    var usedInWeek: [CalendarDay: Int] = [:]
    var steps = 0
    while steps < limit {
      steps += 1
      if activeDays.contains(day) {
        length += 1
      } else {
        let monday = PlanAdjustments.monday(of: day)
        let used = usedInWeek[monday, default: 0]
        guard length > 0, used < allowed, activeDays.contains(day.adding(days: -1)) else { break }
        usedInWeek[monday] = used + 1
        jokers.append(day)
        length += 1
      }
      day = day.adding(days: -1)
    }
    return (length, jokers)
  }
}

/// Was für Abzeichen zählt (alles auf dem Gerät berechnet).
public struct GameStats: Equatable, Sendable {
  public var workouts = 0
  public var bestDayStreak = 0
  /// Abgeschlossene Wochen in Folge mit mindestens 80 % des Plans (`ScoreRules.streak`).
  public var planWeekStreak = 0
  public var mealDays = 0
  public var friends = 0
  public var challengesWon = 0
  public var level = 0

  public init() {}
}

/// Abzeichen für Beständigkeit, nicht für Menge: kein Abzeichen für mehr Training als geplant, für Kaloriendefizit
/// oder Gewichtsverlust (Schutzgrenzen aus `GoalRules` bleiben unberührt).
public struct Badge: Equatable, Sendable, Identifiable {
  public enum Metric: Sendable {
    case workouts, dayStreak, planWeeks, mealDays, friends, challengesWon, level
  }

  public var id: String
  public var title: String
  public var detail: String
  public var symbol: String
  public var target: Int
  public var metric: Metric

  public func value(_ stats: GameStats) -> Int {
    switch metric {
    case .workouts: stats.workouts
    case .dayStreak: stats.bestDayStreak
    case .planWeeks: stats.planWeekStreak
    case .mealDays: stats.mealDays
    case .friends: stats.friends
    case .challengesWon: stats.challengesWon
    case .level: stats.level
    }
  }

  public func progress(_ stats: GameStats) -> Int { min(value(stats), target) }
  public func isEarned(_ stats: GameStats) -> Bool { value(stats) >= target }
}

public enum BadgeRules {
  private static func badge(
    _ id: String, _ title: String, _ detail: String, _ symbol: String, _ target: Int, _ metric: Badge.Metric
  ) -> Badge {
    Badge(id: id, title: title, detail: detail, symbol: symbol, target: target, metric: metric)
  }

  public static let all: [Badge] = [
    badge("workout.1", "Los geht’s", "Erstes Training erfasst", "figure.run", 1, .workouts),
    badge("workout.10", "Dranbleiber", "10 Trainings", "flame", 10, .workouts),
    badge("workout.50", "Gewohnheit", "50 Trainings", "flame.fill", 50, .workouts),
    badge("workout.100", "Hundert", "100 Trainings", "medal.fill", 100, .workouts),
    badge("streak.7", "Eine Woche", "7 Tage in Folge etwas erfasst", "calendar", 7, .dayStreak),
    badge("streak.30", "Ein Monat", "30 Tage in Folge", "calendar.badge.checkmark", 30, .dayStreak),
    badge("streak.100", "Hundert Tage", "100 Tage in Folge", "star.circle.fill", 100, .dayStreak),
    badge("plan.1", "Plan erfüllt", "Eine Woche mit mindestens 80 % des Plans", "checkmark.seal", 1, .planWeeks),
    badge("plan.4", "Vier Wochen stark", "4 Wochen in Folge nach Plan", "checkmark.seal.fill", 4, .planWeeks),
    badge("plan.12", "Ein Block", "12 Wochen in Folge nach Plan", "rosette", 12, .planWeeks),
    badge("meals.7", "Tagebuch", "An 7 Tagen Essen erfasst", "fork.knife", 7, .mealDays),
    badge("meals.30", "Ernährungsprofi", "An 30 Tagen Essen erfasst", "fork.knife.circle.fill", 30, .mealDays),
    badge("friends.1", "Gemeinsam", "Erste Freundschaft", "person.2", 1, .friends),
    badge("friends.5", "Team", "5 Freunde", "person.3.fill", 5, .friends),
    badge("challenge.1", "Gewonnen!", "Erste Challenge gewonnen", "trophy", 1, .challengesWon),
    badge("challenge.5", "Seriensieger", "5 Challenges gewonnen", "trophy.fill", 5, .challengesWon),
    badge("level.5", "Stufe 5", "Stufe 5 erreicht", "5.circle.fill", 5, .level),
    badge("level.10", "Stufe 10", "Stufe 10 erreicht", "10.circle.fill", 10, .level),
  ]

  public static func earned(_ stats: GameStats) -> [Badge] { all.filter { $0.isEarned(stats) } }

  /// Das nächste erreichbare Abzeichen: das mit dem größten Anteil am Ziel, das noch fehlt.
  public static func next(_ stats: GameStats) -> Badge? {
    all.filter { !$0.isEarned(stats) }
      .max { Double($0.progress(stats)) / Double($0.target) < Double($1.progress(stats)) / Double($1.target) }
  }
}

/// Stufe aus den Punkten der Planerfüllung (`ScoreRules.level`, alle 100 Punkte eine Stufe).
public enum GameLevel {
  public static func progress(totalPoints: Int) -> (level: Int, inLevel: Int, perLevel: Int) {
    let level = ScoreRules.level(totalPoints: totalPoints)
    return (level, max(totalPoints, 0) % 100, 100)
  }
}

/// Messgrößen der Challenges, gleich wie im Worker (`METRICS` in game.ts). Immer eine Kalenderwoche.
public enum ChallengeMetric: String, CaseIterable, Codable, Sendable, Identifiable {
  case plan, sessions, minutes, meals

  public var id: Self { self }

  public var title: String {
    switch self {
    case .plan: "Plan erfüllt"
    case .sessions: "Trainingstage"
    case .minutes: "Trainingsminuten"
    case .meals: "Tage mit Ernährungstagebuch"
    }
  }

  public var unit: String {
    switch self {
    case .plan: "%"
    case .sessions, .meals: "Tage"
    case .minutes: "min"
    }
  }

  /// Warum diese Grenze: Mehr als geplant bringt keine Punkte.
  public var rule: String {
    switch self {
    case .plan: "Anteil deines eigenen Plans – wer wenig plant, kann genauso gewinnen."
    case .sessions: "Höchstens ein Trainingstag pro Tag zählt."
    case .minutes: "Höchstens 90 Minuten am Tag zählen – Übertraining bringt nichts."
    case .meals: "Ein Tag zählt, sobald eine Mahlzeit erfasst ist."
    }
  }

  public var max: Int {
    switch self {
    case .plan: 100
    case .sessions, .meals: 7
    case .minutes: 7 * 90
    }
  }

  /// Wert für die Woche ab `monday` (bis einschließlich `today`).
  public func value(
    monday: CalendarDay, today: CalendarDay, minutesByDay: [CalendarDay: Int], mealDays: Set<CalendarDay>,
    adherence: WeekAdherence?
  ) -> Int {
    let days = (0..<7).map { monday.adding(days: $0) }.filter { $0 <= today }
    switch self {
    case .plan:
      guard let adherence, adherence.planned > 0 else { return 0 }
      return Swift.min(100, Int((Double(adherence.done) / Double(adherence.planned) * 100).rounded()))
    case .sessions:
      return days.filter { (minutesByDay[$0] ?? 0) > 0 }.count
    case .minutes:
      return days.reduce(0) { $0 + Swift.min(minutesByDay[$1] ?? 0, 90) }
    case .meals:
      return days.filter(mealDays.contains).count
    }
  }
}

/// Eintrag der Freundes-Rangliste (`GET /v1/game/leaderboard`).
public struct LeaderboardEntry: Codable, Equatable, Sendable, Identifiable {
  public var rank: Int
  public var username: String
  public var displayName: String
  public var me: Bool
  public var weekPoints: Int
  public var totalPoints: Int
  public var streak: Int
  public var dayStreak: Int
  public var level: Int
  public var reported: Bool
  public var id: String { username }
}

public struct Challenge: Codable, Equatable, Sendable, Identifiable {
  public struct Member: Codable, Equatable, Sendable, Identifiable {
    public var username: String
    public var displayName: String
    public var status: String
    public var progress: Double
    public var me: Bool
    public var winner: Bool
    public var id: String { username }
  }

  public var id: String
  public var title: String
  public var metric: String
  public var metricTitle: String
  public var max: Int
  public var week: String
  public var finished: Bool
  /// `joined`, `invited` oder `none`.
  public var status: String
  public var mineCreated: Bool
  public var members: [Member]

  public var kind: ChallengeMetric? { ChallengeMetric(rawValue: metric) }
  public var monday: CalendarDay? { CalendarDay(iso: week) }
  public var joined: [Member] { members.filter { $0.status == "joined" } }
  public var iWon: Bool { finished && members.contains { $0.me && $0.winner } }
}
