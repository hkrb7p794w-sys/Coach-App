import Foundation
import Testing

@testable import CoachCore

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> CalendarDay {
  CalendarDay(year: year, month: month, day: dayOfMonth)
}

private func metrics(
  hrv: String? = nil, weekly: Double? = nil, low: Double? = nil, rhr: Double? = nil, sleepHours: Double? = nil
) -> DailyMetrics {
  var metrics = DailyMetrics(day: day(2026, 10, 23))
  metrics.hrvStatus = hrv
  metrics.hrvWeeklyAverage = weekly
  metrics.hrvBaselineLow = low
  metrics.restingHeartRate = rhr
  metrics.sleepSeconds = sleepHours.map { $0 * 3600 }
  return metrics
}

struct RecommendationTests {
  @Test func noDataIsNormal() {
    let result = RecoveryEvaluator.evaluate(metrics(), restingHeartRate7DayAverage: nil)
    #expect(result.level == .normal)
    #expect(result.reasons == ["keine Erholungswerte auffällig"])
  }

  @Test func lowHRVMeansRest() {
    let result = RecoveryEvaluator.evaluate(metrics(hrv: "LOW"), restingHeartRate7DayAverage: nil)
    #expect(result.level == .pause)
    #expect(result.label == "Ruhetag oder sehr locker")
  }

  @Test func unbalancedBelowBaselineMeansEasy() {
    let below = RecoveryEvaluator.evaluate(
      metrics(hrv: "UNBALANCED", weekly: 50, low: 55), restingHeartRate7DayAverage: nil)
    #expect(below.level == .locker)
    let above = RecoveryEvaluator.evaluate(
      metrics(hrv: "UNBALANCED", weekly: 75, low: 55), restingHeartRate7DayAverage: nil)
    #expect(above.level == .normal)
    #expect(above.reasons.first?.contains("über der Baseline") == true)
  }

  @Test func elevatedRestingHeartRate() {
    let result = RecoveryEvaluator.evaluate(metrics(hrv: "BALANCED", rhr: 55), restingHeartRate7DayAverage: 49.6)
    #expect(result.level == .locker)
    #expect(result.reasons.contains("Ruhepuls 55 bpm, 5 über deinem 7-Tage-Schnitt"))
    let fine = RecoveryEvaluator.evaluate(metrics(rhr: 54), restingHeartRate7DayAverage: 49.6)
    #expect(fine.level == .normal)
  }

  @Test(arguments: [(4.5, RecoveryLevel.pause), (5.5, .locker), (6.0, .normal)])
  func sleepThresholds(hours: Double, expected: RecoveryLevel) {
    #expect(RecoveryEvaluator.evaluate(metrics(sleepHours: hours), restingHeartRate7DayAverage: nil).level == expected)
  }

  @Test func worstSignalWins() {
    let result = RecoveryEvaluator.evaluate(
      metrics(hrv: "POOR", rhr: 60, sleepHours: 5.5), restingHeartRate7DayAverage: 50, readinessScore: 40)
    #expect(result.level == .pause)
    #expect(result.reasons.count == 4)
    #expect(result.reasons.contains("kurzer Schlaf (5,5 h)"))
    #expect(result.reasons.contains("Readiness 40 (Garmin-Stufe „Low“)"))
  }

  @Test func averageUsesDaysBeforeToday() {
    let today = day(2026, 10, 23)
    let history = (0...8).map { offset -> DailyMetrics in
      var entry = DailyMetrics(day: today.adding(days: -offset))
      entry.restingHeartRate = Double(50 + offset)
      return entry
    }
    // Tage 1…7 vor heute: 51…57 → 54
    #expect(RecoveryEvaluator.average(\.restingHeartRate, in: history, daysBefore: 1...7, today: today) == 54)
    #expect(RecoveryEvaluator.average(\.restingHeartRate, in: [], daysBefore: 1...7, today: today) == nil)
  }
}

struct SeasonPlanTests {
  private let config = SeasonConfig.standard

  @Test func phaseBoundsMatchLegacyPlan() {
    let bounds = SeasonPlan.phaseBounds(config)
    #expect(bounds.map(\.phase) == TrainingPhase.allCases)
    #expect(bounds[1].end == day(2027, 4, 11))  // Marathon-Aufbau bis 11.04.
    #expect(bounds[2].start == day(2027, 4, 12))
    #expect(bounds[3] == PhaseSpan(phase: .regeneration, start: day(2027, 5, 3), end: day(2027, 5, 16)))
    #expect(bounds[4].start == day(2027, 5, 17))  // Almere-Aufbau 17.05.–08.08.
    #expect(bounds[4].end == day(2027, 8, 8))
    #expect(bounds[5].start == day(2027, 8, 9))  // Almere-Peak 09.08.–29.08.
    #expect(bounds[6].start == day(2027, 8, 30))  // Taper ab Mo 30.08.
    #expect(bounds[6].end == day(2027, 9, 11))
  }

  @Test func phaseLookup() {
    #expect(SeasonPlan.phase(on: day(2026, 10, 23), config: config) == .grundlage)
    #expect(SeasonPlan.phase(on: day(2027, 2, 1), config: config) == .marathonAufbau)
    #expect(SeasonPlan.phase(on: day(2027, 9, 20), config: config) == .almereTaper)
    #expect(SeasonPlan.phase(on: day(2026, 1, 1), config: config) == .grundlage)
  }

  @Test func weekdayIndexStartsMonday() {
    #expect(day(2026, 10, 19).weekdayIndex == 0)  // Montag
    #expect(day(2026, 10, 25).weekdayIndex == 6)  // Sonntag
    #expect(day(2027, 9, 11).weekdayIndex == 5)  // Samstag
  }

