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
    let todaysActivities = activities.filter { $0.day == day }
    // Saisonplan: Musterwoche aus dem Plan; persönliches Profil: die eigenen Einheiten des Wochentags.
    let planItems: [TemplateItem]
    if settings.profile.mode == .season {
      let week = WeeklyVolume(activities: activities, weekContaining: day)
      planItems = SeasonPlan.state(today: day, config: settings.season, week: week).todayFixed
    } else {
      planItems = settings.schedule(inWeekOf: day).templateItems(on: Weekday(day: day))
    }
    targets = NutritionPlanner.compute(
      activities: todaysActivities, planItems: planItems, settings: settings.nutrition,
      garminProfile: profile, day: day, hasGarminData: hasGarminData)
    totals = NutritionSummary.totals(meals.filter { $0.dayKey == day.iso }.flatMap(\.items))
  }

  // MARK: - Erfassen

  func newManualDraft(now: Date = .now) {
    let item = MealItem(name: "", grams: 100, source: .manual, per100g: NutrientValues())
    draft = Draft(title: "", category: Self.category(at: now), hint: "", items: [item])
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

  func analyze(text: String, photo: Data?, ai: AIClient, settings: CoachSettings, foods: [FoodRecord]) async {
    guard ai.isConfigured else {
      errorMessage = AIClientError.notConfigured.localizedDescription
      return
    }
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
    }
  }

  func lookup(barcode: String, foods: [FoodRecord], context: ModelContext) async {
    await work {
      let key = "barcode:\(barcode)"
      let item: MealItem
      if let cached = foods.first(where: { $0.key == key })?.item {
        item = cached
      } else {
        let product = try await openFoodFacts.product(barcode: barcode)
        item = product.item()
        context.insert(FoodRecord(item: item))
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

  private func work(_ operation: () async throws -> Void) async {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await operation()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
