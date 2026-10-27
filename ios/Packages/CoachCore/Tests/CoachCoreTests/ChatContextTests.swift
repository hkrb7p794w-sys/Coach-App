import Foundation
import Testing

@testable import CoachCore

struct ChatContextTests {
  private func facts(_ privacy: PrivacyMode) -> ChatContext.Facts {
    var facts = ChatContext.Facts(profile: UserProfile(goal: .loseWeight), privacy: privacy)
    facts.recommendation = "Locker"
    facts.reasons = ["HRV 48 ms unter dem Normalbereich"]
    facts.todaySessions = ["Lockerer Lauf, 40 min"]
    facts.sleep = SleepCoach.Report(
      nights: 7, averageHours: 6.4, shortNights: 5, debtHours: 9, tonightMinutes: 540, bedtimeMinutes: 1_275,
      bedtimeSpreadMinutes: 75, tips: [])
    facts.weightTrend = WeightTrend.Result(trendKilograms: 71.8, weeklyPercent: -0.52, entries: 20, spanDays: 27)
    return facts
  }

  @Test func reducedPrivacySendsNoRawHealthValues() {
    let text = ChatContext.lines(facts(.reduced)).joined(separator: "\n")
    #expect(text.contains("Tagesampel heute: Locker."))
    #expect(!text.contains("48 ms"))
    #expect(text.contains("im Schnitt unter 7 Stunden"))
    #expect(!text.contains("6,4"))
    #expect(text.contains("Gewichtstrend: leicht fallend."))
    #expect(!text.contains("71,8"))
    #expect(text.contains("Schlafenszeit heute 21:15"))
    #expect(text.contains("Die Einschlafzeit schwankt stark."))
  }

  @Test func fullPrivacyIncludesValues() {
    let text = ChatContext.lines(facts(.full)).joined(separator: "\n")
    #expect(text.contains("48 ms"))
    #expect(text.contains("6,4 Stunden"))
    #expect(text.contains("71,8 kg"))
  }

  @Test func inputAndAnswer() throws {
    let history = (0..<10).map { (role: $0.isMultiple(of: 2) ? "user" : "coach", text: "Nachricht \($0)") }
    let input = ChatContext.input(facts(.reduced), question: "Wie geht es mir?", history: history)
    #expect(input["history"]?.arrayValue?.count == 6)
    #expect(input["question"]?.stringValue == "Wie geht es mir?")
    let answer = try #require(
      ChatContext.answer(from: .object(["antwort": .string(" Gut. "), "quellen": .array([.string("recovery.hrv")])])))
    #expect(answer.text == "Gut.")
    #expect(answer.sources == ["recovery.hrv"])
    #expect(ChatContext.answer(from: .object([:])) == nil)
  }
}
