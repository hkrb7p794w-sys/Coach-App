import Foundation

/// Was eine Person für gemeinsame Rezepte ausdrücklich freigibt. Mehr verlässt das Gerät nicht: keine Körperwerte,
/// keine Gesundheitsangaben, kein Tagebuch. Fehlt ein Wert, ist er nicht freigegeben.
public struct CookShare: Codable, Equatable, Hashable, Sendable {
  public var name: String
  /// Tagesziele im Mittel einer Woche; `nil` = nicht freigegeben.
  public var kcal: Double?
  public var protein: Double?
  public var carbs: Double?
  public var fat: Double?
  public var diet: Diet?
  public var allergens: Set<Allergen>
  public var dislikes: String

  public init(
    name: String, kcal: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil,
    diet: Diet? = nil, allergens: Set<Allergen> = [], dislikes: String = ""
  ) {
    self.name = name
    self.kcal = kcal
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
    self.diet = diet
    self.allergens = allergens
    self.dislikes = dislikes
  }

  enum CodingKeys: String, CodingKey {
    case name, kcal, protein, carbs, fat, diet, allergens, dislikes
  }

  /// Unbekannte Allergene oder Ernährungsweisen (neuere App-Version) lassen die Freigabe nicht scheitern.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
    kcal = try? container.decodeIfPresent(Double.self, forKey: .kcal)
    protein = try? container.decodeIfPresent(Double.self, forKey: .protein)
    carbs = try? container.decodeIfPresent(Double.self, forKey: .carbs)
    fat = try? container.decodeIfPresent(Double.self, forKey: .fat)
    diet = (try? container.decodeIfPresent(String.self, forKey: .diet)).flatMap(Diet.init(rawValue:))
    let raw = try? container.decodeIfPresent([String].self, forKey: .allergens)
    allergens = Set((raw ?? []).compactMap(Allergen.init(rawValue:)))
    dislikes = (try? container.decodeIfPresent(String.self, forKey: .dislikes)) ?? ""
  }
}

/// Welche Angaben die Person freigibt (einzeln abwählbar).
public struct CookShareFields: Codable, Equatable, Hashable, Sendable {
  public var targets = true
  public var diet = true
  public var allergens = true
  public var dislikes = true

  public init() {}
}

/// Eine verbundene Person: Code der Freigabe und zuletzt abgerufener Stand.
public struct CookPartner: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var code: String
  public var share: CookShare
  public var id: String { code }

  public init(code: String, share: CookShare) {
    self.code = code
    self.share = share
  }
}

/// Die eigene Freigabe.
public struct CookRelease: Codable, Equatable, Hashable, Sendable {
  public var code: String
  public var fields: CookShareFields
  public var share: CookShare
  public var expiresAt: String?

  public init(code: String, fields: CookShareFields, share: CookShare, expiresAt: String?) {
    self.code = code
    self.fields = fields
    self.share = share
    self.expiresAt = expiresAt
  }
}

/// Links rund ums gemeinsame Kochen. Sie tragen nie ein Token oder eine Worker-Adresse, nur den Code der Freigabe.
public enum CookLink: Equatable, Sendable, Identifiable {
  /// `coach://cook/<code>`: Freigabe einer anderen Person übernehmen.
  case partner(String)
  /// `coach://open/cookShare`: eigene Freigabe erteilen.
  case release

  public var id: String {
    switch self {
    case .partner(let code): code
    case .release: "release"
    }
  }

  public init?(url: URL) {
    guard url.scheme == "coach" else { return nil }
    if url.host() == "open", url.pathComponents.last == "cookShare" {
      self = .release
    } else if url.host() == "cook", let code = CookPlanner.code(from: url.lastPathComponent) {
      self = .partner(code)
    } else {
      return nil
    }
  }
}

/// Für wen gekocht wird.
public enum CookAudience: String, Codable, CaseIterable, Sendable, Identifiable {
  case me, partner, both
  public var id: String { rawValue }
}

