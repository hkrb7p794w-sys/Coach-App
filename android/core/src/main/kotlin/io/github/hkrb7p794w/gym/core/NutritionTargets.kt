package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/** Tagestyp für die Ernährungsziele (wie `DayType` in CoachCore). */
@Serializable
enum class DayType(val label: String, val carbsPerKg: Double, val minimumCarbsPerKg: Double, val plannedMinutes: Double, val goalScale: Double) {
    @SerialName("ruhetag")
    REST("Ruhetag", 3.0, 3.0, 0.0, 1.0),

    @SerialName("leicht")
    LIGHT("Leichter Tag", 4.0, 3.0, 45.0, 1.0),

    @SerialName("moderat")
    MODERATE("Moderater Trainingstag", 6.0, 5.0, 60.0, 0.5),

    @SerialName("hart")
    HARD("Harter Trainingstag", 8.0, 6.0, 90.0, 0.0),

    @SerialName("sehr_hart")
    VERY_HARD("Sehr harter Trainingstag", 10.0, 8.0, 180.0, 0.0),
    ;

    /** MET der geplanten Einheit (Ainsworth 2011): Kraft etwa 5, Ausdauer etwa 7. */
    val plannedMet: Double get() = if (this == LIGHT) 5.0 else 7.0

    /** Kurzbeschreibung für die Auswahl auf Android (ohne Garmin bestimmt die Person den Tagestyp). */
    val example: String
        get() = when (this) {
            REST -> "kein Training"
            LIGHT -> "Krafttraining oder kurze lockere Einheit"
            MODERATE -> "etwa 1 Stunde Ausdauer"
            HARD -> "1,5 Stunden oder intensive Einheit"
            VERY_HARD -> "3 Stunden und mehr"
        }
}

@Serializable
enum class NutritionGoal(val label: String, val adjustPercent: Double, val proteinPerKg: Double) {
    @SerialName("halten")
    MAINTAIN("Gewicht halten", 0.0, 1.8),

    @SerialName("abnehmen")
    LOSE("Abnehmen", -15.0, 2.2),

    @SerialName("aufbauen")
    GAIN("Aufbauen", 10.0, 2.0),

    @SerialName("umformen")
    RECOMPOSITION("Umformen (Fett ab, Muskeln auf)", -5.0, 2.0),
}

@Serializable
enum class Diet(val label: String) {
    @SerialName("alles")
    OMNIVORE("Alles"),

    @SerialName("pescetarisch")
    PESCETARIAN("Pescetarisch"),

    @SerialName("vegetarisch")
    VEGETARIAN("Vegetarisch"),

    @SerialName("vegan")
    VEGAN("Vegan"),
}

/** Körperwerte und Ziel. Ohne Garmin trägt die Person sie selbst ein (Standard wie `BodyProfile.fallback`). */
@Serializable
data class NutritionSettings(
    val weightKg: Double = 75.0,
    val heightCm: Double = 180.0,
    val age: Int = 35,
    val isFemale: Boolean = false,
    /** Aktivitätsfaktor ohne Sport (PAL). */
    val activityFactor: Double = 1.4,
    val bodyFatPercent: Double? = null,
    val goal: NutritionGoal = NutritionGoal.MAINTAIN,
    val diet: Diet = Diet.OMNIVORE,
    /** Gewünschte Gewichtsänderung in % pro Woche (negativ = abnehmen); hat Vorrang vor dem Ziel-Prozentsatz. */
    val weeklyChangePercent: Double? = null,
    /** Einmal ausgefüllt: sonst fragt die App beim ersten Öffnen nach den Körperwerten. */
    val configured: Boolean = false,
    /** Übernommene Anpassung aus dem Gewichtsverlauf (kcal pro Tag, ±500). */
    val energyAdjustmentKcal: Double = 0.0,
    /** Zielgewicht für die Prognose (optional). */
    val targetWeightKg: Double? = null,
) {
    companion object {
        /** Schutzgrenzen wie `GoalRules` in CoachCore: höchstens 1 % Abnahme, 0,5 % Zunahme pro Woche. */
        fun safeWeeklyChange(percent: Double): Double = percent.coerceIn(-1.0, 0.5)
    }
}

