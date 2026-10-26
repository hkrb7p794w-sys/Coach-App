import Foundation
import Testing

@testable import CoachCore

/// Vergleich mit dem Altbestand: Die Erwartungswerte in `Fixtures/analysis-cases.json` hat der Original-Code
/// (`decoupling.py`, `pace_check.py`, `tagesform.py`) aus Zufallsdaten berechnet; `run.zip` ist eine mit
/// `fit_tool` erzeugte FIT-Datei, `run-expected.json` deren Inhalt laut `fitparse`.
struct AnalysisTests {
  struct Cases: Decodable {
    struct SeriesCase: Decodable {
      let sport: String
      let samples: [[Double]]
      let expected: Expected?
    }
    struct Lap: Decodable {
      let distance: Double
      let duration: Double
      let averageHR: Double?
    }
    struct LapCase: Decodable {
      let laps: [Lap]
      let expected: Expected?
    }
    struct Expected: Decodable {
      let percent: Double
      let hr1: Double
      let hr2: Double
      let pace1: Int?
      let pace2: Int?
      let power1: Int?
      let power2: Int?
    }
    struct Activity: Decodable {
      struct ActivityType: Decodable { let typeKey: String? }
      let activityType: ActivityType
      let activityName: String?
      let duration: Double
      let distance: Double
      let avgPower: Double?
      let zone1: Double?
      let zone2: Double?
      let zone3: Double?
      let zone4: Double?
      let zone5: Double?

      enum CodingKeys: String, CodingKey {
        case activityType, activityName, duration, distance, avgPower
        case zone1 = "hrTimeInZone_1"
        case zone2 = "hrTimeInZone_2"
        case zone3 = "hrTimeInZone_3"
        case zone4 = "hrTimeInZone_4"
        case zone5 = "hrTimeInZone_5"
      }
    }
    struct ClassifyCase: Decodable {
      let activity: Activity
      let classify: String?
      let skip: String?
      let hard: Bool?
      let kind: String?
    }
    struct PaceLap: Decodable {
      let dur: Double
      let dist: Double
      let hr: Double?
      let hrmax: Double?
      let type: String?
    }
    struct PaceSession: Decodable {
      let id: Int64
      let date: String
      let name: String
      let kind: String
      let rpe: Double?
      let laps: [PaceLap]
    }
    struct PaceRow: Decodable {
      let id: Int64
      let verdict: String?
      let workMinutes: Int?
      let workPace: Int?
      let workHeartRate: Int?
      let percentOfThreshold: Int?
      let estimatedThreshold: Int?
      let peakPercent: Int?
    }
    struct PaceCase: Decodable {
      let thresholdPace: Int
      let lthr: Double?
      let maxHeartRate: Double?
      let restingHeartRate: Double
      let sessions: [PaceSession]
      let status: String
      let suggested: Int?
      let reason: String?
      let intervalBand: String
      let suggestedIntervalBand: String?
      let suggestionTitle: String?
      let suggestionText: String?
      let rows: [PaceRow]
    }
    let series: [SeriesCase]
    let laps: [LapCase]
    let classify: [ClassifyCase]
    let pace: [PaceCase]
  }

  private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  private func cases() throws -> Cases {
    try JSONDecoder().decode(Cases.self, from: fixture("analysis-cases", "json"))
  }

  private func activity(_ raw: Cases.Activity) -> GarminActivity {
    var activity = GarminActivity(id: 1)
    activity.typeKey = raw.activityType.typeKey
    activity.name = raw.activityName
    activity.durationSeconds = raw.duration
    activity.distanceMeters = raw.distance
    activity.averagePower = raw.avgPower
    let zones = [raw.zone1, raw.zone2, raw.zone3, raw.zone4, raw.zone5]
      .compactMap { $0 }
    if zones.count == 5, zones.reduce(0, +) > 0 { activity.secondsInZones = zones }
    return activity
  }

  @Test func decouplingFromSeriesMatchesOriginal() throws {
    let all = try cases().series
    #expect(all.contains { $0.expected != nil })
    for testCase in all {
      let sport = AerobicDecoupling.Sport(rawValue: testCase.sport)!
      let samples = testCase.samples.map { AerobicDecoupling.Sample(time: $0[0], output: $0[1], heartRate: $0[2]) }
      let result = AerobicDecoupling.fromSeries(samples, sport: sport)
      guard let expected = testCase.expected else {
        #expect(result == nil)
        continue
      }
      let value = try #require(result)
      #expect(abs(value.percent - expected.percent) < 0.051)
      #expect(abs(value.firstHalfHeartRate - expected.hr1) < 0.051)
      #expect(abs(value.secondHalfHeartRate - expected.hr2) < 0.051)
      #expect(value.firstHalfPace == expected.pace1)
      #expect(value.secondHalfPace == expected.pace2)
      #expect(value.firstHalfPower == expected.power1)
      #expect(value.secondHalfPower == expected.power2)
    }
  }

