import CoachCore
import SwiftUI

/// Die Woche auf einen Blick und der Fortschritt zu den eigenen Zielen.
struct PersonalWeekSections: View {
  let snapshot: TodayViewModel.Snapshot
  let activities: [GarminActivity]
  let gymDays: Set<CalendarDay>
  @Environment(AppModel.self) private var model

  var body: some View {
    PersonalWeekStrip(
      schedule: model.settings.schedule(inWeekOf: snapshot.plan.today), sessions: snapshot.sessions,
      activityDays: Set(activities.filter { ($0.durationSeconds ?? 0) >= 600 }.compactMap(\.day)).union(gymDays))
    PersonalGoalSection(profile: model.settings.profile, snapshot: snapshot, activities: activities)
  }
}

/// Die sieben Tage der Woche: geplant, erledigt (Soll/Ist je Einheit), frei.
private struct PersonalWeekStrip: View {
  let schedule: WeekSchedule
  let sessions: SessionMatcher.Week?
  /// Tage mit Training (ab 10 Minuten) – an freien Tagen als Extra markiert.
  let activityDays: Set<CalendarDay>

  private enum DayState {
    case done, partial, today, planned, missed, rest, extra
  }

  var body: some View {
    let today = CalendarDay(date: .now)
    let monday = today.adding(days: -today.weekdayIndex)
    Section("Diese Woche") {
      HStack(spacing: 4) {
        ForEach(Weekday.allCases) { weekday in
          let day = monday.adding(days: weekday.rawValue)
          dayCell(weekday: weekday, day: day, today: today)
        }
      }
    }
  }

  private func state(planned: Bool, day: CalendarDay, today: CalendarDay) -> DayState {
    let results = sessions?.results(on: day) ?? []
    guard planned, !results.isEmpty else { return activityDays.contains(day) ? .extra : .rest }
    if results.allSatisfy({ $0.status == .done }) { return .done }
    if results.allSatisfy(\.status.counts) { return .partial }
    if results.contains(where: { $0.status == .missed }) {
      return results.contains(where: \.status.counts) ? .partial : .missed
    }
    return day == today ? .today : .planned
  }

  private func dayCell(weekday: Weekday, day: CalendarDay, today: CalendarDay) -> some View {
    let slots = schedule.slots(on: weekday)
    let current = state(planned: !slots.isEmpty, day: day, today: today)
    return VStack(spacing: 6) {
      Text(weekday.short)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(day == today ? Color.accentColor : Color.secondary)
      ZStack {
        Circle().fill(fill(current))
        Circle().strokeBorder(current == .today ? Color.accentColor : .clear, lineWidth: 2)
        icon(current, slots: slots)
      }
      .frame(width: 36, height: 36)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(weekday.long): \(label(current, slots: slots))")
  }

  private func fill(_ state: DayState) -> Color {
    switch state {
    case .done: .green
    case .partial: .orange
    case .extra: Color.green.opacity(0.25)
    case .today: Color.accentColor.opacity(0.15)
    case .planned: Color.secondary.opacity(0.15)
    case .missed: Color.red.opacity(0.12)
    case .rest: .clear
    }
  }

  @ViewBuilder
  private func icon(_ state: DayState, slots: [SessionSlot]) -> some View {
    switch state {
    case .done:
      Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
    case .partial:
      Image(systemName: "circle.lefthalf.filled").font(.footnote.weight(.bold)).foregroundStyle(.white)
    case .extra:
      Image(systemName: "plus").font(.footnote.weight(.bold)).foregroundStyle(.green)
    case .missed:
      Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.red)
    case .rest:
      Text("–").foregroundStyle(.secondary)
    default:
      Image(systemName: slots.first?.sport.symbol ?? "circle")
        .font(.footnote)
        .foregroundStyle(state == .missed ? Color.secondary : (slots.first?.sport.color ?? .secondary))
    }
  }

  private func label(_ state: DayState, slots: [SessionSlot]) -> String {
    switch state {
    case .done: "erledigt"
    case .partial: "teilweise oder anders gemacht"
    case .extra: "frei, außerplanmäßig trainiert"
    case .rest: "frei"
    case .missed: "verpasst"
    case .today, .planned: slots.map(\.title).joined(separator: ", ")
    }
  }
}

/// Fortschritt zu den eigenen Zielen: Wettkampf, Ruhepuls, Laufstrecke.
private struct PersonalGoalSection: View {
  let profile: UserProfile
  let snapshot: TodayViewModel.Snapshot
  let activities: [GarminActivity]

  var body: some View {
    let today = CalendarDay(date: .now)
    let targets = profile.targets
    let longestRun =
      activities
      .filter { $0.sport == .run && ($0.day ?? today.adding(days: -999)) >= today.adding(days: -28) }
      .compactMap(\.distanceMeters).max().map { $0 / 1000 }
    if profile.event != nil || targets.restingHeartRate != nil || targets.runDistanceKilometers != nil {
      Section("Deine Ziele") {
        if let event = profile.event {
          let days = today.days(until: event.date)
          row(
            "flag.checkered", event.name,
            days > 0 ? "noch \(days) Tage" : (days == 0 ? "heute" : "vorbei"))
        }
        if let target = targets.restingHeartRate {
          let current = snapshot.metrics?.restingHeartRate
          row(
            "heart.fill", "Ruhepuls",
            "\(current.map { "\(Int($0.rounded())) bpm" } ?? "–") → \(target) bpm")
          Text(GoalRules.restingHeartRateOutlook(current: current, target: target))
            .font(.footnote)
            .foregroundStyle(.secondary)
          EvidenceDisclosure(ruleIDs: ["rhr.endurance"])
        }
        if let target = targets.runDistanceKilometers {
          row(
            "figure.run", "Längster Lauf (4 Wochen)",
            "\(longestRun.map { GermanFormat.decimal($0) } ?? "–") von \(GermanFormat.decimal(target)) km")
        }
      }
    }
  }

  private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).frame(width: 24).foregroundStyle(Color.accentColor).accessibilityHidden(true)
      Text(title)
      Spacer()
      Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
    }
  }
}
