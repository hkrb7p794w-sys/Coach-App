import Charts
import CoachCore
import SwiftData
import SwiftUI

/// Erholung, Ausdauer und Herzfrequenz – die Garmin-Werte aus dem früheren Home-Assistant-Dashboard.
struct TrainingView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @State private var viewModel = TrainingViewModel()
  @State private var section = Part.recovery

  enum Part: String, CaseIterable, Identifiable {
    case recovery = "Erholung"
    case endurance = "Ausdauer"
    case heartRate = "Herzfrequenz"
    var id: String { rawValue }
  }

  private var refreshKey: String {
    "\(days.last?.updatedAt.timeIntervalSince1970 ?? 0)-\(activities.count)-\(model.settings.heartRate.hashValue)"
  }

  var body: some View {
    NavigationStack {
      List {
        Picker("Bereich", selection: $section) {
          ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        switch section {
        case .recovery: RecoverySections(viewModel: viewModel)
        case .endurance: EnduranceSections(viewModel: viewModel)
        case .heartRate: HeartRateSections(report: viewModel.zones)
        }
      }
      .navigationTitle("Training")
      .refreshable { await model.syncNow() }
      .task(id: refreshKey) {
        viewModel.update(
          days: days.compactMap(\.metrics),
          activities: activities.compactMap(\.activity),
          profile: model.sync.profile,
          watchZones: model.sync.raw(.heartRateZones),
          overrides: model.settings.heartRate
        )
      }
    }
  }
}

// MARK: - Erholung

private struct RecoverySections: View {
  let viewModel: TrainingViewModel

  var body: some View {
    if viewModel.recovery.isEmpty && viewModel.tiles.isEmpty {
      Section {
        Text("Noch keine Garmin-Werte. Ziehe nach unten, um abzurufen.").foregroundStyle(.secondary)
      }
    }
    ForEach(viewModel.recovery) { card in
      Section { TrendCardView(card: card) }
    }
    if !viewModel.tiles.isEmpty {
      Section {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
          ForEach(viewModel.tiles) { tile in
            VStack(alignment: .leading, spacing: 2) {
              Text(tile.value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7)
              Text(tile.title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
          }
        }
      } header: {
        Text("Werte von heute")
      } footer: {
        Text(
          "Training Readiness, Trainingsstatus und Endurance Score liefert die offizielle Garmin-Schnittstelle "
            + "nicht. Sie kommen mit dem optionalen Garmin-Login dazu.")
      }
    }
    if let night = viewModel.sleepStages {
      Section("Schlafphasen (\(Formatters.day(night.day)))") { SleepStagesView(metrics: night) }
    }
  }
}

private struct TrendCardView: View {
  let card: TrainingViewModel.TrendCard

