import Charts
import CoachCore
import SwiftUI

/// Aerobe Kopplung (HF-Pace- bzw. HF-Watt-Drift) gleichmäßiger Einheiten aus den FIT-Dateien.
struct DecouplingSection: View {
  let title: String
  let sport: AerobicDecoupling.Sport
  let viewModel: TrainingViewModel
  var showsSkipped = false

  var body: some View {
    let sessions = viewModel.decoupled(sport)
    Section {
      if sessions.isEmpty {
        Text(
          sport == .run
            ? "Noch keine gewertete Einheit. Gewertet werden gleichmäßige Läufe ab 35 min mit höchstens 10 % der "
              + "Zeit in Zone 4–5."
            : "Noch keine gewertete Fahrt. Gewertet werden Fahrten ab 45 min mit Leistungsmessung und höchstens "
              + "10 % der Zeit in Zone 4–5."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      } else {
        if let average = ActivityAnalysisPlanner.recentAverage(sessions) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Ø letzte \(min(sessions.count, 5)) Einheiten").font(.caption).foregroundStyle(.secondary)
              Text("\(GermanFormat.decimal(average)) %")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DecouplingStyle.color(average))
            }
            Spacer()
            Text(DecouplingStyle.label(average)).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        Chart(sessions.suffix(12)) { analysis in
          let percent = analysis.decoupling?.percent ?? 0
          BarMark(x: .value("Datum", analysis.day.localDate, unit: .day), y: .value("Kopplung", percent))
            .foregroundStyle(DecouplingStyle.color(percent))
            .cornerRadius(3)
          RuleMark(y: .value("Grenze", AerobicDecoupling.goodBelowPercent))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.secondary)
        }
        .chartYAxisLabel("%")
        .frame(height: 140)
        .accessibilityLabel("Kopplung der letzten Einheiten")
        ForEach(sessions.suffix(6).reversed()) { analysis in
          DecouplingRow(analysis: analysis)
        }
      }
      if showsSkipped {
        let skipped = viewModel.skippedDecoupling
        if !skipped.isEmpty {
          DisclosureGroup("Nicht gewertet (\(skipped.count))") {
            ForEach(skipped.reversed()) { analysis in
              VStack(alignment: .leading, spacing: 2) {
                Text(analysis.name ?? "Aktivität").font(.subheadline)
                Text("\(GermanFormat.date(analysis.day)) · \(analysis.skipReason ?? "")")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    } header: {
      Text(title)
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          "Steigt die Herzfrequenz in der zweiten Hälfte bei gleichem Tempo bzw. gleicher Leistung, ist die Kopplung "
            + "positiv. Unter 5 % gilt als stabile Grundlage für diese Dauer. Die ersten 10 Minuten zählen nicht.")
        EvidenceDisclosure(ruleIDs: ["run.decoupling"])
      }
    }
  }
}

private struct DecouplingRow: View {
  let analysis: ActivityAnalysis

  var body: some View {
    let result = analysis.decoupling
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(analysis.name ?? "Einheit").font(.subheadline).lineLimit(1)
        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      Spacer()
      if let percent = result?.percent {
        Text("\(GermanFormat.decimal(percent)) %")
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(DecouplingStyle.color(percent))
      }
    }
  }

  private var detail: String {
    guard let result = analysis.decoupling else { return GermanFormat.date(analysis.day) }
    var parts = [
      GermanFormat.date(analysis.day),
      "HF \(Int(result.firstHalfHeartRate.rounded())) → \(Int(result.secondHalfHeartRate.rounded()))",
    ]
    if let first = result.firstHalfPace, let second = result.secondHalfPace {
      parts.append("\(PlanTokens.mmss(first)) → \(PlanTokens.mmss(second)) /km")
    }
    if let first = result.firstHalfPower, let second = result.secondHalfPower {
      parts.append("\(first) → \(second) W")
    }
    return parts.joined(separator: " · ")
  }
}

enum DecouplingStyle {
  static func color(_ percent: Double) -> Color {
    percent < AerobicDecoupling.goodBelowPercent ? .green : percent < 10 ? .orange : .red
  }

