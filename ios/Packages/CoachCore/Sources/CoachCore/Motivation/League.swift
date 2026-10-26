import Foundation

/// Stand der Planerfüllung: aktuelle Woche, Punkte und Serie. Grundlage für Begleiter und Rangliste.
public struct MotivationSummary: Equatable, Sendable {
  public var week: WeekAdherence
  public var weekPoints: Int
  /// Punkte der letzten `weeks` Wochen inklusive der aktuellen.
  public var totalPoints: Int
  /// Abgeschlossene Wochen in Folge mit mindestens 80 % des Plans.
  public var streak: Int
  public var level: Int

  /// - Parameters:
  ///   - schedule: Plan der Woche, die den Tag enthält (mit Ausnahmen).
  ///   - trainingDays: Tage mit Training (Garmin-Aktivität oder Krafteinheit).
  public static func compute(
    schedule: (CalendarDay) -> WeekSchedule, trainingDays: Set<CalendarDay>, today: CalendarDay, weeks: Int = 12
  ) -> MotivationSummary {
    let monday = PlanAdjustments.monday(of: today)
    let current = WeekAdherence.compute(
      schedule: schedule(monday), trainingDays: trainingDays, weekOf: monday, today: today)
    let past = (1..<max(weeks, 1)).map { offset -> WeekAdherence in
      let start = monday.adding(days: -7 * offset)
      return WeekAdherence.compute(schedule: schedule(start), trainingDays: trainingDays, weekOf: start, today: today)
    }
    let weekPoints = ScoreRules.points(current)
    let total = past.reduce(weekPoints) { $0 + ScoreRules.points($1) }
    return MotivationSummary(
      week: current, weekPoints: weekPoints, totalPoints: total, streak: ScoreRules.streak(past),
      level: ScoreRules.level(totalPoints: total))
  }

  /// Gestern war etwas geplant und wurde nicht gemacht (nur innerhalb der Woche).
  public func missedYesterday(today: CalendarDay) -> Bool {
    let index = today.weekdayIndex
    return index > 0 && week.days[index - 1] == .missed
  }
}

/// Eintrag der Rangliste, wie ihn der Worker speichert (`worker/src/league.ts`).
public struct LeagueEntry: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var avatar: String
  public var week: String
  public var weekPoints: Int
  public var totalPoints: Int
  public var streak: Int
  public var done: Int
  public var planned: Int
  public var updatedAt: String?

  public init(
    id: String, name: String, avatar: String, week: String, weekPoints: Int, totalPoints: Int, streak: Int,
    done: Int, planned: Int, updatedAt: String? = nil
  ) {
    self.id = id
    self.name = name
    self.avatar = avatar
    self.week = week
    self.weekPoints = weekPoints
    self.totalPoints = totalPoints
    self.streak = streak
    self.done = done
    self.planned = planned
    self.updatedAt = updatedAt
  }

  public init(id: String, name: String, avatar: String, summary: MotivationSummary) {
    self.init(
      id: id, name: name, avatar: avatar, week: summary.week.monday.iso, weekPoints: summary.weekPoints,
      totalPoints: summary.totalPoints, streak: summary.streak, done: summary.week.done,
      planned: summary.week.planned)
  }
}

/// Einladung in die Rangliste: Worker-Adresse, App-Token und Ranglisten-Code als Link `coach://join?…`.
/// Wer den Link öffnet, nutzt denselben Worker – Profil, Garmin-Konto und Daten bleiben auf dem eigenen iPhone.
public struct LeagueInvite: Equatable, Sendable {
  public static let scheme = "coach"

  public var workerURL: String
  public var token: String
  public var code: String

  public init(workerURL: String, token: String, code: String) {
    self.workerURL = workerURL
    self.token = token
    self.code = code
  }

  public init?(url: URL) {
    guard url.scheme == Self.scheme, url.host() == "join",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
    let worker = value("worker")
    let code = value("league")
    guard worker.hasPrefix("https://"), LeagueCode.isValid(code) else { return nil }
    self.init(workerURL: worker, token: value("token"), code: code)
  }

  public var url: URL? {
    // Selbst kodiert: Nur unreservierte Zeichen bleiben stehen, damit „+“, „&“ und „=“ im Token sicher ankommen.
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
    return URL(
      string: "\(Self.scheme)://join?worker=\(encode(workerURL))&token=\(encode(token))&league=\(encode(code))")
  }
}

public enum LeagueCode {
  /// Gleiche Regel wie im Worker: 6–40 Zeichen, Kleinbuchstaben, Ziffern, Bindestrich.
  public static func isValid(_ code: String) -> Bool {
    (6...40).contains(code.count) && code.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
  }

  public static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
    let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
    let suffix = (0..<10).map { _ in String(alphabet[Int.random(in: 0..<alphabet.count, using: &generator)]) }
    return "team-" + suffix.joined()
  }

  public static func generate() -> String {
    var generator = SystemRandomNumberGenerator()
    return generate(using: &generator)
  }
}
