import Foundation

/// Inoffizieller Zugang zu Garmin Connect wie die Garmin-Connect-App auf dem iPhone (Anmeldung mit E-Mail und
/// Passwort, optional Bestätigungscode). Liefert mehr als die Personal API (Training Readiness,
/// Trainingsstatus, Endurance Score, Wettkampfprognosen). Die Personal API bleibt der Rückfallweg.
///
/// Ablauf nach python-garminconnect 0.3.20 (Strategie „mobile“, `client/sso.py`, `client/session.py`,
/// `client/constants.py`, Stand 23.10.2026), seit Garmin im März 2026 den alten OAuth1-Weg (garth) abgeschaltet hat:
/// 1. `GET sso.garmin.com/mobile/sso/en_US/sign-in` (setzt Cookies, wie die WebView der App),
/// 2. `POST sso.garmin.com/mobile/api/login` mit JSON → Service-Ticket oder `MFA_REQUIRED`,
/// 3. ggf. `POST …/mobile/api/mfa/verifyCode`,
/// 4. Ticket gegen ein DI-OAuth2-Token tauschen (`diauth.garmin.com`), Erneuerung per Refresh-Token,
/// 5. Abrufe auf `connectapi.garmin.com` mit `Authorization: Bearer`.
public enum GarminConnect {
  public static let ssoBase = "https://sso.garmin.com"
  public static let apiBase = "https://connectapi.garmin.com"
  public static let ssoClientID = "GCM_IOS_DARK"
  public static let serviceURL = "https://mobile.integration.garmin.com/gcm/ios"
  public static let loginUserAgent =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
  public static let grantType = "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"
  /// Reihenfolge wie im Vorbild, die iOS-Kennung zuerst (die App läuft auf einem iPhone).
  public static let diClientIDs = [
    "GARMIN_CONNECT_MOBILE_IOS_DI",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI",
  ]

