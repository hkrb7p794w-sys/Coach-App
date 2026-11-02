package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID
import kotlin.math.abs

/** Allergene (Auswahl der kennzeichnungspflichtigen nach EU-LMIV), wie `Allergen` in CoachCore. */
@Serializable
enum class Allergen(val label: String) {
    @SerialName("gluten") GLUTEN("Gluten"),
    @SerialName("lactose") LACTOSE("Laktose / Milch"),
    @SerialName("nuts") NUTS("Schalenfrüchte (Nüsse)"),
    @SerialName("peanuts") PEANUTS("Erdnüsse"),
    @SerialName("egg") EGG("Ei"),
    @SerialName("soy") SOY("Soja"),
    @SerialName("fish") FISH("Fisch"),
    @SerialName("shellfish") SHELLFISH("Krebstiere und Weichtiere"),
    @SerialName("sesame") SESAME("Sesam"),
    ;

    val key: String get() = name.lowercase()
}

@Serializable
data class RecipePreferences(
    val allergens: Set<Allergen> = emptySet(),
    /** Freitext, z. B. „keine Pilze“. */
    val dislikes: String = "",
    val maxMinutes: Int = 30,
    val snacks: Boolean = true,
    val servings: Int = 1,
    val mealPrep: Boolean = false,
)

@Serializable
data class Recipe(
    val id: String = UUID.randomUUID().toString(),
    val meal: MealCategory,
    val title: String,
    val minutes: Int,
    val ingredients: List<MealItem>,
    val steps: List<String>,
) {
    val totals: NutrientMap get() = Nutrition.totals(ingredients)
}

@Serializable
data class RecipeDay(val day: String, val recipes: List<Recipe>, val scale: Double) {
    val totals: NutrientMap get() = Nutrition.totals(recipes.flatMap { it.ingredients })
}

@Serializable
data class WeeklyRecipePlan(val created: Long, val days: List<RecipeDay>, val notes: List<String>) {
    fun day(day: LocalDate): RecipeDay? = days.firstOrNull { it.day == day.toString() }
}

/** Tagesziel eines Tages der kommenden Woche (regelbasiert, aus `NutritionPlanner`). */
data class RecipeDayTarget(val day: LocalDate, val dayType: DayType, val kcal: Double, val protein: Double, val carbs: Double, val fat: Double) {
    companion object {
        fun of(day: LocalDate, targets: Targets) = RecipeDayTarget(
            day, targets.dayType, targets.values[Nutrient.KCAL] ?: 0.0, targets.values[Nutrient.PROTEIN] ?: 0.0,
            targets.values[Nutrient.CARBS] ?: 0.0, targets.values[Nutrient.FAT] ?: 0.0,
        )
    }
}

fun LocalDate.weekdayLong(): String = dayOfWeek.getDisplayName(TextStyle.FULL, Locale.GERMANY)

private fun Diet.key(): String = when (this) {
    Diet.OMNIVORE -> "alles"
    Diet.PESCETARIAN -> "pescetarisch"
    Diet.VEGETARIAN -> "vegetarisch"
    Diet.VEGAN -> "vegan"
}

private fun MealCategory.key(): String = when (this) {
    MealCategory.BREAKFAST -> "fruehstueck"
    MealCategory.LUNCH -> "mittagessen"
    MealCategory.DINNER -> "abendessen"
    MealCategory.SNACK -> "snack"
    MealCategory.OTHER -> "sonstiges"
}

/**
 * Port von `RecipePlanner` (CoachCore): Rezepte der KI lesen, Ernährungsweise und Allergene prüfen (auch versteckte
 * wie Pesto), unstimmige Nährwerte verwerfen, Mengen ans Tagesziel anpassen, Einkaufsliste.
 */
object RecipePlanner {
    val EVIDENCE = listOf("nutrition.energy", "nutrition.carbs", "nutrition.protein", "nutrition.reds")
    private const val SCALE_MIN = 0.75
    private const val SCALE_MAX = 1.33
    private const val TOLERANCE = 0.15

