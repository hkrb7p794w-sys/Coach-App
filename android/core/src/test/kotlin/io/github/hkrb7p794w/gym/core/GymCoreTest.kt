package io.github.hkrb7p794w.gym.core

import java.io.File
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GymCoreTest {
    private val bench = Exercise(id = "bankdruecken", name = "Bankdrücken", group = "Brust", lowerReps = 6, upperReps = 10)
    private val dips = Exercise(id = "dips", name = "Dips", group = "Trizeps", tracking = Tracking.REPS, lowerReps = 6, upperReps = 12)

    private fun day(text: String) = LocalDate.parse(text)

    private fun millis(text: String) = day(text).atTime(18, 0).toInstant(ZoneOffset.UTC).toEpochMilli()

    private fun session(date: String, exercise: Exercise, weight: Double, reps: List<Int>) = Session(
        id = date + exercise.id,
        startedAt = millis(date),
        endedAt = millis(date) + 3_600_000,
        exercises = listOf(LoggedExercise(exercise.id, exercise.name, exercise.group, reps.map { SetEntry(weight, it, done = true) })),
    )

    private fun advise(exercise: Exercise, vararg sessions: Session, today: String = "2026-10-22") =
        Progression.evaluate(exercise, Progression.history(exercise.id, sessions.toList(), ZoneOffset.UTC), day(today))

    @Test
    fun nextWeightMatchesCoachCore() {
        // Gleiche Fälle wie `nextWeightMatchesLegacy` in CoachCore (GymTests.swift).
        assertEquals(154.0 to 3.4, Progression.nextWeight(149.0, 5.0, 5.0))
        assertEquals(23.75 to 5.6, Progression.nextWeight(22.5, 1.25, 2.5))
        assertEquals(112.5 to 2.3, Progression.nextWeight(110.0, 2.5, 2.5))
        assertEquals(8.5 to 13.3, Progression.nextWeight(7.5, 1.0, 2.5))
        assertNull(Progression.nextWeight(0.0, 1.0, 2.5))
    }

    @Test
    fun allSetsAtTopIncrease() {
        val advice = assertNotNull(advise(bench, session("2026-10-20", bench, 60.0, listOf(10, 10, 10))))
        assertEquals(Progression.Status.INCREASE, advice.status)
        assertEquals(62.5, advice.nextWeightKg)
        assertEquals("Erhöhen auf 62,5 kg (+4,2 %)", advice.headline)
    }

    @Test
    fun belowTopBuildsAndFirstSessionIsBaseline() {
        val first = session("2026-10-15", bench, 60.0, listOf(8, 8, 7))
        assertEquals(Progression.Status.BASELINE, advise(bench, first)?.status)
        val second = session("2026-10-20", bench, 60.0, listOf(9, 8, 8))
        val advice = assertNotNull(advise(bench, first, second))
        assertEquals(Progression.Status.BUILD, advice.status)
        assertEquals("Bei 60 kg bleiben", advice.headline)
    }

    @Test
    fun twoSessionsNearTopIncrease() {
        val advice = advise(
            bench,
            session("2026-10-15", bench, 60.0, listOf(10, 9, 9)),
            session("2026-10-20", bench, 60.0, listOf(10, 10, 9)),
        )
        assertEquals(Progression.Status.INCREASE, advice?.status)
    }

    @Test
    fun repeatedDropIsFlaggedAndLongBreakRestarts() {
        val drop = advise(
            bench,
            session("2026-10-15", bench, 70.0, listOf(4, 4, 3)),
            session("2026-10-20", bench, 70.0, listOf(4, 3, 3)),
        )
        assertEquals(Progression.Status.CHECK, drop?.status)
        val restart = advise(bench, session("2026-09-01", bench, 60.0, listOf(8, 8)), today = "2026-10-22")
        assertEquals(Progression.Status.RESTART, restart?.status)
        assertEquals(55.0, restart?.nextWeightKg)
    }

    @Test
    fun bodyweightAndWarmupSets() {
        val advice = advise(dips, session("2026-10-20", dips, 0.0, listOf(12, 12)))
        assertEquals("Zusatzgewicht beginnen", advice?.headline)
        val entry = Progression.summary(
            day("2026-10-20"),
            listOf(SetEntry(40.0, 10, true), SetEntry(60.0, 8, true), SetEntry(60.0, 7, true), SetEntry(20.0, 12, true, warmup = true)),
        )
        assertEquals(60.0, entry?.weight)
        assertEquals(listOf(8, 7), entry?.reps)
    }

    @Test
    fun workoutFlowPrefillsFinishesAndDropsOpenSets() {
        val past = session("2026-10-20", bench, 60.0, listOf(10, 9))
        var data = AppData(sessions = listOf(past))
        data = Workouts.start(data, now = millis("2026-10-22"))
        data = Workouts.addExercise(data, bench)
        val logged = data.active!!.exercises.single()
        assertEquals(listOf(10, 9), logged.sets.map { it.reps })
        assertTrue(logged.sets.all { it.weightKg == 60.0 && !it.done })

        data = Workouts.updateSet(data, 0, 0) { it.copy(reps = 11, done = true) }
        data = Workouts.addSet(data, 0)
        assertEquals(3, data.active!!.exercises[0].sets.size)
        data = Workouts.finish(data, now = millis("2026-10-22") + 3_000_000)
        assertNull(data.active)
        assertEquals(2, data.sessions.size)
        val saved = data.sessions.first()
        assertEquals(listOf(11), saved.exercises.single().sets.map { it.reps })
        assertEquals(660.0, saved.volumeKg)

        // Ohne erledigten Satz wird nichts gespeichert.
        val empty = Workouts.finish(Workouts.addExercise(Workouts.start(data, 0), bench), 1)
        assertEquals(2, empty.sessions.size)
        assertNull(empty.active)
    }

    @Test
    fun routinesStartWithPlannedSets() {
        val routine = Routine("r1", "Push", listOf(RoutineExercise("bankdruecken", 4), RoutineExercise("unbekannt", 3)))
        val data = Workouts.start(AppData(routines = listOf(routine)), 0, routine, listOf(bench))
        val active = assertNotNull(data.active)
        assertEquals("Push", active.name)
        assertEquals(listOf(4), active.exercises.map { it.sets.size })
        val fromSession = Workouts.routineFrom(session("2026-10-20", bench, 60.0, listOf(8, 8, 8)), " ")
        assertEquals(listOf(RoutineExercise("bankdruecken", 3)), fromSession.exercises)
    }

    @Test
    fun backupRoundTripAndMergeKeepsLocalData() {
        val local = AppData(sessions = listOf(session("2026-10-20", bench, 60.0, listOf(8))))
        val other = AppData(
            sessions = listOf(session("2026-10-20", bench, 99.0, listOf(1)), session("2026-10-18", dips, 0.0, listOf(10))),
            customExercises = listOf(Exercise.custom("Landmine Press", "Schultern", Tracking.WEIGHT_REPS)),
        )
        val decoded = assertNotNull(Backup.decode(Backup.encode(other)))
        val merged = Backup.merge(local, decoded)
        assertEquals(2, merged.sessions.size)
        // Gleiche ID: Stand auf dem Gerät bleibt.
        assertEquals(60.0, merged.sessions.first { it.id == local.sessions[0].id }.exercises[0].sets[0].weightKg)
        assertEquals("eigen_landmine_press", merged.customExercises.single().id)
        assertNull(Backup.decode("{kein json"))
        assertNull(Backup.decode("""{"version": 99}"""))
        // Unbekannte Felder späterer Versionen stören nicht.
        assertNotNull(Backup.decode("""{"version": 1, "neu": true, "sessions": []}"""))
    }

    @Test
    fun customExerciseSlugAndDescribe() {
        assertEquals("eigen_schulterdruecken_maschine", Exercise.custom(" Schulterdrücken Maschine ", "Schultern", Tracking.WEIGHT_REPS).id)
        assertEquals("60 kg × 8/8/7", Stats.describe(listOf(SetEntry(60.0, 8), SetEntry(60.0, 8), SetEntry(60.0, 7)), Tracking.WEIGHT_REPS))
        assertEquals("30/45 s", Stats.describe(listOf(SetEntry(0.0, 30), SetEntry(0.0, 45)), Tracking.TIME))
        assertEquals("62,5", Progression.kg(62.5))
    }

    @Test
    fun bundledLibraryParsesAndMatchesCoachCoreIds() {
        val file = File("../app/src/main/assets/exercises.json")
        val library = Library.parse(file.readText())
        assertTrue(library.size >= 40)
        assertTrue(library.map { it.id }.toSet().size == library.size, "IDs sind eindeutig")
        val bench = library.first { it.id == "bankdruecken" }
        assertEquals(6..10, bench.repRange)
        assertEquals(Tracking.TIME, library.first { it.id == "plank" }.tracking)
        assertTrue(library.all { it.group in MUSCLE_GROUPS })
        assertEquals("Brust", Library.search(library, "").first().group)
        assertTrue(Library.search(library, "kniebeuge").any { it.id == "kniebeuge" })
    }
}
