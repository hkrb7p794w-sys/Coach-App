package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Ernährung wie in der iPhone-App (CoachCore `Nutrition/`): gleiche Nährstoff-Schlüssel und Einheiten, damit
 * BLS-Tabelle, KI-Antworten des Workers und Open Food Facts ohne Umrechnung passen.
 */
enum class Nutrient(val key: String, val label: String, val unit: String) {
    KCAL("kcal", "Kalorien", "kcal"),
    PROTEIN("protein_g", "Protein", "g"),
    CARBS("carbs_g", "Kohlenhydrate", "g"),
    SUGAR("sugar_g", "davon Zucker", "g"),
    FAT("fat_g", "Fett", "g"),
    SATURATED_FAT("satfat_g", "davon gesättigt", "g"),
    FIBER("fiber_g", "Ballaststoffe", "g"),
    WATER("water_ml", "Flüssigkeit", "ml"),
    SODIUM("sodium_mg", "Natrium", "mg"),
    POTASSIUM("potassium_mg", "Kalium", "mg"),
    MAGNESIUM("magnesium_mg", "Magnesium", "mg"),
    CALCIUM("calcium_mg", "Calcium", "mg"),
    IRON("iron_mg", "Eisen", "mg"),
    ZINC("zinc_mg", "Zink", "mg"),
    VITAMIN_D("vitd_ug", "Vitamin D", "µg"),
    VITAMIN_B12("b12_ug", "Vitamin B12", "µg"),
    VITAMIN_C("vitc_mg", "Vitamin C", "mg"),
    IODINE("iodine_ug", "Jod", "µg"),
    OMEGA3("omega3_mg", "Omega-3 (EPA+DHA)", "mg"),
    ;

    val isMacro: Boolean get() = this in setOf(KCAL, PROTEIN, CARBS, SUGAR, FAT, SATURATED_FAT, FIBER)

    /** Obergrenze statt Mindestziel (Zucker, gesättigte Fette) bzw. nur Referenz (Natrium). */
    val isUpperLimit: Boolean get() = this == SUGAR || this == SATURATED_FAT || this == SODIUM

    companion object {
        private val byKey = entries.associateBy { it.key }
        fun of(key: String): Nutrient? = byKey[key]
    }
}

/** Nährwerte als Schlüssel → Menge (Schlüssel wie `Nutrient.key`). Fehlende Werte sind unbekannt, nicht 0. */
typealias NutrientMap = Map<String, Double>

operator fun NutrientMap.get(nutrient: Nutrient): Double? = this[nutrient.key]

fun NutrientMap.scaled(grams: Double): NutrientMap = mapValues { it.value * grams / 100 }

fun NutrientMap.plus(other: NutrientMap): NutrientMap {
    val result = toMutableMap()
    for ((key, value) in other) result[key] = (result[key] ?: 0.0) + value
    return result
}

fun nutrients(vararg pairs: Pair<Nutrient, Double>): NutrientMap = pairs.associate { it.first.key to it.second }

@Serializable
enum class MealCategory(val label: String) {
    @SerialName("fruehstueck")
    BREAKFAST("Frühstück"),

    @SerialName("mittagessen")
    LUNCH("Mittagessen"),

    @SerialName("abendessen")
    DINNER("Abendessen"),

    @SerialName("snack")
    SNACK("Snack"),

    @SerialName("sonstiges")
    OTHER("Sonstiges"),
    ;

    companion object {
        /** Kategorie nach Uhrzeit (wie `MealCategory.guess` in CoachCore). */
        fun guess(hour: Int, minute: Int): MealCategory {
            val time = hour + minute / 60.0
            return when {
                time >= 4 && time < 10.5 -> BREAKFAST
                time >= 10.5 && time < 14.5 -> LUNCH
                time >= 17.5 && time < 21.5 -> DINNER
                else -> SNACK
            }
        }

        fun of(raw: String?): MealCategory? = when (raw) {
            "fruehstueck" -> BREAKFAST
            "mittagessen" -> LUNCH
            "abendessen" -> DINNER
            "snack" -> SNACK
            "sonstiges" -> OTHER
            else -> null
        }
    }
}

