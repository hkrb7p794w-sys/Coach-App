package io.github.hkrb7p794w.gym

import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Game
import io.github.hkrb7p794w.gym.core.GameStats
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import java.time.LocalDate

data class LeaderboardEntry(
    val rank: Int,
    val username: String,
    val displayName: String,
    val me: Boolean,
    val weekPoints: Int,
    val dayStreak: Int,
    val level: Int,
    val reported: Boolean,
)

data class ChallengeMember(val username: String, val displayName: String, val status: String, val progress: Double, val me: Boolean, val winner: Boolean)

data class Challenge(
    val id: String,
    val title: String,
    val metric: String,
    val metricTitle: String,
    val max: Int,
    val week: String,
    val finished: Boolean,
    val status: String,
    val mineCreated: Boolean,
    val members: List<ChallengeMember>,
) {
    val iWon: Boolean get() = finished && members.any { it.me && it.winner }
}

/** Stand auf diesem Handy: Serie, Wochenpunkte, Abzeichen-Werte. */
data class GameState(val streak: Int, val bestStreak: Int, val activeToday: Boolean, val weekPoints: Int, val totalPoints: Int, val stats: GameStats)

/** Rangliste und Challenges unter Freunden (`worker/src/game.ts`), Werte mit den Regeln aus `core/Game.kt`. */
class GameModel(private val scope: CoroutineScope, private val client: WorkerClient, private val account: AccountModel) {
    private val _leaderboard = MutableStateFlow<List<LeaderboardEntry>>(emptyList())
    val leaderboard: StateFlow<List<LeaderboardEntry>> = _leaderboard.asStateFlow()
    private val _challenges = MutableStateFlow<List<Challenge>>(emptyList())
    val challenges: StateFlow<List<Challenge>> = _challenges.asStateFlow()
    private val _state = MutableStateFlow<GameState?>(null)
    val state: StateFlow<GameState?> = _state.asStateFlow()
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()
    private var lastReported: String? = null

    private fun int(obj: JsonObject, key: String) = (obj[key] as? JsonPrimitive)?.intOrNull ?: 0
    private fun text(obj: JsonObject, key: String) = (obj[key] as? JsonPrimitive)?.content.orEmpty()
    private fun bool(obj: JsonObject, key: String) = (obj[key] as? JsonPrimitive)?.booleanOrNull ?: false

    private fun launch(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (cancel: kotlinx.coroutines.CancellationException) {
                throw cancel
            } catch (error: Exception) {
                _message.value = error.message ?: "Unbekannter Fehler"
            }
        }
    }

    fun refresh() {
        if (!account.isSignedIn) return
        launch {
            val board = client.game("GET", "leaderboard")
            _leaderboard.value = (board["entries"] as? JsonArray).orEmpty().mapNotNull { raw ->
                val obj = raw as? JsonObject ?: return@mapNotNull null
                LeaderboardEntry(int(obj, "rank"), text(obj, "username"), text(obj, "displayName"), bool(obj, "me"), int(obj, "weekPoints"),
                    int(obj, "dayStreak"), int(obj, "level"), bool(obj, "reported"))
            }
            _challenges.value = parseChallenges(client.game("GET", "challenges"))
            _message.value = null
        }
    }

    private fun parseChallenges(json: JsonObject): List<Challenge> =
        (json["challenges"] as? JsonArray).orEmpty().mapNotNull { raw -> (raw as? JsonObject)?.let(::parseChallenge) }

    private fun parseChallenge(obj: JsonObject): Challenge = Challenge(
        text(obj, "id"), text(obj, "title"), text(obj, "metric"), text(obj, "metricTitle"), int(obj, "max"), text(obj, "week"),
        bool(obj, "finished"), text(obj, "status"), bool(obj, "mineCreated"),
        (obj["members"] as? JsonArray).orEmpty().mapNotNull { raw ->
            val member = raw as? JsonObject ?: return@mapNotNull null
            ChallengeMember(text(member, "username"), text(member, "displayName"), text(member, "status"),
                (member["progress"] as? JsonPrimitive)?.doubleOrNull ?: 0.0, bool(member, "me"), bool(member, "winner"))
        },
    )

    /** Stand berechnen und – mit Konto – an Rangliste und laufende Challenges melden (nur bei Änderung). */
    fun report(data: AppData, friends: Int, today: LocalDate = LocalDate.now()) {
        val minutes = Game.minutesByDay(data)
        val meals = Game.mealDays(data)
        val streak = Game.streak(minutes.keys + meals, today)
        val monday = Game.monday(today)
        val weekPoints = Game.weekPoints(minutes, monday)
        // Gesamtpunkte der letzten 12 Wochen wie beim iPhone.
        val total = (0L until 12L).sumOf { Game.weekPoints(minutes, monday.minusWeeks(it)) }
        val level = Game.level(total)
        val stats = GameStats(
            workouts = data.sessions.count { it.endedAt != null },
            bestDayStreak = streak.best,
            mealDays = meals.size,
            friends = friends,
            challengesWon = _challenges.value.count { it.iWon },
            level = level,
        )
        _state.value = GameState(streak.current, streak.best, streak.activeToday, weekPoints, total, stats)
        if (!account.isSignedIn) return
        val values = _challenges.value.filter { it.status == "joined" && !it.finished && it.week == monday.toString() }.mapNotNull { challenge ->
            val metric = Game.Metric.of(challenge.metric) ?: return@mapNotNull null
            Game.value(metric, monday, today, minutes, meals)?.let { challenge.id to it }
        }
        val key = "$monday-$weekPoints-$total-${streak.current}-$values"
        if (key == lastReported) return
        launch {
            client.game("PUT", "score", buildJsonObject {
                put("week", monday.toString())
                put("weekPoints", weekPoints)
                put("totalPoints", total)
                put("streak", 0)
                put("dayStreak", streak.current)
                put("level", level)
            })
            values.forEach { (id, value) -> client.game("PUT", "challenges/$id/progress", buildJsonObject { put("value", value) }) }
            lastReported = key
            refresh()
        }
    }

    fun create(metric: Game.Metric, nextWeek: Boolean, title: String, invite: List<String>, done: () -> Unit) = launch {
        val monday = Game.monday(LocalDate.now()).let { if (nextWeek) it.plusWeeks(1) else it }
        val created = client.game("POST", "challenges", buildJsonObject {
            put("metric", metric.key)
            put("week", monday.toString())
            put("title", title.trim())
            put("invite", buildJsonArray { invite.forEach { add(JsonPrimitive(it)) } })
        })
        (created["challenge"] as? JsonObject)?.let { _challenges.value = listOf(parseChallenge(it)) + _challenges.value }
        lastReported = null
        done()
    }

    fun join(challenge: Challenge) = launch {
        client.game("POST", "challenges/${challenge.id}/join", JsonObject(emptyMap()))
        lastReported = null
        refresh()
    }

    fun leave(challenge: Challenge) = launch {
        client.game("DELETE", "challenges/${challenge.id}")
        _challenges.value = _challenges.value.filterNot { it.id == challenge.id }
    }
}
