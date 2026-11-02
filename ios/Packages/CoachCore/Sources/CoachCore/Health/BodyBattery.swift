import Foundation

/// Body Battery (Garmin, 0–100): aktueller Stand, Wert beim Aufwachen, Verlauf und der Zusammenhang mit Schlaf und
/// Stress – nur aus gemessenen Werten. Apple Health kennt keinen vergleichbaren Wert; ohne Garmin bleibt alles leer.
public enum BodyBatteryAnalysis {
  public struct Day: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    public var high: Double?
    public var low: Double?
    public var wake: Double?
    public var charged: Double?
    public var drained: Double?
    public var sleepHours: Double?
    public var stress: Double?
    public var id: String { day.iso }
  }

  public struct Relation: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
  }

  public struct Summary: Equatable, Sendable {
    /// Letzter Messwert und seine Uhrzeit (Minuten nach Mitternacht), falls aus dem Verlauf bekannt.
    public var current: Double?
    public var currentMinute: Int?
    public var currentDay: CalendarDay?
    public var wake: Double?
    public var curve: [BodyBatterySample]
    public var history: [Day]
    /// Persönlicher Bereich des Aufwachwerts (letzte 30 Tage).
    public var wakeNorm: PersonalNorm?
    public var relations: [Relation]

    public var hasData: Bool { current != nil || !history.isEmpty }
  }

  /// Aufwachwert: Garmins `bodyBatteryAtWakeTime`, sonst der Verlaufswert zur Aufwachzeit, sonst der Höchstwert
  /// am Vormittag (die Batterie lädt nachts und ist morgens am höchsten).
  public static func wakeValue(_ metrics: DailyMetrics) -> Double? {
    if let wake = metrics.bodyBatteryAtWake { return wake }
    guard let curve = metrics.bodyBatteryCurve, !curve.isEmpty else { return nil }
    if let end = metrics.sleepEndMinutes {
      let minute = Int(end)
      if let sample = curve.last(where: { $0.minute <= minute && minute - $0.minute <= 60 }) {
        return Double(sample.value)
      }
    }
    return curve.filter { $0.minute <= 12 * 60 }.map(\.value).max().map(Double.init)
  }

  public static func summary(days: [DailyMetrics], today: CalendarDay, historyDays: Int = 30) -> Summary {
    let sorted = days.sorted { $0.day < $1.day }
    let start = today.adding(days: -(historyDays - 1))
    let history = sorted.filter { $0.day >= start && $0.day <= today }.compactMap { metrics -> Day? in
      let day = Day(
        day: metrics.day, high: metrics.bodyBatteryHigh, low: metrics.bodyBatteryLow, wake: wakeValue(metrics),
        charged: metrics.bodyBatteryCharged, drained: metrics.bodyBatteryDrained, sleepHours: metrics.sleepHours,
        stress: metrics.stressAverage)
      return day.high == nil && day.wake == nil && day.charged == nil ? nil : day
    }
    let latest = sorted.last { $0.day <= today && $0.day >= today.adding(days: -1) && hasBattery($0) }
    let curve = latest?.bodyBatteryCurve ?? []
    let wakeValues = history.filter { $0.day < today }.compactMap(\.wake)
    return Summary(
      current: curve.last.map { Double($0.value) } ?? latest?.bodyBatteryLatest,
      currentMinute: curve.last?.minute, currentDay: latest?.day,
      wake: (sorted.last { $0.day == today }).flatMap(wakeValue),
      curve: curve, history: history, wakeNorm: PersonalNorm.of(wakeValues), relations: relations(history))
  }

  private static func hasBattery(_ metrics: DailyMetrics) -> Bool {
    metrics.bodyBatteryLatest != nil || metrics.bodyBatteryCurve?.isEmpty == false
  }

  /// Mindestens so viele Tage je Vergleichsgruppe.
  public static let minimumGroup = 3

  /// Zusammenhang mit Schlaf (Aufladung nach langen und kurzen Nächten) und Stress (Verbrauch an Tagen mit viel und
  /// wenig Stress). Nur ein Vergleich eigener Tage, keine Kausalaussage.
  public static func relations(_ history: [Day], sleepTarget: Double = 7) -> [Relation] {
    var result: [Relation] = []
    let sleepDays = history.filter { $0.charged != nil && $0.sleepHours != nil }
    let long = sleepDays.filter { ($0.sleepHours ?? 0) >= sleepTarget }.compactMap(\.charged)
    let short = sleepDays.filter { ($0.sleepHours ?? 0) < sleepTarget }.compactMap(\.charged)
    if long.count >= minimumGroup, short.count >= minimumGroup {
      let (a, b) = (average(long), average(short))
      let hours = GermanFormat.decimal(sleepTarget)
      result.append(
        Relation(
          id: "sleep",
          text: abs(a - b) < 5
            ? "Nach Nächten ab \(hours) h lädt sie kaum mehr auf als nach kürzeren (+\(Int(a)) zu +\(Int(b)))."
            : "Nach Nächten ab \(hours) h Schlaf lädt sie im Schnitt um \(Int(a)) auf, nach kürzeren um \(Int(b))."
        ))
    }
    let stressDays = history.filter { $0.drained != nil && $0.stress != nil }
    if stressDays.count >= minimumGroup * 2 {
      let levels = stressDays.compactMap(\.stress).sorted()
      let median = levels[levels.count / 2]
      let high = stressDays.filter { ($0.stress ?? 0) >= median }.compactMap(\.drained)
      let low = stressDays.filter { ($0.stress ?? 0) < median }.compactMap(\.drained)
      if high.count >= minimumGroup, low.count >= minimumGroup {
        let (a, b) = (average(high), average(low))
        result.append(
          Relation(
            id: "stress",
            text: abs(a - b) < 5
              ? "Stress und Verbrauch hängen bei dir kaum zusammen (−\(Int(a)) zu −\(Int(b)))."
              : "An Tagen mit mehr Stress (Ø ab \(Int(median))) verbraucht sie im Schnitt \(Int(a)), "
                + "an ruhigeren \(Int(b))."))
      }
    }
    return result
  }

  private static func average(_ values: [Double]) -> Double {
    (values.reduce(0, +) / Double(values.count)).rounded()
  }

  /// Einordnung eines Stands (Garmin: 0–25 niedrig, 26–50 mittel, 51–75 hoch, 76–100 sehr hoch).
  public static func band(_ value: Double) -> String {
    switch value {
    case ..<26: "niedrig"
    case ..<51: "mittel"
    case ..<76: "hoch"
    default: "sehr hoch"
    }
  }
}