  @Test func decouplingFromLapsMatchesOriginal() throws {
    for testCase in try cases().laps {
      let laps = testCase.laps.map {
        FitLap(timerSeconds: $0.duration, distanceMeters: $0.distance, averageHeartRate: $0.averageHR)
      }
      let result = AerobicDecoupling.fromLaps(laps)
      guard let expected = testCase.expected else {
        #expect(result == nil)
        continue
      }
      let value = try #require(result)
      #expect(abs(value.percent - expected.percent) < 0.051)
      #expect(abs(value.firstHalfHeartRate - expected.hr1) < 0.051)
      #expect(value.firstHalfPace == expected.pace1)
      #expect(value.secondHalfPace == expected.pace2)
    }
  }

  @Test func classificationMatchesOriginal() throws {
    let kinds: [String: SessionKind] = [
      "locker": .easy, "test": .test, "vo2": .vo2, "schwelle": .threshold, "hart": .hard, "gym": .gym,
    ]
    for testCase in try cases().classify {
      let activity = activity(testCase.activity)
      let label = "\(testCase.activity.activityType.typeKey ?? "-") \(testCase.activity.activityName ?? "-")"
      #expect(AerobicDecoupling.classify(activity)?.rawValue == testCase.classify, "\(label)")
      #expect(AerobicDecoupling.skipReason(activity) == testCase.skip, "\(label)")
      guard let kind = testCase.kind else { continue }
      #expect(SessionKind.isHard(activity) == testCase.hard, "\(label)")
      #expect(SessionKind.of(activity) == kinds[kind], "\(label)")
    }
  }

