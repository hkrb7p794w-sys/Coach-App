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
  }

  private(set) var day = CalendarDay(date: .now)
  private(set) var targets: NutritionTargets?
  private(set) var totals = NutrientValues()
  private(set) var isWorking = false
  private(set) var reviewPoints: [String] = []
  private(set) var reviewModel: String?
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
    day = CalendarDay(date: now)
    let todaysActivities = activities.filter { $0.day == day }
    let week = WeeklyVolume(activities: activities, weekContaining: day)
    let plan = SeasonPlan.state(today: day, config: settings.season, week: week)
    targets = NutritionPlanner.compute(
      activities: todaysActivities, planItems: plan.todayFixed, settings: settings.nutrition,
      garminProfile: profile, day: day, hasGarminData: hasGarminData)
    totals = NutritionSummary.totals(meals.filter { $0.dayKey == day.iso }.flatMap(\.items))
  }

  // MARK: - Erfassen

  func newManualDraft(now: Date = .now) {
    let item = MealItem(name: "", grams: 100, source: .manual, per100g: NutrientValues())
    draft = Draft(title: "", category: Self.category(at: now), hint: "", items: [item])
  }

  func edit(_ record: MealRecord) {
    draft = Draft(
      record: record, title: record.title, category: record.category, hint: record.hint, items: record.items)
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
    } else {
      context.insert(MealRecord(day: day, category: draft.category, title: title, hint: draft.hint, items: items))
    }
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
    try? context.save()
    self.draft = nil
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
      let week = WeeklyVolume(activities: activities, weekContaining: day)
      let plan = SeasonPlan.state(today: day, config: settings.season, week: week)
      let training = activities.filter { $0.day == day }.map { activity -> String in
        let minutes = Int(((activity.durationSeconds ?? 0) / 60).rounded())
        let load = activity.trainingLoad.map { ", Last \(Int($0.rounded()))" } ?? ""
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
        "weekday": .string(plan.weekday),
        "time": .string(Date.now.formatted(date: .omitted, time: .shortened)),
        "dayType": .string(targets.dayType.label),
        "dayTypeSource": .string(targets.source.rawValue),
        "phase": .string(plan.phase.rawValue),
        "training": .array(training.map { .string($0) }),
        "planned": .array(plan.todayFixed.map { .string($0.text) }),
        "recovery": .string(recovery),
        "goal": .string(settings.nutrition.goal.label),
        "diet": .string(settings.nutrition.diet.label),
        "mealCount": .number(Double(todays.count)),
        "meals": .array(todays.map { .string("\($0.category.label): \($0.title)") }),
        "nutrients": .array(nutrients),
      ]
      let response = try await ai.run(task: "nutrition_review", input: input)
      reviewPoints = CoachingNote.points(from: response.output)
      reviewModel = response.model
    }
  }

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
