package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.ln
import kotlin.math.pow

/** Schutzgrenzen wie `GoalRules` in CoachCore. */
object GoalRules {
    const val MAX_LOSS_PERCENT_PER_WEEK = 1.0
    const val MAX_GAIN_PERCENT_PER_WEEK = 0.5
    const val MINIMUM_BMI = 18.5
}

/** Eine Wägung (yyyy-MM-dd, kg). */
@Serializable
data class WeightEntry(val day: String, val kilograms: Double)

/**
 * Gewichtsverlauf (Port von `WeightTrend`): lineare Regression über 28 Tage, Abgleich mit dem geplanten Tempo und
 * Vorschlag in kleinen Schritten (höchstens ±250 kcal auf einmal, ±500 insgesamt).
 */
object WeightTrend {
    const val MINIMUM_ENTRIES = 8
    const val MINIMUM_SPAN_DAYS = 14
    const val WINDOW_DAYS = 28
    const val TOLERANCE_PERCENT = 0.25
    const val MAX_STEP_KCAL = 250.0
    const val MAX_TOTAL_KCAL = 500.0

    data class Result(val trendKilograms: Double, val weeklyPercent: Double, val entries: Int, val spanDays: Int)

    enum class Kind { ON_TRACK, EAT_MORE, EAT_LESS, TOO_FAST }

    data class Advice(val kind: Kind, val message: String, val kcal: Double)

    /** Ein Wert pro Tag (der zuletzt eingetragene), nur 25–300 kg. */
    fun merged(entries: List<WeightEntry>): List<WeightEntry> =
        entries.filter { it.kilograms in 25.0..300.0 }.associateBy { it.day }.values.sortedBy { it.day }

    fun trend(entries: List<WeightEntry>, today: LocalDate): Result? {
        val start = today.minusDays((WINDOW_DAYS - 1).toLong())
        val recent = merged(entries).filter { val d = LocalDate.parse(it.day); d >= start && d <= today }
        if (recent.size < MINIMUM_ENTRIES) return null
        val first = LocalDate.parse(recent.first().day)
        val span = ChronoUnit.DAYS.between(first, LocalDate.parse(recent.last().day)).toInt()
        if (span < MINIMUM_SPAN_DAYS) return null
        val xs = recent.map { ChronoUnit.DAYS.between(first, LocalDate.parse(it.day)).toDouble() }
        val ys = recent.map { it.kilograms }
        val meanX = xs.average()
        val meanY = ys.average()
        val covariance = xs.zip(ys).sumOf { (x, y) -> (x - meanX) * (y - meanY) }
        val variance = xs.sumOf { (it - meanX) * (it - meanX) }
        if (variance <= 0) return null
        val slope = covariance / variance
        val todayX = ChronoUnit.DAYS.between(first, today).toDouble()
        val trend = meanY + slope * (todayX - meanX)
        return Result(Math.rint(trend * 10) / 10, Math.rint(slope * 7 / trend * 100 * 100) / 100, recent.size, span)
    }

    fun advice(result: Result, plannedPercent: Double?, currentAdjustment: Double): Advice {
        val planned = plannedPercent ?: 0.0
        val difference = result.weeklyPercent - planned
        val actual = German.number(abs(result.weeklyPercent), 2)
        val direction = if (result.weeklyPercent < 0) "ab" else "zu"
        if (result.weeklyPercent < -GoalRules.MAX_LOSS_PERCENT_PER_WEEK) {
            val kcal = step(-difference, result.trendKilograms, currentAdjustment, 100.0)
            return Advice(
                Kind.TOO_FAST,
                "Du nimmst gerade etwa $actual % pro Woche ab – schneller als die Obergrenze von 1 %. Iss täglich etwa ${kcal.toInt()} kcal mehr, damit du Muskeln behältst.",
                kcal,
            )
        }
        if (abs(difference) <= TOLERANCE_PERCENT) {
            return Advice(Kind.ON_TRACK, "Dein Gewicht entwickelt sich wie geplant (etwa $actual % pro Woche $direction). Weiter so.", 0.0)
        }
        val kcal = step(-difference, result.trendKilograms, currentAdjustment, 50.0)
        if (kcal == 0.0) {
            return Advice(Kind.ON_TRACK, "Der Verlauf weicht etwas vom Plan ab, die Anpassung ist aber schon ausgeschöpft. Prüfe, ob alle Mahlzeiten erfasst sind.", 0.0)
        }
        val planText = plannedPercent?.let { "geplant ${German.number(abs(it), 2)} % ${if (it < 0) "ab" else "zu"}" } ?: "geplant: halten"
        val change = if (kcal > 0) "${kcal.toInt()} kcal mehr" else "${(-kcal).toInt()} kcal weniger"
        return Advice(
            if (kcal > 0) Kind.EAT_MORE else Kind.EAT_LESS,
            "Dein Gewicht ändert sich um etwa $actual % pro Woche $direction ($planText). Vorschlag: täglich $change. In zwei Wochen prüft die App erneut.",
            kcal,
        )
    }

