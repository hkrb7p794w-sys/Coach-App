import Charts
import CoachCore
import SwiftUI

/// Trends auf einen Blick: Minuten je Sportart und Woche (gestapelt), Form-Kurve mit „heute“ und die aerobe Effizienz
/// lockerer Läufe. Die Verläufe lassen sich wie im Gym zoomen und verschieben.
struct TrendsPage: View {
  let activities: [GarminActivity]
  let gym: [ActivityFeed.GymItem]
  @State private var weeks = 12

  var body: some View {
    let today = CalendarDay(date: .now)
    let minutes = TrainingTrends.weeklyMinutes(activities: activities, gym: gym, today: today, weeks: weeks)
    let form = FitnessForm.series(activities: activities, today: today)
    let efficiency = TrainingTrends.aerobicEfficiency(activities: activities)
    List {
      Section {
        Picker("Wochen", selection: $weeks) {
          Text("12 Wochen").tag(12)
          Text("26 Wochen").tag(26)
          Text("1 Jahr").tag(52)
        }
        .pickerStyle(.segmented)
        if minutes.isEmpty {
          Text("Noch keine Aktivitäten in diesem Zeitraum.").foregroundStyle(.secondary)
        } else {
          let sports = TrainingSport.allCases.filter { sport in minutes.contains { $0.sport == sport } }
          Chart(minutes) { entry in
            BarMark(
              x: .value("Woche", entry.monday.localDate, unit: .weekOfYear), y: .value("Minuten", entry.minutes))
              .foregroundStyle(by: .value("Sportart", entry.sport.label))
          }
          .chartForegroundStyleScale(domain: sports.map(\.label), range: sports.map(\.color))
          .frame(height: 200)
          .accessibilityLabel("Trainingsminuten je Woche und Sportart, letzte \(weeks) Wochen")
        }
      } header: {
        Text("Minuten je Woche")
      } footer: {
        Text("Alle Quellen, Gym-Einheiten der App eingerechnet; doppelte Aufzeichnungen zählen einmal.")
      }

      Section {
        if FitnessForm.isReliable(form) {
          ZoomableTrendChart(
            points: form.map { ($0.day.localDate, $0.form) }, unit: "Form", includesZero: true, bars: true,
            marksToday: true)
        } else {
          Text("Die Form-Kurve braucht Trainingsbelastung der Uhr aus mindestens \(FitnessForm.warmUpDays) Tagen.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Form")
      } footer: {
        Text(
          "Fitness minus Ermüdung (Belastung über 42 bzw. 7 Tage). Unter −30 % der Fitness rät die Tagesampel zu "
            + "lockerem Training.")
      }

      Section {
        if efficiency.count >= 2 {
          ZoomableTrendChart(
            points: efficiency.map { ($0.day.localDate, $0.value) }, unit: "m je Schlag", minimumPadding: 0.02)
        } else {
          Text("Dafür braucht es mindestens zwei lockere Läufe ab 20 Minuten mit Herzfrequenz und Strecke.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Aerobe Effizienz (lockere Läufe)")
      } footer: {
        Text(
          "Meter je Herzschlag: Tempo geteilt durch die mittlere Herzfrequenz. Steigt der Wert bei lockeren Läufen, "
            + "wird die Grundlage besser. Hitze, Hügel und Müdigkeit drücken ihn – auf den Trend achten, nicht auf "
            + "einzelne Läufe.")
      }
    }
    .navigationTitle("Trends")
  }
}

/// Verlauf mit Zeitraum-Knöpfen, Zoom mit zwei Fingern und seitlichem Verschieben (wie `ExerciseHistoryCharts`).
struct ZoomableTrendChart: View {
  let points: [(date: Date, value: Double)]
  let unit: String
  var includesZero = false
  var minimumPadding: Double = 1
  var bars = false
  /// Linie bei heute.
  var marksToday = false
  @State private var days: Double = 91
  @State private var zoomBase: Double?
  @State private var start = Date.now
  @State private var prepared = false

  private var dates: [Date] { points.map(\.date) + (marksToday ? [Date.now] : []) }
  private var span: Double { ChartZoom.spanDays(dates) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Zeitraum", selection: presetBinding) {
        ForEach(ChartZoom.presets) { preset in Text(preset.label).tag(preset.label) }
        if presetLabel == nil { Text("Eigener").tag("") }
      }
      .pickerStyle(.segmented)
      chart.frame(height: 180)
      Text("Mit zwei Fingern zoomen, seitlich wischen zum Verschieben.").font(.caption2).foregroundStyle(.secondary)
    }
    .onAppear {
      guard !prepared else { return }
      prepared = true
      days = ChartZoom.initialDays(span: span)
      start = ChartZoom.initialStart(dates, days: days)
    }
  }

  private var chart: some View {
    let showsPoints = ChartZoom.showsPoints(days: days, count: points.count, span: span)
    return Chart {
      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        if bars {
          BarMark(x: .value("Tag", point.date, unit: .day), y: .value(unit, point.value))
            .foregroundStyle(point.value >= 0 ? Color.green.opacity(0.6) : Color.orange.opacity(0.6))
        } else {
          LineMark(x: .value("Tag", point.date, unit: .day), y: .value(unit, point.value))
          if showsPoints {
            PointMark(x: .value("Tag", point.date, unit: .day), y: .value(unit, point.value))
          }
        }
      }
      if marksToday {
        RuleMark(x: .value("Heute", Date.now, unit: .day))
          .foregroundStyle(Color.accentColor)
          .annotation(position: .top, alignment: .leading) { Text("heute").font(.caption2) }
      }
    }
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: days * 86_400)
    .chartScrollPosition(x: $start)
    .chartYScale(
      domain: ChartZoom.yDomain(
        points, from: start, days: days, includesZero: includesZero, minimumPadding: minimumPadding)
    )
    .simultaneousGesture(
      MagnifyGesture()
        .onChanged { value in
          let base = zoomBase ?? days
          if zoomBase == nil { zoomBase = days }
          let center = start.addingTimeInterval(days * 43_200)
          let newDays = ChartZoom.clamp(base / max(value.magnification, 0.1), span: span)
          start = center.addingTimeInterval(-newDays * 43_200)
          days = newDays
        }
        .onEnded { _ in zoomBase = nil })
    .accessibilityLabel("Verlauf \(unit)")
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
}