  private func activity(_ id: Int64, _ typeKey: String, _ day: CalendarDay, km: Double = 5) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = typeKey
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.distanceMeters = km * 1000
    activity.durationSeconds = 1800
    return activity
  }

  @Test func weeklyVolumeCountsCalendarWeekAndSkipsBikeWithoutDistance() {
    let friday = day(2026, 10, 23)
    let week = WeeklyVolume(
      activities: [
        activity(1, "running", day(2026, 10, 19), km: 8),
        activity(2, "running", day(2026, 10, 18)),  // Sonntag davor
        activity(3, "virtual_ride", day(2026, 10, 20), km: 30),
        activity(4, "indoor_cycling", day(2026, 10, 20), km: 0),  // Zweitaufzeichnung der Uhr
        activity(5, "strength_training", day(2026, 10, 21), km: 0),
        activity(6, "lap_swimming", day(2026, 10, 22), km: 2),
      ],
      weekContaining: friday)

    #expect(week.sessions == [.run: 1, .bike: 1, .strength: 1, .swim: 1])
    #expect(week.kilometers[.run] == 8)
    #expect(week.minutes[.bike] == 30)
  }

  @Test func planStateListsOpenItemsAndTodayFixed() {
    let friday = day(2026, 10, 23)
    var week = WeeklyVolume()
    week.sessions = [.run: 1, .strength: 4]
    let state = SeasonPlan.state(today: friday, config: config, week: week)

    #expect(state.weekday == "Freitag")
    #expect(state.phase == .grundlage)
    #expect(state.daysLeftInWeek == 2)
    #expect(state.todayFixed.map(\.text) == ["Push + Pull kombiniert (Home-Gym)"])
    #expect(
      state.weekOpen == ["1× Schwimmen", "1× Laufen (1x Zone 2, 1x Schwelle/Intervall im Wechsel)", "1× Rad"])
    #expect(state.targets.first { $0.target.sport == .run }?.percent == 50)
    #expect(state.daysToRace == friday.days(until: day(2027, 9, 11)))
  }

  @Test func weekendBikeIsMarkedDoneWhenTargetReached() {
    var week = WeeklyVolume()
    week.sessions = [.bike: 1]
    let sunday = day(2026, 10, 25)
    let state = SeasonPlan.state(today: sunday, config: config, week: week)
    #expect(state.todayFixed.first?.done == true)
    #expect(state.todayFixed.first?.text.hasSuffix("diese Woche schon erledigt") == true)
  }

  @Test func planTextUsesTestValues() {
    var custom = config
    custom.ftpWatts = 200
    let text = SeasonPlan.planText(for: .almerePeak, config: custom)
    #expect(text.bike.contains("150–156 W"))
    #expect(SeasonPlan.testValuesText(config).contains("CSS 2:10 /100 m"))
    #expect(SeasonPlan.testValuesText(config).contains("Lauf-Schwellenpace 4:55 /km"))
  }

  @Test func configDecodesOldStoredVersions() throws {
    let data = Data(#"{"mainRaceName": "Test", "ftpWatts": 190}"#.utf8)
    let decoded = try JSONDecoder().decode(SeasonConfig.self, from: data)
    #expect(decoded.mainRaceName == "Test")
    #expect(decoded.ftpWatts == 190)
    #expect(decoded.marathonDate == SeasonConfig.standard.marathonDate)
  }
}

struct CoachingNoteTests {
  private let plan = SeasonPlan.state(
    today: CalendarDay(year: 2026, month: 10, day: 23), config: .standard, week: WeeklyVolume())

  @Test func reducedModeSendsNoRawValues() throws {
    var today = metrics(hrv: "BALANCED", rhr: 58, sleepHours: 5.5)
    today.hrvLastNightAverage = 61
    today.bodyBatteryHigh = 72
    let recommendation = RecoveryEvaluator.evaluate(today, restingHeartRate7DayAverage: 50)

    let input = CoachingNote.input(
      recommendation: recommendation, metrics: today, plan: plan, config: .standard, week: WeeklyVolume(),
      privacy: .reduced)

    let health = JSONValue.object(["vitals": input["vitals"] ?? .null, "decision": input["decision"] ?? .null])
    let text = String(decoding: try JSONEncoder().encode(health), as: UTF8.self)
    #expect(!text.contains("58"))
    #expect(!text.contains("61"))
    #expect(!text.contains("5,5"))
    #expect(text.contains("Ruhepuls deutlich über deinem 7-Tage-Schnitt"))
    #expect(text.contains("Schlaf: kurz"))
    #expect(text.contains("Body Battery: hoch"))
  }

  @Test func fullModeIncludesValues() {
    let today = metrics(hrv: "BALANCED", rhr: 58, sleepHours: 7.25)
    let vitals = CoachingNote.vitals(today, privacy: .full)
    #expect(vitals.first == "Ruhepuls: 58 bpm")
    #expect(vitals.last?.hasPrefix("Schlaf: 7,3 h") == true)
  }

  @Test func fallbackNoteMentionsDecisionAndOpenItems() {
    let recommendation = Recommendation(level: .locker, reasons: ["kurzer Schlaf (5,5 h)"])
    let lines = CoachingNote.fallback(recommendation, plan: plan)
    #expect(lines[0] == "Locker / verkürzt: " + RecoveryLevel.locker.advice)
    #expect(lines[1] == "Grund: kurzer Schlaf (5,5 h).")
    #expect(lines.contains { $0.hasPrefix("Diese Woche noch offen: 1× Schwimmen") })
  }

  @Test func pointsFromModelOutput() {
    let output = JSONValue.object(["punkte": .array([.string(" Eins "), .string(""), .number(2)])])
    #expect(CoachingNote.points(from: output) == ["Eins", "2"])
  }
}
