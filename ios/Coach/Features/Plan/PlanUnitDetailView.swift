import CoachCore
import SwiftUI

/// Eine Einheit im Detail: Ablauf mit Paces/Watt, Ausrüstung, Wettkampf-Entscheidung, Grundlage.
struct PlanUnitDetailView: View {
  let unit: PlannedUnit
  let week: PlanWeek
  @Environment(AppModel.self) private var model

  private var tokens: PlanTokens { PlanTokens(config: model.settings.season) }

  var body: some View {
    List {
      Section {
        HStack(spacing: 14) {
          SportIcon(symbol: unit.kind.symbol, color: unit.kind.color, size: 48)
          VStack(alignment: .leading, spacing: 2) {
            Text(unit.kind.label).font(.subheadline.weight(.semibold)).foregroundStyle(unit.kind.color)
            Text(unit.title).font(.title3.bold())
            if unit.done {
              Label("Erledigt", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green)
            }
          }
        }
        .padding(.vertical, 4)
      }

      if unit.kind == .swim, !unit.swimSteps.isEmpty {
        Section {
          ForEach(Array(SwimStepText.lines(unit.swimSteps, tokens: tokens).enumerated()), id: \.offset) { _, line in
            Text(line.trimmingCharacters(in: .whitespaces))
              .font(.subheadline)
              .padding(.leading, CGFloat(line.prefix { $0 == " " }.count) * 8)
          }
        } header: {
          Text("Ablauf")
        } footer: {
          if let meters = unit.swimMeters {
            Text("Gesamt \(meters) m · CSS \(PlanTokens.mmss(model.settings.season.cssSecondsPer100m)) /100 m")
          }
        }
        let equipment = SwimStepText.equipment(in: unit.swimSteps)
        if !equipment.isEmpty {
          Section("Mitnehmen") {
            ForEach(equipment, id: \.self) { Label($0, systemImage: "bag") }
          }
        }
      } else if let workout = unit.gymWorkout {
        Section("Übungen") {
          ForEach(workout.exercises) { exercise in
            LabeledContent(exercise.name) {
              Text(gymTarget(exercise)).monospacedDigit()
            }
            .font(.subheadline)
          }
        }
        if !workout.note.isEmpty {
          Section { Text(workout.note).font(.footnote).foregroundStyle(.secondary) }
        }
      } else {
        Section("Ablauf") {
          Text(unit.detail).font(.body)
        }
      }

      if let code = unit.zwiftCode {
        Section {
          LabeledContent("Zwift-Workout", value: code == "RAMP" ? "FTP Ramp Test Lite" : "GAC \(code)")
          LabeledContent("FTP", value: "\(model.settings.season.ftpWatts) W")
        } footer: {
          Text("Watt-Angaben aus der FTP unter Einstellungen › Saison & Ziele.")
        }
      }

      if unit.isCompetition {
        CompetitionSection(unit: unit, week: week)
      }

      Section {
        EvidenceDisclosure(ruleIDs: unit.evidenceIDs)
      }
    }
    .navigationTitle(unit.kind.label)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func gymTarget(_ exercise: PlannedExercise) -> String {
    let reps = exercise.reps.map { "\(exercise.sets) × \($0)" } ?? "\(exercise.sets) Sätze"
    let weight = exercise.weightKg.map { " · \(GermanFormat.number($0)) kg" } ?? ""
    return reps + weight
  }
}

private struct CompetitionSection: View {
  let unit: PlannedUnit
  let week: PlanWeek
  @Environment(AppModel.self) private var model

  private var key: String { SeasonSchedule.decisionKey(week: week, kind: unit.kind) }

  var body: some View {
    @Bindable var settings = model.settings
    Section {
      Picker("Entscheidung", selection: decisionBinding(settings)) {
        Text("Offen").tag(PlannedUnit.Decision.open)
        Text("Annehmen").tag(PlannedUnit.Decision.accepted)
        Text("Ablehnen").tag(PlannedUnit.Decision.rejected)
      }
      .pickerStyle(.segmented)
      if let alternative = unit.alternative, unit.decision != .rejected {
        VStack(alignment: .leading, spacing: 4) {
          Text("Alternative bei Ablehnen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text(alternative).font(.footnote)
        }
      }
    } header: {
      Text("Wettkampf-Einheit 🏁")
    } footer: {
      Text("Renntempo-Einheiten sind ein Angebot: Ablehnen ersetzt sie durch die Alternative, ohne mehr Umfang.")
    }
  }

  private func decisionBinding(_ settings: CoachSettings) -> Binding<PlannedUnit.Decision> {
    Binding(
      get: { settings.competitionDecisions[key] ?? .open },
      set: { settings.competitionDecisions[key] = $0 == .open ? nil : $0 })
  }
}
