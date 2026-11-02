package io.github.hkrb7p794w.gym.core

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** JSON für Speicher, Sicherung und Bibliothek: unbekannte Felder ignorieren (spätere Versionen bleiben lesbar). */
val GymJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    prettyPrint = false
}

object Library {
    fun parse(json: String): List<Exercise> = GymJson.decodeFromString(json)

    /** Suche über Name und Muskelgruppe, nach Gruppe sortiert. */
    fun search(all: List<Exercise>, text: String, group: String? = null): List<Exercise> {
        val query = text.trim().lowercase()
        return all.filter { exercise ->
            (group == null || exercise.group == group) &&
                (query.isEmpty() || exercise.name.lowercase().contains(query) || exercise.group.lowercase().contains(query))
        }.sortedWith(compareBy({ MUSCLE_GROUPS.indexOf(it.group).let { index -> if (index < 0) 99 else index } }, { it.name }))
    }
}

/** Letzte Ausführung einer Übung: zum Vorbelegen der Sätze und als Hinweis „Letztes Mal“. */
data class LastPerformance(val startedAt: Long, val sets: List<SetEntry>)

object Stats {
    fun last(exerciseId: String, sessions: List<Session>): LastPerformance? =
        sessions.filter { it.endedAt != null }.sortedByDescending { it.startedAt }.firstNotNullOfOrNull { session ->
            session.exercises.firstOrNull { it.exerciseId == exerciseId && it.sets.any(SetEntry::done) }
                ?.let { LastPerformance(session.startedAt, it.sets.filter(SetEntry::done)) }
        }

    /** Geschätztes Einwiederholungsmaximum nach Epley (nur bis 12 Wdh. sinnvoll). */
    fun estimatedOneRepMax(set: SetEntry): Double? =
        if (set.weightKg <= 0 || set.reps <= 0 || set.reps > 12) null else set.weightKg * (1 + set.reps / 30.0)

    fun bestOneRepMax(exerciseId: String, sessions: List<Session>): Double? =
        sessions.flatMap { session -> session.exercises.filter { it.exerciseId == exerciseId } }
            .flatMap { it.sets.filter { set -> set.done && !set.warmup } }
            .mapNotNull(::estimatedOneRepMax)
            .maxOrNull()

    /** Kurzform der Sätze: „60 kg × 8/8/7“ bzw. „12/10/9 Wdh.“. */
    fun describe(sets: List<SetEntry>, tracking: Tracking): String {
        val working = sets.filter { !it.warmup }.ifEmpty { sets }
        if (working.isEmpty()) return ""
        val reps = working.joinToString("/") { it.reps.toString() }
        val unit = if (tracking == Tracking.TIME) "s" else "Wdh."
        val weights = working.map { it.weightKg }.distinct()
        return when {
            weights.all { it <= 0 } -> "$reps $unit"
            weights.size == 1 -> "${Progression.kg(weights[0])} kg × $reps"
            else -> working.joinToString(", ") { "${Progression.kg(it.weightKg)}×${it.reps}" }
        }
    }
}

/**
 * Änderungen am Datenbestand – rein funktional, damit sie ohne Android testbar sind. Die App ruft sie auf und
 * speichert das Ergebnis.
 */
object Workouts {
    fun newId(): String = UUID.randomUUID().toString()

    fun start(data: AppData, now: Long, routine: Routine? = null, library: List<Exercise> = emptyList()): AppData {
        if (data.active != null) return data
        val exercises = routine?.exercises?.mapNotNull { planned ->
            val exercise = find(planned.exerciseId, library, data.customExercises) ?: return@mapNotNull null
            logged(exercise, data.sessions, planned.sets)
        } ?: emptyList()
        val session = Session(
            id = newId(),
            startedAt = now,
            name = routine?.name ?: "Training",
            exercises = exercises,
            routineId = routine?.id,
        )
        return data.copy(active = session)
    }

