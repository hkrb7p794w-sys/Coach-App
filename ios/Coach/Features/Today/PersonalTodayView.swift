import CoachCore
import SwiftUI

/// „Heute“ für Profile ohne Saisonplan: Empfehlung aus Erholung und eigenem Wochenplan, die Woche auf einen Blick
/// und der Fortschritt zu den eigenen Zielen.
struct PersonalTodaySections: View {
  let snapshot: TodayViewModel.Snapshot
  let activities: [GarminActivity]
  let gymDays: Set<CalendarDay>
  @Environment(AppModel.self) private var model

  var body: some View {
    let profile = model.settings.profile
    if let advice = snapshot.advice {
      PersonalAdviceSection(snapshot: snapshot, advice: advice, profile: profile)
    }
    PersonalWeekStrip(profile: profile, activityDays: Set(activities.compactMap(\.day)).union(gymDays))
    PersonalGoalSection(profile: profile, snapshot: snapshot, activities: activities)
  }
}

private struct PersonalAdviceSection: View {
  let snapshot: TodayViewModel.Snapshot
  let advice: ScheduleAdvice
  let profile: UserProfile

  private var color: Color {
    switch snapshot.recommendation.level {
    case .normal: .green
    case .locker: .orange
    case .pause: .red
    }
  }

  private var symbol: String {
    switch advice.mode {
    case .asPlanned: "checkmark.circle.fill"
    case .lighter: "tortoise.fill"
    case .rest, .restDay: "bed.double.fill"
    case .done: "checkmark.seal.fill"
    }
  }

  var body: some View {
    let slots = profile.schedule.slots(on: Weekday(day: snapshot.plan.today))
    Section {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: symbol)
            .font(.title)
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(advice.headline).font(.title3.bold())
            Text("Erholung: \(snapshot.recommendation.label)").font(.footnote).foregroundStyle(.secondary)
          }
        }
        Text(advice.detail).font(.subheadline)
        if !snapshot.recommendation.reasons.isEmpty {
          Text(snapshot.recommendation.reasons.joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if snapshot.isFromYesterday {
          Label("Noch keine Garmin-Werte für heute – Einordnung mit den Werten von gestern.", systemImage: "clock")
            .font(.footnote)
            .foregroundStyle(.orange)
        }
        if let move = advice.move {
          Label("Vorschlag: auf \(move.long) verschieben", systemImage: "arrow.turn.down.right")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
        if !slots.isEmpty {
          HStack(spacing: 8) {
            ForEach(slots) { slot in
              Chip(text: slot.chipLabel, color: slot.sport.color)
            }
          }
        }
        if !advice.evidenceIDs.isEmpty {
          EvidenceDisclosure(ruleIDs: advice.evidenceIDs)
        }
      }
      .padding(.vertical, 4)
    }
  }
}

/// Die sieben Tage der Woche: geplant, erledigt, frei.
private struct PersonalWeekStrip: View {
  let profile: UserProfile
  let activityDays: Set<CalendarDay>

  private enum DayState {
    case done, today, planned, missed, rest
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
    if activityDays.contains(day) { return .done }
    if !planned { return .rest }
    if day == today { return .today }
    return day < today ? .missed : .planned
  }

  private func dayCell(weekday: Weekday, day: CalendarDay, today: CalendarDay) -> some View {
    let slots = profile.schedule.slots(on: weekday)
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
    case .today: Color.accentColor.opacity(0.15)
    case .planned: Color.secondary.opacity(0.15)
    case .missed: Color.secondary.opacity(0.08)
    case .rest: .clear
    }
  }

  @ViewBuilder
  private func icon(_ state: DayState, slots: [SessionSlot]) -> some View {
    switch state {
    case .done:
      Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
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
    case .rest: "frei"
    case .missed: "nicht gemacht"
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
    let longestRun = activities
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
