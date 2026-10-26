import Foundation

/// Eine Herzfrequenzzone mit Grenzen in Schlägen pro Minute (`nil` = offen).
public struct HeartRateZone: Equatable, Sendable, Codable {
  public var name: String
  public var use: String
  public var low: Int?
  public var high: Int?

  public init(name: String, use: String, low: Int?, high: Int?) {
    self.name = name
    self.use = use
    self.low = low
    self.high = high
  }

  public var rangeText: String {
    switch (low, high) {
    case (nil, let high?): "bis \(high)"
    case (let low?, nil): "ab \(low)"
    case (let low?, let high?): "\(low)–\(high)"
    default: "–"
    }
  }
}

/// Zonen, wie sie auf der Uhr eingestellt sind (`/biometric-service/heartRateZones/v2`).
public struct WatchZones: Equatable, Sendable, Codable {
  public var sport: String
  /// `HR_MAX`, `HR_RESERVE` oder `LACTATE_THRESHOLD`.
  public var method: String
  public var maxHeartRate: Int?
  public var restingHeartRate: Int?
  public var lactateThreshold: Int?
  public var zones: [HeartRateZone]

  public var methodText: String {
    let upper = method.uppercased()
    if upper.contains("MAX") { return "% HFmax" }
    if upper.contains("RESERVE") { return "HF-Reserve" }
    if upper.contains("LACTATE") || upper.contains("THRESHOLD") { return "% Laktatschwelle" }
    return method
  }
}

/// Schwellenbasierte Coach-Zonen einer Sportart.
public struct CoachZones: Equatable, Sendable {
  public var sport: GarminActivity.Sport
  public var lactateThreshold: Int?
  public var source: String
  /// Schwelle ist geschätzt oder aus der anderen Sportart übernommen.
  public var isApproximate: Bool
  public var zones: [HeartRateZone]

  /// Obergrenze „locker“ (Z2).
  public var easyLimit: Int? { zones.count > 1 ? zones[1].high : nil }

  /// Z5a–c zusammengefasst – fünf Felder bleiben auf dem iPhone lesbar.
  public var fiveZones: [HeartRateZone] {
    let top = zones.filter { $0.name.hasPrefix("Z5") }
    var base = Array(zones.filter { !$0.name.hasPrefix("Z5") }.prefix(4))
    if let first = top.first {
      base.append(HeartRateZone(name: "Z5", use: "Schwelle+", low: first.low, high: top.last?.high))
    }
    return base
  }
}

/// Zeitanteile locker / mittel / hart.
public struct IntensityShare: Equatable, Sendable {
  public var minutes: Int
  public var zonePercent: [Int]
  public var easyPercent: Int
  public var moderatePercent: Int
  public var hardPercent: Int

  init?(seconds: [Double]) {
    let total = seconds.reduce(0, +)
    guard total > 0, seconds.count == 5 else { return nil }
    func percent(_ value: Double) -> Int { Int((value / total * 100).rounded()) }
    minutes = Int((total / 60).rounded())
    zonePercent = seconds.map(percent)
    easyPercent = percent(seconds[0] + seconds[1])
    moderatePercent = percent(seconds[2])
    hardPercent = percent(seconds[3] + seconds[4])
  }
}

/// Verteilung der Zeit in den Zonen der Uhr, gesamt und je Woche.
public struct ZoneDistribution: Equatable, Sendable {
  public struct Week: Equatable, Sendable {
    public var monday: CalendarDay
    public var run: IntensityShare?
    public var bike: IntensityShare?
  }

  public var weeks: Int
  public var run: IntensityShare?
  public var bike: IntensityShare?
  public var perWeek: [Week]
  public var withoutZoneData: Int
}

/// Ergebnis der Zonenberechnung – wie `hr_zones.build()` im Altbestand.
public struct HeartRateZoneReport: Equatable, Sendable {
  public var maxHeartRate: Int?
  public var maxHeartRateSource: String
  public var observedConfirmedMax: Int?
  public var observedPeak: Int?
  public var observedCount: Int
  public var watch: [WatchZones]
  public var run: CoachZones
  public var bike: CoachZones
  public var distribution: ZoneDistribution
  public var hints: [String]
}