  /// HTTP-Anfrage mit vollständiger Adresse (verschiedene Garmin-Hosts).
  public struct Request: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
  }

  // MARK: - Anmeldung

  /// Adresse aus festen Garmin-Hosts; `base` ist immer eine der Konstanten oben.
  static func url(_ base: String, _ path: String, _ query: [(String, String)] = []) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = base.replacingOccurrences(of: "https://", with: "").components(separatedBy: "/")[0]
    components.path = path
    if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
    return components.url ?? URL(fileURLWithPath: "/")
  }

  static var signInQuery: [(String, String)] { [("clientId", ssoClientID), ("service", serviceURL)] }
  static var apiQuery: [(String, String)] {
    [("clientId", ssoClientID), ("locale", "en-US"), ("service", serviceURL)]
  }

  public static var signInPage: Request {
    Request(
      method: "GET", url: url(ssoBase, "/mobile/sso/en_US/sign-in", signInQuery),
      headers: [
        "User-Agent": loginUserAgent,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
      ])
  }

  static var jsonHeaders: [String: String] {
    [
      "User-Agent": loginUserAgent,
      "Accept": "application/json, text/plain, */*",
      "Accept-Language": "en-US,en;q=0.9",
      "Content-Type": "application/json",
      "Origin": ssoBase,
      "Referer": signInPage.url.absoluteString,
    ]
  }

  public static func login(email: String, password: String) -> Request {
    let body: JSONValue = .object([
      "username": .string(email), "password": .string(password), "rememberMe": .bool(true),
      "captchaToken": .string(""),
    ])
    return Request(
      method: "POST", url: url(ssoBase, "/mobile/api/login", apiQuery), headers: jsonHeaders,
      body: try? JSONEncoder().encode(body))
  }

  public static func verifyCode(_ code: String, method: String) -> Request {
    let body: JSONValue = .object([
      "mfaMethod": .string(method), "mfaVerificationCode": .string(code), "rememberMyBrowser": .bool(true),
      "reconsentList": .array([]), "mfaSetup": .bool(false),
    ])
    return Request(
      method: "POST", url: url(ssoBase, "/mobile/api/mfa/verifyCode", apiQuery), headers: jsonHeaders,
      body: try? JSONEncoder().encode(body))
  }

  public enum LoginResult: Equatable, Sendable {
    case ticket(String)
    /// Bestätigungscode nötig; `method` z. B. `email` oder `sms`.
    case needsCode(method: String)
    case invalidCredentials
    /// Garmin blockiert (Captcha, Cloudflare, Rate-Limit) – später erneut versuchen.
    case blocked(String)
    case unexpected(String)
  }

  /// Antwort von `/mobile/api/login` und `/mfa/verifyCode`.
  public static func loginResult(status: Int, body: Data) -> LoginResult {
    if status == 429 || status == 427 { return .blocked("zu viele Anmeldeversuche (HTTP \(status))") }
    if status == 403 { return .blocked("Garmin hat die Anmeldung blockiert (HTTP 403)") }
    guard let json = try? JSONValue(data: body) else { return .unexpected("keine JSON-Antwort (HTTP \(status))") }
    if json["error"]?["status-code"]?.stringValue == "429" { return .blocked("zu viele Anmeldeversuche") }
    switch json["responseStatus"]?["type"]?.stringValue {
    case "SUCCESSFUL":
      guard let ticket = json["serviceTicketId"]?.stringValue, !ticket.isEmpty else {
        return .unexpected("Anmeldung ohne Ticket")
      }
      return .ticket(ticket)
    case "MFA_REQUIRED":
      return .needsCode(method: json["customerMfaInfo"]?["mfaLastMethodUsed"]?.stringValue ?? "email")
    case "INVALID_USERNAME_PASSWORD":
      return .invalidCredentials
    case "CAPTCHA_REQUIRED":
      return .blocked("Garmin verlangt ein Captcha")
    case let other:
      return .unexpected("HTTP \(status), Status \(other ?? "unbekannt")")
    }
  }

  // MARK: - Token

  /// Kopfzeilen der Garmin-Connect-App für Token- und API-Abrufe (`_native_headers`).
  public static var nativeHeaders: [String: String] {
    [
      "User-Agent": "GCM-Android-5.23",
      "X-Garmin-User-Agent":
        "com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0",
      "X-Garmin-Paired-App-Version": "10861",
      "X-Garmin-Client-Platform": "Android",
      "X-App-Ver": "10861",
      "X-Lang": "en",
      "X-GCExperience": "GC5",
      "Accept-Language": "en-US,en;q=0.9",
    ]
  }

  static func form(_ fields: [(String, String)]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let text = fields.map { name, value in
      "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
    }
    return Data(text.joined(separator: "&").utf8)
  }

  static func tokenRequest(clientID: String, fields: [(String, String)], accept: String) -> Request {
    var headers = nativeHeaders
    headers["Authorization"] = "Basic " + Data("\(clientID):".utf8).base64EncodedString()
    headers["Accept"] = accept
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    headers["Cache-Control"] = "no-cache"
    return Request(
      method: "POST", url: url("https://diauth.garmin.com", "/di-oauth2-service/oauth/token"), headers: headers,
      body: form(fields))
  }

  public static func exchange(ticket: String, clientID: String) -> Request {
    tokenRequest(
      clientID: clientID,
      fields: [
        ("client_id", clientID), ("service_ticket", ticket), ("grant_type", grantType), ("service_url", serviceURL),
      ],
      accept: "application/json,text/html;q=0.9,*/*;q=0.8")
  }

  public static func refresh(_ token: Token) -> Request? {
    guard let refreshToken = token.refreshToken else { return nil }
    return tokenRequest(
      clientID: token.clientID,
      fields: [("grant_type", "refresh_token"), ("client_id", token.clientID), ("refresh_token", refreshToken)],
      accept: "application/json")
  }

  /// DI-OAuth2-Token; liegt nur im Schlüsselbund.
  public struct Token: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var clientID: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, clientID: String, expiresAt: Date) {
      self.accessToken = accessToken
      self.refreshToken = refreshToken
      self.clientID = clientID
      self.expiresAt = expiresAt
    }

    /// Antwort des Token-Endpunkts; `client_id` aus dem JWT hat Vorrang (wie im Vorbild).
    public init?(response body: Data, clientID: String, now: Date = .now) {
      guard let json = try? JSONValue(data: body), let access = json["access_token"]?.stringValue, !access.isEmpty
      else { return nil }
      accessToken = access
      refreshToken = json["refresh_token"]?.stringValue
      self.clientID = Self.jwtClaim(access, "client_id")?.stringValue ?? clientID
      if let exp = Self.jwtClaim(access, "exp")?.doubleValue {
        expiresAt = Date(timeIntervalSince1970: exp)
      } else if let seconds = json["expires_in"]?.doubleValue {
        expiresAt = now.addingTimeInterval(seconds)
      } else {
        expiresAt = now.addingTimeInterval(3_600)
      }
    }

    /// Erneuern, wenn weniger als 15 Minuten bleiben (`_token_expires_soon`).
    public func needsRefresh(now: Date = .now) -> Bool {
      expiresAt.timeIntervalSince(now) < 900
    }

    static func jwtClaim(_ token: String, _ name: String) -> JSONValue? {
      let parts = token.split(separator: ".")
      guard parts.count >= 2 else { return nil }
      var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
      guard let data = Data(base64Encoded: base64), let payload = try? JSONValue(data: data) else { return nil }
      return payload[name]
    }
  }

  // MARK: - Abrufe

  /// Abruf auf connectapi; die Pfade der Personal API sind dieselben wie in Garmin Connect.
  public static func apiRequest(path: String, query: [GarminRequest.QueryItem], token: Token, accept: String)
    -> Request
  {
    var headers = nativeHeaders
    headers["Authorization"] = "Bearer \(token.accessToken)"
    headers["Accept"] = accept
    return Request(
      method: "GET", url: url(apiBase, path, query.map { ($0.name, $0.value) }), headers: headers, body: nil)
  }
}

