import Charts
import CoachCore
import MapKit
import SwiftData
import SwiftUI

/// Alle Details einer Garmin-Aktivität wie in Garmin Connect: Übersicht, Karte, Verlauf (Herzfrequenz, Tempo,
/// Höhe, Kadenz, Leistung), Runden und alle Kennzahlen. Fehlende Werte holt die Ansicht beim Öffnen von Garmin
/// (Aktivitätsdetails und FIT-Datei); die FIT-Datei bleibt im Cache, damit sie offline verfügbar ist.
struct ActivityDetailView: View {
  let record: ActivityRecord
  @Environment(AppModel.self) private var model
  @Environment(\.modelContext) private var context
  @State private var activity: GarminActivity?
  @State private var fit: FitActivity?
  @State private var loading = false
  @State private var problem: String?

  private var current: GarminActivity? { activity ?? record.activity }

  var body: some View {
    List {
      if let current {
        header(current)
        if let fit {
          let route = ActivityDetails.route(fit)
          if route.count > 1 { mapSection(route) }
          let samples = ActivityDetails.samples(fit, sport: current.sport)
          chartsSection(samples, sport: current.sport, byDistance: fit.records.contains { ($0.distance ?? 0) > 0 })
          if fit.laps.count > 1 { lapsSection(fit.laps, sport: current.sport) }
        } else if loading {
          Section { ProgressView("Verlauf wird geladen …") }
        }
        ForEach(ActivityDetails.sections(current).dropFirst()) { section in
          Section(section.title) {
            ForEach(section.rows) { row in
              LabeledContent(row.label, value: row.value).monospacedDigit()
            }
          }
        }
        MissingDataSection(notes: ActivityFeed.missing(current))
        if let problem {
          Section {
            Text(problem).font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle(current?.name ?? "Aktivität")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private func header(_ activity: GarminActivity) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 4) {
        if let day = activity.day {
          Text(
            [
              Formatters.day(day), activity.startLocal.map { String($0.dropFirst(11).prefix(5)) + " Uhr" },
              activity.locationName,
            ]
            .compactMap { $0 }.joined(separator: " · ")
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
        HStack(spacing: 6) {
          FeedBadges(sources: [ActivitySource.of(activity.id)], intensity: SessionKind.of(activity))
          if let effort = model.settings.efforts[String(activity.id)] {
            Text("Anstrengung \(effort)/10").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
          }
        }
      }
      let overview = ActivityDetails.sections(activity).first?.rows ?? []
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], alignment: .leading, spacing: 12) {
        ForEach(overview) { row in
          VStack(alignment: .leading, spacing: 2) {
            Text(row.value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(row.label).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .padding(.vertical, 4)
      if let shares = ActivityFeed.zoneShares(activity) {
        ZoneShareBar(shares: shares).padding(.vertical, 2)
      }
    }
  }

  private func mapSection(_ route: [(latitude: Double, longitude: Double)]) -> some View {
    let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    return Section {
      Map(interactionModes: [.zoom, .pan]) {
        MapPolyline(coordinates: coordinates).stroke(Color.orange, lineWidth: 4)
        Marker("Start", systemImage: "flag", coordinate: coordinates[0]).tint(.green)
        Marker("Ziel", systemImage: "flag.checkered", coordinate: coordinates[coordinates.count - 1]).tint(.red)
      }
      .frame(height: 240)
      .listRowInsets(EdgeInsets())
      .accessibilityLabel("Karte der Strecke")
    }
  }

  private struct ChartPoint: Identifiable {
    let x: Double
    let y: Double
    var id: Double { x }
  }

  private struct Series: Identifiable {
    let title: String
    let color: Color
    let points: [ChartPoint]
    /// Pace: kleiner ist schneller, daher umgekehrte Achse.
    let reversed: Bool
    var id: String { title }
  }

  /// Diagrammreihen aus dem FIT-Verlauf; nur Reihen mit mindestens zwei Punkten.
  private func makeSeries(_ samples: [ActivityDetails.Sample], sport: GarminActivity.Sport) -> [Series] {
    let paceTitle = sport == .run ? "Pace (min/km)" : sport == .swim ? "Pace (min/100 m)" : "Geschwindigkeit (km/h)"
    func points(_ value: (ActivityDetails.Sample) -> Double?) -> [ChartPoint] {
      samples.compactMap { sample in value(sample).map { ChartPoint(x: sample.x, y: $0) } }
    }
    return [
      Series(title: "Herzfrequenz (bpm)", color: .red, points: points(\.heartRate), reversed: false),
      Series(title: paceTitle, color: .blue, points: points(\.pace), reversed: sport == .run || sport == .swim),
      Series(title: "Höhe (m)", color: .green, points: points(\.altitude), reversed: false),
      Series(
        title: sport == .bike ? "Trittfrequenz (U/min)" : "Kadenz (spm)", color: .purple, points: points(\.cadence),
        reversed: false),
      Series(title: "Leistung (W)", color: .orange, points: points(\.power), reversed: false),
    ].filter { $0.points.count > 1 }
  }

  @ViewBuilder
  private func chartsSection(
    _ samples: [ActivityDetails.Sample], sport: GarminActivity.Sport, byDistance: Bool
  ) -> some View {
    let xLabel = byDistance ? "km" : "min"
    let series = makeSeries(samples, sport: sport)
    if !series.isEmpty {
      Section("Verlauf") {
        ForEach(series) { item in
          VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.subheadline.weight(.semibold))
            Chart(item.points) { point in
              LineMark(x: .value(xLabel, point.x), y: .value(item.title, point.y))
                .foregroundStyle(item.color)
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: item.reversed))
            .chartYAxis {
              AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                  if let number = value.as(Double.self) {
                    Text(item.reversed ? clock(number) : GermanFormat.decimal(number))
                  }
                }
              }
            }
            .chartXAxisLabel(xLabel)
            .frame(height: 140)
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private func lapsSection(_ laps: [FitLap], sport: GarminActivity.Sport) -> some View {
    Section("Runden") {
      ScrollView(.horizontal) {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
          GridRow {
            Text("#")
            Text("Distanz")
            Text("Zeit")
            Text(sport == .run || sport == .swim ? "Pace" : "km/h")
            Text("Ø HF")
            Text("Max HF")
            Text("Anstieg")
            Text("Kadenz")
            Text("Leistung")
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          ForEach(Array(laps.enumerated()), id: \.offset) { index, lap in
            GridRow {
              Text("\(index + 1)")
              Text(lap.distanceMeters.map { ActivityDetails.distance($0, sport: sport) } ?? "–")
              Text(lap.timerSeconds.map(ActivityDetails.duration) ?? "–")
              Text(lapSpeed(lap).map { ActivityDetails.speed($0, sport: sport) } ?? "–")
              Text(lap.averageHeartRate.map { "\(Int($0))" } ?? "–")
              Text(lap.maxHeartRate.map { "\(Int($0))" } ?? "–")
              Text(lap.ascentMeters.map { "\(Int($0)) m" } ?? "–")
              Text(lap.averageCadence.map { "\(Int(sport == .run ? $0 * 2 : $0))" } ?? "–")
              Text(lap.averagePower.map { "\(Int($0)) W" } ?? "–")
            }
            .font(.caption)
            .monospacedDigit()
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func lapSpeed(_ lap: FitLap) -> Double? {
    if let speed = lap.averageSpeed, speed > 0 { return speed }
    guard let distance = lap.distanceMeters, let seconds = lap.timerSeconds, seconds > 0 else { return nil }
    return distance / seconds
  }

  private func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  // MARK: - Laden

  private static func cacheURL(_ id: Int64) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("fit", isDirectory: true).appendingPathComponent("\(id).fit")
  }

  private func load() async {
    guard let base = record.activity else { return }
    loading = true
    defer { loading = false }
    // Aus dem Cache sofort anzeigen.
    if let url = Self.cacheURL(base.id), let data = try? Data(contentsOf: url) {
      fit = try? await GarminSyncService.decodeFit(data)
    }
    // Workouts aus Apple Health (negative ID) haben keine Garmin-Details.
    guard model.garmin.isConfigured, !model.isDemo, base.id >= 0 else { return }
    if let json = try? await model.garmin.json(.activity(id: base.id)) {
      let detailed = GarminActivityParser.detail(json, base: base)
      activity = detailed
      if detailed != base {
        record.update(detailed)
        try? context.save()
      }
    }
    guard fit == nil else { return }
    do {
      let data = try await model.garmin.data(.activityFile(id: base.id))
      fit = try await GarminSyncService.decodeFit(data)
      if let url = Self.cacheURL(base.id) {
        try? FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
      }
    } catch {
      problem =
        "Der Verlauf (FIT-Datei) konnte gerade nicht geladen werden. Die Übersicht stammt aus der "
        + "Aktivitätsliste."
    }
  }
}

/// Zeile einer Aktivität: Symbol, Name, Datum und Kernwerte.
struct ActivitySummaryRow: View {
  let activity: GarminActivity

  var body: some View {
    HStack(spacing: 12) {
      SportIcon(symbol: symbol, color: color)
      VStack(alignment: .leading, spacing: 2) {
        Text(activity.name ?? activity.typeKey ?? "Aktivität").font(.subheadline.weight(.semibold))
        HStack(spacing: 10) {
          if let day = activity.day { Text(Formatters.day(day)) }
          if let seconds = activity.durationSeconds { Text(ActivityDetails.duration(seconds)) }
          if let meters = activity.distanceMeters, meters > 0 {
            Text(ActivityDetails.distance(meters, sport: activity.sport))
          }
          if let load = activity.trainingLoad { Text("Belastung \(Int(load.rounded()))") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var symbol: String {
    switch activity.sport {
    case .run: "figure.run"
    case .bike: "figure.outdoor.cycle"
    case .swim: "figure.pool.swim"
    case .strength: "dumbbell.fill"
    case .other: "figure.mixed.cardio"
    }
  }

  private var color: Color {
    switch activity.sport {
    case .run: .green
    case .bike: .orange
    case .swim: .blue
    case .strength: .purple
    case .other: .teal
    }
  }
}
