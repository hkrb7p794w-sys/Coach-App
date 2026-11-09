import Foundation
import Testing

@testable import CoachCore

/// Phase 76 (Audit): Einwilligung vor der KI-Nutzung.
struct Phase76Tests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func settings(_ provider: AIProviderChoice = .auto, health: Bool? = nil) -> AISettings {
    var settings = AISettings(provider: provider)
    settings.consent = health.map { AIConsent(date: now, includesHealthDetails: $0) }
    return settings
  }

  @Test func withoutConsentNothingGoesToTrainingProviders() {
    #expect(AIPolicy.route(task: "ai_insights", settings: settings()).provider == .privat)
    #expect(AIPolicy.route(task: "ai_insights", settings: settings(.gemini)).provider == .privat)
    #expect(AIPolicy.route(task: "ai_insights", settings: settings()).consented == false)
  }

  @Test func consentAllowsTheChosenProvider() {
    let route = AIPolicy.route(task: "ai_insights", settings: settings(health: false))
    #expect(route.provider == .auto)
    #expect(route.consented)
  }

  @Test func healthDetailsNeedTheirOwnConsent() {
    #expect(AIPolicy.route(task: "coach_chat", settings: settings(health: false)).provider == .privat)
    #expect(AIPolicy.route(task: "meal_analyze", settings: settings(health: false)).provider == .privat)
    #expect(AIPolicy.route(task: "coach_chat", settings: settings(health: true)).provider == .auto)
  }

  @Test func providersWithoutTrainingNeedNoConsent() {
    #expect(AIPolicy.route(task: "coach_chat", settings: settings(.workersAI)).provider == .workersAI)
    #expect(AIPolicy.route(task: "coach_chat", settings: settings(.privat)).provider == .privat)
    #expect(!settings(.privat).needsConsent)
    #expect(settings().needsConsent)
    #expect(!settings(health: false).needsConsent)
  }

  @Test func newConsentVersionAsksAgain() {
    var old = settings(health: true)
    old.consent?.version = AIConsent.currentVersion - 1
    #expect(old.needsConsent)
    #expect(AIPolicy.route(task: "ai_insights", settings: old).provider == .privat)
  }

  @Test func consentSurvivesStorage() throws {
    let stored = settings(health: true)
    #expect(try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(stored)) == stored)
  }

  @Test func expiringGuestTokensCountAsGuests() {
    #expect(GuestToken.isGuest("g2.abcdefghijk2.1893456000.ff"))
  }
}