/** Portion eines Lebensmittels: „Scheibe“ à 30 g. */
@Serializable
data class Portion(val name: String, val grams: Double)

@Serializable
enum class FoodSource(val label: String) {
    @SerialName("KI")
    AI("KI"),

    @SerialName("Open Food Facts")
    OPEN_FOOD_FACTS("Open Food Facts"),

    @SerialName("Eigene Angabe")
    MANUAL("Eigene Angabe"),

    @SerialName("BLS 4.0")
    BLS("BLS 4.0"),
}

/** Eine Position einer Mahlzeit. */
@Serializable
data class MealItem(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val grams: Double,
    val source: FoodSource,
    val per100g: NutrientMap = emptyMap(),
    val amountText: String? = null,
    val isDrink: Boolean = false,
    /** `hoch`, `mittel`, `niedrig` (Einschätzung der KI). */
    val confidence: String? = null,
    val barcode: String? = null,
    val portion: Portion? = null,
    val blsCode: String? = null,
    /** Generische Bezeichnung der KI für die Suche im BLS. */
    val searchTerm: String? = null,
    /** Menge vor einer Portionsanpassung; `null` = nie angepasst. */
    val plannedGrams: Double? = null,
    /** Lebensmittelgruppe der KI (`gemuese`, `milch` …) für die Einkaufsliste. */
    val group: String? = null,
) {
    val amounts: NutrientMap get() = per100g.scaled(grams)

    val portionCount: Double? get() = portion?.takeIf { it.grams > 0 }?.let { grams / it.grams }

    fun withPortions(count: Double): MealItem {
        val portion = portion?.takeIf { it.grams > 0 } ?: return this
        return copy(grams = maxOf(0.0, round1(count * portion.grams)))
    }

    /** „2 × Scheibe (60 g)“ bzw. „150 g“. */
    val amountLabel: String
        get() {
            val unit = if (isDrink) "ml" else "g"
            val count = portionCount
            if (portion == null || count == null) return "${German.number(grams)} $unit"
            return "${PortionGuess.format(count)} × ${portion.name} (${German.number(Math.rint(grams))} $unit)"
        }

    val isQuickEstimate: Boolean get() = source == FoodSource.MANUAL && amountText == "Schätzung"

    companion object {
        /** Schnell-Eintrag ohne Lebensmittel: Werte gelten für die ganze Portion (100 g „Portion“). */
        fun quick(name: String = "Schnell-Eintrag", kcal: Double, protein: Double? = null, carbs: Double? = null, fat: Double? = null): MealItem {
            val values = mutableMapOf(Nutrient.KCAL.key to maxOf(kcal, 0.0))
            protein?.let { values[Nutrient.PROTEIN.key] = maxOf(it, 0.0) }
            carbs?.let { values[Nutrient.CARBS.key] = maxOf(it, 0.0) }
            fat?.let { values[Nutrient.FAT.key] = maxOf(it, 0.0) }
            return MealItem(name = name, grams = 100.0, source = FoodSource.MANUAL, per100g = values, amountText = "Schätzung", confidence = "niedrig")
        }

        /** Wasser in ml (1 ml ≈ 1 g). */
        fun water(milliliters: Double) =
            MealItem(name = "Wasser", grams = milliliters, source = FoodSource.MANUAL, per100g = nutrients(Nutrient.WATER to 100.0), isDrink = true)
    }
}

@Serializable
data class Meal(
    val id: String = UUID.randomUUID().toString(),
    /** Millisekunden seit 1970. */
    val createdAt: Long,
    /** Kalendertag (yyyy-MM-dd) in Ortszeit beim Eintragen. */
    val day: String,
    val category: MealCategory,
    val title: String,
    val hint: String = "",
    val items: List<MealItem>,
) {
    val totals: NutrientMap get() = Nutrition.totals(items)
}

/** Als Favorit gespeicherte Mahlzeit (Vorlage; Eintragen legt eine Kopie an). */
@Serializable
data class FavoriteMeal(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val items: List<MealItem>,
    val category: MealCategory? = null,
) {
    val signature: String get() = MealSuggestions.signature(items)
}

