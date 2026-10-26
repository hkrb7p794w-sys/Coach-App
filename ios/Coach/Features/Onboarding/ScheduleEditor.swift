import CoachCore
import SwiftUI

/// Wochenplan bearbeiten: je Tag Einheiten hinzufügen, Intensität ändern oder entfernen.
struct ScheduleEditor: View {
  @Binding var schedule: WeekSchedule
  let sports: [TrainingSport]
  var highlight: Weekday?

  var body: some View {
    ForEach(Weekday.allCases) { weekday in
      DayEditorRow(
        weekday: weekday, isHighlighted: weekday == highlight, sports: sports,
        slots: Binding(get: { schedule.slots(on: weekday) }, set: { schedule.set($0, on: weekday) }))
    }
  }
}

private struct DayEditorRow: View {
  let weekday: Weekday
  let isHighlighted: Bool
  let sports: [TrainingSport]
  @Binding var slots: [SessionSlot]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(weekday.long)
          .font(.subheadline.weight(isHighlighted ? .bold : .semibold))
        if isHighlighted { Chip(text: "Heute", color: .accentColor) }
        Spacer()
        Menu {
          ForEach(sports) { sport in
            Button {
              slots.append(SessionSlot(sport, sport == .strength ? .hard : .easy))
            } label: {
              Label(sport.label, systemImage: sport.symbol)
            }
          }
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.title3)
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Einheit am \(weekday.long) hinzufügen")
      }
      if slots.isEmpty {
        Text("Frei").font(.footnote).foregroundStyle(.secondary)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
            SlotChip(slot: slot) { updated in
              if let updated { slots[index] = updated } else { slots.remove(at: index) }
            }
          }
        }
      }
    }
    .padding(.vertical, 2)
  }
}

private struct SlotChip: View {
  let slot: SessionSlot
  /// `nil` = entfernen.
  let change: (SessionSlot?) -> Void

  private var intensities: [SessionIntensity] {
    switch slot.sport {
    case .strength: [.easy, .hard]
    case .other: []
    default: SessionIntensity.allCases
    }
  }

  var body: some View {
    Menu {
      ForEach(intensities) { intensity in
        Button {
          change(SessionSlot(slot.sport, intensity))
        } label: {
          if intensity == slot.intensity {
            Label(intensity.label, systemImage: "checkmark")
          } else {
            Text(intensity.label)
          }
        }
      }
      Button("Entfernen", role: .destructive) { change(nil) }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: slot.sport.symbol)
        Text(slot.chipLabel).lineLimit(1)
      }
      .font(.footnote.weight(.semibold))
      .padding(.horizontal, 10)
      .frame(minHeight: 34)
      .background(slot.sport.color.opacity(0.15), in: Capsule())
      .foregroundStyle(slot.sport.color)
    }
  }
}

/// Hinweise zum Wochenplan mit Quellen (Praxisregeln sind gekennzeichnet).
struct ScheduleHintsSection: View {
  let hints: [ScheduleHint]

  var body: some View {
    if !hints.isEmpty {
      Section {
        ForEach(hints) { hint in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(hint.severity))
              .foregroundStyle(color(hint.severity))
              .frame(width: 24)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
              Text(hint.message).font(.subheadline)
              if hint.isPracticeRule && hint.severity != .info {
                Text("Praxisregel").font(.caption2).foregroundStyle(.secondary)
              }
            }
          }
        }
        let ids = hints.flatMap(\.evidenceIDs)
        if !ids.isEmpty { EvidenceDisclosure(ruleIDs: ids) }
      } header: {
        Text("Dein Plan im Check")
      }
    }
  }

  private func symbol(_ severity: ScheduleHint.Severity) -> String {
    switch severity {
    case .warning: "exclamationmark.triangle.fill"
    case .tip: "lightbulb.fill"
    case .info: "info.circle.fill"
    }
  }

  private func color(_ severity: ScheduleHint.Severity) -> Color {
    switch severity {
    case .warning: .orange
    case .tip: .blue
    case .info: .secondary
    }
  }
}
