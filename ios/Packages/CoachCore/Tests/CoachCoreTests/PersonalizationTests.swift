import Foundation
import Testing

@testable import CoachCore

private let today = CalendarDay(year: 2026, month: 11, day: 2)

struct PersonalizationTests {
  @Test func goalsKeepPrimaryOutOfSecondaryAndCapCounts() {
    let goals = PersonalGoals(
      primary: .muscleGain, secondary: [.muscleGain, .fatLoss, .health, .endurance],
      priorities: [.muscle, .muscle, .sleep, .nutrition, .health], since: today)
    #expect(goals.secondary == [.fatLoss, .health])
    #expect(goals.priorities == [.muscle, .sleep, .nutrition])
  }

  @Test func defaultPrioritiesFollowGoals() {
    let goals = PersonalGoals(primary: .endurance, secondary: [.recovery], since: today)
    #expect(goals.effectivePriorities == [.endurance, .recovery, .sleep])
    let chosen = PersonalGoals(primary: .endurance, priorities: [.nutrition], since: today)
    #expect(chosen.effectivePriorities == [.nutrition])
  }

  @Test func fitnessGoalForNutritionFromGoals() {
    #expect(Personalization.fitnessGoal(for: .init(primary: .fatLoss, since: today)) == .loseWeight)
    let both = PersonalGoals(primary: .fatLoss, secondary: [.strength], since: today)
    #expect(Personalization.fitnessGoal(for: both) == .loseAndBuild)
    #expect(Personalization.fitnessGoal(for: .init(primary: .muscleGain, since: today)) == .buildMuscle)
    #expect(Personalization.fitnessGoal(for: .init(primary: .competition, since: today)) == .improveFitness)
    #expect(Personalization.fitnessGoal(for: .init(primary: .health, since: today)) == .maintain)
  }

  @Test func derivedGoalsForOldProfiles() {
    #expect(Personalization.derived(from: .seasonPlan, since: today).primary == .competition)
    var profile = UserProfile(goal: .loseAndBuild)
    #expect(Personalization.derived(from: profile, since: today).all == [.fatLoss, .muscleGain])
    profile.event = EventGoal(name: "Halbmarathon", date: today.adding(days: 60), kind: .halfMarathon)
    let withEvent = Personalization.derived(from: profile, since: today)
    #expect(withEvent.primary == .competition)
    #expect(withEvent.secondary.first == .fatLoss)
  }

  @Test func muscleGoalPlansMoreStrengthThanTriathlon() {
    var profile = UserProfile(sports: [.run, .strength], goal: .improveFitness)
    profile.setLevel(.intermediate, for: .run)
    profile.setLevel(.intermediate, for: .strength)
    let before = SchedulePlanner.wantedCounts(profile: profile)
    profile.updateGoals(.init(primary: .muscleGain, since: today), on: today)
    let muscle = SchedulePlanner.wantedCounts(profile: profile)
    #expect((muscle[.strength] ?? 0) >= 4)
    #expect((muscle[.strength] ?? 0) > (before[.strength] ?? 0))
    profile.updateGoals(.init(primary: .endurance, since: today), on: today)
    #expect((SchedulePlanner.wantedCounts(profile: profile)[.run] ?? 0) >= 3)
  }

