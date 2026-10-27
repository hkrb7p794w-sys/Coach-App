import Charts
import CoachCore
import SwiftData
import SwiftUI

/// Gewichtsverlauf: Wägungen eintragen (oder von Garmin), Trend über 28 Tage und Vorschlag, die Tagesenergie
/// nachzusteuern. Die Anpassung übernimmt die Person selbst; die App ändert nichts ohne Zustimmung.
struct WeightTrendView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activities: [ActivityRecord]
  @State private var input = ""
  @State private var day = Date.now
  @FocusState private var inputFocused: Bool

  private var today: CalendarDay { CalendarDay(date: .now) }

  private var entries: [WeightEntry] {
    WeightTrend.merged(model.allWeights)
  }

  private var result: WeightTrend.Result? {
    WeightTrend.trend(entries, today: today)
  }

  /// Erfasste kcal je Tag.
  private var intake: [CalendarDay: Double] {
    var result: [CalendarDay: Double] = [:]
    for meal in meals {
      guard let day = CalendarDay(iso: meal.dayKey) else { continue }
      result[day, default: 0] += NutritionSummary.totals(meal.items)[.kcal] ?? 0
    }
    return result
  }

  /// Verbrauch laut Ernährung und Gewicht mit dem Bedarf laut Formel an denselben Tagen.
  private var expenditure: (result: Expenditure.Result, formula: Double)? {
    let settings = model.settings.nutrition
    let body = settings.profile(garmin: model.sync.profile, on: today)
    let days = intake
    guard
      let result = Expenditure.estimate(
        intake: days, weights: entries, today: today,
        basalMetabolicRate: NutritionPlanner.mifflinStJeor(body))
    else { return nil }
    // Formel ohne Ziel und Anpassung: Grundumsatz × Alltag + Training des jeweiligen Tages.
    var maintenance = settings
    maintenance.goal = .maintain
    maintenance.weeklyWeightChangePercent = nil
    maintenance.energyAdjustmentKilocalories = 0
    let all = activities.compactMap(\.activity)
    let start = today.adding(days: -Expenditure.windowDays)
    let loggedDays = days.keys.filter { $0 >= start && $0 < today }
    let values = loggedDays.map { day in
      NutritionPlanner.compute(
        activities: all.filter { $0.day == day }, planItems: [], settings: maintenance,
        garminProfile: model.sync.profile, day: day, hasGarminData: true
      ).values[.kcal] ?? 0
    }
    guard !values.isEmpty else { return nil }
    return (result, values.reduce(0, +) / Double(values.count))
  }

  /// Geplantes Tempo in % pro Woche; `nil` = Gewicht halten. Ohne festgelegtes Tempo bei Ab- oder Zunehmen gibt es
  /// keinen Vergleich (die App rät dann nicht).
  private var plan: (known: Bool, percent: Double?) {
    let nutrition = model.settings.nutrition
    if let weekly = nutrition.weeklyWeightChangePercent { return (true, weekly) }
    return (nutrition.goal == .maintain, nil)
  }

  var body: some View {
    List {
      entrySection
      if let result {
        trendSection(result)
      } else {
        Section {
          Text(
            "Für einen Trend braucht die App mindestens \(WeightTrend.minimumEntries) Wägungen über "
              + "\(WeightTrend.minimumSpanDays) Tage. Am besten täglich morgens nach dem Aufstehen wiegen."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      }
      if let expenditure {
        expenditureSection(expenditure.result, formula: expenditure.formula)
      }
      if model.settings.nutrition.energyAdjustmentKilocalories != 0 {
        adjustmentSection
      }
      historySection
    }
    .navigationTitle("Gewichtsverlauf")
  }

  private var entrySection: some View {
    Section {
      HStack {
        TextField("Gewicht", text: $input)
          .keyboardType(.decimalPad)
          .focused($inputFocused)
        Text("kg").foregroundStyle(.secondary)
      }
      DatePicker("Tag", selection: $day, in: ...Date.now, displayedComponents: .date)
      Button("Eintragen", systemImage: "plus.circle.fill") {
        guard let value = parsedInput else { return }
        model.settings.logWeight(value, on: CalendarDay(date: day))
        input = ""
        inputFocused = false
      }
      .disabled(parsedInput == nil)
    } header: {
      Text("Wägung eintragen")
    } footer: {
      Text("Wägungen aus Garmin Connect (Waage oder App) kommen beim Abruf dazu; deine Eingabe hat Vorrang.")
    }
  }

  private var parsedInput: Double? {
    let value = Double(input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    return value.flatMap { (30...250).contains($0) ? $0 : nil }
  }

  private func trendSection(_ result: WeightTrend.Result) -> some View {
    let start = today.adding(days: -(WeightTrend.windowDays - 1))
    let recent = entries.filter { $0.day >= start }
    return Section {
      Chart(recent) { entry in
        PointMark(x: .value("Tag", entry.day.localDate, unit: .day), y: .value("kg", entry.kilograms))
          .foregroundStyle(entry.source == .manual ? Color.accentColor : Color.secondary)
      }
      .chartYScale(domain: .automatic(includesZero: false))
      .frame(height: 160)
      .accessibilityLabel("Wägungen der letzten vier Wochen")
      LabeledContent("Trendgewicht heute", value: "\(GermanFormat.number(result.trendKilograms)) kg")
      LabeledContent("Änderung pro Woche", value: "\(signed(result.weeklyPercent)) %")
      if let expenditure, expenditure.result.plausible {
        Text("Die Anpassung ergibt sich aus deinem gemessenen Verbrauch (siehe unten).")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else if plan.known {
        let advice = WeightTrend.advice(
          result: result, plannedPercent: plan.percent,
          currentAdjustment: model.settings.nutrition.energyAdjustmentKilocalories)
        adviceRow(advice)
      } else {
        Text(
          "Lege im Profil ein Zieltempo fest, dann vergleicht die App deinen Verlauf damit und schlägt "
            + "Anpassungen vor."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
    } header: {
      Text("Trend (\(result.entries) Wägungen, \(result.spanDays) Tage)")
    }
  }

  private func expenditureSection(_ result: Expenditure.Result, formula: Double) -> some View {
    let current = model.settings.nutrition.energyAdjustmentKilocalories
    return Section {
      LabeledContent("Verbrauch laut Verlauf", value: "\(GermanFormat.number(result.kilocalories)) kcal")
      LabeledContent("Laut Formel", value: "\(GermanFormat.number((formula / 10).rounded() * 10)) kcal")
      LabeledContent("Im Schnitt gegessen", value: "\(GermanFormat.number(result.averageIntake)) kcal")
      if !result.plausible {
        Label(
          "Das Ergebnis ist unplausibel – vermutlich fehlen Mahlzeiten. Erfasse alles, was du isst, auch Getränke "
            + "und Snacks.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline)
        .foregroundStyle(.orange)
      } else if let proposal = Expenditure.adjustment(result, formulaMaintenance: formula, current: current) {
        Button {
          var nutrition = model.settings.nutrition
          nutrition.energyAdjustmentKilocalories = proposal
          model.settings.nutrition = nutrition
        } label: {
          Label(
            proposal == 0
              ? "Anpassung zurücksetzen (Formel passt)"
              : "Tagesziele um \(proposal > 0 ? "+" : "−")\(Int(abs(proposal))) kcal anpassen",
            systemImage: "checkmark")
        }
      } else {
        Label("Deine Tagesziele passen zu deinem Verbrauch.", systemImage: "checkmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.green)
      }
      EvidenceDisclosure(ruleIDs: ["energy.measured"])
    } header: {
      Text("Gemessener Verbrauch")
    } footer: {
      Text(
        "Aus \(result.loggedDays) Tagen mit erfassten Mahlzeiten"
          + (result.excludedDays > 0 ? " (\(result.excludedDays) unvollständige Tage nicht gezählt)" : "")
          + " und dem Gewichtstrend. Nur so genau wie deine Erfassung."
      )
    }
  }

  @ViewBuilder
  private func adviceRow(_ advice: WeightTrend.Advice) -> some View {
    Label {
      Text(advice.message).font(.subheadline)
    } icon: {
      Image(systemName: advice.kind == .onTrack ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
        .foregroundStyle(advice.kind == .tooFast ? Color.orange : advice.kind == .onTrack ? Color.green : Color.blue)
    }
    if advice.kilocalories != 0 {
      Button {
        var nutrition = model.settings.nutrition
        nutrition.energyAdjustmentKilocalories += advice.kilocalories
        model.settings.nutrition = nutrition
      } label: {
        Label(
          "Übernehmen (\(advice.kilocalories > 0 ? "+" : "−")\(Int(abs(advice.kilocalories))) kcal pro Tag)",
          systemImage: "checkmark")
      }
    }
    EvidenceDisclosure(ruleIDs: advice.evidenceIDs)
  }

  private var adjustmentSection: some View {
    let value = model.settings.nutrition.energyAdjustmentKilocalories
    return Section {
      LabeledContent(
        "Aktuelle Anpassung", value: "\(value > 0 ? "+" : "−")\(Int(abs(value))) kcal pro Tag")
      Button("Zurücksetzen", role: .destructive) {
        var nutrition = model.settings.nutrition
        nutrition.energyAdjustmentKilocalories = 0
        model.settings.nutrition = nutrition
      }
    } footer: {
      Text("Die Anpassung gilt für alle Tagesziele. Die Untergrenze für die Energieverfügbarkeit bleibt bestehen.")
    }
  }

  static func icon(_ source: WeightEntry.Source) -> String {
    switch source {
    case .manual: "pencil"
    case .garmin: "applewatch"
    case .health: "heart.fill"
    }
  }

  static func sourceLabel(_ source: WeightEntry.Source) -> String {
    switch source {
    case .manual: "eigene Eingabe"
    case .garmin: "Garmin"
    case .health: "Apple Health"
    }
  }

  private var historySection: some View {
    Section("Verlauf") {
      if entries.isEmpty {
        Text("Noch keine Wägungen.").foregroundStyle(.secondary)
      }
      ForEach(Array(entries.reversed().prefix(60))) { entry in
        HStack {
          Text(GermanFormat.date(entry.day))
          Spacer()
          Text("\(GermanFormat.number(entry.kilograms)) kg").monospacedDigit()
          Image(systemName: Self.icon(entry.source))
            .foregroundStyle(.secondary)
            .accessibilityLabel(Self.sourceLabel(entry.source))
        }
        .swipeActions {
          if entry.source == .manual {
            Button("Löschen", role: .destructive) {
              model.settings.weights.removeAll { $0.day == entry.day }
            }
          }
        }
      }
    }
  }

  private func signed(_ value: Double) -> String {
    (value > 0 ? "+" : value < 0 ? "−" : "") + GermanFormat.number(abs(value))
  }
}