  static func label(_ percent: Double) -> String {
    percent < AerobicDecoupling.goodBelowPercent ? "stabil" : percent < 10 ? "erhöhte Drift" : "starke Drift"
  }
}

/// Pace-Check: Passt die eingestellte Schwellenpace zu den letzten harten Läufen?
struct PaceCheckSection: View {
  @Environment(AppModel.self) private var model
  let viewModel: TrainingViewModel
  @State private var accepted = false

  var body: some View {
    let result = viewModel.paceCheck(thresholdPace: model.settings.season.thresholdPaceSecondsPerKm)
    Section {
      HStack(spacing: 12) {
        Image(systemName: symbol(result.status))
          .font(.title3)
          .foregroundStyle(color(result.status))
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(headline(result)).font(.subheadline.weight(.semibold))
          Text("Schwelle \(PlanTokens.mmss(result.current)) /km · Intervalle \(result.intervalBand) /km")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      if let suggestion = PaceCheck.suggestionText(result), let suggested = result.suggested {
        VStack(alignment: .leading, spacing: 8) {
          Text(suggestion.title).font(.subheadline.weight(.medium))
          Text(suggestion.text).font(.footnote).foregroundStyle(.secondary)
          Button {
            model.settings.season.thresholdPaceSecondsPerKm = suggested
            accepted = true
          } label: {
            Label("\(PlanTokens.mmss(suggested)) /km übernehmen", systemImage: "checkmark.circle")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }
        .padding(.vertical, 4)
      }
      if !result.rows.isEmpty {
        DisclosureGroup("Ausgewertete Läufe (\(result.rows.count))") {
          ForEach(result.rows.reversed()) { row in
            PaceCheckRowView(row: row)
          }
        }
      }
    } header: {
      Text("Pace-Check")
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          "Ausgewertet werden Schwellen- und 4×4-Läufe der letzten 6 Wochen. Ein Vorschlag kommt erst, wenn "
            + "mindestens zwei Einheiten in dieselbe Richtung zeigen, und ändert höchstens 10 s/km. Der 30-min-Test "
            + "bleibt maßgeblich.")
        EvidenceDisclosure(ruleIDs: ["run.pace-check", "run.4x4"])
      }
    }
    .sensoryFeedback(.success, trigger: accepted)
  }

  private func headline(_ result: PaceCheck.Result) -> String {
    switch result.status {
    case .fits: "Schwellenpace passt"
    case .faster: "Schwelle eher schneller"
    case .slower: "Schwelle eher langsamer"
    case .tooFewData: "Noch zu wenig harte Läufe"
    }
  }

  private func symbol(_ status: PaceCheck.Status) -> String {
    switch status {
    case .fits: "checkmark.seal.fill"
    case .faster: "hare.fill"
    case .slower: "tortoise.fill"
    case .tooFewData: "hourglass"
    }
  }

  private func color(_ status: PaceCheck.Status) -> Color {
    switch status {
    case .fits: .green
    case .faster: .blue
    case .slower: .orange
    case .tooFewData: .secondary
    }
  }
}

private struct PaceCheckRowView: View {
  let row: PaceCheck.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(row.name ?? (row.kind == .vo2 ? "4×4" : "Schwellenlauf")).font(.subheadline).lineLimit(1)
        Spacer()
        Text(GermanFormat.date(row.day)).font(.caption).foregroundStyle(.secondary)
      }
      Text(row.verdict).font(.caption)
      if !details.isEmpty {
        Text(details).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
      }
    }
  }

  private var details: String {
    var parts: [String] = []
    if let minutes = row.workMinutes { parts.append("Arbeit \(minutes) min") }
    if let pace = row.workPace { parts.append("\(PlanTokens.mmss(pace)) /km") }
    if let heart = row.workHeartRate { parts.append("\(heart) bpm") }
    if let percent = row.heartRatePercentOfThreshold { parts.append("\(percent) % Schwellen-HF") }
    if let estimate = row.estimatedThreshold { parts.append("geschätzt \(PlanTokens.mmss(estimate)) /km") }
    if let peak = row.repetitionPeakPercentOfMax { parts.append("Spitze \(peak) % HFmax") }
    return parts.joined(separator: " · ")
  }
}
