package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.time.LocalDateTime

/** Erinnerungen an Mahlzeiten (Standard aus) und abends „Tag auswerten“ (Port von `MealReminderSettings`). */
@Serializable
data class ReminderSlot(val enabled: Boolean = false, val hour: Int, val minute: Int) {
    val minutes: Int get() = hour * 60 + minute
}

@Serializable
data class MealReminders(
    val breakfast: ReminderSlot = ReminderSlot(hour = 8, minute = 0),
    val lunch: ReminderSlot = ReminderSlot(hour = 12, minute = 30),
    val snack: ReminderSlot = ReminderSlot(hour = 16, minute = 0),
    val dinner: ReminderSlot = ReminderSlot(hour = 19, minute = 0),
    /** Abends 20 Uhr: Tag auswerten. */
    val review: Boolean = false,
) {
    fun slot(category: MealCategory): ReminderSlot? = when (category) {
        MealCategory.BREAKFAST -> breakfast
        MealCategory.LUNCH -> lunch
        MealCategory.SNACK -> snack
        MealCategory.DINNER -> dinner
        MealCategory.OTHER -> null
    }

    fun with(category: MealCategory, slot: ReminderSlot): MealReminders = when (category) {
        MealCategory.BREAKFAST -> copy(breakfast = slot)
        MealCategory.LUNCH -> copy(lunch = slot)
        MealCategory.SNACK -> copy(snack = slot)
        MealCategory.DINNER -> copy(dinner = slot)
        MealCategory.OTHER -> this
    }

    val anyEnabled: Boolean get() = CATEGORIES.any { slot(it)?.enabled == true } || review

    companion object {
        val CATEGORIES = listOf(MealCategory.BREAKFAST, MealCategory.LUNCH, MealCategory.SNACK, MealCategory.DINNER)
        const val REVIEW_HOUR = 20
    }
}

/** Eine geplante Mitteilung. `category == null` bedeutet „Tag auswerten“. */
data class ScheduledNote(val at: LocalDateTime, val category: MealCategory?, val title: String, val body: String)

object Reminders {
    fun body(category: MealCategory): String = when (category) {
        MealCategory.BREAKFAST -> "Was gab es zum Frühstück? Ein Tipp auf „Zuletzt“ reicht oft."
        MealCategory.LUNCH -> "Mittagessen eintragen – Foto, Text oder aus deinen Favoriten."
        MealCategory.DINNER -> "Abendessen eintragen, dann stimmt die Tagesbilanz."
        else -> "Snack eintragen?"
    }

    /**
     * Nächste Mitteilungen für heute und morgen. Keine, wenn die Mahlzeit an dem Tag schon erfasst ist oder die Zeit
     * heute vorbei ist (wie `ReminderPlanner.meals`).
     */
    fun upcoming(settings: MealReminders, now: LocalDateTime, meals: List<Meal>, days: Int = 2): List<ScheduledNote> {
        val logged = meals.map { "${it.day}|${it.category}" }.toSet()
        val result = mutableListOf<ScheduledNote>()
        for (offset in 0 until maxOf(days, 1)) {
            val day = now.toLocalDate().plusDays(offset.toLong())
            for (category in MealReminders.CATEGORIES) {
                val slot = settings.slot(category) ?: continue
                if (!slot.enabled) continue
                val at = day.atTime(slot.hour, slot.minute)
                if (!at.isAfter(now)) continue
                if ("$day|$category" in logged) continue
                result.add(ScheduledNote(at, category, "${category.label} eintragen", body(category)))
            }
            if (settings.review) {
                val at = day.atTime(MealReminders.REVIEW_HOUR, 0)
                if (at.isAfter(now)) {
                    result.add(ScheduledNote(at, null, "Tag auswerten", "Kurz schauen: Hat das Essen heute zum Training gepasst? Fehlt noch Protein?"))
                }
            }
        }
        return result.sortedBy { it.at }
    }
}

/** Geteilte Mahlzeit über den Worker (`/v1/share/meal`): nur Titel und Positionen, keine Gesundheitsdaten. */
object MealShare {
    fun body(title: String, items: List<MealItem>): JsonObject = buildJsonObject {
        put("title", title.take(80))
        put("items", buildJsonArray {
            items.map(MealPortion::restored).forEach { item ->
                add(buildJsonObject {
                    put("name", item.name.take(80))
                    put("grams", item.grams)
                    put("isDrink", item.isDrink)
                    put("source", item.source.label)
                    put("per100g", buildJsonObject { item.per100g.forEach { (key, value) -> put(key, value) } })
                    item.amountText?.let { put("amountText", it.take(60)) }
                })
            }
        })
    }

