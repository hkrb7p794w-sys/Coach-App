import Foundation
import Testing

@testable import CoachCore

private let day = CalendarDay(year: 2026, month: 10, day: 23)

private func activity(_ typeKey: String, minutes: Double, kcal: Double = 0, load: Double? = nil) -> GarminActivity {
  var activity = GarminActivity(id: Int64(minutes * 100))
  activity.typeKey = typeKey
  activity.durationSeconds = minutes * 60
  activity.calories = kcal
  activity.trainingLoad = load
  activity.startLocal = "\(day.iso) 07:00:00"
  return activity
}

struct NutritionTargetTests {
  private var settings: NutritionSettings {
    var settings = NutritionSettings()
    settings.weightKilograms = 80
    settings.heightCentimeters = 180
    settings.age = 36
    settings.isFemale = false
    return settings
  }

  @Test func classifiesDayByEnduranceStrengthAndLoad() {
    #expect(NutritionPlanner.classify([]).type == .restDay)
    #expect(NutritionPlanner.classify([activity("strength_training", minutes: 45)]).type == .light)
    #expect(NutritionPlanner.classify([activity("running", minutes: 50)]).type == .moderate)
    #expect(NutritionPlanner.classify([activity("strength_training", minutes: 80)]).type == .moderate)
    #expect(NutritionPlanner.classify([activity("virtual_ride", minutes: 95)]).type == .hard)
    #expect(NutritionPlanner.classify([activity("running", minutes: 30, load: 160)]).type == .hard)
    #expect(NutritionPlanner.classify([activity("cycling", minutes: 250)]).type == .veryHard)
    #expect(NutritionPlanner.classify([activity("walking", minutes: 120)]).type == .restDay)
  }

  @Test func plannedDayTypeFromWeekTemplate() {
    #expect(NutritionPlanner.plannedDayType([TemplateItem(kind: .strength, text: "Push (Home-Gym)")]) == .light)
    #expect(
      NutritionPlanner.plannedDayType([TemplateItem(kind: .bike, text: "Zwift-Einheit (Sa oder So)")]) == .moderate)
    #expect(
      NutritionPlanner.plannedDayType([TemplateItem(kind: .bike, text: "Lange Radeinheit + Koppellauf")]) == .hard)
    #expect(NutritionPlanner.plannedDayType([TemplateItem(kind: .optional, text: "locker")]) == nil)
  }

  /// Grundumsatz und Verbrauch wie in `targets.py`; die Makros weichen bewusst ab: Fett bleibt bei mindestens 20 %
  /// der Energie, Kohlenhydrate werden dafür gekürzt (`targets.py` überschritt sonst die Tagesenergie).
  @Test func computesTargetsLikeLegacyAddOn() {
    let targets = NutritionPlanner.compute(
      activities: [activity("running", minutes: 60, kcal: 700, load: 90)], planItems: [], settings: settings,
      garminProfile: nil, day: day, hasGarminData: true)

    #expect(targets.dayType == .moderate)
    #expect(targets.source == .garmin)
    #expect(targets.basalMetabolicRate == 1750)
    #expect(targets.exerciseKilocalories == 627)
    let kcal = targets.values[.kcal] ?? 0
    let carbs = targets.values[.carbs] ?? 0
    let fat = targets.values[.fat] ?? 0
    #expect(abs(kcal - 3_077) <= 2)
    #expect(targets.values[.protein] == 144)
    #expect((400...480).contains(carbs))
    #expect(9 * fat / kcal >= 0.195)
    #expect(abs(4 * 144 + 4 * carbs + 9 * fat - kcal) <= 10)
    #expect(targets.values[.water] == 3400)
    #expect(targets.values[.iron] == 11)
    #expect(targets.values[.iodine] == 150)
  }

  @Test func plannedHardDayRaisesCarbsBeforeTraining() {
    let targets = NutritionPlanner.compute(
      activities: [], planItems: [TemplateItem(kind: .bike, text: "Lange Radeinheit + Koppellauf (Sa oder So)")],
      settings: settings, garminProfile: nil, day: day, hasGarminData: true)
    #expect(targets.dayType == .hard)
    #expect(targets.source == .planned)
    // Geplante 90 Minuten Ausdauer (MET 7) fließen in die Energie ein; Kohlenhydrate mindestens 6 g/kg.
    #expect(targets.exerciseKilocalories == 720)
    #expect(targets.values[.carbs] ?? 0 >= 480)
    let kcal = targets.values[.kcal] ?? 0
    #expect(9 * (targets.values[.fat] ?? 0) / kcal >= 0.195)
  }

  @Test func deficitIsSkippedOnHardDaysAndFloored() {
    var losing = settings
    losing.goal = .lose
    let rest = NutritionPlanner.compute(
      activities: [], planItems: [], settings: losing, garminProfile: nil, day: day, hasGarminData: true)
    let maintain = NutritionPlanner.compute(
      activities: [], planItems: [], settings: settings, garminProfile: nil, day: day, hasGarminData: true)
    #expect((rest.values[.kcal] ?? 0) < (maintain.values[.kcal] ?? 0))
    #expect(rest.proteinPerKilogram == 2.2)

    let hard = [activity("running", minutes: 100, kcal: 1100)]
    let hardLosing = NutritionPlanner.compute(
      activities: hard, planItems: [], settings: losing, garminProfile: nil, day: day, hasGarminData: true)
    let hardMaintain = NutritionPlanner.compute(
      activities: hard, planItems: [], settings: settings, garminProfile: nil, day: day, hasGarminData: true)
    // Kein Defizit an harten Tagen; Unterschied nur durch das höhere Protein.
    #expect(abs((hardLosing.values[.kcal] ?? 0) - (hardMaintain.values[.kcal] ?? 0)) < 200)
  }

  @Test func profileFallsBackToGarminThenDefaults() {
    var garmin = GarminProfile()
    garmin.weightKilograms = 70
    garmin.gender = "FEMALE"
    let profile = NutritionSettings().profile(garmin: garmin, on: day)
    #expect(profile.weightKilograms == 70)
    #expect(profile.isFemale)
    #expect(profile.heightCentimeters == 180)
    #expect(NutritionSettings().profile(garmin: nil, on: day) == .fallback)
  }
}

