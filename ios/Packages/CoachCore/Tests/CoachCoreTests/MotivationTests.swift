import Foundation
import Testing

@testable import CoachCore

/// Montag, 26.10.2026.
private let monday = CalendarDay(year: 2026, month: 10, day: 26)

/// Di, Do, Sa geplant.
private func threeDays() -> WeekSchedule {
  var schedule = WeekSchedule()
  schedule.set([SessionSlot(.run)], on: .tuesday)
  schedule.set([SessionSlot(.strength, .hard)], on: .thursday)
  schedule.set([SessionSlot(.run, .long)], on: .saturday)
  return schedule
}

private func week(done offsets: [Int], today offset: Int, schedule: WeekSchedule = threeDays()) -> WeekAdherence {
  WeekAdherence.compute(
    schedule: schedule, trainingDays: Set(offsets.map { monday.adding(days: $0) }), weekOf: monday,
    today: monday.adding(days: offset))
}

struct AdherenceTests {
  @Test func statesPerDay() {
    // Di erledigt, Mi extra, Do verpasst, heute Fr, Sa offen.
    let result = week(done: [1, 2], today: 4)
    #expect(result.days == [.rest, .done, .extra, .missed, .rest, .open, .rest])
    #expect(result.planned == 3)
    #expect(result.done == 1)
    #expect(result.missed == 1)
    #expect(result.shareSoFar == 0.5)
    #expect(!result.isComplete)
  }

  @Test func extraTrainingEarnsNothing() {
    let planOnly = ScoreRules.points(week(done: [1, 3, 5], today: 6))
    let withExtra = ScoreRules.points(week(done: [0, 1, 2, 3, 4, 5, 6], today: 6))
    #expect(planOnly == 3 * ScoreRules.pointsPerSession + ScoreRules.completeWeekBonus)
    #expect(withExtra == planOnly)
  }

  @Test func smallPlansCanWinToo() {
    var two = WeekSchedule()
    two.set([SessionSlot(.run)], on: .monday)
    two.set([SessionSlot(.run)], on: .friday)
    let small = week(done: [0, 4], today: 6, schedule: two)
    let bigButPartial = week(done: [1], today: 6)
    #expect(ScoreRules.points(small) > ScoreRules.points(bigButPartial))
  }

  @Test func skippedDaysAreNotPlanned() {
    var adjustments = PlanAdjustments()
    adjustments.skip(.thursday, inWeekOf: monday)
    let adjusted = week(done: [1, 5], today: 6, schedule: adjustments.schedule(threeDays(), inWeekOf: monday))
    #expect(adjusted.planned == 2)
    #expect(adjusted.isComplete)
  }

  @Test func streakSkipsEmptyWeeksAndStopsAtMiss() {
    let good = week(done: [1, 3], today: 6)  // 2 von 3 = 67 %
    let full = week(done: [1, 3, 5], today: 6)
    let empty = week(done: [], today: 6, schedule: WeekSchedule())
    #expect(!ScoreRules.countsForStreak(good))
    #expect(ScoreRules.streak([full, empty, full, good, full]) == 2)
    #expect(ScoreRules.level(totalPoints: 0) == 1)
    #expect(ScoreRules.level(totalPoints: 250) == 3)
  }
}

struct CompanionTests {
  private let daisy = CompanionSettings(enabled: true, name: "Daisy", kind: .dog)

  private func context(
    planned: [String] = ["Lockerer Lauf"], trained: Bool = false, recovery: RecoveryLevel? = .normal,
    week: WeekAdherence = week(done: [], today: 1), missed: Bool = false
  ) -> CompanionVoice.Context {
    CompanionVoice.Context(
      plannedToday: planned, trainedToday: trained, recovery: recovery, week: week, missedYesterday: missed)
  }

  @Test func moodFollowsRules() {
    #expect(CompanionVoice.mood(context()) == .excited)
    #expect(CompanionVoice.mood(context(trained: true)) == .happy)
    #expect(CompanionVoice.mood(context(trained: true, week: week(done: [1, 3, 5], today: 5))) == .proud)
    #expect(CompanionVoice.mood(context(recovery: .pause)) == .cozy)
    #expect(CompanionVoice.mood(context(planned: [])) == .resting)
    #expect(CompanionVoice.mood(context(missed: true)) == .hopeful)
  }

  @Test func messagesUseNameAndSession() {
    let message = CompanionVoice.message(context(), companion: daisy, day: monday)
    #expect(message.text.contains("Daisy"))
    #expect(message.text.contains("Lockerer Lauf"))
    let cozy = CompanionVoice.message(context(recovery: .pause), companion: daisy, day: monday)
    #expect(cozy.mood == .cozy)
    #expect(cozy.text.contains("Daisy"))
  }

