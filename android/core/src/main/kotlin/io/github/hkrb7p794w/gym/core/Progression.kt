package io.github.hkrb7p794w.gym.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToLong

/**
 * Doppelprogression im Wiederholungsbereich, portiert aus `GymProgression` in CoachCore (dort aus `gym_progress.py`).
 *
 * Zuerst die Wiederholungen bis zur Obergrenze steigern, dann das Gewicht erhöhen (2–10 %, mindestens ein
 * Gerätesprung) und wieder unten beginnen. Auslöser: alle Arbeitssätze an der Obergrenze, „2 für 2“ (ACSM 2009) oder
 * zweimal in Folge knapp an der Obergrenze. Ohne RIR-Eingabe und ohne Tagesampel (die gibt es auf Android nicht).
 */
object Progression {
    /** Sätze unter 80 % des schwersten Satzes gelten als Aufwärmen. */
    const val WARMUP_FRACTION = 0.80
    const val MINIMUM_WORKING_SETS = 2
    const val BREAK_DAYS = 21
    const val RESTART_FACTOR = 0.90
    const val MAX_INCREASE_PERCENT = 10.0
    private const val WEIGHT_TOLERANCE = 0.011

    enum class Status { INCREASE, RESTART, CHECK, BUILD, BASELINE, NO_WEIGHT }

    data class Advice(
        val status: Status,
        val headline: String,
        val detail: String,
        val nextWeightKg: Double? = null,
    )

    data class Entry(val day: LocalDate, val weight: Double, val reps: List<Int>) {
        val minReps: Int get() = reps.minOrNull() ?: 0
        val maxReps: Int get() = reps.maxOrNull() ?: 0
        val lastReps: Int get() = reps.lastOrNull() ?: 0
    }

    /** Arbeitssätze: mindestens 80 % des schwersten Gewichts; ohne Gewicht alle Sätze. */
    fun workingSets(sets: List<SetEntry>): List<SetEntry> {
        val valid = sets.filter { it.done && it.reps > 0 && !it.warmup }.map { it.copy(weightKg = max(it.weightKg, 0.0)) }
        val top = valid.maxOfOrNull { it.weightKg } ?: return emptyList()
        if (top <= 0) return valid
        return valid.filter { it.weightKg >= top * WARMUP_FRACTION }
    }

    fun summary(day: LocalDate, sets: List<SetEntry>): Entry? {
        val working = workingSets(sets)
        val top = working.maxOfOrNull { it.weightKg } ?: return null
        val atTop = if (top > 0) working.filter { abs(it.weightKg - top) <= WEIGHT_TOLERANCE } else working
        return Entry(day, top, atTop.map { it.reps })
    }

    /** Verlauf einer Übung (alt → neu); mehrere Einheiten am selben Tag werden zusammengelegt. */
    fun history(exerciseId: String, sessions: List<Session>, zone: ZoneId = ZoneId.systemDefault()): List<Entry> {
        val perDay = sortedMapOf<LocalDate, MutableList<SetEntry>>()
        for (session in sessions) {
            val day = Instant.ofEpochMilli(session.startedAt).atZone(zone).toLocalDate()
            for (exercise in session.exercises.filter { it.exerciseId == exerciseId }) {
                perDay.getOrPut(day) { mutableListOf() }.addAll(exercise.sets)
            }
        }
        return perDay.mapNotNull { (day, sets) -> summary(day, sets) }
    }

    /** Wie `round` in CoachCore: auf den Gerätesprung, halbe Werte zur geraden Zahl. */
    fun round(value: Double, step: Double): Double {
        val units = Math.rint(value / step)
        return (units * step * 100).roundToLong() / 100.0
    }

    /** Nächstes Gewicht: ca. `percent` % mehr, mindestens ein Gerätesprung, höchstens 10 % (sofern möglich). */
    fun nextWeight(weight: Double, step: Double, percent: Double): Pair<Double, Double>? {
        if (weight <= 0) return null
        var increase = round(max(weight * percent / 100, step), step)
        if (increase == 0.0) increase = step
        val cap = weight * MAX_INCREASE_PERCENT / 100
        if (increase > cap && cap >= step) increase = floor(cap / step) * step
        val next = ((weight + increase) * 100).roundToLong() / 100.0
        return next to (increase / weight * 1000).roundToLong() / 10.0
    }