  private var changeColor: Color {
    guard let change = card.trend.change, let higher = card.higherIsBetter, abs(change) >= 0.05 else {
      return .secondary
    }
    return (change > 0) == higher ? .green : .orange
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(card.title).font(.subheadline.bold())
        Spacer()
        Text(Formatters.number(card.trend.latest?.value, unit: card.unit, digits: card.digits))
          .font(.title3.weight(.semibold))
          .monospacedDigit()
      }
      Chart {
        ForEach(card.trend.points) { point in
          LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value(card.title, point.value))
            .interpolationMethod(.monotone)
        }
        if let average = card.trend.average {
          RuleMark(y: .value("Schnitt", average))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(.secondary)
        }
      }
      .chartYScale(domain: .automatic(includesZero: false))
      .frame(height: 110)
      HStack {
        Text("Ø 28 Tage \(Formatters.number(card.trend.average, unit: card.unit, digits: card.digits))")
        Spacer()
        if let change = card.trend.change {
          let sign = change >= 0 ? "+" : ""
          Text(sign + Formatters.number(change, unit: card.unit, digits: card.digits) + " zum Vormonat")
            .foregroundStyle(changeColor)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private struct SleepStagesView: View {
  let metrics: DailyMetrics

  private var stages: [(String, Double, Color)] {
    [
      ("Tief", metrics.deepSleepSeconds ?? 0, .indigo), ("Leicht", metrics.lightSleepSeconds ?? 0, .blue),
      ("REM", metrics.remSleepSeconds ?? 0, .cyan), ("Wach", metrics.awakeSleepSeconds ?? 0, .orange),
    ]
  }

  var body: some View {
    let total = max(stages.map(\.1).reduce(0, +), 1)
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { geometry in
        HStack(spacing: 2) {
          ForEach(stages, id: \.0) { _, seconds, color in
            color.frame(width: max(geometry.size.width * seconds / total - 2, 0))
          }
        }
      }
      .frame(height: 12)
      .clipShape(Capsule())
      HStack {
        ForEach(stages, id: \.0) { name, seconds, color in
          VStack(alignment: .leading) {
            Text(name).font(.caption).foregroundStyle(color)
            Text(Formatters.duration(seconds)).font(.caption.monospacedDigit())
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

// MARK: - Ausdauer

private struct EnduranceSections: View {
  let viewModel: TrainingViewModel

  private let sports: [(GarminActivity.Sport, String, Color)] = [
    (.swim, "Schwimmen", .blue), (.bike, "Rad", .orange), (.run, "Laufen", .green),
  ]

  var body: some View {
    ForEach(sports, id: \.0) { sport, title, color in
      Section {
        let thisWeek = viewModel.weeks.last?.volume.kilometers[sport] ?? 0
        let previous = viewModel.weeks.dropLast().suffix(4).map { $0.volume.kilometers[sport] ?? 0 }
        let average = previous.isEmpty ? 0 : previous.reduce(0, +) / Double(previous.count)
        HStack(alignment: .firstTextBaseline) {
          Text("Diese Woche").font(.subheadline)
          Spacer()
          Text(Formatters.number(thisWeek, unit: "km", digits: sport == .bike ? 0 : 1))
            .font(.title3.weight(.semibold)).monospacedDigit()
        }
        Chart(viewModel.weeks) { week in
          BarMark(
            x: .value("Woche", week.monday.localDate, unit: .weekOfYear),
            y: .value("km", week.volume.kilometers[sport] ?? 0)
          )
          .foregroundStyle(week.id == viewModel.weeks.last?.id ? color : color.opacity(0.45))
        }
        .frame(height: 120)
        Text(
          "Ø der 4 Wochen davor: \(Formatters.number(average, unit: "km", digits: 1)) · "
            + "\(viewModel.weeks.last?.volume.sessions[sport] ?? 0) Einheiten diese Woche"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } header: {
        Text("\(title) · Kilometer pro Woche")
      }
    }
    VO2Section(title: "VO2max Laufen (Garmin)", trend: viewModel.vo2Run)
    VO2Section(title: "VO2max Rad (Garmin)", trend: viewModel.vo2Bike)
    Section {
      Text(
        "Garmin berechnet VO2max nur nach geeigneten Einheiten (Lauf im Freien mit GPS, Rad mit Leistungsmesser). "
          + "Die aerobe Kopplung (HF-Pace-Drift) aus dem alten Dashboard folgt, sobald die App FIT-Dateien auswertet."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }
}

private struct VO2Section: View {
  let title: String
  let trend: MetricTrend?

  var body: some View {
    if let trend, !trend.points.isEmpty {
      Section(title) {
        HStack {
          Text("Aktuell")
          Spacer()
          Text(Formatters.number(trend.latest?.value, unit: "ml/kg/min", digits: 1)).monospacedDigit()
        }
        Chart(trend.points) { point in
          LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("VO2max", point.value))
          PointMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("VO2max", point.value))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 110)
      }
    }
  }
}

// MARK: - Herzfrequenz

private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

private struct HeartRateSections: View {
  let report: HeartRateZoneReport?

  var body: some View {
    if let report {
      Section {
        LabeledContent("HFmax", value: report.maxHeartRate.map { "\($0) bpm" } ?? "–")
        Text(report.maxHeartRateSource).font(.caption).foregroundStyle(.secondary)
        NavigationLink("Eigene Werte eintragen") { SeasonSettingsView() }
      } header: {
        Text("Herzfrequenz-Zonen")
      } footer: {
        Text("Coach-Zonen nach Friel in % der Schwellen-HF – sie hängen an der Schwelle, nicht an der HFmax.")
      }
      CoachZoneSection(title: "Laufen", zones: report.run)
      CoachZoneSection(title: "Rad", zones: report.bike)
      IntensitySection(distribution: report.distribution)
      ForEach(report.watch, id: \.sport) { watch in
        Section("Uhr-Zonen \(watch.sport.capitalized) (\(watch.methodText))") {
          ZoneBand(zones: watch.zones)
          Text(
            "Danach zählt die Uhr „Zeit in Zone“. Ändern: Garmin Connect › Benutzereinstellungen › Herzfrequenzzonen."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      Section("Hinweise") {
        ForEach(report.hints, id: \.self) { Text($0).font(.footnote) }
      }
    }
  }
}

private struct CoachZoneSection: View {
  let title: String
  let zones: CoachZones

  var body: some View {
    Section {
      if zones.zones.isEmpty {
        Text("Noch keine Schwelle bekannt – HFmax oder Schwelle unter Einstellungen eintragen.")
          .foregroundStyle(.secondary)
      } else {
        HStack {
          VStack(alignment: .leading) {
            Text(zones.source).font(.caption).foregroundStyle(zones.isApproximate ? .orange : .secondary)
          }
          Spacer()
          Text("\(zones.lactateThreshold ?? 0) bpm Schwelle").font(.headline).monospacedDigit()
        }
        ZoneBand(zones: zones.fiveZones)
        if let easy = zones.easyLimit {
          Text("Locker (Z1–2): bis \(easy) bpm").font(.subheadline)
        }
        DisclosureGroup("Alle Zonen") {
          ForEach(zones.zones, id: \.name) { zone in
            LabeledContent("\(zone.name) · \(zone.use)", value: zone.rangeText).font(.footnote)
          }
        }
      }
    } header: {
      Text("Coach-Zonen \(title)")
    }
  }
}

private struct ZoneBand: View {
  let zones: [HeartRateZone]

  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 2) {
        ForEach(Array(zones.enumerated()), id: \.offset) { index, _ in
          zoneColors[min(index, zoneColors.count - 1)].frame(height: 10)
        }
      }
      .clipShape(Capsule())
      HStack(spacing: 2) {
        ForEach(zones, id: \.name) { zone in
          VStack {
            Text(zone.name).font(.caption.bold())
            Text(zone.rangeText).font(.caption2).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
  }
}

private struct IntensitySection: View {
  let distribution: ZoneDistribution

  var body: some View {
    Section {
      if distribution.run == nil && distribution.bike == nil {
        Text("Keine Zonendaten der Uhr in den letzten \(distribution.weeks) Wochen.").foregroundStyle(.secondary)
      }
      ShareRow(title: "Laufen", share: distribution.run)
      ShareRow(title: "Rad", share: distribution.bike)
      if !distribution.perWeek.isEmpty {
        DisclosureGroup("Je Woche") {
          ForEach(distribution.perWeek, id: \.monday) { week in
            VStack(alignment: .leading, spacing: 4) {
              Text("Woche ab \(GermanFormat.date(week.monday))").font(.caption.bold())
              ShareRow(title: "Laufen", share: week.run)
              ShareRow(title: "Rad", share: week.bike)
            }
          }
        }
      }
    } header: {
      Text("Intensität (letzte \(distribution.weeks) Wochen)")
    } footer: {
      Text("Zeit in den Zonen der Uhr. Richtwert: ca. 80 % locker (Z1–2).")
    }
  }
}

private struct ShareRow: View {
  let title: String
  let share: IntensityShare?

  var body: some View {
    if let share {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(title).font(.subheadline)
          Spacer()
          Text(Formatters.duration(Double(share.minutes * 60))).font(.caption).foregroundStyle(.secondary)
        }
        GeometryReader { geometry in
          HStack(spacing: 2) {
            ForEach(Array(share.zonePercent.enumerated()), id: \.offset) { index, percent in
              zoneColors[index].frame(width: max(geometry.size.width * Double(percent) / 100 - 2, 0))
            }
          }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        Text("locker \(share.easyPercent) % · mittel \(share.moderatePercent) % · hart \(share.hardPercent) %")
          .font(.caption)
          .foregroundStyle(share.easyPercent >= 75 ? .green : .orange)
      }
    }
  }
}
