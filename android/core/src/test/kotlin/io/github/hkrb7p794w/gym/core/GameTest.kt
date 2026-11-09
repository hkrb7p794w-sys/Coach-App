package io.github.hkrb7p794w.gym.core

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Gleiche Fälle wie `GameTests` in CoachCore.
class GameTest {
    private val today = LocalDate.of(2026, 11, 11) // Mittwoch
    private fun nov(vararg days: Int) = days.map { LocalDate.of(2026, 11, it) }.toSet()

    @Test
    fun streakUntilYesterday() {
        val days = (1L..5L).map { today.minusDays(it) }.toSet()
        val streak = Game.streak(days, today)
        assertEquals(5, streak.current)
        assertFalse(streak.activeToday)
        assertEquals(6, Game.streak(days + today, today).current)
    }

    @Test
    fun jokerPerWeek() {
        val streak = Game.streak(nov(9, 10, 7, 6), today)
        assertEquals(5, streak.current)
        assertEquals(listOf(LocalDate.of(2026, 11, 8)), streak.jokerDays)
        val bridged = Game.streak(nov(10, 8, 6, 4), today)
        assertEquals(5, bridged.current)
        assertEquals(listOf(LocalDate.of(2026, 11, 9), LocalDate.of(2026, 11, 7)), bridged.jokerDays)
    }

    @Test
    fun noStreak() {
        assertEquals(0, Game.streak(emptySet(), today).current)
        val old = Game.streak((20L..29L).map { today.minusDays(it) }.toSet(), today)
        assertEquals(0, old.current)
        assertEquals(10, old.best)
    }

    @Test
    fun badgesAndValues() {
        val earned = Game.earned(GameStats(workouts = 12, bestDayStreak = 8, friends = 1)).map { it.id }.toSet()
        assertEquals(setOf("workout.1", "workout.10", "streak.7", "friends.1"), earned)
        val monday = LocalDate.of(2026, 11, 9)
        val minutes = mapOf(monday to 200, monday.plusDays(1) to 45, monday.plusDays(5) to 60)
        val meals = setOf(monday, monday.plusDays(2))
        assertEquals(135, Game.value(Game.Metric.MINUTES, monday, today, minutes, meals))
        assertEquals(2, Game.value(Game.Metric.SESSIONS, monday, today, minutes, meals))
        assertEquals(2, Game.value(Game.Metric.MEALS, monday, today, minutes, meals))
        assertNull(Game.value(Game.Metric.PLAN, monday, today, minutes, meals))
        assertEquals(75, Game.weekPoints(minutes, monday))
        assertTrue(Game.weekPoints((0L..6L).associate { monday.plusDays(it) to 60 }, monday) == 100)
        assertEquals(4, Game.level(345))
    }
}
