import Foundation

/// Open Food Facts – Produktabfrage per Barcode (API v2).
///
/// Regeln laut OFF-Doku: eigener User-Agent, höchstens 15 Produktabfragen je Minute. Daten unter Open Database
/// License (ODbL), © Open Food Facts contributors. Werte in `nutriments` sind je 100 g; Mineralstoffe und
/// Vitamine stehen dort in Gramm.
public enum OpenFoodFacts {
  public static let userAgent = "CoachApp/0.4 (iOS; privat)"
  static let fields =
    "code,product_name,product_name_de,generic_name_de,brands,quantity,serving_quantity,nutriments"

  public struct Product: Equatable, Sendable {
    public let barcode: String
    public let name: String
    public let brand: String?
    public let servingGrams: Double?
    public let per100g: NutrientValues

    public func item(grams: Double? = nil) -> MealItem {
      var item = MealItem(
        name: brand.map { "\(name) (\($0))" } ?? name, grams: grams ?? servingGrams ?? 100,
        source: .openFoodFacts, per100g: per100g)
      item.barcode = barcode
      return item
    }
  }

  /// Prüfziffer nach GS1 für EAN-8, UPC-A, EAN-13 und GTIN-14.
  public static func isValidBarcode(_ text: String) -> Bool {
    let digits = text.compactMap(\.wholeNumberValue)
    guard digits.count == text.count, [8, 12, 13, 14].contains(digits.count), let check = digits.last else {
      return false
    }
    let body = digits.dropLast().reversed()
    let sum = body.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
    return (10 - sum % 10) % 10 == check
  }

  public static func productURL(barcode: String) -> URL? {
    var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)")
    components?.queryItems = [URLQueryItem(name: "fields", value: fields)]
    return components?.url
  }

  private static let mapping: [(String, Nutrient, Double)] = [
    ("energy-kcal", .kcal, 1), ("proteins", .protein, 1), ("carbohydrates", .carbs, 1), ("sugars", .sugar, 1),
    ("fat", .fat, 1), ("saturated-fat", .saturatedFat, 1), ("fiber", .fiber, 1), ("sodium", .sodium, 1000),
    ("potassium", .potassium, 1000), ("magnesium", .magnesium, 1000), ("calcium", .calcium, 1000),
    ("iron", .iron, 1000), ("zinc", .zinc, 1000), ("vitamin-d", .vitaminD, 1_000_000),
    ("vitamin-b12", .vitaminB12, 1_000_000), ("vitamin-c", .vitaminC, 1000), ("iodine", .iodine, 1_000_000),
  ]

  /// Liest die API-Antwort. `nil`, wenn das Produkt unbekannt ist oder keine Kalorienangabe hat.
  public static func product(from json: JSONValue, barcode: String) -> Product? {
    guard json["status"]?.doubleValue != 0, let product = json["product"],
      let nutriments = product["nutriments"]
    else { return nil }
    var values = NutrientValues()
    for (key, nutrient, factor) in mapping {
      if let value = nutriments["\(key)_100g"]?.doubleValue, value >= 0 { values[nutrient] = value * factor }
    }
    if values[.kcal] == nil, let kilojoule = nutriments["energy_100g"]?.doubleValue {
      values[.kcal] = (kilojoule / 4.184).rounded()
    }
    let omega3 = ["eicosapentaenoic-acid", "docosahexaenoic-acid"].compactMap {
      nutriments["\($0)_100g"]?.doubleValue
    }
    if !omega3.isEmpty { values[.omega3] = omega3.reduce(0, +) * 1000 }
    guard values[.kcal] != nil else { return nil }

    let names = ["product_name_de", "product_name", "generic_name_de"].compactMap { product[$0]?.stringValue }
    let name = names.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Produkt \(barcode)"
    let brand = product["brands"]?.stringValue?.split(separator: ",").first.map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    let serving = product["serving_quantity"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
    return Product(
      barcode: barcode, name: name, brand: brand?.isEmpty == false ? brand : nil, servingGrams: serving,
      per100g: values)
  }
}
