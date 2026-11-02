package io.github.hkrb7p794w.gym.core

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/** Änderungen am Ernährungstagebuch – rein funktional wie `Workouts`, damit sie ohne Android testbar sind. */
object Diary {
    /** Tagestyp: für den Tag gewählt, sonst Wochentag-Standard, sonst Ruhetag. */
    fun dayType(data: AppData, day: LocalDate): DayType =
        data.dayTypes[day.toString()] ?: data.weekDayTypes[day.dayOfWeek.value] ?: DayType.REST

    fun targets(data: AppData, day: LocalDate): Targets = NutritionPlanner.compute(data.nutrition, dayType(data, day))

    fun setDayType(data: AppData, day: LocalDate, type: DayType): AppData =
        data.copy(dayTypes = data.dayTypes + (day.toString() to type))

    fun totals(data: AppData, day: LocalDate): NutrientMap = Nutrition.totals(Nutrition.meals(day, data.meals).flatMap { it.items })

    /** Zeitpunkt für einen Eintrag am gewählten Tag: heute = jetzt, sonst derselbe Tag zur aktuellen Uhrzeit. */
    fun timestamp(day: LocalDate, now: LocalDateTime, zone: ZoneId = ZoneId.systemDefault()): Long =
        day.atTime(now.toLocalTime()).atZone(zone).toInstant().toEpochMilli()

    /** Speichert (neu oder geändert, über die ID). Leere Mahlzeiten werden gelöscht statt gespeichert. */
    fun save(data: AppData, meal: Meal, zone: ZoneId = ZoneId.systemDefault()): AppData {
        val cleaned = meal.copy(
            items = meal.items.filter { it.grams > 0 },
            day = Nutrition.dayKey(meal.createdAt, zone),
            title = meal.title.trim().ifEmpty { meal.items.joinToString(", ") { it.name }.take(60) },
        )
        if (cleaned.items.isEmpty()) return delete(data, meal.id)
        val exists = data.meals.any { it.id == meal.id }
        val meals = if (exists) data.meals.map { if (it.id == meal.id) cleaned else it } else data.meals + cleaned
        return rememberFoods(data.copy(meals = meals.sortedBy { it.createdAt }), cleaned.items)
    }

    fun delete(data: AppData, id: String): AppData = data.copy(meals = data.meals.filter { it.id != id })

    /** Kopie einer früheren Mahlzeit oder eines Favoriten eintragen (neue IDs, ursprüngliche Mengen). */
    fun logCopy(data: AppData, title: String, items: List<MealItem>, category: MealCategory, at: Long): Pair<AppData, Meal> {
        val meal = Meal(
            createdAt = at,
            day = Nutrition.dayKey(at),
            category = category,
            title = title,
            items = items.map { MealPortion.restored(it).copy(id = java.util.UUID.randomUUID().toString()) },
        )
        return save(data, meal) to meal
    }

    fun logWater(data: AppData, milliliters: Double, at: Long): AppData =
        save(data, Meal(createdAt = at, day = Nutrition.dayKey(at), category = MealCategory.OTHER, title = "Wasser", items = listOf(MealItem.water(milliliters))))

    fun water(data: AppData, day: LocalDate): Double = hydration(data, day).total

    /** Getränke und Wasser aus Essen (wie auf dem iPhone). */
    fun hydration(data: AppData, day: LocalDate): Hydration.Total = Hydration.total(Nutrition.meals(day, data.meals).flatMap { it.items })

    /** Favorit an/aus für diese Zusammenstellung. */
    fun toggleFavorite(data: AppData, meal: Meal): AppData {
        val key = MealSuggestions.signature(meal.items.map(MealPortion::restored))
        val existing = data.favorites.firstOrNull { it.signature == key }
        return if (existing != null) {
            data.copy(favorites = data.favorites.filter { it.id != existing.id })
        } else {
            data.copy(favorites = data.favorites + FavoriteMeal(title = meal.title, items = meal.items.map(MealPortion::restored), category = meal.category))
        }
    }

