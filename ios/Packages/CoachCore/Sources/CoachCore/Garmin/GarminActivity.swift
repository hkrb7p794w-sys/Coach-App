import Foundation

/// Zusammenfassung einer Garmin-Aktivität aus der Aktivitätssuche.
public struct GarminActivity: Codable, Equatable, Sendable, Identifiable {
  public let id: Int64
  public var name: String?
  /// Garmins `activityType.typeKey`, z. B. `running`, `cycling`, `lap_swimming`, `strength_training`.
  public var typeKey: String?
  /// Lokale Startzeit wie von Garmin geliefert (`yyyy-MM-dd HH:mm:ss`).
  public var startLocal: String?
  public var durationSeconds: Double?
  public var distanceMeters: Double?
  public var averageHeartRate: Double?
  public var maxHeartRate: Double?
  public var calories: Double?
  public var trainingLoad: Double?
  public var aerobicTrainingEffect: Double?
  public var anaerobicTrainingEffect: Double?
  public var averagePower: Double?
  public var normalizedPower: Double?
  public var elevationGain: Double?
  public var vo2Max: Double?
  /// Sekunden in den fünf Herzfrequenzzonen der Uhr (`hrTimeInZone_1` … `_5`).
  public var secondsInZones: [Double]?
  // Weitere Werte der Aktivitätsliste, wie sie Garmin Connect in der Übersicht zeigt.
  public var movingSeconds: Double?
  public var elapsedSeconds: Double?
  /// m/s
  public var averageSpeed: Double?
  public var maxSpeed: Double?
  public var elevationLoss: Double?
  public var minElevation: Double?
  public var maxElevation: Double?
  /// Schritte pro Minute (Laufen) bzw. Umdrehungen pro Minute (Rad).
  public var averageCadence: Double?
  public var maxCadence: Double?
  /// cm
  public var strideLength: Double?
  /// ms
  public var groundContactTime: Double?
  /// cm
  public var verticalOscillation: Double?
  /// %
  public var verticalRatio: Double?
  public var maxPower: Double?
  public var steps: Double?
  /// m
  public var poolLength: Double?
  public var lengths: Double?
  public var strokes: Double?
  public var swolf: Double?
  /// Züge pro Minute
  public var strokeRate: Double?
  public var minTemperature: Double?
  public var maxTemperature: Double?
  public var lapCount: Double?
  /// Garmins Einordnung, z. B. `TEMPO`, `AEROBIC_BASE`, `VO2MAX`.
  public var trainingEffectLabel: String?
  public var locationName: String?
  public var activeKilocalories: Double?

  public init(id: Int64) {
    self.id = id
  }

  public var day: CalendarDay? {
    startLocal.flatMap { CalendarDay(iso: $0) }
  }

  public var sport: Sport {
    Sport(typeKey: typeKey)
  }

  /// Grobe Sportart für Wochen-Soll/Ist und Ernährungsziele.
  public enum Sport: String, Codable, Sendable {
    case run, bike, swim, strength, other

    /// Gleiche Reihenfolge und Schlüsselwörter wie der Altbestand (`app.py`, Wochenvolumen).
    init(typeKey: String?) {
      let key = typeKey?.lowercased() ?? ""
      if key.contains("swim") {
        self = .swim
      } else if key.contains("bik") || key.contains("cycl") || key.contains("ride") {
        self = .bike
      } else if key.contains("run") {
        self = .run
      } else if key.contains("strength") || key.contains("weight") || key.contains("gym") {
        self = .strength
      } else {
        self = .other
      }
    }
  }
}

public enum GarminActivityParser {
  /// `/activity-service/activity/{id}`: Werte stehen unter `summaryDTO`, die Art unter `activityTypeDTO`.
  /// Ergänzt fehlende Werte von `base`; vorhandene Werte bleiben.
  public static func detail(_ json: JSONValue, base: GarminActivity) -> GarminActivity {
    guard case .object(let top) = json else { return base }
    var record = top
    if case .object(let summary)? = top["summaryDTO"] {
      for (key, value) in summary { record[key] = value }
    }
    if let type = top["activityTypeDTO"]?["typeKey"] { record["activityType"] = .object(["typeKey": type]) }
    record["activityId"] = .number(Double(base.id))
    guard let detail = activity(record) else { return base }
    return merged(base, filledFrom: detail)
  }

