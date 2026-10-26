import CoachCore
import Foundation
import Observation

/// Verläufe und Kennzahlen wie im Home-Assistant-Dashboard (Reiter Erholung, Laufen/Rad/Schwimmen,
/// Herzfrequenz). Gerechnet wird in `CoachCore`; hier wird nur zusammengestellt.
@Observable
final class TrainingViewModel {
  struct Tile: Equatable, Identifiable {
    let title: String
    let value: String
    var id: String { title }
  }

  struct TrendCard: Equatable, Identifiable {
    let title: String
    let unit: String
    let digits: Int
    /// Höher ist besser (für die Farbe der Veränderung); `nil` = neutral.
    let higherIsBetter: Bool?
    let trend: MetricTrend
    var id: String { title }
  }

  /// Saisonplan (Zwift-Bibliothek, Longrun-Leiter).
  let schedule = SeasonSchedule.load()
  private(set) var today = CalendarDay(date: .now)
  private(set) var recovery: [TrendCard] = []
  private(set) var tiles: [Tile] = []
  private(set) var sleepStages: DailyMetrics?
  private(set) var weeks: [WeekVolume] = []
  private(set) var vo2Run: MetricTrend?
  private(set) var vo2Bike: MetricTrend?
  private(set) var zones: HeartRateZoneReport?
  /// FIT-Auswertungen (aerobe Kopplung, Runden für den Pace-Check).
  private(set) var analyses: [ActivityAnalysis] = []
  private(set) var restingHeartRate: Double?

  func update(
    days: [DailyMetrics],
    activities: [GarminActivity],
    profile: GarminProfile?,
    watchZones: JSONValue?,
    overrides: HeartRateOverrides,
    analyses: [ActivityAnalysis] = [],
    now: Date = .now
  ) {
    let today = CalendarDay(date: now)
    self.today = today
    let sorted = days.sorted { $0.day < $1.day }

    func card(
      _ title: String, _ unit: String, digits: Int = 0, higherIsBetter: Bool?, _ field: (DailyMetrics) -> Double?
    ) -> TrendCard {
      TrendCard(
        title: title, unit: unit, digits: digits, higherIsBetter: higherIsBetter,
        trend: MetricTrend(values: MetricTrend.values(sorted, field), days: 28, today: today))
    }
    recovery = [
      card("HRV · 7-Tage-Schnitt", "ms", higherIsBetter: nil) { $0.hrvWeeklyAverage },
      card("Ruhepuls", "bpm", higherIsBetter: false) { $0.restingHeartRate },
      card("Schlaf", "h", digits: 1, higherIsBetter: nil) { $0.sleepHours },
      card("Body Battery (Höchstwert)", "", higherIsBetter: true) { $0.bodyBatteryHigh },
    ].filter { !$0.trend.points.isEmpty }

    let latest = sorted.last { $0.day == today } ?? sorted.last { $0.day == today.adding(days: -1) }
    sleepStages = sorted.last { $0.deepSleepSeconds != nil && $0.day >= today.adding(days: -1) }
    let runVO2 = VO2MaxHistory.values(activities: activities, sport: .run)
    let bikeVO2 = VO2MaxHistory.values(activities: activities, sport: .bike)
    vo2Run = runVO2.isEmpty ? nil : MetricTrend(values: runVO2, days: 180, today: today)
    vo2Bike = bikeVO2.isEmpty ? nil : MetricTrend(values: bikeVO2, days: 180, today: today)
    let vo2 = profile?.vo2MaxRunning ?? runVO2.last?.value ?? sorted.last { $0.vo2Max != nil }?.vo2Max
    tiles = Self.tiles(latest: latest, vo2Max: vo2, vo2MaxBike: profile?.vo2MaxCycling ?? bikeVO2.last?.value)

    self.analyses = analyses
    restingHeartRate = sorted.last { $0.restingHeartRate != nil }?.restingHeartRate
    weeks = WeekVolume.history(activities: activities, today: today, weeks: 12)
    zones = HeartRateZoneCalculator.report(
      activities: activities, watchZonesJSON: watchZones, profile: profile, overrides: overrides, today: today)
  }

  /// Pace-Check mit der aktuell eingestellten Schwellenpace; ohne Ruhepuls wie im Altbestand 50 bpm.
  func paceCheck(thresholdPace: Int) -> PaceCheck.Result {
    PaceCheck.evaluate(
      ActivityAnalysisPlanner.paceSessions(analyses, today: today), thresholdPace: thresholdPace,
      lthr: zones?.run.lactateThreshold.map(Double.init), maxHeartRate: zones?.maxHeartRate.map(Double.init),
      restingHeartRate: restingHeartRate ?? 50)
  }

  func decoupled(_ sport: AerobicDecoupling.Sport) -> [ActivityAnalysis] {
    ActivityAnalysisPlanner.decoupled(analyses, sport: sport)
  }

  var skippedDecoupling: [ActivityAnalysis] {
    ActivityAnalysisPlanner.skipped(analyses)
  }

  static func tiles(latest: DailyMetrics?, vo2Max: Double?, vo2MaxBike: Double?) -> [Tile] {
    func text(_ value: Double?, _ unit: String = "", digits: Int = 0) -> String? {
      guard let value else { return nil }
      let number = value.formatted(.number.precision(.fractionLength(digits)))
      return unit.isEmpty ? number : "\(number) \(unit)"
    }
    let metrics = latest
    let battery: String? = metrics?.bodyBatteryHigh.map { high in
      let low = metrics?.bodyBatteryLow.map { " / \(Int($0))" } ?? ""
      return "\(Int(high))\(low)"
    }
    var flow: String?
    if let charged = metrics?.bodyBatteryCharged, let drained = metrics?.bodyBatteryDrained {
      flow = "+\(Int(charged)) / −\(Int(drained))"
    }
    let candidates: [(String, String?)] = [
      ("Body Battery (hoch / tief)", battery),
      ("Geladen / verbraucht", flow),
      ("Schlaf-Score", text(metrics?.sleepScore)),
      ("HRV letzte Nacht", text(metrics?.hrvLastNightAverage, "ms")),
      ("HRV-Status", metrics?.hrvStatus.map { RecoveryEvaluator.hrvStatusGerman[$0] ?? $0 }),
      ("Stress (Ø)", text(metrics?.stressAverage)),
      ("Atemfrequenz", text(metrics?.respirationWaking ?? metrics?.respirationSleep, "/min", digits: 1)),
      ("SpO2", text(metrics?.spo2Average, "%")),
      ("VO2max Laufen", text(vo2Max, digits: 1)),
      ("VO2max Rad", text(vo2MaxBike, digits: 1)),
      ("Fitnessalter", text(metrics?.fitnessAge, "J.", digits: 1)),
      ("Schritte", text(metrics?.steps)),
    ]
    return candidates.compactMap { title, value in value.map { Tile(title: title, value: $0) } }
  }
}
