import Foundation
import Testing

@testable import CoachCore

struct ActivityDetailsTests {
  private var listJSON: JSONValue {
    .array([
      .object([
        "activityId": .number(42), "activityName": .string("Lauf"), "activityType": .object(["typeKey": .string("running")]),
        "startTimeLocal": .string("2026-10-25 08:00:00"), "duration": .number(3_000), "movingDuration": .number(2_950),
        "distance": .number(10_000), "averageSpeed": .number(3.333), "maxSpeed": .number(4.5),
        "averageHR": .number(148), "maxHR": .number(171), "elevationGain": .number(85), "elevationLoss": .number(84),
        "averageRunningCadenceInStepsPerMinute": .number(172), "avgStrideLength": .number(116.4),
        "avgGroundContactTime": .number(242), "avgVerticalOscillation": .number(8.6), "avgVerticalRatio": .number(7.4),
        "aerobicTrainingEffect": .number(3.4), "trainingEffectLabel": .string("TEMPO"),
        "hrTimeInZone_1": .number(300), "hrTimeInZone_2": .number(900), "hrTimeInZone_3": .number(1_200),
        "hrTimeInZone_4": .number(600), "hrTimeInZone_5": .number(0),
      ])
    ])
  }

  @Test func runSectionsLikeGarmin() throws {
    let activity = try #require(GarminActivityParser.activities(listJSON).first)
    let sections = ActivityDetails.sections(activity)
    let titles = sections.map(\.title)
    #expect(titles.contains("Laufdynamik"))
    #expect(!titles.contains("Schwimmen"))
    let rows = Dictionary(sections.flatMap(\.rows).map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
    #expect(rows["Distanz"] == "10 km")
    #expect(rows["Zeit"] == "50:00")
    #expect(rows["Ø Pace"] == "5:00 /km")
    #expect(rows["Beste Pace"] == "3:42 /km")
    #expect(rows["Ø Schrittlänge"] == "1,16 m")
    #expect(rows["Ø Bodenkontaktzeit"] == "242 ms")
    #expect(rows["Schwerpunkt"] == "Tempo")
    #expect(rows["Zone 3"] == "20:00 (40 %)")
  }

  @Test func detailFillsMissingValues() throws {
    let base = try #require(GarminActivityParser.activities(listJSON).first)
    var sparse = GarminActivity(id: 42)
    sparse.distanceMeters = 9_999
    let detail = JSONValue.object([
      "activityId": .number(42), "activityTypeDTO": .object(["typeKey": .string("running")]),
      "summaryDTO": .object([
        "distance": .number(10_000), "maxRunCadence": .number(188), "normalizedPower": .number(260),
        "minElevation": .number(4),
      ]),
    ])
    let merged = GarminActivityParser.detail(detail, base: sparse)
    #expect(merged.distanceMeters == 9_999)
    #expect(merged.maxCadence == 188)
    #expect(merged.normalizedPower == 260)
    #expect(merged.minElevation == 4)
    #expect(merged.typeKey == "running")
    #expect(GarminActivityParser.detail(.null, base: base) == base)
  }

  @Test func swimAndBikeFormats() {
    #expect(ActivityDetails.speed(1.0, sport: .swim) == "1:40 /100 m")
    #expect(ActivityDetails.speed(8.0, sport: .bike) == "28,8 km/h")
    #expect(ActivityDetails.distance(1_500, sport: .swim) == "1500 m")
    #expect(ActivityDetails.duration(3_930) == "1:05:30")
  }

  @Test func samplesAndRouteFromFit() {
    var records: [FitRecord] = []
    for second in 0..<600 {
      var record = FitRecord(
        timestamp: Double(second), heartRate: 140, speed: 3.0, power: nil, distance: Double(second) * 3)
      record.cadence = 86
      record.altitude = 10 + Double(second) / 60
      record.latitude = 52.5 + Double(second) / 100_000
      record.longitude = 13.4
      records.append(record)
    }
    let fit = FitActivity(records: records, laps: [])
    let samples = ActivityDetails.samples(fit, sport: .run, maxPoints: 60)
    #expect(samples.count == 60)
    #expect(samples.first?.cadence == 172)
    #expect(abs((samples.first?.pace ?? 0) - 333.3) < 1)
    #expect(samples.last?.x == 1.797)
    #expect(ActivityDetails.route(fit, maxPoints: 100).count == 100)
  }

  @Test func fitDecoderReadsSignedPositions() {
    #expect(FitDecoder.signed32(4_294_967_295) == -1)
    #expect(FitDecoder.signed32(100) == 100)
  }
}
