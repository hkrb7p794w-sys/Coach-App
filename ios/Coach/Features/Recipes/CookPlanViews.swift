import CoachCore
import SwiftData
import SwiftUI

/// Freigaben über den Worker (`/v1/share/cook`). Die Worker-Adresse und das Token kommen aus den eigenen Einstellungen.
enum CookShareService {
  private struct Created: Decodable {
    let code: String
    let expiresAt: String?
  }

  static func publish(_ share: CookShare, ai: AIClient) async throws -> (code: String, expiresAt: String?) {
    let data = try await ai.send(path: "v1/share/cook", method: "POST", body: JSONEncoder().encode(share))
    let created = try JSONDecoder().decode(Created.self, from: data)
    return (created.code, created.expiresAt)
  }

  static func update(_ share: CookShare, code: String, ai: AIClient) async throws -> String? {
    let data = try await ai.send(path: "v1/share/cook/\(code)", method: "PUT", body: JSONEncoder().encode(share))
    return try JSONDecoder().decode(Created.self, from: data).expiresAt
  }

  static func fetch(_ code: String, ai: AIClient) async throws -> CookShare {
    let data = try await ai.send(path: "v1/share/cook/\(code)", method: "GET")
    return try JSONDecoder().decode(CookShare.self, from: data)
  }

  static func revoke(_ code: String, ai: AIClient) async throws {
    _ = try await ai.send(path: "v1/share/cook/\(code)", method: "DELETE")
  }

  static func link(_ code: String, ai: AIClient) -> URL? {
    AIClient.normalizedURL(ai.workerURL)?.appending(path: "k/\(code)")
  }

  static func inviteLink(ai: AIClient) -> URL? {
    AIClient.normalizedURL(ai.workerURL)?.appending(path: "k/einladen")
  }
}

/// Rezeptideen für eine oder zwei Personen, frisch oder zum Vorkochen.
struct CookPlanView: View {
  let viewModel: RecipeViewModel
  let favorites: [String]
  @Environment(AppModel.self) private var model

  private enum Preset: Hashable, CaseIterable {
    case one, two, four, six, twoDays, threeDays, custom

    var label: String {
      switch self {
      case .one: "1 Portion"
      case .two: "2 Portionen"
      case .four: "4 Portionen"
      case .six: "6 Portionen"
      case .twoDays: "2 Tage"
      case .threeDays: "3 Tage"
      case .custom: "Eigene Anzahl"
      }
    }
  }

  private enum Unit: Hashable {
    case portions, days
  }

  @State private var audience = CookAudience.me
  @State private var partnerCode: String?
  @State private var meal = MealCategory.dinner
  @State private var preset = Preset.two
  @State private var unit = Unit.portions
  @State private var customCount = 3

  private var partner: CookPartner? {
    let partners = model.settings.cookPartners
    return partners.first { $0.code == partnerCode } ?? partners.first
  }

  private var amount: CookAmount {
    switch preset {
    case .one: .portions(1)
    case .two: .portions(2)
    case .four: .portions(4)
    case .six: .portions(6)
    case .twoDays: .days(2)
    case .threeDays: .days(3)
    case .custom: unit == .portions ? .portions(customCount) : .days(customCount)
    }
  }

  /// Der Plan in einem Satz, damit Portionen und Tage nicht verwechselt werden.
  private var summary: String {
    let eaters = audience == .both ? 2 : 1
    switch amount {
    case .portions(let count):
      if eaters == 2 { return "\(count) Teller, auf euch beide verteilt." }
      return count == 1 ? "Ein Teller." : "\(count) Teller für mehrere Mahlzeiten."
    case .days(let count):
      return "Einmal kochen, \(count) Tage essen: je Tag \(eaters == 2 ? "ein Teller pro Person" : "ein Teller")."
    }
  }

