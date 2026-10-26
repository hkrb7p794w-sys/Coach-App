import CoachCore
import Foundation
import Testing

@testable import Coach

/// JWT mit `client_id` und Ablauf 2100 (Signatur egal, die App prüft sie nicht).
private let connectToken =
  "eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln"
private let personalToken = "eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.c2ln"

extension StubbedNetworkTests {
  @MainActor
  struct GarminConnectSessionTests {
    private func makeSession(_ secrets: InMemorySecretStore) throws -> GarminConnectSession {
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let session = GarminConnectSession(secrets: secrets, defaults: defaults, makeSession: StubURLProtocol.session)
      session.pause = {}
      return session
    }

    /// Anmeldeseite, Login mit Bestätigungscode, Token-Tausch, Profil – wie im Vorbild python-garminconnect.
    @Test func loginWithCodeStoresTokenAndDisplayName() async throws {
      StubURLProtocol.install { request in
        let path = request.url?.path() ?? ""
        switch path {
        case "/mobile/sso/en_US/sign-in": return (200, "<html></html>")
        case "/mobile/api/login":
          return (200, #"{"responseStatus":{"type":"MFA_REQUIRED"},"customerMfaInfo":{"mfaLastMethodUsed":"email"}}"#)
        case "/mobile/api/mfa/verifyCode":
          return (200, #"{"responseStatus":{"type":"SUCCESSFUL"},"serviceTicketId":"ST-123"}"#)
        case "/di-oauth2-service/oauth/token":
          return (200, #"{"access_token":"\#(connectToken)","refresh_token":"r1","expires_in":3600}"#)
        case "/userprofile-service/socialProfile": return (200, #"{"displayName":"alex-123"}"#)
        default: return (404, "")
        }
      }
      let secrets = InMemorySecretStore()
      let session = try makeSession(secrets)

      let first = try await session.login(email: " alex@example.com ", password: "geheim")
      #expect(first == .needsCode(method: "email"))
      #expect(!session.isLoggedIn)
      let second = try await session.submitCode("123456")

      #expect(second == .loggedIn)
      #expect(session.isLoggedIn)
      #expect(session.displayName == "alex-123")
      #expect(session.email == "alex@example.com")
      #expect(secrets.string(for: .garminConnectToken)?.contains("r1") == true)
      // Das Passwort landet nirgends im Speicher.
      #expect(secrets.string(for: .garminConnectToken)?.contains("geheim") == false)
      let requests = StubURLProtocol.requests
      let login = try #require(requests.first { $0.url?.path() == "/mobile/api/login" })
      #expect(login.value(forHTTPHeaderField: "Origin") == "https://sso.garmin.com")
      let exchange = try #require(requests.first { $0.url?.path() == "/di-oauth2-service/oauth/token" })
      #expect(exchange.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
      let profile = try #require(requests.last)
      #expect(profile.value(forHTTPHeaderField: "Authorization") == "Bearer \(connectToken)")
    }

    @Test func wrongPasswordIsReported() async throws {
      StubURLProtocol.install { request in
        request.url?.path() == "/mobile/api/login"
          ? (200, #"{"responseStatus":{"type":"INVALID_USERNAME_PASSWORD"}}"#) : (200, "")
      }
      let session = try makeSession(InMemorySecretStore())
      await #expect(throws: GarminConnectError.invalidCredentials) {
        _ = try await session.login(email: "a@b.de", password: "falsch")
      }
      #expect(!session.isLoggedIn)
    }

    /// Konto zuerst; scheitert es (hier 403), springt die Personal API mit dem Key ein.
    @Test func clientPrefersAccountAndFallsBackToPersonalAPI() async throws {
      let token = GarminConnect.Token(
        accessToken: connectToken, refreshToken: "r1", clientID: "GARMIN_CONNECT_MOBILE_IOS_DI",
        expiresAt: Date(timeIntervalSince1970: 4_102_444_800))
      let stored = String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
      let secrets = InMemorySecretStore([.garminConnectToken: stored, .garminAPIKey: "key"])
      let client = GarminClient(
        secrets: secrets, session: StubURLProtocol.session(), connect: try makeSession(secrets))

      StubURLProtocol.install { request in
        if request.url?.host() == "connectapi.garmin.com" {
          return request.url?.path() == "/userprofile-service/userprofile/settings" ? (403, "") : (200, #"{"ok":1}"#)
        }
        return request.url?.path().hasSuffix("/token") == true ? (200, personalToken) : (200, #"{"fallback":1}"#)
      }

      let viaAccount = try await client.json(.heartRateZones)
      #expect(viaAccount["ok"]?.doubleValue == 1)
      let viaFallback = try await client.json(.profileSettings)
      #expect(viaFallback["fallback"]?.doubleValue == 1)
      #expect(client.sources[.connect] == 1)
      #expect(client.sources[.personalAPI] == 1)
      #expect(client.lastConnectError != nil)
      // Abrufe aufs Konto tragen die Kopfzeilen der Garmin-App.
      let accountCall = try #require(StubURLProtocol.requests.first { $0.url?.host() == "connectapi.garmin.com" })
      #expect(accountCall.value(forHTTPHeaderField: "X-Garmin-Client-Platform") == "Android")
    }
  }
}
