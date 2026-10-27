import Charts
import CoachCore
import SwiftUI

/// Verlauf einer Übung: 1RM bzw. Höchstgewicht und die bewegte Last je Einheit. Zeitraum per Knopf, mit zwei
/// Fingern zoomen, seitlich wischen zum Verschieben; die Y-Achse passt sich dem sichtbaren Ausschnitt an. Beide
/// Diagramme zeigen denselben Ausschnitt.
struct ExerciseHistoryCharts: View {
  let history: [GymStats.Point]
  @State private var showOneRepMax = true
  @State private var days: Double = 91
  @State private var zoomBase: Double?
  @State private var start = Date.now
  @State private var prepared = false

  private var dates: [Date] { history.map(\.day.localDate) }
  private var span: Double { ChartZoom.spanDays(dates) }

  private var strengthPoints: [(date: Date, value: Double)] {
    history.map { ($0.day.localDate, showOneRepMax ? ($0.oneRepMaxKg ?? $0.topWeightKg) : $0.topWeightKg) }
  }

  private var volumePoints: [(date: Date, value: Double)] {
    history.map { ($0.day.localDate, $0.volumeKg) }
  }

  var body: some View {
    Section {
      Picker("Zeitraum", selection: presetBinding) {
        ForEach(ChartZoom.presets) { preset in Text(preset.label).tag(preset.label) }
        if presetLabel == nil { Text("Eigener").tag("") }
      }
      .pickerStyle(.segmented)

      Picker("Anzeige", selection: $showOneRepMax) {
        Text("Geschätztes 1RM").tag(true)
        Text("Höchstgewicht").tag(false)
      }
      .pickerStyle(.segmented)
      chart(strengthPoints, unit: "kg", includesZero: false, bars: false)
        .frame(height: 180)

      VStack(alignment: .leading, spacing: 6) {
        Text("Bewegte Last je Einheit").font(.subheadline.weight(.semibold))
        chart(volumePoints, unit: "kg", includesZero: true, bars: true)
          .frame(height: 140)
      }
    } header: {
      Text("Verlauf")
    } footer: {
      Text(
        "\(rangeText) · Mit zwei Fingern zoomen, seitlich wischen zum Verschieben. 1RM geschätzt nach Epley aus "
          + "Sätzen mit bis zu 12 Wiederholungen; bewegte Last = Gewicht × Wiederholungen aller Sätze.")
    }
    .onAppear {
      guard !prepared else { return }
      prepared = true
      days = ChartZoom.initialDays(span: span)
      start = ChartZoom.initialStart(dates, days: days)
    }
  }

  @ViewBuilder
  private func chart(
    _ points: [(date: Date, value: Double)], unit: String, includesZero: Bool, bars: Bool
  ) -> some View {
    let showsPoints = ChartZoom.showsPoints(days: days, count: points.count, span: span)
    Chart(Array(points.enumerated()), id: \.offset) { _, point in
      if bars {
        BarMark(x: .value("Tag", point.date, unit: .day), y: .value(unit, point.value))
          .foregroundStyle(Color.accentColor.opacity(0.7))
      } else {
        LineMark(x: .value("Tag", point.date, unit: .day), y: .value(unit, point.value))
        if showsPoints {
          PointMark(x: .value("Tag", point.date, unit: .day), y: .value(unit, point.value))
        }
      }
    }
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: days * 86_400)
    .chartScrollPosition(x: $start)
    .chartYScale(domain: ChartZoom.yDomain(points, from: start, days: days, includesZero: includesZero))
    .simultaneousGesture(
      MagnifyGesture()
        .onChanged { value in
          let base = zoomBase ?? days
          if zoomBase == nil { zoomBase = days }
          let center = start.addingTimeInterval(days * 43_200)
          let newDays = ChartZoom.clamp(base / max(value.magnification, 0.1), span: span)
          // Um die Mitte zoomen, damit der betrachtete Zeitraum im Bild bleibt.
          start = center.addingTimeInterval(-newDays * 43_200)
          days = newDays
        }
        .onEnded { _ in zoomBase = nil })
  }

  private var presetLabel: String? {
    ChartZoom.presets.first { preset in
      abs((preset.days.map { ChartZoom.clamp($0, span: span) } ?? span) - days) < 0.5
    }?.label
  }

  private var presetBinding: Binding<String> {
    Binding(
      get: { presetLabel ?? "" },
      set: { label in
        guard let preset = ChartZoom.presets.first(where: { $0.label == label }) else { return }
        withAnimation {
          days = ChartZoom.clamp(preset.days ?? span, span: span)
          start = ChartZoom.initialStart(dates, days: days)
        }
      })
  }

  private var rangeText: String {
    let end = start.addingTimeInterval(days * 86_400)
    let format = Date.FormatStyle().day(.twoDigits).month(.twoDigits).year(.twoDigits)
    return "\(start.formatted(format)) – \(end.formatted(format))"
  }
}
