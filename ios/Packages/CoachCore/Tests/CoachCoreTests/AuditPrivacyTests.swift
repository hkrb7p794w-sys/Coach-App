import Foundation
import Testing

@testable import CoachCore

/// Audit CORE2-01: Im Datenschutzmodus „reduziert“ dürfen keine Roh-Gesundheitswerte an die KI gehen.
/// `ChatContext.lines` (Worker-Aufgaben `coach_chat` und – über `CoachFacts.analysis` – `ai_insights`) übernimmt die
/// Sätze des Wochenberichts aber ungefiltert; diese enthalten die mittlere Schlafdauer in Stunden und den
/// Ruhepuls-Anstieg in Schlägen.
struct AuditPrivacyTests {
  private func highlights() -> [String] {
    var week = WeeklyReport.Totals()
    week.sessions = 3
    week.minutes = 120
    week.averageSleepHours = 5.8
    week.averageRestingHeartRate = 58
    var previous = WeeklyReport.Totals()
    previous.sessions = 3
    previous.minutes = 120
    previous.averageRestingHeartRate = 52
    return WeeklyReport.highlights(week: week, previous: previous, fitnessChange: nil)
  }

  @Test func weeklyHighlightsContainRawValues() {
    // Vorbedingung: Die Sätze tragen tatsächlich Rohwerte.
    let lines = highlights()
    #expect(lines.contains { $0.contains("5,8 Stunden") })
    #expect(lines.contains { $0.contains("6 Schläge") })
  }

  @Test func reducedChatFactsHideRawSleepAndPulseFromWeeklyHighlights() {
    var facts = ChatContext.Facts(profile: UserProfile(goal: .loseWeight), privacy: .reduced)
    facts.weekHighlights = highlights()
    let text = ChatContext.lines(facts).joined(separator: "\n")
    #expect(!text.contains("5,8"), "Schlafdauer in Stunden geht im Modus „reduziert“ an die KI")
    #expect(!text.contains("6 Schläge"), "Ruhepuls-Differenz in Schlägen geht im Modus „reduziert“ an die KI")
  }

  @Test func reducedChatInputHasNoRawWeeklyValues() {
    var facts = ChatContext.Facts(profile: UserProfile(goal: .loseWeight), privacy: .reduced)
    facts.weekHighlights = highlights()
    let input = ChatContext.input(facts, question: "Wie war meine Woche?", history: [])
    let sent = (input["facts"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: "\n")
    #expect(!sent.contains("5,8"))
    #expect(!sent.contains("Schläge höher"))
  }
}
