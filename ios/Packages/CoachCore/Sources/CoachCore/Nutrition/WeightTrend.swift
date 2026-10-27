import Foundation

/// Eine Wägung (eigene Eingabe oder von Garmin).
public struct WeightEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
  public enum Source: String, Codable, Sendable {
    case manual, garmin, health
  }

  public var day: CalendarDay
  public var kilograms: Double
  public var source: Source

  public init(day: CalendarDay, kilograms: Double, source: Source) {
    self.day = day
    self.kilograms = kilograms
    self.source = source
  }

  public var id: String { "\(day.iso)-\(source.rawValue)" }
}

/// Gewichtsverlauf und Abgleich mit dem geplanten Tempo. Die Formeln für den Energiebedarf liegen einzeln oft
/// daneben; der tatsächliche Verlauf zeigt, ob das Ziel passt. Nachgesteuert wird in kleinen Schritten, weil das
/// Gewicht verzögert reagiert (Hall et al. 2011). Tägliches Wiegen unterstützt das Abnehmen (Steinberg et al. 2013).
public enum WeightTrend {
  public static let minimumEntries = 8
  public static let minimumSpanDays = 14
  public static let windowDays = 28
  /// Innerhalb dieser Abweichung (in % Körpergewicht pro Woche) gilt der Verlauf als im Plan.
  public static let tolerancePercent = 0.25
  /// Größte Anpassung auf einmal (kcal pro Tag) und insgesamt.
  public static let maxStepKilocalories = 250.0
  public static let maxTotalKilocalories = 500.0

  /// Ein Wert pro Tag: eigene Eingaben vor Garmin, Garmin vor Apple Health.
  public static func merged(_ entries: [WeightEntry]) -> [WeightEntry] {
    func rank(_ source: WeightEntry.Source) -> Int {
      switch source {
      case .manual: 2
      case .garmin: 1
      case .health: 0
      }
    }
    var byDay: [CalendarDay: WeightEntry] = [:]
    for entry in entries where (25...300).contains(entry.kilograms) {
      if let existing = byDay[entry.day], rank(existing.source) > rank(entry.source) { continue }
      byDay[entry.day] = entry
    }
    return byDay.values.sorted { $0.day < $1.day }
  }

  public struct Result: Equatable, Sendable {
    /// Gewicht laut Trendlinie heute.
    public var trendKilograms: Double
    /// Änderung pro Woche in % des Körpergewichts (negativ = Abnahme).
    public var weeklyPercent: Double
    public var entries: Int
    public var spanDays: Int
  }

  /// Lineare Regression über die letzten 28 Tage; `nil`, wenn zu wenige Wägungen vorliegen.
  public static func trend(_ entries: [WeightEntry], today: CalendarDay) -> Result? {
    let start = today.adding(days: -(windowDays - 1))
    let recent = merged(entries).filter { $0.day >= start && $0.day <= today }
    guard recent.count >= minimumEntries, let first = recent.first, let last = recent.last else { return nil }
    let span = first.day.days(until: last.day)
    guard span >= minimumSpanDays else { return nil }
    let xs = recent.map { Double(first.day.days(until: $0.day)) }
    let ys = recent.map(\.kilograms)
    let meanX = xs.reduce(0, +) / Double(xs.count)
    let meanY = ys.reduce(0, +) / Double(ys.count)
    let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
    let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
    guard variance > 0 else { return nil }
    let slope = covariance / variance
    let todayX = Double(first.day.days(until: today))
    let trend = meanY + slope * (todayX - meanX)
    return Result(
      trendKilograms: (trend * 10).rounded() / 10, weeklyPercent: (slope * 7 / trend * 100 * 100).rounded() / 100,
      entries: recent.count, spanDays: span)
  }

  public struct Advice: Equatable, Sendable {
    public enum Kind: String, Sendable {
      case onTrack, eatMore, eatLess, tooFast
    }

    public var kind: Kind
    public var message: String
    /// Vorgeschlagene Änderung der Tagesenergie in kcal (0 = nichts ändern).
    public var kilocalories: Double
    public var evidenceIDs: [String]
  }