/// Wie viel gekocht wird: einzelne Portionen (Teller) oder Tage, an denen die Mahlzeit gegessen wird.
public enum CookAmount: Codable, Equatable, Hashable, Sendable {
  /// Teller insgesamt, auf alle Personen verteilt.
  case portions(Int)
  /// Je Person ein Teller pro Tag.
  case days(Int)

  public static let maxPortions = 20
  public static let maxDays = 7

  public var label: String {
    switch self {
    case .portions(let count): count == 1 ? "1 Portion" : "\(count) Portionen"
    case .days(let count): count == 1 ? "1 Tag" : "\(count) Tage"
    }
  }

  var clamped: CookAmount {
    switch self {
    case .portions(let count): .portions(min(max(count, 1), Self.maxPortions))
    case .days(let count): .days(min(max(count, 1), Self.maxDays))
    }
  }
}

/// Eine Person in einem Kochplan (Stand beim Erstellen).
public struct CookPerson: Codable, Equatable, Hashable, Sendable, Identifiable {
  public static let meID = "me"

  public var id: String
  public var share: CookShare

  public init(id: String, share: CookShare) {
    self.id = id
    self.share = share
  }

  public var name: String { share.name }

  /// Anteil der Mahlzeit am Tagesziel (`MealSplit`, zur Orientierung).
  public func mealTarget(_ meal: MealCategory) -> CookMealTarget? {
    guard let kcal = share.kcal, kcal > 0 else { return nil }
    let part = MealSplit.share(meal)
    return CookMealTarget(
      kcal: kcal * part, protein: share.protein.map { $0 * part }, carbs: share.carbs.map { $0 * part },
      fat: share.fat.map { $0 * part })
  }
}

public struct CookMealTarget: Equatable, Sendable {
  public var kcal: Double
  public var protein: Double?
  public var carbs: Double?
  public var fat: Double?
}

/// Wo eine Portion bis zum Essen bleibt.
public enum CookStorage: String, Codable, Sendable {
  case fresh, fridge, freezer

  public var label: String {
    switch self {
    case .fresh: "Frisch"
    case .fridge: "Kühlschrank"
    case .freezer: "Einfrieren, am Vortag auftauen"
    }
  }
}

/// Teller einer Person: Mengen, Nährwerte je Teller und Anteil am ganzen Gericht.
public struct CookPortion: Equatable, Sendable, Identifiable {
  public var person: CookPerson
  public var plates: Int
  /// Mengen eines Tellers (roh) gegenüber der Basisportion.
  public var factor: Double
  public var items: [MealItem]
  public var nutrients: NutrientValues
  /// Gramm roh je Teller.
  public var grams: Double
  /// Anteil eines Tellers am ganzen Gericht in Prozent.
  public var sharePercent: Double
  public var target: CookMealTarget?
  public var notes: [String]
  public var id: String { person.id }
}