object Nutrition {
    fun totals(items: List<MealItem>): NutrientMap = items.fold(emptyMap()) { sum, item -> sum.plus(item.amounts) }

    fun dayKey(millis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        Instant.ofEpochMilli(millis).atZone(zone).toLocalDate().toString()

    fun meals(day: LocalDate, meals: List<Meal>): List<Meal> =
        meals.filter { it.day == day.toString() }.sortedBy { it.createdAt }
}

internal fun round1(value: Double): Double = (value * 10).roundToLong() / 10.0

/** Deutsche Zahlen ohne unnötige Nachkommastellen. */
object German {
    fun number(value: Double, decimals: Int = 1): String {
        val factor = Math.pow(10.0, decimals.toDouble())
        val rounded = Math.rint(value * factor) / factor
        val text = if (rounded == Math.floor(rounded)) rounded.toLong().toString() else rounded.toString()
        return text.replace('.', ',')
    }
}

/** Suche: Kleinbuchstaben, Umlaute ausgeschrieben, Akzente entfernt („muesli“ findet „Müsli“). */
object FoodSearch {
    fun normalized(text: String): String {
        val replaced = text.lowercase()
            .replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
        return Normalizer.normalize(replaced, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").trim()
    }

    data class Candidate(val id: String, val title: String, val useCount: Int, val lastUsed: Long, val item: MealItem)

    fun rank(candidates: List<Candidate>, query: String, limit: Int = 12): List<Candidate> {
        val words = normalized(query).split(" ").filter { it.isNotEmpty() }
        if (words.isEmpty()) return emptyList()
        return candidates.mapNotNull { candidate ->
            val title = normalized(candidate.title)
            if (!words.all { title.contains(it) }) return@mapNotNull null
            val titleWords = title.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
            val prefixHits = words.count { word -> titleWords.any { it.startsWith(word) } }
            val starts = if (title.startsWith(words[0])) 2 else 0
            candidate to starts + prefixHits
        }.sortedWith(
            compareByDescending<Pair<Candidate, Int>> { it.second }.thenByDescending { it.first.useCount }.thenByDescending { it.first.lastUsed },
        ).take(limit).map { it.first }
    }

    /** Eigene frühere Lebensmittel (letzte Verwendung je Name) als Suchkandidaten. */
    fun ownFoods(meals: List<Meal>): List<Candidate> {
        val byName = linkedMapOf<String, Candidate>()
        for (meal in meals.sortedByDescending { it.createdAt }) {
            for (item in meal.items) {
                if (item.isQuickEstimate || item.name == "Wasser") continue
                val key = normalized(item.name)
                val existing = byName[key]
                byName[key] = existing?.copy(useCount = existing.useCount + 1)
                    ?: Candidate(key, item.name, 1, meal.createdAt, MealPortion.restored(item))
            }
        }
        return byName.values.toList()
    }
}

/** Schnell eintragen: häufige Mahlzeiten, „wie gestern“, zuletzt erfasst. */
object MealSuggestions {
    data class Suggestion(val id: String, val title: String, val category: MealCategory, val items: List<MealItem>, val count: Int, val lastDate: Long) {
        val kcal: Double get() = Nutrition.totals(items)[Nutrient.KCAL] ?: 0.0
    }

    /** Gleiche Mahlzeit = gleiche Lebensmittel mit etwa gleicher Menge (auf 10 g gerundet). */
    fun signature(items: List<MealItem>): String =
        items.map { "${FoodSearch.normalized(it.name)}@${Math.rint(it.grams / 10).toInt()}" }.sorted().joinToString("|")

