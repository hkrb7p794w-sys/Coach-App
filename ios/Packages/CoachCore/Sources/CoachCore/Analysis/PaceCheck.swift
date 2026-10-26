import Foundation

/// Hinweis, ob die Schwellenpace (und damit die Intervallpace: Schwelle −23 bis −18 s/km) angepasst werden
/// sollte – wie im Altbestand (`pace_check.py`). Bewusst konservativ, der Feldtest bleibt der Goldstandard.
///
/// - Schwellenläufe: Aus Tempo und Ø-HF der Arbeitsrunden wird linear über die Herzfrequenzreserve das Tempo
///   bei der Schwellen-HF (LTHR) geschätzt, nur bei Ø-HF zwischen 90 und 103 % der LTHR.
/// - 4×4-Läufe: Ziel sind 90–95 % HFmax (Helgerud et al. 2007). Das ergibt nur eine Richtung.
/// - Ein Vorschlag braucht mindestens zwei Einheiten in dieselbe Richtung und ≥ 5 s/km Abweichung; höchstens
///   10 s/km je Schritt, auf 5 s gerundet. RPE ≥ 9 bremst „schneller“ aus.
public enum PaceCheck {
  public static let lookbackDays = 42
  public static let minSessions = 2
  public static let minDeltaSeconds = 5.0
  public static let maxStepSeconds = 10.0

  public enum Kind: String, Codable, Sendable {
    case threshold, vo2
  }

  /// Kompakte Runde (`laps_compact`): Dauer und Distanz gerundet.
  public struct Lap: Codable, Equatable, Sendable {
    public var duration: Double
    public var distance: Double
    public var heartRate: Double?
    public var maxHeartRate: Double?
    public var isWork: Bool?

    public init(duration: Double, distance: Double, heartRate: Double?, maxHeartRate: Double?, isWork: Bool?) {
      self.duration = duration
      self.distance = distance
      self.heartRate = heartRate
      self.maxHeartRate = maxHeartRate
      self.isWork = isWork
    }

    /// Aus der FIT-Datei; Runden ohne Dauer oder Distanz fallen weg.
    public static func from(_ laps: [FitLap]) -> [Lap] {
      laps.compactMap { lap in
        guard let duration = lap.timerSeconds ?? lap.elapsedSeconds, duration > 0,
          let distance = lap.distanceMeters, distance > 0
        else { return nil }
        return Lap(
          duration: duration.rounded(.toNearestOrEven), distance: distance.rounded(.toNearestOrEven),
          heartRate: lap.averageHeartRate, maxHeartRate: lap.maxHeartRate,
          isWork: lap.intensity.map { _ in lap.isWork })
      }
    }
  }

  public struct Session: Codable, Equatable, Sendable {
    public var id: Int64
    public var day: CalendarDay
    public var name: String?
    public var kind: Kind
    public var rpe: Double?
    public var laps: [Lap]

    public init(id: Int64, day: CalendarDay, name: String?, kind: Kind, rpe: Double?, laps: [Lap]) {
      self.id = id
      self.day = day
      self.name = name
      self.kind = kind
      self.rpe = rpe
      self.laps = laps
    }
  }

