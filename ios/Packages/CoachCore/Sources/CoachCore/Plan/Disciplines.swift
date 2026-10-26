import Foundation

/// Ein eingetragener Testwert mit Datum – Grundlage der Verläufe (CSS, FTP, Schwelle) und der Aktualität.
public struct TestRecord: Codable, Equatable, Sendable, Identifiable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    /// Sekunden je 100 m
    case css
    /// Watt
    case ftp
    /// Lauf-Schwellenpace, Sekunden je km
    case threshold
    /// Halbmarathon-Testzeit, Sekunden
    case halfMarathon
    /// Rad-Schnitt für die 94 km, km/h
    case bikeSpeed
    /// Renn-Laufpace nach dem Rad, Sekunden je km
    case racePace

    public var label: String {
      switch self {
      case .css: "CSS"
      case .ftp: "FTP"
      case .threshold: "Schwellenpace"
      case .halfMarathon: "Halbmarathon"
      case .bikeSpeed: "Rad-Schnitt"
      case .racePace: "Renn-Laufpace"
      }
    }
  }

  public var kind: Kind
  public var value: Double
  public var day: CalendarDay
  public var id: String { "\(kind.rawValue)-\(day.iso)" }

  public init(kind: Kind, value: Double, day: CalendarDay) {
    self.kind = kind
    self.value = value
    self.day = day
  }
}

public enum TestHistory {
  /// Neuer Eintrag ersetzt einen gleichartigen vom selben Tag.
  public static func adding(_ record: TestRecord, to records: [TestRecord]) -> [TestRecord] {
    (records.filter { $0.id != record.id } + [record]).sorted {
      ($0.day, $0.kind.rawValue) < ($1.day, $1.kind.rawValue)
    }
  }

  public static func latest(_ kind: TestRecord.Kind, in records: [TestRecord]) -> TestRecord? {
    records.filter { $0.kind == kind }.max { $0.day < $1.day }
  }

  public static func values(_ kind: TestRecord.Kind, in records: [TestRecord]) -> [DayValue] {
    records.filter { $0.kind == kind }.map { DayValue(day: $0.day, value: $0.value) }.sorted { $0.day < $1.day }
  }
}

/// Eine Zeile einer Tempo- oder Zonentabelle.
public struct PaceRow: Equatable, Sendable, Identifiable {
  public var label: String
  public var value: String
  public var use: String
  public var isKey = false
  public var id: String { label }
}

/// Schwimm-Paces aus der CSS (Tabelle `swim_paces` im Altbestand).
public enum SwimPaces {
  public static func rows(css: Int) -> [PaceRow] {
    let t = PlanTokens.mmss
    return [
      PaceRow(label: "Tempo (50er)", value: "\(t(css - 4))–\(t(css - 2))", use: "kurze, schnelle Wiederholungen"),
      PaceRow(label: "Schwelle (100er)", value: t(css), use: "CSS-Serien", isKey: true),
      PaceRow(label: "200er", value: "\(t(css + 1))–\(t(css + 2))", use: "CSS 200er"),
      PaceRow(label: "400er", value: "\(t(css + 3))–\(t(css + 4))", use: "CSS 400er"),
      PaceRow(label: "Ausdauer / Technik", value: "\(t(css + 4))–\(t(css + 6))", use: "lange Serien"),
      PaceRow(label: "Rennen 1,9 km", value: "\(t(css))–\(t(css + 3))", use: "Almere"),
    ]
  }

  /// CSS = (Zeit 400 m − Zeit 200 m) ÷ 2, in Sekunden je 100 m (Wakayoshi 1992). `nil` bei unplausiblen Zeiten.
  public static func css(time400: Int, time200: Int) -> Int? {
    guard time400 > time200, time200 > 0 else { return nil }
    let css = Int((Double(time400 - time200) / 2).rounded())
    return (60...300).contains(css) ? css : nil
  }
}

