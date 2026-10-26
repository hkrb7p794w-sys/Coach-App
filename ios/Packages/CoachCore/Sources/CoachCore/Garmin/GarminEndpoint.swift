import Foundation

/// HTTP-Anfrage ohne Abhängigkeit von `URLRequest` (das auf Linux in FoundationNetworking liegt).
public struct GarminRequest: Equatable, Sendable {
  public struct QueryItem: Equatable, Sendable {
    public let name: String
    public let value: String
  }

  public let method: String
  public let path: String
  public let query: [QueryItem]
  public let accept: String

  /// Vollständige URL relativ zur Basis-URL.
  public func url(base: String = GarminEndpoint.baseURL) -> URL? {
    var components = URLComponents(string: base + path)
    if !query.isEmpty {
      components?.queryItems = query.map { URLQueryItem(name: $0.name, value: $0.value) }
    }
    return components?.url
  }
}

/// Endpunkte der Garmin Connect Personal API.
///
/// Pfade und Parameter aus Garmins offiziellem Client
/// (github.com/garmin/connect-personal-api-python, `client.py`, `constants.py`, Stand 21.10.2026).
/// Bereichsgrenzen je Aufruf: was Garmins Server am 21.10.2026 akzeptierten
/// (github.com/Shape-Calendar/garmin-personal-mcp, README). Darüber antwortet Garmin mit 400/500.
public enum GarminEndpoint: Equatable, Sendable {
  public static let baseURL = "https://personal.connectapi.garmin.com"
  public static let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"
  /// Garmins Suche liefert oberhalb von ca. 60 Einträgen je Seite HTTP 500.
  public static let maxActivitiesPerPage = 50

  case tokenExchange
  case profileSettings
  case heartRateZones
  case dailySummaries(DateRange)
  case dailySleep(CalendarDay)
  case sleepSummaries(DateRange)
  case hrv(CalendarDay)
  case hrvSummaries(DateRange)
  case bodyBattery(DateRange)
  case dailyStress(DateRange)
  case dailyHeartRate(CalendarDay)
  case weight(DateRange)
  case activities(start: Int, limit: Int)
  case activity(id: Int64)
  case activityFile(id: Int64)

  /// Größter erlaubter Datumsbereich je Aufruf (nil = einzelner Tag oder kein Bereich).
  public var maxDays: Int? {
    switch self {
    case .dailySummaries, .hrvSummaries: 180
    case .sleepSummaries, .bodyBattery: 28
    case .dailyStress: 7
    case .weight: 365
    default: nil
    }
  }

  public var request: GarminRequest {
    func item(_ name: String, _ value: String) -> GarminRequest.QueryItem {
      GarminRequest.QueryItem(name: name, value: value)
    }
    let json = "application/json"
    switch self {
    case .tokenExchange:
      return GarminRequest(method: "POST", path: Self.tokenPath, query: [], accept: "*/*")
    case .profileSettings:
      return GarminRequest(method: "GET", path: "/userprofile-service/userprofile/settings", query: [], accept: json)
    case .heartRateZones:
      return GarminRequest(method: "GET", path: "/biometric-service/heartRateZones/v2", query: [], accept: json)
    case .dailySummaries(let range):
      return GarminRequest(
        method: "GET",
        path: "/usersummary-service/v2/dailysummaries",
        query: [item("startDate", range.start.iso), item("endDate", range.end.iso)],
        accept: json
      )
    case .dailySleep(let day):
      return GarminRequest(
        method: "GET",
        path: "/sleep-service/sleep/dailySleep",
        query: [item("date", day.iso)],
        accept: json
      )
    case .sleepSummaries(let range):
      return GarminRequest(
        method: "GET",
        path: "/sleep-service/sleep/dailySleepSummariesByDate",
        query: [item("startDate", range.start.iso), item("endDate", range.end.iso)],
        accept: json
      )
    case .hrv(let day):
      return GarminRequest(method: "GET", path: "/hrv-service/hrv/\(day.iso)", query: [], accept: json)
    case .hrvSummaries(let range):
      return GarminRequest(
        method: "GET",
        path: "/hrv-service/hrv/daily/\(range.start.iso)/\(range.end.iso)",
        query: [],
        accept: json
      )
    case .bodyBattery(let range):
      return GarminRequest(
        method: "GET",
        path: "/wellness-service/wellness/bodyBattery/reports/daily",
        query: [item("startDate", range.start.iso), item("endDate", range.end.iso)],
        accept: json
      )
    case .dailyStress(let range):
      return GarminRequest(
        method: "GET",
        path: "/usersummary-service/stats/stress/daily/\(range.start.iso)/\(range.end.iso)",
        query: [],
        accept: json
      )
    case .dailyHeartRate(let day):
      return GarminRequest(
        method: "GET",
        path: "/wellness-service/wellness/dailyHeartRate",
        query: [item("date", day.iso)],
        accept: json
      )
    case .weight(let range):
      return GarminRequest(
        method: "GET",
        path: "/weight-service/weight/range/\(range.start.iso)/\(range.end.iso)",
        query: [item("includeAll", "true")],
        accept: json
      )
    case .activities(let start, let limit):
      return GarminRequest(
        method: "GET",
        path: "/activitylist-service/activities/search/activities",
        query: [item("start", String(start)), item("limit", String(min(limit, Self.maxActivitiesPerPage)))],
        accept: json
      )
    case .activity(let id):
      return GarminRequest(method: "GET", path: "/activity-service/activity/\(id)", query: [], accept: json)
    case .activityFile(let id):
      return GarminRequest(
        method: "GET",
        path: "/download-service/files/activity/\(id)",
        query: [],
        accept: "application/zip, application/x-zip-compressed, application/octet-stream"
      )
    }
  }
}
