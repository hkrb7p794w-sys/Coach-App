package io.github.hkrb7p794w.gym.core

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/**
 * Spielelemente wie in CoachCore (`Game.swift`): Tages-Serie mit einem Joker je Woche, Abzeichen für Beständigkeit,
 * Challenge-Werte mit Obergrenzen (Übertraining bringt nichts).
 */
data class DailyStreak(val current: Int, val best: Int, val jokerDays: List<LocalDate>, val activeToday: Boolean)

data class GameStats(
    val workouts: Int = 0,
    val bestDayStreak: Int = 0,
    val planWeekStreak: Int = 0,
    val mealDays: Int = 0,
    val friends: Int = 0,
    val challengesWon: Int = 0,
    val level: Int = 0,
)

data class Badge(val id: String, val title: String, val detail: String, val target: Int, val value: (GameStats) -> Int) {
    fun progress(stats: GameStats): Int = minOf(value(stats), target)
    fun isEarned(stats: GameStats): Boolean = value(stats) >= target
}

object Game {
    const val JOKERS_PER_WEEK = 1

    fun monday(day: LocalDate): LocalDate = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    fun streak(activeDays: Set<LocalDate>, today: LocalDate, lookback: Int = 400): DailyStreak {
        val activeToday = today in activeDays
        val current = run(if (activeToday) today else today.minusDays(1), activeDays, lookback)
        var best = current.first
        activeDays.filter { it <= today && it >= today.minusDays(lookback.toLong()) && it.plusDays(1) !in activeDays }.forEach { day ->
            best = maxOf(best, run(day, activeDays, lookback).first)
        }
        return DailyStreak(current.first, best, current.second, activeToday)
    }

    private fun run(start: LocalDate, activeDays: Set<LocalDate>, limit: Int): Pair<Int, List<LocalDate>> {
        var day = start
        var length = 0
        val jokers = mutableListOf<LocalDate>()
        val used = mutableMapOf<LocalDate, Int>()
        repeat(limit) {
            if (day in activeDays) {
                length += 1
            } else {
                val week = monday(day)
                val count = used[week] ?: 0
                if (length == 0 || count >= JOKERS_PER_WEEK || day.minusDays(1) !in activeDays) return length to jokers
                used[week] = count + 1
                jokers += day
                length += 1
            }
            day = day.minusDays(1)
        }
        return length to jokers
    }

    val BADGES: List<Badge> = listOf(
        Badge("workout.1", "Los geht’s", "Erstes Training erfasst", 1) { it.workouts },
        Badge("workout.10", "Dranbleiber", "10 Trainings", 10) { it.workouts },
        Badge("workout.50", "Gewohnheit", "50 Trainings", 50) { it.workouts },
        Badge("workout.100", "Hundert", "100 Trainings", 100) { it.workouts },
        Badge("streak.7", "Eine Woche", "7 Tage in Folge etwas erfasst", 7) { it.bestDayStreak },
        Badge("streak.30", "Ein Monat", "30 Tage in Folge", 30) { it.bestDayStreak },
        Badge("streak.100", "Hundert Tage", "100 Tage in Folge", 100) { it.bestDayStreak },
        Badge("plan.1", "Plan erfüllt", "Eine Woche mit mindestens 80 % des Plans", 1) { it.planWeekStreak },
        Badge("plan.4", "Vier Wochen stark", "4 Wochen in Folge nach Plan", 4) { it.planWeekStreak },
        Badge("plan.12", "Ein Block", "12 Wochen in Folge nach Plan", 12) { it.planWeekStreak },
        Badge("meals.7", "Tagebuch", "An 7 Tagen Essen erfasst", 7) { it.mealDays },
        Badge("meals.30", "Ernährungsprofi", "An 30 Tagen Essen erfasst", 30) { it.mealDays },
        Badge("friends.1", "Gemeinsam", "Erste Freundschaft", 1) { it.friends },
        Badge("friends.5", "Team", "5 Freunde", 5) { it.friends },
        Badge("challenge.1", "Gewonnen!", "Erste Challenge gewonnen", 1) { it.challengesWon },
        Badge("challenge.5", "Seriensieger", "5 Challenges gewonnen", 5) { it.challengesWon },
        Badge("level.5", "Stufe 5", "Stufe 5 erreicht", 5) { it.level },
        Badge("level.10", "Stufe 10", "Stufe 10 erreicht", 10) { it.level },
    )

    fun earned(stats: GameStats): List<Badge> = BADGES.filter { it.isEarned(stats) }

    fun next(stats: GameStats): Badge? =
        BADGES.filterNot { it.isEarned(stats) }.maxByOrNull { it.progress(stats).toDouble() / it.target }

    /** Messgrößen wie im Worker (`METRICS`); `plan` gibt es nur in der iPhone-App (Wochenplan). */
    enum class Metric(val key: String, val title: String, val unit: String, val max: Int, val rule: String) {
        PLAN("plan", "Plan erfüllt", "%", 100, "Anteil des eigenen Wochenplans (nur iPhone-App)."),
        SESSIONS("sessions", "Trainingstage", "Tage", 7, "Höchstens ein Trainingstag pro Tag zählt."),
        MINUTES("minutes", "Trainingsminuten", "min", 630, "Höchstens 90 Minuten am Tag zählen – Übertraining bringt nichts."),
        MEALS("meals", "Tage mit Ernährungstagebuch", "Tage", 7, "Ein Tag zählt, sobald eine Mahlzeit erfasst ist."),
        ;

        companion object {
            fun of(key: String): Metric? = entries.firstOrNull { it.key == key }
        }
    }

    /** Wert einer Woche ab `monday` bis einschließlich `today`; `null`, wenn auf Android nicht messbar. */
    fun value(metric: Metric, monday: LocalDate, today: LocalDate, minutesByDay: Map<LocalDate, Int>, mealDays: Set<LocalDate>): Int? {
        val days = (0L until 7L).map { monday.plusDays(it) }.filter { it <= today }
        return when (metric) {
            Metric.PLAN -> null
            Metric.SESSIONS -> days.count { (minutesByDay[it] ?: 0) > 0 }
            Metric.MINUTES -> days.sumOf { minOf(minutesByDay[it] ?: 0, 90) }
            Metric.MEALS -> days.count { it in mealDays }
        }
    }

    /**
     * Wochenpunkte für die Rangliste ohne Wochenplan (Android): 25 je Trainingstag, höchstens 100 – vier Tage reichen
     * für die volle Punktzahl, mehr Training bringt nichts.
     */
    fun weekPoints(minutesByDay: Map<LocalDate, Int>, monday: LocalDate): Int =
        minOf(100, (0L until 7L).count { (minutesByDay[monday.plusDays(it)] ?: 0) > 0 } * 25)

    fun minutesByDay(data: AppData, zone: ZoneId = ZoneId.systemDefault()): Map<LocalDate, Int> =
        data.sessions.filter { it.endedAt != null && it.workingSets > 0 }.groupBy { Instant.ofEpochMilli(it.startedAt).atZone(zone).toLocalDate() }
            .mapValues { (_, sessions) -> sessions.sumOf { (((it.endedAt ?: it.startedAt) - it.startedAt) / 60_000).toInt().coerceAtLeast(1) } }

    fun mealDays(data: AppData): Set<LocalDate> =
        data.meals.mapNotNull { runCatching { LocalDate.parse(it.day) }.getOrNull() }.toSet()

    /** Stufe aus allen Punkten: alle 100 Punkte eine Stufe (wie `ScoreRules.level`). */
    fun level(totalPoints: Int): Int = maxOf(totalPoints, 0) / 100 + 1
}
