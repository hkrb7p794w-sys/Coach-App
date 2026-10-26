import Foundation
import Testing

@testable import CoachCore

/// Vergleich mit `coach_today()` aus dem Altbestand: `Fixtures/today-cases.json` wurde mit den Original-Templates
/// (`coach_app.jinja`, `coach_plan.jinja`, `coach_days.jinja`) und der Testumgebung von `scripts/check_today.py`
/// erzeugt – alle Wochentage × Tagesampel × Erledigt-Zustände × Läufe × HF-Verteilung in fünf Phasen-Wochen.
struct TodayPlanTests {
  private struct Case: Decodable {
    struct Entry: Decodable, Equatable {
      var day: String?
      var s: String
      var t: String
      var c: String
      var d: String?
      var ok: Bool?
      var a: String?
    }

    var today: String
    var level: String
    var done: [String: Int]
    var gym: [String]
    var zones: String?
    var items: [Entry]
    var open: [Entry]
    var skip: [String]
    var week: [Entry]
    var hint: String
    var advice: String
  }

  private static let advice: [RecoveryLevel: String] = [
    .normal: "Geplante Einheit wie vorgesehen durchziehen.",
    .locker:
      "Einheit machen, aber Intensität raus: harte Intervalle durch lockeres Training ersetzen oder um ein Drittel "
      + "kürzen.",
    .pause: "Heute Ruhetag - höchstens 20-30 min sehr locker bewegen.",
  ]

  private func cases() throws -> [Case] {
    let url = try #require(Bundle.module.url(forResource: "today-cases", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
  }

  /// Die App verweist für Wettkampf-Läufe auf den Reiter Plan statt auf den Chat in Home Assistant.
  private func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "im Reiter Chat", with: "im Reiter Plan")
  }

  @Test func matchesLegacyTemplates() throws {
    let schedule = try #require(SeasonSchedule.load())
    let all = try cases()
    #expect(all.count > 2000)
    var failures: [String] = []
    for testCase in all {
      let today = try #require(CalendarDay(iso: testCase.today))
      let level = try #require(RecoveryLevel(rawValue: testCase.level))
      let zones: IntensityShare? =
        switch testCase.zones {
        case "easy": IntensityShare(seconds: [0, 97, 3, 0, 0])
        case "hard": IntensityShare(seconds: [0, 40, 40, 20, 0])
        default: nil
        }
      let plan = TodayPlan(
        schedule: schedule, config: .standard, decisions: [:], today: today, level: level,
        advice: Self.advice[level] ?? "",
        done: TodayPlan.Done(
          swim: testCase.done["swim"] ?? 0, run: testCase.done["run"] ?? 0, bike: testCase.done["bike"] ?? 0,
          strength: testCase.done["strength"] ?? 0),
        gymDays: Set(testCase.gym.compactMap(CalendarDay.init(iso:))), runZones: zones)

      func entries(_ items: [TodayPlan.Item], withDone: Bool, withChip: Bool, withDay: Bool) -> [Case.Entry] {
        items.map {
          Case.Entry(
            day: withDay ? $0.day : nil, s: $0.sport.rawValue, t: $0.title, c: normalized($0.caption),
            d: normalized($0.detail), ok: withDone ? $0.done : nil, a: withChip ? $0.chip : nil)
        }
      }
      let expectedItems = testCase.items.map { entry in
        var entry = entry
        entry.c = normalized(entry.c)
        entry.d = entry.d.map(normalized)
        return entry
      }
      let expectedOpen = testCase.open.map { entry in
        var entry = entry
        entry.c = normalized(entry.c)
        entry.d = entry.d.map(normalized)
        return entry
      }
      let label = "\(testCase.today) \(testCase.level) \(testCase.done) gym=\(testCase.gym) zones=\(testCase.zones ?? "-")"
      if entries(plan.items, withDone: true, withChip: true, withDay: false) != expectedItems {
        failures.append("items \(label)")
      }
      if entries(plan.open, withDone: false, withChip: true, withDay: false) != expectedOpen {
        failures.append("open \(label)")
      }
      if plan.skipped.map(\.title) != testCase.skip { failures.append("skip \(label)") }
      if entries(plan.rest, withDone: false, withChip: false, withDay: true) != testCase.week {
        failures.append("week \(label)")
      }
      if plan.hint != testCase.hint { failures.append("hint \(label)") }
      if plan.advice != testCase.advice { failures.append("advice \(label)") }
    }
    #expect(failures.isEmpty, "\(failures.count) Abweichungen, z. B. \(failures.prefix(5))")
  }

  /// Regeln aus `check_today.py`: am letzten Tag nie „nicht heute“, Ausfälle nur am letzten Tag, grüne Ampel ohne
  /// Hinweise, erledigte Einheiten ohne Hinweis.
  @Test func legacyConsistencyRules() throws {
    let schedule = try #require(SeasonSchedule.load())
    let monday = CalendarDay(year: 2026, month: 10, day: 12)
    for offset in 0..<7 {
      for level in [RecoveryLevel.normal, .locker, .pause] {
        let plan = TodayPlan(
          schedule: schedule, config: .standard, decisions: [:], today: monday.adding(days: offset), level: level,
          advice: "", done: TodayPlan.Done(), gymDays: [], runZones: nil)
        let chips = (plan.items + plan.open).map(\.chip).filter { !$0.isEmpty }
        if offset == 6 { #expect(!chips.contains("nicht heute")) }
        if offset < 6 { #expect(plan.skipped.isEmpty) }
        if level == .normal { #expect(chips.isEmpty && plan.skipped.isEmpty) }
        #expect(!plan.items.contains { $0.done && !$0.chip.isEmpty })
        #expect(!plan.open.contains { $0.chip == "⅓ weniger Sätze" })
        if offset == 6 { #expect(plan.rest.isEmpty) }
      }
    }
  }
}
