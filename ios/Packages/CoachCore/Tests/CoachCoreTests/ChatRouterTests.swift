import Foundation
import Testing

@testable import CoachCore

/// Welche Daten der Chat je Frage bekommt (Testfälle aus Paket 12).
struct ChatRouterTests {
  private let today = CalendarDay(year: 2026, month: 11, day: 9)

  private func date(_ offset: Int) -> Date {
    let day = today.adding(days: offset)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 18)) ?? .now
  }

  private func bench(_ offset: Int, weight: Double, reps: Int) -> GymSession {
    var set = LoggedSet(reps: reps, weightKg: weight)
    set.done = true
    let exercise = LoggedExercise(exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest, sets: [set, set])
    return GymSession(workoutKey: nil, title: "Oberkörper", start: date(offset), exercises: [exercise])
  }

  private func facts(_ privacy: PrivacyMode = .reduced) -> ChatContext.Facts {
    var facts = ChatContext.Facts(profile: UserProfile(mode: .personal, sports: [.strength], goal: .buildMuscle), privacy: privacy)
    facts.gymSessions = [bench(-20, weight: 75, reps: 8), bench(-3, weight: 80, reps: 8)]
    facts.eaten = NutrientValues([.kcal: 1_200, .protein: 70, .carbs: 120, .fat: 40])
    facts.todayMeals = [ChatContext.MealLine(title: "Haferbrei", nutrients: NutrientValues([.kcal: 400, .protein: 20]))]
    facts.recommendation = "Locker trainieren"
    facts.reasons = ["Ruhepuls 8 über Normal"]
    facts.todaySessions = ["Oberkörper"]
    facts.tomorrowSessions = ["Beine"]
    var metrics = DailyMetrics(day: today)
    metrics.restingHeartRate = 58
    facts.todayMetrics = metrics
    return facts
  }

  private func text(_ facts: ChatContext.Facts, question: String, history: [(role: String, text: String)] = []) -> String {
    let topics = ChatRouter.topics(question: question, history: history)
    return ChatContext.focusedLines(facts, topics: topics, question: question, today: today).joined(separator: "\n")
  }

  /// Test 1: Trainingsanalyse.
  @Test func benchHistoryIsCompared() {
    let result = text(facts(), question: "Wie hat sich meine Leistung beim Bankdrücken in den letzten vier Wochen entwickelt?")
    #expect(result.contains("75 kg × 8"))
    #expect(result.contains("80 kg × 8"))
    #expect(result.contains("Differenz 5 kg"))
  }

  @Test func missingExerciseIsNamed() {
    let result = text(facts(), question: "Wie läuft meine Kniebeuge?")
    #expect(result.contains("keine erfassten Sätze"))
  }

  /// Test 2: Ernährung, mit fertig gerechneter Differenz.
  @Test func remainingProteinIsCalculated() {
    var value = facts()
    value.targets = NutritionPlanner.compute(
      activities: [], planItems: [], settings: NutritionSettings(), garminProfile: nil, day: today, hasGarminData: false)
    let goal = Int((value.targets?.values[.protein] ?? 0).rounded())
    let result = text(value, question: "Wie viel Protein fehlt mir heute noch?")
    #expect(result.contains("70 g Protein"))
    #expect(result.contains("Noch offen heute"))
    #expect(result.contains("\(goal - 70) g Protein"))
  }

  /// Test 3: Regeneration.
  @Test func recoveryQuestionGetsAmpelAndPlan() {
    let result = text(facts(), question: "Sollte ich heute schwer trainieren?")
    #expect(result.contains("Locker trainieren"))
    #expect(result.contains("Heute geplant"))
  }

  /// Test 4: Folgefrage übernimmt das Thema.
  @Test func followUpKeepsTopic() {
    let history = [(role: "user", text: "Wie viel Protein fehlt mir heute?"), (role: "coach", text: "Noch 60 g.")]
    let topics = ChatRouter.topics(question: "Und was bedeutet das für mein Training morgen?", history: history)
    #expect(topics.contains(.nutrition))
    #expect(topics.contains(.recovery))
    #expect(text(facts(), question: "Und was bedeutet das für mein Training morgen?", history: history).contains("Morgen geplant: Beine"))
  }

  @Test func generalQuestionLoadsNoPersonalData() {
    let result = text(facts(), question: "Was ist der Unterschied zwischen Kreatin und Molke im Allgemeinen?")
    #expect(!result.contains("Oberkörper"))
    #expect(!result.contains("kcal"))
  }

  @Test func onlyRelevantDataIsLoaded() {
    let result = text(facts(), question: "Wie viel Protein brauche ich noch?")
    #expect(!result.contains("Bankdrücken"))
    #expect(!result.contains("Ampel"))
  }

  @Test func reducedModeHidesRawHealthValues() {
    let question = "Wie war mein Schlaf und soll ich heute trainieren?"
    let reduced = text(facts(.reduced), question: question)
    #expect(!reduced.contains("Ruhepuls heute"))
    #expect(!reduced.contains("Ruhepuls 8"))
    #expect(text(facts(.full), question: question).contains("Ruhepuls heute: 58"))
  }

  @Test func inputKeepsRecentHistoryAndSummarizesOlder() {
    let history = (0..<14).map { (role: "user", text: "Frage \($0)") }
    let input = ChatContext.focusedInput(facts(), question: "Wie geht es weiter?", history: history, today: today)
    #expect(input["history"]?.arrayValue?.count == 10)
    #expect(input["olderQuestions"]?.arrayValue?.isEmpty == false)
  }
}