  @Test func paceCheckMatchesOriginal() throws {
    let statuses: [String: PaceCheck.Status] = [
      "passt": .fits, "schneller": .faster, "langsamer": .slower, "zu wenig Daten": .tooFewData,
    ]
    for testCase in try cases().pace {
      let sessions = testCase.sessions.map { session in
        PaceCheck.Session(
          id: session.id, day: CalendarDay(iso: session.date)!, name: session.name,
          kind: session.kind == "vo2" ? .vo2 : .threshold, rpe: session.rpe,
          laps: session.laps.map {
            PaceCheck.Lap(
              duration: $0.dur, distance: $0.dist, heartRate: $0.hr, maxHeartRate: $0.hrmax,
              isWork: $0.type.map { ["ACTIVE", "INTERVAL"].contains($0) })
          })
      }
      let result = PaceCheck.evaluate(
        sessions, thresholdPace: testCase.thresholdPace, lthr: testCase.lthr, maxHeartRate: testCase.maxHeartRate,
        restingHeartRate: testCase.restingHeartRate)
      #expect(result.status == statuses[testCase.status])
      #expect(result.suggested == testCase.suggested)
      #expect(result.reason == testCase.reason)
      #expect(result.intervalBand == testCase.intervalBand)
      #expect(result.suggestedIntervalBand == testCase.suggestedIntervalBand)
      let suggestion = PaceCheck.suggestionText(result)
      #expect(suggestion?.title == testCase.suggestionTitle)
      #expect(suggestion?.text == testCase.suggestionText)
      #expect(result.rows.count == testCase.rows.count)
      for (row, expected) in zip(result.rows, testCase.rows) {
        #expect(row.id == expected.id)
        if let verdict = expected.verdict { #expect(row.verdict == verdict) }
        #expect(row.workMinutes == expected.workMinutes)
        #expect(row.workPace == expected.workPace)
        #expect(row.workHeartRate == expected.workHeartRate)
        #expect(row.heartRatePercentOfThreshold == expected.percentOfThreshold)
        #expect(row.estimatedThreshold == expected.estimatedThreshold)
        #expect(row.repetitionPeakPercentOfMax == expected.peakPercent)
      }
    }
  }

  // MARK: - FIT

  struct FitExpected: Decodable {
    struct Lap: Decodable {
      let timer: Double
      let elapsed: Double
      let distance: Double
      let avgHR: Double
      let maxHR: Double
      let intensity: Int
    }
    struct Decoupling: Decodable {
      let percent: Double
      let hr1: Double
      let hr2: Double
      let pace1: String
      let pace2: String
    }
    let recordCount: Int
    let withHeartRate: Int
    let withPower: Int
    let lastDistance: Double
    let firstSpeed: Double
    let laps: [Lap]
    let decoupling: Decoupling
  }

  @Test func readsGarminStyleZip() throws {
    let expected = try JSONDecoder().decode(FitExpected.self, from: fixture("run-expected", "json"))
    let fit = try FitDecoder.decode(ZipArchive.fitData(from: fixture("run", "zip")))
    #expect(fit.records.count == expected.recordCount)
    #expect(fit.records.filter { $0.heartRate != nil }.count == expected.withHeartRate)
    #expect(fit.records.filter { $0.power != nil }.count == expected.withPower)
    #expect(abs((fit.records.last?.distance ?? 0) - expected.lastDistance) < 0.001)
    #expect(abs((fit.records.first?.speed ?? 0) - expected.firstSpeed) < 0.0005)
    #expect(fit.laps.count == expected.laps.count)
    for (lap, want) in zip(fit.laps, expected.laps) {
      #expect(lap.timerSeconds == want.timer)
      #expect(lap.elapsedSeconds == want.elapsed)
      #expect(abs((lap.distanceMeters ?? 0) - want.distance) < 0.001)
      #expect(lap.averageHeartRate == want.avgHR)
      #expect(lap.maxHeartRate == want.maxHR)
      #expect(lap.intensity?.rawValue == want.intensity)
    }
    let result = try #require(AerobicDecoupling.compute(fit, sport: .run))
    #expect(result.source == .series)
    #expect(abs(result.percent - expected.decoupling.percent) < 0.051)
    #expect(abs(result.firstHalfHeartRate - expected.decoupling.hr1) < 0.051)
    #expect(result.firstHalfPace.map(PlanTokens.mmss) == expected.decoupling.pace1)
    #expect(result.secondHalfPace.map(PlanTokens.mmss) == expected.decoupling.pace2)
    // Runden für den Pace-Check: Aufwärmen, Pausen und Auslaufen zählen nicht als Arbeit.
    let work = PaceCheck.workLaps(PaceCheck.Lap.from(fit.laps), thresholdPace: 300)
    #expect(work.count == 4)
  }

  /// Handgebaute Datei: Big Endian, Entwicklerfeld, komprimierter Zeitstempel mit Überlauf.
  @Test func decodesCompressedTimestampsAndBigEndian() throws {
    var body: [UInt8] = []
    // Definition lokal 0: record (20), Big Endian, Felder 253 (4 Byte), 3 (1 Byte); 1 Entwicklerfeld à 2 Byte.
    body += [0x60, 0, 1, 0, 20, 2, 253, 4, 0x86, 3, 1, 0x02, 1, 0, 2, 0]
    // Daten: Zeit 1000 (0x3E8), HF 120, Entwicklerbytes.
    body += [0x00, 0, 0, 0x03, 0xE8, 120, 0xAA, 0xBB]
    // Definition lokal 1: record ohne Zeitfeld (nur HF), Little Endian.
    body += [0x41, 0, 0, 20, 0, 1, 3, 1, 2]
    // Komprimierter Zeitstempel lokal 1, Versatz 2 → 1000 & ~31 = 992, 992 + 2 < 1000 → +32 = 1026.
    body += [0x80 | (1 << 5) | 2, 130]
    // Ungültige HF (0xFF) fällt weg.
    body += [0x80 | (1 << 5) | 4, 0xFF]
    var header: [UInt8] = [12, 0x20, 0x08, 0x08]
    let size = UInt32(body.count)
    header += [UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24)]
    header += Array(".FIT".utf8)
    let fit = try FitDecoder.decode(Data(header + body + [0, 0]))
    #expect(fit.records.map(\.timestamp) == [1000, 1026, 1028])
    #expect(fit.records.map(\.heartRate) == [120, 130, nil])
  }

  @Test func inflatesStoredAndFixedBlocks() throws {
    // Gespeicherter Block "abc".
    #expect(try Inflate.decompress(Data([0x01, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63])) == Data("abc".utf8))
    // Feste Huffman-Codes: zlib.compress(b"aaaaaaaaaa")[2:-4] (Wiederholung mit Abstand 1).
    #expect(try Inflate.decompress(Data([0x4B, 0x4C, 0x84, 0x01, 0x00])) == Data("aaaaaaaaaa".utf8))
    #expect(throws: Inflate.Failure.self) { try Inflate.decompress(Data([0x07])) }
  }

  // MARK: - Auswahl und Speicherung