/// Rad-Zonen in % FTP (Tabelle `bike_zones` im Altbestand).
public enum BikeZones {
  public static func rows(ftp: Int) -> [PaceRow] {
    func watts(_ low: Int, _ high: Int) -> String {
      "\(Int((Double(ftp) * Double(low) / 100).rounded()))–\(Int((Double(ftp) * Double(high) / 100).rounded())) W"
    }
    return [
      PaceRow(label: "Z1 Erholung", value: watts(0, 55), use: "0–55 % FTP"),
      PaceRow(label: "Z2 Grundlage", value: watts(56, 75), use: "56–75 % FTP"),
      PaceRow(label: "Z3 Tempo", value: watts(76, 87), use: "76–87 % FTP"),
      PaceRow(label: "Sweet Spot", value: watts(88, 94), use: "88–94 % FTP"),
      PaceRow(label: "Z4 Schwelle", value: watts(95, 105), use: "95–105 % FTP"),
      PaceRow(label: "Z5 VO2max", value: watts(106, 120), use: "106–120 % FTP"),
      PaceRow(label: "Renntempo", value: watts(75, 78), use: "75–78 % FTP · Almere", isKey: true),
    ]
  }
}

/// Lauf-Paces (Tabelle `run_paces` im Altbestand).
public enum RunPaces {
  public static func rows(config: SeasonConfig) -> [PaceRow] {
    let tokens = PlanTokens(config: config)
    let t = PlanTokens.mmss
    return [
      PaceRow(label: "Locker (Z2)", value: tokens.easyRange, use: "Z2-Läufe, Longruns – Herzfrequenz hat Vorrang"),
      PaceRow(label: "Marathon", value: t(config.marathonPaceSecondsPerKm), use: "Marathontempo-Abschnitte"),
      PaceRow(label: "Renn-Lauf", value: t(config.racePaceSecondsPerKm), use: "Lauf nach dem Rad"),
      PaceRow(
        label: "Schwelle", value: t(config.thresholdPaceSecondsPerKm), use: "2–4-km-Intervalle, Tempodauerlauf",
        isKey: true),
      PaceRow(label: "Intervall", value: tokens.intervalRange, use: "4×4 min – 90–95 % HFmax hat Vorrang"),
    ]
  }
}

/// Geschätzte Zeit für Almere aus den Benchmarks (Karte „Zielzeit Almere“ im Altbestand).
public struct RaceEstimate: Equatable, Sendable {
  public struct Leg: Equatable, Sendable, Identifiable {
    public var label: String
    public var assumption: String
    public var minutes: Double
    public var id: String { label }
  }

  public struct Freshness: Equatable, Sendable, Identifiable {
    public var label: String
    /// Tage seit dem letzten Test, `nil` = nie getestet
    public var age: Int?
    public var id: String { label }
    public var isFresh: Bool { age.map { $0 <= RaceEstimate.maxAgeDays } ?? false }
  }

  public static let maxAgeDays = 56
  public static let corridor = 330.0...360.0
  static let swimMeters = 1900.0
  static let bikeKilometers = 94.0
  static let runKilometers = 21.1
  static let transition1 = 3.0
  static let transition2 = 2.0

  public var legs: [Leg]
  public var totalMinutes: Double
  public var freshness: [Freshness]
  /// Ersparnis in Minuten: Schwimmen −5 s/100 m, Rad +1 km/h, Lauf −10 s/km
  public var savings: (swim: Double, bike: Double, run: Double)

  public var allFresh: Bool { freshness.allSatisfy(\.isFresh) }

  public var corridorText: String {
    if totalMinutes < Self.corridor.lowerBound { return "Unter dem Zielkorridor 5:30–6:00." }
    if totalMinutes <= Self.corridor.upperBound { return "Im Zielkorridor 5:30–6:00." }
    return "\(Int((totalMinutes - Self.corridor.upperBound).rounded())) min über dem Zielkorridor."
  }

  public static func == (lhs: RaceEstimate, rhs: RaceEstimate) -> Bool {
    lhs.legs == rhs.legs && lhs.totalMinutes == rhs.totalMinutes && lhs.freshness == rhs.freshness
  }

