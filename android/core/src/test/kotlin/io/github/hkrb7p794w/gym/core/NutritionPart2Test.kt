package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Teil 2 der Ernährung; Testfälle wie in CoachCore (`RecipeTests`, `WeightForecastTests`, `SafeguardTests`). */
class NutritionPart2Test {
    private val bls by lazy { Bls.parse(File("../app/src/main/assets/bls.tsv").readText()) }
    private val monday = LocalDate.parse("2026-11-02")
    private val targets = listOf(
        RecipeDayTarget(monday, DayType.MODERATE, 2000.0, 120.0, 250.0, 60.0),
        RecipeDayTarget(monday.plusDays(1), DayType.REST, 1800.0, 120.0, 180.0, 60.0),
    )

    private fun ingredient(name: String, grams: Int, kcal: Int, protein: Int = 0) =
        """{"name":"$name","menge_g":$grams,"naehrwerte_100g":{"kcal":$kcal,"protein_g":$protein}}"""

    private fun dish(title: String, meal: String, vararg ingredients: String) =
        """{"titel":"$title","mahlzeit":"$meal","minuten":15,"zubereitung":["Alles mischen.","Servieren."],"zutaten":[${ingredients.joinToString(",")}]}"""

    private fun output(day: LocalDate, vararg dishes: String): JsonElement =
        Json.parseToJsonElement("""{"tage":[{"datum":"$day","gerichte":[${dishes.joinToString(",")}]}]}""")

    @Test
    fun dietRulesLikeCoachCore() {
        fun v(name: String, diet: Diet, allergens: Set<Allergen> = emptySet()) = RecipePlanner.violations(name, diet, allergens)
        assertEquals(listOf("Fleisch"), v("Hähnchenbrust", Diet.VEGETARIAN))
        assertTrue(v("Lachsfilet", Diet.PESCETARIAN).isEmpty())
        assertEquals(listOf("Fisch"), v("Lachsfilet", Diet.VEGETARIAN))
        assertTrue(v("Sojahack", Diet.VEGAN).isEmpty())
        assertEquals(listOf("Ei"), v("Hühnerei", Diet.VEGAN))
        assertTrue(v("Naturreis", Diet.VEGAN).isEmpty())
        assertTrue(v("Haferbrei", Diet.VEGAN).isEmpty())
        assertEquals(listOf("Milchprodukte"), v("Skyr", Diet.VEGAN))
        assertTrue(v("Haferdrink", Diet.VEGAN).isEmpty())
        assertTrue(v("Sojajoghurt", Diet.VEGAN).isEmpty())
        assertTrue(v("Erdnussbutter", Diet.VEGAN).isEmpty())
        assertTrue(v("Vegane Bratwurst", Diet.VEGAN).isEmpty())
        assertEquals(listOf("Honig"), v("Honig", Diet.VEGAN))
        assertTrue(v("Rinderhack", Diet.OMNIVORE).isEmpty())
    }

    @Test
    fun allergenRulesLikeCoachCore() {
        fun v(name: String, diet: Diet, allergen: Allergen) = RecipePlanner.violations(name, diet, setOf(allergen))
        assertEquals(listOf("Gluten"), v("Vollkornnudeln", Diet.OMNIVORE, Allergen.GLUTEN))
        assertTrue(v("Buchweizen", Diet.OMNIVORE, Allergen.GLUTEN).isEmpty())
        assertTrue(v("Erdnussbutter", Diet.OMNIVORE, Allergen.NUTS).isEmpty())
        assertEquals(listOf("Erdnüsse"), v("Erdnussbutter", Diet.OMNIVORE, Allergen.PEANUTS))
        assertEquals(listOf("Schalenfrüchte (Nüsse)"), v("Walnusskerne", Diet.OMNIVORE, Allergen.NUTS))
        assertTrue(v("Laktosefreie Milch", Diet.OMNIVORE, Allergen.LACTOSE).isEmpty())
        assertEquals(listOf("Laktose / Milch"), v("Bergkäse", Diet.OMNIVORE, Allergen.LACTOSE))
        assertEquals(listOf("Soja"), v("Tofu natur", Diet.VEGAN, Allergen.SOY))
        assertEquals(listOf("Krebstiere und Weichtiere"), v("Garnelen", Diet.OMNIVORE, Allergen.SHELLFISH))
        assertEquals(listOf("Sesam"), v("Tahin", Diet.VEGAN, Allergen.SESAME))
        assertEquals(listOf("Ei"), v("Spiegelei", Diet.OMNIVORE, Allergen.EGG))
        // Versteckt: Pesto enthält Milch und Nüsse.
        assertTrue(RecipePlanner.violations("Basilikumpesto", Diet.VEGAN, setOf(Allergen.NUTS)).containsAll(listOf("Milchprodukte", "Schalenfrüchte (Nüsse)")))
    }