/// Ein Rezept für eine oder zwei Personen. Gespeichert wird die Zusammensetzung einer Basisportion; Tellergrößen,
/// Gesamtmengen und Nährwerte werden immer daraus berechnet, damit sie auch nach dem Bearbeiten stimmen.
public struct CookPlan: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var created: Date
  public var title: String
  public var meal: MealCategory
  public var minutes: Int
  public var steps: [String]
  /// Zutaten einer Basisportion (roh, Nährwerte je 100 g).
  public var base: [MealItem]
  public var people: [CookPerson]
  public var amount: CookAmount
  /// Teller je Person (`CookPerson.id`).
  public var plates: [String: Int]
  public var fridgeDays: Int
  public var freezable: Bool
  public var storageHint: String
  public var reheatHint: String
  /// Begründung der KI, wie unterschiedliche Ziele zusammengebracht wurden.
  public var compromise: String
  public var source: String

  public init(
    id: UUID = UUID(), created: Date, title: String, meal: MealCategory, minutes: Int, steps: [String],
    base: [MealItem], people: [CookPerson], amount: CookAmount, plates: [String: Int], fridgeDays: Int,
    freezable: Bool, storageHint: String, reheatHint: String, compromise: String, source: String
  ) {
    self.id = id
    self.created = created
    self.title = title
    self.meal = meal
    self.minutes = minutes
    self.steps = steps
    self.base = base
    self.people = people
    self.amount = amount
    self.plates = plates
    self.fridgeDays = fridgeDays
    self.freezable = freezable
    self.storageHint = storageHint
    self.reheatHint = reheatHint
    self.compromise = compromise
    self.source = source
  }

  public var baseNutrients: NutrientValues { NutritionSummary.totals(base) }

  /// Tellergröße einer Person gegenüber der Basisportion: so, dass die Energie zum Mahlzeitenziel passt.
  public func factor(for person: CookPerson) -> Double {
    guard let target = person.mealTarget(meal), let kcal = baseNutrients[.kcal], kcal > 0 else { return 1 }
    return min(max(target.kcal / kcal, CookPlanner.factorRange.lowerBound), CookPlanner.factorRange.upperBound)
  }

  /// Summe aller Teller in Basisportionen.
  public var totalFactor: Double {
    people.reduce(0) { $0 + Double(plates[$1.id] ?? 0) * factor(for: $1) }
  }

  public var portions: [CookPortion] {
    let baseValues = baseNutrients
    let baseGrams = base.reduce(0) { $0 + $1.grams }
    let total = totalFactor
    return people.map { person in
      let factor = factor(for: person)
      let items = base.map { item -> MealItem in
        var scaled = item
        scaled.id = UUID()
        scaled.grams = (item.grams * factor).rounded()
        return scaled
      }
      let nutrients = Self.scaled(baseValues, by: factor)
      let target = person.mealTarget(meal)
      return CookPortion(
        person: person, plates: plates[person.id] ?? 0, factor: factor, items: items, nutrients: nutrients,
        grams: baseGrams * factor, sharePercent: total > 0 ? factor / total * 100 : 0, target: target,
        notes: Self.notes(person: person, nutrients: nutrients, target: target))
    }
  }

  /// Nährwerte des ganzen Gerichts.
  public var wholeNutrients: NutrientValues { Self.scaled(baseNutrients, by: totalFactor) }

  /// Einkaufsmengen für alle Teller, auf 5 g gerundet.
  public var totalIngredients: [MealItem] {
    let total = totalFactor
    return base.map { item in
      var scaled = item
      scaled.grams = max((item.grams * total / 5).rounded() * 5, 5)
      return scaled
    }
  }

  /// Teller, die eine Person nacheinander isst: danach richtet sich die Lagerung.
  public var mealsPerPerson: Int { plates.values.max() ?? 0 }

  /// Lagerung je Tag ab dem Kochtag; `nil`, wenn das Gericht nicht so lange hält.
  public var storagePlan: [CookStorage]? {
    CookPlanner.storagePlan(meals: mealsPerPerson, fridgeDays: fridgeDays, freezable: freezable)
  }

  public mutating func setGrams(_ grams: Double, of itemID: UUID) {
    guard let index = base.firstIndex(where: { $0.id == itemID }) else { return }
    base[index].grams = min(max(grams, 1), 5_000)
  }

  /// Die letzte Zutat bleibt: Ein Rezept ohne Zutaten ließe sich nicht mehr berechnen.
  public mutating func remove(itemID: UUID) {
    guard base.count > 1 else { return }
    base.removeAll { $0.id == itemID }
  }

  static func scaled(_ values: NutrientValues, by factor: Double) -> NutrientValues {
    NutrientValues(values.values.mapValues { $0 * factor })
  }

  /// Weicht Protein trotz passender Energie deutlich ab, sagt die App es offen.
  static func notes(person: CookPerson, nutrients: NutrientValues, target: CookMealTarget?) -> [String] {
    var result: [String] = []
    if let target, let kcal = nutrients[.kcal], kcal > 0, abs(kcal - target.kcal) / target.kcal > 0.1 {
      result.append(
        "\(person.name): \(Int(kcal.rounded())) statt \(Int(target.kcal.rounded())) kcal, weil die Portion sonst "
          + "unverhältnismäßig klein oder groß würde.")
    }
    if let wanted = target?.protein, let protein = nutrients[.protein], wanted - protein >= 10 {
      result.append(
        "\(person.name): \(Int(protein.rounded())) g Protein, Ziel \(Int(wanted.rounded())) g. Eine eiweißreiche "
          + "Beilage gleicht das aus.")
    }
    return result
  }
}

