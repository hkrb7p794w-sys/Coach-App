import CoachCore
import PhotosUI
import SwiftData
import SwiftUI

/// Ernährung des Tages: Ziele nach Training, Mahlzeiten, Erfassen per Foto, Text, Barcode oder manuell und die
/// gemeinsame KI-Auswertung von Ernährung und Training.
struct NutritionView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.modelContext) private var context
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @Query(sort: \FoodRecord.useCount, order: .reverse) private var foods: [FoodRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]
  @State private var viewModel = NutritionViewModel()
  @State private var sheet: Sheet?
  @State private var photoItem: PhotosPickerItem?

  enum Sheet: String, Identifiable {
    case text, camera, barcode
    var id: String { rawValue }
  }

  private var todaysMeals: [MealRecord] {
    meals.filter { $0.dayKey == viewModel.day.iso }
  }

  private var refreshKey: String {
    let settings = model.settings
    return "\(meals.count)-\(meals.last?.itemsPayload.count ?? 0)-\(activities.count)-"
      + "\(settings.season.hashValue)-\(settings.nutrition.goal.rawValue)-\(settings.nutrition.weightKilograms ?? 0)"
  }

  var body: some View {
    NavigationStack {
      List {
        if let targets = viewModel.targets {
          TargetsSection(targets: targets, totals: viewModel.totals)
        }
        mealsSection
        reviewSection
      }
      .navigationTitle("Ernährung")
      .toolbar { addMenu }
      .overlay {
        if viewModel.isWorking {
          ProgressView("Wird ausgewertet …")
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .task(id: refreshKey) { refresh() }
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        photoItem = nil
        Task {
          let data = try? await item.loadTransferable(type: Data.self)
          await viewModel.analyze(text: "", photo: data, ai: model.ai, settings: model.settings, foods: foods)
        }
      }
      .sheet(item: $sheet) { sheet in
        switch sheet {
        case .text:
          MealTextEntry { text, photo in
            await viewModel.analyze(text: text, photo: photo, ai: model.ai, settings: model.settings, foods: foods)
          }
        case .camera:
          CameraPicker { data in
            Task {
              await viewModel.analyze(text: "", photo: data, ai: model.ai, settings: model.settings, foods: foods)
            }
          }
          .ignoresSafeArea()
        case .barcode:
          BarcodeEntry { code in
            Task { await viewModel.lookup(barcode: code, foods: foods, context: context) }
          }
        }
      }
      .sheet(item: $viewModel.draft) { draft in
        MealEditor(draft: draft, viewModel: viewModel, foods: foods)
      }
      .alert(
        "Hinweis",
        isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(viewModel.errorMessage ?? "")
      }
    }
  }

  private func refresh() {
    viewModel.update(
      meals: meals,
      activities: activities.compactMap(\.activity),
      settings: model.settings,
      profile: model.sync.profile,
      hasGarminData: !days.isEmpty
    )
  }

  private var addMenu: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Menu {
        if CameraPicker.isAvailable {
          Button("Foto aufnehmen", systemImage: "camera") { sheet = .camera }
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
          Label("Foto auswählen", systemImage: "photo")
        }
        Button("Beschreiben", systemImage: "text.bubble") { sheet = .text }
        Button("Barcode", systemImage: "barcode.viewfinder") { sheet = .barcode }
        Button("Manuell", systemImage: "square.and.pencil") { viewModel.newManualDraft() }
      } label: {
        Label("Erfassen", systemImage: "plus")
      }
    }
  }

  private var mealsSection: some View {
    Section("Mahlzeiten") {
      if todaysMeals.isEmpty {
        Text("Noch nichts erfasst. Über „+“ per Foto, Text, Barcode oder manuell.")
          .foregroundStyle(.secondary)
      }
      ForEach(MealCategory.allCases, id: \.self) { category in
        ForEach(todaysMeals.filter { $0.category == category }) { meal in
          Button {
            viewModel.edit(meal)
          } label: {
            MealRow(meal: meal)
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("Löschen", role: .destructive) { viewModel.delete(meal, context: context) }
          }
        }
      }
    }
  }

  private var reviewSection: some View {
    Section {
      ForEach(viewModel.reviewPoints, id: \.self) { point in
        Text(point)
      }
      Button("Ernährung und Training auswerten", systemImage: "sparkles") {
        Task {
          await viewModel.review(
            meals: meals, activities: activities.compactMap(\.activity), ai: model.ai, settings: model.settings,
            recovery: recoveryText)
        }
      }
      .disabled(viewModel.isWorking || !model.ai.isConfigured)
      if !viewModel.reviewPoints.isEmpty {
        EvidenceDisclosure(ruleIDs: viewModel.reviewSources + NutritionViewModel.reviewEvidence)
      }
    } header: {
      Text("KI-Auswertung")
    } footer: {
      if let model = viewModel.reviewModel {
        Text("KI · \(model). Schätzungen – Nährwerte aus Fotos können deutlich abweichen.")
      } else if !model.ai.isConfigured {
        Text("Dafür den KI-Worker in den Einstellungen einrichten.")
      }
    }
  }

  private var recoveryText: String {
    let records = days.compactMap(\.metrics)
    guard let today = records.first else { return "keine Daten" }
    let average = RecoveryEvaluator.average(
      \.restingHeartRate, in: records, daysBefore: 1...7, today: today.day)
    return RecoveryEvaluator.evaluate(today, restingHeartRate7DayAverage: average).label
  }
}

