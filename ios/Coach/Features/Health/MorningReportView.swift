import CoachCore
import SwiftData
import SwiftUI

/// Baut den Morning Report aus den gespeicherten Tageswerten, dem Schlaf-Coach und den Einheiten von heute.
enum MorningReportBuilder {
  static func make(
    model: AppModel, days: [DailyMetrics], activities: [GarminActivity], focus: TodayFocus?, now: Date = .now
  ) -> MorningReport {
    let today = CalendarDay(date: now)
    let sessions = (focus?.items ?? []).filter { $0.sport != nil && $0.status != .done }.map {
      MorningReport.Session(id: $0.id, title: $0.title, target: $0.target, demanding: $0.demanding)
    }
    let form = FitnessForm.series(activities: activities, today: today)
    return MorningReport.make(
      days: days, today: today, sleep: model.settings.sleep, goal: model.settings.profile.goal, sessions: sessions,
      form: FitnessForm.isReliable(form) ? form.last : nil, formSeries: form)
  }
}

extension MorningReport.Status {
  var color: Color {
    switch self {
    case .good: .green
    case .normal: .blue
    case .attention: .orange
    case .missing: .gray
    }
  }

  var symbol: String {
    switch self {
    case .good: "checkmark.circle.fill"
    case .normal: "circle.fill"
    case .attention: "exclamationmark.triangle.fill"
    case .missing: "questionmark.circle"
    }
  }

  var label: String {
    switch self {
    case .good: "gut"
    case .normal: "üblich"
    case .attention: "auffällig"
    case .missing: "fehlt"
    }
  }
}

extension MorningReport {
  var levelColor: Color {
    switch level {
    case .normal?: .green
    case .locker?: .orange
    case .pause?: .red
    case nil: .gray
    }
  }

  var levelSymbol: String {
    switch level {
    case .normal?: "sun.max.fill"
    case .locker?: "tortoise.fill"
    case .pause?: "bed.double.fill"
    case nil: "questionmark"
    }
  }
}

/// Vollständiger Morning Report.
struct MorningReportView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start) private var gymSessions: [GymSessionRecord]
  /// Aus „Heute“ übergeben; sonst hier berechnet (z. B. aus dem Gesundheitsbereich).
  var focus: TodayFocus?
  @State private var computedFocus: TodayFocus?

  var body: some View {
    let report = MorningReportBuilder.make(
      model: model, days: days.compactMap(\.metrics), activities: activities.compactMap(\.activity),
      focus: focus ?? computedFocus)
    List {
      Section {
        MorningReportHeader(report: report)
        if !report.findings.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(report.findings, id: \.self) { finding in
              Label(finding, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(TintedLabelStyle(color: .orange))
            }
          }
          .font(.subheadline)
        }
        Text(report.recommendation).font(.subheadline.weight(.semibold))
      } footer: {
        if report.isFromYesterday {
          Text(
            "Für heute liegen noch keine Werte vor – gezeigt wird die letzte Nacht davor. Ziehe zum Abrufen "
              + "nach unten.")
        }
      }

      Section {
        ForEach(report.items) { item in
          MorningReportRow(item: item)
        }
      } header: {
        Text("Werte der Nacht")
      } footer: {
        Text(
          "Eingeordnet gegen deinen üblichen Bereich der letzten 30 Tage (ab 7 Tagen mit Werten), HRV gegen Garmins "
            + "Baseline. Stress vom Vortag.")
      }

      Section("Heute geplant") {
        if report.sessions.isEmpty {
          Text("Keine Einheit geplant.").foregroundStyle(.secondary)
        }
        ForEach(report.sessions) { session in
          VStack(alignment: .leading, spacing: 2) {
            Text(session.title).font(.subheadline.weight(.semibold))
            Text(session.target).font(.caption).foregroundStyle(.secondary)
          }
        }
      }

      Section("Schlafempfehlung") {
        if let advice = report.sleepAdvice {
          Text(advice)
        } else {
          Text("Ab 3 Nächten mit Schlafdaten berechnet der Schlaf-Coach deine Schlafenszeit.").foregroundStyle(
            .secondary)
        }
        NavigationLink("Schlaf-Coach") { SleepCoachView() }
      }
      WakeAlarmSection(
        wake: WakePlan.Time(minutes: model.settings.sleep.wakeMinutes),
        tonightMinutes: SleepCoach.report(
          days: days.compactMap(\.metrics), settings: model.settings.sleep, goal: model.settings.profile.goal,
          today: report.day)?.tonightMinutes ?? Int(model.settings.sleep.targetHours * 60))

      if !report.missing.isEmpty {
        Section {
          Text(report.missing.joined(separator: ", ")).foregroundStyle(.secondary)
        } header: {
          Text("Fehlt heute")
        } footer: {
          Text("Fehlende Werte werden nicht geschätzt. Body Battery, Stress und Readiness gibt es nur von Garmin.")
        }
      }
    }
    .navigationTitle("Morning Report")
    .refreshable { await model.syncNow() }
    .task(id: days.last?.updatedAt) {
      guard focus == nil else { return }
      let today = TodayViewModel()
      today.update(
        days: days.compactMap(\.metrics), activities: activities.compactMap(\.activity), settings: model.settings,
        gymDays: gymSessions.compactMap { $0.session?.day },
        gym: gymSessions.compactMap(\.session).map(ActivityFeed.GymItem.init))
      computedFocus = today.snapshot?.focus
    }
  }
}

struct MorningReportHeader: View {
  let report: MorningReport

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: report.levelSymbol)
        .font(.title2)
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(report.levelColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(report.headline).font(.title3.bold())
        Text(report.day.localDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

struct MorningReportRow: View {
  let item: MorningReport.Item

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: item.status.symbol)
        .foregroundStyle(item.status.color)
        .frame(width: 20)
        .accessibilityLabel(item.status.label)
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(item.title).font(.subheadline.weight(.semibold))
          Spacer()
          Text(item.value ?? "–").font(.subheadline.monospacedDigit())
            .foregroundStyle(item.value == nil ? .secondary : .primary)
        }
        Text(item.note).font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// Kompakte Karte im Reiter „Heute“ (bis 12 Uhr): Kopf, Auffälligkeiten, vier Kernwerte.
struct MorningReportCard: View {
  let report: MorningReport
  let focus: TodayFocus?

  private static let keyMetrics: [MorningReport.Metric] = [.sleepDuration, .hrv, .restingHeartRate, .bodyBattery]

  var body: some View {
    Section {
      NavigationLink {
        MorningReportView(focus: focus)
      } label: {
        VStack(alignment: .leading, spacing: 10) {
          MorningReportHeader(report: report)
          let items = report.items.filter { Self.keyMetrics.contains($0.metric) && $0.status != .missing }
          if !items.isEmpty {
            HStack(spacing: 8) {
              ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                  Text(item.value ?? "–").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                  Label(item.title, systemImage: item.status.symbol)
                    .labelStyle(TintedLabelStyle(color: item.status.color))
                    .font(.caption2)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          if let first = report.findings.first {
            Text(report.findings.count > 1 ? "\(first) (+\(report.findings.count - 1))" : first)
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }
    } header: {
      Text("Morning Report")
    }
  }
}

/// Symbol farbig, Text normal.
struct TintedLabelStyle: LabelStyle {
  let color: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      configuration.icon.foregroundStyle(color)
      configuration.title
    }
  }
}
