import CoachCore
import Foundation
import Observation
import SwiftData

/// Tagesziele, Summen und die Wege, eine Mahlzeit zu erfassen (Foto, Text, Barcode, manuell).
@Observable
final class NutritionViewModel {
  /// Entwurf einer Mahlzeit, der im Editor geprüft und dann gespeichert wird.
  struct Draft: Identifiable {
    let id = UUID()
    var record: MealRecord?
    var title: String
    var category: MealCategory
    var hint: String
    var items: [MealItem]
    /// Zeitpunkt; `nil` = gewählter Tag zur aktuellen Uhrzeit.
    var date: Date?
  }

  /// Heute laut letzter Aktualisierung.
  private(set) var today = CalendarDay(date: .now)
  /// Im Wochenstreifen gewählter Tag; `nil` = heute.
  var selectedDay: CalendarDay?
  var day: CalendarDay { selectedDay ?? today }
  /// Zuletzt per Schnell-Leiste eingetragen – für „Rückgängig“.
  private(set) var lastLogged: (record: MealRecord, label: String)?
  private(set) var targets: NutritionTargets?
  private(set) var totals = NutrientValues()
  private(set) var isWorking = false
  private(set) var reviewPoints: [String] = []
  private(set) var reviewModel: String?
  private(set) var reviewSources: [String] = []
  var errorMessage: String?
  var draft: Draft?
  /// Zeitpunkt des letzten Speicherns im Entwurf (z. B. Rezept „eingetragen“).
  private(set) var lastSaved: Date?
  /// Barcode ohne Treffer bei Open Food Facts – selbst anlegen oder Etikett fotografieren.
  var missingBarcode: String?

  private let openFoodFacts: OpenFoodFactsClient

  init(openFoodFacts: OpenFoodFactsClient = OpenFoodFactsClient()) {
    self.openFoodFacts = openFoodFacts
  }

  func update(
    meals: [MealRecord], activities: [GarminActivity], settings: CoachSettings, profile: GarminProfile?,
    hasGarminData: Bool, now: Date = .now
  ) {
    today = CalendarDay(date: now)
    if selectedDay == today { selectedDay = nil }
    let day = self.day
    targets = Self.targets(
      for: day, activities: activities, settings: settings, profile: profile, hasGarminData: hasGarminData)
    totals = NutritionSummary.totals(meals.filter { $0.dayKey == day.iso }.flatMap(\.items))
  }

  /// Tagesziele für einen Tag: Saisonplan aus der Musterwoche, persönliches Profil aus den eigenen Einheiten.
  static func targets(
    for day: CalendarDay, activities: [GarminActivity], settings: CoachSettings, profile: GarminProfile?,
    hasGarminData: Bool
  ) -> NutritionTargets {
    let dayActivities = activities.filter { $0.day == day }
    let planItems: [TemplateItem]
    if settings.profile.mode == .season {
      let week = WeeklyVolume(activities: activities, weekContaining: day)
      planItems = SeasonPlan.state(today: day, config: settings.season, week: week).todayFixed
    } else {
      planItems = settings.schedule(inWeekOf: day).templateItems(on: Weekday(day: day))
    }
    return NutritionPlanner.compute(
      activities: dayActivities, planItems: planItems, settings: settings.nutrition, garminProfile: profile,
      day: day, hasGarminData: hasGarminData)
  }

  // MARK: - Was jetzt?

  private(set) var nowSuggestions: [Recipe] = []
  private(set) var nowNotes: [String] = []