  /// Vergleich des Verlaufs mit dem geplanten Tempo. `plannedPercent` negativ = abnehmen, `nil` = Gewicht halten.
  public static func advice(result: Result, plannedPercent: Double?, currentAdjustment: Double) -> Advice {
    let planned = plannedPercent ?? 0
    let difference = result.weeklyPercent - planned
    let actual = GermanFormat.number(abs(result.weeklyPercent))
    let direction = result.weeklyPercent < 0 ? "ab" : "zu"
    let evidence = ["weightloss.rate", "weight.trend"]
    // Schutz: schneller als 1 % pro Woche abnehmen ist nie gewollt.
    if result.weeklyPercent < -GoalRules.maxLossPercentPerWeek {
      let kcal = step(-difference, weight: result.trendKilograms, current: currentAdjustment, minimum: 100)
      return Advice(
        kind: .tooFast,
        message:
          "Du nimmst gerade etwa \(actual) % pro Woche ab – schneller als die Obergrenze von 1 %. Iss täglich "
          + "etwa \(Int(kcal)) kcal mehr, damit du Muskeln behältst.",
        kilocalories: kcal, evidenceIDs: evidence)
    }
    if abs(difference) <= tolerancePercent {
      return Advice(
        kind: .onTrack,
        message: "Dein Gewicht entwickelt sich wie geplant (etwa \(actual) % pro Woche \(direction)). Weiter so.",
        kilocalories: 0, evidenceIDs: evidence)
    }
    let kcal = step(-difference, weight: result.trendKilograms, current: currentAdjustment, minimum: 50)
    if kcal == 0 {
      return Advice(
        kind: .onTrack,
        message:
          "Der Verlauf weicht etwas vom Plan ab, die Anpassung ist aber schon ausgeschöpft. Prüfe, ob alle "
          + "Mahlzeiten erfasst sind.",
        kilocalories: 0, evidenceIDs: evidence)
    }
    let planText =
      plannedPercent.map { "geplant \(GermanFormat.number(abs($0))) % \($0 < 0 ? "ab" : "zu")" } ?? "geplant: halten"
    return Advice(
      kind: kcal > 0 ? .eatMore : .eatLess,
      message:
        "Dein Gewicht ändert sich um etwa \(actual) % pro Woche \(direction) (\(planText)). Vorschlag: täglich "
        + "\(kcal > 0 ? "\(Int(kcal)) kcal mehr" : "\(Int(-kcal)) kcal weniger"). In zwei Wochen prüft die App "
        + "erneut.",
      kilocalories: kcal, evidenceIDs: evidence)
  }

  /// kcal pro Tag aus der Abweichung in % pro Woche (7.700 kcal je kg als Näherung), begrenzt und auf 50 gerundet.
  static func step(_ percentPerWeek: Double, weight: Double, current: Double, minimum: Double) -> Double {
    let raw = percentPerWeek / 100 * weight * 7_700 / 7
    var value = min(max(raw, -maxStepKilocalories), maxStepKilocalories)
    if abs(value) < minimum { value = value < 0 ? -minimum : minimum }
    let total = min(max(current + value, -maxTotalKilocalories), maxTotalKilocalories)
    return ((total - current) / 50).rounded() * 50
  }

  /// Wägungen aus Garmin Connect (`/weight-service/weight/range`, Gewicht in Gramm), tolerant gelesen.
  public static func garminEntries(_ json: JSONValue) -> [WeightEntry] {
    var result: [WeightEntry] = []
    func walk(_ value: JSONValue) {
      switch value {
      case .object(let object):
        let dateText =
          object["calendarDate"]?.stringValue ?? object["summaryDate"]?.stringValue
          ?? object["date"]?.stringValue
        if let grams = object["weight"]?.doubleValue, let text = dateText, let day = CalendarDay(iso: text) {
          let kilograms = grams > 500 ? grams / 1000 : grams
          result.append(WeightEntry(day: day, kilograms: (kilograms * 10).rounded() / 10, source: .garmin))
        }
        for child in object.values { walk(child) }
      case .array(let items):
        for item in items { walk(item) }
      default:
        break
      }
    }
    walk(json)
    return merged(result)
  }
}
