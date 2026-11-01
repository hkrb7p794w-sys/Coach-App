import CoachCore
import SwiftUI

/// Schematische Körperkarte (vorn und hinten) mit Farbe je Muskel: grau = nicht beansprucht, gelb bis rot = mehr.
/// Eine Übersicht, keine anatomisch genaue Darstellung.
struct BodyMapView: View {
  /// Wert je Muskel; ab `full` volle Farbe.
  let values: [Muscle: Double]
  let full: Double
  /// Eigene Farbe je Muskel (z. B. Regeneration); überschreibt die Heatmap-Farbe.
  var colors: [Muscle: Color] = [:]

  var body: some View {
    HStack(spacing: 16) {
      figure(Self.front, title: "Vorn")
      figure(Self.back, title: "Hinten")
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private func figure(_ regions: [Region], title: String) -> some View {
    VStack(spacing: 4) {
      Canvas { context, size in
        let scale = min(size.width / 100, size.height / 200)
        let offsetX = (size.width - 100 * scale) / 2
        func rect(_ r: CGRect) -> CGRect {
          CGRect(x: offsetX + r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
        }
        let base = Color.secondary.opacity(0.12)
        // Umriss: Kopf, Rumpf, Arme, Beine.
        context.fill(Path(ellipseIn: rect(CGRect(x: 40, y: 2, width: 20, height: 22))), with: .color(base))
        for part in Self.silhouette {
          context.fill(Path(roundedRect: rect(part), cornerRadius: 6 * scale), with: .color(base))
        }
        for region in regions {
          let color = colors[region.muscle] ?? heat(values[region.muscle] ?? 0)
          for frame in region.frames {
            context.fill(Path(roundedRect: rect(frame), cornerRadius: 3 * scale), with: .color(color))
          }
        }
      }
      .aspectRatio(0.5, contentMode: .fit)
      .frame(maxHeight: 220)
      Text(title).font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func heat(_ value: Double) -> Color {
    let level = MuscleLoad.intensity(value, full: full)
    guard level > 0 else { return Color.secondary.opacity(0.22) }
    // Gelb → Orange → Rot.
    return Color(hue: 0.15 - 0.15 * level, saturation: 0.85, brightness: 0.95).opacity(0.45 + 0.55 * level)
  }

  private var accessibilityText: String {
    let shown = values.filter { $0.value > 0 }.sorted { $0.value > $1.value }
    guard !shown.isEmpty else { return "Keine Muskeln beansprucht" }
    return "Muskelkarte: "
      + shown.map { "\($0.key.label) \(GermanFormat.decimal($0.value)) Sätze" }.joined(separator: ", ")
  }

  struct Region {
    var muscle: Muscle
    var frames: [CGRect]
  }

  /// Links und rechts gespiegelt (Zeichenfläche 100 × 200).
  private static func pair(_ muscle: Muscle, x: Double, y: Double, width: Double, height: Double) -> Region {
    Region(
      muscle: muscle,
      frames: [
        CGRect(x: x, y: y, width: width, height: height),
        CGRect(x: 100 - x - width, y: y, width: width, height: height),
      ])
  }

  static let silhouette: [CGRect] = [
    CGRect(x: 30, y: 28, width: 40, height: 66),
    CGRect(x: 14, y: 32, width: 14, height: 72), CGRect(x: 72, y: 32, width: 14, height: 72),
    CGRect(x: 31, y: 90, width: 18, height: 104), CGRect(x: 51, y: 90, width: 18, height: 104),
  ]

  static let front: [Region] = [
    pair(.frontDelts, x: 26, y: 32, width: 10, height: 10),
    pair(.sideDelts, x: 15, y: 34, width: 9, height: 12),
    pair(.chest, x: 36, y: 34, width: 13, height: 16),
    pair(.biceps, x: 16, y: 48, width: 10, height: 22),
    pair(.forearms, x: 15, y: 73, width: 10, height: 28),
    Region(muscle: .abs, frames: [CGRect(x: 42, y: 53, width: 16, height: 34)]),
    pair(.obliques, x: 33, y: 55, width: 8, height: 28),
    pair(.quads, x: 32, y: 96, width: 13, height: 46),
    pair(.adductors, x: 45.5, y: 98, width: 4, height: 30),
    pair(.calves, x: 34, y: 150, width: 10, height: 30),
  ]

  static let back: [Region] = [
    Region(muscle: .traps, frames: [CGRect(x: 38, y: 29, width: 24, height: 15)]),
    pair(.rearDelts, x: 23, y: 33, width: 11, height: 10),
    pair(.sideDelts, x: 15, y: 34, width: 8, height: 12),
    pair(.lats, x: 32, y: 45, width: 15, height: 30),
    Region(muscle: .lowerBack, frames: [CGRect(x: 41, y: 76, width: 18, height: 14)]),
    pair(.triceps, x: 16, y: 48, width: 10, height: 22),
    pair(.forearms, x: 15, y: 73, width: 10, height: 28),
    pair(.glutes, x: 32, y: 91, width: 17, height: 17),
    pair(.hamstrings, x: 32, y: 110, width: 15, height: 34),
    pair(.calves, x: 33, y: 148, width: 13, height: 32),
  ]
}

/// Heatmap mit Liste: welche Muskeln wie viele effektive Sätze bekommen haben.
struct MuscleHeatmapSection: View {
  let title: String
  let values: [Muscle: Double]
  /// Ab so vielen Sätzen volle Farbe.
  var full = 6.0
  var footer: String?

  var body: some View {
    Section {
      BodyMapView(values: values, full: full)
        .padding(.vertical, 6)
      let shown = values.filter { $0.value > 0 }.sorted { $0.value > $1.value }
      ForEach(shown, id: \.key) { entry in
        HStack {
          Text(entry.key.label)
          Spacer()
          Text("\(GermanFormat.decimal(entry.value)) Sätze").monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.subheadline)
      }
    } header: {
      Text(title)
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          footer
            ?? "Effektive Arbeitssätze: Hauptmuskel 1, mitarbeitende Muskeln 0,5; Sätze mit RIR 4+ und Drop-Sätze "
            + "halb, Aufwärmen nicht. Eine Schätzung, keine Messung.")
        EvidenceDisclosure(ruleIDs: ["gym.muscle-load", "gym.volume"])
      }
    }
  }
}

/// Langzeitübersicht: Wochensätze je Muskel, Mittel über 4 Wochen, wenig Trainiertes und Regeneration.
struct MuscleOverviewSection: View {
  let sessions: [GymSession]
  @Environment(AppModel.self) private var model
  @State private var mode = Mode.week

  enum Mode: String, CaseIterable, Identifiable {
    case week = "7 Tage"
    case month = "Ø 4 Wochen"
    case recovery = "Erholung"
    var id: String { rawValue }
  }

  var body: some View {
    let statuses = MuscleLoad.status(
      sessions: sessions, now: .now, custom: model.settings.gym.customExercises)
    Section {
      Picker("Ansicht", selection: $mode) {
        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      BodyMapView(
        values: Dictionary(uniqueKeysWithValues: statuses.map { ($0.muscle, value($0)) }),
        full: MuscleLoad.weeklyFull,
        colors: mode == .recovery
          ? Dictionary(uniqueKeysWithValues: statuses.map { ($0.muscle, recoveryColor($0.recovery)) }) : [:]
      )
      .padding(.vertical, 6)
      ForEach(statuses.sorted { order($0) < order($1) }) { status in
        HStack(alignment: .firstTextBaseline) {
          Circle().fill(recoveryColor(status.recovery)).frame(width: 8, height: 8).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 1) {
            Text(status.muscle.label).font(.subheadline)
            Text(detail(status)).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(GermanFormat.decimal(value(status))) Sätze")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(status.isLow && mode != .recovery ? .orange : .secondary)
        }
      }
    } header: {
      Text("Muskeln")
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          "Effektive Sätze je Muskel (Hauptmuskel 1, mitarbeitend 0,5). Volle Farbe ab \(Int(MuscleLoad.weeklyFull)) "
            + "Sätzen pro Woche, orange unter \(Int(MuscleLoad.weeklyEnough)). „Vermutlich noch in der Erholung“ heißt: "
            + "in den letzten "
            + "\(Int(MuscleLoad.recoveryHours)) Stunden nennenswert belastet – eine Schätzung, keine Messung von Ermüdung.")
        EvidenceDisclosure(ruleIDs: ["gym.muscle-load", "gym.volume"])
      }
    }
  }

  private func value(_ status: MuscleLoad.Status) -> Double {
    mode == .month ? status.averageWeeklySets : status.weeklySets
  }

  /// Erholung zuerst, dann wenig trainiert, dann nach Sätzen.
  private func order(_ status: MuscleLoad.Status) -> (Int, Double) {
    switch status.recovery {
    case .recovering: (0, -value(status))
    case .neglected: (1, -value(status))
    case .ready: (2, -value(status))
    }
  }

  private func detail(_ status: MuscleLoad.Status) -> String {
    let last = status.lastLoaded.map { "zuletzt \($0.formatted(.relative(presentation: .named)))" } ?? "noch nie"
    return "\(status.recovery.label) · \(last)"
  }

  private func recoveryColor(_ recovery: MuscleLoad.Recovery) -> Color {
    switch recovery {
    case .recovering: .orange
    case .ready: .green
    case .neglected: Color.secondary.opacity(0.4)
    }
  }
}