    /** Antwort von `GET /v1/share/meal/<code>` als Positionen (neue IDs). */
    fun items(json: JsonElement): Pair<String, List<MealItem>>? {
        val obj = json as? JsonObject ?: return null
        val items = (obj["items"] as? JsonArray).orEmpty().mapNotNull { raw ->
            val item = raw as? JsonObject ?: return@mapNotNull null
            val name = item.string("name")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val grams = item.number("grams")?.takeIf { it > 0 } ?: return@mapNotNull null
            val per100g = (item["per100g"] as? JsonObject)?.mapNotNull { (key, value) ->
                val number = (value as? JsonPrimitive)?.content?.toDoubleOrNull()
                if (Nutrient.of(key) != null && number != null) key to number else null
            }?.toMap().orEmpty()
            MealItem(
                name = name,
                grams = grams,
                source = FoodSource.entries.firstOrNull { it.label == item.string("source") } ?: FoodSource.MANUAL,
                per100g = per100g,
                isDrink = (item["isDrink"] as? JsonPrimitive)?.content == "true",
                amountText = item.string("amountText"),
            )
        }
        if (items.isEmpty()) return null
        return (obj.string("title") ?: "Geteilte Mahlzeit") to items
    }

    /** Code aus `…/m/<code>`, `coach://meal/<code>` oder eingetippt (10 Zeichen, Kleinbuchstaben und Ziffern). */
    fun code(text: String): String? {
        val trimmed = text.trim().lowercase()
        if (isValid(trimmed)) return trimmed
        val last = trimmed.trimEnd('/').substringAfterLast('/')
        val marker = trimmed.contains("/m/") || trimmed.startsWith("coach://meal/")
        return if (marker && isValid(last)) last else null
    }

    fun isValid(code: String): Boolean = code.length == 10 && code.all { it in 'a'..'z' || it in '0'..'9' }

    fun message(title: String, kcal: Double, link: String, code: String): String = listOf(
        "Mahlzeit „$title“ (${Math.rint(kcal).toInt()} kcal) für IronLudi:",
        link,
        "Oder in der App unter Ernährung › „Geteilte Mahlzeit öffnen“ den Code $code eingeben.",
        "Der Code gilt 7 Tage.",
    ).joinToString("\n")
}

/** Regeln, auf die sich KI-Texte stützen dürfen (Auszug aus `Evidence` in CoachCore, `assets/evidence.json`). */
@Serializable
data class EvidenceRule(val id: String, val title: String, val statement: String)

object EvidenceInput {
    val REVIEW = listOf("nutrition.energy", "nutrition.carbs", "nutrition.protein", "nutrition.reds", "recovery.sleep")

    fun json(rules: List<EvidenceRule>, ids: List<String>): JsonArray = buildJsonArray {
        rules.filter { it.id in ids }.forEach { rule ->
            add(buildJsonObject {
                put("id", rule.id)
                put("statement", rule.statement)
            })
        }
    }

    /** Punkte aus `{"punkte": [...]}` bzw. einer Liste. */
    fun points(output: JsonElement): List<String> {
        val values = ((output as? JsonObject)?.get("punkte") as? JsonArray) ?: (output as? JsonArray) ?: JsonArray(emptyList())
        return values.mapNotNull { (it as? JsonPrimitive)?.content?.trim() }.filter { it.isNotEmpty() }
    }

    /** Quellen-IDs aus `{"quellen": [...]}`, nur bekannte Regeln. */
    fun sources(output: JsonElement, rules: List<EvidenceRule>): List<EvidenceRule> {
        val ids = ((output as? JsonObject)?.get("quellen") as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }
        return ids.mapNotNull { id -> rules.firstOrNull { it.id == id } }
    }
}

/** Mahlzeit, die ohne Netz nicht ausgewertet werden konnte (Text, Foto als Base64). */
@Serializable
data class PendingAnalysis(val id: String = java.util.UUID.randomUUID().toString(), val createdAt: Long, val day: String, val text: String, val photo: String? = null)

/** Woche auf einen Blick: Energie je Tag gegen das Ziel, Protein im Schnitt (Port von `NutritionWeek`). */
object NutritionWeek {
    data class Day(val day: LocalDate, val kcal: Double, val protein: Double, val targetKcal: Double?, val logged: Boolean)

    data class Summary(val days: List<Day>, val averageKcal: Double?, val averageTargetKcal: Double?, val averageProtein: Double?)

    fun summary(data: AppData, monday: LocalDate, today: LocalDate): Summary {
        val days = (0L until 7L).map { monday.plusDays(it) }.filter { it <= today }.map { day ->
            val totals = Diary.totals(data, day)
            val logged = data.meals.any { it.day == day.toString() && it.items.any { item -> !(item.isDrink && item.name == "Wasser") } }
            Day(day, totals[Nutrient.KCAL] ?: 0.0, totals[Nutrient.PROTEIN] ?: 0.0, Diary.targets(data, day).values[Nutrient.KCAL], logged)
        }
        val logged = days.filter { it.logged }
        fun average(values: List<Double>) = if (values.isEmpty()) null else Math.rint(values.average())
        return Summary(days, average(logged.map { it.kcal }), average(logged.mapNotNull { it.targetKcal }), average(logged.map { it.protein }))
    }
}
