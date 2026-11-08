import Foundation
import Testing

@testable import CoachCore

/// Pausenlogik, Feiertage und Schlafempfehlung nach Arbeits- und freien Tagen (Paket 11).
struct Paket11Tests {
  // MARK: - Pausen

  private func gym(compound: Int = 150, isolation: Int = 75) -> GymSettings {
    var settings = GymSettings()
    settings.restCompound = compound
    settings.restIsolation = isolation
    return settings
  }

  @Test func exerciseOverrideBeatsEverything() {
    var settings = gym()
    settings.restOverrides["x"] = 200
    #expect(settings.rest(for: "x", compound: true, planned: 45) == 200)
  }

  @Test func ownPlanValueBeatsDefaults() {
    #expect(gym().rest(for: "x", compound: true, planned: 45) == 45)
    #expect(gym().rest(for: "x", compound: false, planned: 200) == 200)
  }

  /// 120 und 90 Sekunden sind die Vorlagenwerte der Pläne: Sie dürfen die Einstellungen nicht überdecken.
  @Test func templateValuesFollowSettings() {
    #expect(gym().rest(for: "x", compound: true, planned: 120) == 150)
    #expect(gym().rest(for: "x", compound: false, planned: 90) == 75)
    #expect(gym().rest(for: "x", compound: true, planned: nil) == 150)
    #expect(gym().rest(for: "x", compound: false) == 75)
  }

  // MARK: - Feiertage

  private func day(_ year: Int, _ month: Int, _ value: Int) -> CalendarDay {
    CalendarDay(year: year, month: month, day: value)
  }

  @Test func easterDates() {
    #expect(GermanHolidays.easter(2025) == day(2025, 4, 20))
    #expect(GermanHolidays.easter(2026) == day(2026, 4, 5))
    #expect(GermanHolidays.easter(2027) == day(2027, 3, 28))
  }

  @Test func nationwideHolidaysApplyEverywhere() {
    for state in GermanState.allCases {
      #expect(GermanHolidays.name(on: day(2026, 10, 3), state: state) != nil)
      #expect(GermanHolidays.name(on: day(2026, 5, 14), state: state) == "Christi Himmelfahrt")
      #expect(GermanHolidays.all(year: 2026, state: state).count >= 9)
    }
  }

  @Test func stateHolidaysDiffer() {
    #expect(GermanHolidays.name(on: day(2026, 6, 4), state: .nw) == "Fronleichnam")
    #expect(GermanHolidays.name(on: day(2026, 6, 4), state: .ni) == nil)
    #expect(GermanHolidays.name(on: day(2026, 11, 1), state: .by) == "Allerheiligen")
    #expect(GermanHolidays.name(on: day(2026, 10, 31), state: .by) == nil)
    #expect(GermanHolidays.name(on: day(2026, 10, 31), state: .sn) == "Reformationstag")
    #expect(GermanHolidays.name(on: day(2026, 11, 18), state: .sn) == "Buß- und Bettag")
    #expect(GermanHolidays.name(on: day(2026, 11, 18), state: .by) == nil)
    #expect(GermanHolidays.name(on: day(2026, 3, 8), state: .be) == "Frauentag")
    #expect(GermanHolidays.name(on: day(2022, 3, 8), state: .mv) == nil)
    #expect(GermanHolidays.name(on: day(2023, 3, 8), state: .mv) == "Frauentag")
    #expect(GermanHolidays.name(on: day(2026, 9, 20), state: .th) == "Weltkindertag")
    #expect(GermanHolidays.name(on: day(2026, 1, 6), state: .st) == "Heilige Drei Könige")
    #expect(GermanHolidays.name(on: day(2017, 10, 31), state: .ni) == nil)
  }

  // MARK: - Schlaf

  private func nights(until today: CalendarDay) -> [DailyMetrics] {
    (0..<7).map {
      var metrics = DailyMetrics(day: today.adding(days: -$0))
      metrics.sleepSeconds = 8 * 3_600
      return metrics
    }
  }

  private func settings(state: GermanState? = .nw) -> SleepSettings {
    var settings = SleepSettings()
    settings.wakeHour = 6
    settings.wakeMinute = 0
    settings.freeWakeHour = 8
    settings.freeWakeMinute = 0
    settings.usesFreeDayTime = true
    settings.state = state
    return settings
  }