/// Eigene Werte aus den Einstellungen (0 oder `nil` = automatisch).
public struct HeartRateOverrides: Hashable, Sendable, Codable {
  public var maxHeartRate: Int?
  public var thresholdRun: Int?
  public var thresholdBike: Int?

  public init(maxHeartRate: Int? = nil, thresholdRun: Int? = nil, thresholdBike: Int? = nil) {
    self.maxHeartRate = maxHeartRate
    self.thresholdRun = thresholdRun
    self.thresholdBike = thresholdBike
  }

  func valid(_ value: Int?) -> Int? {
    value.flatMap { $0 >= 40 ? $0 : nil }
  }
}

/// Herzfrequenzzonen nach dem Altbestand (`hr_zones.py`).
///
/// - Uhr-Zonen: unverändert aus Garmin Connect.
/// - Coach-Zonen: Friel (% der Laktatschwellen-HF), Anker Schwelle statt HFmax (Esteve-Lanao 2007).
/// - HFmax: eigener Wert > bestätigter Messwert (zweite Einheit höchstens 3 Schläge darunter) > Garmin.
///   Altersformeln weichen um ±11 Schläge ab (Nes 2013) und werden nicht benutzt.
/// - Verteilung: Zeit in den Uhr-Zonen der letzten 4 Wochen; Richtwert ca. 80 % locker (Seiler).
public enum HeartRateZoneCalculator {
  static let confirmTolerance = 3
  static let plausibleMax = 140...230
  static let estimateFactor = 0.90
  static let ratioBand = 0.80...0.97

  /// (Name, Verwendung, Untergrenze % LTHR, Obergrenze % LTHR) nach Friel.
  static let friel: [GarminActivity.Sport: [(String, String, Double?, Double?)]] = [
    .run: [
      ("Z1", "Erholung", nil, 85), ("Z2", "Grundlagenausdauer", 85, 89), ("Z3", "Tempo", 90, 94),
      ("Z4", "Unterschwelle", 95, 99), ("Z5a", "Schwelle", 100, 102), ("Z5b", "VO₂max", 103, 106),
      ("Z5c", "Anaerob", 106, nil),
    ],
    .bike: [
      ("Z1", "Erholung", nil, 81), ("Z2", "Grundlagenausdauer", 81, 89), ("Z3", "Tempo", 90, 93),
      ("Z4", "Unterschwelle", 94, 99), ("Z5a", "Schwelle", 100, 102), ("Z5b", "VO₂max", 103, 106),
      ("Z5c", "Anaerob", 106, nil),
    ],
  ]

  public static func frielZones(threshold: Int, sport: GarminActivity.Sport, maxHeartRate: Int? = nil)
    -> [HeartRateZone]
  {
    let lthr = Double(threshold)
    var rows = (friel[sport] ?? friel[.run] ?? []).map { name, use, low, high in
      HeartRateZone(
        name: name, use: use,
        low: low.map { Int((lthr * $0 / 100 - 1e-9).rounded(.up)) },
        high: high.map { Int((lthr * $0 / 100 + 1e-9).rounded(.down)) })
    }
    // Lückenlos: Obergrenze = nächste Untergrenze - 1
    for index in rows.indices.dropLast() {
      if let next = rows[index + 1].low { rows[index].high = next - 1 }
    }
    if let maxHeartRate, !rows.isEmpty { rows[rows.count - 1].high = maxHeartRate }
    return rows
  }