  /// Fehlende Felder von `base` aus `other` (über die Codable-Darstellung, damit kein Feld vergessen wird).
  static func merged(_ base: GarminActivity, filledFrom other: GarminActivity) -> GarminActivity {
    guard let baseData = try? JSONEncoder().encode(base), let otherData = try? JSONEncoder().encode(other),
      var baseObject = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any],
      let otherObject = (try? JSONSerialization.jsonObject(with: otherData)) as? [String: Any]
    else { return base }
    for (key, value) in otherObject where baseObject[key] == nil || baseObject[key] is NSNull {
      baseObject[key] = value
    }
    guard let data = try? JSONSerialization.data(withJSONObject: baseObject),
      let result = try? JSONDecoder().decode(GarminActivity.self, from: data)
    else { return base }
    return result
  }

  /// `/activitylist-service/activities/search/activities` – Liste (oder Objekt mit Liste) von
  /// Aktivitäten mit `activityId`.
  public static func activities(_ json: JSONValue) -> [GarminActivity] {
    json.objects(containingKey: "activityId").compactMap(activity)
  }

  static func activity(_ record: [String: JSONValue]) -> GarminActivity? {
    guard let rawID = record["activityId"]?.doubleValue, rawID > 0, rawID < 9e15 else { return nil }
    var activity = GarminActivity(id: Int64(rawID))
    activity.name = record["activityName"]?.stringValue
    activity.typeKey = record["activityType"]?["typeKey"]?.stringValue ?? record["activityType"]?.stringValue
    activity.startLocal = record["startTimeLocal"]?.stringValue
    activity.durationSeconds = record["duration"]?.doubleValue ?? record["elapsedDuration"]?.doubleValue
    activity.distanceMeters = record["distance"]?.doubleValue
    activity.averageHeartRate = record["averageHR"]?.doubleValue
    activity.maxHeartRate = record["maxHR"]?.doubleValue
    activity.calories = record["calories"]?.doubleValue
    activity.trainingLoad = record["activityTrainingLoad"]?.doubleValue
    activity.aerobicTrainingEffect = (record["aerobicTrainingEffect"] ?? record["trainingEffect"])?.doubleValue
    activity.anaerobicTrainingEffect = record["anaerobicTrainingEffect"]?.doubleValue
    activity.averagePower = record["avgPower"]?.doubleValue
    activity.normalizedPower = (record["normPower"] ?? record["normalizedPower"])?.doubleValue
    activity.elevationGain = record["elevationGain"]?.doubleValue
    activity.vo2Max = record["vO2MaxValue"]?.doubleValue
    activity.movingSeconds = record["movingDuration"]?.doubleValue
    activity.elapsedSeconds = record["elapsedDuration"]?.doubleValue
    activity.averageSpeed = record["averageSpeed"]?.doubleValue
    activity.maxSpeed = record["maxSpeed"]?.doubleValue
    activity.elevationLoss = record["elevationLoss"]?.doubleValue
    activity.minElevation = record["minElevation"]?.doubleValue
    activity.maxElevation = record["maxElevation"]?.doubleValue
    activity.averageCadence =
      (record["averageRunningCadenceInStepsPerMinute"] ?? record["averageRunCadence"]
      ?? record["averageBikingCadenceInRevPerMinute"] ?? record["averageBikeCadence"])?.doubleValue
    activity.maxCadence =
      (record["maxRunningCadenceInStepsPerMinute"] ?? record["maxRunCadence"]
      ?? record["maxBikingCadenceInRevPerMinute"] ?? record["maxBikeCadence"])?.doubleValue
    activity.strideLength = (record["avgStrideLength"] ?? record["strideLength"])?.doubleValue
    activity.groundContactTime = (record["avgGroundContactTime"] ?? record["groundContactTime"])?.doubleValue
    activity.verticalOscillation = (record["avgVerticalOscillation"] ?? record["verticalOscillation"])?.doubleValue
    activity.verticalRatio = (record["avgVerticalRatio"] ?? record["verticalRatio"])?.doubleValue
    activity.maxPower = record["maxPower"]?.doubleValue
    activity.steps = record["steps"]?.doubleValue
    activity.poolLength = record["poolLength"]?.doubleValue
    activity.lengths = record["activeLengths"]?.doubleValue
    activity.strokes = record["totalNumberOfStrokes"]?.doubleValue ?? record["strokes"]?.doubleValue
    activity.swolf = record["averageSwolf"]?.doubleValue
    activity.strokeRate = record["averageSwimCadenceInStrokesPerMinute"]?.doubleValue
    activity.minTemperature = record["minTemperature"]?.doubleValue
    activity.maxTemperature = record["maxTemperature"]?.doubleValue
    activity.lapCount = record["lapCount"]?.doubleValue
    activity.trainingEffectLabel = record["trainingEffectLabel"]?.stringValue
    activity.locationName = record["locationName"]?.stringValue
    activity.activeKilocalories = record["activeKilocalories"]?.doubleValue
    let zones = (1...5).compactMap { record["hrTimeInZone_\($0)"]?.doubleValue }
    if zones.count == 5, zones.reduce(0, +) > 0 { activity.secondsInZones = zones }
    return activity
  }
}

/// Körperdaten aus den Profileinstellungen (für Ernährungsziele).
public struct GarminProfile: Codable, Equatable, Sendable {
  public var weightKilograms: Double?
  public var heightCentimeters: Double?
  public var birthDate: CalendarDay?
  /// `MALE` oder `FEMALE`.
  public var gender: String?
  public var vo2MaxRunning: Double?
  public var vo2MaxCycling: Double?
  public var lactateThresholdHeartRate: Double?

  public init() {}

  /// `/userprofile-service/userprofile/settings` (Werte unter `userData`; Gewicht in Gramm).
  public init(settings json: JSONValue) {
    let data = json["userData"] ?? json
    if let grams = data.firstValue(forAnyOf: ["weight"])?.doubleValue, grams > 0 {
      weightKilograms = grams > 500 ? (grams / 100).rounded() / 10 : grams
    }
    heightCentimeters = data.firstValue(forAnyOf: ["height"])?.doubleValue
    birthDate = data.firstValue(forAnyOf: ["birthDate"])?.stringValue.flatMap { CalendarDay(iso: $0) }
    gender = data.firstValue(forAnyOf: ["gender"])?.stringValue?.uppercased()
    vo2MaxRunning = data.firstValue(forAnyOf: ["vo2MaxRunning"])?.doubleValue
    vo2MaxCycling = data.firstValue(forAnyOf: ["vo2MaxCycling"])?.doubleValue
    lactateThresholdHeartRate = data.firstValue(forAnyOf: ["lactateThresholdHeartRate"])?.doubleValue
  }

  public func age(on day: CalendarDay) -> Int? {
    guard let birthDate else { return nil }
    var age = day.year - birthDate.year
    if (day.month, day.day) < (birthDate.month, birthDate.day) { age -= 1 }
    return age
  }
}