    fun input(days: List<RecipeDayTarget>, preferences: RecipePreferences, diet: Diet, goal: String, gaps: List<String>, favorites: List<String>, evidence: JsonArray): JsonObject =
        buildJsonObject {
            put("days", buildJsonArray {
                days.forEach { target ->
                    add(buildJsonObject {
                        put("datum", target.day.toString())
                        put("wochentag", target.day.weekdayLong())
                        put("training", if (target.dayType == DayType.REST) "frei" else target.dayType.example)
                        put("tagestyp", target.dayType.label)
                        put("kcal", Math.rint(target.kcal))
                        put("protein_g", Math.rint(target.protein))
                        put("kohlenhydrate_g", Math.rint(target.carbs))
                        put("fett_g", Math.rint(target.fat))
                    })
                }
            })
            put("diet", diet.key())
            put("dietLabel", diet.label)
            put("goal", goal)
            put("allergens", buildJsonArray { preferences.allergens.sortedBy { it.key }.forEach { add(JsonPrimitive(it.label)) } })
            put("dislikes", preferences.dislikes.take(200))
            put("maxMinutes", preferences.maxMinutes)
            put("snacks", preferences.snacks)
            put("mealPrep", preferences.mealPrep)
            put("gaps", buildJsonArray { gaps.forEach { add(JsonPrimitive(it)) } })
            put("favorites", buildJsonArray { favorites.take(15).forEach { add(JsonPrimitive(it)) } })
            put("evidence", evidence)
        }

    fun plan(output: JsonElement, targets: List<RecipeDayTarget>, diet: Diet, allergens: Set<Allergen>, bls: Bls?, created: Long): WeeklyRecipePlan? {
        val rawDays = (output as? JsonObject)?.get("tage") as? JsonArray ?: return null
        val notes = mutableListOf<String>()
        val days = mutableListOf<RecipeDay>()
        for (target in targets) {
            val raw = rawDays.firstOrNull { (it as? JsonObject)?.string("datum") == target.day.toString() } as? JsonObject
            val parsed = (raw?.get("gerichte") as? JsonArray).orEmpty().mapNotNull { recipe(it, bls) }
            val kept = parsed.filter { recipe ->
                val problems = violations(recipe, diet, allergens)
                if (problems.isNotEmpty()) {
                    notes.add("„${recipe.title}“ verworfen: enthält ${problems.joinToString(", ")}.")
                    return@filter false
                }
                recipe.ingredients.firstOrNull(::implausible)?.let {
                    notes.add("„${recipe.title}“ verworfen: unstimmige Nährwerte bei „${it.name}“.")
                    return@filter false
                }
                true
            }
            if (kept.isEmpty()) {
                if (parsed.isEmpty()) notes.add("${target.day.weekdayLong()}: keine Rezepte erhalten.")
                continue
            }
            days.add(fit(target, kept, notes))
        }
        if (days.isEmpty()) return null
        return WeeklyRecipePlan(created, days, notes)
    }

