package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlin.math.roundToInt

/** Person aus dem Worker (`worker/src/social.ts`). */
data class SocialPerson(val username: String, val displayName: String, val relation: String? = null) {
    val initial: String get() = (displayName.firstOrNull() ?: username.firstOrNull() ?: '?').uppercase()
}

/** Beitrag im Feed, wie `SocialPost` in CoachCore. */
data class SocialPost(
    val id: String,
    val kind: String,
    val createdAt: String,
    val author: SocialPerson,
    val mine: Boolean,
    val payload: JsonObject,
    val reactions: Int,
    val myReaction: String?,
    val topReactions: String,
    val comments: Int,
) {
    val meal: Pair<String, List<MealItem>>? get() = (payload["meal"] as? JsonObject)?.let(MealShare::items)

    val headline: String
        get() = when (kind) {
            "meal" -> meal?.first ?: "Mahlzeit"
            "workout", "milestone" -> payload.string("title") ?: "Beitrag"
            else -> "Beitrag (neuere App-Version nötig)"
        }

    /** Kennzahlen in einer Zeile, z. B. „45 min · 8,2 km“. */
    val facts: String
        get() {
            val parts = mutableListOf<String>()
            when (kind) {
                "workout" -> {
                    payload.number("durationMin")?.let { parts += "${it.roundToInt()} min" }
                    payload.number("distanceKm")?.takeIf { it > 0 }?.let { parts += "${Social.decimal(it)} km" }
                    payload.number("elevationM")?.takeIf { it >= 10 }?.let { parts += "${it.roundToInt()} hm" }
                    payload.number("sets")?.takeIf { it > 0 }?.let { parts += "${it.roundToInt()} Sätze" }
                    payload.number("volumeKg")?.takeIf { it > 0 }?.let { parts += "${((it / 100).roundToInt() * 100)} kg bewegt" }
                }
                "meal" -> meal?.second?.let { items ->
                    val totals = Nutrition.totals(items)
                    parts += "${(totals[Nutrient.KCAL] ?: 0.0).roundToInt()} kcal"
                    (totals[Nutrient.PROTEIN] ?: 0.0).takeIf { it > 0 }?.let { parts += "${it.roundToInt()} g Protein" }
                }
                "milestone" -> payload.string("text")?.let { parts += it }
            }
            return parts.joinToString(" · ")
        }

    val exercises: List<String> get() = (payload["exercises"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }
    val records: List<String> get() = (payload["records"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }
    val note: String? get() = payload.string("note")
}

object Social {
    /** Reaktionen wie im Worker (`REACTIONS`). */
    val REACTIONS = listOf("👏", "🔥", "💪", "😋", "❤️")

    fun decimal(value: Double): String {
        val rounded = (value * 10).roundToInt() / 10.0
        return if (rounded == rounded.toLong().toDouble()) rounded.toLong().toString() else rounded.toString().replace('.', ',')
    }

    fun person(json: JsonObject?): SocialPerson? {
        json ?: return null
        val username = json.string("username") ?: return null
        return SocialPerson(username, json.string("displayName") ?: username, json.string("relation"))
    }

    fun post(json: JsonObject): SocialPost? {
        val id = json.string("id") ?: return null
        return SocialPost(
            id = id,
            kind = json.string("kind") ?: "unknown",
            createdAt = json.string("createdAt").orEmpty(),
            author = person(json["author"] as? JsonObject) ?: SocialPerson("?", "?"),
            mine = (json["mine"] as? JsonPrimitive)?.booleanOrNull ?: false,
            payload = json["payload"] as? JsonObject ?: JsonObject(emptyMap()),
            reactions = (json["reactions"] as? JsonPrimitive)?.intOrNull ?: 0,
            myReaction = json.string("myReaction"),
            topReactions = json.string("topReactions").orEmpty(),
            comments = (json["comments"] as? JsonPrimitive)?.intOrNull ?: 0,
        )
    }

    fun posts(json: JsonObject): List<SocialPost> =
        (json["posts"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::post) }

    fun people(json: JsonObject, key: String): List<SocialPerson> =
        (json[key] as? JsonArray).orEmpty().mapNotNull { person(it as? JsonObject) }

    /**
     * Krafttraining für den Feed: Dauer, Sätze, bewegtes Gewicht, Übungen (höchstens 12), Bestleistungen.
     * Bewusst ohne Körperwerte – Gewicht, Puls und Kalorien bleiben auf dem Handy.
     */
    fun workout(session: Session, records: List<String> = emptyList(), note: String? = null, now: Long = System.currentTimeMillis()): JsonObject =
        buildJsonObject {
            put("kind", "workout")
            put("sport", "strength")
            put("title", session.name.ifBlank { "Krafttraining" }.take(80))
            put("durationMin", maxOf(1, (((session.endedAt ?: now) - session.startedAt) / 60_000.0).roundToInt()))
            put("sets", session.workingSets)
            if (session.volumeKg > 0) put("volumeKg", session.volumeKg.roundToInt())
            val names = session.exercises.filter { exercise -> exercise.sets.any { it.done && !it.warmup } }.map { it.name }
            if (names.isNotEmpty()) put("exercises", buildJsonArray { names.take(12).forEach { add(JsonPrimitive(it)) } })
            if (records.isNotEmpty()) put("records", buildJsonArray { records.take(10).forEach { add(JsonPrimitive(it)) } })
            note?.trim()?.takeIf { it.isNotEmpty() }?.let { put("note", it.take(280)) }
        }

    /** Mahlzeit für den Feed: gleiche Felder wie das Teilen per Code. */
    fun meal(title: String, items: List<MealItem>, note: String? = null): JsonObject = buildJsonObject {
        put("kind", "meal")
        put("meal", MealShare.body(title, items))
        note?.trim()?.takeIf { it.isNotEmpty() }?.let { put("note", it.take(280)) }
    }
}
