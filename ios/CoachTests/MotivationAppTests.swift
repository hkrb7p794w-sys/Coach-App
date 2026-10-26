import CoachCore
import Foundation
import Testing

@testable import Coach

extension StubbedNetworkTests {
  @MainActor
  struct MotivationAppTests {
    private func environment() throws -> (CoachSettings, AIClient, UserDefaults) {
      let store = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let settings = CoachSettings(defaults: store)
      var profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .improveFitness)
      for weekday in Weekday.allCases { profile.schedule.set([SessionSlot(.run)], on: weekday) }
      settings.profile = profile
      let ai = AIClient(secrets: InMemorySecretStore(), defaults: store, session: StubURLProtocol.session())
      return (settings, ai, store)
    }

    @Test func memberIDStaysStableAndCompanionIsOff() throws {
      let (settings, _, store) = try environment()
      #expect(!settings.companion.isActive)
      #expect(!settings.league.isJoined)
      let reloaded = CoachSettings(defaults: store)
      #expect(reloaded.league.memberID == settings.league.memberID)
      settings.companion = CompanionSettings(enabled: true, name: "Daisy", kind: .dog)
      #expect(CoachSettings(defaults: store).companion.displayName == "Daisy")
    }

    @Test func inviteConfiguresWorkerAndJoins() throws {
      let (settings, ai, _) = try environment()
      let league = LeagueService(ai: ai, settings: settings)
      #expect(!league.canUse)
      try league.accept(
        LeagueInvite(workerURL: "https://coach-ai.example.workers.dev", token: "tok-123", code: "team-abc234xyz9"))
      #expect(league.canUse)
      #expect(settings.league.code == "team-abc234xyz9")
      let invite = try #require(league.inviteURL)
      #expect(LeagueInvite(url: invite)?.token == "tok-123")
    }

    @Test func syncSendsOnlyNameAndPoints() async throws {
      let (settings, ai, _) = try environment()
      try ai.configure(url: "https://coach-ai.example.workers.dev", token: "tok-123")
      settings.league.code = "team-abc234xyz9"
      settings.league.name = "Lea"
      let league = LeagueService(ai: ai, settings: settings)
      let me = settings.league.memberID
      StubURLProtocol.install { request in
        if request.httpMethod == "PUT" { return (200, #"{"member":{}}"#) }
        return (
          200,
          #"{"members":[{"id":"\#(me)","name":"Lea","avatar":"person.fill","week":"2026-10-26","weekPoints":20,"#
            + #""totalPoints":20,"streak":0,"done":2,"planned":7}]}"#
        )
      }
      let today = CalendarDay(date: .now)
      let summary = MotivationSummary.compute(
        schedule: { settings.schedule(inWeekOf: $0) }, trainingDays: [today], today: today, weeks: 1)
      await league.sync(summary: summary)

      #expect(league.lastError == nil)
      #expect(league.members.first?.name == "Lea")
      let put = try #require(StubURLProtocol.requests.first)
      #expect(put.url?.path() == "/v1/league/team-abc234xyz9/members/\(me)")
      #expect(put.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
      #expect(StubURLProtocol.requests.last?.url?.query()?.contains("week=") == true)
    }
  }
}