    fun recipe(value: JsonElement, bls: Bls?): Recipe? {
        val obj = value as? JsonObject ?: return null
        val title = obj.string("titel")?.takeIf { it.isNotEmpty() } ?: return null
        val raw = obj["zutaten"] as? JsonArray ?: return null
        val items = raw.mapNotNull { MealAnalysis.item(it, bls) }
        if (items.isEmpty() || items.none { (it.per100g[Nutrient.KCAL] ?: 0.0) > 0 }) return null
        val steps = (obj["zubereitung"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }.take(8)
        return Recipe(
            meal = MealCategory.of(obj.string("mahlzeit")) ?: MealCategory.OTHER,
            title = title.take(60),
            minutes = maxOf(obj.number("minuten")?.toInt() ?: 0, 0),
            ingredients = items,
            steps = steps,
        )
    }

    private fun scaledItems(items: List<MealItem>, factor: Double): List<MealItem> =
        items.map { it.copy(grams = maxOf(5.0, Math.rint(it.grams * factor / 5) * 5)) }

    fun fit(target: RecipeDayTarget, recipes: List<Recipe>, notes: MutableList<String>): RecipeDay {
        val total = recipes.sumOf { it.totals[Nutrient.KCAL] ?: 0.0 }
        if (total <= 0 || target.kcal <= 0) return RecipeDay(target.day.toString(), recipes, 1.0)
        val scale = (target.kcal / total).coerceIn(SCALE_MIN, SCALE_MAX)
        val scaled = recipes.map { it.copy(ingredients = scaledItems(it.ingredients, scale)) }
        val result = RecipeDay(target.day.toString(), scaled, Math.rint(scale * 100) / 100)
        val kcal = result.totals[Nutrient.KCAL] ?: 0.0
        if (abs(kcal - target.kcal) / target.kcal > TOLERANCE) {
            notes.add("${target.day.weekdayLong()}: Rezepte ergeben ca. ${Math.rint(kcal).toInt()} statt ${Math.rint(target.kcal).toInt()} kcal – Portionen anpassen.")
        }
        return result
    }

    // Ernährungsweise und Allergene (gleiche Wortlisten wie CoachCore).
    private val meat = listOf("fleisch", "hähnchen", "hühnchen", "huhn", "pute", "truthahn", "rind", "schwein", "speck", "schinken", "salami", "wurst", "würstchen", "hack", "lamm", "kalb", "ente", "chorizo", "bacon", "gyros", "leber")
    private val fish = listOf("fisch", "lachs", "thunfisch", "forelle", "kabeljau", "seelachs", "hering", "makrele", "sardine", "sardelle", "dorsch", "zander", "pangasius", "scholle", "rotbarsch")
    private val shellfish = listOf("garnele", "shrimp", "krabbe", "muschel", "hummer", "scampi", "languste", "krebs", "tintenfisch", "calamari")
    private val dairy = listOf("milch", "joghurt", "quark", "käse", "sahne", "butter", "skyr", "mozzarella", "parmesan", "feta", "schmand", "ricotta", "molke", "kefir", "ghee", "mascarpone", "halloumi", "whey")
    private val plantPrefixes = listOf("hafer", "soja", "mandel", "kokos", "reis", "erbsen", "cashew", "erdnuss", "nuss", "dinkel", "pflanz", "vegan")
    private val gluten = listOf("weizen", "dinkel", "roggen", "gerste", "hafer", "nudel", "pasta", "spaghetti", "penne", "brot", "brötchen", "couscous", "bulgur", "seitan", "mehl", "grieß", "toast", "tortilla", "wrap", "semmel", "lasagne", "gnocchi")
    private val glutenFree = listOf("glutenfrei", "buchweizen", "reismehl", "maismehl", "reisnudel", "glasnudel", "polenta", "kichererbsenmehl", "mandelmehl", "kokosmehl")
    private val nuts = listOf("mandel", "walnuss", "haselnuss", "cashew", "pistazie", "pekannuss", "macadamia", "paranuss", "nüsse", "nuss")
    private val soy = listOf("soja", "tofu", "edamame", "tempeh", "miso")
    private val sesame = listOf("sesam", "tahin")

    private data class Hidden(val keyword: String, val allergens: Set<Allergen>, val animal: String?)

    private val hidden = listOf(
        Hidden("pesto", setOf(Allergen.LACTOSE, Allergen.NUTS), "Milchprodukte"),
        Hidden("worcester", setOf(Allergen.FISH), "Fisch"),
        Hidden("caesar", setOf(Allergen.FISH, Allergen.EGG, Allergen.LACTOSE), "Fisch"),
        Hidden("mayonnaise", setOf(Allergen.EGG), "Ei"),
        Hidden("mayo", setOf(Allergen.EGG), "Ei"),
        Hidden("remoulade", setOf(Allergen.EGG), "Ei"),
        Hidden("aioli", setOf(Allergen.EGG), "Ei"),
        Hidden("marzipan", setOf(Allergen.NUTS), null),
        Hidden("nougat", setOf(Allergen.NUTS, Allergen.LACTOSE), "Milchprodukte"),
        Hidden("praline", setOf(Allergen.NUTS), null),
        Hidden("hummus", setOf(Allergen.SESAME), null),
        Hidden("sojasauce", setOf(Allergen.SOY, Allergen.GLUTEN), null),
        Hidden("sojasoße", setOf(Allergen.SOY, Allergen.GLUTEN), null),
        Hidden("teriyaki", setOf(Allergen.SOY, Allergen.GLUTEN), null),
        Hidden("fischsauce", setOf(Allergen.FISH), "Fisch"),
        Hidden("austernsauce", setOf(Allergen.SHELLFISH), "Fisch"),
        Hidden("milchschokolade", setOf(Allergen.LACTOSE), "Milchprodukte"),
        Hidden("panko", setOf(Allergen.GLUTEN), null),
    )

    private fun words(text: String): List<String> = text.lowercase().split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }

