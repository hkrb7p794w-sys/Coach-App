import CoachCore
import SwiftData
import SwiftUI

/// Teilen und Empfangen über den Worker (`/v1/share/meal`). Nur wer denselben App-Zugang hat, kann einen Code
/// abrufen; Codes verfallen nach 7 Tagen und lassen sich zurückziehen.
enum MealShareService {
  struct Created: Decodable {
    let code: String
    let expiresAt: String
  }

  static func share(_ meal: SharedMeal, ai: AIClient) async throws -> Created {
    let data = try await ai.send(path: "v1/share/meal", method: "POST", body: JSONEncoder().encode(meal))
    return try JSONDecoder().decode(Created.self, from: data)
  }

  static func fetch(_ code: String, ai: AIClient) async throws -> SharedMeal {
    let data = try await ai.send(path: "v1/share/meal/\(code)", method: "GET")
    return try JSONDecoder().decode(SharedMeal.self, from: data)
  }

  static func revoke(_ code: String, ai: AIClient) async throws {
    _ = try await ai.send(path: "v1/share/meal/\(code)", method: "DELETE")
  }

  /// https-Link, den Messenger anklickbar machen (die Seite öffnet coach://meal/<code>).
  static func link(_ code: String, ai: AIClient) -> URL? {
    AIClient.normalizedURL(ai.workerURL)?.appending(path: "m/\(code)")
  }
}

/// Teilen einer Mahlzeit: legt den Code an und bietet die Nachricht zum Weitergeben an.
struct ShareMealSheet: View {
  let title: String
  let items: [MealItem]
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var created: MealShareService.Created?
  @State private var error: String?
  @State private var revoked = false

  var body: some View {
    let meal = SharedMeal(title: title, items: items)
    NavigationStack {
      List {
        Section {
          Text(title).font(.headline)
          Text("\(meal.items.count) Positionen · \(Int(meal.kilocalories.rounded())) kcal")
            .foregroundStyle(.secondary)
        } footer: {
          Text(
            "Geteilt werden nur Titel, Mengen und Nährwerte – kein Name, kein Datum, keine Gesundheitsdaten. "
              + "Abrufen kann nur, wer IronLudi über denselben Zugang nutzt.")
        }
        if let created, !revoked {
          Section {
            ShareLink(
              item: MealShare.message(
                title: title, kilocalories: meal.kilocalories, link: MealShareService.link(created.code, ai: model.ai),
                code: created.code)
            ) {
              Label("Nachricht teilen", systemImage: "square.and.arrow.up")
            }
            LabeledContent("Code", value: created.code).textSelection(.enabled)
            Button("Freigabe zurückziehen", systemImage: "xmark.circle", role: .destructive) {
              Task {
                try? await MealShareService.revoke(created.code, ai: model.ai)
                revoked = true
              }
            }
          } footer: {
            Text("Gültig 7 Tage. Zurückziehen löscht die Mahlzeit sofort beim Worker.")
          }
        } else if revoked {
          Section { Text("Freigabe zurückgezogen.").foregroundStyle(.secondary) }
        } else if let error {
          Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
        } else {
          Section { ProgressView("Freigabe wird erstellt …") }
        }
      }
      .navigationTitle("Mahlzeit teilen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
      .task {
        guard created == nil else { return }
        do {
          created = try await MealShareService.share(meal, ai: model.ai)
        } catch {
          self.error = error.localizedDescription
        }
      }
    }
  }
}

/// Empfangene Mahlzeit: Vorschau und Übernahme als neuer Eintrag (nie überschreibend) oder als Favorit.
struct ReceivedMealSheet: View {
  let code: String?
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var input = ""
  @State private var meal: SharedMeal?
  @State private var error: String?
  @State private var category = NutritionViewModel.category(at: .now)
  @State private var done: String?

  var body: some View {
    NavigationStack {
      List {
        if meal == nil {
          Section {
            TextField("Code, z. B. k7m2q9xa4b", text: $input)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            Button("Öffnen") { Task { await load(input) } }
              .disabled(MealShare.code(from: input) == nil)
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
          } footer: {
            Text("Code oder Link aus der Nachricht einfügen.")
          }
        }
        if let meal {
          Section {
            ForEach(Array(meal.mealItems.enumerated()), id: \.offset) { _, item in
              LabeledContent(
                item.name,
                value: "\(GermanFormat.number(item.grams.rounded())) \(item.isDrink ? "ml" : "g") · "
                  + "\(Int((item.amounts[.kcal] ?? 0).rounded())) kcal")
            }
          } header: {
            Text("\(meal.title) · \(Int(meal.kilocalories.rounded())) kcal")
          } footer: {
            Text("Mengen und Nährwerte so, wie sie geteilt wurden – nach dem Übernehmen kannst du alles anpassen.")
          }
          Section {
            Picker("Mahlzeit", selection: $category) {
              ForEach(MealCategory.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Button("In mein Tagebuch (heute)", systemImage: "plus.circle.fill") { addToDiary(meal) }
              .disabled(done != nil)
            Button("Als Favorit merken", systemImage: "star") { addFavorite(meal) }
              .disabled(done != nil)
            if let done { Label(done, systemImage: "checkmark.circle").foregroundStyle(.green) }
          }
        }
      }
      .navigationTitle("Geteilte Mahlzeit")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
      .task {
        if let code, meal == nil { await load(code) }
      }
    }
  }

  private func load(_ text: String) async {
    guard let code = MealShare.code(from: text) else { return }
    do {
      meal = try await MealShareService.fetch(code, ai: model.ai)
      error = nil
    } catch AIClientError.http(404, _) {
      error = "Code unbekannt oder abgelaufen."
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// Immer ein neuer Eintrag – vorhandene Mahlzeiten bleiben unberührt.
  private func addToDiary(_ meal: SharedMeal) {
    let context = model.container.mainContext
    context.insert(
      MealRecord(
        day: CalendarDay(date: .now), category: category, title: meal.title, hint: "Geteilt", items: meal.mealItems))
    try? context.save()
    done = "Eingetragen unter \(category.label)."
  }

  private func addFavorite(_ meal: SharedMeal) {
    model.settings.favoriteMeals.append(FavoriteMeal(title: meal.title, items: meal.mealItems, category: category))
    done = "Als Favorit gespeichert."
  }
}

/// Erkennt geteilte Mahlzeiten in coach://-Links.
struct SharedMealLink: Identifiable {
  let code: String
  var id: String { code }

  init?(url: URL) {
    guard let code = MealShare.code(from: url.absoluteString) else { return nil }
    self.code = code
  }
}