/// Regeln rund um gemeinsames Kochen und Vorkochen. Die KI schlägt nur die Zusammensetzung vor; Teller,
/// Hochrechnung, Ausschlüsse und Lagerung entscheidet die App.
public enum CookPlanner {
  /// Tellergröße höchstens halb so groß oder 1,8-mal so groß wie die Basisportion.
  static let factorRange = 0.5...1.8
  /// Gekochtes hält im Kühlschrank 2–3 Tage (BfR, „Vorkochen für mehrere Tage“); mehr sagt die App nicht zu.
  public static let maxFridgeDays = 3
  public static let ideaCount = 3

  /// Teller je Person. Portionen werden gleichmäßig verteilt, ein Rest geht an die erste Person.
  public static func plates(_ amount: CookAmount, people: [CookPerson]) -> [String: Int] {
    guard !people.isEmpty else { return [:] }
    switch amount.clamped {
    case .days(let days):
      return Dictionary(uniqueKeysWithValues: people.map { ($0.id, days) })
    case .portions(let portions):
      var result: [String: Int] = [:]
      for (index, person) in people.enumerated() {
        result[person.id] = portions / people.count + (index < portions % people.count ? 1 : 0)
      }
      return result
    }
  }

  /// Die strengste Ernährungsweise gilt für das gemeinsame Gericht.
  public static func mergedDiet(_ people: [CookPerson]) -> Diet {
    let order: [Diet] = [.omnivore, .pescetarian, .vegetarian, .vegan]
    return people.compactMap(\.share.diet).max { order.firstIndex(of: $0) ?? 0 < order.firstIndex(of: $1) ?? 0 }
      ?? .omnivore
  }

  public static func mergedAllergens(_ people: [CookPerson]) -> Set<Allergen> {
    people.reduce(into: Set<Allergen>()) { $0.formUnion($1.share.allergens) }
  }

  /// Lagerung je Tag ab dem Kochtag; `nil`, wenn die Portionen nicht sicher bis zum letzten Tag reichen.
  public static func storagePlan(meals: Int, fridgeDays: Int, freezable: Bool) -> [CookStorage]? {
    let limit = min(max(fridgeDays, 0), maxFridgeDays)
    var result: [CookStorage] = []
    for day in 0..<max(meals, 0) {
      if day == 0 {
        result.append(.fresh)
      } else if day <= limit {
        result.append(.fridge)
      } else if freezable {
        result.append(.freezer)
      } else {
        return nil
      }
    }
    return result
  }

