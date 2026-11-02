package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NutritionTest {
    private val bls by lazy { Bls.parse(File("../app/src/main/assets/bls.tsv").readText()) }

    // Gleiche Fälle wie `BLSTests` in CoachCore.
    @Test
    fun blsTableLoads() {
        assertTrue(bls.foods.size > 7_000)
        val oats = assertNotNull(bls.food("C133000"))
        assertEquals("Hafer Flocken", oats.name)
        assertEquals(348.0, oats.per100g[Nutrient.KCAL])
        assertEquals(13.22, oats.per100g[Nutrient.PROTEIN])
        assertNull(oats.per100g[Nutrient.VITAMIN_C])
    }

    @Test
    fun blsMatchesSearchTermsLikeCoachCore() {
        val cases = listOf(
            "Hühnerei gekocht" to "E111132", "Eier gekocht" to "E111132", "Haferflocken" to "C133000",
            "Möhren gekocht" to "G620132", "Karotte" to "G620100", "Erdnüsse" to "H110600", "Walnüsse" to "H120100",
            "Kartoffeln gekocht" to "K110132", "Nudeln gekocht" to "E401032", "Reis poliert, gekocht" to "C352032",
            "Vollmilch 3,5 % Fett" to "M111300", "Kaffee mit Milch" to "N410200", "Butter" to "Q611000",
            "Pilsner Bier" to "P163000", "Weizenbrötchen" to "B511000", "Apfel" to "F110100", "Tomaten" to "G561100",
        )
        for ((term, code) in cases) assertEquals(code, bls.match(term)?.code, "$term → ${bls.match(term)?.name}")
        for (term in listOf("Brötchen", "Bier", "Müsli", "Cola", "Rührei", "", "x")) {
            assertNull(bls.match(term), "$term → ${bls.match(term)?.name}")
        }
        assertFalse(bls.match("Butter")!!.name.contains("gesalzen"))
        assertEquals("Q6A4000", bls.match("Butter gesalzen")?.code)
        assertEquals("E612032", bls.match("Teigwaren glutenfrei gekocht")?.code)
    }

    @Test
    fun blsEnrichAndSearch() {
        val item = MealItem(
            name = "Haferflocken", grams = 50.0, source = FoodSource.AI,
            per100g = nutrients(Nutrient.KCAL to 370.0, Nutrient.PROTEIN to 12.0, Nutrient.VITAMIN_C to 1.0), searchTerm = "Haferflocken",
        )
        val enriched = bls.enrich(item)
        assertEquals(FoodSource.BLS, enriched.source)
        assertEquals("C133000", enriched.blsCode)
        assertEquals(348.0, enriched.per100g[Nutrient.KCAL])
        assertEquals(1.0, enriched.per100g[Nutrient.VITAMIN_C])
        assertEquals(174.0, enriched.amounts[Nutrient.KCAL])
        val egg = assertNotNull(bls.food("E111132"))
        val switched = bls.apply(egg, enriched)
        assertEquals(egg.per100g[Nutrient.VITAMIN_C], switched.per100g[Nutrient.VITAMIN_C])

        val manual = MealItem(name = "Haferflocken", grams = 50.0, source = FoodSource.MANUAL, per100g = nutrients(Nutrient.KCAL to 1.0))
        assertEquals(manual, bls.enrich(manual))
        val results = bls.search("hafer")
        assertTrue(results.first().name.startsWith("Hafer"))
        assertTrue(results.any { it.code == "C133000" })
        assertTrue(bls.search("x").isEmpty())
        assertEquals("F110100", bls.search("apfel roh").first().code)
        assertTrue(bls.food("N410100")!!.item().isDrink)
        assertFalse(bls.food("C133000")!!.item().isDrink)
    }

    @Test
    fun targetsMatchCoachCoreFormula() {
        // 75 kg, 180 cm, 35 J., Mann, PAL 1,4, halten, Ruhetag – von Hand nach `NutritionPlanner.compute` gerechnet.
        val rest = NutritionPlanner.compute(NutritionSettings(), DayType.REST)
        assertEquals(1705.0, rest.basalMetabolicRate)
        assertEquals(2387.0, rest.values[Nutrient.KCAL])
        assertEquals(135.0, rest.values[Nutrient.PROTEIN])
        assertEquals(253.0, rest.values[Nutrient.CARBS])
        assertEquals(93.0, rest.values[Nutrient.FAT])
        assertEquals(2600.0, rest.values[Nutrient.WATER])

        // Harter Tag: mehr Kohlenhydrate, kein Defizit („fuel for the work“).
        val hard = NutritionPlanner.compute(NutritionSettings(goal = NutritionGoal.LOSE), DayType.HARD)
        assertTrue(hard.values[Nutrient.CARBS]!! >= 6 * 75)
        assertFalse(hard.energyFloorApplied)

        // Makros ergeben die Energie, Fett mindestens 20 %.
        for (type in DayType.entries) {
            val t = NutritionPlanner.compute(NutritionSettings(goal = NutritionGoal.LOSE, isFemale = true, weightKg = 60.0, heightCm = 165.0), type)
            val kcal = t.values[Nutrient.KCAL]!!
            val sum = 4 * t.values[Nutrient.PROTEIN]!! + 4 * t.values[Nutrient.CARBS]!! + 9 * t.values[Nutrient.FAT]!!
            assertTrue(abs(sum - kcal) < 15, "$type: $sum vs $kcal")
            assertTrue(9 * t.values[Nutrient.FAT]!! >= 0.19 * kcal, "$type Fett")
        }
    }

    @Test
    fun energyFloorProtectsAgainstTooLittle() {
        // Starkes Defizit bei kleiner Person: nie unter 30 kcal je kg fettfreie Masse (REDs).
        val settings = NutritionSettings(weightKg = 50.0, heightCm = 158.0, age = 30, isFemale = true, activityFactor = 1.2, goal = NutritionGoal.LOSE, weeklyChangePercent = -5.0)
        val targets = NutritionPlanner.compute(settings, DayType.REST)
        assertTrue(targets.values[Nutrient.KCAL]!! >= 30 * 50 * 0.75 - 1)
        // Wunsch −5 %/Woche wird auf −1 % begrenzt.
        assertEquals(-1.0, NutritionSettings.safeWeeklyChange(-5.0))
        assertEquals(0.5, NutritionSettings.safeWeeklyChange(3.0))
    }

    @Test
    fun analysisFromWorkerAnswer() {
        val output = Json.parseToJsonElement(
            """{"titel":"Frühstück","kategorie":"fruehstueck","hinweis":"Schätzung","vielleicht_vergessen":["Butter",3],
            "items":[{"name":"Haferflocken","menge_g":60,"menge_text":"6 EL","suchbegriff":"Haferflocken",
            "naehrwerte_100g":{"kcal":370,"protein_g":12,"water_g":10}},{"name":"","menge_g":10},{"name":"Milch","menge_g":0}]}""",
        )
        val analysis = assertNotNull(MealAnalysis.parse(output, bls))
        assertEquals(MealCategory.BREAKFAST, analysis.category)
        assertEquals(listOf("Butter"), analysis.possiblyMissing)
        val oats = analysis.items.single()
        assertEquals(FoodSource.BLS, oats.source)
        assertEquals(Portion("EL", 10.0), oats.portion)
        assertNull(MealAnalysis.parse(Json.parseToJsonElement("""{"items":[]}"""), bls))
    }

    @Test
    fun openFoodFactsAndBarcodes() {
        assertTrue(OpenFoodFacts.isValidBarcode("4006381333931"))
        assertFalse(OpenFoodFacts.isValidBarcode("4006381333932"))
        assertFalse(OpenFoodFacts.isValidBarcode("abc"))
        val json = Json.parseToJsonElement(
            """{"status":1,"product":{"product_name_de":"Proteinriegel","brands":"Marke, Zweite","serving_quantity":45,
            "serving_size":"1 Riegel (45 g)","nutriments":{"energy-kcal_100g":380,"proteins_100g":30,"sodium_100g":0.4}}}""",
        )
        val item = assertNotNull(OpenFoodFacts.item(json, "4006381333931"))
        assertEquals("Proteinriegel (Marke)", item.name)
        assertEquals(45.0, item.grams)
        assertEquals(400.0, item.per100g[Nutrient.SODIUM])
        assertEquals(Portion("Riegel", 45.0), item.portion)
        assertNull(OpenFoodFacts.item(Json.parseToJsonElement("""{"status":0}"""), "1"))
    }

    @Test
    fun diaryFlowSuggestionsAndPortions() {
        val zone = ZoneOffset.UTC
        val monday = LocalDate.parse("2026-11-02")
        fun at(day: LocalDate, hour: Int) = day.atTime(hour, 0).toInstant(zone).toEpochMilli()
        val oats = bls.food("C133000")!!.item(60.0)
        var data = AppData()
        for (offset in 1L..3L) {
            val day = monday.minusDays(offset)
            data = Diary.save(data, Meal(createdAt = at(day, 8), day = "", category = MealCategory.BREAKFAST, title = "Porridge", items = listOf(oats)), zone)
        }
        val frequent = MealSuggestions.frequent(data.meals, MealCategory.BREAKFAST, monday)
        assertEquals(3, frequent.single().count)
        assertEquals(1, MealSuggestions.yesterday(data.meals, MealCategory.BREAKFAST, monday).size)
        assertEquals(1, MealSuggestions.recent(data.meals).size)

        val (logged, meal) = Diary.logCopy(data, "Porridge", frequent.single().items, MealCategory.BREAKFAST, at(monday, 8))
        data = logged
        assertEquals(oats.amounts[Nutrient.KCAL], Nutrition.totals(Nutrition.meals(monday, data.meals).flatMap { it.items })[Nutrient.KCAL])
        // Heute schon eingetragen: nicht noch einmal vorschlagen.
        assertTrue(MealSuggestions.frequent(data.meals, MealCategory.BREAKFAST, monday).isEmpty())

        data = Diary.toggleFavorite(data, meal)
        assertTrue(Diary.isFavorite(data, meal))
        val half = MealPortion.adjusted(meal.items, 0.5)
        assertEquals(30.0, half.single().grams)
        assertEquals(0.5, MealPortion.eatenFraction(half))
        assertEquals(60.0, MealPortion.adjusted(half, 1.0).single().grams)

        data = Diary.logWater(data, 250.0, at(monday, 10))
        assertEquals(250.0 + 60 * 0.0 + (oats.amounts[Nutrient.WATER] ?: 0.0), Diary.totals(data, monday)[Nutrient.WATER])
        // Leere Mahlzeit wird gelöscht statt gespeichert.
        data = Diary.save(data, meal.copy(items = emptyList()), zone)
        assertTrue(data.meals.none { it.id == meal.id })

        // Sicherung mit Ernährung bleibt vollständig und alte Sicherungen (ohne Ernährung) sind lesbar.
        assertEquals(data.meals.size, Backup.decode(Backup.encode(data))?.meals?.size)
        assertNotNull(Backup.decode("""{"version":1,"sessions":[]}"""))
    }

    @Test
    fun portionsAndBudget() {
        assertEquals(Portion("Scheibe", 30.0), PortionGuess.from("2 Scheiben", 60.0))
        assertNull(PortionGuess.from("150 g", 150.0))
        assertEquals("1½", PortionGuess.format(1.5))
        val item = MealItem(name = "Brot", grams = 60.0, source = FoodSource.MANUAL, portion = Portion("Scheibe", 30.0))
        assertEquals("2 × Scheibe (60 g)", item.amountLabel)
        assertEquals(45.0, item.withPortions(1.5).grams)
        val line = assertNotNull(NutritionBudget.line(Nutrient.PROTEIN, nutrients(Nutrient.PROTEIN to 135.0), nutrients(Nutrient.PROTEIN to 73.0)))
        assertEquals("noch 62 g", NutritionBudget.remainingText(line))
        assertEquals("muesli", FoodSearch.normalized(" Müsli "))
        val quick = MealItem.quick(kcal = 650.0, protein = 30.0)
        assertTrue(quick.isQuickEstimate)
        assertEquals(650.0, quick.amounts[Nutrient.KCAL])
        assertEquals(MealCategory.LUNCH, MealCategory.guess(12, 30))
    }
}