    fun frequent(meals: List<Meal>, category: MealCategory, today: LocalDate, lookbackDays: Long = 60, limit: Int = 5): List<Suggestion> {
        val start = today.minusDays(lookbackDays)
        val todayKey = today.toString()
        val loggedToday = meals.filter { it.day == todayKey && it.category == category }.map { signature(it.items) }.toSet()
        val groups = linkedMapOf<String, Suggestion>()
        for (meal in meals) {
            val day = LocalDate.parse(meal.day)
            if (meal.category != category || day < start || day >= today || meal.items.isEmpty()) continue
            val key = signature(meal.items)
            if (key in loggedToday) continue
            val existing = groups[key]
            groups[key] = when {
                existing == null -> Suggestion(key, meal.title, category, meal.items, 1, meal.createdAt)
                meal.createdAt > existing.lastDate -> existing.copy(count = existing.count + 1, lastDate = meal.createdAt, title = meal.title, items = meal.items)
                else -> existing.copy(count = existing.count + 1)
            }
        }
        return groups.values.sortedWith(compareByDescending<Suggestion> { it.count }.thenByDescending { it.lastDate }).take(limit)
    }

    fun yesterday(meals: List<Meal>, category: MealCategory, today: LocalDate): List<Meal> {
        val key = today.minusDays(1).toString()
        return meals.filter { it.day == key && it.category == category }.sortedBy { it.createdAt }
    }

    /** Zuletzt erfasste Mahlzeiten, jede Zusammenstellung nur einmal. */
    fun recent(meals: List<Meal>, limit: Int = 8): List<Meal> {
        val seen = mutableSetOf<String>()
        return meals.sortedByDescending { it.createdAt }.filter { it.items.isNotEmpty() }
            .filter { seen.add(signature(it.items.map(MealPortion::restored))) }
            .take(limit)
    }

    /** Häufigste Mahlzeiten über alle Kategorien (mindestens zweimal gegessen). */
    fun frequentAll(meals: List<Meal>, today: LocalDate, limit: Int = 8): List<Suggestion> {
        val merged = linkedMapOf<String, Suggestion>()
        for (category in MealCategory.entries) {
            for (suggestion in frequent(meals, category, today.plusDays(1), limit = limit)) {
                val existing = merged[suggestion.id]
                merged[suggestion.id] = existing?.copy(count = existing.count + suggestion.count) ?: suggestion
            }
        }
        return merged.values.filter { it.count >= 2 }.sortedWith(compareByDescending<Suggestion> { it.count }.thenByDescending { it.lastDate }).take(limit)
    }
}

/** Nachträglich weniger oder mehr gegessen: Mengen anteilig ändern, ursprüngliche Menge bleibt gespeichert. */
object MealPortion {
    val presets = listOf(0.25, 0.5, 0.75, 1.0)

    fun eatenFraction(items: List<MealItem>): Double {
        val planned = items.sumOf { it.plannedGrams ?: it.grams }
        return if (planned <= 0) 1.0 else items.sumOf { it.grams } / planned
    }

    fun adjusted(items: List<MealItem>, fraction: Double): List<MealItem> {
        val value = fraction.coerceIn(0.05, 3.0)
        return items.map { item ->
            val base = item.plannedGrams ?: item.grams
            item.copy(grams = round1(base * value), plannedGrams = if (abs(value - 1) < 0.001) null else base)
        }
    }

    fun restored(item: MealItem): MealItem = item.copy(grams = item.plannedGrams ?: item.grams, plannedGrams = null)
}

/** Was heute noch übrig ist („noch 62 g Protein“). */
object NutritionBudget {
    data class Line(val nutrient: Nutrient, val actual: Double, val target: Double) {
        val remaining: Double get() = target - actual
        val progress: Double get() = if (target > 0) minOf(actual / target, 1.0) else 0.0
        val isOver: Boolean
            get() = if (nutrient.isUpperLimit) actual > target else actual > target * (if (nutrient == Nutrient.KCAL) 1.1 else 1.25)
    }

    val main = listOf(Nutrient.PROTEIN, Nutrient.CARBS, Nutrient.FAT)

    fun line(nutrient: Nutrient, targets: NutrientMap, totals: NutrientMap): Line? {
        val target = targets[nutrient]?.takeIf { it > 0 } ?: return null
        return Line(nutrient, totals[nutrient] ?: 0.0, target)
    }

