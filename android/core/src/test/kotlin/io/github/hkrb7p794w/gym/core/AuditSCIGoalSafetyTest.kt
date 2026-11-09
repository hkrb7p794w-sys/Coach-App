package io.github.hkrb7p794w.gym.core

import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Audit SCI-02: Android setzt das Ziel „Abnehmen“ ohne die Schutzregeln aus `GoalRules.assess` (CoachCore) um –
 * kein Halt bei BMI unter 18,5 und keiner unter 18 Jahren. Beide Fälle schlagen mit dem Stand 8baa407 fehl.
 */
class AuditSCIGoalSafetyTest {
    private fun kcal(settings: NutritionSettings): Double =
        NutritionPlanner.compute(settings, DayType.REST).values[Nutrient.KCAL.key]!!

    @Test
    fun noDeficitBelowMinimumBmi() {
        // 50 kg, 175 cm: BMI 16,3
        val underweight = NutritionSettings(weightKg = 50.0, heightCm = 175.0, age = 25, isFemale = true, configured = true)
        val lose = kcal(underweight.copy(goal = NutritionGoal.LOSE, weeklyChangePercent = -1.0))
        val maintain = kcal(underweight.copy(goal = NutritionGoal.MAINTAIN))
        assertTrue(lose >= maintain - 1, "BMI 16,3: Abnehmen $lose kcal statt mindestens $maintain kcal")
    }

    @Test
    fun noDeficitForMinors() {
        val teen = NutritionSettings(weightKg = 60.0, heightCm = 165.0, age = 16, isFemale = true, configured = true)
        val lose = kcal(teen.copy(goal = NutritionGoal.LOSE))
        val maintain = kcal(teen.copy(goal = NutritionGoal.MAINTAIN))
        assertTrue(lose >= maintain - 1, "16 Jahre: Abnehmen $lose kcal statt mindestens $maintain kcal")
    }
}