private struct TargetsSection: View {
  static let primary: [Nutrient] = [.kcal, .protein, .carbs, .fat, .fiber, .water]
  let targets: NutritionTargets
  let totals: NutrientValues

  var body: some View {
    Section {
      ForEach(Self.primary, id: \.self) { nutrient in
        NutrientRow(nutrient: nutrient, actual: totals[nutrient], target: targets.values[nutrient])
      }
      DisclosureGroup("Weitere Nährstoffe") {
        ForEach(Nutrient.allCases.filter { !Self.primary.contains($0) }, id: \.self) { nutrient in
          NutrientRow(nutrient: nutrient, actual: totals[nutrient], target: targets.values[nutrient])
        }
      }
    } header: {
      Text("\(targets.dayType.label) · \(targets.source.rawValue)")
    } footer: {
      Text(
        "Grundumsatz \(Int(targets.basalMetabolicRate)) kcal, Training \(Int(targets.exerciseKilocalories)) kcal, "
          + "Protein \(GermanFormat.decimal(targets.proteinPerKilogram)) g/kg."
          + (targets.energyAvailabilityFloorApplied ? " Energie auf Mindestverfügbarkeit angehoben." : ""))
    }
  }
}

private struct NutrientRow: View {
  let nutrient: Nutrient
  let actual: Double?
  let target: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(nutrient.label)
        Spacer()
        Text("\(Self.format(actual ?? 0)) / \(target.map(Self.format) ?? "–") \(nutrient.unit)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      if let percent = NutritionSummary.percent(actual, of: target) {
        ProgressView(value: Double(min(percent, 100)), total: 100)
          .tint(nutrient.isUpperLimit ? (percent > 100 ? .red : .orange) : (percent >= 100 ? .green : .accentColor))
      }
    }
  }

  static func format(_ value: Double) -> String {
    value >= 10 ? String(Int(value.rounded())) : GermanFormat.decimal(value)
  }
}

private struct MealRow: View {
  let meal: MealRecord

  var body: some View {
    let totals = NutritionSummary.totals(meal.items)
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(meal.title).font(.headline).lineLimit(1)
        Spacer()
        Text("\(Int((totals[.kcal] ?? 0).rounded())) kcal").monospacedDigit()
      }
      Text(
        "\(meal.category.label) · Protein \(Int((totals[.protein] ?? 0).rounded())) g · "
          + "KH \(Int((totals[.carbs] ?? 0).rounded())) g · Fett \(Int((totals[.fat] ?? 0).rounded())) g"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}
