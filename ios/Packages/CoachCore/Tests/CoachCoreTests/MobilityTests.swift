import Foundation
import Testing

@testable import CoachCore

struct MobilityTests {
  let today = CalendarDay(year: 2026, month: 11, day: 9)

  @Test func libraryCoversEveryAreaForEveryContext() {
    for area in MobilityArea.allCases {
      let drills = MobilityLibrary.drills.filter { $0.areas.contains(area) }
      #expect(drills.contains { $0.style == .dynamic }, "\(area) ohne dynamische Übung")
      #expect(drills.contains { $0.style == .hold }, "\(area) ohne Halteübung")
    }
    #expect(Set(MobilityLibrary.drills.map(\.id)).count == MobilityLibrary.drills.count)
    // Halten unter 60 s je Seite (Behm et al. 2016).
    #expect(MobilityLibrary.drills.filter { $0.style == .hold }.allSatisfy { $0.seconds < 60 })
  }

  @Test func ratingsUseThresholds() throws {
    let knee = try #require(MobilityTest.byID["knee_to_wall"])
    #expect(knee.rating(4) == .limited)
    #expect(knee.rating(6) == .moderate)
    #expect(knee.rating(12) == .good)
    let toes = try #require(MobilityTest.byID["toe_touch"])
    #expect(toes.rating(-15) == .limited)
    #expect(toes.rating(-5) == .moderate)
    #expect(toes.rating(0) == .good)
    let squat = try #require(MobilityTest.byID["deep_squat"])
    #expect(squat.rating(2) == .good)
    #expect(squat.rating(7) == .good)
    #expect(squat.rating(-1) == .limited)
  }

  @Test func runningFocusesLegsAndHips() {
    let scores = MobilityPlanner.scores(recentSets: [:], enduranceMinutes: [.run: 60], results: [])
    let top = Set(scores.prefix(4).map(\.area))
    #expect(top == [.ankles, .hipFlexors, .hamstrings, .hips])
    #expect(scores[0].reasons.first == "Laufen 60 min seit gestern")
  }

  @Test func shortActivitiesDoNotCount() {
    let scores = MobilityPlanner.scores(recentSets: [:], enduranceMinutes: [.swim: 10], results: [])
    #expect(scores.allSatisfy { $0.points == 0 })
  }

  @Test func upperBodyDayFocusesShoulders() {
    let scores = MobilityPlanner.scores(
      recentSets: [.chest: 9, .lats: 9, .triceps: 6], enduranceMinutes: [:], results: [])
    #expect(Set(scores.prefix(2).map(\.area)) == [.shoulders, .thoracicSpine])
  }

  @Test func limitedTestOutranksTraining() {
    let results = [MobilityTestResult(testID: "knee_to_wall", day: today, value: 3)]
    let scores = MobilityPlanner.scores(recentSets: [.chest: 12], enduranceMinutes: [:], results: results)
    #expect(scores[0].area == .ankles)
    #expect(scores[0].reasons.contains("Test „Knie zur Wand“: eingeschränkt"))
  }

  @Test func latestResultCounts() {
    let results = [
      MobilityTestResult(testID: "knee_to_wall", day: today.adding(days: -30), value: 3),
      MobilityTestResult(testID: "knee_to_wall", day: today, value: 12),
    ]
    #expect(MobilityTestResult.latest(results)["knee_to_wall"]?.value == 12)
    let scores = MobilityPlanner.scores(recentSets: [:], enduranceMinutes: [:], results: results)
    #expect(scores.allSatisfy { $0.points == 0 })
  }

  @Test func preTrainingUsesOnlyDynamicDrills() {
    for minutes in MobilityPlanner.durations {
      let routine = MobilityPlanner.routine(
        context: .preTraining, minutes: minutes, recentSets: [.quads: 10], enduranceMinutes: [.run: 40], results: [])
      #expect(!routine.blocks.isEmpty)
      #expect(routine.blocks.allSatisfy { $0.drill.style == .dynamic })
    }
  }

  @Test func restDayStartsWithHolds() {
    let routine = MobilityPlanner.routine(
      context: .restDay, minutes: 10, recentSets: [:], enduranceMinutes: [.run: 60], results: [])
    #expect(routine.blocks.first?.drill.style == .hold)
    #expect(routine.focus.count == 3)
  }

  @Test func routineRespectsBudgetAndHasNoDuplicates() {
    for context in MobilityContext.allCases {
      for minutes in MobilityPlanner.durations {
        let routine = MobilityPlanner.routine(
          context: context, minutes: minutes, recentSets: [.hamstrings: 8, .glutes: 8], enduranceMinutes: [.bike: 90],
          results: [])
        #expect(routine.totalSeconds <= minutes * 60 + 30, "\(context) \(minutes) min zu lang")
        // Vor dem Training reichen die dynamischen Übungen nicht für 20 Minuten; das zeigt die App ehrlich an.
        if context != .preTraining || minutes <= 10 {
          #expect(routine.totalSeconds >= minutes * 60 / 2, "\(context) \(minutes) min zu kurz")
        }
        #expect(Set(routine.blocks.map(\.id)).count == routine.blocks.count)
        #expect(routine.blocks.allSatisfy { routine.focus.contains($0.area) })
      }
    }
  }

  @Test func withoutDataTheRoutineIsBalanced() {
    let routine = MobilityPlanner.routine(
      context: .restDay, minutes: 5, recentSets: [:], enduranceMinutes: [:], results: [])
    #expect(routine.reasons == [MobilityPlanner.balancedReason])
    #expect(!routine.blocks.isEmpty)
  }

