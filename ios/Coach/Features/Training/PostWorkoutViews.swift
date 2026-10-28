import CoachCore
import SwiftData
import SwiftUI

/// „Nach dem Training“ auf Heute: Anstrengung 1–10 abfragen, gegen den Plan auswerten, morgen ggf. entschärfen.
struct PostWorkoutSection: View {
  let records: [ActivityRecord]
  let sessions: SessionMatcher.Week?
  @Environment(AppModel.self) private var model
  @State private var applied: (day: CalendarDay, previous: PlanAdjustments)?
  @State private var editing: PlanSuggestion?

  var body: some View {
    let settings = model.settings
    let candidates = records.compactMap(\.activity)
      .filter { ($0.durationSeconds ?? 0) >= SessionMatcher.minimumSeconds }
      .sorted { ($0.startLocal ?? "") > ($1.startLocal ?? "") }
    if let activity = candidates.first(where: { !settings.closedReviews.contains(String($0.id)) }) {
      let key = String(activity.id)
      let effort = settings.efforts[key]
      Section {
        Text(activity.name ?? activity.typeKey ?? "Training").font(.headline)
        if let effort {
          review(activity, effort: effort)
        } else {
          EffortPicker { settings.efforts[key] = $0 }
        }
        Button(effort == nil ? "Ohne Angabe schließen" : "Fertig") {
          settings.closedReviews = Array((settings.closedReviews + [key]).suffix(60))
        }
        .font(.subheadline)
      } header: {
        Text("Nach dem Training")
      } footer: {
        if effort == nil {
          Text("1 = sehr leicht, 10 = maximal. Daraus und aus der Dauer schätzt die App die Belastung (session RPE).")
        }
      }
    }
  }

  @ViewBuilder
  private func review(_ activity: GarminActivity, effort: Int) -> some View {
    let settings = model.settings
    let today = CalendarDay(date: .now)
    let tomorrow = today.adding(days: 1)
    let personal = settings.profile.mode == .personal
    let result = PostWorkout.review(
      activity: activity, effort: effort,
      planned: sessions?.results.first { $0.activityID == activity.id }, planKnown: sessions != nil,
      tomorrow: tomorrow, tomorrowSchedule: personal ? settings.schedule(inWeekOf: tomorrow) : nil)
    VStack(alignment: .leading, spacing: 6) {
      Label(result.headline, systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold))
        .foregroundStyle(.green)
      ForEach(result.points, id: \.self) { Text($0).font(.subheadline) }
    }
    if let applied, applied.day == tomorrow {
      Label("Morgen ist jetzt locker geplant.", systemImage: "checkmark").font(.subheadline)
      Button("Rückgängig", systemImage: "arrow.uturn.backward") {
        settings.planAdjustments = applied.previous
        self.applied = nil
      }
    } else if let suggestion = result.tomorrow,
      let plan = PlanSuggestion.postWorkout(
        suggestion, activityID: activity.id, profile: settings.profile, adjustments: settings.planAdjustments),
      !settings.dismissedSuggestions.contains(plan.id)
    {
      // Gleiche Karte wie in der Vorschlagsliste: Diff, Regelprüfung, Übernehmen/Anpassen/Verwerfen.
      SuggestionCard(
        suggestion: plan,
        apply: {
          applied = (suggestion.day, settings.planAdjustments)
          settings.planAdjustments = plan.adjustments
        },
        adjust: { editing = plan },
        dismiss: { settings.dismissedSuggestions = Array((settings.dismissedSuggestions + [plan.id]).suffix(60)) })
      .sheet(item: $editing) { plan in NextWeekPlanSheet(monday: plan.week, initial: plan.schedule) }
    }
    Button("Anstrengung ändern (\(effort)/10)") { settings.efforts[String(activity.id)] = nil }
      .font(.footnote)
    if !result.evidenceIDs.isEmpty {
      EvidenceDisclosure(ruleIDs: result.evidenceIDs)
    }
  }
}

/// Zehn Tasten statt Schieberegler: ein Tipp, mit einer Hand.
private struct EffortPicker: View {
  let pick: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Wie anstrengend war es?").font(.subheadline)
      HStack(spacing: 4) {
        ForEach(1...10, id: \.self) { value in
          Button("\(value)") { pick(value) }
            .buttonStyle(.bordered)
            .tint(color(value))
            .font(.subheadline.monospacedDigit())
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Anstrengung \(value) von 10")
        }
      }
      .buttonBorderShape(.roundedRectangle(radius: 8))
      .controlSize(.small)
    }
  }

  private func color(_ value: Int) -> Color {
    value <= PostWorkout.easyEffort ? .green : value < PostWorkout.hardEffort ? .orange : .red
  }
}

/// Kleine Etiketten: Quelle(n) und Intensität.
struct FeedBadges: View {
  let sources: [ActivitySource]
  let intensity: SessionKind?

  var body: some View {
    HStack(spacing: 4) {
      if let intensity, intensity != .gym {
        badge(intensity.label, color: intensity == .easy ? .green : .orange)
      }
      ForEach(sources, id: \.self) { badge($0.label, color: .secondary) }
    }
  }

  private func badge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15), in: Capsule())
      .foregroundStyle(color)
  }
}

/// Zeit in den fünf Herzfrequenzzonen als ein Balken.
struct ZoneShareBar: View {
  let shares: [Double]
  private let colors: [Color] = [.gray, .blue, .green, .orange, .red]

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      GeometryReader { proxy in
        HStack(spacing: 1) {
          ForEach(shares.indices, id: \.self) { index in
            Rectangle().fill(colors[index % colors.count])
              .frame(width: max(proxy.size.width * shares[index] - 1, 0))
          }
        }
      }
      .frame(height: 10)
      .clipShape(Capsule())
      HStack(spacing: 8) {
        ForEach(shares.indices, id: \.self) { index in
          Text("Z\(index + 1) \(Int((shares[index] * 100).rounded())) %")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Zonen: "
        + shares.indices.map { "Zone \($0 + 1) \(Int((shares[$0] * 100).rounded())) Prozent" }.joined(separator: ", "))
  }
}

/// Was fehlt und was das heißt – statt leerer Felder.
struct MissingDataSection: View {
  let notes: [String]

  var body: some View {
    if !notes.isEmpty {
      Section("Fehlende Daten") {
        ForEach(notes, id: \.self) { note in
          Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
  }
}
