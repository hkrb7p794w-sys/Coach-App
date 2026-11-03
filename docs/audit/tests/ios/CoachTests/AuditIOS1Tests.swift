import CoachCore
import Foundation
import Testing

@testable import Coach

/// Audit IOS1: Befunde aus der App-Prüfung (müssen mit dem Stand 8baa407 fehlschlagen).
@MainActor
struct AuditIOS1TodayTests {
  /// IOS1-01: Im persönlichen Profil darf „Jetzt dran“ keinen Text des Almere-Saisonplans zeigen.
  /// `NowSection` (NowViews.swift:81) zeigt `snapshot.today?.focus` in beiden Modi; `TodayViewModel.update`
  /// berechnet `today` aus dem Saisonplan auch für `.personal`. Woche ab 12.10.2026 hat den Fokus
  /// „Neustart + Lauftest: alle Lauf-Paces hängen daran“.
  @Test func personalProfileDoesNotCarrySeasonWeekFocus() throws {
    let store = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
    let settings = CoachSettings(defaults: store)
    settings.profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run])
    let viewModel = TodayViewModel(defaults: store)

    viewModel.update(
      days: [], activities: [], settings: settings, now: CalendarDay(year: 2026, month: 10, day: 13).localDate)

    let snapshot = try #require(viewModel.snapshot)
    #expect((snapshot.today?.focus ?? "").isEmpty)
  }
}

/// JWT mit `client_id` und Ablauf 2100 (Signatur egal).
private let auditConnectToken =
  "eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln"

extension StubbedNetworkTests {
  @MainActor
  struct AuditIOS1NetworkTests {
    private func session(token: GarminConnect.Token) throws -> (GarminConnectSession, InMemorySecretStore) {
      let stored = String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
      let secrets = InMemorySecretStore([.garminConnectToken: stored])
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let session = GarminConnectSession(secrets: secrets, defaults: defaults, makeSession: StubURLProtocol.session)
      session.pause = {}
      return (session, secrets)
    }

    private var refreshCount: Int {
      StubURLProtocol.requests.filter { $0.url?.path() == "/di-oauth2-service/oauth/token" }.count
    }

    /// IOS1-05: Zwei gleichzeitige Abrufe (z. B. Abruf beim Öffnen und Garmin-Abgleich nach der Gym-Einheit) mit
    /// abgelaufenem Token erneuern es zweimal mit demselben Refresh-Token. Erwartet: genau eine Erneuerung.
    @Test func concurrentCallersShareOneTokenRefresh() async throws {
      StubURLProtocol.install { request in
        request.url?.path() == "/di-oauth2-service/oauth/token"
          ? (200, #"{"access_token":"\#(auditConnectToken)","refresh_token":"r2","expires_in":3600}"#) : (404, "")
      }
      let expired = GarminConnect.Token(
        accessToken: "alt", refreshToken: "r1", clientID: "GARMIN_CONNECT_MOBILE_IOS_DI",
        expiresAt: Date.now.addingTimeInterval(-60))
      let (session, _) = try session(token: expired)

      async let first = session.validToken()
      async let second = session.validToken()
      _ = try await (first, second)

      #expect(refreshCount == 1)
    }

    /// IOS1-06: Garmin drosselt die Erneuerung (HTTP 429), das Token gilt aber noch 10 Minuten. Heute wirft die App
    /// `needsLogin` („Anmeldung abgelaufen. Bitte neu anmelden“). Erwartet wie bei 5xx: altes Token weiterverwenden.
    @Test func rateLimitedRefreshKeepsStillValidToken() async throws {
      StubURLProtocol.install { request in
        request.url?.path() == "/di-oauth2-service/oauth/token" ? (429, "") : (404, "")
      }
      let soon = GarminConnect.Token(
        accessToken: "alt", refreshToken: "r1", clientID: "GARMIN_CONNECT_MOBILE_IOS_DI",
        expiresAt: Date.now.addingTimeInterval(600))
      let (session, _) = try session(token: soon)

      let token = try await session.validToken()

      #expect(token.accessToken == "alt")
      #expect(session.isLoggedIn)
    }

    /// IOS1-04: Wird die Ansicht verlassen bzw. `.task(id:)` neu gestartet, bricht SwiftUI die KI-Anfrage ab. Der
    /// Abbruch darf nicht als „Netzwerkfehler: …“ in der Coach-Notiz und als Fehlschlag im Nutzungsprotokoll landen.
    @Test func cancelledAIRequestIsNotANetworkError() async throws {
      StubURLProtocol.install { _ in
        (200, #"{"output": {"ok": true, "gruss": "Hallo"}, "model": "m", "provider": "p"}"#)
      }
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let client = AIClient(secrets: InMemorySecretStore(), defaults: defaults, session: StubURLProtocol.session())
      try client.configure(url: "https://coach-ai.example.workers.dev", token: "geheim")
      var failures = 0
      client.onUsage = { entry in if !entry.ok { failures += 1 } }

      let task = Task { () async throws -> AIResponse in
        withUnsafeCurrentTask { $0?.cancel() }
        return try await client.run(task: "ping")
      }
      do {
        _ = try await task.value
        Issue.record("Abgebrochene Anfrage lieferte ein Ergebnis")
      } catch {
        #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
      }
      #expect(failures == 0)
    }
  }
}
