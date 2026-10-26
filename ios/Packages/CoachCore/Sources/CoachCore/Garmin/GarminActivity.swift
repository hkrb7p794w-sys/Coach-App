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

    init(typeKey: String?) {
      let key = typeKey?.lowercased() ?? ""
      if key.contains("strength") || key.contains("fitness_equipment") {
        self = .strength
      } else if key.contains("swim") {
        self = .swim
      } else if key.contains("cycling") || key.contains("biking") || key.contains("bike") {
        self = .bike
      } else if key.contains("running") || key.contains("run") || key.contains("trail") {
        self = .run
      } else {
        self = .other
      }
    }
  }
}

public enum GarminActivityParser {
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
    activity.aerobicTrainingEffect = record["aerobicTrainingEffect"]?.doubleValue
    activity.anaerobicTrainingEffect = record["anaerobicTrainingEffect"]?.doubleValue
    activity.averagePower = record["avgPower"]?.doubleValue
    activity.normalizedPower = record["normPower"]?.doubleValue
    activity.elevationGain = record["elevationGain"]?.doubleValue
    activity.vo2Max = record["vO2MaxValue"]?.doubleValue
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
    lactateThresholdHeartRate = data.firstValue(forAnyOf: ["lactateThresholdHeartRate"])?.doubleValue
  }

  public func age(on day: CalendarDay) -> Int? {
    guard let birthDate else { return nil }
    var age = day.year - birthDate.year
    if (day.month, day.day) < (birthDate.month, birthDate.day) { age -= 1 }
    return age
  }
}