    fun isFavorite(data: AppData, meal: Meal): Boolean {
        val key = MealSuggestions.signature(meal.items.map(MealPortion::restored))
        return data.favorites.any { it.signature == key }
    }

    /** Eigene Lebensmittel (Barcode, eigene Angaben) zum Wiederfinden merken; höchstens 300, neueste zuerst. */
    fun rememberFoods(data: AppData, items: List<MealItem>): AppData {
        val keep = items.filter { (it.source == FoodSource.OPEN_FOOD_FACTS || (it.source == FoodSource.MANUAL && !it.isQuickEstimate)) && it.name != "Wasser" }
        if (keep.isEmpty()) return data
        val keys = keep.map { FoodSearch.normalized(it.name) }.toSet()
        val foods = keep.map(MealPortion::restored) + data.foods.filter { FoodSearch.normalized(it.name) !in keys }
        return data.copy(foods = foods.take(300))
    }

    fun food(data: AppData, barcode: String): MealItem? = data.foods.firstOrNull { it.barcode == barcode }

    /** Tage der Woche (Montag–Sonntag) mit kcal-Summe für den Wochenstreifen. */
    fun week(data: AppData, day: LocalDate): List<Pair<LocalDate, Double>> {
        val monday = day.minusDays((day.dayOfWeek.value - 1).toLong())
        return (0L until 7L).map { offset ->
            val date = monday.plusDays(offset)
            date to (totals(data, date)[Nutrient.KCAL] ?: 0.0)
        }
    }

    // MARK: Rezepte (Meal-Prep)

    fun saveRecipe(data: AppData, recipe: OwnRecipe): AppData {
        val exists = data.recipes.any { it.id == recipe.id }
        return data.copy(recipes = if (exists) data.recipes.map { if (it.id == recipe.id) recipe else it } else data.recipes + recipe)
    }

    fun deleteRecipe(data: AppData, id: String): AppData = data.copy(recipes = data.recipes.filter { it.id != id })

    /** Portion bzw. Menge eines Rezepts eintragen und den Vorrat verringern. */
    fun logRecipe(data: AppData, recipe: OwnRecipe, grams: Double?, category: MealCategory, at: Long): AppData {
        val item = recipe.item(grams)
        val (logged, _) = logCopy(data, recipe.name, listOf(item), category, at)
        return saveRecipe(logged, recipe.consumed(item.grams))
    }

    // MARK: Gewicht

    fun addWeight(data: AppData, day: LocalDate, kilograms: Double): AppData {
        if (kilograms !in 25.0..300.0) return data
        val weights = WeightTrend.merged(data.weights.filter { it.day != day.toString() } + WeightEntry(day.toString(), round1(kilograms)))
        // Das aktuelle Gewicht fließt in die Ziele ein (neueste Wägung).
        val latest = weights.lastOrNull()?.kilograms ?: kilograms
        return data.copy(weights = weights, nutrition = data.nutrition.copy(weightKg = latest))
    }

    fun deleteWeight(data: AppData, day: String): AppData = data.copy(weights = data.weights.filter { it.day != day })

    /** Vorschlag aus dem Gewichtsverlauf übernehmen (Summe auf ±500 kcal begrenzt). */
    fun applyAdjustment(data: AppData, kcal: Double): AppData {
        val total = (data.nutrition.energyAdjustmentKcal + kcal).coerceIn(-500.0, 500.0)
        return data.copy(nutrition = data.nutrition.copy(energyAdjustmentKcal = total))
    }

    // MARK: Ohne Netz

    fun enqueue(data: AppData, pending: PendingAnalysis): AppData = data.copy(pending = (data.pending + pending).takeLast(10))

    fun dequeue(data: AppData, id: String): AppData = data.copy(pending = data.pending.filter { it.id != id })
}