    private fun contains(name: String, keywords: List<String>, except: List<String> = emptyList()): Boolean =
        words(name).any { word -> keywords.any { word.contains(it) } && except.none { word.contains(it) } }

    private fun isEgg(name: String): Boolean = words(name).any { word ->
        word == "ei" || word.startsWith("eier") || word.startsWith("eigelb") || word.startsWith("eiklar") ||
            (word.endsWith("ei") && word.length > 3 && !word.endsWith("brei"))
    }

    private fun isDairy(name: String): Boolean =
        words(name).any { word -> dairy.any { word.contains(it) } && plantPrefixes.none { word.startsWith(it) } }

    /** Was an einer Zutat nicht zu Ernährungsweise oder Allergenen passt. */
    fun violations(name: String, diet: Diet, allergens: Set<Allergen>): List<String> {
        val lower = name.lowercase()
        val result = mutableListOf<String>()
        val plantBased = lower.contains("vegan") || lower.contains("vegetarisch")
        if (!plantBased) {
            if (diet != Diet.OMNIVORE && contains(name, meat, except = listOf("soja", "erbsen", "tofu", "seitan"))) result.add("Fleisch")
            if ((diet == Diet.VEGETARIAN || diet == Diet.VEGAN) && (contains(name, fish) || contains(name, shellfish))) result.add("Fisch")
            if (diet == Diet.VEGAN) {
                if (isEgg(name)) result.add("Ei")
                if (isDairy(name)) result.add("Milchprodukte")
                if (contains(name, listOf("honig"))) result.add("Honig")
            }
        }
        for (item in hidden.filter { lower.contains(it.keyword) }) {
            val animal = item.animal
            if (animal != null && !plantBased) {
                val conflict = if (animal == "Fisch") diet == Diet.VEGETARIAN || diet == Diet.VEGAN else diet == Diet.VEGAN
                if (conflict) result.add(animal)
            }
            item.allergens.sortedBy { it.key }.filter { it in allergens }.forEach { result.add(it.label) }
        }
        for (allergen in allergens.sortedBy { it.key }) {
            val hit = when (allergen) {
                Allergen.GLUTEN -> contains(name, gluten) && glutenFree.none { lower.contains(it) }
                Allergen.LACTOSE -> isDairy(name) && !lower.contains("laktosefrei")
                Allergen.NUTS -> contains(name, nuts, except = listOf("erdnuss", "muskatnuss", "kokosnuss"))
                Allergen.PEANUTS -> lower.contains("erdnuss")
                Allergen.EGG -> isEgg(name)
                Allergen.SOY -> contains(name, soy)
                Allergen.FISH -> contains(name, fish)
                Allergen.SHELLFISH -> contains(name, shellfish)
                Allergen.SESAME -> contains(name, sesame)
            }
            if (hit) result.add(allergen.label)
        }
        return result.distinct()
    }

    fun violations(recipe: Recipe, diet: Diet, allergens: Set<Allergen>): List<String> =
        recipe.ingredients.flatMap { violations(it.name, diet, allergens) }.distinct()

    /** Unstimmige Nährwerte je 100 g (mehr als 900 kcal, Makros über 100 g bzw. zusammen über 105 g, kcal ≠ Makros). */
    fun implausible(item: MealItem): Boolean {
        val kcal = item.per100g[Nutrient.KCAL] ?: 0.0
        val protein = item.per100g[Nutrient.PROTEIN]
        val carbs = item.per100g[Nutrient.CARBS]
        val fat = item.per100g[Nutrient.FAT]
        if (kcal > 900 || kcal < 0) return true
        if (listOfNotNull(protein, carbs, fat).any { it > 100 || it < 0 }) return true
        if ((protein ?: 0.0) + (carbs ?: 0.0) + (fat ?: 0.0) > 105) return true
        if (protein != null && carbs != null && fat != null) {
            val fromMacros = 4 * protein + 4 * carbs + 9 * fat
            if (abs(kcal - fromMacros) > maxOf(0.25 * maxOf(kcal, fromMacros), 40.0)) return true
        }
        return false
    }