  /// Drei Gerichte zu dem, was heute noch übrig ist; Ernährungsweise und Allergene prüft die App.
  func suggestNow(ai: AIClient, settings: CoachSettings, foods: [FoodRecord], now: Date = .now) async {
    guard let targets else { return }
    guard ai.isConfigured else {
      errorMessage = AIClientError.notConfigured.localizedDescription
      return
    }
    var remaining = NutrientValues()
    for nutrient in [Nutrient.kcal, .protein, .carbs, .fat] {
      remaining[nutrient] = max(0, (targets.values[nutrient] ?? 0) - (totals[nutrient] ?? 0))
    }
    guard let kcal = MealNow.targetKilocalories(remaining: remaining[.kcal] ?? 0) else {
      nowSuggestions = []
      nowNotes = ["Heute ist kaum noch etwas übrig – höchstens ein kleiner, proteinreicher Snack."]
      return
    }
    await work {
      let input = MealNow.input(
        remaining: remaining, category: Self.category(at: now), diet: settings.nutrition.diet,
        preferences: settings.recipes, pantry: settings.pantry, favorites: foods.prefix(15).map(\.name))
      let response = try await ai.run(task: "meal_now", input: input)
      let result = MealNow.suggestions(
        output: response.output, targetKilocalories: kcal, diet: settings.nutrition.diet,
        allergens: settings.recipes.allergens)
      nowSuggestions = result.recipes
      nowNotes = result.notes
      if result.recipes.isEmpty { errorMessage = "Keine passenden Vorschläge erhalten – bitte noch einmal." }
    }
  }

  /// Vorschlag übernehmen: Entwurf zum Prüfen (Portion, Zutaten, Zeitpunkt).
  func draft(
    from recipe: Recipe, hint: String = "Vorschlag „Was jetzt?“ (Nährwerte KI-geschätzt)", now: Date = .now
  ) {
    draft = Draft(title: recipe.title, category: Self.category(at: now), hint: hint, items: recipe.ingredients)
  }

  // MARK: - Ohne Netz

  /// Fotos und Beschreibungen, die ohne Netz nicht ausgewertet werden konnten.
  private(set) var pending: [PendingAnalysis] = PendingAnalysis.load()

  /// Nächste wartende Auswertung versuchen; bleibt bei Netzfehler in der Warteschlange.
  func retryPending(ai: AIClient, settings: CoachSettings, foods: [FoodRecord]) async {
    guard let next = pending.first, !isWorking, draft == nil, ai.isConfigured else { return }
    let ok = await analyze(
      text: next.text, photo: next.photo, ai: ai, settings: settings, foods: foods, queueOnNetworkError: false)
    if ok { removePending(next) }
  }

  func removePending(_ item: PendingAnalysis) {
    item.deletePhoto()
    pending.removeAll { $0.id == item.id }
    PendingAnalysis.save(pending)
  }

  // MARK: - Kopieren und verschieben

  /// Mahlzeit heute (bzw. am gewählten Tag) erneut eintragen.
  func repeatMeal(_ record: MealRecord, context: ModelContext, foods: [FoodRecord], now: Date = .now) {
    log(
      title: record.title, category: Self.category(at: now), items: record.items, context: context, foods: foods,
      label: "\(record.title) erneut eingetragen", now: now)
  }

  func move(_ record: MealRecord, to category: MealCategory, context: ModelContext) {
    record.category = category
    try? context.save()
  }

  // MARK: - Erfassen

  func newManualDraft(now: Date = .now) {
    let item = MealItem(name: "", grams: 100, source: .manual, per100g: NutrientValues())
    draft = Draft(title: "", category: Self.category(at: now), hint: "", items: [item])
  }

  /// Unbekannter Barcode: leere Position mit Barcode – beim Speichern merkt sich die App das Produkt.
  func draftForMissingBarcode(_ barcode: String, now: Date = .now) {
    missingBarcode = nil
    var item = MealItem(name: "", grams: 100, source: .manual, per100g: NutrientValues())
    item.barcode = barcode
    draft = Draft(title: "", category: Self.category(at: now), hint: "Werte vom Etikett je 100 g", items: [item])
  }