data class Targets(
    val values: NutrientMap,
    val dayType: DayType,
    val basalMetabolicRate: Double,
    val exerciseKcal: Double,
    val proteinPerKg: Double,
    /** Energie auf 30 kcal/kg fettfreie Masse angehoben (REDs-Schwelle). */
    val energyFloorApplied: Boolean,
)

/**
 * Port von `NutritionPlanner.compute` (CoachCore) für Tage ohne Garmin-Aktivitäten: Mifflin-St Jeor × PAL plus
 * Netto-Verbrauch der geplanten Einheit nach Tagestyp; Kohlenhydrate nach Thomas et al. 2016, Protein nach Ziel,
 * Fett 20–35 %, Energie nie unter 30 kcal/kg fettfreie Masse (IOC REDs 2023), Mikronährstoffe nach DGE.
 */
object NutritionPlanner {
    fun mifflinStJeor(settings: NutritionSettings): Double =
        10 * settings.weightKg + 6.25 * settings.heightCm - 5 * settings.age + if (settings.isFemale) -161 else 5

    private fun micro(isFemale: Boolean): Map<Nutrient, Double> = mapOf(
        Nutrient.SODIUM to 1500.0, Nutrient.POTASSIUM to 4000.0, Nutrient.MAGNESIUM to if (isFemale) 300.0 else 350.0,
        Nutrient.CALCIUM to 1000.0, Nutrient.IRON to if (isFemale) 16.0 else 11.0, Nutrient.ZINC to if (isFemale) 8.0 else 14.0,
        Nutrient.VITAMIN_D to 20.0, Nutrient.VITAMIN_B12 to 4.0, Nutrient.VITAMIN_C to if (isFemale) 95.0 else 110.0,
        Nutrient.FIBER to 30.0, Nutrient.IODINE to 150.0, Nutrient.OMEGA3 to 250.0,
    )

    fun compute(settings: NutritionSettings, dayType: DayType): Targets {
        val weight = settings.weightKg
        val bmr = mifflinStJeor(settings)
        val baseKcal = bmr * settings.activityFactor
        // Netto-Verbrauch der geplanten Einheit: (MET − 1) × kg × Stunden.
        val exerciseKcal = (dayType.plannedMet - 1) * weight * dayType.plannedMinutes / 60
        val dayEnergy = baseKcal + exerciseKcal
        var adjustPercent = settings.goal.adjustPercent
        val weekly = settings.weeklyChangePercent
        if (weekly != null && dayEnergy > 0) {
            // 7.700 kcal je kg; höchstens 25 % Defizit bzw. 15 % Überschuss.
            val daily = NutritionSettings.safeWeeklyChange(weekly) / 100 * weight * 7_700 / 7
            adjustPercent = (daily / dayEnergy * 100).coerceIn(-25.0, 15.0)
        }
        val goalPercent = adjustPercent * dayType.goalScale
        var energy = dayEnergy * (1 + goalPercent / 100) + settings.energyAdjustmentKcal.coerceIn(-500.0, 500.0)

        val bodyFat = settings.bodyFatPercent ?: if (settings.isFemale) 25.0 else 15.0
        val fatFreeMass = weight * (1 - bodyFat / 100)
        var floorApplied = false
        if (goalPercent < 0 && energy < 30 * fatFreeMass + exerciseKcal) {
            energy = 30 * fatFreeMass + exerciseKcal
            floorApplied = true
        }

        val proteinPerKg = settings.goal.proteinPerKg
        val protein = proteinPerKg * weight
        val fatMinimum = 0.20 * energy / 9
        val fatMaximum = 0.35 * energy / 9
        val carbRoom = (energy - 4 * protein - 9 * fatMinimum) / 4
        var carbs = minOf(dayType.carbsPerKg * weight, maxOf(carbRoom, dayType.minimumCarbsPerKg * weight))
        val rest = energy - 4 * protein - 4 * carbs
        var fat = minOf(maxOf(rest / 9, fatMinimum), fatMaximum)
        if (rest / 9 > fatMaximum) carbs += (rest - fat * 9) / 4
        fat = maxOf(fat, (protein + carbs) / 9)
        val total = 4 * protein + 4 * carbs + 9 * fat

        val endurance = if (dayType == DayType.LIGHT) 0.0 else dayType.plannedMinutes
        val strength = if (dayType == DayType.LIGHT) dayType.plannedMinutes else 0.0
        val water = 35 * weight + 10 * endurance + 5 * strength

        val values = micro(settings.isFemale).mapKeys { it.key.key }.toMutableMap()
        values[Nutrient.KCAL.key] = Math.rint(total)
        values[Nutrient.PROTEIN.key] = Math.rint(protein)
        values[Nutrient.CARBS.key] = Math.rint(carbs)
        values[Nutrient.FAT.key] = Math.rint(fat)
        values[Nutrient.SUGAR.key] = Math.rint(0.10 * total / 4)
        values[Nutrient.SATURATED_FAT.key] = Math.rint(0.10 * total / 9)
        values[Nutrient.WATER.key] = Math.rint(water / 50) * 50
        return Targets(values, dayType, Math.rint(bmr), Math.rint(exerciseKcal), proteinPerKg, floorApplied)
    }
}