    /** Nährstoffe, die im Schnitt unter 80 % des Ziels lagen (mindestens 3 Tage mit Einträgen). */
    fun gaps(dailyTotals: List<NutrientMap>, targets: NutrientMap): List<String> {
        if (dailyTotals.size < 3) return emptyList()
        val watched = listOf(Nutrient.PROTEIN, Nutrient.FIBER, Nutrient.OMEGA3, Nutrient.CALCIUM, Nutrient.IRON, Nutrient.IODINE, Nutrient.MAGNESIUM)
        return watched.mapNotNull { nutrient ->
            val target = targets[nutrient]?.takeIf { it > 0 } ?: return@mapNotNull null
            val average = dailyTotals.sumOf { it[nutrient] ?: 0.0 } / dailyTotals.size
            if (average >= 0.8 * target) return@mapNotNull null
            "${nutrient.label}: im Schnitt ${Math.rint(average).toInt()} von ${Math.rint(target).toInt()} ${nutrient.unit} (${Math.rint(average / target * 100).toInt()} %)"
        }
    }

    data class ShoppingItem(val name: String, val grams: Double, val group: String?) {
        val aisle: ShoppingAisle get() = ShoppingAisle.of(name, group)
    }

    /** Einkaufsliste: gleiche Zutaten zusammengefasst, für `servings` Personen, auf 5 g gerundet. */
    fun shoppingList(plan: WeeklyRecipePlan, servings: Int): List<ShoppingItem> {
        val sums = linkedMapOf<String, ShoppingItem>()
        for (item in plan.days.flatMap { it.recipes }.flatMap { it.ingredients }) {
            val key = item.name.lowercase().trim()
            val current = sums[key] ?: ShoppingItem(item.name, 0.0, item.group)
            sums[key] = current.copy(grams = current.grams + item.grams * maxOf(servings, 1), group = current.group ?: item.group)
        }
        return sums.values.map { it.copy(grams = Math.rint(it.grams / 5) * 5) }.sortedBy { it.name.lowercase() }
    }
}

/** Einkaufsliste nach Supermarkt-Abteilung (wie `ShoppingAisle` in CoachCore). */
enum class ShoppingAisle(val label: String) {
    PRODUCE("Obst und Gemüse"),
    COOLED("Kühlregal"),
    MEAT_FISH("Fleisch und Fisch"),
    BAKERY("Brot und Backwaren"),
    DRY("Nudeln, Reis, Hülsenfrüchte, Nüsse"),
    SPICES("Öl, Gewürze, Saucen"),
    FROZEN("Tiefkühl"),
    DRINKS("Getränke"),
    OTHER("Sonstiges"),
    ;

    companion object {
        fun of(name: String, group: String?): ShoppingAisle = when (group) {
            "gemuese", "obst" -> PRODUCE
            "milch", "ei" -> COOLED
            "fleisch", "fisch", "fisch_fett" -> MEAT_FISH
            "vollkorn", "getreide", "kartoffel", "huelsenfruechte", "nuesse" -> byName(name) ?: DRY
            "fett" -> SPICES
            "getraenk", "alkohol" -> DRINKS
            else -> byName(name) ?: OTHER
        }

        private fun byName(name: String): ShoppingAisle? {
            val lower = FoodSearch.normalized(name)
            if (listOf("brot", "broetchen", "toast", "wrap", "tortilla").any { lower.contains(it) }) return BAKERY
            if (listOf("tiefkuehl", "tk-", "gefroren").any { lower.contains(it) }) return FROZEN
            if (listOf("oel", "salz", "pfeffer", "gewuerz", "sauce", "sosse", "essig", "bruehe", "senf", "honig").any { lower.contains(it) }) return SPICES
            return null
        }
    }
}

/** „Was esse ich jetzt?“ – drei Vorschläge passend zum Rest des Tages (Port von `MealNow`). */
object MealNow {
    const val MAXIMUM_KCAL = 900.0
    const val MINIMUM_KCAL = 150.0

    fun targetKcal(remaining: Double): Double? = if (remaining < MINIMUM_KCAL) null else minOf(remaining, MAXIMUM_KCAL)