  /// Liest die Uhr-Zonen (Felder `zone1Floor` … `zone5Floor`, `maxHeartRateUsed`, `trainingMethod`).
  public static func watchZones(_ json: JSONValue) -> [WatchZones] {
    let entries: [[String: JSONValue]]
    switch json {
    case .array(let values): entries = values.compactMap(\.objectValue)
    case .object(let object): entries = [object]
    default: entries = []
    }
    return entries.compactMap { entry in
      var floors: [Int: Int] = [:]
      var maxHR: Int?
      var restHR: Int?
      var lthr: Int?
      for (key, value) in entry {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let number = value.doubleValue else { continue }
        if normalized.hasPrefix("zone"), normalized.hasSuffix("floor"),
          let digit = Int(normalized.dropFirst(4).dropLast(5))
        {
          floors[digit] = Int(number)
        } else if normalized.contains("max"), normalized.contains("heartrate") {
          maxHR = maxHR ?? Int(number)
        } else if normalized.contains("rest"), normalized.contains("heartrate") {
          restHR = restHR ?? Int(number)
        } else if normalized.contains("lactate"), normalized.contains("heartrate") {
          lthr = lthr ?? Int(number)
        }
      }
      guard (1...5).allSatisfy({ floors[$0] != nil }) else { return nil }
      let zones = (1...5).map { index in
        HeartRateZone(
          name: "Z\(index)", use: "", low: floors[index],
          high: index < 5 ? floors[index + 1].map { $0 - 1 } : maxHR)
      }
      return WatchZones(
        sport: entry["sport"]?.stringValue ?? "DEFAULT",
        method: entry["trainingMethod"]?.stringValue ?? entry["method"]?.stringValue ?? "",
        maxHeartRate: maxHR, restingHeartRate: restHR, lactateThreshold: lthr.flatMap { $0 > 0 ? $0 : nil },
        zones: zones)
    }
  }

  /// Höchster bestätigter Puls der letzten 12 Monate aus Lauf- und Radeinheiten
  /// (Schwimmen und Kraft haben unzuverlässigen optischen Puls).
  public static func observedMax(activities: [GarminActivity], today: CalendarDay)
    -> (confirmed: Int?, peak: Int?, count: Int)
  {
    let cutoff = today.adding(days: -365)
    let values =
      activities
      .filter { [.run, .bike].contains($0.sport) && $0.day.map { $0 >= cutoff } == true }
      .compactMap { $0.maxHeartRate.map { Int($0.rounded()) } }
      .filter { plausibleMax.contains($0) }
      .sorted(by: >)
    var confirmed: Int?
    for index in values.indices.dropLast() where values[index] - values[index + 1] <= confirmTolerance {
      confirmed = values[index]
      break
    }
    return (confirmed, values.first, values.count)
  }

  public static func report(
    activities: [GarminActivity],
    watchZonesJSON: JSONValue?,
    profile: GarminProfile?,
    overrides: HeartRateOverrides,
    today: CalendarDay
  ) -> HeartRateZoneReport {
    let watch = watchZonesJSON.map(watchZones) ?? []
    let observed = observedMax(activities: activities, today: today)
    let garminMax = watch.compactMap(\.maxHeartRate).first

    var maxHR: Int?
    var maxSource = "unbekannt"
    if let own = overrides.valid(overrides.maxHeartRate) {
      (maxHR, maxSource) = (own, "eigener Wert")
    } else if let best = [
      (observed.confirmed, "bestätigter Messwert (12 Monate)"), (garminMax, "Garmin-Einstellung"),
    ].compactMap({ value, source in value.map { ($0, source) } }).max(by: { $0.0 < $1.0 }) {
      (maxHR, maxSource) = best
    } else if let peak = observed.peak {
      (maxHR, maxSource) = (peak, "unbestätigter Höchstwert")
    }

    let garminThreshold =
      profile?.lactateThresholdHeartRate.map { Int($0.rounded()) }.flatMap { (80...220).contains($0) ? $0 : nil }
      ?? watch.compactMap(\.lactateThreshold).first

    func coach(_ sport: GarminActivity.Sport) -> CoachZones {
      let ownRun = overrides.valid(overrides.thresholdRun)
      let own = sport == .run ? ownRun : overrides.valid(overrides.thresholdBike)
      var choice: (Int?, String, Bool)
      if let own {
        choice = (own, "eigener Wert", false)
      } else if sport == .run, let garminThreshold {
        choice = (garminThreshold, "Garmin (Laktatschwelle)", false)
      } else if sport == .bike, let ownRun {
        choice = (ownRun, "eigener Laufwert als Näherung", true)
      } else if sport == .bike, let garminThreshold {
        choice = (garminThreshold, "Garmin-Laufwert als Näherung", true)
      } else if let maxHR {
        choice = (
          Int((Double(maxHR) * estimateFactor).rounded()), "Schätzung (\(Int(estimateFactor * 100)) % HFmax)", true
        )
      } else {
        choice = (nil, "unbekannt", true)
      }
      let zones = choice.0.map { frielZones(threshold: $0, sport: sport, maxHeartRate: maxHR) } ?? []
      return CoachZones(
        sport: sport, lactateThreshold: choice.0, source: choice.1, isApproximate: choice.2, zones: zones)
    }

    let run = coach(.run)
    let bike = coach(.bike)
    let distribution = distribution(activities: activities, today: today)
    let hints = hints(
      run: run, bike: bike, maxHR: maxHR, garminMax: garminMax, observed: observed, overrides: overrides,
      watch: watch, distribution: distribution, activities: activities, today: today)
    return HeartRateZoneReport(
      maxHeartRate: maxHR, maxHeartRateSource: maxSource, observedConfirmedMax: observed.confirmed,
      observedPeak: observed.peak, observedCount: observed.count, watch: watch, run: run, bike: bike,
      distribution: distribution, hints: hints)
  }

