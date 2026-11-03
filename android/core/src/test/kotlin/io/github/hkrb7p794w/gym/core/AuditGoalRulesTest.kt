package io.github.hkrb7p794w.gym.core

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Audit AND-1/AND-2: CoachCore `GoalRules.assess` (GoalRules.swift:80–93) hält das Gewicht für unter 18-Jährige und
 * bei BMI unter 18,5 (kein Defizit). Android hat nur die Tempo-Grenzen (Weight.kt:12–16, NutritionTargets.kt:98);
 * `Diary.targets` rechnet für diese Personen trotzdem ein Defizit. CLAUDE.md: „Gewichtsziele nur mit den
 * Schutzgrenzen aus GoalRules“. Der Test prüft den Weg, den die App nutzt (`Diary.targets`, NutritionScreen.kt:108).
 */
class AuditGoalRulesTest {
    private val day = LocalDate.parse("2026-11-03")

    private fun kcal(settings: NutritionSettings): Double =
        Diary.targets(AppData(nutrition = settings), day).values[Nutrient.KCAL]!!

    @Test
    fun minorGetsNoDeficit() {
        val minor = NutritionSettings(weightKg = 60.0, heightCm = 170.0, age = 16, goal = NutritionGoal.LOSE, weeklyChangePercent = -1.0)
        val maintain = kcal(minor.copy(goal = NutritionGoal.MAINTAIN, weeklyChangePercent = null))
        assertTrue(kcal(minor) >= maintain - 15, "16 Jahre, Abnehmen: ${kcal(minor)} kcal statt mindestens ~$maintain")
    }

    @Test
    fun underweightGetsNoDeficit() {
        // 50 kg bei 175 cm = BMI 16,3.
        val thin = NutritionSettings(weightKg = 50.0, heightCm = 175.0, age = 30, goal = NutritionGoal.LOSE, weeklyChangePercent = -0.5)
        val maintain = kcal(thin.copy(goal = NutritionGoal.MAINTAIN, weeklyChangePercent = null))
        assertTrue(kcal(thin) >= maintain - 15, "BMI 16,3, Abnehmen: ${kcal(thin)} kcal statt mindestens ~$maintain")
    }
}
