package io.github.hkrb7p794w.gym.core

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Audit AND-3: CoachCore rundet mit Swift `.rounded()` (kaufmännisch, ,5 weg von null), der Kotlin-Port mit
 * `Math.rint` (,5 zur geraden Zahl). Bei genau ,5 weichen Android und iPhone ab.
 * Belege: NutritionTargets.swift:362 vs. NutritionTargets.kt:176, RecipePlan.swift:451 vs. Recipes.kt:325,
 * QuickLog.swift:145 vs. Nutrition.kt:365.
 * Hinweis: `NutritionTest.targetsMatchCoachCoreFormula` (Zeile 83) schreibt den abweichenden Wert 2600 fest und muss
 * beim Fix auf 2650 geändert werden.
 */
class AuditRoundingTest {
    @Test
    fun waterTargetRoundsHalfUpLikeCoachCore() {
        // 75 kg × 35 ml = 2625 ml → 52,5 × 50: Swift (52,5).rounded() = 53 → 2650 ml.
        val rest = NutritionPlanner.compute(NutritionSettings(), DayType.REST)
        assertEquals(2650.0, rest.values[Nutrient.WATER])
    }

    @Test
    fun shoppingListRoundsHalfUpLikeCoachCore() {
        val recipe = Recipe(
            meal = MealCategory.LUNCH,
            title = "Salat",
            minutes = 10,
            ingredients = listOf(
                MealItem(name = "Salz", grams = 2.5, source = FoodSource.MANUAL),
                MealItem(name = "Olivenöl", grams = 12.5, source = FoodSource.MANUAL),
            ),
            steps = emptyList(),
        )
        val plan = WeeklyRecipePlan(0, listOf(RecipeDay("2026-11-03", listOf(recipe), 1.0)), emptyList())
        val list = RecipePlanner.shoppingList(plan, 1).associate { it.name to it.grams }
        // Swift: (0,5).rounded() × 5 = 5 g bzw. (2,5).rounded() × 5 = 15 g; Kotlin liefert 0 g und 10 g.
        assertEquals(5.0, list["Salz"])
        assertEquals(15.0, list["Olivenöl"])
    }

    @Test
    fun remainingTextRoundsHalfUpLikeCoachCore() {
        val line = NutritionBudget.line(Nutrient.PROTEIN, nutrients(Nutrient.PROTEIN to 135.0), nutrients(Nutrient.PROTEIN to 72.5))!!
        assertEquals("noch 63 g", NutritionBudget.remainingText(line))
    }
}