/** Ergebnis der Worker-Aufgabe `meal_analyze` bzw. `meal_amend` (Schema wie `MealAnalysis` in CoachCore). */
data class MealAnalysis(
    val title: String,
    val category: MealCategory?,
    val hint: String,
    val items: List<MealItem>,
    val possiblyMissing: List<String>,
) {
    companion object {
        fun parse(output: JsonElement, bls: Bls?): MealAnalysis? {
            val obj = output as? JsonObject ?: return null
            val raw = obj["items"] as? JsonArray ?: return null
            val items = raw.mapNotNull { item(it, bls) }
            if (items.isEmpty()) return null
            return MealAnalysis(
                title = obj.string("titel").orEmpty().take(60),
                category = MealCategory.of(obj.string("kategorie")),
                hint = obj.string("hinweis").orEmpty(),
                items = items,
                possiblyMissing = missing(obj),
            )
        }

        /** `meal_amend`: nur neue Positionen (dürfen leer sein) und ein Hinweis. */
        fun amendment(output: JsonElement, bls: Bls?): Pair<List<MealItem>, String> {
            val obj = output as? JsonObject ?: return emptyList<MealItem>() to ""
            val items = (obj["items"] as? JsonArray)?.mapNotNull { item(it, bls) }.orEmpty()
            return items to obj.string("hinweis").orEmpty()
        }

        private fun missing(obj: JsonObject): List<String> =
            (obj["vielleicht_vergessen"] as? JsonArray).orEmpty()
                .mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content?.trim()?.take(40) }
                .filter { it.isNotEmpty() }.take(4)

        fun item(value: JsonElement, bls: Bls?): MealItem? {
            val obj = value as? JsonObject ?: return null
            val name = obj.string("name")?.takeIf { it.isNotEmpty() } ?: return null
            val grams = obj.number("menge_g")?.takeIf { it > 0 } ?: return null
            val per100g = nutrientsFrom(obj["naehrwerte_100g"] as? JsonObject)
            val amountText = obj.string("menge_text")
            val item = MealItem(
                name = name,
                grams = grams,
                source = FoodSource.AI,
                per100g = per100g,
                amountText = amountText,
                isDrink = (obj["getraenk"] as? JsonPrimitive)?.booleanOrNull == true,
                confidence = obj.string("sicherheit"),
                barcode = obj.string("barcode")?.takeIf(OpenFoodFacts::isValidBarcode),
                portion = PortionGuess.from(amountText, grams),
                searchTerm = obj.string("suchbegriff")?.take(80),
                group = obj.string("gruppe"),
            )
            return bls?.enrich(item) ?: item
        }

        /** Nährwerte je 100 g aus der KI-Antwort; Flüssigkeit heißt dort `water_g`. */
        fun nutrientsFrom(obj: JsonObject?): NutrientMap {
            if (obj == null) return emptyMap()
            return Nutrient.entries.mapNotNull { nutrient ->
                val key = if (nutrient == Nutrient.WATER) "water_g" else nutrient.key
                obj.number(key)?.takeIf { it >= 0 }?.let { nutrient.key to it }
            }.toMap()
        }
    }
}