    @Test
    fun weeklyPlanScalesAndDropsViolations() {
        val plan = assertNotNull(
            RecipePlanner.plan(
                output(
                    monday,
                    dish("Porridge", "fruehstueck", ingredient("Haferflocken", 100, 370, 13)),
                    dish("Linsencurry", "mittagessen", ingredient("Rote Linsen", 150, 340, 25)),
                    dish("Hähnchen-Bowl", "abendessen", ingredient("Hähnchenbrust", 200, 110, 23)),
                ),
                targets, Diet.VEGETARIAN, emptySet(), bls, 0,
            ),
        )
        val day = assertNotNull(plan.day(monday))
        assertEquals(listOf("Porridge", "Linsencurry"), day.recipes.map { it.title })
        assertTrue("„Hähnchen-Bowl“ verworfen: enthält Fleisch." in plan.notes)
        assertTrue("Dienstag: keine Rezepte erhalten." in plan.notes)
        assertEquals(1.33, day.scale)
        assertEquals(135.0, day.recipes.first().ingredients.first().grams)
        assertTrue(plan.notes.any { it.startsWith("Montag: Rezepte ergeben ca.") })
        assertNull(RecipePlanner.plan(Json.parseToJsonElement("{}"), targets, Diet.OMNIVORE, emptySet(), bls, 0))
    }

    @Test
    fun shoppingListAndGaps() {
        val plan = assertNotNull(
            RecipePlanner.plan(
                output(
                    monday,
                    dish("A", "fruehstueck", ingredient("Testflocken", 80, 370)),
                    dish("B", "snack", ingredient("testflocken", 40, 370), ingredient("Testbanane", 120, 90)),
                ),
                listOf(RecipeDayTarget(monday, DayType.REST, 552.0, 0.0, 0.0, 0.0)), Diet.OMNIVORE, emptySet(), bls, 0,
            ),
        )
        val list = RecipePlanner.shoppingList(plan, 2)
        assertEquals(listOf("Testbanane", "Testflocken"), list.map { it.name })
        assertEquals(240.0, list.last().grams)

        val goal = nutrients(Nutrient.PROTEIN to 120.0, Nutrient.FIBER to 30.0, Nutrient.IRON to 15.0)
        val day = nutrients(Nutrient.PROTEIN to 115.0, Nutrient.FIBER to 18.0, Nutrient.IRON to 14.0)
        assertTrue(RecipePlanner.gaps(listOf(day, day), goal).isEmpty())
        assertEquals(listOf("Ballaststoffe: im Schnitt 18 von 30 g (60 %)"), RecipePlanner.gaps(listOf(day, day, day), goal))
        assertEquals(ShoppingAisle.SPICES, ShoppingAisle.of("Olivenöl", null))
        assertEquals(ShoppingAisle.PRODUCE, ShoppingAisle.of("Brokkoli", "gemuese"))
    }

    @Test
    fun mealNowScalesAndChecks() {
        assertNull(MealNow.targetKcal(100.0))
        assertEquals(900.0, MealNow.targetKcal(1500.0))
        val answer = Json.parseToJsonElement(
            """{"gerichte":[${dish("Skyr-Bowl", "snack", ingredient("Testskyr", 200, 60, 11))},
            ${dish("Wurstbrot", "snack", ingredient("Salami", 50, 400, 20))}]}""",
        )
        val (recipes, notes) = MealNow.suggestions(answer, 240.0, Diet.VEGETARIAN, emptySet(), bls)
        assertEquals(listOf("Skyr-Bowl"), recipes.map { it.title })
        assertTrue(notes.single().contains("Fleisch"))
        // 120 kcal → Ziel 240: Faktor 2 auf 1,6 begrenzt → 320 g.
        assertEquals(320.0, recipes.single().ingredients.single().grams)
        assertTrue(RecipePlanner.implausible(MealItem(name = "x", grams = 1.0, source = FoodSource.AI, per100g = nutrients(Nutrient.KCAL to 950.0))))
    }