  @Test func inputsFromSessionsAndActivities() {
    let now = Date(timeIntervalSince1970: 1_793_500_000)
    let squat = LoggedExercise(
      exerciseID: "kniebeuge", name: "Kniebeuge", group: .legs,
      sets: (0..<4).map { _ in LoggedSet(reps: 8, weightKg: 100) })
    let recent = GymSession(
      workoutKey: nil, title: "Beine", start: now.addingTimeInterval(-20 * 3_600),
      end: now.addingTimeInterval(-19 * 3_600), exercises: [squat])
    let old = GymSession(
      workoutKey: nil, title: "Beine", start: now.addingTimeInterval(-80 * 3_600),
      end: now.addingTimeInterval(-79 * 3_600), exercises: [squat])
    let sets = MobilityPlanner.recentSets(sessions: [recent, old], now: now)
    #expect((sets[.quads] ?? 0) > 0)
    #expect((sets[.quads] ?? 0) <= 4)

    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.startLocal = "2026-11-08 07:00:00"
    run.durationSeconds = 3_000
    var oldRide = GarminActivity(id: 2)
    oldRide.typeKey = "cycling"
    oldRide.startLocal = "2026-11-05 07:00:00"
    oldRide.durationSeconds = 3_600
    let minutes = MobilityPlanner.enduranceMinutes(activities: [run, oldRide], today: today)
    #expect(minutes[.run] == 50)
    #expect(minutes[.bike] == nil)
  }

  @Test func weeklyCountUsesDistinctDays() {
    var settings = MobilitySettings()
    settings.log = [
      MobilityLogEntry(day: today, minutes: 10, areas: [.hips]),
      MobilityLogEntry(day: today, minutes: 5, areas: [.ankles]),
      MobilityLogEntry(day: today.adding(days: -3), minutes: 10, areas: [.hips]),
      MobilityLogEntry(day: today.adding(days: -8), minutes: 10, areas: [.hips]),
    ]
    #expect(settings.sessions(inWeekEnding: today) == 2)
    let data = try? JSONEncoder().encode(settings)
    let decoded = data.flatMap { try? JSONDecoder().decode(MobilitySettings.self, from: $0) }
    #expect(decoded == settings)
    #expect((try? JSONDecoder().decode(MobilitySettings.self, from: Data("{}".utf8)))?.minutes == 10)
  }

  @Test func evidenceRulesExist() {
    #expect(Evidence.rulesByID["mobility.stretching"]?.studies.count == 3)
    #expect(Evidence.rulesByID["mobility.focus"] != nil)
  }

  @Test func suggestionOnRestAndRecoveryDays() {
    #expect(MobilityPlanner.suggestToday(hasTraining: false, recovery: .normal, doneToday: false))
    #expect(!MobilityPlanner.suggestToday(hasTraining: true, recovery: .normal, doneToday: false))
    #expect(MobilityPlanner.suggestToday(hasTraining: true, recovery: .locker, doneToday: false))
    #expect(MobilityPlanner.suggestToday(hasTraining: true, recovery: .pause, doneToday: false))
    #expect(!MobilityPlanner.suggestToday(hasTraining: false, recovery: nil, doneToday: true))
  }

  @Test func contextLineWithoutRawValues() {
    var settings = MobilitySettings()
    #expect(settings.contextLine(today: today) == nil)
    settings.log = [MobilityLogEntry(day: today, minutes: 10, areas: [.hips])]
    settings.results = [MobilityTestResult(testID: "knee_to_wall", day: today, value: 4)]
    #expect(
      settings.contextLine(today: today)
        == "Mobility: 1 Einheiten in den letzten 7 Tagen; Selbsttests: Knie zur Wand eingeschränkt.")
    var facts = ChatContext.Facts(profile: UserProfile(), privacy: .reduced)
    facts.mobilityLine = settings.contextLine(today: today)
    #expect(ChatContext.lines(facts).contains { $0.hasPrefix("Mobility: 1 Einheiten") })
  }

  @Test func complaintsPrioritiseAreasAndFlagExercises() {
    let scores = MobilityPlanner.scores(recentSets: [:], enduranceMinutes: [:], results: [], complaints: [.knee])
    #expect(Set(scores.prefix(3).map(\.area)) == [.hipFlexors, .ankles, .hamstrings])
    #expect(scores[0].reasons.first == "Beschwerden: Knie – nur schmerzfrei bewegen")
    // Kniebeuge belastet das Knie (Oberschenkel vorn als Hauptmuskel), Bankdrücken nicht.
    #expect(ComplaintArea.loaded(byExercise: "kniebeuge", group: .legs, complaints: [.knee, .shoulder]) == [.knee])
    #expect(ComplaintArea.loaded(byExercise: "bankdruecken", group: .chest, complaints: [.knee]).isEmpty)
    #expect(ComplaintArea.loaded(byExercise: "bankdruecken", group: .chest, complaints: [.shoulder]) == [.shoulder])
    #expect(ComplaintArea.hint(for: []) == nil)
    #expect(ComplaintArea.hint(for: [.knee])?.hasPrefix("Belastet: Knie.") == true)
  }

  @Test func complaintsReachTheCoachWithoutDiagnosis() {
    var settings = MobilitySettings()
    settings.complaints = [.lowerBack]
    let line = settings.contextLine(today: today)
    #expect(line?.contains("Angegebene Beschwerden: Unterer Rücken") == true)
    #expect(line?.contains("keine Diagnose") == true)
    let decoded = try? JSONDecoder().decode(MobilitySettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded?.complaints == [.lowerBack])
  }
}
