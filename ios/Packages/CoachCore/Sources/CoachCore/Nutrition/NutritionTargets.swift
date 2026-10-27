import Foundation

/// Tagestyp für die Ernährungsziele.
public enum DayType: String, CaseIterable, Codable, Sendable, Comparable {
  case restDay = "ruhetag"
  case light = "leicht"
  case moderate = "moderat"
  case hard = "hart"
  case veryHard = "sehr_hart"

  public var label: String {
    switch self {
    case .restDay: "Ruhetag"
    case .light: "Leichter Tag"
    case .moderate: "Moderater Trainingstag"
    case .hard: "Harter Trainingstag"
    case .veryHard: "Sehr harter Trainingstag"
    }
  }

  /// Kohlenhydrate g/kg (Thomas, Erdman & Burke 2016, ACSM/AND/DC).
  public var carbsPerKilogram: Double {
    switch self {
    case .restDay: 3
    case .light: 4
    case .moderate: 6
    case .hard: 8
    case .veryHard: 10
    }
  }

  /// Anteil des Energie-Defizits/-Überschusses, der angewendet wird („fuel for the work“).
  var goalScale: Double {
    switch self {
    case .restDay, .light: 1
    case .moderate: 0.5
    case .hard, .veryHard: 0
    }
  }

  private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  public static func < (lhs: DayType, rhs: DayType) -> Bool { lhs.order < rhs.order }
}

public enum NutritionGoal: String, CaseIterable, Codable, Sendable {
  case maintain = "halten"
  case lose = "abnehmen"
  case gain = "aufbauen"
  case recomposition = "umformen"

  public var label: String {
    switch self {
    case .maintain: "Gewicht halten"
    case .lose: "Abnehmen"
    case .gain: "Aufbauen"
    case .recomposition: "Umformen (Fett ab, Muskeln auf)"
    }
  }

  var adjustPercent: Double {
    switch self {
    case .maintain: 0
    case .lose: -15
    case .gain: 10
    case .recomposition: -5
    }
  }

  /// Protein g/kg: Ausdauer ~1,8 (Williamson 2023), Aufbau bis 2,0 (Morton 2018), Defizit 2,2 (ISSN).
  var proteinPerKilogram: Double {
    switch self {
    case .maintain: 1.8
    case .gain: 2.0
    case .lose: 2.2
    case .recomposition: 2.0
    }
  }
}

public enum Diet: String, CaseIterable, Codable, Sendable {
  case omnivore = "alles"
  case pescetarian = "pescetarisch"
  case vegetarian = "vegetarisch"
  case vegan

  public var label: String {
    switch self {
    case .omnivore: "Alles"
    case .pescetarian: "Pescetarisch"
    case .vegetarian: "Vegetarisch"
    case .vegan: "Vegan"
    }
  }
}

public struct BodyProfile: Codable, Equatable, Sendable {
  public var weightKilograms: Double
  public var heightCentimeters: Double
  public var age: Int
  public var isFemale: Bool

  public init(weightKilograms: Double, heightCentimeters: Double, age: Int, isFemale: Bool) {
    self.weightKilograms = weightKilograms
    self.heightCentimeters = heightCentimeters
    self.age = age
    self.isFemale = isFemale
  }

  public static let fallback = BodyProfile(weightKilograms: 75, heightCentimeters: 180, age: 35, isFemale: false)
}

/// Einstellungen der Ernährung. Körperwerte sind optional: ohne Eintrag gelten die Garmin-Werte.
public struct NutritionSettings: Codable, Equatable, Sendable {
  public var goal: NutritionGoal = .maintain
  public var diet: Diet = .pescetarian
  /// Aktivitätsfaktor ohne Sport (PAL).
  public var activityFactor = 1.4
  public var bodyFatPercent: Double?
  public var weightKilograms: Double?
  public var heightCentimeters: Double?
  public var age: Int?
  public var isFemale: Bool?
  /// Gewünschte Gewichtsänderung in % des Körpergewichts pro Woche (negativ = abnehmen). Kommt aus dem Profil und
  /// hat Vorrang vor dem festen Prozentsatz des Ziels.
  public var weeklyWeightChangePercent: Double?
  /// Vom Nutzer übernommene Anpassung aus dem Gewichtsverlauf (kcal pro Tag, ±500).
  public var energyAdjustmentKilocalories: Double = 0

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    goal = (try? container.decodeIfPresent(NutritionGoal.self, forKey: .goal)) ?? .maintain
    diet = (try? container.decodeIfPresent(Diet.self, forKey: .diet)) ?? .pescetarian
    activityFactor = (try? container.decodeIfPresent(Double.self, forKey: .activityFactor)) ?? 1.4
    bodyFatPercent = try? container.decodeIfPresent(Double.self, forKey: .bodyFatPercent)
    weightKilograms = try? container.decodeIfPresent(Double.self, forKey: .weightKilograms)
    heightCentimeters = try? container.decodeIfPresent(Double.self, forKey: .heightCentimeters)
    age = try? container.decodeIfPresent(Int.self, forKey: .age)
    isFemale = try? container.decodeIfPresent(Bool.self, forKey: .isFemale)
    weeklyWeightChangePercent = try? container.decodeIfPresent(Double.self, forKey: .weeklyWeightChangePercent)
    energyAdjustmentKilocalories = min(
      max((try? container.decodeIfPresent(Double.self, forKey: .energyAdjustmentKilocalories)) ?? 0, -500), 500)
  }

  /// Einstellungen haben Vorrang, dann Garmin-Profil, dann Standardwerte.
  public func profile(garmin: GarminProfile?, on day: CalendarDay) -> BodyProfile {
    let fallback = BodyProfile.fallback
    return BodyProfile(
      weightKilograms: weightKilograms ?? garmin?.weightKilograms ?? fallback.weightKilograms,
      heightCentimeters: heightCentimeters ?? garmin?.heightCentimeters ?? fallback.heightCentimeters,
      age: age ?? garmin?.age(on: day) ?? fallback.age,
      isFemale: isFemale ?? garmin.map { $0.gender == "FEMALE" } ?? fallback.isFemale
    )
  }
}

