import Foundation
import Testing

@testable import CoachCore

struct GarminEndpointTests {
  private let range = DateRange(
    start: CalendarDay(year: 2026, month: 9, day: 1),
    end: CalendarDay(year: 2026, month: 10, day: 22)
  )

  @Test func tokenExchangeMatchesOfficialClient() throws {
    let request = GarminEndpoint.tokenExchange.request
    #expect(request.method == "POST")
    #expect(request.path == "/personalapitoken-service/personal-api/personal-api-key/token")
    let url = try #require(request.url())
    #expect(
      url.absoluteString
        == "https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token")
  }

  @Test func rangeEndpointsUseQueryOrPath() throws {
    let summaries = try #require(GarminEndpoint.dailySummaries(range).request.url())
    #expect(
      summaries.absoluteString
        == "https://personal.connectapi.garmin.com/usersummary-service/v2/dailysummaries"
        + "?startDate=2026-09-01&endDate=2026-10-22")

    let hrv = GarminEndpoint.hrvSummaries(range).request
    #expect(hrv.path == "/hrv-service/hrv/daily/2026-09-01/2026-10-22")
    #expect(hrv.query.isEmpty)

    let sleep = GarminEndpoint.dailySleep(range.end).request
    #expect(sleep.path == "/sleep-service/sleep/dailySleep")
    #expect(sleep.query == [.init(name: "date", value: "2026-10-22")])
  }

  @Test func activitiesPageIsCapped() {
    let request = GarminEndpoint.activities(start: 0, limit: 200).request
    #expect(request.query.last == .init(name: "limit", value: "50"))
  }

  @Test func rangeLimits() {
    #expect(GarminEndpoint.sleepSummaries(range).maxDays == 28)
    #expect(GarminEndpoint.hrvSummaries(range).maxDays == 180)
    #expect(GarminEndpoint.hrv(range.end).maxDays == nil)
  }

  @Test func chunksCoverRangeNewestFirst() {
    let chunks = range.chunks(maxDays: 28)

    #expect(range.dayCount == 52)
    #expect(chunks.count == 2)
    #expect(chunks[0] == DateRange(start: CalendarDay(year: 2026, month: 9, day: 25), end: range.end))
    #expect(chunks[1] == DateRange(start: range.start, end: CalendarDay(year: 2026, month: 9, day: 24)))
    #expect(chunks.map(\.dayCount).reduce(0, +) == 52)
  }

  @Test func calendarDayArithmeticAcrossMonthAndYear() {
    let newYear = CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1)
    #expect(newYear == CalendarDay(year: 2027, month: 1, day: 1))
    #expect(CalendarDay(year: 2026, month: 3, day: 1).adding(days: -1) == CalendarDay(year: 2026, month: 2, day: 28))
    #expect(DateRange.last(7, endingOn: newYear).start == CalendarDay(year: 2026, month: 12, day: 26))
    #expect(CalendarDay(iso: "2026-10-22T00:00:00.0") == CalendarDay(year: 2026, month: 10, day: 22))
    #expect(CalendarDay(iso: "22.10.2026") == nil)
  }

  @Test func tokenExpiryFromJWT() throws {
    // Payload {"sub":"x","exp":1761220800} (2025-10-23T12:00:00Z), Base64URL ohne Padding.
    let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4IiwiZXhwIjoxNzYxMjIwODAwfQ.c2ln"
    let parsed = try #require(GarminBearerToken(responseBody: "  \(token)\n"))

    #expect(parsed.value == token)
    #expect(parsed.expiresAt == Date(timeIntervalSince1970: 1_761_220_800))
    #expect(parsed.needsRefresh(now: Date(timeIntervalSince1970: 1_761_220_800 - 3_000)))
    #expect(!parsed.needsRefresh(now: Date(timeIntervalSince1970: 1_761_220_800 - 7_200)))
  }

  @Test func tokenWithoutJWTUsesFallbackLifetime() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let parsed = try #require(GarminBearerToken(responseBody: "opaque", now: now))
    #expect(parsed.expiresAt == now.addingTimeInterval(GarminBearerToken.fallbackLifetime))
    #expect(GarminBearerToken(responseBody: " \n") == nil)
  }

  @Test(arguments: [
    (200, false, GarminAPIError?.none),
    (401, true, .keyRejected),
    (403, false, .unauthorized),
    (429, false, .rateLimited),
    (400, false, .rejectedRequest(status: 400)),
    (503, false, .server(status: 503)),
  ])
  func statusMapping(status: Int, isTokenExchange: Bool, expected: GarminAPIError?) {
    #expect(GarminAPIError.from(status: status, isTokenExchange: isTokenExchange) == expected)
  }
}
