import Foundation
import Testing

@testable import CoachCore

struct InsightsTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func insight(
    _ topic: InsightTopic = .recovery, subject: String = "schlaf", title: String = "Schlaf nachholen",
    text: String = "Mehr schlafen.", direction: InsightDirection = .more, origin: InsightOrigin = .rules,
    days: Double = 3
  ) -> Insight {
    Insight(
      topic: topic, subject: subject, title: title, text: text, direction: direction, origin: origin,
      created: now, validUntil: now.addingTimeInterval(days * 86_400), basis: ["Fakt"])
  }

  @Test func keepsStatusUnlessContentChanges() {
    var inbox = InsightInbox.merge([], with: [insight()], now: now)
    inbox = InsightInbox.setStatus(.read, id: inbox[0].id, in: inbox, now: now)
    // Gleicher Inhalt: bleibt gelesen.
    inbox = InsightInbox.merge(inbox, with: [insight()], now: now.addingTimeInterval(60))
    #expect(inbox.count == 1)
    #expect(inbox[0].status == .read)
    // Neuer Inhalt: wieder neu.
    inbox = InsightInbox.merge(inbox, with: [insight(text: "Heute früher ins Bett.")], now: now)
    #expect(inbox[0].status == .new)
    // Verworfen bleibt verworfen, solange die Richtung gleich ist.
    inbox = InsightInbox.setStatus(.dismissed, id: inbox[0].id, in: inbox, now: now)
    inbox = InsightInbox.merge(inbox, with: [insight(text: "Noch ein Text.")], now: now)
    #expect(inbox[0].status == .dismissed)
  }

  @Test func rulesBeatContradictingAI() {
    let rule = insight(subject: "intensitaet", title: "Heute locker", direction: .less)
    let ai = insight(.training, subject: "intensitaet", title: "Heute Intervalle", direction: .more, origin: .ai)
    var inbox = InsightInbox.merge([], with: [rule], now: now)
    inbox = InsightInbox.merge(inbox, with: [ai], now: now)
    #expect(inbox.map(\.title) == ["Heute locker"])
    // Umgekehrt ersetzt die Regel die KI.
    inbox = InsightInbox.merge([], with: [ai], now: now)
    inbox = InsightInbox.merge(inbox, with: [rule], now: now)
    #expect(inbox.map(\.title) == ["Heute locker"])
    // KI unter gleicher ID wie eine gültige Regel: Regel bleibt.
    let sameID = insight(text: "KI-Text", origin: .ai)
    inbox = InsightInbox.merge([insight()], with: [sameID], now: now)
    #expect(inbox[0].origin == .rules)
  }

  @Test func dropsDuplicateTitlesAndExpired() {
    let first = insight(subject: "protein", title: "Mehr Protein")
    let duplicate = insight(.nutrition, subject: "eiweiss", title: "Mehr Protein", origin: .ai)
    let expired = insight(subject: "alt", title: "Alt", days: -1)
    let inbox = InsightInbox.merge([], with: [first, duplicate, expired], now: now)
    #expect(inbox.count == 1)
  }

  @Test func groupsAndRetiresRules() {
    var inbox = InsightInbox.merge(
      [], with: [insight(), insight(subject: "protein", title: "Mehr Protein", days: 5)], now: now)
    inbox = InsightInbox.setStatus(.done, id: "erholung.protein", in: inbox, now: now)
    #expect(InsightInbox.unreadCount(inbox, now: now) == 1)
    var groups = InsightInbox.groups(inbox, now: now)
    #expect(groups.new.count == 1)
    #expect(groups.closed.count == 1)
    // Regel trifft nicht mehr zu → nicht mehr aktuell.
    inbox = InsightInbox.retireRules(inbox, keeping: [], now: now)
    groups = InsightInbox.groups(inbox, now: now.addingTimeInterval(1))
    #expect(groups.expired.count == 1)
    // Nach 30 Tagen fallen erledigte, nach 14 Tagen abgelaufene weg.
    #expect(InsightInbox.merge(inbox, with: [], now: now.addingTimeInterval(31 * 86_400)).isEmpty)
  }

  @Test func rulesProduceInsightsFromExistingChecks() {
    let recommendation = Recommendation(level: .locker, reasons: ["Ruhepuls deutlich über dem Schnitt"])
    let insights = InsightRules.build(
      InsightRules.Input(
        now: now, recommendation: recommendation,
        gymObservations: [
          "Bankdrücken: seit drei Einheiten 80 kg ohne mehr Wiederholungen – Stillstand. Variante ändern.",
          "Beine: 4 Sätze in 7 Tagen – unter 10. Für mehr Zuwachs Sätze ergänzen.",
        ],
        nutritionGaps: ["Protein: im Schnitt 90 von 140 g (64 %)"]))
    #expect(insights.map(\.topic) == [.recovery, .stagnation, .training, .nutrition])
    #expect(insights[1].subject == "bankdruecken")
    #expect(insights[1].direction == .change)
    #expect(insights[2].direction == .more)
    #expect(insights[3].text.hasPrefix("Du kommst im Schnitt 90 von 140 g"))
    // Normale Erholung erzeugt nichts.
    let normal = InsightRules.build(
      InsightRules.Input(now: now, recommendation: Recommendation(level: .normal, reasons: [])))
    #expect(normal.isEmpty)
  }

  @Test func readsGroundedAIAnswer() {
    let facts = InsightAnalysis.facts(["Ruhepuls heute 64, Schnitt 58", ""])
    #expect(facts.map(\.id) == ["f1"])
    let output: JSONValue = .object([
      "empfehlungen": .array([
        .object([
          "thema": .string("erholung"), "betreff": .string("Ruhepuls"), "titel": .string("Erholung reduziert"),
          "text": .string("Dein Ruhepuls liegt über deinem Normalbereich."), "richtung": .string("weniger"),
          "prioritaet": .number(1), "gueltig_tage": .number(30), "sicherheit": .string("niedrig"),
          "belege": .array([.string("f1")]),
        ]),
        .object(["thema": .string("erholung"), "titel": .string("Ohne Beleg"), "text": .string("x")]),
        .object([
          "thema": .string("unsinn"), "titel": .string("x"), "text": .string("x"), "belege": .array([.string("f1")]),
        ]),
      ])
    ])
    let insights = InsightAnalysis.insights(from: output, facts: facts, model: "gemma", now: now)
    #expect(insights.count == 1)
    #expect(insights[0].basis == ["Ruhepuls heute 64, Schnitt 58"])
    #expect(insights[0].uncertain)
    #expect(insights[0].validUntil == now.addingTimeInterval(14 * 86_400))
    #expect(insights[0].subject == "ruhepuls")
    let input = InsightAnalysis.input(
      topic: .recovery, facts: facts, missing: ["Keine Schlafdaten"], ruleInsights: [])
    #expect(input["thema"] == .string("erholung"))
    #expect(input["fehlend"] == .array([.string("Keine Schlafdaten")]))
  }

  @Test func storedInsightsDecode() throws {
    let data = try JSONEncoder().encode([insight()])
    #expect(try JSONDecoder().decode([Insight].self, from: data) == [insight()])
  }
}