  /// Eingabe der Worker-Aufgabe `cook_plan`. Namen gehen nicht an die KI, die Personen heißen „Person 1“ und „Person 2“.
  public static func input(
    people: [CookPerson], meal: MealCategory, amount: CookAmount, preferences: RecipePreferences, favorites: [String]
  ) -> [String: JSONValue] {
    let plates = plates(amount, people: people)
    let lines = people.enumerated().map { index, person -> JSONValue in
      var line: [String: JSONValue] = [
        "bezeichnung": .string("Person \(index + 1)"), "teller": .number(Double(plates[person.id] ?? 0)),
      ]
      if let target = person.mealTarget(meal) {
        line["kcal"] = .number(target.kcal.rounded())
        if let protein = target.protein { line["protein_g"] = .number(protein.rounded()) }
        if let carbs = target.carbs { line["kohlenhydrate_g"] = .number(carbs.rounded()) }
        if let fat = target.fat { line["fett_g"] = .number(fat.rounded()) }
      }
      return .object(line)
    }
    let meals = plates.values.max() ?? 1
    let dislikes = people.map(\.share.dislikes).filter { !$0.isEmpty } + [preferences.dislikes].filter { !$0.isEmpty }
    return [
      "personen": .array(lines),
      "mahlzeit": .string(meal.rawValue),
      "mahlzeiten_je_person": .number(Double(meals)),
      "vorkochen": .bool(meals > 1),
      "diet": .string(mergedDiet(people).rawValue),
      "allergens": .array(
        mergedAllergens(people).sorted { $0.rawValue < $1.rawValue }.map { .string($0.label) }),
      "dislikes": .string(String(dislikes.joined(separator: "; ").prefix(200))),
      "maxMinutes": .number(Double(preferences.maxMinutes)),
      "favorites": .array(favorites.prefix(10).map { .string($0) }),
    ]
  }

  /// Antwort prüfen: Ernährungsweise, Allergene und Nährwerte wie bei den Wochenrezepten, dazu die Eignung zum
  /// Vorkochen. Wer nur die Menge vervielfacht, ohne dass das Gericht hält, wird verworfen.
  public static func plans(
    output: JSONValue, people: [CookPerson], meal: MealCategory, amount: CookAmount, source: String, created: Date
  ) -> (plans: [CookPlan], notes: [String]) {
    let diet = mergedDiet(people)
    let allergens = mergedAllergens(people)
    let plates = plates(amount, people: people)
    let meals = plates.values.max() ?? 0
    var result: [CookPlan] = []
    var notes: [String] = []
    for value in (output["rezepte"]?.arrayValue ?? []).prefix(ideaCount) {
      guard let recipe = RecipePlanner.recipe(value) else { continue }
      let problems = RecipePlanner.violations(recipe, diet: diet, allergens: allergens)
      if !problems.isEmpty {
        notes.append("„\(recipe.title)“ verworfen: enthält \(problems.joined(separator: ", ")).")
        continue
      }
      if let item = recipe.ingredients.first(where: RecipePlanner.implausible) {
        notes.append("„\(recipe.title)“ verworfen: unstimmige Nährwerte bei „\(item.name)“.")
        continue
      }
      let fridge = Int(min(max(value["haltbarkeit_tage"]?.doubleValue ?? 0, 0), 30))
      let freezable = value["einfrierbar"] == .bool(true)
      if meals > 1 {
        if value["vorkochen_geeignet"] != .bool(true) {
          notes.append("„\(recipe.title)“ verworfen: eignet sich nicht zum Vorkochen.")
          continue
        }
        if storagePlan(meals: meals, fridgeDays: fridge, freezable: freezable) == nil {
          notes.append("„\(recipe.title)“ verworfen: hält nicht für \(meals) Mahlzeiten.")
          continue
        }
      }
      result.append(
        CookPlan(
          created: created, title: recipe.title, meal: meal, minutes: recipe.minutes, steps: recipe.steps,
          base: recipe.ingredients, people: people, amount: amount.clamped, plates: plates,
          fridgeDays: min(fridge, maxFridgeDays), freezable: freezable,
          storageHint: String((value["lagerung"]?.stringValue ?? "").prefix(300)),
          reheatHint: String((value["aufwaermen"]?.stringValue ?? "").prefix(200)),
          compromise: people.count > 1 ? String((value["kompromiss"]?.stringValue ?? "").prefix(400)) : "",
          source: source))
    }
    return (result, notes)
  }

  /// Aus dem Link `coach://cook/<code>`, dem https-Link oder dem Code selbst.
  public static func code(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let last = trimmed.split(separator: "/").last.map(String.init), last.count == 10,
      last.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
    else { return nil }
    if trimmed.contains("/"), !(trimmed.contains("coach://cook/") || trimmed.contains("/k/")) { return nil }
    return last
  }

