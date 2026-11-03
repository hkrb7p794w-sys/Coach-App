import Foundation
import Testing

@testable import CoachCore

/// Audit R2D-01: Tagestyp aus dem eigenen Wochenplan (Modus `.personal`), solange noch nichts aufgezeichnet ist.
/// `WeekSchedule.templateItems` hängt an jede fordernde Ausdauereinheit „intensiv lange“ an
/// (WeekSchedule.swift:110–112), `NutritionPlanner.plannedDayType` wertet „lange“ als harten Tag
/// (NutritionTargets.swift:274–285): 90 min, 8 g/kg Kohlenhydrate, kein Defizit.
private let auditR2DDay = CalendarDay(year: 2026, month: 11, day: 3)  // Dienstag

private func auditR2DItems(_ slot: SessionSlot) -> [TemplateItem] {
  var schedule = WeekSchedule()
  schedule.set([slot], on: Weekday(day: auditR2DDay))
  return schedule.templateItems(on: Weekday(day: auditR2DDay))
}

private func auditR2DSettings(goal: NutritionGoal) -> NutritionSettings {
  var settings = NutritionSettings()
  settings.weightKilograms = 95
  settings.heightCentimeters = 180
  settings.age = 45
  settings.isFemale = false
  settings.goal = goal
  return settings
}

struct AuditR2DPlannedDayTests {
  /// Ein Qualitätslauf (Tempo/Intervalle, typischerweise 30–50 min) ist kein langer Lauf. Erwartet höchstens
  /// „moderat“; tatsächlich `.hard`, weil `nutritionText` „Qualitätslauf … intensiv lange“ liefert.
  @Test func intervalRunIsNotPlannedAsHardDay() {
    let items = auditR2DItems(SessionSlot(.run, .hard))
    let type = NutritionPlanner.plannedDayType(items)
    #expect(type != nil)
    #expect((type ?? .restDay) <= .moderate)
  }

  /// 45 J., 95 kg, 180 cm, Ziel Abnehmen, heute laut Plan „Lockerer Lauf“ (noch nicht gelaufen).
  /// Handrechnung: geplant 60 min × MET 7 → +570 kcal, Tag „moderat“ → nur halbes Defizit, REDs-Boden mit
  /// pauschal 15 % KF → ≈ 3.420 kcal. Dasselbe mit Ziel „halten“ ≈ 3.230 kcal. Ein Abnehmziel darf am selben
  /// Tag nie über dem Halteziel liegen.
  @Test func plannedEasyRunLossTargetStaysBelowMaintenance() {
    let items = auditR2DItems(SessionSlot(.run, .easy))
    let lose = NutritionPlanner.compute(
      activities: [], planItems: items, settings: auditR2DSettings(goal: .lose), garminProfile: nil,
      day: auditR2DDay, hasGarminData: true)
    let hold = NutritionPlanner.compute(
      activities: [], planItems: items, settings: auditR2DSettings(goal: .maintain), garminProfile: nil,
      day: auditR2DDay, hasGarminData: true)
    #expect(lose.source == .planned)
    #expect((lose.values[.kcal] ?? 0) < (hold.values[.kcal] ?? 0))
  }
}