    @Test
    fun ownRecipeTracksStock() {
        val chili = OwnRecipe(
            name = "Chili",
            ingredients = listOf(MealItem(name = "Bohnen", grams = 800.0, source = FoodSource.MANUAL, per100g = nutrients(Nutrient.KCAL to 100.0))),
            cookedGrams = 1000.0, portions = 4, remainingPortions = 4.0,
        )
        assertEquals(250.0, chili.portionGrams)
        assertEquals(80.0, chili.per100g[Nutrient.KCAL])
        assertEquals(200.0, chili.item().amounts[Nutrient.KCAL])
        assertEquals(3.0, chili.consumed(250.0).remainingPortions)
        val data = Diary.logRecipe(AppData(recipes = listOf(chili)), chili, null, MealCategory.LUNCH, 0)
        assertEquals(3.0, data.recipes.single().remainingPortions)
        assertEquals("Chili", data.meals.single().title)
    }

    @Test
    fun weightForecastLikeCoachCore() {
        val half = assertNotNull(WeightForecast.compute(90.0, -0.5, 180.0, 2_800.0, 85.0, monday))
        assertEquals(0.45, half.weeklyKilograms)
        assertEquals(500.0, half.dailyDeficit)
        assertEquals(listOf(4, 8, 12), half.points.map { it.weeks })
        assertEquals(88.2, half.points[0].kilograms)
        assertEquals(85.0, half.points[2].kilograms)
        assertEquals(12, half.weeksToTarget)
        val capped = assertNotNull(WeightForecast.compute(120.0, -1.0, 175.0, 2_400.0, null, monday))
        assertTrue(capped.deficitCapped)
        assertEquals(600.0, capped.dailyDeficit)
        val floor = assertNotNull(WeightForecast.compute(62.0, -1.0, 180.0, null, 50.0, monday))
        assertEquals(60.0, floor.floorKilograms)
        assertEquals(60.0, floor.target)
        assertTrue(floor.points.all { it.kilograms >= 60 })
        assertNull(WeightForecast.compute(80.0, 0.25, 180.0, null, null, monday))
    }

    private fun entries(start: Double, perWeek: Double, days: Int = 28) = (0 until days).map { offset ->
        val noise = if (offset % 2 == 0) 0.3 else -0.3
        WeightEntry(monday.plusDays((offset - days + 1).toLong()).toString(), start + perWeek * offset / 7 + noise)
    }

    @Test
    fun weightTrendLikeCoachCore() {
        assertNull(WeightTrend.trend(entries(80.0, -0.4, 7), monday))
        assertNull(WeightTrend.trend(entries(80.0, -0.4).take(5), monday))
        val onTrack = assertNotNull(WeightTrend.trend(entries(80.0, -0.4), monday))
        assertTrue(abs(onTrack.weeklyPercent + 0.5) < 0.1)
        assertEquals(WeightTrend.Kind.ON_TRACK, WeightTrend.advice(onTrack, -0.5, 0.0).kind)
        val fast = assertNotNull(WeightTrend.trend(entries(80.0, -1.0), monday))
        val fastAdvice = WeightTrend.advice(fast, -0.5, 0.0)
        assertEquals(WeightTrend.Kind.TOO_FAST, fastAdvice.kind)
        assertTrue(fastAdvice.kcal > 0 && fastAdvice.kcal <= WeightTrend.MAX_STEP_KCAL)
        val gaining = assertNotNull(WeightTrend.trend(entries(80.0, 0.2), monday))
        val less = WeightTrend.advice(gaining, -0.5, 0.0)
        assertEquals(WeightTrend.Kind.EAT_LESS, less.kind)
        assertTrue(less.kcal < 0 && less.kcal % 50 == 0.0)
        assertEquals(0.0, WeightTrend.advice(gaining, -0.5, -500.0).kcal)

        // Übernommene Anpassung fließt in die Tagesenergie ein.
        val base = NutritionPlanner.compute(NutritionSettings(), DayType.REST).values[Nutrient.KCAL]!!
        val adjusted = NutritionPlanner.compute(NutritionSettings(energyAdjustmentKcal = -200.0), DayType.REST).values[Nutrient.KCAL]!!
        assertTrue(abs(base - adjusted - 200) < 2)
        val data = Diary.applyAdjustment(Diary.applyAdjustment(AppData(), -400.0), -400.0)
        assertEquals(-500.0, data.nutrition.energyAdjustmentKcal)
        assertEquals(72.5, Diary.addWeight(AppData(), monday, 72.5).nutrition.weightKg)
    }

