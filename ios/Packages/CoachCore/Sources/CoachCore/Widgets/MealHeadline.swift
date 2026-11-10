import Foundation

/// Kopfzeile der Mahlzeiten-Anzeigen (Homescreen-Widget, Karte auf dem Sperrbildschirm): ein Satz, der zum Stand
/// des Tages passt – was eingetragen ist, was als Nächstes ansteht, wie viel übrig ist, wie die Serie steht.
/// Feste Regeln, keine KI. Kein Druck: nichts droht mit Verlust, und ohne Kalorienziel (z. B. gesperrte
/// Gewichtsziele) nennt der Satz keine Kalorien.
public enum MealHeadline {
  /// Kurze Namen, damit der Satz in eine Zeile passt.
  static func name(_ category: MealCategory) -> String {
    switch category {
    case .breakfast: "Frühstück"
    case .lunch: "Mittagessen"
    case .dinner: "Abendessen"
    case .snack, .other: "Snack"
    }
  }

  /// - Parameters:
  ///   - meals: Mahlzeiten des Tages in fester Reihenfolge (`MealSplit.order`).
  ///   - kcalRemaining: übrige Kalorien (negativ = darüber); `nil` ohne Ziel.
  ///   - streak: Serie der Mahlzeiten.
  ///   - hour: Stunde des Tages (0–23), für den Satz vor dem ersten Eintrag.
  public static func text(
    meals: [WidgetSnapshot.MealPart], kcalRemaining: Double?, kcalTarget: Double? = nil,
    streak: WidgetSnapshot.Streak?, hour: Int
  ) -> String {
    let mains = meals.filter { $0.category != .snack && $0.category != .other }
    let logged = meals.filter { $0.kcal > 0 }
    let loggedMains = mains.filter { $0.kcal > 0 }
    let days = streak?.days ?? 0

    // Noch nichts eingetragen: nach Tageszeit, mit laufender Serie der nächste Tag.
    if logged.isEmpty {
      if days >= 2 { return "Tag \(days + 1) der Serie – los geht’s" }
      switch hour {
      case ..<10: return "Guten Morgen – Frühstück eintragen?"
      case ..<15: return "Mittagessen eintragen?"
      case ..<21: return "Heute noch nichts eingetragen"
      default: return "Noch kurz den Tag eintragen?"
      }
    }

    // Alle Hauptmahlzeiten eingetragen: Tagesbilanz.
    if !mains.isEmpty, loggedMains.count == mains.count {
      guard let remaining = kcalRemaining else {
        return days >= 3 ? "Alles eingetragen – Tag \(days) der Serie" : "Alles eingetragen – stark!"
      }
      let tolerance = max((kcalTarget ?? 2_000) * 0.07, 100)
      if abs(remaining) <= tolerance { return "Tagesziel getroffen – stark!" }
      if remaining > 0 { return "Alles eingetragen · noch \(Int(remaining.rounded())) kcal frei" }
      return "Alles eingetragen · \(Int((-remaining).rounded())) kcal über Ziel"
    }

    // Dazwischen: die nächste offene Hauptmahlzeit nach der zuletzt eingetragenen, sonst die erste offene.
    let lastIndex = mains.lastIndex { $0.kcal > 0 } ?? -1
    let open = mains.dropFirst(lastIndex + 1).first { $0.kcal <= 0 } ?? mains.first { $0.kcal <= 0 }
    guard let next = open.map({ name($0.category) }) else {
      // Nur ein Snack eingetragen (keine Hauptmahlzeiten in der Liste).
      return "Eingetragen – weiter so!"
    }
    if loggedMains.isEmpty { return "Snack notiert – \(next) eintragen?" }
    if loggedMains.count == mains.count - 1 {
      if let remaining = kcalRemaining, remaining > 0 {
        return "Noch \(Int(remaining.rounded())) kcal – \(next) fehlt"
      }
      return "Fast komplett – \(next) fehlt noch"
    }
    if let streak, streak.isRunning { return "Tag \(streak.days) der Serie – \(next) steht an" }
    return "Guter Start – \(next) steht an"
  }

  /// Satz für einen Widget-Stand.
  public static func text(_ snapshot: WidgetSnapshot, hour: Int) -> String {
    guard let nutrition = snapshot.nutrition else { return "Mahlzeiten" }
    let meals = nutrition.meals ?? MealSplit.order.map { WidgetSnapshot.MealPart(category: $0, kcal: 0, target: nil) }
    return text(
      meals: meals, kcalRemaining: nutrition.kcalRemaining, kcalTarget: nutrition.kcalTarget,
      streak: snapshot.mealStreak, hour: hour)
  }
}