  public static func distribution(activities: [GarminActivity], today: CalendarDay, weeks: Int = 4)
    -> ZoneDistribution
  {
    let start = today.adding(days: -weeks * 7)
    var total: [GarminActivity.Sport: [Double]] = [:]
    var perWeek: [CalendarDay: [GarminActivity.Sport: [Double]]] = [:]
    var missing = 0
    for activity in activities where [.run, .bike].contains(activity.sport) {
      guard let day = activity.day, day >= start, day <= today else { continue }
      guard let seconds = activity.secondsInZones else {
        missing += 1
        continue
      }
      total[activity.sport] = add(total[activity.sport], seconds)
      let monday = day.adding(days: -day.weekdayIndex)
      perWeek[monday, default: [:]][activity.sport] = add(perWeek[monday]?[activity.sport], seconds)
    }
    let weeksList = perWeek.keys.sorted(by: >).map { monday in
      ZoneDistribution.Week(
        monday: monday,
        run: perWeek[monday]?[.run].flatMap(IntensityShare.init(seconds:)),
        bike: perWeek[monday]?[.bike].flatMap(IntensityShare.init(seconds:)))
    }
    return ZoneDistribution(
      weeks: weeks, run: total[.run].flatMap(IntensityShare.init(seconds:)),
      bike: total[.bike].flatMap(IntensityShare.init(seconds:)), perWeek: weeksList, withoutZoneData: missing)
  }

  private static func add(_ base: [Double]?, _ values: [Double]) -> [Double] {
    zip(base ?? Array(repeating: 0, count: 5), values).map(+)
  }

  /// Näherung: jede Einheit (ab 15 min) nach ihrer Durchschnitts-HF einer Coach-Zone zuordnen.
  static func averageHeartRateShare(
    activities: [GarminActivity], coach: CoachZones, today: CalendarDay, weeks: Int = 4
  ) -> IntensityShare? {
    guard coach.zones.count >= 3, let easy = coach.zones[1].high, let moderate = coach.zones[2].high else {
      return nil
    }
    let start = today.adding(days: -weeks * 7)
    var seconds = [0.0, 0, 0, 0, 0]
    for activity in activities where activity.sport == coach.sport {
      guard let day = activity.day, day >= start, day <= today, let average = activity.averageHeartRate,
        let duration = activity.durationSeconds, duration >= 15 * 60
      else { continue }
      let index = average <= Double(easy) ? 0 : (average <= Double(moderate) ? 2 : 3)
      seconds[index] += duration
    }
    return IntensityShare(seconds: seconds)
  }