public struct DayClassification: Equatable, Sendable {
  public let type: DayType
  public let enduranceMinutes: Double
  public let trainingMinutes: Double
  public let trainingLoad: Double
}

public struct NutritionTargets: Equatable, Sendable {
  public enum Source: String, Sendable {
    case garmin = "Garmin"
    case planned = "Wochenplan"
    case none = "keine Daten"
  }

  public let values: NutrientValues
  public let dayType: DayType
  public let source: Source
  public let classification: DayClassification
  public let profile: BodyProfile
  public let basalMetabolicRate: Double
  public let exerciseKilocalories: Double
  public let proteinPerKilogram: Double
  /// true, wenn die Energie auf 30 kcal/kg fettfreie Masse angehoben wurde (REDs-Schwelle).
  public let energyAvailabilityFloorApplied: Bool
}

/// Portierung von `ernaehrung/app/targets.py`.
///
/// - Energie: Grundumsatz nach Mifflin-St Jeor (1990) × PAL ohne Sport + Netto-kcal der Garmin-Aktivitäten.
/// - Kohlenhydrate je kg nach Tagestyp (Thomas, Erdman & Burke 2016), Protein je Ziel, Fett als Rest
///   (20–35 % der Energie, ACSM 2016).
/// - Mikronährstoffe, Ballaststoffe: DGE-Referenzwerte 25 bis < 51 Jahre; Jod 150 µg (DGE/ÖGE 2025);
///   Omega-3 EPA+DHA 250 mg (EFSA 2012).
/// - Flüssigkeit ~35 ml/kg + ~0,6 l je Stunde Ausdauer (ACSM 2016).
public enum NutritionPlanner {
  static let enduranceKeys = [
    "running", "cycling", "swimming", "lap_swimming", "open_water", "trail", "treadmill", "virtual_ride",
    "indoor_cycling", "rowing", "elliptical", "cross_country", "hiking", "multi_sport", "triathlon", "road_biking",
    "mountain_biking", "gravel",
  ]
  static let strengthKeys = ["strength", "fitness_equipment", "hiit", "yoga", "pilates", "training"]

  static func micro(isFemale: Bool) -> [Nutrient: Double] {
    [
      .sodium: 1500, .potassium: 4000, .magnesium: isFemale ? 300 : 350, .calcium: 1000,
      .iron: isFemale ? 16 : 11, .zinc: isFemale ? 8 : 14, .vitaminD: 20, .vitaminB12: 4,
      .vitaminC: isFemale ? 95 : 110, .fiber: 30, .iodine: 150, .omega3: 250,
    ]
  }

  public static func mifflinStJeor(_ profile: BodyProfile) -> Double {
    let base = 10 * profile.weightKilograms + 6.25 * profile.heightCentimeters - 5 * Double(profile.age)
    return base + (profile.isFemale ? -161 : 5)
  }

  static func isEndurance(_ typeKey: String?) -> Bool {
    let key = typeKey?.lowercased() ?? ""
    return enduranceKeys.contains { key.contains($0) } && !key.contains("walking")
  }

  static func isStrength(_ typeKey: String?) -> Bool {
    let key = typeKey?.lowercased() ?? ""
    return strengthKeys.contains { key.contains($0) }
  }