    @Test
    fun remindersSkipLoggedAndPast() {
        val settings = MealReminders(lunch = ReminderSlot(true, 12, 30), dinner = ReminderSlot(true, 19, 0), review = true)
        val now = LocalDateTime.parse("2026-11-02T13:00")
        val lunchToday = Meal(createdAt = 0, day = "2026-11-02", category = MealCategory.LUNCH, title = "x", items = emptyList())
        val notes = Reminders.upcoming(settings, now, listOf(lunchToday))
        // Heute: Mittag vorbei, Abend und Auswertung; morgen: Mittag, Abend, Auswertung.
        assertEquals(listOf("19:00", "20:00", "12:30", "19:00", "20:00"), notes.map { it.at.toLocalTime().toString() })
        assertEquals("Abendessen eintragen", notes.first().title)
        val dinnerLogged = lunchToday.copy(category = MealCategory.DINNER)
        assertTrue(Reminders.upcoming(settings, now, listOf(dinnerLogged)).none { it.at.toLocalDate() == monday && it.category == MealCategory.DINNER })
    }

    @Test
    fun shareRoundTripAndCodes() {
        val item = MealItem(name = "Skyr", grams = 150.0, source = FoodSource.BLS, per100g = nutrients(Nutrient.KCAL to 63.0), plannedGrams = 200.0)
        val body = MealShare.body("Frühstück", listOf(item))
        val (title, items) = assertNotNull(MealShare.items(body))
        assertEquals("Frühstück", title)
        assertEquals(200.0, items.single().grams)
        assertEquals(FoodSource.BLS, items.single().source)
        assertEquals(63.0, items.single().per100g[Nutrient.KCAL])
        assertEquals("abcdefgh23", MealShare.code("https://w.example.dev/m/abcdefgh23"))
        assertEquals("abcdefgh23", MealShare.code("coach://meal/abcdefgh23"))
        assertEquals("abcdefgh23", MealShare.code(" ABCDEFGH23 "))
        assertNull(MealShare.code("https://w.example.dev/x/abc"))
    }

    @Test
    fun evidenceAndPoints() {
        val rules = Json { ignoreUnknownKeys = true }.decodeFromString<List<EvidenceRule>>(File("../app/src/main/assets/evidence.json").readText())
        assertTrue(rules.map { it.id }.containsAll(EvidenceInput.REVIEW))
        assertEquals(5, EvidenceInput.json(rules, EvidenceInput.REVIEW).size)
        val output = Json.parseToJsonElement("""{"punkte":["Protein fehlt noch."," "],"quellen":["nutrition.protein","erfunden"]}""")
        assertEquals(listOf("Protein fehlt noch."), EvidenceInput.points(output))
        assertEquals(listOf("nutrition.protein"), EvidenceInput.sources(output, rules).map { it.id })
    }

    @Test
    fun weekSummaryAndBackupKeepsPart2() {
        val oats = bls.food("C133000")!!.item(100.0)
        var data = Diary.save(AppData(), Meal(createdAt = 0, day = "", category = MealCategory.BREAKFAST, title = "Hafer", items = listOf(oats)), java.time.ZoneOffset.UTC)
        val day = LocalDate.parse(data.meals.single().day)
        data = Diary.addWeight(data, day, 80.0).copy(recipes = listOf(OwnRecipe.from("Hafer", listOf(oats))))
        val summary = NutritionWeek.summary(data, day.minusDays((day.dayOfWeek.value - 1).toLong()), day)
        assertEquals(348.0, summary.averageKcal)
        val restored = assertNotNull(Backup.decode(Backup.encode(data)))
        assertEquals(1, restored.recipes.size)
        assertEquals(1, restored.weights.size)
        val merged = Backup.merge(AppData(), restored)
        assertEquals(1, merged.recipes.size)
        assertEquals(1, merged.weights.size)
    }

    @Test
    fun hydrationLikeCoachCore() {
        val coffee = MealItem(name = "Kaffee", grams = 250.0, source = FoodSource.BLS, per100g = nutrients(Nutrient.WATER to 98.0), isDrink = true)
        val juice = MealItem(name = "Saft", grams = 200.0, source = FoodSource.AI, per100g = nutrients(Nutrient.KCAL to 45.0), isDrink = true)
        val soup = MealItem(name = "Suppe", grams = 300.0, source = FoodSource.BLS, per100g = nutrients(Nutrient.WATER to 90.0))
        val bread = MealItem(name = "Brot", grams = 50.0, source = FoodSource.MANUAL, per100g = nutrients(Nutrient.KCAL to 250.0))
        val total = Hydration.total(listOf(coffee, juice, soup, bread, MealItem.water(500.0)))
        assertEquals(945.0, total.drinks)
        assertEquals(270.0, total.food)
        assertEquals(1215.0, total.total)
    }
}
