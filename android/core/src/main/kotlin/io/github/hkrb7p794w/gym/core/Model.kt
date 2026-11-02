package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Wie eine Übung erfasst wird (gleiche Werte wie `ExerciseTracking` in CoachCore). */
@Serializable
enum class Tracking {
    /** Gewicht × Wiederholungen. */
    @SerialName("weightReps")
    WEIGHT_REPS,

    /** Nur Wiederholungen (Körpergewicht, optional mit Zusatzgewicht). */
    @SerialName("reps")
    REPS,

    /** Haltezeit in Sekunden (im Feld „Wiederholungen“). */
    @SerialName("time")
    TIME,
}

/** Übung der Bibliothek (aus `exercises.json`, erzeugt aus CoachCore) oder selbst angelegt. */
@Serializable
data class Exercise(
    val id: String,
    val name: String,
    val group: String,
    val secondary: List<String> = emptyList(),
    val equipment: List<String> = emptyList(),
    val tracking: Tracking = Tracking.WEIGHT_REPS,
    val compound: Boolean = false,
    val lowerReps: Int = 8,
    val upperReps: Int = 12,
    /** Kleinster Gewichtssprung in kg. */
    val step: Double = 2.5,
    /** Angestrebte Steigerung in Prozent. */
    val percent: Double = 2.5,
    val instructions: List<String> = emptyList(),
    val custom: Boolean = false,
) {
    val repRange: IntRange get() = lowerReps..maxOf(lowerReps, upperReps)

    companion object {
        /** Eigene Übung; ID wie in CoachCore (`eigen_` + Kurzname). */
        fun custom(name: String, group: String, tracking: Tracking): Exercise {
            val trimmed = name.trim()
            val isTime = tracking == Tracking.TIME
            return Exercise(
                id = "eigen_" + slug(trimmed),
                name = trimmed,
                group = group,
                tracking = tracking,
                lowerReps = if (isTime) 20 else 8,
                upperReps = if (isTime) 60 else 12,
                custom = true,
            )
        }

        /** Kurzname aus dem Anzeigenamen: Kleinbuchstaben, Umlaute ausgeschrieben, sonst `_`. */
        fun slug(name: String): String {
            val replaced = name.lowercase()
                .replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
            return replaced.replace(Regex("[^a-z0-9]+"), "_").trim('_').ifEmpty { "uebung" }
        }
    }
}

/** Muskelgruppen in der Reihenfolge der App. */
val MUSCLE_GROUPS = listOf("Brust", "Rücken", "Schultern", "Bizeps", "Trizeps", "Beine", "Rumpf", "Unterarme", "Sonstige")

@Serializable
data class SetEntry(
    val weightKg: Double = 0.0,
    val reps: Int = 0,
    val done: Boolean = false,
    val warmup: Boolean = false,
)

@Serializable
data class LoggedExercise(
    val exerciseId: String,
    val name: String,
    val group: String,
    val sets: List<SetEntry> = emptyList(),
)

@Serializable
data class Session(
    val id: String,
    /** Millisekunden seit 1970 (UTC). */
    val startedAt: Long,
    val endedAt: Long? = null,
    val name: String = "Training",
    val exercises: List<LoggedExercise> = emptyList(),
    val routineId: String? = null,
) {
    /** Erledigte Sätze (ohne Aufwärmen). */
    val workingSets: Int get() = exercises.sumOf { exercise -> exercise.sets.count { it.done && !it.warmup } }

    /** Bewegte Last in kg (erledigte Arbeitssätze, Gewicht × Wiederholungen). */
    val volumeKg: Double
        get() = exercises.sumOf { exercise ->
            exercise.sets.filter { it.done && !it.warmup }.sumOf { it.weightKg * it.reps }
        }
}

@Serializable
data class RoutineExercise(
    val exerciseId: String,
    val sets: Int = 3,
)

@Serializable
data class Routine(
    val id: String,
    val name: String,
    val exercises: List<RoutineExercise> = emptyList(),
)

@Serializable
data class Settings(
    /** Pause nach einem erledigten Satz; 0 = keine. */
    val restSeconds: Int = 90,
    val keepScreenOn: Boolean = true,
)

/** Alles, was die App speichert – eine JSON-Datei im App-Speicher, auch als Sicherung exportierbar. */
@Serializable
data class AppData(
    val version: Int = CURRENT_VERSION,
    val sessions: List<Session> = emptyList(),
    val active: Session? = null,
    val routines: List<Routine> = emptyList(),
    val customExercises: List<Exercise> = emptyList(),
    val settings: Settings = Settings(),
) {
    companion object {
        const val CURRENT_VERSION = 1
    }
}
