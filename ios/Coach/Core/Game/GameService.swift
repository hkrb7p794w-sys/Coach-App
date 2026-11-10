import CoachCore
import Foundation
import Observation

/// Rangliste und Challenges unter Freunden (`worker/src/game.ts`). Die Werte rechnet die App mit denselben Regeln wie
/// Begleiter und Plan; der Worker begrenzt sie (Übertraining bringt keine Punkte).
@Observable
final class GameService {
  /// Zuletzt auf „Heute“ berechneter Stand (Serie, Stufe, Abzeichen), damit „Wettkampf“ ihn ohne Neuberechnung zeigt.
  struct Snapshot: Equatable {
    var streak: DailyStreak
    var summary: MotivationSummary
    var stats: GameStats
  }

  /// Eingaben für Challenges der laufenden Woche.
  struct Inputs: Equatable {
    var today: CalendarDay
    var minutesByDay: [CalendarDay: Int]
    var mealDays: Set<CalendarDay>
    var adherence: WeekAdherence
  }

  private(set) var leaderboard: [LeaderboardEntry] = []
  private(set) var challenges: [Challenge] = []
  private(set) var lastError: String?
  var snapshot: Snapshot?

  private let ai: AIClient
  private let account: AccountService
  @ObservationIgnored private var lastReported: String?

  init(ai: AIClient, account: AccountService) {
    self.ai = ai
    self.account = account
  }

  var isAvailable: Bool { account.isSignedIn }
  var challengesWon: Int { challenges.filter(\.iWon).count }
  var invitations: [Challenge] { challenges.filter { $0.status == "invited" && !$0.finished } }

  private struct Board: Decodable { let entries: [LeaderboardEntry] }
  private struct List: Decodable { let challenges: [Challenge] }
  private struct One: Decodable { let challenge: Challenge }

  func refresh() async {
    guard isAvailable else { return }
    do {
      let board = try await ai.send(path: "v1/game/leaderboard", method: "GET", auth: .session)
      leaderboard = try JSONDecoder().decode(Board.self, from: board).entries
      let list = try await ai.send(path: "v1/game/challenges", method: "GET", auth: .session)
      challenges = try JSONDecoder().decode(List.self, from: list).challenges
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// Eigenen Stand melden (nur bei Änderung) und laufende Challenges aktualisieren.
  func report(summary: MotivationSummary, streak: DailyStreak, inputs: Inputs) async {
    guard isAvailable else { return }
    let monday = PlanAdjustments.monday(of: inputs.today)
    let values = challenges.filter { $0.status == "joined" && !$0.finished }.compactMap { challenge -> (String, Int)? in
      guard let metric = challenge.kind, let week = challenge.monday, week == monday else { return nil }
      return (
        challenge.id,
        metric.value(
          monday: week, today: inputs.today, minutesByDay: inputs.minutesByDay, mealDays: inputs.mealDays,
          adherence: inputs.adherence)
      )
    }
    let key = "\(monday.iso)-\(summary.weekPoints)-\(summary.totalPoints)-\(streak.current)-\(values)"
    guard key != lastReported else { return }
    do {
      let score: [String: JSONValue] = [
        "week": .string(monday.iso), "weekPoints": .number(Double(summary.weekPoints)),
        "totalPoints": .number(Double(summary.totalPoints)), "streak": .number(Double(summary.streak)),
        "dayStreak": .number(Double(streak.current)), "level": .number(Double(summary.level)),
      ]
      _ = try await ai.send(
        path: "v1/game/score", method: "PUT", body: try JSONEncoder().encode(JSONValue.object(score)), auth: .session)
      for (id, value) in values {
        let body = try JSONEncoder().encode(["value": value])
        _ = try await ai.send(path: "v1/game/challenges/\(id)/progress", method: "PUT", body: body, auth: .session)
      }
      lastReported = key
      await refresh()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func create(metric: ChallengeMetric, week: CalendarDay, title: String, invite: [String]) async throws {
    let body: [String: JSONValue] = [
      "metric": .string(metric.rawValue), "week": .string(week.iso), "title": .string(title),
      "invite": .array(invite.map { .string($0) }),
    ]
    let data = try await ai.send(
      path: "v1/game/challenges", method: "POST", body: try JSONEncoder().encode(JSONValue.object(body)),
      auth: .session)
    let created = try JSONDecoder().decode(One.self, from: data).challenge
    challenges.insert(created, at: 0)
    lastReported = nil
  }

  func join(_ challenge: Challenge) async {
    do {
      _ = try await ai.send(
        path: "v1/game/challenges/\(challenge.id)/join", method: "POST", body: Data("{}".utf8), auth: .session)
      lastReported = nil
      await refresh()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func leave(_ challenge: Challenge) async {
    do {
      _ = try await ai.send(path: "v1/game/challenges/\(challenge.id)", method: "DELETE", auth: .session)
      challenges.removeAll { $0.id == challenge.id }
    } catch {
      lastError = error.localizedDescription
    }
  }
}