  public init(config: SeasonConfig, tests: [TestRecord], today: CalendarDay) {
    let swim = Double(config.cssSecondsPer100m)
    let bike = max(config.raceBikeSpeedKmh, 1)
    let run = Double(config.racePaceSecondsPerKm)
    let swimMinutes = swim * Self.swimMeters / 100 / 60
    let bikeMinutes = Self.bikeKilometers / bike * 60
    let runMinutes = run * Self.runKilometers / 60
    legs = [
      Leg(label: "Schwimmen 1,9 km", assumption: "\(PlanTokens.mmss(Int(swim))) /100 m", minutes: swimMinutes),
      Leg(label: "Wechsel 1", assumption: "Annahme", minutes: Self.transition1),
      Leg(label: "Rad 94 km", assumption: "\(GermanFormat.decimal(bike)) km/h", minutes: bikeMinutes),
      Leg(label: "Wechsel 2", assumption: "Annahme", minutes: Self.transition2),
      Leg(label: "Lauf 21,1 km", assumption: "\(PlanTokens.mmss(Int(run))) /km", minutes: runMinutes),
    ]
    totalMinutes = legs.map(\.minutes).reduce(0, +)
    func age(_ kind: TestRecord.Kind) -> Int? {
      TestHistory.latest(kind, in: tests).map { $0.day.days(until: today) }
    }
    freshness = [
      Freshness(label: "Schwimmen", age: age(.css)),
      Freshness(label: "Rad", age: age(.bikeSpeed) ?? age(.ftp)),
      Freshness(label: "Lauf", age: age(.racePace) ?? age(.threshold)),
    ]
    savings = (
      swim: Self.swimMeters / 100 * 5 / 60,
      bike: bikeMinutes - Self.bikeKilometers / (bike + 1) * 60,
      run: Self.runKilometers * 10 / 60
    )
  }

  /// „5:42“ für Minuten als Stunden:Minuten.
  public static func hoursMinutes(_ minutes: Double) -> String {
    let rounded = Int(minutes.rounded())
    return String(format: "%d:%02d", rounded / 60, rounded % 60)
  }
}

/// Marathon-Ausblick (Reiter „Marathon“ im Altbestand).
public struct MarathonOutlook: Equatable, Sendable {
  public struct LadderWeek: Equatable, Sendable, Identifiable {
    public var sunday: CalendarDay
    public var longRun: String
    public var quality: String
    public var isCurrent: Bool
    public var isPast: Bool
    public var id: String { sunday.iso }
  }

  public static let marathonKilometers = 42.195
  /// Praxiswert: Marathonzeit ≈ Halbmarathon × 2,15–2,2 (für Debütanten vorsichtiger als Riegel × 2,09).
  public static let halfMarathonFactor = 2.15...2.2

  public var daysToRace: Int
  public var targetSeconds: Int
  public var predicted: ClosedRange<Int>?
  /// Zielpace schneller als der Halbmarathon-Test hergibt
  public var targetTooFast: Bool
  public var ladder: [LadderWeek]

  public init(config: SeasonConfig, halfMarathonSeconds: Int?, schedule: SeasonSchedule?, today: CalendarDay) {
    daysToRace = today.days(until: config.marathonDate)
    targetSeconds = Int((Double(config.marathonPaceSecondsPerKm) * Self.marathonKilometers).rounded())
    if let half = halfMarathonSeconds, half > 0 {
      let low = Int((Double(half) * Self.halfMarathonFactor.lowerBound).rounded())
      let high = Int((Double(half) * Self.halfMarathonFactor.upperBound).rounded())
      predicted = low...high
      targetTooFast = Double(config.marathonPaceSecondsPerKm) < (Double(low) / Self.marathonKilometers).rounded(.down)
    } else {
      predicted = nil
      targetTooFast = false
    }
    let monday = today.adding(days: -today.weekdayIndex)
    ladder = (schedule?.weeks ?? []).filter { ["Marathon-Aufbau", "Marathon-Taper"].contains($0.ph) }.compactMap {
      week in
      guard let start = week.monday else { return nil }
      let sunday = start.adding(days: 6)
      let longRun: String
      if week.key == "marathon" {
        longRun = "🏁 Marathon"
      } else if week.lr == 21.1 {
        longRun = "Halbmarathon-Test"
      } else {
        longRun = week.lr > 0 ? "\(GermanFormat.decimal(week.lr)) km" : "–"
      }
      return LadderWeek(
        sunday: sunday, longRun: longRun, quality: week.qc, isCurrent: start == monday, isPast: sunday < today)
    }
  }

  public static func hoursMinutes(seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
  }

  public static func pace(seconds: Double) -> String {
    PlanTokens.mmss(Int(seconds))
  }
}