  private func run(
    _ id: Int64, day: String, name: String, minutes: Double, zones: [Double] = [1200, 1500, 300, 60, 0]
  ) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = "running"
    activity.name = name
    activity.startLocal = "\(day) 07:00:00"
    activity.durationSeconds = minutes * 60
    activity.distanceMeters = minutes * 170
    activity.secondsInZones = zones
    return activity
  }

  @Test func plannerPicksRecentRunsAndSkipsKnown() {
    let today = CalendarDay(iso: "2026-10-26")!
    let easy = run(1, day: "2026-10-25", name: "Berlin Laufen", minutes: 50)
    let threshold = run(2, day: "2026-10-24", name: "Schwelle 3x2 km", minutes: 50, zones: [600, 900, 600, 900, 0])
    let short = run(3, day: "2026-10-23", name: "Lockerer Lauf", minutes: 20)
    let old = run(4, day: "2026-07-01", name: "Berlin Laufen", minutes: 60)
    var known = ActivityAnalysis(id: 5, day: CalendarDay(iso: "2026-10-22")!, name: nil)
    let analyzedRun = run(5, day: "2026-10-22", name: "Berlin Laufen", minutes: 50)
    var outdated = ActivityAnalysis(id: 6, day: CalendarDay(iso: "2026-10-21")!, name: nil)
    outdated.method = 1
    let outdatedRun = run(6, day: "2026-10-21", name: "Berlin Laufen", minutes: 50)
    known.method = AerobicDecoupling.methodVersion

    let pending = ActivityAnalysisPlanner.pending(
      [old, short, threshold, easy, analyzedRun, outdatedRun], analyzed: [5: known, 6: outdated], today: today)
    #expect(pending.map(\.id) == [1, 2, 3, 6])
    #expect(ActivityAnalysisPlanner.needsFile(easy))
    #expect(ActivityAnalysisPlanner.needsFile(threshold))
    #expect(!ActivityAnalysisPlanner.needsFile(short))
    #expect(ActivityAnalysisPlanner.paceKind(threshold) == .threshold)
    #expect(ActivityAnalysisPlanner.paceKind(easy) == nil)

    // Kurzer Lauf: ohne Datei, nur mit Grund.
    let skipped = ActivityAnalysisPlanner.analyze(short, fit: nil, rpe: nil)
    #expect(skipped.skipReason == "kürzer als 35 min")
    #expect(skipped.decoupling == nil)
    // Schwellenlauf ohne lesbare Datei: Pace-Check bekommt leere Runden, Kopplung entfällt (zu intensiv).
    let hard = ActivityAnalysisPlanner.analyze(threshold, fit: nil, rpe: 8)
    #expect(hard.paceKind == .threshold)
    #expect(hard.laps == [])
    #expect(hard.skipReason == "zu intensiv (30 % der Zeit in Zone 4-5)")
    #expect(ActivityAnalysisPlanner.paceSessions([hard, skipped], today: today).map(\.id) == [2])
    #expect(ActivityAnalysisPlanner.needsRPE([hard, skipped], today: today).isEmpty)
    var noRPE = hard
    noRPE.rpe = nil
    #expect(ActivityAnalysisPlanner.needsRPE([noRPE], today: today) == [2])
    #expect(ActivityAnalysisPlanner.skipped([hard, skipped]).count == 2)
  }

  @Test func readsRPEFromActivityDetail() throws {
    let json = try JSONValue(data: Data(#"{"summaryDTO":{"directWorkoutRpe":70,"directWorkoutFeel":50}}"#.utf8))
    #expect(ActivityAnalysisPlanner.rpe(fromActivityDetail: json) == 7)
    let empty = try JSONValue(data: Data(#"{"summaryDTO":{}}"#.utf8))
    #expect(ActivityAnalysisPlanner.rpe(fromActivityDetail: empty) == nil)
  }

  @Test func recentAverageUsesLastFive() {
    let values = [1.0, 9.0, 3.0, 4.0, 5.0, 6.0]
    let sessions = values.enumerated().map { index, percent in
      var analysis = ActivityAnalysis(
        id: Int64(index), day: CalendarDay(year: 2026, month: 10, day: index + 1), name: nil)
      analysis.decouplingSport = .run
      analysis.decoupling = AerobicDecoupling.Result(
        percent: percent, firstHalfHeartRate: 140, secondHalfHeartRate: 145, source: .series)
      return analysis
    }
    #expect(ActivityAnalysisPlanner.recentAverage(sessions) == 5.4)
    #expect(ActivityAnalysisPlanner.decoupled(sessions.reversed(), sport: .run).map(\.id) == [0, 1, 2, 3, 4, 5])
  }
}