  /// Montag, 9.11.2026: Der nächste Tag ist ein Arbeitstag.
  @Test func workdayUsesWorkdayWake() throws {
    let today = day(2026, 11, 9)
    let report = try #require(
      SleepCoach.report(days: nights(until: today), settings: settings(), goal: nil, today: today))
    #expect(report.nextDayIsFree == false)
    #expect(report.bedtimeMinutes == (6 * 60 - 480 - SleepCoach.latencyMinutes + 1_440) % 1_440)
  }

  /// Freitag: Am Samstag gilt die spätere Zeit.
  @Test func weekendUsesFreeWake() throws {
    let today = day(2026, 11, 13)
    let report = try #require(
      SleepCoach.report(days: nights(until: today), settings: settings(), goal: nil, today: today))
    #expect(report.nextDayIsFree)
    #expect(report.bedtimeMinutes == (8 * 60 - 480 - SleepCoach.latencyMinutes + 1_440) % 1_440)
  }

  /// Fronleichnam 2026 ist Donnerstag: frei in NRW, Arbeitstag in Niedersachsen.
  @Test func holidayDependsOnState() throws {
    let today = day(2026, 6, 3)
    let free = try #require(
      SleepCoach.report(days: nights(until: today), settings: settings(state: .nw), goal: nil, today: today))
    let work = try #require(
      SleepCoach.report(days: nights(until: today), settings: settings(state: .ni), goal: nil, today: today))
    #expect(free.nextDayIsFree)
    #expect(free.nextHoliday == "Fronleichnam")
    #expect(!work.nextDayIsFree)
  }

  @Test func withoutStateOnlyWeekendsAreFree() throws {
    let today = day(2026, 6, 3)
    let report = try #require(
      SleepCoach.report(days: nights(until: today), settings: settings(state: nil), goal: nil, today: today))
    #expect(!report.nextDayIsFree)
  }

  @Test func withoutFreeDayTimeNothingChanges() throws {
    var plain = settings()
    plain.usesFreeDayTime = false
    let today = day(2026, 11, 13)
    let report = try #require(SleepCoach.report(days: nights(until: today), settings: plain, goal: nil, today: today))
    #expect(report.bedtimeMinutes == (6 * 60 - 480 - SleepCoach.latencyMinutes + 1_440) % 1_440)
  }

  @Test func oldSleepSettingsStillDecode() throws {
    let decoded = try JSONDecoder().decode(SleepSettings.self, from: Data(#"{"targetHours":8,"wakeHour":7}"#.utf8))
    #expect(decoded.wakeHour == 7)
    #expect(!decoded.usesFreeDayTime)
    #expect(decoded.state == nil)
  }

  // MARK: - Planübergreifender Stand

  @Test func planInputCarriesNotesAndRecentPerformance() throws {
    var set = LoggedSet(reps: 12, weightKg: 80)
    set.done = true
    let exercise = LoggedExercise(exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest, sets: [set])
    let session = GymSession(
      workoutKey: nil, title: "Plan B", start: Date(timeIntervalSince1970: 1_790_000_000), exercises: [exercise])
    let input = GymCoach.planInput(
      request: GymCoach.PlanRequest(), profile: UserProfile(), equipment: Equipment.gym, routines: [],
      sessions: [session],
      custom: [], today: CalendarDay(year: 2026, month: 11, day: 9), notes: ["bankdruecken": "Schulter links zwickt"])
    let notes = try #require(input["exerciseNotes"]?.arrayValue)
    #expect(notes.first?.stringValue?.contains("Schulter") == true)
    let recent = try #require(input["recentPerformance"]?.arrayValue)
    #expect(recent.first?.stringValue?.contains("80 kg × 12") == true)
  }

  @Test func alarmDecidesWakeTimeOnItsDays() {
    var settings = SleepSettings()
    let monday = CalendarDay(year: 2026, month: 11, day: 9)
    settings.alarm = SleepAlarm(minutes: 300, onlyDay: monday)
    #expect(settings.wakeMinutes(on: monday) == 300)
    #expect(settings.wakeMinutes(on: monday.adding(days: 1)) == settings.wakeMinutes)
    settings.alarm = SleepAlarm(minutes: 300, weekdaysOnly: true)
    #expect(settings.wakeMinutes(on: monday.adding(days: 4)) == 300)
    #expect(settings.wakeMinutes(on: monday.adding(days: 5)) == settings.wakeMinutes)
  }
}