/// Endpunkte, die es nur über den Garmin-Connect-Zugang gibt (python-garminconnect `api/base.py`).
public enum ConnectEndpoint: Equatable, Sendable {
  case socialProfile
  case trainingReadiness(CalendarDay)
  case trainingStatus(CalendarDay)
  case enduranceScore(CalendarDay)
  case racePredictions(displayName: String)
  /// Tageszusammenfassung und Schlaf in der Form von Garmin Connect (die Personal-API-Pfade
  /// `v2/dailysummaries` und `dailySleep` sind dort nicht sicher verfügbar).
  case userSummary(displayName: String, day: CalendarDay)
  case dailySleepData(displayName: String, day: CalendarDay)
  /// Wägungen eines Zeitraums (Waage, Garmin-App oder Eingabe in Connect).
  case weightRange(start: CalendarDay, end: CalendarDay)

  public var path: String {
    switch self {
    case .socialProfile: "/userprofile-service/socialProfile"
    case .trainingReadiness(let day): "/metrics-service/metrics/trainingreadiness/\(day.iso)"
    case .trainingStatus(let day): "/metrics-service/metrics/trainingstatus/aggregated/\(day.iso)"
    case .enduranceScore: "/metrics-service/metrics/endurancescore"
    // URLComponents kodiert den Pfad selbst; Schrägstriche im Namen würden den Pfad verlassen.
    case .racePredictions(let name):
      "/metrics-service/metrics/racepredictions/latest/" + Self.safe(name)
    case .userSummary(let name, _): "/usersummary-service/usersummary/daily/" + Self.safe(name)
    case .dailySleepData(let name, _): "/wellness-service/wellness/dailySleepData/" + Self.safe(name)
    case .weightRange(let start, let end): "/weight-service/weight/range/\(start.iso)/\(end.iso)"
    }
  }

  public var query: [GarminRequest.QueryItem] {
    switch self {
    case .enduranceScore(let day), .userSummary(_, let day):
      [GarminRequest.QueryItem(name: "calendarDate", value: day.iso)]
    case .dailySleepData(_, let day):
      [
        GarminRequest.QueryItem(name: "date", value: day.iso),
        GarminRequest.QueryItem(name: "nonSleepBufferMinutes", value: "60"),
      ]
    case .weightRange:
      [GarminRequest.QueryItem(name: "includeAll", value: "true")]
    default:
      []
    }
  }

