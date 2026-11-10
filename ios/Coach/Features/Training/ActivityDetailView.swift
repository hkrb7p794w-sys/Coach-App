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
  /// Gespeicherter Bericht vom Abruf: Runden, Splits und Verlauf ohne erneutes Laden.
  @State private var report: ActivityReport?
  @State private var loading = false
  @State private var problem: String?
  @State private var sharing = false

  private var current: GarminActivity? { activity ?? record.activity }

  var body: some View {
    List {
      if let current {
        header(current)
        if current.sport == .strength {
          LinkedGymSection(activity: current)
        }
        if let report { findingsSection(report) }
        if let fit {
          let route = ActivityDetails.route(fit)
          if route.count > 1 { mapSection(route) }
          let samples = ActivityDetails.samples(fit, sport: current.sport)
          chartsSection(samples, sport: current.sport, byDistance: fit.records.contains { ($0.distance ?? 0) > 0 })
          if fit.laps.count > 1 { lapsSection(fit.laps, sport: current.sport) }
        } else if let report {
          // Datei der Uhr nicht (mehr) da: Verlauf und Runden aus dem gespeicherten Bericht.
          chartsSection(report.samples, sport: current.sport, byDistance: report.byDistance)
          if report.laps.count > 1 { lapsSection(report.laps, sport: current.sport) }
        } else if loading {
          Section { ProgressView("Verlauf wird geladen …") }
        }
        if let report, report.splits.count > 1 { splitsSection(report, sport: current.sport) }
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
    .toolbar {
      if current != nil {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Mit Freunden teilen", systemImage: "person.2") { sharing = true }
        }
      }
    }
    .sheet(isPresented: $sharing) {
      if let current { ShareWithFriendsSheet(content: .workout(WorkoutShare.activity(current))) }
    }
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

  /// Aussagen der Regeln zu dieser Einheit (Tempo-Einteilung, Puls-Drift, Intervalle, Standzeit).
  private func findingsSection(_ report: ActivityReport) -> some View {
    let findings = ActivityFindings.findings(report)
    return Section {
      if findings.isEmpty {
        Text("Für diese Einheit gibt es keine besonderen Auffälligkeiten.").foregroundStyle(.secondary)
      }
      ForEach(findings) { finding in
        Label {
          Text(finding.text).font(.subheadline)
        } icon: {
          switch finding.tone {
          case .good: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
          case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          case .neutral: Image(systemName: "info.circle").foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      Text("Auswertung")
    } footer: {
      Text("Aus der Aufzeichnung der Uhr berechnet – feste Regeln, keine KI.")
    }
  }

  /// Abschnitte fester Länge (Laufen 1 km, Rad 5 km, Schwimmen 100 m) mit Balken für das Tempo.
  private func splitsSection(_ report: ActivityReport, sport: GarminActivity.Sport) -> some View {
    let fastest = report.splits.map(\.speed).max() ?? 1
    return Section(report.splitMeters == 1_000 ? "Kilometer" : ActivityFindings.splitTitle(report.splitMeters)) {
      ForEach(report.splits) { split in
        HStack(spacing: 8) {
          Text("\(split.index)").frame(width: 24, alignment: .trailing).foregroundStyle(.secondary)
          Text(ActivityDetails.speed(split.speed, sport: sport)).frame(width: 84, alignment: .leading)
          GeometryReader { proxy in
            Capsule().fill(.tint.opacity(0.7))
              .frame(width: max(4, proxy.size.width * (fastest > 0 ? split.speed / fastest : 0)))
          }
          .frame(height: 8)
          Text(split.averageHeartRate.map { "\(Int($0.rounded())) ♥" } ?? "").frame(width: 56, alignment: .trailing)
        }
        .font(.caption)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "Abschnitt \(split.index): \(ActivityDetails.speed(split.speed, sport: sport))"
            + (split.averageHeartRate.map { ", Puls \(Int($0.rounded()))" } ?? ""))
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

  private func load() async {
    guard let base = record.activity else { return }
    loading = true
    defer { loading = false }
    // Bericht vom letzten Abruf und Datei aus dem Cache sofort anzeigen.
    report = model.sync.reportStore.report(base.id)
    if let data = ActivityReportStore.cachedFile(base.id) {
      fit = try? await GarminSyncService.decodeFit(data)
      storeReport(base)
    }
    // Workouts aus Apple Health (negative ID): Verlauf und Strecke direkt aus HealthKit.
    if base.id < 0 {
      if !model.isDemo, let recording = await model.health.recording(for: base.id, around: base.day) {
        fit = recording
        storeReport(base)
      }
      return
    }
    guard model.garmin.isConfigured, !model.isDemo else { return }
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
      ActivityReportStore.cache(data, id: base.id)
      storeReport(activity ?? base)
    } catch {
      problem =
        "Der Verlauf (FIT-Datei) konnte gerade nicht geladen werden. Die Übersicht stammt aus der "
        + "Aktivitätsliste."
    }
  }

  /// Bericht aus der geladenen Datei erzeugen und speichern (auch für ältere Aktivitäten außerhalb des Abrufs).
  private func storeReport(_ activity: GarminActivity) {
    guard let fit, report?.version != ActivityReport.version else { return }
    let built = ActivityReportBuilder.build(activity, fit: fit)
    report = built
    model.sync.reportStore.store(built, today: CalendarDay(date: .now))
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

/// Krafttraining von Garmin plus Einheit der App: dieselbe Einheit, also beides an einem Ort – Kalorien und Puls
/// der Uhr oben, Sätze der App hier. Zuordnung über die gespeicherte Verbindung, sonst über die Startzeit.
private struct LinkedGymSection: View {
  let activity: GarminActivity
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var records: [GymSessionRecord]

  var body: some View {
    let pairs = records.prefix(60).compactMap { record in record.session.map { (record, $0) } }
    let linked = pairs.first { $0.1.garmin?.activityID == activity.id }
    let byTime = pairs.first { pair in
      guard pair.1.garmin?.activityID == nil, let start = ActivityFeed.start(activity, timeZone: .current) else {
        return false
      }
      return abs(pair.1.start.timeIntervalSince(start)) <= GarminStrengthSync.matchWindow && pair.1.day == activity.day
    }
    if let pair = linked ?? byTime {
      let (record, session) = pair
      Section {
        ForEach(session.exercises.filter { !$0.loggedSets.isEmpty }) { exercise in
          VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name).font(.subheadline.bold())
            Text(
              exercise.loggedSets.map { set in
                set.weightKg > 0 ? "\(GermanFormat.number(set.weightKg))×\(set.reps)" : "\(set.reps)"
              }.joined(separator: " · ")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
          }
        }
        NavigationLink("Einheit in der App öffnen") { SessionDetailView(record: record, session: session) }
      } header: {
        Text("Sätze aus der App · \(session.title)")
      } footer: {
        Text(
          session.garmin?.status == .enriched
            ? "Die Sätze stehen auch in Garmin Connect in dieser Aktivität."
            : "Dieselbe Einheit – Kalorien und Puls kommen von der Uhr, die Sätze aus der App. Es zählt nur einmal.")
      }
    }
  }
}