struct MealTests {
  @Test func parsesWorkerAnalysis() throws {
    let output = try JSONValue(
      data: Data(
        """
        {"titel": "Rührei mit Brot", "kategorie": "fruehstueck", "hinweis": "Ölmenge geschätzt",
         "items": [
           {"name": "Rührei", "menge_g": 120, "menge_text": "2 Eier", "getraenk": false, "sicherheit": "mittel",
            "gruppe": "ei", "barcode": null,
            "naehrwerte_100g": {"kcal": 150, "protein_g": 10, "carbs_g": 1, "fat_g": 11, "water_g": 75,
              "iron_mg": null}},
           {"name": "Kaffee", "menge_g": 200, "getraenk": true, "naehrwerte_100g": {"kcal": 2}},
           {"name": "ohne Menge", "menge_g": 0}
         ]}
        """.utf8))

    let analysis = try #require(MealAnalysis(output: output))

    #expect(analysis.title == "Rührei mit Brot")
    #expect(analysis.category == .breakfast)
    #expect(analysis.items.count == 2)
    let egg = analysis.items[0]
    #expect(egg.amounts[.kcal] == 180)
    #expect(egg.per100g[.water] == 75)
    #expect(egg.per100g[.iron] == nil)
    #expect(egg.confidence == "mittel")
    #expect(analysis.items[1].isDrink)
    #expect(NutritionSummary.totals(analysis.items)[.kcal] == 184)
  }

  @Test func rejectsEmptyAnalysis() {
    #expect(MealAnalysis(output: .object(["items": .array([])])) == nil)
    #expect(MealAnalysis(output: .null) == nil)
  }

  @Test(arguments: [
    (7, 30, MealCategory.breakfast), (12, 0, .lunch), (15, 30, .snack), (19, 0, .dinner), (23, 0, .snack),
  ])
  func categoryByTime(hour: Int, minute: Int, expected: MealCategory) {
    #expect(MealCategory.guess(hour: hour, minute: minute) == expected)
  }

  @Test func nutrientValuesRoundTrip() throws {
    var values = NutrientValues()
    values[.protein] = 12.5
    values[.vitaminD] = 1.2
    let data = try JSONEncoder().encode(values)
    #expect(String(decoding: data, as: UTF8.self).contains("vitd_ug"))
    #expect(try JSONDecoder().decode(NutrientValues.self, from: data) == values)
    #expect(NutritionSummary.percent(50, of: 200) == 25)
    #expect(NutritionSummary.percent(50, of: nil) == nil)
  }
}

struct OpenFoodFactsTests {
  @Test(arguments: ["4006381333931", "40170725", "036000291452", "4000417025005"])
  func validBarcodes(code: String) {
    #expect(OpenFoodFacts.isValidBarcode(code))
  }

  @Test(arguments: ["4006381333932", "1234", "40063813339x1", ""])
  func invalidBarcodes(code: String) {
    #expect(!OpenFoodFacts.isValidBarcode(code))
  }

  @Test func parsesProductWithUnitConversion() throws {
    let json = try JSONValue(
      data: Data(
        """
        {"status": 1, "product": {"product_name_de": "Skyr Natur", "brands": "Milbona, Lidl", "serving_quantity": 150,
          "nutriments": {"energy-kcal_100g": 63, "proteins_100g": 11, "carbohydrates_100g": 4, "fat_100g": 0.2,
            "sodium_100g": 0.04, "calcium_100g": 0.15, "vitamin-d_100g": 0.0000001, "iodine_100g": 0.00001}}}
        """.utf8))

    let product = try #require(OpenFoodFacts.product(from: json, barcode: "4056489123456"))

    #expect(product.name == "Skyr Natur")
    #expect(product.brand == "Milbona")
    #expect(product.servingGrams == 150)
    #expect(product.per100g[.kcal] == 63)
    #expect(abs((product.per100g[.sodium] ?? 0) - 40) < 0.001)
    #expect(abs((product.per100g[.calcium] ?? 0) - 150) < 0.001)
    #expect(abs((product.per100g[.vitaminD] ?? 0) - 0.1) < 0.0001)
    #expect(abs((product.per100g[.iodine] ?? 0) - 10) < 0.0001)
    let item = product.item()
    #expect(item.name == "Skyr Natur (Milbona)")
    #expect(item.grams == 150)
    #expect(item.source == .openFoodFacts)
  }

  @Test func kilojouleFallbackAndUnknownProduct() throws {
    let kj = try JSONValue(
      data: Data(#"{"status": 1, "product": {"product_name": "X", "nutriments": {"energy_100g": 418.4}}}"#.utf8))
    #expect(OpenFoodFacts.product(from: kj, barcode: "1")?.per100g[.kcal] == 100)
    let unknown = try JSONValue(data: Data(#"{"status": 0, "status_verbose": "product not found"}"#.utf8))
    #expect(OpenFoodFacts.product(from: unknown, barcode: "1") == nil)
    #expect(
      OpenFoodFacts.productURL(barcode: "4006381333931")?.absoluteString.hasPrefix(
        "https://world.openfoodfacts.org/api/v2/product/4006381333931?fields=") == true)
  }
}