    /** kcal pro Tag aus der Abweichung (7.700 kcal je kg), begrenzt und auf 50 gerundet. */
    fun step(percentPerWeek: Double, weight: Double, current: Double, minimum: Double): Double {
        val raw = percentPerWeek / 100 * weight * 7_700 / 7
        var value = raw.coerceIn(-MAX_STEP_KCAL, MAX_STEP_KCAL)
        if (abs(value) < minimum) value = if (value < 0) -minimum else minimum
        val total = (current + value).coerceIn(-MAX_TOTAL_KCAL, MAX_TOTAL_KCAL)
        return Math.rint((total - current) / 50) * 50
    }
}

/** Prognose beim Abnehmen (Port von `WeightForecast`): 4/8/12 Wochen, nie unter BMI 18,5, Defizit höchstens 25 %. */
object WeightForecast {
    private const val KCAL_PER_KG = 7_700.0
    private const val MAX_DEFICIT_SHARE = 0.25
    val HORIZONS = listOf(4, 8, 12)

    data class Point(val weeks: Int, val day: LocalDate, val kilograms: Double)

    data class Result(
        val weeklyPercent: Double,
        val weeklyKilograms: Double,
        val dailyDeficit: Double,
        val deficitCapped: Boolean,
        val points: List<Point>,
        val target: Double?,
        val weeksToTarget: Int?,
        val floorKilograms: Double,
    )

    fun compute(current: Double, weeklyChangePercent: Double, heightCm: Double, maintenanceKcal: Double?, target: Double?, today: LocalDate): Result? {
        if (current <= 0 || weeklyChangePercent >= 0) return null
        val meters = heightCm / 100
        val floor = if (meters > 0) ceil(GoalRules.MINIMUM_BMI * meters * meters * 10) / 10 else 0.0
        var percent = minOf(-weeklyChangePercent, GoalRules.MAX_LOSS_PERCENT_PER_WEEK)
        var deficit = percent / 100 * current * KCAL_PER_KG / 7
        var capped = false
        if (maintenanceKcal != null && maintenanceKcal > 0 && deficit > maintenanceKcal * MAX_DEFICIT_SHARE) {
            deficit = maintenanceKcal * MAX_DEFICIT_SHARE
            percent = deficit * 7 / KCAL_PER_KG / current * 100
            capped = true
        }
        val goal = target?.let { maxOf(it, floor) }
        fun weight(weeks: Int): Double = maxOf(current * (1 - percent / 100).pow(weeks), goal ?: floor, floor)
        val points = HORIZONS.map { Point(it, today.plusDays(it * 7L), Math.rint(weight(it) * 10) / 10) }
        val weeksToTarget = if (goal != null && goal < current && percent > 0) ceil(ln(goal / current) / ln(1 - percent / 100)).toInt() else null
        return Result(
            Math.rint(percent * 100) / 100, Math.rint(current * percent / 100 * 100) / 100, Math.rint(deficit / 10) * 10,
            capped, points, goal, weeksToTarget, floor,
        )
    }
}
