import Foundation

/// Flüssigkeit des Tages aus allem, was eingetragen ist: Getränke (Wasser, Kaffee, Saft, Milch …) und das Wasser in
/// Lebensmitteln (Suppe, Obst, Joghurt). Das Ziel von ~35 ml je kg (`NutritionPlanner`) entspricht der gesamten
/// Wasserzufuhr; laut EFSA (2010) stammen davon üblicherweise rund 20 % aus Lebensmitteln.
public enum Hydration {
  public struct Total: Equatable, Sendable {
    public var drinks: Double
    public var food: Double
    public var total: Double { drinks + food }

    public init(drinks: Double = 0, food: Double = 0) {
      self.drinks = drinks
      self.food = food
    }
  }

  /// Wasser einer Position in ml: der Wasserwert je 100 g (BLS, KI, Open Food Facts) oder bei Getränken ohne
  /// Angabe die Menge selbst (1 ml ≈ 1 g). Lebensmittel ohne Angabe zählen nicht (keine Schätzung).
  public static func milliliters(_ item: MealItem) -> Double {
    if let water = item.per100g[.water] { return max(0, water) * item.grams / 100 }
    return item.isDrink ? max(0, item.grams) : 0
  }

  public static func total(_ items: [MealItem]) -> Total {
    items.reduce(into: Total()) { total, item in
      if item.isDrink { total.drinks += milliliters(item) } else { total.food += milliliters(item) }
    }
  }
}

/// Kalorienziel je Mahlzeit für Übersicht und Widget (wie gängige Ernährungs-Apps): Frühstück 25 %, Mittag 35 %,
/// Abend 30 %, Snacks 10 % der Tagesenergie. Eine Orientierung, keine Regel – gezählt wird der Tag.
public enum MealSplit {
  public static let order: [MealCategory] = [.breakfast, .lunch, .dinner, .snack]

  public static func share(_ category: MealCategory) -> Double {
    switch category {
    case .breakfast: 0.25
    case .lunch: 0.35
    case .dinner: 0.30
    case .snack, .other: 0.10
    }
  }

  /// „Sonstiges“ zählt zu den Snacks.
  public static func slot(_ category: MealCategory) -> MealCategory {
    category == .other ? .snack : category
  }

  public static func target(_ category: MealCategory, dayKilocalories: Double?) -> Double? {
    dayKilocalories.map { ($0 * share(slot(category))).rounded() }
  }
}
