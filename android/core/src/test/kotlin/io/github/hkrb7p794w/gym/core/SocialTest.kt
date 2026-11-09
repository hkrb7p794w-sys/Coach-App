package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

// Gleiche Fälle wie `SocialTests` in CoachCore.
class SocialTest {
    @Test
    fun parsesFeed() {
        val json = GymJson.parseToJsonElement(
            """{"posts": [{"id": "p1", "kind": "workout", "createdAt": "2026-11-09T12:00:00.000Z",
            "author": {"username": "lena", "displayName": "Lena"}, "mine": false,
            "payload": {"sport": "run", "title": "Lockerer Lauf", "durationMin": 45, "distanceKm": 8.2},
            "reactions": 2, "myReaction": "🔥", "topReactions": "🔥💪", "comments": 1}]}""",
        ) as JsonObject
        val post = Social.posts(json).single()
        assertEquals("Lockerer Lauf", post.headline)
        assertEquals("45 min · 8,2 km", post.facts)
        assertEquals("🔥", post.myReaction)
        assertEquals("Lena", post.author.displayName)
    }

    @Test
    fun workoutShareHasNoBodyValues() {
        val session = Session(
            id = "s1",
            startedAt = 0,
            endedAt = 50 * 60_000L,
            name = "Beine",
            exercises = listOf(LoggedExercise("kniebeuge", "Kniebeuge", "legs", List(3) { SetEntry(weightKg = 100.0, reps = 5, done = true) })),
        )
        val share = Social.workout(session, listOf("Kniebeuge: 100 kg × 5"))
        assertEquals(50, (share["durationMin"] as JsonPrimitive).content.toInt())
        assertEquals(1500, (share["volumeKg"] as JsonPrimitive).content.toInt())
        assertEquals("strength", (share["sport"] as JsonPrimitive).content)
        assertFalse(share.toString().contains("heart"))
        assertFalse(share.containsKey("weightKg"))
    }

    @Test
    fun mealRoundTrip() {
        val items = listOf(MealItem(name = "Haferflocken", grams = 60.0, source = FoodSource.MANUAL, per100g = mapOf(Nutrient.KCAL.key to 370.0)))
        val share = Social.meal("Overnight Oats", items, "Lecker")
        val post = SocialPost("p", "meal", "", SocialPerson("tom", "Tom"), false, JsonObject(mapOf("meal" to share["meal"]!!)), 0, null, "", 0)
        assertNotNull(post.meal)
        assertEquals("Overnight Oats", post.headline)
        assertEquals("222 kcal", post.facts)
    }
}
