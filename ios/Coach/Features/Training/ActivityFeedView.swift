import CoachCore
import SwiftData
import SwiftUI

/// Ein Verlauf für alles Training: Garmin, Apple Health, Nachgetragenes und die Gym-Einheiten der App.
/// Doppelte Einheiten (Gym-App und Garmin-Kraft) erscheinen einmal, mit beiden Quellen.
struct ActivityListView: View {
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var records: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymRecords: [GymSessionRecord]
  @Environment(AppModel.self) private var model

  /// So viele Wochen bekommen den Bezug zum Plan (ältere Wochen ohne, damit die Liste schnell bleibt).
  private static let plannedWeeks = 6

  var body: some View {
    let entries = feed()
    let grouped = Dictionary(grouping: entries) { String($0.day.iso.prefix(7)) }
    let recordsByID = Dictionary(records.map { ($0.garminID, $0) }, uniquingKeysWith: { first, _ in first })
    let gymByID = Dictionary(gymRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    List {
      if entries.isEmpty {
        ContentUnavailableView(
          "Noch keine Aktivitäten", systemImage: "figure.run",
          description: Text("Ziehe unter „Heute“ nach unten, um Garmin abzurufen, oder trage ein Training nach."))
      }
      ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
        Section(monthTitle(month)) {
          ForEach(grouped[month] ?? []) { entry in
            if let activity = entry.activity, let record = recordsByID[activity.id] {
              NavigationLink {
                ActivityDetailView(record: record)
              } label: {
                FeedRow(entry: entry)
              }
            } else if let gym = entry.gym, let record = gymByID[gym.id], let session = record.session {
              NavigationLink {
                SessionDetailView(record: record, session: session)
              } label: {
                FeedRow(entry: entry)
              }
            } else {
              FeedRow(entry: entry)
            }
          }
        }
      }
    }
    .navigationTitle("Aktivitäten")
  }

  private func feed() -> [ActivityFeed.Entry] {
    let activities = records.compactMap(\.activity)
    let sessions = gymRecords.compactMap(\.session)
    var results: [SessionResult] = []
    if model.settings.profile.mode == .personal {
      let today = CalendarDay(date: .now)
      let gymDays = sessions.map(\.day)
      for week in 0..<Self.plannedWeeks {
        results += TodayViewModel.sessionWeek(
          settings: model.settings, activities: activities, gymDays: gymDays, today: today,
          weekOf: today.adding(days: -7 * week)
        ).results
      }
    }
    return ActivityFeed.entries(activities: activities, gym: sessions.map(ActivityFeed.GymItem.init), results: results)
  }

  private func monthTitle(_ key: String) -> String {
    guard let day = CalendarDay(iso: key + "-01") else { return key }
    return day.localDate.formatted(.dateTime.month(.wide).year())
  }
}

/// Zeile im Verlauf: Sportart, Titel, Kernwerte, Intensität, Quellen und Bezug zum Plan.
struct FeedRow: View {
  let entry: ActivityFeed.Entry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      let sport = SessionMatcher.sport(entry.sport)
      SportIcon(symbol: sport.symbol, color: sport.color)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
          Spacer(minLength: 4)
          Text(Formatters.day(entry.day)).font(.caption).foregroundStyle(.secondary)
        }
        if !entry.values.isEmpty {
          Text(entry.values.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        HStack(spacing: 6) {
          FeedBadges(sources: entry.sources, intensity: entry.intensity)
          if let planned = entry.planned {
            SessionStatusBadge(status: planned.status)
          }
        }
        if let planned = entry.planned {
          Text("Plan: \(planned.planned.slot.title)" + (planned.intensityNote.map { " · \($0)" } ?? ""))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