/** Open Food Facts (API v2): Produkt per Barcode, Werte je 100 g; Mineralstoffe stehen dort in Gramm. */
object OpenFoodFacts {
    const val USER_AGENT = "IronLudiGym/1.0 (Android; privat)"
    private const val FIELDS = "code,product_name,product_name_de,generic_name_de,brands,quantity,serving_quantity,serving_size,nutriments"

    fun url(barcode: String) = "https://world.openfoodfacts.org/api/v2/product/$barcode?fields=$FIELDS"

    /** Prüfziffer nach GS1 für EAN-8, UPC-A, EAN-13 und GTIN-14. */
    fun isValidBarcode(text: String): Boolean {
        if (text.isEmpty() || !text.all { it.isDigit() } || text.length !in setOf(8, 12, 13, 14)) return false
        val digits = text.map { it - '0' }
        val body = digits.dropLast(1).reversed()
        val sum = body.withIndex().sumOf { (index, digit) -> digit * if (index % 2 == 0) 3 else 1 }
        return (10 - sum % 10) % 10 == digits.last()
    }

    private val mapping = listOf(
        Triple("energy-kcal", Nutrient.KCAL, 1.0), Triple("proteins", Nutrient.PROTEIN, 1.0), Triple("carbohydrates", Nutrient.CARBS, 1.0),
        Triple("sugars", Nutrient.SUGAR, 1.0), Triple("fat", Nutrient.FAT, 1.0), Triple("saturated-fat", Nutrient.SATURATED_FAT, 1.0),
        Triple("fiber", Nutrient.FIBER, 1.0), Triple("sodium", Nutrient.SODIUM, 1000.0), Triple("potassium", Nutrient.POTASSIUM, 1000.0),
        Triple("magnesium", Nutrient.MAGNESIUM, 1000.0), Triple("calcium", Nutrient.CALCIUM, 1000.0), Triple("iron", Nutrient.IRON, 1000.0),
        Triple("zinc", Nutrient.ZINC, 1000.0), Triple("vitamin-d", Nutrient.VITAMIN_D, 1_000_000.0),
        Triple("vitamin-b12", Nutrient.VITAMIN_B12, 1_000_000.0), Triple("vitamin-c", Nutrient.VITAMIN_C, 1000.0),
        Triple("iodine", Nutrient.IODINE, 1_000_000.0),
    )

    /** Position aus der API-Antwort; `null`, wenn unbekannt oder ohne Kalorienangabe. */
    fun item(json: JsonElement, barcode: String): MealItem? {
        val root = json as? JsonObject ?: return null
        if (root.number("status") == 0.0) return null
        val product = root["product"] as? JsonObject ?: return null
        val nutriments = product["nutriments"] as? JsonObject ?: return null
        val values = mutableMapOf<String, Double>()
        for ((key, nutrient, factor) in mapping) {
            nutriments.number("${key}_100g")?.takeIf { it >= 0 }?.let { values[nutrient.key] = it * factor }
        }
        if (values[Nutrient.KCAL.key] == null) nutriments.number("energy_100g")?.let { values[Nutrient.KCAL.key] = Math.rint(it / 4.184) }
        val omega3 = listOf("eicosapentaenoic-acid", "docosahexaenoic-acid").mapNotNull { nutriments.number("${it}_100g") }
        if (omega3.isNotEmpty()) values[Nutrient.OMEGA3.key] = omega3.sum() * 1000
        if (values[Nutrient.KCAL.key] == null) return null
        val name = listOf("product_name_de", "product_name", "generic_name_de").mapNotNull { product.string(it) }
            .firstOrNull { it.isNotBlank() } ?: "Produkt $barcode"
        val brand = product.string("brands")?.split(",")?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
        val serving = product.number("serving_quantity")?.takeIf { it > 0 }
        return MealItem(
            name = if (brand != null) "$name ($brand)" else name,
            grams = serving ?: 100.0,
            source = FoodSource.OPEN_FOOD_FACTS,
            per100g = values,
            barcode = barcode,
            portion = PortionGuess.serving(product.string("serving_size"), serving),
        )
    }
}

internal fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonObject.number(key: String): Double? {
    val primitive = this[key] as? JsonPrimitive ?: return null
    return primitive.doubleOrNull ?: primitive.content.replace(',', '.').toDoubleOrNull()
}