  public struct Row: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var day: CalendarDay
    public var name: String?
    public var kind: Kind
    public var workMinutes: Int?
    public var workPace: Int?
    public var workHeartRate: Int?
    public var heartRatePercentOfThreshold: Int?
    public var estimatedThreshold: Int?
    public var repetitionPeakPercentOfMax: Int?
    public var verdict: String
  }

  public enum Status: String, Sendable {
    case fits = "passt"
    case faster = "schneller"
    case slower = "langsamer"
    case tooFewData = "zu wenig Daten"
  }

  public struct Result: Equatable, Sendable {
    public var status: Status
    public var current: Int
    public var rows: [Row]
    public var suggested: Int?
    public var reason: String?

    public var intervalBand: String { Self.band(current) }
    public var suggestedIntervalBand: String? { suggested.map(Self.band) }

    static func band(_ threshold: Int) -> String {
      "\(PlanTokens.mmss(threshold - 23))–\(PlanTokens.mmss(threshold - 18))"
    }
  }

  /// Arbeitsrunden: bei strukturierten Workouts laut Uhr (ab 2 min), sonst Runden ab 150 s, die schneller
  /// sind als Schwelle + 30 s/km.
  public static func workLaps(_ laps: [Lap], thresholdPace: Int) -> [Lap] {
    let typed = laps.filter { $0.isWork == true }
    if !typed.isEmpty { return typed.filter { $0.duration >= 120 } }
    let limit = Double(thresholdPace + 30)
    return laps.filter { $0.duration >= 150 && $0.distance > 0 && $0.duration / $0.distance * 1000 <= limit }
  }

  public static func evaluate(
    _ sessions: [Session], thresholdPace: Int, lthr: Double?, maxHeartRate: Double?, restingHeartRate: Double
  ) -> Result {
    var rows: [Row] = []
    var estimates: [Double] = []
    var directions: [Int] = []
    let intervalSlowEnd = Double(thresholdPace - 18)
    let current = Double(thresholdPace)

    for session in sessions {
      var row = Row(id: session.id, day: session.day, name: session.name, kind: session.kind, verdict: "passt")
      let work = workLaps(session.laps, thresholdPace: thresholdPace)
      guard !work.isEmpty else {
        row.verdict = "keine Arbeitsrunden erkannt"
        rows.append(row)
        continue
      }
      let duration = work.reduce(0) { $0 + $1.duration }
      let pace = duration / work.reduce(0) { $0 + $1.distance } * 1000
      let withHeart = work.compactMap { lap in lap.heartRate.map { ($0, lap.duration) } }
      let heart: Double? =
        withHeart.isEmpty
        ? nil : withHeart.reduce(0) { $0 + $1.0 * $1.1 } / withHeart.reduce(0) { $0 + $1.1 }
      row.workMinutes = pyRound(duration / 60)
      row.workPace = pyRound(pace)
      row.workHeartRate = heart.map(pyRound)

      switch session.kind {
      case .threshold:
        if let heart, let lthr, lthr > 0, restingHeartRate > 0, (0.90...1.03).contains(heart / lthr) {
          let speedAtThreshold = 1000 / pace * (lthr - restingHeartRate) / (heart - restingHeartRate)
          let estimate = 1000 / speedAtThreshold
          row.heartRatePercentOfThreshold = pyRound(heart / lthr * 100)
          row.estimatedThreshold = pyRound(estimate)
          if let rpe = session.rpe, rpe >= 9, estimate < current {
            row.verdict = "RPE ≥ 9 – keine Empfehlung „schneller“ aus dieser Einheit"
          } else {
            estimates.append(estimate)
            row.verdict =
              estimate < current - minDeltaSeconds
              ? "Schwelle eher schneller" : estimate > current + minDeltaSeconds ? "Schwelle eher langsamer" : "passt"
          }
        } else {
          row.verdict = heart == nil ? "ohne HF" : "HF außerhalb 90–103 % LTHR – nicht auswertbar"
        }
      case .vo2:
        guard let maxHeartRate, maxHeartRate > 0 else { break }
        let peaks = work.compactMap(\.maxHeartRate)
        let peak = peaks.isEmpty ? nil : peaks.reduce(0, +) / Double(peaks.count)
        row.repetitionPeakPercentOfMax = peak.map { pyRound($0 / maxHeartRate * 100) }
        if let peak, peak < 0.90 * maxHeartRate, pace <= intervalSlowEnd {
          directions.append(-1)
          row.verdict = "Ziel-HF nicht erreicht trotz Pace im Band – Band zu langsam"
        } else if let peak, peak > 0.96 * maxHeartRate, pace > intervalSlowEnd + 5 {
          directions.append(1)
          row.verdict = "HF über Ziel, Pace langsamer als Band – Band zu schnell"
        }
      }
      rows.append(row)
    }

    var result = Result(status: .fits, current: thresholdPace, rows: Array(rows.suffix(10)))
    if estimates.count >= minSessions {
      let target = median(estimates)
      let delta = target - current
      let votes = estimates.filter { ($0 - current) * delta > 0 && abs($0 - current) >= minDeltaSeconds }.count
      let vo2Agree = directions.filter { Double($0) * delta > 0 }.count
      if abs(delta) >= minDeltaSeconds && votes + vo2Agree >= minSessions {
        let step = max(-maxStepSeconds, min(maxStepSeconds, delta))
        let suggested = 5 * pyRound((current + step) / 5)
        if suggested != thresholdPace {
          result.status = suggested < thresholdPace ? .faster : .slower
          result.suggested = suggested
          var reason =
            "\(votes) Schwellenläufe der letzten \(lookbackDays / 7) Wochen ergeben bei deiner Schwellen-HF "
            + "\(Int(lthr ?? 0)) bpm im Median \(PlanTokens.mmss(pyRound(target))) /km"
          if vo2Agree > 0 { reason += ", \(vo2Agree) 4×4-Lauf/-Läufe zeigen in dieselbe Richtung" }
          result.reason = reason + "."
        }
      }
    } else if estimates.count + directions.count < minSessions {
      result.status = .tooFewData
    } else if let first = directions.first, directions.allSatisfy({ $0 == first }), directions.count >= minSessions {
      result.suggested = thresholdPace + 5 * first
      result.status = first < 0 ? .faster : .slower
      result.reason = "\(directions.count) 4×4-Läufe zeigen dieselbe Richtung (Ziel-HF 90–95 % HFmax)."
    }
    return result
  }

  /// Vorschlagstext wie im Vorschlags-Pool des Altbestands (`suggestion`).
  public static func suggestionText(_ result: Result) -> (title: String, text: String)? {
    guard let suggested = result.suggested, let reason = result.reason, let band = result.suggestedIntervalBand
    else { return nil }
    let word = result.status == .faster ? "schneller" : "langsamer"
    let title =
      "Schwellenpace auf \(PlanTokens.mmss(suggested)) /km (\(word), bisher \(PlanTokens.mmss(result.current)))"
    let text =
      "\(reason) Annehmen trägt \(PlanTokens.mmss(suggested)) /km als Schwellenpace ein; die Intervallpace für "
      + "4×4 wird damit \(band) /km (bisher \(result.intervalBand)). Den nächsten 30-min-Test als Bestätigung "
      + "nutzen."
    return (title, text)
  }

  static func pyRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
  }

  static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
  }
}