  private static func hints(
    run: CoachZones, bike: CoachZones, maxHR: Int?, garminMax: Int?,
    observed: (confirmed: Int?, peak: Int?, count: Int), overrides: HeartRateOverrides, watch: [WatchZones],
    distribution: ZoneDistribution, activities: [GarminActivity], today: CalendarDay
  ) -> [String] {
    var hints: [String] = []
    for zones in [run, bike] {
      guard let lthr = zones.lactateThreshold, let maxHR else { continue }
      let ratio = Double(lthr) / Double(maxHR)
      if !ratioBand.contains(ratio) {
        let label = zones.sport == .run ? "Lauf" : "Rad"
        hints.append(
          "\(label)-Schwelle \(lthr) liegt bei \(Int((ratio * 100).rounded())) % der HFmax \(maxHR) – außerhalb "
            + "des üblichen Bereichs von 80–97 %. HFmax oder Schwelle prüfen.")
      }
    }
    if run.isApproximate, run.lactateThreshold != nil {
      hints.append(
        "Die Lauf-Schwelle ist nur geschätzt. Genauer: 30 Minuten Lauf am Anschlag, Durchschnitts-HF der letzten "
          + "20 Minuten = Schwelle (Friel-Feldtest), dann unter Einstellungen eintragen.")
    }
    if bike.isApproximate, bike.lactateThreshold != nil {
      hints.append(
        "Für das Rad liegt kein eigener Schwellenwert vor – die Rad-Zonen sind eine Näherung. Ein eigener "
          + "30-Minuten-Test auf dem Rad macht sie genau.")
    }
    if let confirmed = observed.confirmed, let garminMax, confirmed - garminMax > 3 {
      hints.append(
        "Bestätigter Höchstpuls \(confirmed) liegt über der Uhr-Einstellung \(garminMax). Die Zonen der Uhr sind "
          + "dadurch zu tief angesetzt.")
    }
    if let confirmed = observed.confirmed, let garminMax, garminMax - confirmed > 5, observed.count >= 5,
      overrides.valid(overrides.maxHeartRate) == nil
    {
      hints.append(
        "Die HFmax der Uhr (\(garminMax)) wurde bisher in keiner Einheit erreicht (höchster bestätigter Wert "
          + "\(confirmed)). Die Coach-Zonen hängen an der Schwelle und sind davon kaum betroffen, die Uhr-Zonen schon."
      )
    }
    if let peak = observed.peak, observed.confirmed.map({ peak - $0 > confirmTolerance }) ?? true {
      hints.append(
        "Höchstwert \(peak) wurde in keiner zweiten Einheit annähernd erreicht und gilt als möglicher "
          + "Sensor-Ausreißer – er fließt nicht in die Zonen ein.")
    }
    if let method = watch.first(where: { ["DEFAULT", "RUNNING"].contains($0.sport.uppercased()) })?.method
      .uppercased()
    {
      if method.contains("MAX") {
        hints.append(
          "Die Uhr rechnet Zonen in % der HFmax. Das ist nicht dasselbe wie Zonen um die Schwelle: Z2 der Uhr liegt "
            + "tiefer als Z2 nach Schwelle.")
      } else if method.contains("RESERVE") {
        hints.append("Die Uhr rechnet Zonen nach HF-Reserve (Karvonen).")
      }
    }
    for (coach, label, share) in [(run, "Laufen", distribution.run), (bike, "Rad", distribution.bike)] {
      let average = averageHeartRateShare(activities: activities, coach: coach, today: today)
      if let average, average.minutes >= 120, average.easyPercent < 70 {
        let watchText = share.map { " Nach den Zonen der Uhr sind es \($0.easyPercent) % in Z1–2." } ?? ""
        hints.append(
          "\(label): \(average.easyPercent) % der Zeit liegen bei einer Durchschnitts-HF in Coach-Z1–2 "
            + "(letzte 4 Wochen, Näherung je Einheit).\(watchText) Richtwert ~80 % locker – zu viel Mittelbereich "
            + "macht lockere Einheiten weniger erholsam.")
      } else if average == nil, let share, share.minutes >= 120, share.easyPercent < 70 {
        hints.append("\(label): nur \(share.easyPercent) % der Zeit in Z1–2 der Uhr (letzte 4 Wochen); Richtwert ~80 %.")
      }
    }
    hints.append(
      "Optisches Messen am Handgelenk unterschätzt bei intensiven Intervallen die Zeit in hohen Zonen "
        + "(Neudorfer 2024). Der Hart-Anteil ist eher eine Untergrenze.")
    return hints
  }
}
