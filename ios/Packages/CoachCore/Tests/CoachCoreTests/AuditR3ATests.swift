import Foundation
import Testing

@testable import CoachCore

/// Audit Runde 3 (R3A): Nur-Ernährung und Personen ab 65. Beide Tests schlagen mit dem aktuellen Stand fehl.
struct AuditR3ATests {
  /// R3A-02: Ein per Barcode erfasstes Getränk (Open Food Facts, Werte je 100 ml, Kategorie „beverages“) zählt heute
  /// mit 0 ml zur Flüssigkeit, weil `OpenFoodFacts.Product.item()` `isDrink` nie setzt und OFF kein Wasserfeld
  /// liefert (`Hydration.milliliters` → 0). Nach dem Fix (z. B. `categories_tags`/`serving_quantity_unit` lesen)
  /// zählt die Flasche mit ihrer Menge.
  @Test func barcodeDrinkCountsAsFluid() throws {
    let json = try JSONValue(
      data: Data(
        """
        {"status": 1, "product": {"product_name_de": "Mineralwasser still", "brands": "Quelle",
          "categories_tags": ["en:beverages", "en:waters"], "quantity": "0,5 l",
          "serving_quantity": 500, "serving_quantity_unit": "ml", "serving_size": "500 ml",
          "nutriments": {"energy-kcal_100g": 0, "proteins_100g": 0, "carbohydrates_100g": 0, "fat_100g": 0}}}
        """.utf8))
    let product = try #require(OpenFoodFacts.product(from: json, barcode: "4006381333931"))
    let item = product.item()
    #expect(item.isDrink)
    #expect(Hydration.total([item]).drinks == 500)
  }

  /// R3A-05: Ältere Personen (Tanaka 2001: HFmax ≈ 208 − 0,7 × Alter, mit 80 J. ≈ 152, Streuung ± 10) und Personen mit
  /// Betablocker erreichen oft keine 140/min. `observedMax` verwirft solche Spitzen (`plausibleMax = 140...230`),
  /// es gibt dann keinen Messwert und ohne Garmin keine Zonen.
  @Test func observedMaxAcceptsLowMaximumOfOlderPerson() {
    let today = CalendarDay(year: 2026, month: 10, day: 22)
    func walk(_ id: Int64, daysAgo: Int, maxHR: Double) -> GarminActivity {
      var activity = GarminActivity(id: id)
      activity.typeKey = "running"
      activity.startLocal = today.adding(days: -daysAgo).iso + " 07:00:00"
      activity.maxHeartRate = maxHR
      activity.durationSeconds = 30 * 60
      return activity
    }
    let observed = HeartRateZoneCalculator.observedMax(
      activities: [walk(1, daysAgo: 3, maxHR: 132), walk(2, daysAgo: 10, maxHR: 130)], today: today)
    #expect(observed.confirmed == 132)
    #expect(observed.count == 2)
  }
}