  @Test func recoveryPriorityMakesLoadCheckStricter() {
    #expect(Personalization.maxLoadIncrease(.init(primary: .muscleGain, since: today)) == WeekLoad.maxIncrease)
    #expect(Personalization.maxLoadIncrease(.init(primary: .recovery, since: today)) == 0.20)
    #expect(
      Personalization.maxLoadIncrease(.init(primary: .endurance, priorities: [.health], since: today)) == 0.20)
  }

  @Test func historyKeepsOldGoalsForPastDays() {
    var profile = UserProfile(goal: .buildMuscle)
    let monday = today.adding(days: -7)
    profile.updateGoals(.init(primary: .muscleGain, since: monday), on: monday)
    profile.updateGoals(.init(primary: .endurance, since: today), on: today)
    #expect(profile.goals(on: today).primary == .endurance)
    #expect(profile.goals(on: today.adding(days: -3)).primary == .muscleGain)
    // Vor dem ersten Festlegen: das damals Abgeleitete (Muskelaufbau aus „Muskeln aufbauen“), nicht das neue Ziel.
    #expect(profile.goals(on: today.adding(days: -30)).primary == .muscleGain)
    // Zweimal am selben Tag ändern ersetzt, statt den Verlauf zu füllen.
    let count = profile.goalHistory.count
    profile.updateGoals(.init(primary: .health, since: today), on: today)
    #expect(profile.goalHistory.count == count)
    #expect(profile.goal == .maintain)
  }

  @Test func firstChangeKeepsDerivedGoalsForThePast() {
    var profile = UserProfile(goal: .loseWeight)
    profile.updateGoals(.init(primary: .muscleGain, since: today), on: today)
    #expect(profile.goals(on: today.adding(days: -100)).primary == .fatLoss)
    #expect(profile.goals(on: today).primary == .muscleGain)
  }

  @Test func profileDecodesWithoutNewFieldsAndSkipsUnknownValues() throws {
    let old = #"{"mode":"personal","onboardingDone":true,"sports":["run"],"goal":"buildMuscle"}"#
    let profile = try JSONDecoder().decode(UserProfile.self, from: Data(old.utf8))
    #expect(profile.goals == nil)
    #expect(profile.effectiveGoals(today: today).primary == .muscleGain)
    let goalsJSON = #"{"primary":"strength","secondary":["zukunft","health"],"priorities":["laune","sleep"]}"#
    let goals = try JSONDecoder().decode(PersonalGoals.self, from: Data(goalsJSON.utf8))
    #expect(goals.secondary == [.health])
    #expect(goals.priorities == [.sleep])
    var updated = profile
    updated.updateGoals(.init(primary: .strength, priorities: [.sleep], since: today), on: today)
    updated.tracker = TrackerSetup(usesTracker: true, providers: [.garmin, .whoop])
    let roundTrip = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(updated))
    #expect(roundTrip == updated)
  }

  @Test func aiContextNamesGoalsPrioritiesAndGuidance() {
    var profile = UserProfile(sports: [.strength])
    let goals = PersonalGoals(primary: .muscleGain, secondary: [.fatLoss], priorities: [.muscle], since: today)
    profile.updateGoals(goals, on: today)
    let lines = ChatContext.lines(ChatContext.Facts(profile: profile, privacy: .reduced)).joined(separator: "\n")
    #expect(lines.contains("Hauptziel: Muskelaufbau; Nebenziele: Fettabbau."))
    #expect(lines.contains("Prioritäten der Person: Muskelaufbau."))
    #expect(lines.contains("Kraftvolumen"))
    var triathlon = UserProfile.seasonPlan
    triathlon.goals = nil
    let season = ChatContext.lines(ChatContext.Facts(profile: triathlon, privacy: .reduced)).joined(separator: "\n")
    #expect(season.contains("Hauptziel: Wettkampfvorbereitung"))
    #expect(season.contains("periodisieren"))
  }

  @Test func prioritiesOrderDashboardAndInsights() {
    let sleep = PersonalGoals(primary: .recovery, priorities: [.sleep, .recovery], since: today)
    #expect(Array(Personalization.healthWidgets(sleep).prefix(3)) == [.sleep, .hrv, .bodyBattery])
    #expect(Personalization.insightTopics(sleep).first == .recovery)
    let muscle = PersonalGoals(primary: .muscleGain, priorities: [.muscle], since: today)
    #expect(Personalization.insightTopics(muscle).prefix(2) == [.training, .progress])
    // Jedes Standard-Widget bleibt erreichbar.
    #expect(Set(HealthDashboard.standard).isSubset(of: Set(Personalization.healthWidgets(muscle))))

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func insight(_ topic: InsightTopic, _ subject: String) -> Insight {
      Insight(
        topic: topic, subject: subject, title: subject, text: "", direction: .check, origin: .rules, created: now,
        validUntil: now.addingTimeInterval(86_400))
    }
    let groups = InsightInbox.groups(
      [insight(.nutrition, "protein"), insight(.recovery, "schlaf")], focus: Personalization.insightTopics(sleep),
      now: now)
    #expect(groups.new.map(\.subject) == ["schlaf", "protein"])
  }

  @Test func loadWarningUsesGivenThreshold() {
    // 4 Wochen je 300 min locker, dann eine Woche mit 375 (+25 %): Standard (30 %) still, vorsichtig (20 %) warnt.
    var activities: [GarminActivity] = []
    for week in 0..<4 {
      for day in 0..<3 {
        var run = GarminActivity(id: Int64(week * 10 + day + 1))
        run.typeKey = "running"
        let date = today.adding(days: -(week * 7) - day)
        run.startLocal = "\(date.iso) 07:00:00"
        run.durationSeconds = (week == 0 ? 125 : 100) * 60
        activities.append(run)
      }
    }
    let normal = WeekLoad.check(activities: activities, today: today)
    let careful = WeekLoad.check(activities: activities, today: today, maxIncrease: 0.20)
    #expect(normal.warning == nil)
    #expect(careful.warning != nil)
  }
}