  static func safe(_ name: String) -> String {
    name.replacingOccurrences(of: "/", with: "")
  }
}

/// Wettkampfprognosen der Uhr in Sekunden.
public struct RacePredictions: Codable, Equatable, Sendable {
  public var fiveK: Double?
  public var tenK: Double?
  public var halfMarathon: Double?
  public var marathon: Double?
  public var day: CalendarDay?

  public init() {}

  public init?(json: JSONValue) {
    let record = json.arrayValue?.last ?? json
    func time(_ key: String) -> Double? { record[key]?.doubleValue.flatMap { $0 > 0 ? $0 : nil } }
    fiveK = time("time5K")
    tenK = time("time10K")
    halfMarathon = time("timeHalfMarathon")
    marathon = time("timeMarathon")
    day = (record["calendarDate"]?.stringValue).flatMap { CalendarDay(iso: String($0.prefix(10))) }
    if fiveK == nil, tenK == nil, halfMarathon == nil, marathon == nil { return nil }
  }
}

extension GarminMetricsParser {
  /// `/metrics-service/metrics/trainingreadiness/{date}`: Liste mit einem Eintrag je Messung (`score`, `level`).
  public static func trainingReadiness(_ json: JSONValue, day: CalendarDay) -> DayMap {
    let entries = json.arrayValue ?? [json]
    guard let first = entries.first(where: { $0["score"]?.doubleValue != nil }),
      let score = first["score"]?.doubleValue, score > 0
    else { return [:] }
    var metrics = DailyMetrics(day: day)
    metrics.trainingReadiness = score
    metrics.trainingReadinessLevel = first["level"]?.stringValue
    return [day: metrics]
  }

  /// `/metrics-service/metrics/trainingstatus/aggregated/{date}`: Status je Gerät unter einer Geräte-ID.
  public static func trainingStatus(_ json: JSONValue, day: CalendarDay) -> DayMap {
    guard case .object(let devices)? = json["mostRecentTrainingStatus"]?["latestTrainingStatusData"],
      let phrase = devices.keys.sorted().lazy.compactMap({ devices[$0]?["trainingStatusFeedbackPhrase"]?.stringValue })
        .first
    else { return [:] }
    var metrics = DailyMetrics(day: day)
    metrics.trainingStatus = phrase
    return [day: metrics]
  }

  /// `/metrics-service/metrics/endurancescore?calendarDate=`: `overallScore`, auch unter `enduranceScoreDTO`.
  public static func enduranceScore(_ json: JSONValue, day: CalendarDay) -> DayMap {
    let value =
      json["overallScore"]?.doubleValue ?? json["enduranceScoreDTO"]?["overallScore"]?.doubleValue
      ?? json["avg"]?.doubleValue ?? json["max"]?.doubleValue
    guard let value, value > 0 else { return [:] }
    var metrics = DailyMetrics(day: day)
    metrics.enduranceScore = value
    return [day: metrics]
  }

  /// Garmins Trainingsstatus auf Deutsch (Altbestand `TRAINING_STATUS_DE`, z. B. `PRODUCTIVE_3`).
  public static func trainingStatusGerman(_ phrase: String) -> String {
    let names: [(String, String)] = [
      ("PRODUCTIVE", "Produktiv"), ("MAINTAINING", "Erhaltend"), ("RECOVERY", "Erholung"),
      ("UNPRODUCTIVE", "Unproduktiv"), ("DETRAINING", "Formverlust"), ("PEAKING", "Formhöhepunkt"),
      ("OVERREACHING", "Überlastung"), ("STRAINED", "Überbeansprucht"), ("NO_STATUS", "Kein Status"),
      ("PAUSED", "Pausiert"),
    ]
    let code = phrase.uppercased()
    return names.first { code.hasPrefix($0.0) }?.1 ?? phrase.replacingOccurrences(of: "_", with: " ").capitalized
  }
}