    fun input(remaining: NutrientMap, category: MealCategory, diet: Diet, preferences: RecipePreferences, favorites: List<String>): JsonObject {
        val kcal = targetKcal(remaining[Nutrient.KCAL] ?: 0.0) ?: MINIMUM_KCAL
        val share = kcal / maxOf(remaining[Nutrient.KCAL] ?: kcal, kcal)
        fun grams(nutrient: Nutrient) = maxOf(0.0, Math.rint((remaining[nutrient] ?: 0.0) * share))
        return buildJsonObject {
            put("mahlzeit", category.key())
            put("kcal", Math.rint(kcal))
            put("protein_g", grams(Nutrient.PROTEIN))
            put("carbs_g", grams(Nutrient.CARBS))
            put("fat_g", grams(Nutrient.FAT))
            put("diet", diet.key())
            put("allergens", buildJsonArray { preferences.allergens.sortedBy { it.key }.forEach { add(JsonPrimitive(it.label)) } })
            put("dislikes", preferences.dislikes.take(200))
            put("maxMinutes", preferences.maxMinutes)
            put("pantry", buildJsonArray {})
            put("favorites", buildJsonArray { favorites.take(15).forEach { add(JsonPrimitive(it)) } })
        }
    }

    /** Antwort `{"gerichte": [...]}` prüfen und auf das Ziel skalieren (Faktor 0,5–1,6, auf 5 g gerundet). */
    fun suggestions(output: JsonElement, targetKcal: Double, diet: Diet, allergens: Set<Allergen>, bls: Bls?): Pair<List<Recipe>, List<String>> {
        val notes = mutableListOf<String>()
        val raw = ((output as? JsonObject)?.get("gerichte") as? JsonArray).orEmpty()
        val recipes = raw.mapNotNull { RecipePlanner.recipe(it, bls) }.mapNotNull { recipe ->
            val problems = RecipePlanner.violations(recipe, diet, allergens)
            if (problems.isNotEmpty()) {
                notes.add("„${recipe.title}“ verworfen: enthält ${problems.joinToString(", ")}.")
                return@mapNotNull null
            }
            recipe.ingredients.firstOrNull(RecipePlanner::implausible)?.let {
                notes.add("„${recipe.title}“ verworfen: unstimmige Nährwerte bei „${it.name}“.")
                return@mapNotNull null
            }
            scaled(recipe, targetKcal)
        }
        return recipes.take(3) to notes
    }

    fun scaled(recipe: Recipe, kcal: Double): Recipe {
        val total = recipe.totals[Nutrient.KCAL] ?: 0.0
        if (total <= 0 || kcal <= 0) return recipe
        val factor = (kcal / total).coerceIn(0.5, 1.6)
        return recipe.copy(ingredients = recipe.ingredients.map { it.copy(grams = maxOf(5.0, Math.rint(it.grams * factor / 5) * 5)) })
    }
}

/** Eigenes Rezept für Meal-Prep: Zutaten für den ganzen Topf, gekochtes Gewicht, Portionen, Vorrat. */
@Serializable
data class OwnRecipe(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val ingredients: List<MealItem>,
    /** Gewicht des fertigen Gerichts; `null` = Summe der Zutaten. */
    val cookedGrams: Double? = null,
    val portions: Int = 1,
    /** Noch übrige Portionen vom letzten Kochen; `null` = kein Vorrat. */
    val remainingPortions: Double? = null,
) {
    val totalGrams: Double get() = cookedGrams?.takeIf { it > 0 } ?: ingredients.sumOf { it.grams }
    val totals: NutrientMap get() = Nutrition.totals(ingredients)
    val per100g: NutrientMap get() = if (totalGrams <= 0) emptyMap() else totals.scaled(100 * 100 / totalGrams)
    val portionGrams: Double get() = totalGrams / maxOf(portions, 1)

    fun item(grams: Double? = null): MealItem = MealItem(
        name = name, grams = grams ?: portionGrams, source = FoodSource.MANUAL, per100g = per100g,
        portion = Portion("Portion", round1(portionGrams)),
    )

    /** Nach dem Eintragen: Vorrat um die gegessene Menge verringern. */
    fun consumed(grams: Double): OwnRecipe {
        val remaining = remainingPortions ?: return this
        if (totalGrams <= 0) return this
        return copy(remainingPortions = maxOf(0.0, round1(remaining - grams / portionGrams)))
    }

    companion object {
        fun from(title: String, items: List<MealItem>) = OwnRecipe(name = title, ingredients = items.map(MealPortion::restored), portions = 1)
    }
}