  /// Nährwerttabelle fotografiert: die KI liest Name, Werte je 100 g und Portion; gespeichert unter dem Barcode.
  func readLabel(photo: Data, barcode: String?, ai: AIClient, now: Date = .now) async {
    guard ai.isConfigured else {
      errorMessage = AIClientError.notConfigured.localizedDescription
      return
    }
    await work {
      guard let jpeg = MealPhoto.jpeg(from: photo) else { throw AIClientError.http(200, "Foto nicht lesbar.") }
      let response = try await ai.run(
        task: "nutrition_label", input: [:], images: [AIClient.Image(mimeType: "image/jpeg", data: jpeg)])
      guard var item = NutritionLabel.item(from: response.output) else {
        throw AIClientError.http(200, "Auf dem Foto war keine Nährwerttabelle lesbar.")
      }
      item.barcode = barcode
      draft = Draft(
        title: item.name, category: Self.category(at: now), hint: "Vom Etikett gelesen – bitte kurz prüfen.",
        items: [item])
    }
  }

  /// Entwurf mit einem bekannten Lebensmittel (Suche), Menge wie zuletzt.
  func draft(with item: MealItem, now: Date = .now) {
    var fresh = item
    fresh.id = UUID()
    draft = Draft(title: item.name, category: Self.category(at: now), hint: "", items: [fresh])
  }