  /// Mittlere Tagesziele einer Woche für die Freigabe.
  public static func share(
    name: String, week: [RecipeDayTarget], diet: Diet, preferences: RecipePreferences, fields: CookShareFields,
    safety: WeightGoalGuard
  ) -> CookShare {
    var share = CookShare(name: String(name.trimmingCharacters(in: .whitespaces).prefix(30)))
    // Schwangerschaft/Stillzeit oder Essstörung: keine Kalorienziele, auch nicht für andere.
    if fields.targets, safety != .noTargets, !week.isEmpty {
      let count = Double(week.count)
      share.kcal = (week.reduce(0) { $0 + $1.kcal } / count).rounded()
      share.protein = (week.reduce(0) { $0 + $1.protein } / count).rounded()
      share.carbs = (week.reduce(0) { $0 + $1.carbs } / count).rounded()
      share.fat = (week.reduce(0) { $0 + $1.fat } / count).rounded()
    }
    if fields.diet { share.diet = diet }
    if fields.allergens { share.allergens = preferences.allergens }
    if fields.dislikes { share.dislikes = String(preferences.dislikes.prefix(200)) }
    return share
  }
}

extension RecipePlanner {
  /// Eine Woche in Abfragen zu höchstens zwei Tagen: Eine Antwort über sieben Tage sprengt das Antwortlimit der KI.
  public static func batches(_ targets: [RecipeDayTarget]) -> [[RecipeDayTarget]] {
    guard targets.count > maxDaysPerRequest else { return targets.isEmpty ? [] : [targets] }
    let parts = Int((Double(targets.count) / Double(maxDaysPerRequest)).rounded(.up))
    var result: [[RecipeDayTarget]] = []
    var start = 0
    for part in 0..<parts {
      let size = targets.count / parts + (part < targets.count % parts ? 1 : 0)
      result.append(Array(targets[start..<(start + size)]))
      start += size
    }
    return result
  }

  static let maxDaysPerRequest = 2
}

extension WeeklyRecipePlan {
  /// Teilpläne zusammenführen, Tage in der Reihenfolge des Kalenders.
  public static func merged(_ parts: [WeeklyRecipePlan], created: Date) -> WeeklyRecipePlan? {
    guard !parts.isEmpty else { return nil }
    let sources = parts.reduce(into: [String]()) { if !$0.contains($1.source) { $0.append($1.source) } }
    return WeeklyRecipePlan(
      created: created, days: parts.flatMap(\.days).sorted { $0.day < $1.day },
      source: sources.joined(separator: ", "), notes: parts.flatMap(\.notes))
  }
}

/// Verständliche Meldung statt technischer Fehlertexte. Der Statuscode bleibt für Rückfragen sichtbar.
public enum AIErrorText {
  public static func message(status: Int, code: String?, detail: String) -> String {
    switch status {
    case 429:
      return "Das KI-Kontingent ist gerade ausgeschöpft. Bitte versuche es später noch einmal. (Fehlercode 429)"
    case 502, 503, 504:
      if code == "ai_invalid" {
        return "Die KI hat keine brauchbare Antwort geliefert. Bitte versuche es noch einmal. (Fehlercode \(status))"
      }
      return
        "Die KI ist gerade nicht erreichbar oder überlastet. Bitte versuche es in ein paar Minuten noch einmal. "
        + "(Fehlercode \(status))"
    case 500...:
      return "Beim KI-Dienst ist ein Fehler aufgetreten. Bitte versuche es später noch einmal. (Fehlercode \(status))"
    default:
      return detail
    }
  }

  /// Lohnt ein zweiter Versuch? Nur bei vorübergehenden Ausfällen, nicht bei falschen Anfragen.
  public static func isTemporary(status: Int) -> Bool {
    [502, 503, 504].contains(status)
  }
}