    fun evaluate(exercise: Exercise, entries: List<Entry>, today: LocalDate): Advice? {
        val last = entries.lastOrNull() ?: return null
        val previous = if (entries.size >= 2) entries[entries.size - 2] else null
        val low = exercise.repRange.first
        val high = exercise.repRange.last
        val weight = last.weight
        val daysSince = ChronoUnit.DAYS.between(last.day, today)

        if (exercise.tracking == Tracking.TIME) {
            return Advice(Status.NO_WEIGHT, "Haltübung", "Zeit statt Gewicht steigern: Ziel $low–$high s.")
        }
        if (weight <= 0) {
            if (last.minReps >= high) {
                return Advice(
                    Status.INCREASE,
                    "Zusatzgewicht beginnen",
                    "Alle Sätze mit ${reps(last.reps)} Wdh. (Ziel $low–$high) – nächstes Mal mit kleinem Zusatzgewicht starten.",
                )
            }
            return Advice(Status.BUILD, "Wiederholungen steigern", "${reps(last.reps)} Wdh. – Ziel: alle Sätze auf $high.")
        }
        if (daysSince > BREAK_DAYS) {
            val restart = round(weight * RESTART_FACTOR, exercise.step)
            return Advice(
                Status.RESTART,
                "Wiedereinstieg mit ca. ${kg(restart)} kg",
                "Letzte Einheit vor $daysSince Tagen mit ${kg(weight)} kg × ${reps(last.reps)}. Nach der Pause ~10 % " +
                    "weniger ansetzen und in 1–2 Einheiten wieder hocharbeiten.",
                restart,
            )
        }

        val next = nextWeight(weight, exercise.step, exercise.percent)
        val sameWeightPrevious = previous?.let { abs(it.weight - weight) <= WEIGHT_TOLERANCE } ?: false
        // A: alle Arbeitssätze an der Obergrenze
        val ruleA = last.reps.size >= MINIMUM_WORKING_SETS && last.minReps >= high
        // B (2 für 2): letzte Serie in zwei Einheiten in Folge ≥ Ziel + 1
        val ruleB = sameWeightPrevious && last.lastReps >= high + 1 && (previous?.lastReps ?: 0) >= high + 1
        // C: zweimal in Folge knapp an der Obergrenze
        val ruleC = sameWeightPrevious && last.reps.size >= MINIMUM_WORKING_SETS && last.minReps >= high - 1 &&
            (previous?.minReps ?: 0) >= high - 1 && last.maxReps >= high
        // Warnsignal: zweimal mindestens 2 Wdh. unter der Untergrenze bei gleichem oder höherem Gewicht
        val drop = previous?.let {
            last.minReps <= low - 2 && it.minReps <= low - 2 && last.weight >= it.weight - WEIGHT_TOLERANCE
        } ?: false

        if ((ruleA || ruleB || ruleC) && next != null) {
            val (nextKg, percent) = next
            val why = when {
                ruleA -> "alle ${last.reps.size} Arbeitssätze bei ${reps(last.reps)} Wdh. (Ziel $low–$high)"
                ruleB -> "letzte Serie in zwei Einheiten in Folge mit ${previous?.lastReps} bzw. ${last.lastReps} Wdh. (Ziel $high)"
                else -> "zwei Einheiten in Folge knapp an der Obergrenze (${reps(previous?.reps ?: emptyList())} → " +
                    "${reps(last.reps)} Wdh., Ziel $high)"
            }
            var detail = "${kg(weight)} kg: $why. Danach wieder bei $low Wdh. beginnen."
            if (percent > MAX_INCREASE_PERCENT) {
                detail += " Kleinster Sprung ist größer als 10 %: erst Zwischenschritt oder nur den ersten Satz steigern."
            }
            return Advice(Status.INCREASE, "Erhöhen auf ${kg(nextKg)} kg (+${kg(percent)} %)", detail, nextKg)
        }
        if (drop && previous != null) {
            return Advice(
                Status.CHECK,
                "Gewicht halten oder senken",
                "Zwei Einheiten in Folge mindestens 2 Wdh. unter dem Ziel $low–$high (${reps(previous.reps)} → " +
                    "${reps(last.reps)}) bei ${kg(weight)} kg. Nicht erhöhen; bei weiterer Stagnation 5–10 % reduzieren.",
            )
        }
        if (entries.size == 1) {
            return Advice(
                Status.BASELINE,
                "Ausgangswert ${kg(weight)} kg",
                "${reps(last.reps)} Wdh. – eine Einheit reicht noch nicht für eine Empfehlung. Ziel: alle Sätze auf $high Wdh.",
            )
        }
        val left = max(0, high - last.minReps)
        return Advice(
            Status.BUILD,
            "Bei ${kg(weight)} kg bleiben",
            "${reps(last.reps)} Wdh. – noch $left Wdh. bis zur Obergrenze $high im schwächsten Satz. Dann auf " +
                "${kg(next?.first ?: weight)} kg gehen.",
            next?.first,
        )
    }

    private fun reps(values: List<Int>): String = values.joinToString("/")

    /** Deutsche Zahl ohne überflüssige Nachkommastellen („62,5“, „60“). */
    fun kg(value: Double): String {
        val rounded = (value * 100).roundToLong() / 100.0
        val text = if (rounded == floor(rounded)) rounded.toLong().toString() else rounded.toString().trimEnd('0')
        return text.replace('.', ',')
    }
}