  /// Zeitpunkt für einen Eintrag am gewählten Tag: heute jetzt, sonst derselbe Tag zur aktuellen Uhrzeit.
  func timestamp(now: Date = .now) -> Date {
    guard day != today else { return now }
    let calendar = Calendar.current
    let time = calendar.dateComponents([.hour, .minute], from: now)
    return calendar.date(
      from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))
      ?? day.localDate
  }

  /// Ein Tipp: Mahlzeit sofort eintragen (Schnell-Leiste, „wie gestern“, Suche, Wasser) – mit „Rückgängig“.
  func log(
    title: String, category: MealCategory, items: [MealItem], context: ModelContext, foods: [FoodRecord],
    label: String? = nil, now: Date = .now
  ) {
    let fresh = items.map { item -> MealItem in
      var copy = item
      copy.id = UUID()
      return copy
    }
    guard !fresh.isEmpty else { return }
    let record = MealRecord(
      day: day, category: category, title: title, hint: "", items: fresh, at: timestamp(now: now))
    context.insert(record)
    remember(fresh, context: context, foods: foods)
    try? context.save()
    lastLogged = (record, label ?? "\(title) eingetragen")
  }

  func undoLastLog(context: ModelContext) {
    guard let record = lastLogged?.record else { return }
    context.delete(record)
    try? context.save()
    lastLogged = nil
  }

  func clearLastLogged() {
    lastLogged = nil
  }

  func edit(_ record: MealRecord) {
    draft = Draft(
      record: record, title: record.title, category: record.category, hint: record.hint, items: record.items,
      date: record.createdAt)
  }

  /// KI-Analyse von Foto und/oder Text. Ohne Netz landet die Mahlzeit in der Warteschlange statt im Fehler.
  @discardableResult
  func analyze(
    text: String, photo: Data?, ai: AIClient, settings: CoachSettings, foods: [FoodRecord],
    queueOnNetworkError: Bool = true
  ) async -> Bool {
    guard ai.isConfigured else {
      errorMessage = AIClientError.notConfigured.localizedDescription
      return false
    }
    var succeeded = false
    await work {
      let input: [String: JSONValue] = [
        "text": .string(text),
        "diet": .string(settings.nutrition.diet.rawValue),
        "personalFoods": .array(foods.prefix(40).map { .string($0.name) }),
      ]
      let jpeg = photo.flatMap { MealPhoto.jpeg(from: $0) }
      let images = jpeg.map { [AIClient.Image(mimeType: "image/jpeg", data: $0)] } ?? []
      let response = try await ai.run(task: "meal_analyze", input: input, images: images)
      guard let analysis = MealAnalysis(output: response.output) else {
        throw AIClientError.http(200, "Die KI hat keine Lebensmittel erkannt.")
      }
      draft = Draft(
        title: analysis.title.isEmpty ? text : analysis.title,
        category: analysis.category ?? Self.category(at: .now),
        hint: analysis.hint,
        items: analysis.items.map { self.preferKnownFood($0, foods: foods) }
      )
      succeeded = true
    }
    if !succeeded, queueOnNetworkError, isNetworkError {
      pending.append(PendingAnalysis(text: text, photo: photo))
      PendingAnalysis.save(pending)
      errorMessage = "Ohne Netz gespeichert – wird ausgewertet, sobald du wieder online bist."
    }
    return succeeded
  }

  /// Der letzte Fehler war ein Netzwerkfehler (für die Warteschlange).
  private var isNetworkError: Bool {
    lastError.map { error in
      if case .network = error as? AIClientError { return true }
      return error is URLError
    } ?? false
  }

  func lookup(barcode: String, foods: [FoodRecord], context: ModelContext) async {
    await work {
      let key = "barcode:\(barcode)"
      let item: MealItem
      if let cached = foods.first(where: { $0.key == key })?.item {
        item = cached
      } else {
        do {
          let product = try await openFoodFacts.product(barcode: barcode)
          item = product.item()
          context.insert(FoodRecord(item: item))
        } catch OpenFoodFactsClient.LookupError.notFound {
          missingBarcode = barcode
          return
        }
      }
      var fresh = item
      fresh.id = UUID()
      if var existing = draft {
        existing.items.append(fresh)
        draft = existing
      } else {
        draft = Draft(title: fresh.name, category: Self.category(at: .now), hint: "", items: [fresh])
      }
    }
  }

  /// Speichert den Entwurf und merkt sich die Lebensmittel für Vorschläge und KI-Hinweise.
  func save(_ draft: Draft, context: ModelContext, foods: [FoodRecord]) {
    let items = draft.items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.grams > 0 }
    guard !items.isEmpty else {
      errorMessage = "Mindestens eine Position mit Name und Menge eintragen."
      return
    }
    let title = draft.title.isEmpty ? items.map(\.name).joined(separator: ", ") : draft.title
    if let record = draft.record {
      record.title = title
      record.category = draft.category
      record.items = items
      if let date = draft.date {
        record.createdAt = date
        record.dayKey = CalendarDay(date: date).iso
      }
    } else {
      // Ohne eigenen Zeitpunkt: gewählter Tag zur aktuellen Uhrzeit.
      let day = draft.date.map { CalendarDay(date: $0) } ?? self.day
      context.insert(
        MealRecord(
          day: day, category: draft.category, title: title, hint: draft.hint, items: items,
          at: draft.date ?? timestamp()))
    }
    remember(items, context: context, foods: foods)
    try? context.save()
    self.draft = nil
    lastSaved = .now
  }

  /// Lebensmittel für Vorschläge, Suche und KI-Hinweise merken.
  private func remember(_ items: [MealItem], context: ModelContext, foods: [FoodRecord]) {
    var known = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    for item in items {
      let key = FoodRecord.key(for: item)
      let record = known[key] ?? FoodRecord(item: item)
      if known[key] == nil {
        context.insert(record)
        known[key] = record
      } else if var stored = record.item {
        // Menge und Portion merken („du nimmst meist 40 g“); eigene Nährwerte bleiben.
        stored.grams = item.grams
        stored.portion = item.portion ?? stored.portion
        if stored.source == .ai, item.source != .ai { stored.per100g = item.per100g }
        record.payload = (try? JSONEncoder().encode(stored)) ?? record.payload
      }
      record.useCount += 1
      record.lastUsed = .now
    }
  }

  /// Gespeicherte Mahlzeiten ohne SwiftData (für Vorschläge, Suche, Woche); Wasser zählt nicht als Mahlzeit.
  static func entries(_ meals: [MealRecord]) -> [MealEntry] {
    meals.compactMap { meal in
      guard let day = CalendarDay(iso: meal.dayKey), !meal.isWater else { return nil }
      return MealEntry(day: day, date: meal.createdAt, category: meal.category, title: meal.title, items: meal.items)
    }
  }

  func delete(_ record: MealRecord, context: ModelContext) {
    context.delete(record)
    try? context.save()
  }

  // MARK: - Auswertung

  func review(
    meals: [MealRecord], activities: [GarminActivity], ai: AIClient, settings: CoachSettings,
    recovery: String
  ) async {
    guard let targets else { return }
    guard ai.isConfigured else {
      errorMessage = AIClientError.notConfigured.localizedDescription
      return
    }
    await work {
      let todays = meals.filter { $0.dayKey == day.iso }
      // Saisonplan: Wochentag, Phase und Fixpunkte aus dem Plan; sonst Ziel und eigene Einheiten des Tages.
      let weekdayName: String
      let phaseName: String
      let plannedTexts: [String]
      if settings.profile.mode == .season {
        let week = WeeklyVolume(activities: activities, weekContaining: day)
        let plan = SeasonPlan.state(today: day, config: settings.season, week: week)
        weekdayName = plan.weekday
        phaseName = plan.phase.rawValue
        plannedTexts = plan.todayFixed.map(\.text)
      } else {
        let weekday = Weekday(day: day)
        weekdayName = weekday.long
        phaseName = settings.profile.goal.label
        plannedTexts = settings.schedule(inWeekOf: day).slots(on: weekday).map(\.title)
      }
      let training = activities.filter { $0.day == day }.map { activity -> String in
        let minutes = Int(((activity.durationSeconds ?? 0) / 60).rounded())
        let load = activity.trainingLoad.map { ", Belastung \(Int($0.rounded()))" } ?? ""
        return "\(activity.name ?? activity.typeKey ?? "Aktivität") \(minutes) min\(load)"
      }
      let nutrients: [JSONValue] = Nutrient.allCases.compactMap { nutrient in
        guard let target = targets.values[nutrient] else { return nil }
        return .object([
          "label": .string(nutrient.label), "unit": .string(nutrient.unit),
          "actual": .number(totals[nutrient] ?? 0), "target": .number(target),
          "upperLimit": .bool(nutrient.isUpperLimit),
        ])
      }
      let input: [String: JSONValue] = [
        "weekday": .string(weekdayName),
        "time": .string(Date.now.formatted(date: .omitted, time: .shortened)),
        "dayType": .string(targets.dayType.label),
        "dayTypeSource": .string(targets.source.rawValue),
        "phase": .string(phaseName),
        "training": .array(training.map { .string($0) }),
        "planned": .array(plannedTexts.map { .string($0) }),
        "recovery": .string(recovery),
        "goal": .string(settings.nutrition.goal.label),
        "diet": .string(settings.nutrition.diet.label),
        "mealCount": .number(Double(todays.count)),
        "meals": .array(todays.map { .string("\($0.category.label): \($0.title)") }),
        "nutrients": .array(nutrients),
        "evidence": CoachingNote.evidenceInput(Self.reviewEvidence),
      ]
      let response = try await ai.run(task: "nutrition_review", input: input)
      reviewPoints = CoachingNote.points(from: response.output)
      reviewSources = CoachingNote.sources(from: response.output)
      reviewModel = response.model
    }
  }

  /// Regeln, auf die sich die Ernährungsauswertung stützen darf.
  static let reviewEvidence = [
    "nutrition.energy", "nutrition.carbs", "nutrition.protein", "nutrition.reds", "recovery.sleep",
  ]

  // MARK: - Hilfen

  static func category(at date: Date) -> MealCategory {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return MealCategory.guess(hour: components.hour ?? 12, minute: components.minute ?? 0)
  }

  /// Eigene, schon einmal gespeicherte Lebensmittel haben Vorrang vor der KI-Schätzung (Nährwerte je 100 g).
  private func preferKnownFood(_ item: MealItem, foods: [FoodRecord]) -> MealItem {
    guard let known = foods.first(where: { $0.name.lowercased() == item.name.lowercased() })?.item,
      known.source != .ai
    else { return item }
    var merged = item
    merged.per100g = known.per100g
    merged.source = known.source
    merged.barcode = known.barcode
    return merged
  }

  private var lastError: (any Error)?

  private func work(_ operation: () async throws -> Void) async {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    lastError = nil
    do {
      try await operation()
    } catch {
      lastError = error
      errorMessage = error.localizedDescription
    }
  }
}
