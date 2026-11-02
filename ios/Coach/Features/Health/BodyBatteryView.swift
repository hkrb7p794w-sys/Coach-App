import Charts
import CoachCore
import SwiftData
import SwiftUI

/// Body Battery: aktueller Stand, Tagesverlauf, Verlauf über 30 Tage und Zusammenhang mit Schlaf und Stress.
struct BodyBatteryView: View {
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]

  var body: some View {
    let today = CalendarDay(date: .now)
    let summary = BodyBatteryAnalysis.summary(days: days.compactMap(\.metrics), today: today)
    List {
      if !summary.hasData {
        Section {
          ContentUnavailableView(
            "Keine Body Battery", systemImage: "battery.0percent",
            description: Text(
              "Body Battery gibt es nur von Garmin-Uhren. Melde dich in den Einstellungen mit dem Garmin-Konto an "
                + "und ziehe nach unten zum Abrufen. Apple Health hat keinen vergleichbaren Wert."))
        }
      } else {
        Section {
          BodyBatteryHeader(summary: summary, today: today)
        }
        if summary.curve.count >= 2 {
          Section {
            BodyBatteryCurveChart(curve: summary.curve)
          } header: {
            Text(summary.currentDay == today ? "Heute" : "Gestern")
          } footer: {
            Text("Lädt im Schlaf und in Ruhe, sinkt bei Belastung und Stress.")
          }
        }
        if summary.history.count >= 2 {
          Section {
            BodyBatteryHistoryChart(history: summary.history, norm: summary.wakeNorm)
          } header: {
            Text("Letzte 30 Tage")
          } footer: {
            Text(
              "Balken: Tiefst- bis Höchstwert des Tages. Punkt: Stand beim Aufwachen. "
                + (summary.wakeNorm == nil
                  ? "Dein üblicher Bereich erscheint ab 7 Tagen mit Aufwachwert."
                  : "Grau hinterlegt: dein üblicher Aufwachwert."))
          }
        }
        Section {
          if summary.relations.isEmpty {
            Text(
              "Für einen Vergleich braucht es je mindestens 3 Tage mit langen und kurzen Nächten bzw. viel "
                + "und wenig Stress."
            )
            .foregroundStyle(.secondary)
          }
          ForEach(summary.relations) { relation in
            Label(relation.text, systemImage: relation.id == "sleep" ? "bed.double" : "waveform.path.ecg")
          }
        } header: {
          Text("Schlaf und Stress")
        } footer: {
          Text("Vergleich deiner eigenen Tage, keine Ursache. Werte der Uhr (Garmin).")
        }
      }
    }
    .navigationTitle("Body Battery")
  }
}

/// Kopf: aktueller Stand mit Einordnung, Aufwachwert gegenüber dem eigenen Bereich, Laden und Verbrauch.
struct BodyBatteryHeader: View {
  let summary: BodyBatteryAnalysis.Summary
  let today: CalendarDay

  private var latestDay: BodyBatteryAnalysis.Day? { summary.history.last }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      BatteryGauge(value: summary.current)
      VStack(alignment: .leading, spacing: 6) {
        if let current = summary.current {
          Text("\(Int(current)) · \(BodyBatteryAnalysis.band(current))").font(.title2.weight(.semibold))
          if let minute = summary.currentMinute {
            Text(
              "Stand \(summary.currentDay == today ? "heute" : "gestern") \(SleepCoach.clock(minute)) Uhr"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text("Aktueller Stand fehlt").font(.headline)
        }
        if let wake = summary.wake {
          Text("Beim Aufwachen \(Int(wake))" + normText(wake)).font(.subheadline)
        } else {
          Text("Aufwachwert heute fehlt").font(.subheadline).foregroundStyle(.secondary)
        }
        if let day = latestDay, day.charged != nil || day.drained != nil {
          Text(
            "Geladen +\(day.charged.map { String(Int($0)) } ?? "–") · verbraucht −"
              + (day.drained.map { String(Int($0)) } ?? "–")
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func normText(_ wake: Double) -> String {
    guard let norm = summary.wakeNorm else { return "" }
    switch norm.position(wake) {
    case .below: return " – unter deinem üblichen Bereich (\(Int(norm.low))–\(Int(norm.high)))"
    case .within: return " – in deinem üblichen Bereich"
    case .above: return " – über deinem üblichen Bereich"
    }
  }
}

/// Batteriesymbol mit Füllstand.
struct BatteryGauge: View {
  let value: Double?

  var body: some View {
    Gauge(value: min(max(value ?? 0, 0), 100), in: 0...100) {
      Image(systemName: "bolt.fill")
    } currentValueLabel: {
      Text(value.map { String(Int($0)) } ?? "–").monospacedDigit()
    }
    .gaugeStyle(.accessoryCircular)
    .tint(Gradient(colors: [.red, .orange, .yellow, .green, .blue]))
    .scaleEffect(1.3)
    .frame(width: 64, height: 64)
    .accessibilityLabel("Body Battery \(value.map { String(Int($0)) } ?? "unbekannt")")
  }
}

/// Tagesverlauf (Viertelstunden).
struct BodyBatteryCurveChart: View {
  let curve: [BodyBatterySample]

  var body: some View {
    Chart(curve, id: \.minute) { sample in
      AreaMark(x: .value("Uhrzeit", Double(sample.minute) / 60), y: .value("Body Battery", sample.value))
        .foregroundStyle(
          .linearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.05)], startPoint: .top, endPoint: .bottom)
        )
        .interpolationMethod(.monotone)
      LineMark(x: .value("Uhrzeit", Double(sample.minute) / 60), y: .value("Body Battery", sample.value))
        .foregroundStyle(.blue)
        .interpolationMethod(.monotone)
    }
    .chartXScale(domain: 0...24)
    .chartYScale(domain: 0...100)
    .chartXAxis {
      AxisMarks(values: [0, 6, 12, 18, 24]) { value in
        AxisGridLine()
        AxisValueLabel { Text("\(value.as(Int.self) ?? 0) Uhr") }
      }
    }
    .frame(height: 160)
    .accessibilityLabel("Body-Battery-Verlauf von heute")
  }
}

/// 30 Tage: Spanne je Tag und Aufwachwert, dazu der eigene übliche Bereich.
struct BodyBatteryHistoryChart: View {
  let history: [BodyBatteryAnalysis.Day]
  let norm: PersonalNorm?

  var body: some View {
    Chart {
      if let norm {
        RectangleMark(yStart: .value("von", norm.low), yEnd: .value("bis", norm.high))
          .foregroundStyle(.gray.opacity(0.15))
      }
      ForEach(history) { day in
        if let low = day.low, let high = day.high {
          BarMark(
            x: .value("Tag", day.day.localDate, unit: .day), yStart: .value("Tief", low), yEnd: .value("Hoch", high)
          )
          .foregroundStyle(.blue.opacity(0.35))
        }
        if let wake = day.wake {
          PointMark(x: .value("Tag", day.day.localDate, unit: .day), y: .value("Aufwachen", wake))
            .foregroundStyle(.blue)
            .symbolSize(20)
        }
      }
    }
    .chartYScale(domain: 0...100)
    .frame(height: 170)
  }
}