    fun find(id: String, library: List<Exercise>, custom: List<Exercise>): Exercise? =
        library.firstOrNull { it.id == id } ?: custom.firstOrNull { it.id == id }

    /** Neue Übung im Training: Sätze aus der letzten Ausführung vorbelegen (Gewicht und Wiederholungen, unerledigt). */
    /** @param setCount Zahl der Sätze aus dem Plan; ohne Plan wie beim letzten Mal, sonst 3. */
    fun logged(exercise: Exercise, sessions: List<Session>, setCount: Int? = null): LoggedExercise {
        val last = Stats.last(exercise.id, sessions)?.sets?.filter { !it.warmup }.orEmpty()
        val count = (setCount ?: last.size.takeIf { it > 0 } ?: 3).coerceIn(1, 20)
        val template = last.lastOrNull()
        val sets = (0 until count).map { index ->
            val source = last.getOrNull(index) ?: template
            SetEntry(weightKg = source?.weightKg ?: 0.0, reps = source?.reps ?: exercise.repRange.first, done = false)
        }
        return LoggedExercise(exercise.id, exercise.name, exercise.group, sets)
    }

    fun updateActive(data: AppData, change: (Session) -> Session): AppData =
        data.active?.let { data.copy(active = change(it)) } ?: data

    fun addExercise(data: AppData, exercise: Exercise): AppData =
        updateActive(data) { it.copy(exercises = it.exercises + logged(exercise, data.sessions)) }

    fun removeExercise(data: AppData, index: Int): AppData =
        updateActive(data) { session -> session.copy(exercises = session.exercises.filterIndexed { i, _ -> i != index }) }

    fun moveExercise(data: AppData, index: Int, offset: Int): AppData = updateActive(data) { session ->
        val target = index + offset
        if (index !in session.exercises.indices || target !in session.exercises.indices) return@updateActive session
        val list = session.exercises.toMutableList()
        list.add(target, list.removeAt(index))
        session.copy(exercises = list)
    }

    fun updateSet(data: AppData, exercise: Int, set: Int, change: (SetEntry) -> SetEntry): AppData =
        updateActive(data) { session ->
            session.copy(
                exercises = session.exercises.mapIndexed { i, logged ->
                    if (i != exercise) logged else logged.copy(sets = logged.sets.mapIndexed { j, s -> if (j == set) change(s) else s })
                },
            )
        }

    /** Weiteren Satz anhängen, mit den Werten des letzten Satzes. */
    fun addSet(data: AppData, exercise: Int): AppData = updateActive(data) { session ->
        session.copy(
            exercises = session.exercises.mapIndexed { i, logged ->
                if (i != exercise) logged else logged.copy(sets = logged.sets + (logged.sets.lastOrNull()?.copy(done = false) ?: SetEntry()))
            },
        )
    }

    fun removeSet(data: AppData, exercise: Int, set: Int): AppData = updateActive(data) { session ->
        session.copy(
            exercises = session.exercises.mapIndexed { i, logged ->
                if (i != exercise) logged else logged.copy(sets = logged.sets.filterIndexed { j, _ -> j != set })
            },
        )
    }

    /**
     * Training abschließen: unerledigte Sätze und leere Übungen fallen weg. Ohne einen erledigten Satz wird nichts
     * gespeichert (wie Verwerfen).
     */
    fun finish(data: AppData, now: Long): AppData {
        val active = data.active ?: return data
        val exercises = active.exercises
            .map { it.copy(sets = it.sets.filter(SetEntry::done)) }
            .filter { it.sets.isNotEmpty() }
        if (exercises.isEmpty()) return data.copy(active = null)
        val finished = active.copy(endedAt = now, exercises = exercises)
        return data.copy(active = null, sessions = (data.sessions + finished).sortedByDescending { it.startedAt })
    }

    fun discard(data: AppData): AppData = data.copy(active = null)

    fun deleteSession(data: AppData, id: String): AppData = data.copy(sessions = data.sessions.filter { it.id != id })

