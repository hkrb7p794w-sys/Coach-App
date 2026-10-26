import Foundation

/// Kanonische Nährwerte (wie `nutrients.py` im Altbestand). Alle Quellen – KI-Schätzung, Open Food Facts,
/// eigene Eingaben – werden auf diese Schlüssel und Einheiten normalisiert.
public enum Nutrient: String, CaseIterable, Codable, Sendable {
  case kcal
  case protein = "protein_g"
  case carbs = "carbs_g"
  case sugar = "sugar_g"
  case fat = "fat_g"
  case saturatedFat = "satfat_g"
  case fiber = "fiber_g"
  case water = "water_ml"
  case sodium = "sodium_mg"
  case potassium = "potassium_mg"
  case magnesium = "magnesium_mg"
  case calcium = "calcium_mg"
  case iron = "iron_mg"
  case zinc = "zinc_mg"
  case vitaminD = "vitd_ug"
  case vitaminB12 = "b12_ug"
  case vitaminC = "vitc_mg"
  case iodine = "iodine_ug"
  case omega3 = "omega3_mg"

  public var label: String {
    switch self {
    case .kcal: "Kalorien"
    case .protein: "Protein"
    case .carbs: "Kohlenhydrate"
    case .sugar: "davon Zucker"
    case .fat: "Fett"
    case .saturatedFat: "davon gesättigt"
    case .fiber: "Ballaststoffe"
    case .water: "Flüssigkeit"
    case .sodium: "Natrium"
    case .potassium: "Kalium"
    case .magnesium: "Magnesium"
    case .calcium: "Calcium"
    case .iron: "Eisen"
    case .zinc: "Zink"
    case .vitaminD: "Vitamin D"
    case .vitaminB12: "Vitamin B12"
    case .vitaminC: "Vitamin C"
    case .iodine: "Jod"
    case .omega3: "Omega-3 (EPA+DHA)"
    }
  }

  public var unit: String {
    switch self {
    case .kcal: "kcal"
    case .protein, .carbs, .sugar, .fat, .saturatedFat, .fiber: "g"
    case .water: "ml"
    case .sodium, .potassium, .magnesium, .calcium, .iron, .zinc, .vitaminC, .omega3: "mg"
    case .vitaminD, .vitaminB12, .iodine: "µg"
    }
  }

  public var isMacro: Bool {
    switch self {
    case .kcal, .protein, .carbs, .sugar, .fat, .saturatedFat, .fiber: true
    default: false
    }
  }

  /// Obergrenze statt Mindestziel (Zucker, gesättigte Fette) bzw. nur Referenz (Natrium).
  public var isUpperLimit: Bool {
    self == .sugar || self == .saturatedFat || self == .sodium
  }
}

/// Nährwerte als Zuordnung Nährstoff → Menge. Fehlende Werte sind unbekannt, nicht 0.
public struct NutrientValues: Equatable, Sendable {
  public private(set) var values: [Nutrient: Double] = [:]

  public init(_ values: [Nutrient: Double] = [:]) {
    self.values = values.filter { $0.value.isFinite }
  }

  public subscript(nutrient: Nutrient) -> Double? {
    get { values[nutrient] }
    set { values[nutrient] = newValue.flatMap { $0.isFinite ? $0 : nil } }
  }

  public var isEmpty: Bool { values.isEmpty }

  /// Werte je 100 g auf eine Menge umrechnen.
  public func scaled(toGrams grams: Double) -> NutrientValues {
    NutrientValues(values.mapValues { $0 * grams / 100 })
  }

  public static func + (lhs: NutrientValues, rhs: NutrientValues) -> NutrientValues {
    NutrientValues(lhs.values.merging(rhs.values, uniquingKeysWith: +))
  }
}

extension NutrientValues: Codable {
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode([String: Double].self)
    var values: [Nutrient: Double] = [:]
    for (key, value) in raw {
      if let nutrient = Nutrient(rawValue: key) { values[nutrient] = value }
    }
    self.init(values)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }))
  }
}
