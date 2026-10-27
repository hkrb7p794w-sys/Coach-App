import Foundation
import Testing

@testable import CoachCore

/// Anfragen und Antworten des inoffiziellen Zugangs, abgeglichen mit python-garminconnect 0.3.20
/// (`client/sso.py`, `client/session.py`, `client/constants.py`).
struct GarminConnectTests {
  private func json(_ text: String) throws -> JSONValue {
    try JSONValue(data: Data(text.utf8))
  }

  private func components(_ request: GarminConnect.Request) throws -> URLComponents {
    try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
  }

  @Test func loginRequestsMatchMobileFlow() throws {
    let page = GarminConnect.signInPage
    #expect(page.method == "GET")
    #expect(page.url.host() == "sso.garmin.com")
    #expect(page.url.path() == "/mobile/sso/en_US/sign-in")
    #expect(try components(page).queryItems?.first { $0.name == "clientId" }?.value == "GCM_IOS_DARK")

    let login = GarminConnect.login(email: "a@b.de", password: "p&ss")
    #expect(login.method == "POST")
    #expect(login.url.path() == "/mobile/api/login")
    let query = try components(login).queryItems ?? []
    #expect(query.contains(URLQueryItem(name: "service", value: "https://mobile.integration.garmin.com/gcm/ios")))
    #expect(query.contains(URLQueryItem(name: "locale", value: "en-US")))
    #expect(login.headers["Referer"] == page.url.absoluteString)
    #expect(login.headers["Content-Type"] == "application/json")
    let body = try JSONValue(data: try #require(login.body))
    #expect(body["username"]?.stringValue == "a@b.de")
    #expect(body["password"]?.stringValue == "p&ss")
    #expect(body["rememberMe"] == .bool(true))

    let code = GarminConnect.verifyCode("123456", method: "email")
    #expect(code.url.path() == "/mobile/api/mfa/verifyCode")
    let codeBody = try JSONValue(data: try #require(code.body))
    #expect(codeBody["mfaVerificationCode"]?.stringValue == "123456")
    #expect(codeBody["mfaMethod"]?.stringValue == "email")
  }

  @Test func loginResponsesAreClassified() throws {
    func result(_ status: Int, _ text: String) -> GarminConnect.LoginResult {
      GarminConnect.loginResult(status: status, body: Data(text.utf8))
    }
    #expect(result(200, #"{"responseStatus":{"type":"SUCCESSFUL"},"serviceTicketId":"ST-1"}"#) == .ticket("ST-1"))
    #expect(
      result(200, #"{"responseStatus":{"type":"MFA_REQUIRED"},"customerMfaInfo":{"mfaLastMethodUsed":"sms"}}"#)
        == .needsCode(method: "sms"))
    #expect(result(200, #"{"responseStatus":{"type":"MFA_REQUIRED"}}"#) == .needsCode(method: "email"))
    #expect(result(200, #"{"responseStatus":{"type":"INVALID_USERNAME_PASSWORD"}}"#) == .invalidCredentials)
    if case .blocked = result(200, #"{"responseStatus":{"type":"CAPTCHA_REQUIRED"}}"#) {
    } else {
      Issue.record("Captcha muss als Blockade gelten")
    }
    if case .blocked = result(429, "") {} else { Issue.record("429 muss als Blockade gelten") }
    if case .blocked = result(403, "<html>") {} else { Issue.record("403 muss als Blockade gelten") }
    if case .blocked = result(200, #"{"error":{"status-code":"429"}}"#) {
    } else {
      Issue.record("429 im JSON muss als Blockade gelten")
    }
    if case .unexpected = result(200, "<html>") {} else { Issue.record("HTML ist unerwartet") }
    if case .unexpected = result(200, #"{"responseStatus":{"type":"SUCCESSFUL"}}"#) {
    } else {
      Issue.record("Erfolg ohne Ticket ist unerwartet")
    }
  }

  @Test func tokenExchangeAndRefreshRequests() throws {
    let exchange = GarminConnect.exchange(ticket: "ST-1", clientID: "GARMIN_CONNECT_MOBILE_IOS_DI")
    #expect(exchange.url.absoluteString == "https://diauth.garmin.com/di-oauth2-service/oauth/token")
    #expect(
      exchange.headers["Authorization"]
        == "Basic " + Data("GARMIN_CONNECT_MOBILE_IOS_DI:".utf8).base64EncodedString())
    #expect(exchange.headers["Content-Type"] == "application/x-www-form-urlencoded")
    let form = String(decoding: try #require(exchange.body), as: UTF8.self)
    #expect(form.contains("service_ticket=ST-1"))
    #expect(form.contains("service_url=https%3A%2F%2Fmobile.integration.garmin.com%2Fgcm%2Fios"))
    #expect(
      form.contains(
        "grant_type=https%3A%2F%2Fconnectapi.garmin.com%2Fdi-oauth2-service%2Foauth%2Fgrant%2Fservice_ticket"))

    let token = GarminConnect.Token(
      accessToken: "a", refreshToken: "r+1", clientID: "C", expiresAt: Date(timeIntervalSince1970: 0))
    let refresh = try #require(GarminConnect.refresh(token))
    let refreshForm = String(decoding: try #require(refresh.body), as: UTF8.self)
    #expect(refreshForm == "grant_type=refresh_token&client_id=C&refresh_token=r%2B1")
    var withoutRefresh = token
    withoutRefresh.refreshToken = nil
    #expect(GarminConnect.refresh(withoutRefresh) == nil)
  }

  @Test func tokenReadsJWTClaims() throws {
    // Payload {"client_id":"GARMIN_CONNECT_MOBILE_IOS_DI","exp":4102444800}
    let jwt =
      "eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln"
    let token = try #require(
      GarminConnect.Token(
        response: Data(#"{"access_token":"\#(jwt)","refresh_token":"r"}"#.utf8), clientID: "OTHER"))
    #expect(token.clientID == "GARMIN_CONNECT_MOBILE_IOS_DI")
    #expect(token.expiresAt == Date(timeIntervalSince1970: 4_102_444_800))
    #expect(!token.needsRefresh(now: Date(timeIntervalSince1970: 4_102_444_800 - 3_600)))
    #expect(token.needsRefresh(now: Date(timeIntervalSince1970: 4_102_444_800 - 600)))

    let now = Date(timeIntervalSince1970: 1_000)
    let plain = try #require(
      GarminConnect.Token(response: Data(#"{"access_token":"x","expires_in":7200}"#.utf8), clientID: "C", now: now))
    #expect(plain.clientID == "C")
    #expect(plain.expiresAt == now.addingTimeInterval(7_200))
    #expect(GarminConnect.Token(response: Data("{}".utf8), clientID: "C") == nil)
  }

  @Test func apiRequestsUseBearerAndConnectPaths() throws {
    let token = GarminConnect.Token(accessToken: "abc", refreshToken: nil, clientID: "C", expiresAt: .distantFuture)
    let day = CalendarDay(year: 2026, month: 10, day: 26)
    let readiness = ConnectEndpoint.trainingReadiness(day)
    let request = GarminConnect.apiRequest(
      path: readiness.path, query: readiness.query, token: token, accept: "application/json")
    #expect(
      request.url.absoluteString == "https://connectapi.garmin.com/metrics-service/metrics/trainingreadiness/2026-10-26"
    )
    #expect(request.headers["Authorization"] == "Bearer abc")
    #expect(request.headers["X-Garmin-Client-Platform"] == "Android")

    let endurance = ConnectEndpoint.enduranceScore(day)
    let enduranceURL = GarminConnect.apiRequest(
      path: endurance.path, query: endurance.query, token: token, accept: "application/json"
    ).url.absoluteString
    #expect(
      enduranceURL == "https://connectapi.garmin.com/metrics-service/metrics/endurancescore?calendarDate=2026-10-26")
    #expect(
      ConnectEndpoint.racePredictions(displayName: "a/b").path == "/metrics-service/metrics/racepredictions/latest/ab")
    #expect(ConnectEndpoint.userSummary(displayName: "alex", day: day).query.first?.value == "2026-10-26")
    let weights = ConnectEndpoint.weightRange(start: day.adding(days: -27), end: day)
    #expect(weights.path == "/weight-service/weight/range/2026-09-29/2026-10-26")
    #expect(weights.query.first?.name == "includeAll")
  }

  @Test func parsesConnectOnlyValues() throws {
    let day = CalendarDay(year: 2026, month: 10, day: 26)
    let readiness = GarminMetricsParser.trainingReadiness(
      try json(#"[{"calendarDate":"2026-10-26","score":71,"level":"HIGH"}]"#), day: day)
    #expect(readiness[day]?.trainingReadiness == 71)
    #expect(readiness[day]?.trainingReadinessLevel == "HIGH")
    #expect(GarminMetricsParser.trainingReadiness(try json("[]"), day: day).isEmpty)

    let status = GarminMetricsParser.trainingStatus(
      try json(
        #"{"mostRecentTrainingStatus":{"latestTrainingStatusData":{"3442":{"trainingStatusFeedbackPhrase":"PRODUCTIVE_3"}}}}"#
      ), day: day)
    #expect(status[day]?.trainingStatus == "PRODUCTIVE_3")
    #expect(GarminMetricsParser.trainingStatusGerman("PRODUCTIVE_3") == "Produktiv")
    #expect(GarminMetricsParser.trainingStatusGerman("UNPRODUCTIVE_1") == "Unproduktiv")
    #expect(GarminMetricsParser.trainingStatusGerman("NEW_THING") == "New Thing")

    #expect(
      GarminMetricsParser.enduranceScore(try json(#"{"overallScore":6512}"#), day: day)[day]?.enduranceScore == 6512)
    #expect(
      GarminMetricsParser.enduranceScore(try json(#"{"enduranceScoreDTO":{"overallScore":6400}}"#), day: day)[day]?
        .enduranceScore == 6400)

    let predictions = try #require(
      RacePredictions(
        json: try json(
          #"{"calendarDate":"2026-10-26","time5K":1250,"time10K":2620,"timeHalfMarathon":5900,"timeMarathon":12600}"#)))
    #expect(predictions.fiveK == 1250)
    #expect(predictions.marathon == 12600)
    #expect(predictions.day == day)
    #expect(RacePredictions(json: try json("{}")) == nil)
  }

  @Test func readinessFromMetricsFeedsRecommendation() {
    var metrics = DailyMetrics(day: CalendarDay(year: 2026, month: 10, day: 26))
    metrics.hrvStatus = "BALANCED"
    metrics.trainingReadiness = 20
    let recommendation = RecoveryEvaluator.evaluate(metrics, restingHeartRate7DayAverage: nil)
    #expect(recommendation.level == .pause)
    #expect(recommendation.reasons.contains { $0.hasPrefix("Readiness 20") })
  }
}