    fun remainingText(line: Line): String {
        val amount = Math.rint(abs(line.remaining)).toInt()
        return if (line.remaining >= 0) "noch $amount ${line.nutrient.unit}" else "$amount ${line.nutrient.unit} drüber"
    }
}

object PortionGuess {
    private val massUnits = setOf("g", "gramm", "kg", "ml", "l", "liter", "mg", "cl")
    private val singular = mapOf(
        "scheiben" to "Scheibe", "stück" to "Stück", "stücke" to "Stück", "eier" to "Ei", "gläser" to "Glas", "tassen" to "Tasse",
        "becher" to "Becher", "portionen" to "Portion", "riegel" to "Riegel", "brötchen" to "Brötchen", "packungen" to "Packung",
        "dosen" to "Dose", "flaschen" to "Flasche", "bananen" to "Banane", "äpfel" to "Apfel", "esslöffel" to "EL", "el" to "EL",
        "teelöffel" to "TL", "tl" to "TL", "handvoll" to "Handvoll", "schalen" to "Schale", "schüsseln" to "Schüssel",
        "teller" to "Teller", "kugeln" to "Kugel", "würfel" to "Würfel", "beutel" to "Beutel", "kapseln" to "Kapsel",
    )
    private val words = mapOf("ein" to 1.0, "eine" to 1.0, "einen" to 1.0, "zwei" to 2.0, "drei" to 3.0, "vier" to 4.0, "halbe" to 0.5)

    val quickCounts = listOf(0.5, 1.0, 1.5, 2.0)

    /** Aus „2 Scheiben“ und 60 g → Scheibe à 30 g. Reine Gewichtsangaben ergeben nichts. */
    fun from(amountText: String?, grams: Double): Portion? {
        val text = amountText?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (grams <= 0) return null
        val parts = text.replace("(", " ").split(" ").filter { it.isNotEmpty() }
        if (parts.size < 2) return null
        val count = number(parts[0])?.takeIf { it > 0 } ?: return null
        val unit = parts[1].trim { !it.isLetterOrDigit() }
        if (unit.isEmpty() || unit.lowercase() in massUnits || !unit.first().isLetter()) return null
        return Portion(singular[unit.lowercase()] ?: unit, round1(grams / count))
    }

    fun serving(text: String?, grams: Double?): Portion? {
        val value = grams?.takeIf { it > 0 } ?: return null
        return from(text, value) ?: Portion("Portion", value)
    }

    private fun number(text: String): Double? {
        val lower = text.lowercase()
        words[lower]?.let { return it }
        if (lower == "½") return 0.5
        if (lower.endsWith("½")) lower.dropLast(1).toDoubleOrNull()?.let { return it + 0.5 }
        return lower.replace(',', '.').toDoubleOrNull()
    }

    /** 0,5 → „½“, 1,5 → „1½“, 2 → „2“. */
    fun format(count: Double): String {
        val rounded = Math.rint(count * 100) / 100
        val whole = Math.floor(rounded)
        if (abs(rounded - whole - 0.5) < 0.01) return if (whole == 0.0) "½" else "${whole.toInt()}½"
        return German.number(rounded, 2)
    }
}

/**
 * Flüssigkeit des Tages wie `Hydration` in CoachCore: Getränke und Wasser aus Lebensmitteln. Getränke ohne
 * Wasserangabe zählen mit ihrer Menge (1 ml ≈ 1 g), Lebensmittel ohne Angabe gar nicht.
 */
object Hydration {
    data class Total(val drinks: Double = 0.0, val food: Double = 0.0) {
        val total: Double get() = drinks + food
    }

    fun milliliters(item: MealItem): Double {
        item.per100g[Nutrient.WATER]?.let { return maxOf(0.0, it) * item.grams / 100 }
        return if (item.isDrink) maxOf(0.0, item.grams) else 0.0
    }

    fun total(items: List<MealItem>): Total = items.fold(Total()) { sum, item ->
        if (item.isDrink) sum.copy(drinks = sum.drinks + milliliters(item)) else sum.copy(food = sum.food + milliliters(item))
    }
}
