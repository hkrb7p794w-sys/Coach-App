import Charts
import CoachCore
import SwiftData
import SwiftUI
import UserNotifications

/// Erinnerung 30 Minuten vor der empfohlenen Schlafenszeit (täglich, bis sie neu berechnet wird).
enum BedtimeReminder {
  static let identifier = "coach.bedtime"

  static func schedule(settings: SleepSettings, bedtimeMinutes: Int?) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard settings.reminder, let bedtimeMinutes else { return }
    let status = await center.notificationSettings().authorizationStatus
    var allowed = status == .authorized || status == .provisional
    if status == .notDetermined {
      allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
    guard allowed else { return }
    let reminder = ((bedtimeMinutes - 30) % 1_440 + 1_440) % 1_440
    let content = UNMutableNotificationContent()
    content.title = "Bald Schlafenszeit"
    content.body = "Um \(SleepCoach.clock(bedtimeMinutes)) ins Bett – dann reicht der Schlaf für morgen."
    content.sound = .default
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: DateComponents(hour: reminder / 60, minute: reminder % 60), repeats: true)
    try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }
}

/// Schlaf-Coach: Bedarf für heute Nacht, Schlafenszeit, Verlauf der letzten zwei Wochen und Hinweise.
struct SleepCoachView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]

  private var today: CalendarDay { CalendarDay(date: .now) }

  private var metrics: [DailyMetrics] { days.compactMap(\.metrics) }

  private var report: SleepCoach.Report? {
    SleepCoach.report(
      days: metrics, settings: model.settings.sleep, goal: model.settings.profile.goal, today: today)
  }

  var body: some View {
    @Bindable var settings = model.settings
    List {
      if let report {
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Text("Heute um \(SleepCoach.clock(report.bedtimeMinutes)) ins Bett").font(.title3.bold())
            Text(
              "Für \(GermanFormat.decimal(Double(report.tonightMinutes) / 60)) Stunden Schlaf bis "
                + "\(SleepCoach.clock(settings.sleep.wakeMinutes)), inklusive etwa \(SleepCoach.latencyMinutes) "
                + "Minuten zum Einschlafen."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
          LabeledContent(
            "Schnitt \(report.nights) Nächte", value: "\(GermanFormat.decimal(report.averageHours)) h")
          if report.debtHours > 0 {
            LabeledContent("Unter deinem Ziel", value: "\(GermanFormat.decimal(report.debtHours)) h")
          }
          if let spread = report.bedtimeSpreadMinutes {
            LabeledContent("Schwankung Einschlafzeit", value: "± \(Int(spread)) min")
          }
        } header: {
          Text("Heute Nacht")
        }
        Section("Hinweise") {
          ForEach(report.tips) { tip in
            Label(tip.text, systemImage: tip.id == "good" ? "checkmark.circle.fill" : "moon.zzz.fill")
              .font(.subheadline)
          }
          EvidenceDisclosure(ruleIDs: report.tips.flatMap(\.evidenceIDs))
        }
      } else {
        Section {
          Text("Für den Schlaf-Coach braucht die App Schlafdaten von mindestens drei Nächten aus Garmin.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      chartSection
      Section {
        Stepper(
          "Ziel: \(GermanFormat.decimal(settings.sleep.targetHours)) Stunden", value: $settings.sleep.targetHours,
          in: 7...9, step: 0.25)
        DatePicker("Aufstehen", selection: wakeTime, displayedComponents: .hourAndMinute)
        Toggle("Erinnerung 30 min vorher", isOn: $settings.sleep.reminder)
      } header: {
        Text("Einstellungen")
      } footer: {
        Text("Erwachsene brauchen regelmäßig 7–9 Stunden. Feste Zeiten, auch am Wochenende, helfen am meisten.")
      }
    }
    .navigationTitle("Schlaf-Coach")
    .task(id: "\(settings.sleep.hashValue)-\(report?.bedtimeMinutes ?? -1)") {
      await BedtimeReminder.schedule(settings: settings.sleep, bedtimeMinutes: report?.bedtimeMinutes)
    }
  }

  private var wakeTime: Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: model.settings.sleep.wakeHour, minute: model.settings.sleep.wakeMinute, second: 0, of: .now)
          ?? .now
      },
      set: { date in
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        model.settings.sleep.wakeHour = parts.hour ?? 6
        model.settings.sleep.wakeMinute = parts.minute ?? 30
      })
  }

  @ViewBuilder
  private var chartSection: some View {
    let recent = metrics.filter { $0.day >= today.adding(days: -13) && ($0.sleepSeconds ?? 0) > 0 }
    if !recent.isEmpty {
      Section("Letzte 14 Nächte") {
        Chart {
          ForEach(recent, id: \.day) { night in
            BarMark(
              x: .value("Nacht", night.day.localDate, unit: .day),
              y: .value("Stunden", (night.sleepSeconds ?? 0) / 3_600)
            )
            .foregroundStyle((night.sleepSeconds ?? 0) / 3_600 >= 7 ? Color.indigo : Color.orange)
          }
          RuleMark(y: .value("Ziel", model.settings.sleep.targetHours))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(.secondary)
        }
        .frame(height: 160)
        .accessibilityLabel("Schlafdauer der letzten 14 Nächte")
      }
    }
  }
}

/// Kurzer Hinweis unter „Heute“: Schlafenszeit für heute Nacht.
struct SleepTonightSection: View {
  let days: [DailyMetrics]
  @Environment(AppModel.self) private var model

  var body: some View {
    let today = CalendarDay(date: .now)
    if let report = SleepCoach.report(
      days: days, settings: model.settings.sleep, goal: model.settings.profile.goal, today: today)
    {
      Section {
        NavigationLink {
          SleepCoachView()
        } label: {
          HStack(spacing: 12) {
            SportIcon(symbol: "moon.stars.fill", color: .indigo)
            VStack(alignment: .leading, spacing: 2) {
              Text("Heute um \(SleepCoach.clock(report.bedtimeMinutes)) ins Bett").font(.subheadline.weight(.semibold))
              Text(report.tips.first?.text ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
          }
        }
      }
    }
  }
}
