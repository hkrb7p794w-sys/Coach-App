import CoachCore
import SwiftData
import SwiftUI

/// Phase 2: zeigt die abgerufenen Garmin-Daten. Tagesempfehlung und Wochen-Soll/Ist folgen in Phase 3.
struct TodayView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]

  var body: some View {
    NavigationStack {
      List {
        SyncStatusSection()

        if !model.garmin.hasKey {
          Section {
            Text("Hinterlege in den Einstellungen deinen Garmin Personal API Key, um Daten abzurufen.")
              .foregroundStyle(.secondary)
          }
        }

        if !days.isEmpty {
          Section("Erholung") {
            ForEach(days.prefix(14)) { record in
              if let metrics = record.metrics {
                DayRow(metrics: metrics)
              }
            }
          }
        }

        if !activities.isEmpty {
          Section("Aktivitäten") {
            ForEach(activities.prefix(10)) { record in
              if let activity = record.activity {
                ActivityRow(activity: activity)
              }
            }
          }
        }
      }
      .navigationTitle("Heute")
      .refreshable { await model.syncNow() }
    }
  }
}

struct SyncStatusSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Section {
      if model.isSyncing {
        HStack {
          ProgressView()
          Text("Garmin-Daten werden abgerufen …")
        }
      } else if let lastSync = model.lastSync {
        LabeledContent("Letzter Abruf") {
          Text(lastSync, format: .relative(presentation: .named))
        }
      }
      if let error = model.lastError {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .font(.footnote)
      }
      if let report = model.lastReport, !report.errors.isEmpty {
        Text("\(report.errors.count) Endpunkte ohne Daten – Details unter Einstellungen › Garmin-Diagnose.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct DayRow: View {
  let metrics: DailyMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(Formatters.day(metrics.day)).font(.headline)
        Spacer()
        if let status = metrics.hrvStatus {
          Text(Formatters.hrvStatus(status))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Formatters.hrvColor(status).opacity(0.2), in: Capsule())
        }
      }
      HStack(spacing: 12) {
        Metric(symbol: "heart", value: Formatters.number(metrics.restingHeartRate, unit: "bpm"))
        Metric(symbol: "waveform.path.ecg", value: Formatters.number(metrics.hrvLastNightAverage, unit: "ms"))
        Metric(symbol: "bed.double", value: Formatters.number(metrics.sleepHours, unit: "h", digits: 1))
        Metric(symbol: "battery.75percent", value: Formatters.number(metrics.bodyBatteryHigh, unit: ""))
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
  }
}

private struct Metric: View {
  let symbol: String
  let value: String

  var body: some View {
    Label(value, systemImage: symbol)
      .labelStyle(.titleAndIcon)
      .lineLimit(1)
  }
}

private struct ActivityRow: View {
  let activity: GarminActivity

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(activity.name ?? activity.typeKey ?? "Aktivität").font(.headline)
      HStack(spacing: 12) {
        if let day = activity.day { Text(Formatters.day(day)) }
        if let seconds = activity.durationSeconds { Text(Formatters.duration(seconds)) }
        if let meters = activity.distanceMeters, meters > 0 {
          Text(Formatters.number(meters / 1000, unit: "km", digits: 1))
        }
        if let load = activity.trainingLoad { Text("Last \(Int(load.rounded()))") }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
  }
}

enum Formatters {
  static func number(_ value: Double?, unit: String, digits: Int = 0) -> String {
    guard let value else { return "–" }
    let text = value.formatted(.number.precision(.fractionLength(digits)))
    return unit.isEmpty ? text : "\(text) \(unit)"
  }

  static func day(_ day: CalendarDay) -> String {
    day.referenceDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  static func duration(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
  }

  static func hrvStatus(_ status: String) -> String {
    switch status {
    case "BALANCED": "ausgeglichen"
    case "UNBALANCED": "unausgeglichen"
    case "LOW": "niedrig"
    case "POOR": "schlecht"
    default: "kein Status"
    }
  }

  static func hrvColor(_ status: String) -> Color {
    switch status {
    case "BALANCED": .green
    case "UNBALANCED": .orange
    case "LOW", "POOR": .red
    default: .gray
    }
  }
}