  public static func classify(_ activities: [GarminActivity]) -> DayClassification {
    let minutes = { (activity: GarminActivity) in (activity.durationSeconds ?? 0) / 60 }
    let endurance = activities.filter { isEndurance($0.typeKey) }.map(minutes).reduce(0, +)
    let total = activities.filter { isEndurance($0.typeKey) || isStrength($0.typeKey) }.map(minutes).reduce(0, +)
    let load = activities.compactMap(\.trainingLoad).reduce(0, +)
    let type: DayType =
      if endurance >= 240 {
        .veryHard
      } else if endurance >= 90 || load >= 150 {
        .hard
      } else if endurance >= 45 || total >= 75 || load >= 80 {
        .moderate
      } else if total >= 20 {
        .light
      } else {
        .restDay
      }
    return DayClassification(
      type: type, enduranceMinutes: endurance.rounded(), trainingMinutes: total.rounded(), trainingLoad: load.rounded())
  }

  /// Erwarteter Tagestyp aus dem Wochenplan, solange noch keine Aktivität aufgezeichnet ist –
  /// Kohlenhydrate gehören vor die Einheit (Impey et al. 2018).
  public static func plannedDayType(_ items: [TemplateItem]) -> DayType? {
    items.compactMap { item -> DayType? in
      let text = item.text.lowercased()
      if ["lange", "longrun", "koppel", "renn"].contains(where: { text.contains($0) }) { return .hard }
      switch item.kind {
      case .bike, .run: return .moderate
      case .strength, .swimOrLegs: return .light
      case .optional: return nil
      }
    }.max()
  }

  public static func compute(
    activities: [GarminActivity],
    planItems: [TemplateItem],
    settings: NutritionSettings,
    garminProfile: GarminProfile?,
    day: CalendarDay,
    hasGarminData: Bool
  ) -> NutritionTargets {
    let profile = settings.profile(garmin: garminProfile, on: day)
    let weight = profile.weightKilograms
    let classification = classify(activities)
    var dayType = classification.type
    var source: NutritionTargets.Source = hasGarminData ? .garmin : .none
    if activities.isEmpty, let planned = plannedDayType(planItems), planned > dayType {
      dayType = planned
      source = .planned
    }

    let bmr = mifflinStJeor(profile)
    let baseKcal = bmr * settings.activityFactor
    let exerciseKcal = activities.reduce(0.0) { sum, activity in
      let minutes = (activity.durationSeconds ?? 0) / 60
      return sum + max(0, (activity.calories ?? 0) - bmr / 1440 * minutes)
    }
    let dayEnergy = baseKcal + exerciseKcal
    var adjustPercent = settings.goal.adjustPercent
    if let weekly = settings.weeklyWeightChangePercent, dayEnergy > 0 {
      // 7.700 kcal je kg Körpergewicht; Grenzen: höchstens 25 % Defizit bzw. 15 % Überschuss.
      let dailyKilocalories = weekly / 100 * weight * 7_700 / 7
      adjustPercent = max(-25, min(15, dailyKilocalories / dayEnergy * 100))
    }
    let goalPercent = adjustPercent * dayType.goalScale
    var energy = dayEnergy * (1 + goalPercent / 100) + settings.energyAdjustmentKilocalories

    // Energieverfügbarkeit bei Defizit nicht unter 30 kcal/kg fettfreie Masse (IOC-Konsensus REDs 2023).
    let bodyFat = settings.bodyFatPercent ?? (profile.isFemale ? 25 : 15)
    let fatFreeMass = weight * (1 - bodyFat / 100)
    var floorApplied = false
    if goalPercent < 0, energy < 30 * fatFreeMass + exerciseKcal {
      energy = 30 * fatFreeMass + exerciseKcal
      floorApplied = true
    }

    let proteinPerKilogram = settings.goal.proteinPerKilogram
    let protein = proteinPerKilogram * weight
    var carbs = dayType.carbsPerKilogram * weight
    let rest = energy - 4 * protein - 4 * carbs
    let fatMinimum = 0.20 * energy / 9
    let fatMaximum = 0.35 * energy / 9
    let fat = min(max(rest / 9, fatMinimum), fatMaximum)
    if rest / 9 > fatMaximum { carbs += (rest - fat * 9) / 4 }
    let total = 4 * protein + 4 * carbs + 9 * fat

    let water =
      35 * weight + 10 * classification.enduranceMinutes
      + 5 * max(0, classification.trainingMinutes - classification.enduranceMinutes)

    var values = NutrientValues(micro(isFemale: profile.isFemale))
    values[.kcal] = total.rounded()
    values[.protein] = protein.rounded()
    values[.carbs] = carbs.rounded()
    values[.fat] = fat.rounded()
    values[.sugar] = (0.10 * total / 4).rounded()
    values[.saturatedFat] = (0.10 * total / 9).rounded()
    values[.water] = (water / 50).rounded() * 50

    return NutritionTargets(
      values: values,
      dayType: dayType,
      source: source,
      classification: classification,
      profile: profile,
      basalMetabolicRate: bmr.rounded(),
      exerciseKilocalories: exerciseKcal.rounded(),
      proteinPerKilogram: proteinPerKilogram,
      energyAvailabilityFloorApplied: floorApplied
    )
  }
}