  @Test func everyKindAndMoodHasText() {
    let moods: [CompanionVoice.Context] = [
      context(), context(trained: true), context(trained: true, week: week(done: [1, 3, 5], today: 5)),
      context(recovery: .pause), context(planned: []), context(missed: true),
    ]
    for kind in CompanionSettings.Kind.allCases {
      for item in moods {
        for offset in 0..<3 {
          let text = CompanionVoice.message(
            item, companion: CompanionSettings(enabled: true, kind: kind), day: monday.adding(days: offset)
          ).text
          #expect(!text.isEmpty)
        }
      }
    }
  }

  @Test func daisySpeaksLikeADogAndHasAPhotoPerMood() {
    let photoDaisy = CompanionSettings(enabled: true, kind: .daisy)
    let dog = CompanionSettings(enabled: true, name: "Daisy", kind: .dog)
    #expect(
      CompanionVoice.message(context(), companion: photoDaisy, day: monday).text
        == CompanionVoice.message(context(), companion: dog, day: monday).text)
    #expect(photoDaisy.displayName == "Daisy")
    #expect(CompanionMood.happy.daisyPhoto == "daisy-gym")
    #expect(CompanionMood.cozy.daisyPhoto == "daisy-rest")
    #expect(CompanionMood.proud.daisyPhoto == "daisy-proud")
    #expect(CompanionMood.excited.daisyPhoto == "daisy-walk")
    #expect(CompanionVoice.reminderLead(photoDaisy) == "Daisy wartet schon an der Tür.")
  }

  @Test func defaultsAndDecoding() throws {
    #expect(CompanionSettings(kind: .dog).displayName == "Daisy")
    #expect(CompanionSettings(name: "  Bello ").displayName == "Bello")
    let decoded = try JSONDecoder().decode(CompanionSettings.self, from: Data(#"{"kind":"pferd"}"#.utf8))
    #expect(decoded == CompanionSettings())
    #expect(CompanionVoice.reminderLead(daisy) == "Daisy wartet schon an der Tür.")
    #expect(CompanionVoice.reminderLead(CompanionSettings()) == nil)
  }
}

struct LeagueTests {
  @Test func summaryCountsWeeksAndStreak() {
    // Drei Wochen zurück alles erledigt, diese Woche Di erledigt (heute Mi).
    var trained: Set<CalendarDay> = [monday.adding(days: 1)]
    for week in 1...3 {
      for offset in [1, 3, 5] { trained.insert(monday.adding(days: offset - 7 * week)) }
    }
    let summary = MotivationSummary.compute(
      schedule: { _ in threeDays() }, trainingDays: trained, today: monday.adding(days: 2), weeks: 6)
    #expect(summary.weekPoints == 10)
    #expect(summary.streak == 3)
    #expect(summary.totalPoints == 10 + 3 * 50)
    #expect(summary.level == 2)
    #expect(!summary.missedYesterday(today: monday.adding(days: 2)))
    let thursdayMissed = MotivationSummary.compute(
      schedule: { _ in threeDays() }, trainingDays: trained, today: monday.adding(days: 4), weeks: 1)
    #expect(thursdayMissed.missedYesterday(today: monday.adding(days: 4)))
  }

  @Test func entryMatchesWorkerFormat() throws {
    let summary = MotivationSummary.compute(
      schedule: { _ in threeDays() }, trainingDays: [monday.adding(days: 1)], today: monday.adding(days: 2),
      weeks: 1)
    let entry = LeagueEntry(id: "alex-0001", name: "Alex", avatar: "dog.fill", summary: summary)
    #expect(entry.week == "2026-10-26")
    #expect(entry.done == 1)
    #expect(entry.planned == 3)
    let json =
      #"{"id":"a","name":"Lea","avatar":"person","week":"2026-10-26","weekPoints":5,"#
      + #""totalPoints":9,"streak":1,"done":1,"planned":2,"updatedAt":"2026-10-28T12:00:00.000Z"}"#
    let decoded = try JSONDecoder().decode(LeagueEntry.self, from: Data(json.utf8))
    #expect(decoded.name == "Lea")
    #expect(decoded.weekPoints == 5)
  }

  @Test func inviteRoundTrip() throws {
    let invite = LeagueInvite(
      workerURL: "https://coach-ai.example.workers.dev", token: "geheim+/=&", code: "team-abc234xyz9")
    let url = try #require(invite.url)
    #expect(url.absoluteString.hasPrefix("coach://join?"))
    #expect(LeagueInvite(url: url) == invite)
    #expect(LeagueInvite(url: try #require(URL(string: "coach://join?worker=http://x&league=team-abc234"))) == nil)
    #expect(LeagueInvite(url: try #require(URL(string: "https://join?worker=https://x&league=team-abc234"))) == nil)
  }

  @Test func codesAreValid() {
    for _ in 0..<20 { #expect(LeagueCode.isValid(LeagueCode.generate())) }
    #expect(!LeagueCode.isValid("AB"))
    #expect(!LeagueCode.isValid("team abc"))
    #expect(LeagueCode.isValid("paar-123"))
  }
}
