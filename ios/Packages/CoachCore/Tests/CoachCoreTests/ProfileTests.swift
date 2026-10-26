import Foundation
import Testing

@testable import CoachCore

/// Montag, 26.10.2026.
private let monday = CalendarDay(year: 2026, month: 10, day: 26)

private func schedule(_ plan: [Weekday: [SessionSlot]]) -> WeekSchedule {
  var result = WeekSchedule()
  for (weekday, slots) in plan { result.set(slots, on: weekday) }
  return result
}

private func profile(
  sports: [TrainingSport] = [.run, .strength], goal: FitnessGoal = .improveFitness, level: ExperienceLevel = .beginner,
  event: EventGoal? = nil, health: [HealthFlag] = []
) -> UserProfile {
  var profile = UserProfile(sports: sports, goal: goal, event: event, health: health)
  for sport in sports { profile.setLevel(level, for: sport) }
  return profile
}

private func ids(_ hints: [ScheduleHint]) -> Set<String> {
  Set(hints.map(\.id))
}

struct UserProfileTests {
  @Test func decodesOldAndPartialData() throws {
    let partial = try JSONDecoder().decode(UserProfile.self, from: Data(#"{"goal":"loseWeight"}"#.utf8))
    #expect(partial.goal == .loseWeight)
    #expect(partial.mode == .personal)
    #expect(!partial.onboardingDone)
    #expect(partial.schedule.days.count == 7)
    let broken = try JSONDecoder().decode(UserProfile.self, from: Data(#"{"goal":"unbekannt","sports":["x"]}"#.utf8))
    #expect(broken.goal == .improveFitness)
    #expect(broken.sports == [.run, .strength])
  }

  @Test func roundTripKeepsEverything() throws {
    var original = profile(sports: [.run, .swim], goal: .loseAndBuild, level: .intermediate)
    original.event = EventGoal(name: "Stadtlauf", date: monday, kind: .run10k, targetSeconds: 3_000)
    original.targets = ImprovementTargets(restingHeartRate: 55, targetWeightKilograms: 62, weeksToTargetWeight: 20)
    original.schedule = schedule([.tuesday: [SessionSlot(.swim)], .thursday: [SessionSlot(.run, .hard)]])
    original.health = [.injury]
    let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
    #expect(decoded.level(for: .swim) == .intermediate)
    #expect(decoded.enduranceLevel == .intermediate)
  }

  @Test func existingUsersKeepTheSeasonPlan() {
    let existing = ProfileMigration.initialProfile(hasExistingData: true)
    #expect(existing.mode == .season)
    #expect(existing.onboardingDone)
    #expect(existing.trains(.swim) && existing.trains(.bike) && existing.trains(.run) && existing.trains(.strength))
    let fresh = ProfileMigration.initialProfile(hasExistingData: false)
    #expect(fresh.mode == .personal)
    #expect(!fresh.onboardingDone)
  }
}

struct WeekScheduleTests {
  @Test func alwaysHasSevenDays() throws {
    #expect(WeekSchedule(days: [[SessionSlot(.run)]]).days.count == 7)
    let decoded = try JSONDecoder().decode(WeekSchedule.self, from: Data(#"[[{"sport":"run","intensity":"easy"}]]"#.utf8))
    #expect(decoded.days.count == 7)
    #expect(decoded.slots(on: .monday) == [SessionSlot(.run)])
    #expect(try JSONDecoder().decode(WeekSchedule.self, from: Data(#"{"a":1}"#.utf8)).days.count == 7)
  }

  @Test func weekdaysMatchCalendarDays() {
    #expect(Weekday(day: monday) == .monday)
    #expect(Weekday(day: monday.adding(days: 6)) == .sunday)
    #expect(Weekday.sunday.next == .monday)
    #expect(Weekday.monday.previous == .sunday)
    #expect(Weekday.friday.adding(-5) == .sunday)
  }

  @Test func streaksWrapAroundTheWeek() {
    let wrap = schedule([.saturday: [SessionSlot(.run)], .sunday: [SessionSlot(.run)], .monday: [SessionSlot(.run)]])
    #expect(wrap.longestStreak == 3)
    var all = WeekSchedule()
    for weekday in Weekday.allCases { all.set([SessionSlot(.run)], on: weekday) }
    #expect(all.longestStreak == 7)
    #expect(all.restDays.isEmpty)
    #expect(WeekSchedule().longestStreak == 0)
  }

  @Test func findsNextRestDay() {
    let plan = schedule([.monday: [SessionSlot(.run)], .tuesday: [SessionSlot(.run)], .wednesday: [SessionSlot(.run)]])
    #expect(plan.nextRestDay(after: .monday, within: 3) == .thursday)
    #expect(plan.nextRestDay(after: .monday, within: 2) == nil)
    #expect(plan.nextRestDay(after: .wednesday, within: 1) == .thursday)
  }

  @Test func mapsToNutritionDayTypes() {
    let plan = schedule([
      .monday: [SessionSlot(.run, .easy)], .tuesday: [SessionSlot(.run, .long)],
      .wednesday: [SessionSlot(.strength, .hard)], .thursday: [SessionSlot(.run, .hard)],
      .friday: [SessionSlot(.other)],
    ])
    #expect(NutritionPlanner.plannedDayType(plan.templateItems(on: .monday)) == .moderate)
    #expect(NutritionPlanner.plannedDayType(plan.templateItems(on: .tuesday)) == .hard)
    #expect(NutritionPlanner.plannedDayType(plan.templateItems(on: .wednesday)) == .light)
    #expect(NutritionPlanner.plannedDayType(plan.templateItems(on: .thursday)) == .hard)
    #expect(NutritionPlanner.plannedDayType(plan.templateItems(on: .friday)) == nil)
    #expect(NutritionPlanner.plannedDayType(plan.templateItems(on: .saturday)) == nil)
  }
}

struct ScheduleCheckTests {
  @Test func emptyPlanAsksForInput() {
    #expect(ids(ScheduleCheck.hints(schedule: WeekSchedule(), profile: profile())) == ["empty"])
  }

  @Test func demandsARestDay() {
    var all = WeekSchedule()
    for weekday in Weekday.allCases { all.set([SessionSlot(.run)], on: weekday) }
    let hints = ScheduleCheck.hints(schedule: all, profile: profile())
    #expect(hints.first?.id == "rest")
    #expect(hints.first?.severity == .warning)
    #expect(hints.first?.isPracticeRule == true)
  }

  @Test func flagsBackToBackDemandingDays() {
    let plan = schedule([.saturday: [SessionSlot(.run, .long)], .sunday: [SessionSlot(.bike, .hard)]])
    let hints = ScheduleCheck.hints(schedule: plan, profile: profile(sports: [.run, .bike], level: .advanced))
    let match = hints.first { $0.id == "back-to-back-5" }
    #expect(match?.severity == .warning)
    #expect(match?.evidenceIDs == ["intensity.distribution"])
    // Auch über die Wochengrenze: Sonntag und Montag.
    let wrap = schedule([.sunday: [SessionSlot(.run, .long)], .monday: [SessionSlot(.run, .hard)]])
    #expect(ids(ScheduleCheck.hints(schedule: wrap, profile: profile(level: .advanced))).contains("back-to-back-6"))
  }

  @Test func warnsAboutTooMuchIntensity() {
    let plan = schedule([
      .monday: [SessionSlot(.run, .hard)], .wednesday: [SessionSlot(.run, .hard)],
      .friday: [SessionSlot(.bike, .easy)], .saturday: [SessionSlot(.run, .easy)],
    ])
    let hints = ScheduleCheck.hints(schedule: plan, profile: profile(sports: [.run, .bike], level: .advanced))
    #expect(ids(hints).contains("hard-share"))
    let beginner = ScheduleCheck.hints(schedule: plan, profile: profile(sports: [.run, .bike], level: .beginner))
    #expect(ids(beginner).contains("beginner-hard"))
  }

  @Test func asksForTwoStrengthDaysWhenBuildingMuscle() {
    let plan = schedule([.monday: [SessionSlot(.strength, .hard)], .thursday: [SessionSlot(.run)]])
    let hints = ScheduleCheck.hints(schedule: plan, profile: profile(goal: .buildMuscle))
    #expect(hints.first { $0.id == "strength-frequency" }?.evidenceIDs == ["gym.volume"])
    let loss = ScheduleCheck.hints(
      schedule: schedule([.monday: [SessionSlot(.run)]]), profile: profile(goal: .loseWeight))
    #expect(loss.first { $0.id == "strength-for-loss" }?.evidenceIDs == ["weightloss.exercise"])
  }

  @Test func notesChosenSportsWithoutDay() {
    let hints = ScheduleCheck.hints(
      schedule: schedule([.monday: [SessionSlot(.run)]]), profile: profile(sports: [.run, .swim]))
    #expect(ids(hints).contains("missing-swim"))
    #expect(!ids(hints).contains("missing-run"))
  }

  @Test func warnsAboutHeavyLegsBeforeLongRun() {
    let plan = schedule([.friday: [SessionSlot(.strength, .hard)], .saturday: [SessionSlot(.run, .long)]])
    #expect(ids(ScheduleCheck.hints(schedule: plan, profile: profile(level: .advanced))).contains("strength-before-run-4"))
    let swapped = schedule([.friday: [SessionSlot(.run, .long)], .saturday: [SessionSlot(.strength, .hard)]])
    #expect(!ids(ScheduleCheck.hints(schedule: swapped, profile: profile(level: .advanced))).contains("strength-before-run-4"))
  }

  @Test func checksMarathonRequirements() {
    let event = EventGoal(name: "Marathon", date: monday, kind: .marathon)
    let plan = schedule([.tuesday: [SessionSlot(.run)], .thursday: [SessionSlot(.run)]])
    let hints = ScheduleCheck.hints(schedule: plan, profile: profile(sports: [.run], event: event))
    #expect(ids(hints).isSuperset(of: ["event-run-days", "event-long-run"]))
  }

  @Test func supportsFitnessAndRestingHeartRateGoals() {
    let hints = ScheduleCheck.hints(
      schedule: schedule([.tuesday: [SessionSlot(.run)]]), profile: profile(sports: [.run], goal: .improveFitness))
    #expect(hints.first { $0.id == "endurance-frequency" }?.evidenceIDs == ["rhr.endurance"])
    #expect(hints.first { $0.id == "who-minimum" }?.evidenceIDs == ["activity.who"])
  }

  @Test func everyEvidenceIDExists() {
    var all = WeekSchedule()
    for weekday in Weekday.allCases { all.set([SessionSlot(.run, .hard), SessionSlot(.strength)], on: weekday) }
    let hints = ScheduleCheck.hints(schedule: all, profile: profile(goal: .buildMuscle))
    for hint in hints { #expect(hint.evidenceIDs.allSatisfy { Evidence.rulesByID[$0] != nil }) }
  }
}

struct ScheduleAdvisorTests {
  private let plan = schedule([
    .monday: [SessionSlot(.run, .hard)], .tuesday: [SessionSlot(.strength, .hard)],
    .thursday: [SessionSlot(.run, .easy)],
  ])

  private func advice(_ level: RecoveryLevel?, day: CalendarDay = monday, trained: Bool = false) -> ScheduleAdvice {
    var person = profile(level: .advanced)
    person.schedule = plan
    return ScheduleAdvisor.advice(profile: person, day: day, recovery: level, trainedToday: trained)
  }

  @Test func followsThePlanWhenRecovered() {
    let result = advice(.normal)
    #expect(result.mode == .asPlanned)
    #expect(result.headline == "Qualitätslauf (Tempo oder Intervalle)")
    #expect(result.detail.contains("Morgen (Dienstag): Krafttraining."))
  }

  @Test func movesDemandingSessionToTheNextRestDayWhenRecoveryIsLow() {
    let result = advice(.pause)
    #expect(result.mode == .rest)
    #expect(result.move == .wednesday)
    #expect(result.detail.contains("Mittwoch"))
    #expect(result.evidenceIDs == ["recovery.hrv", "recovery.subjective"])
  }

  @Test func makesTheSessionEasierWhenRecoveryIsMedium() {
    let result = advice(.locker)
    #expect(result.mode == .lighter)
    #expect(result.move == nil)
    #expect(result.detail.contains("lockerer"))
  }

  @Test func easySessionsStayEasyOnLowRecovery() {
    let result = advice(.pause, day: monday.adding(days: 3))
    #expect(result.mode == .rest)
    #expect(result.move == nil)
    #expect(result.headline == "Heute nur ganz locker oder frei")
  }

  @Test func restDaysAreAcknowledged() {
    let result = advice(.normal, day: monday.adding(days: 2))
    #expect(result.mode == .restDay)
    #expect(result.plannedTitles.isEmpty)
    #expect(result.detail.contains("Morgen (Donnerstag): Lockerer Lauf."))
    #expect(advice(.pause, day: monday.adding(days: 2)).evidenceIDs == ["recovery.hrv", "recovery.subjective"])
  }

  @Test func recognisesFinishedTraining() {
    #expect(advice(.normal, trained: true).mode == .done)
  }

  @Test func worksWithoutGarminValues() {
    let result = advice(nil)
    #expect(result.mode == .asPlanned)
    #expect(result.detail.contains("noch keine Garmin-Werte"))
  }

  @Test func withoutARestDayNearbyTheSessionIsPostponed() {
    var person = profile(level: .advanced)
    var busy = WeekSchedule()
    for weekday in Weekday.allCases { busy.set([SessionSlot(.run, .hard)], on: weekday) }
    person.schedule = busy
    let result = ScheduleAdvisor.advice(profile: person, day: monday, recovery: .pause, trainedToday: false)
    #expect(result.move == nil)
    #expect(result.detail.contains("hole"))
  }
}

struct GoalRulesTests {
  private let woman = BodyProfile(weightKilograms: 68, heightCentimeters: 168, age: 32, isFemale: true)

  @Test func normalWeightLossUsesHalfAPercentPerWeek() {
    let result = GoalRules.assess(profile: profile(goal: .loseWeight), body: woman)
    #expect(result.nutritionGoal == .lose)
    #expect(result.weeklyChangePercent == -0.5)
    #expect(!result.blocksWeightChange)
    #expect(result.evidenceIDs.contains("weightloss.rate"))
  }

  @Test func capsAmbitiousTargets() {
    var person = profile(goal: .loseWeight)
    person.targets = ImprovementTargets(targetWeightKilograms: 58, weeksToTargetWeight: 4)
    let result = GoalRules.assess(profile: person, body: woman)
    #expect(result.weeklyChangePercent == -1.0)
    #expect(result.notes.contains { $0.contains("begrenzt") })
    // Mittleres Tempo: 68 → 64 kg in 10 Wochen ≈ 0,59 % pro Woche.
    person.targets = ImprovementTargets(targetWeightKilograms: 64, weeksToTargetWeight: 10)
    let moderate = GoalRules.assess(profile: person, body: woman)
    #expect(abs((moderate.weeklyChangePercent ?? 0) + 0.588) < 0.01)
  }

  @Test func blocksWeightGoalsForRiskGroups() {
    for flag in [HealthFlag.pregnantOrPostpartum, .eatingDisorder] {
      let result = GoalRules.assess(profile: profile(goal: .loseWeight, health: [flag]), body: woman)
      #expect(result.blocksWeightChange)
      #expect(result.nutritionGoal == .maintain)
      #expect(result.weeklyChangePercent == nil)
    }
    let minor = BodyProfile(weightKilograms: 60, heightCentimeters: 170, age: 16, isFemale: true)
    #expect(GoalRules.assess(profile: profile(goal: .loseWeight), body: minor).blocksWeightChange)
    #expect(GoalRules.assess(profile: profile(goal: .buildMuscle), body: minor).blocksWeightChange)
    #expect(!GoalRules.assess(profile: profile(goal: .improveFitness), body: minor).blocksWeightChange)
  }

  @Test func neverRecommendsLosingWeightBelowBMI185() {
    let thin = BodyProfile(weightKilograms: 50, heightCentimeters: 172, age: 25, isFemale: true)
    #expect(GoalRules.bmi(thin) < 18.5)
    let result = GoalRules.assess(profile: profile(goal: .loseAndBuild), body: thin)
    #expect(result.blocksWeightChange)
    #expect(result.nutritionGoal == .maintain)
    // Muskelaufbau bleibt möglich.
    #expect(!GoalRules.assess(profile: profile(goal: .buildMuscle), body: thin).blocksWeightChange)
    // Ein Zielgewicht unter BMI 18,5 wird nicht angesteuert.
    var person = profile(goal: .loseWeight)
    person.targets = ImprovementTargets(targetWeightKilograms: 50, weeksToTargetWeight: 30)
    let result2 = GoalRules.assess(profile: person, body: woman)
    #expect(result2.weeklyChangePercent == -0.5)
    #expect(result2.notes.contains { $0.contains("BMI 18,5") })
  }

  @Test func mapsMuscleAndWeightGainGoals() {
    let recomposition = GoalRules.assess(profile: profile(goal: .loseAndBuild), body: woman)
    #expect(recomposition.nutritionGoal == .recomposition)
    #expect(recomposition.weeklyChangePercent == -0.25)
    let muscle = GoalRules.assess(profile: profile(goal: .buildMuscle), body: woman)
    #expect(muscle.nutritionGoal == .gain)
    #expect(muscle.weeklyChangePercent == 0.25)
    let gain = GoalRules.assess(profile: profile(goal: .gainWeight), body: woman)
    #expect(gain.weeklyChangePercent == 0.5)
    #expect(GoalRules.assess(profile: profile(goal: .maintain), body: woman).weeklyChangePercent == nil)
  }

  @Test func medicalConditionsAddANoteButDoNotBlock() {
    let result = GoalRules.assess(profile: profile(goal: .loseWeight, health: [.injury]), body: woman)
    #expect(!result.blocksWeightChange)
    #expect(result.notes.contains { $0.contains("Arzt") })
  }

  @Test func rateHelpers() {
    let loss = GoalRules.weeklyLossPercent(currentKilograms: 80, targetKilograms: 72, weeks: 20)
    #expect(abs(loss.percent - 0.5) < 0.001)
    #expect(!loss.capped)
    #expect(GoalRules.weeklyLossPercent(currentKilograms: 80, targetKilograms: 90, weeks: 10).percent == 0.5)
    let gain = GoalRules.weeklyGainPercent(currentKilograms: 60, targetKilograms: 66, weeks: 4)
    #expect(gain.percent == 0.5)
    #expect(gain.capped)
  }

  @Test func restingHeartRateOutlook() {
    #expect(GoalRules.restingHeartRateOutlook(current: nil, target: 55).contains("Sobald Garmin"))
    #expect(GoalRules.restingHeartRateOutlook(current: 54, target: 55).contains("bei oder unter"))
    #expect(GoalRules.restingHeartRateOutlook(current: 60, target: 55).contains("Realistisch"))
    #expect(GoalRules.restingHeartRateOutlook(current: 75, target: 55).contains("ambitioniert"))
  }

  @Test func appliesToNutritionSettings() {
    var settings = NutritionSettings()
    GoalRules.apply(GoalRules.assess(profile: profile(goal: .loseWeight), body: woman), to: &settings)
    #expect(settings.goal == .lose)
    #expect(settings.weeklyWeightChangePercent == -0.5)
  }

  @Test func weeklyRateShapesTheDailyTarget() {
    func kilocalories(_ goal: NutritionGoal, _ rate: Double?) -> Double {
      var settings = NutritionSettings()
      settings.weightKilograms = 68
      settings.heightCentimeters = 168
      settings.age = 32
      settings.isFemale = true
      settings.goal = goal
      settings.weeklyWeightChangePercent = rate
      let targets = NutritionPlanner.compute(
        activities: [], planItems: [], settings: settings, garminProfile: nil, day: monday, hasGarminData: false)
      return targets.values[.kcal] ?? 0
    }
    let maintain = kilocalories(.maintain, nil)
    #expect(kilocalories(.lose, -0.5) < maintain)
    #expect(kilocalories(.lose, -0.25) > kilocalories(.lose, -0.5))
    #expect(kilocalories(.gain, 0.25) > maintain)
    // Extreme Wünsche werden auf höchstens 25 % Defizit begrenzt.
    #expect(kilocalories(.lose, -1.0) == kilocalories(.lose, -5.0))
    // Ohne Wochentempo bleibt das Verhalten wie zuvor.
    #expect(kilocalories(.lose, nil) < maintain)
  }

  @Test func decodesOldNutritionSettings() throws {
    let settings = try JSONDecoder().decode(NutritionSettings.self, from: Data(#"{"goal":"abnehmen"}"#.utf8))
    #expect(settings.goal == .lose)
    #expect(settings.weeklyWeightChangePercent == nil)
  }
}

struct SchedulePlannerTests {
  private let weekdays: [Weekday] = [.monday, .wednesday, .friday, .saturday]

  @Test func suggestsOnlyAvailableDaysAndNoWarnings() {
    let person = profile(sports: [.run, .strength], goal: .improveFitness)
    let result = SchedulePlanner.suggest(profile: person, availableDays: weekdays)
    #expect(Set(result.trainingDays).isSubset(of: Set(weekdays)))
    #expect(result.sessionCount == 4)
    #expect(!ScheduleCheck.hints(schedule: result, profile: person).contains { $0.severity == .warning })
    #expect(result.count(of: .run) == 3)
    #expect(result.count(of: .strength) == 1)
  }

  @Test func beginnersGetNoIntensiveRuns() {
    let result = SchedulePlanner.suggest(
      profile: profile(sports: [.run], goal: .loseWeight, level: .beginner), availableDays: weekdays)
    #expect(result.days.flatMap { $0 }.allSatisfy { $0.intensity == .easy })
  }

  @Test func trimsToTheAvailableDays() {
    let result = SchedulePlanner.suggest(
      profile: profile(sports: [.run, .strength, .swim, .bike], goal: .improveFitness, level: .intermediate),
      availableDays: [.tuesday, .thursday])
    #expect(result.sessionCount == 2)
    #expect(result.count(of: .run) == 1)
    #expect(result.count(of: .strength) == 1)
  }

  @Test func muscleGoalsGetMoreStrengthDays() {
    let result = SchedulePlanner.suggest(
      profile: profile(sports: [.run, .strength], goal: .buildMuscle, level: .intermediate),
      availableDays: [.monday, .tuesday, .thursday, .friday, .saturday])
    #expect(result.count(of: .strength) == 4)
    #expect(result.count(of: .run) == 1)
    #expect(!ScheduleCheck.hints(schedule: result, profile: profile(sports: [.run, .strength], goal: .buildMuscle, level: .intermediate)).contains { $0.severity == .warning })
  }

  @Test func marathonPlansHaveALongRunOnTheWeekend() {
    let event = EventGoal(name: "Marathon", date: monday.adding(days: 120), kind: .marathon)
    let person = profile(sports: [.run, .strength], level: .intermediate, event: event)
    let result = SchedulePlanner.suggest(
      profile: person, availableDays: [.tuesday, .wednesday, .thursday, .saturday, .sunday])
    let longDays = Weekday.allCases.filter { result.slots(on: $0).contains(SessionSlot(.run, .long)) }
    #expect(longDays.count == 1)
    #expect(longDays.first == .saturday || longDays.first == .sunday)
    #expect(result.count(of: .run) == 4)
    #expect(result.count(of: .strength) == 1)
    #expect(!ScheduleCheck.hints(schedule: result, profile: person).contains { $0.severity == .warning })
  }

  @Test func triathlonKeepsAllThreeDisciplines() {
    let event = EventGoal(name: "Sprint", date: monday.adding(days: 90), kind: .triathlon)
    let person = profile(sports: [.swim, .bike, .run, .strength], level: .intermediate, event: event)
    let result = SchedulePlanner.suggest(
      profile: person, availableDays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
    for sport in [TrainingSport.swim, .bike, .run] { #expect(result.count(of: sport) == 2) }
    // Auch bei sieben freien Tagen bleibt ein Ruhetag.
    #expect(result.restDays.count == 1)
    #expect(result.sessionCount == SchedulePlanner.maxSessionsPerWeek)
  }

  @Test func handlesEmptyInput() {
    #expect(SchedulePlanner.suggest(profile: profile(sports: []), availableDays: weekdays).isEmpty)
    #expect(SchedulePlanner.suggest(profile: profile(), availableDays: []).isEmpty)
  }

  @Test func isDeterministic() {
    let person = profile(sports: [.run, .strength, .bike], goal: .loseWeight, level: .intermediate)
    let first = SchedulePlanner.suggest(profile: person, availableDays: Weekday.allCases)
    let second = SchedulePlanner.suggest(profile: person, availableDays: Array(Weekday.allCases.reversed()))
    #expect(first == second)
  }
}

struct ProfileEvidenceTests {
  @Test func newRulesPointToVerifiedStudies() {
    let ids = [
      "activity.who", "weightloss.rate", "weightloss.exercise", "weightloss.protein", "weightloss.sleep",
      "gain.surplus", "run.progression", "run.minimum", "rhr.endurance", "fitness.hiit", "plan.deload",
      "cycle.individual",
    ]
    for id in ids {
      let rule = Evidence.rulesByID[id]
      #expect(rule != nil, "\(id) fehlt")
      #expect(rule?.studies.count == rule?.studyIDs.count)
    }
    // Die verbreitete 10-%-Regel ist nur als Praxisregel geführt.
    #expect(Evidence.rulesByID["run.progression"]?.strength == .practice)
  }
}
