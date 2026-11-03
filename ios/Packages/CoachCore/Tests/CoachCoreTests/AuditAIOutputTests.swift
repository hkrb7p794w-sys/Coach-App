import Foundation
import Testing

@testable import CoachCore

/// Audit CORE2-04: KI-Antworten werden mit `Int(doubleValue)` in Ganzzahlen gewandelt. Liefert die KI (oder ein
/// eingefügter Import) eine riesige Zahl, bricht die App mit „Double value cannot be converted to Int“ ab:
/// - `InsightAnalysis.insights` (`gueltig_tage`, `prioritaet`), Worker `groundInsights` begrenzt die Werte nicht,
/// - `GymCoach.validatePlan` (`saetze`, `wdh_min`, `wdh_max`, `pause`), erreichbar über `gym_plan` und den
///   manuellen Import `CoachImport.preview`.
/// Exit-Tests (Swift 6.2): Der Absturz läuft in einem Kindprozess, der Testlauf selbst bleibt stehen.
#if os(macOS) || os(Linux)
  struct AuditAIOutputTests {
    @Test func hugeValidityFromAIDoesNotCrash() async {
      await #expect(processExitsWith: .success) {
        let facts = [InsightAnalysis.Fact(id: "f1", text: "Schlaf der letzten Nächte: im Schnitt unter 7 Stunden")]
        let output: JSONValue = .object([
          "empfehlungen": .array([
            .object([
              "thema": .string("erholung"), "betreff": .string("schlaf"), "titel": .string("Mehr Schlaf"),
              "text": .string("Heute früher ins Bett."), "richtung": .string("mehr"),
              "belege": .array([.string("f1")]), "gueltig_tage": .number(1e30), "prioritaet": .number(-1e30),
            ])
          ])
        ])
        let insights = InsightAnalysis.insights(
          from: output, facts: facts, model: "test", now: Date(timeIntervalSince1970: 1_790_000_000))
        precondition(insights.count == 1)
        precondition(insights[0].priority == 1)
      }
    }

    @Test func hugeSetCountInImportDoesNotCrash() async {
      await #expect(processExitsWith: .success) {
        let answer = """
          ```ironludi
          {"routinen": {"modus": "ergaenzen", "liste": [
            {"name": "Push", "uebungen": [{"id": "bankdruecken", "saetze": 1e30, "wdh_min": 8, "wdh_max": 12}]}
          ]}}
          ```
          """
        let preview = try CoachImport.preview(
          answer, profile: UserProfile(mode: .personal, sports: [.strength]), equipment: Equipment.gym, custom: [])
        precondition(preview.routines.first?.items.first?.sets == 5)
      }
    }

    @Test func hugeRestFromAIDoesNotCrash() async {
      await #expect(processExitsWith: .success) {
        let output: JSONValue = .object([
          "routinen": .array([
            .object([
              "name": .string("Push"),
              "uebungen": .array([.object(["id": .string("bankdruecken"), "pause": .number(-1e300)])]),
            ])
          ])
        ])
        let result = GymCoach.validatePlan(
          output, request: GymCoach.PlanRequest(), equipment: Equipment.gym, custom: [])
        precondition(result.routines.first?.items.first?.restSeconds == 45)
      }
    }
  }
#endif