  var body: some View {
    List {
      Section {
        Picker("Für wen", selection: $audience) {
          Text("Nur für mich").tag(CookAudience.me)
          if let partner {
            Text("Nur für \(partner.share.name)").tag(CookAudience.partner)
            Text("Für uns beide").tag(CookAudience.both)
          }
        }
        if model.settings.cookPartners.count > 1, audience != .me {
          Picker("Person", selection: Binding(get: { partner?.code ?? "" }, set: { partnerCode = $0 })) {
            ForEach(model.settings.cookPartners) { Text($0.share.name).tag($0.code) }
          }
        }
        NavigationLink("Gemeinsam kochen: Personen und Freigaben") { CookPartnersView(viewModel: viewModel) }
      } header: {
        Text("Für wen")
      }
      Section("Was und wie viel") {
        Picker("Mahlzeit", selection: $meal) {
          ForEach([MealCategory.breakfast, .lunch, .dinner, .snack], id: \.self) { Text($0.label).tag($0) }
        }
        Picker("Menge", selection: $preset) {
          ForEach(Preset.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if preset == .custom {
          Picker("Einheit", selection: $unit) {
            Text("Portionen").tag(Unit.portions)
            Text("Tage").tag(Unit.days)
          }
          .pickerStyle(.segmented)
          Stepper(
            "Anzahl: \(customCount)", value: $customCount,
            in: 1...(unit == .portions ? CookAmount.maxPortions : CookAmount.maxDays))
        }
        Text(summary).font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        Button(viewModel.isCooking ? "Rezepte werden erstellt …" : "Rezepte vorschlagen", systemImage: "sparkles") {
          Task {
            await viewModel.createCookPlans(
              audience: audience, partner: partner, meal: meal, amount: amount, ai: model.ai, settings: model.settings,
              garminProfile: model.sync.profile, favorites: favorites)
          }
        }
        .disabled(viewModel.isCooking)
        if let error = viewModel.cookError {
          Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
        }
      } footer: {
        Text(
          "Gericht und Nährwerte schlägt die KI vor; Tellergrößen, Mengen und Haltbarkeit rechnet und prüft die App.")
      }
      if !viewModel.cookNotes.isEmpty {
        Section("Prüfung") {
          ForEach(viewModel.cookNotes, id: \.self) { Label($0, systemImage: "checkmark.shield").font(.footnote) }
        }
      }
      if !viewModel.cookPlans.isEmpty {
        Section("Vorschläge") {
          ForEach(viewModel.cookPlans) { plan in
            NavigationLink {
              CookPlanDetailView(viewModel: viewModel, planID: plan.id)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(.headline)
                Text(
                  "\(plan.amount.label) · \(plan.people.map(\.name).joined(separator: " und ")) · \(plan.minutes) min"
                )
                .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          .onDelete { offsets in
            for plan in offsets.map({ viewModel.cookPlans[$0] }) { viewModel.delete(plan) }
          }
        }
      }
    }
    .navigationTitle("Kochen planen")
    .task { viewModel.loadCookPlans() }
    .onChange(of: model.settings.cookPartners) { _, partners in
      if partners.isEmpty { audience = .me }
    }
  }
}

/// Mengen je Person, Gesamtmengen und Nährwerte; Zutaten lassen sich ändern, alles rechnet sich daraus neu.
struct CookPlanDetailView: View {
  let viewModel: RecipeViewModel
  let planID: UUID
  @Query(sort: \FoodRecord.useCount, order: .reverse) private var foods: [FoodRecord]
  @State private var nutrition = NutritionViewModel()
  @State private var editing = false

  private var plan: CookPlan? { viewModel.cookPlans.first { $0.id == planID } }

  var body: some View {
    Group {
      if let plan {
        content(plan)
      } else {
        ContentUnavailableView("Rezept nicht mehr vorhanden", systemImage: "fork.knife")
      }
    }
    .navigationTitle(plan?.title ?? "Rezept")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button(editing ? "Fertig" : "Bearbeiten") { editing.toggle() }
    }
    .sheet(item: $nutrition.draft) { draft in
      MealEditor(draft: draft, viewModel: nutrition, foods: foods)
    }
  }

  private func content(_ plan: CookPlan) -> some View {
    List {
      Section("Wer isst wie viel") {
        ForEach(plan.portions) { portion in
          VStack(alignment: .leading, spacing: 3) {
            Text(portion.person.name).font(.headline)
            Text(
              "\(portion.plates) × \(Int(portion.grams.rounded())) g roh · \(percent(portion.sharePercent)) % des "
                + "Gerichts je Teller"
            )
            .font(.subheadline)
            Text("Je Teller: \(macros(portion.nutrients))").font(.caption).foregroundStyle(.secondary)
            if let target = portion.target {
              Text("Ziel: \(Int(target.kcal.rounded())) kcal, \(Int((target.protein ?? 0).rounded())) g Protein")
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(portion.notes, id: \.self) { note in
              Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      Section("Ganzes Gericht") {
        Text(macros(plan.wholeNutrients)).font(.subheadline)
        if !plan.compromise.isEmpty {
          Label(plan.compromise, systemImage: "scalemass").font(.footnote)
        }
      }
      ingredients(plan)
      if plan.mealsPerPerson > 1 {
        storage(plan)
      }
      if !plan.steps.isEmpty {
        Section("Zubereitung") {
          ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
            Text("\(index + 1). \(step)").font(.subheadline)
          }
        }
      }
      if let mine = plan.portions.first(where: { $0.person.id == CookPerson.meID }) {
        Section {
          Button("Meine Portion eintragen …", systemImage: "plus") {
            nutrition.draft = NutritionViewModel.Draft(
              title: plan.title, category: plan.meal, hint: "Aus Rezeptidee (Nährwerte KI-geschätzt)", items: mine.items
            )
          }
        }
      }
      Section {
        EmptyView()
      } footer: {
        Text("Quelle: \(plan.source). Nährwerte sind KI-Schätzungen wie bei der Mahlzeiten-Analyse.")
      }
    }
  }

  @ViewBuilder
  private func ingredients(_ plan: CookPlan) -> some View {
    Section {
      if editing {
        ForEach(plan.base) { item in
          Stepper(
            value: Binding(
              get: { item.grams },
              set: { grams in
                var changed = plan
                changed.setGrams(grams, of: item.id)
                viewModel.update(changed)
              }), in: 5...1_000, step: 5
          ) {
            LabeledContent(item.name, value: "\(Int(item.grams.rounded())) g")
          }
        }
        .onDelete { offsets in
          var changed = plan
          for item in offsets.map({ plan.base[$0] }) { changed.remove(itemID: item.id) }
          viewModel.update(changed)
        }
      } else {
        ForEach(plan.totalIngredients) { item in
          LabeledContent(item.name, value: amount(item.grams))
        }
      }
    } header: {
      Text(editing ? "Zutaten einer Basisportion" : "Zutaten insgesamt (roh)")
    } footer: {
      if editing { Text("Portionen, Gesamtmengen und Nährwerte rechnen sich aus diesen Mengen neu.") }
    }
  }

  private func storage(_ plan: CookPlan) -> some View {
    Section {
      if let days = plan.storagePlan {
        ForEach(Array(days.enumerated()), id: \.offset) { index, place in
          LabeledContent("Tag \(index + 1)", value: place.label)
        }
      } else {
        Label(
          "Nach deiner Änderung reicht die Haltbarkeit nicht für alle Tage.", systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
      }
      if !plan.storageHint.isEmpty { Text(plan.storageHint).font(.footnote) }
      if !plan.reheatHint.isEmpty { Text("Aufwärmen: \(plan.reheatHint)").font(.footnote) }
    } header: {
      Text("Lagerung")
    } footer: {
      Text("Gekochtes höchstens \(CookPlanner.maxFridgeDays) Tage im Kühlschrank (BfR), danach einfrieren.")
    }
  }

  private func macros(_ values: NutrientValues) -> String {
    "\(Int((values[.kcal] ?? 0).rounded())) kcal · \(Int((values[.protein] ?? 0).rounded())) g Protein · "
      + "\(Int((values[.carbs] ?? 0).rounded())) g KH · \(Int((values[.fat] ?? 0).rounded())) g Fett"
  }

  private func percent(_ value: Double) -> String { String(Int(value.rounded())) }

  private func amount(_ grams: Double) -> String {
    grams >= 1000 ? "\(GermanFormat.number((grams / 100).rounded() / 10)) kg" : "\(Int(grams)) g"
  }
}

/// Eigene Freigabe erteilen, ändern, zurückziehen; andere Personen verbinden.
struct CookPartnersView: View {
  var viewModel: RecipeViewModel?
  var initialCode: String?
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var ownViewModel = RecipeViewModel()
  @State private var name = ""
  @State private var fields = CookShareFields()
  @State private var codeInput = ""
  @State private var preview: (code: String, share: CookShare)?
  @State private var message: String?
  @State private var isBusy = false

  init(viewModel: RecipeViewModel? = nil, initialCode: String? = nil) {
    self.viewModel = viewModel
    self.initialCode = initialCode
  }

  private var plans: RecipeViewModel { viewModel ?? ownViewModel }

  /// Genau das, was gespeichert würde.
  private var draft: CookShare {
    let settings = model.settings
    let today = CalendarDay(date: .now)
    let body = settings.nutrition.profile(garmin: model.sync.profile, on: today)
    return CookPlanner.share(
      name: name, week: plans.targets, diet: settings.nutrition.diet, preferences: settings.recipes, fields: fields,
      safety: GoalRules.weightGuard(settings: settings.nutrition, body: body))
  }

  var body: some View {
    List {
      connectSection
      releaseSection
      Section {
        if let link = CookShareService.inviteLink(ai: model.ai) {
          ShareLink(
            item:
              "Magst du Rezepte mit mir zusammen planen? Du entscheidest selbst, was du freigibst: \(link.absoluteString)"
          ) {
            Label("Person einladen", systemImage: "person.badge.plus")
          }
        }
      } footer: {
        Text("Die Person braucht die App und einen KI-Zugang, zum Beispiel über eine Einladung der Rangliste.")
      }
      if let message {
        Section { Text(message).font(.footnote) }
      }
    }
    .navigationTitle("Gemeinsam kochen")
    .task {
      if plans.targets.isEmpty {
        plans.update(settings: model.settings, garminProfile: model.sync.profile, meals: [])
      }
      plans.loadCookPlans()
      name = model.settings.cookRelease?.share.name ?? name
      fields = model.settings.cookRelease?.fields ?? fields
      if let initialCode {
        codeInput = initialCode
        await lookUp()
      }
    }
  }

  private var connectSection: some View {
    Section {
      ForEach(model.settings.cookPartners) { partner in
        VStack(alignment: .leading, spacing: 2) {
          Text(partner.share.name).font(.headline)
          Text(summary(partner.share)).font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions {
          Button("Lösen", role: .destructive) { plans.forget(partner, settings: model.settings) }
        }
      }
      if let preview {
        VStack(alignment: .leading, spacing: 6) {
          Text("\(preview.share.name) gibt frei:").font(.headline)
          Text(summary(preview.share)).font(.footnote)
          Button("Verbinden", systemImage: "link") {
            model.settings.cookPartners.removeAll { $0.code == preview.code }
            model.settings.cookPartners.append(CookPartner(code: preview.code, share: preview.share))
            self.preview = nil
            codeInput = ""
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        TextField("Code oder Link der anderen Person", text: $codeInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Freigabe abrufen", systemImage: "arrow.down.circle") { Task { await lookUp() } }
          .disabled(isBusy || CookPlanner.code(from: codeInput) == nil)
      }
    } header: {
      Text("Verbundene Personen")
    } footer: {
      Text(
        "Verbunden sind nur die Angaben, die die andere Person freigegeben hat. Sie kann das jederzeit zurückziehen.")
    }
  }

  private var releaseSection: some View {
    Section {
      TextField("Dein Name für die andere Person", text: $name)
      Toggle("Tagesziele (Kalorien, Makros)", isOn: $fields.targets)
      Toggle("Ernährungsweise", isOn: $fields.diet)
      Toggle("Allergene und Unverträglichkeiten", isOn: $fields.allergens)
      Toggle("Was ich nicht mag", isOn: $fields.dislikes)
      Text("Wird freigegeben: \(summary(draft))").font(.footnote).foregroundStyle(.secondary)
      Button(
        model.settings.cookRelease == nil ? "Freigeben" : "Freigabe aktualisieren", systemImage: "square.and.arrow.up"
      ) {
        Task { await publish() }
      }
      .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)
      if let release = model.settings.cookRelease {
        if let link = CookShareService.link(release.code, ai: model.ai) {
          ShareLink(item: "Meine Freigabe für gemeinsame Rezepte: \(link.absoluteString)") {
            Label("Link senden", systemImage: "paperplane")
          }
        }
        Button("Freigabe zurückziehen", systemImage: "xmark.circle", role: .destructive) {
          Task { await revoke(release) }
        }
        .disabled(isBusy)
      }
    } header: {
      Text("Meine Freigabe")
    } footer: {
      Text(
        "Nur diese Angaben werden gespeichert, höchstens 90 Tage. Körperdaten, Gesundheitsangaben und dein Tagebuch "
          + "bleiben auf deinem iPhone. Für Rezepte gehen Ziele, Ernährungsweise und Allergene ohne deinen Namen an den "
          + "KI-Anbieter.")
    }
  }

  private func summary(_ share: CookShare) -> String {
    var parts: [String] = []
    if let kcal = share.kcal {
      parts.append("\(Int(kcal)) kcal, \(Int(share.protein ?? 0)) g Protein am Tag")
    } else {
      parts.append("keine Kalorienziele")
    }
    if let diet = share.diet { parts.append(diet.label) }
    if !share.allergens.isEmpty {
      parts.append(share.allergens.map(\.label).sorted().joined(separator: ", "))
    }
    if !share.dislikes.isEmpty { parts.append("mag nicht: \(share.dislikes)") }
    return parts.joined(separator: " · ")
  }

  private func lookUp() async {
    guard let code = CookPlanner.code(from: codeInput) else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      preview = (code, try await CookShareService.fetch(code, ai: model.ai))
      message = nil
    } catch AIClientError.http(404, _) {
      message = "Diese Freigabe gibt es nicht mehr. Bitte um einen neuen Link."
    } catch {
      message = error.localizedDescription
    }
  }

  private func publish() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let share = draft
      if let current = model.settings.cookRelease {
        let expiresAt = try await CookShareService.update(share, code: current.code, ai: model.ai)
        model.settings.cookRelease = CookRelease(code: current.code, fields: fields, share: share, expiresAt: expiresAt)
      } else {
        let created = try await CookShareService.publish(share, ai: model.ai)
        model.settings.cookRelease = CookRelease(
          code: created.code, fields: fields, share: share, expiresAt: created.expiresAt)
      }
      message = "Freigabe gespeichert."
    } catch AIClientError.http(404, _) {
      // Abgelaufen: neu anlegen, damit ein gültiger Link entsteht.
      model.settings.cookRelease = nil
      message = "Die alte Freigabe war abgelaufen. Bitte noch einmal freigeben."
    } catch {
      message = error.localizedDescription
    }
  }

  private func revoke(_ release: CookRelease) async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await CookShareService.revoke(release.code, ai: model.ai)
      model.settings.cookRelease = nil
      message = "Freigabe zurückgezogen. Beim nächsten Abruf werden deine Angaben auch bei der anderen Person gelöscht."
    } catch {
      message = error.localizedDescription
    }
  }
}