    /** Plan aus einem Training: Übungen in der Reihenfolge, Zahl der Arbeitssätze. */
    fun routineFrom(session: Session, name: String): Routine = Routine(
        id = newId(),
        name = name.trim().ifEmpty { session.name },
        exercises = session.exercises.map { RoutineExercise(it.exerciseId, it.sets.count { set -> !set.warmup }.coerceAtLeast(1)) },
    )

    fun saveRoutine(data: AppData, routine: Routine): AppData {
        val exists = data.routines.any { it.id == routine.id }
        return data.copy(routines = if (exists) data.routines.map { if (it.id == routine.id) routine else it } else data.routines + routine)
    }

    fun deleteRoutine(data: AppData, id: String): AppData = data.copy(routines = data.routines.filter { it.id != id })

    /** Eigene Übung anlegen; gibt es den Kurznamen schon, wird die vorhandene genutzt. */
    fun addCustom(data: AppData, exercise: Exercise, library: List<Exercise>): Pair<AppData, Exercise> {
        val existing = find(exercise.id, library, data.customExercises)
        if (existing != null) return data to existing
        return data.copy(customExercises = data.customExercises + exercise) to exercise
    }
}

/** Speichern und Sichern: JSON lesen und schreiben, mit Prüfung beim Einlesen einer Sicherung. */
object Backup {
    fun encode(data: AppData): String = GymJson.encodeToString(AppData.serializer(), data)

    /** Liest eine Sicherung; `null`, wenn die Datei keine gültige Sicherung dieser App ist. */
    fun decode(text: String): AppData? = try {
        val data = GymJson.decodeFromString(AppData.serializer(), text)
        if (data.version > AppData.CURRENT_VERSION) null else data
    } catch (_: SerializationException) {
        null
    } catch (_: IllegalArgumentException) {
        null
    }

    /**
     * Sicherung einspielen, ohne Vorhandenes zu verlieren: Trainings, Pläne und eigene Übungen werden über ihre ID
     * zusammengeführt; bei gleicher ID gewinnt der Stand auf dem Gerät.
     */
    fun merge(current: AppData, imported: AppData): AppData {
        val sessions = (current.sessions + imported.sessions.filter { s -> current.sessions.none { it.id == s.id } })
            .sortedByDescending { it.startedAt }
        val routines = current.routines + imported.routines.filter { r -> current.routines.none { it.id == r.id } }
        val custom = current.customExercises + imported.customExercises.filter { e -> current.customExercises.none { it.id == e.id } }
        val meals = (current.meals + imported.meals.filter { m -> current.meals.none { it.id == m.id } }).sortedBy { it.createdAt }
        val favorites = current.favorites + imported.favorites.filter { f -> current.favorites.none { it.id == f.id } }
        val foods = current.foods + imported.foods.filter { f -> current.foods.none { FoodSearch.normalized(it.name) == FoodSearch.normalized(f.name) } }
        // Einstellungen der Sicherung nur übernehmen, wenn auf dem Gerät noch nichts eingerichtet ist (neues Handy).
        val nutrition = if (current.nutrition.configured || !imported.nutrition.configured) current.nutrition else imported.nutrition
        return current.copy(
            sessions = sessions, routines = routines, customExercises = custom, meals = meals, favorites = favorites,
            foods = foods, nutrition = nutrition, dayTypes = imported.dayTypes + current.dayTypes,
            weekDayTypes = if (current.weekDayTypes.isEmpty()) imported.weekDayTypes else current.weekDayTypes,
            recipes = current.recipes + imported.recipes.filter { r -> current.recipes.none { it.id == r.id } },
            weights = WeightTrend.merged(imported.weights + current.weights),
            weeklyPlan = current.weeklyPlan ?: imported.weeklyPlan,
        )
    }

    fun fileName(now: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        "IronLudi-Gym-Sicherung-${Instant.ofEpochMilli(now).atZone(zone).toLocalDate()}.json"
}
