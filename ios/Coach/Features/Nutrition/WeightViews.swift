import Charts
import CoachCore
import SwiftUI

/// Gewichtsverlauf: Wägungen eintragen (oder von Garmin), Trend über 28 Tage und Vorschlag, die Tagesenergie
/// nachzusteuern. Die Anpassung übernimmt die Person selbst; die App ändert nichts ohne Zustimmung.
struct WeightTrendView: View {
  @Environment(AppModel.self) private var model
  @State private var input = ""
  @State private var day = Date.now
  @FocusState private var inputFocused: Bool

  private var today: CalendarDay { CalendarDay(date: .now) }

  private var entries: [WeightEntry] {
    WeightTrend.merged(model.settings.weights + model.sync.weights)
  }

  private var result: WeightTrend.Result? {
    WeightTrend.trend(entries, today: today)
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
      if plan.known {
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
          Image(systemName: entry.source == .manual ? "pencil" : "applewatch")
            .foregroundStyle(.secondary)
            .accessibilityLabel(entry.source == .manual ? "eigene Eingabe" : "Garmin")
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
