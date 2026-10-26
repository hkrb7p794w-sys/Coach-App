import CoachCore
import SwiftUI

/// Ausführliche Erklärung einer Einheit: wozu, Schritt für Schritt, Gefühl, typische Fehler, Begriffe.
struct UnitGuideSections: View {
  let guide: UnitGuide

  var body: some View {
    Section("Worum es geht") {
      Text(guide.purpose).font(.subheadline)
    }
    if !guide.steps.isEmpty {
      Section("So gehst du vor") {
        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
          HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
              .font(.caption.bold())
              .frame(width: 20, height: 20)
              .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(step).font(.subheadline)
          }
        }
      }
    }
    Section("So soll es sich anfühlen") {
      Label(guide.feel, systemImage: "heart.text.square").font(.subheadline)
    }
    if !guide.mistakes.isEmpty {
      Section("Typische Fehler") {
        ForEach(guide.mistakes, id: \.self) { mistake in
          Label(mistake, systemImage: "exclamationmark.triangle").font(.subheadline)
        }
      }
    }
    if !guide.terms.isEmpty {
      Section("Begriffe") {
        ForEach(guide.terms) { term in
          DisclosureGroup(term.name) {
            Text(term.explanation).font(.subheadline)
          }
        }
      }
    }
  }
}

/// Eine Einheit des eigenen Wochenplans im Detail.
struct SessionGuideView: View {
  let slot: SessionSlot

  var body: some View {
    List {
      Section {
        HStack(spacing: 14) {
          SportIcon(symbol: slot.sport.symbol, color: slot.sport.color, size: 48)
          VStack(alignment: .leading, spacing: 2) {
            Text(slot.intensity.label).font(.subheadline.weight(.semibold)).foregroundStyle(slot.sport.color)
            Text(slot.title).font(.title3.bold())
          }
        }
        Text(slot.guide).font(.footnote).foregroundStyle(.secondary)
      }
      UnitGuideSections(guide: UnitGuides.guide(for: slot))
      Section {
        let isIntervals = slot.intensity == .hard && slot.sport == .run
        EvidenceDisclosure(ruleIDs: isIntervals ? ["run.4x4", "intensity.distribution"] : ["intensity.distribution"])
      }
    }
    .navigationTitle(slot.sport.label)
    .navigationBarTitleDisplayMode(.inline)
  }
}
