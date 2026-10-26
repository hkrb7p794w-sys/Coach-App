import CoachCore
import Foundation
import SwiftData
import Testing

@testable import Coach

/// Gültig bis 2100, damit es im Test nicht erneuert wird.
private let longLivedToken = "eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.c2ln"

extension StubbedNetworkTests {
  @MainActor
  struct NetworkClientTests {
    private func authorization(_ request: URLRequest) -> String? {
      request.value(forHTTPHeaderField: "Authorization")
    }

    @Test func exchangesKeyForTokenAndUsesBearer() async throws {
      StubURLProtocol.install { request in
        request.url?.path().hasSuffix("/token") == true ? (200, longLivedToken) : (200, #"{"data": []}"#)
      }
      let client = GarminClient(
        secrets: InMemorySecretStore([.garminAPIKey: "mein-key"]), session: StubURLProtocol.session())

      let range = DateRange.last(7, endingOn: CalendarDay(year: 2026, month: 10, day: 23))
      let json = try await client.json(.dailySummaries(range))

      #expect(json["data"] == .array([]))
      let requests = StubURLProtocol.requests
      #expect(requests.count == 2)
      #expect(requests[0].httpMethod == "POST")
      #expect(authorization(requests[0]) == "ApiKey mein-key")
      #expect(authorization(requests[1]) == "Bearer \(longLivedToken)")
    }

    @Test func retriesOnceWithFreshTokenAfter401() async throws {
      let secrets = InMemorySecretStore([.garminAPIKey: "k"])
      StubURLProtocol.install { request in
        if request.url?.path().hasSuffix("/token") == true { return (200, longLivedToken) }
        let calls = StubURLProtocol.requests.filter { !($0.url?.path().hasSuffix("/token") ?? false) }.count
        return calls == 1 ? (401, "") : (200, "{}")
      }
      let client = GarminClient(secrets: secrets, session: StubURLProtocol.session())

      _ = try await client.json(.profileSettings)

      #expect(StubURLProtocol.requests.count == 4)
      #expect(secrets.string(for: .garminBearerToken) != nil)
    }

    @Test func rejectedKeyIsReportedClearly() async {
      StubURLProtocol.install { _ in (401, "") }
      let client = GarminClient(
        secrets: InMemorySecretStore([.garminAPIKey: "alt"]), session: StubURLProtocol.session())

      await #expect(throws: GarminAPIError.keyRejected) {
        _ = try await client.validToken()
      }
    }

    @Test func missingKeyFailsWithoutNetwork() async {
      StubURLProtocol.install { _ in (200, "") }
      let client = GarminClient(secrets: InMemorySecretStore(), session: StubURLProtocol.session())

      await #expect(throws: GarminAPIError.missingKey) {
        _ = try await client.validToken()
      }
      #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func syncStoresDaysActivitiesAndProfile() async throws {
      let now = CalendarDay(year: 2026, month: 10, day: 23).referenceDate
      let today = CalendarDay(date: now).iso
      StubURLProtocol.install { request in
        let path = request.url?.path() ?? ""
        switch true {
        case path.hasSuffix("/token"):
          return (200, longLivedToken)
        case path.hasSuffix("/v2/dailysummaries"):
          return (200, #"{"data": [{"calendarDate": "\#(today)", "restingHeartRate": 49, "totalSteps": 9000}]}"#)
        case path.contains("/hrv/daily/"):
          return (200, #"{"hrvSummaries": [{"calendarDate": "\#(today)", "lastNightAvg": 60, "status": "BALANCED"}]}"#)
        case path.contains("/activities/search"):
          return (
            200,
            #"[{"activityId": 7, "startTimeLocal": "\#(today) 07:00:00", "activityType": {"typeKey": "running"}}]"#
          )
        case path.hasSuffix("/userprofile/settings"):
          return (200, #"{"userData": {"weight": 80000, "gender": "MALE"}}"#)
        case path.contains("/bodyBattery/"):
          return (500, "")
        default:
          return (200, "[]")
        }
      }
      let container = CoachSchema.makeContainer(inMemory: true)
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let client = GarminClient(secrets: InMemorySecretStore([.garminAPIKey: "k"]), session: StubURLProtocol.session())
      let service = GarminSyncService(client: client, context: container.mainContext, defaults: defaults)

      let report = try await service.sync(now: now)

      #expect(report.range.dayCount == SyncPlan.initialDays)
      #expect(report.activitiesUpdated == 1)
      #expect(report.errors.count == 3)  // Body Battery in drei 28-Tage-Blöcken
      let records = try container.mainContext.fetch(FetchDescriptor<DailyMetricsRecord>())
      let metrics = try #require(records.first { $0.dayKey == today }?.metrics)
      #expect(metrics.restingHeartRate == 49)
      #expect(metrics.hrvStatus == "BALANCED")
      #expect(service.profile?.weightKilograms == 80)
      #expect(service.lastSync == now)
    }

    @Test func aiClientValidatesURLAndParsesResponse() async throws {
      let secrets = InMemorySecretStore()
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let client = AIClient(secrets: secrets, defaults: defaults, session: StubURLProtocol.session())

      #expect(throws: AIClientError.invalidURL) { try client.configure(url: "http://unsicher.example", token: "t") }
      try client.configure(url: " https://coach-ai.example.workers.dev/ ", token: "geheim")
      #expect(client.workerURL == "https://coach-ai.example.workers.dev")
      #expect(client.isConfigured)

      StubURLProtocol.install { _ in
        (200, #"{"output": {"ok": true, "gruss": "Hallo"}, "model": "gemini-3.6-flash", "provider": "gemini"}"#)
      }
      let response = try await client.run(task: "ping")

      #expect(response.output["gruss"]?.stringValue == "Hallo")
      let request = try #require(StubURLProtocol.requests.first)
      #expect(request.url?.absoluteString == "https://coach-ai.example.workers.dev/v1/ai/generate")
      #expect(authorization(request) == "Bearer geheim")
    }

    @Test func aiClientMapsUnauthorized() async throws {
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let client = AIClient(
        secrets: InMemorySecretStore([.aiAppToken: "falsch"]), defaults: defaults, session: StubURLProtocol.session())
      try client.configure(url: "https://coach-ai.example.workers.dev", token: "")
      StubURLProtocol.install { _ in (401, #"{"error": "Nicht autorisiert"}"#) }

      await #expect(throws: AIClientError.unauthorized) {
        _ = try await client.run(task: "ping")
      }
    }
  }
}
