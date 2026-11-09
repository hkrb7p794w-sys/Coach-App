package io.github.hkrb7p794w.gym

import io.github.hkrb7p794w.gym.core.MealItem
import io.github.hkrb7p794w.gym.core.Session
import io.github.hkrb7p794w.gym.core.Social
import io.github.hkrb7p794w.gym.core.SocialPerson
import io.github.hkrb7p794w.gym.core.SocialPost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.URLEncoder

data class SocialComment(val id: String, val text: String, val createdAt: String, val author: SocialPerson, val canDelete: Boolean)

/**
 * Freunde und Feed über den Worker (`worker/src/social.ts`). Nur mit Konto; geteilt wird nur, was die Person
 * ausdrücklich teilt (Training ohne Körperwerte, Mahlzeit).
 */
class SocialModel(private val scope: CoroutineScope, private val client: WorkerClient, private val account: AccountModel) {
    private val _friends = MutableStateFlow<List<SocialPerson>>(emptyList())
    val friends: StateFlow<List<SocialPerson>> = _friends.asStateFlow()
    private val _incoming = MutableStateFlow<List<SocialPerson>>(emptyList())
    val incoming: StateFlow<List<SocialPerson>> = _incoming.asStateFlow()
    private val _outgoing = MutableStateFlow<List<SocialPerson>>(emptyList())
    val outgoing: StateFlow<List<SocialPerson>> = _outgoing.asStateFlow()
    private val _feed = MutableStateFlow<List<SocialPost>>(emptyList())
    val feed: StateFlow<List<SocialPost>> = _feed.asStateFlow()
    private val _results = MutableStateFlow<List<SocialPerson>>(emptyList())
    val results: StateFlow<List<SocialPerson>> = _results.asStateFlow()
    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()
    private var hasMore = true

    val isAvailable: Boolean get() = account.isSignedIn

    private fun name(username: String) = URLEncoder.encode(username, "UTF-8")

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

    fun clearMessage() {
        _message.value = null
    }

    fun refresh() {
        if (!isAvailable || _loading.value) return
        launch {
            _loading.value = true
            try {
                val lists = client.social("GET", "friends")
                _friends.value = Social.people(lists, "friends")
                _incoming.value = Social.people(lists, "incoming")
                _outgoing.value = Social.people(lists, "outgoing")
                val page = Social.posts(client.social("GET", "feed"))
                _feed.value = page
                hasMore = page.size >= 30
                _message.value = null
            } finally {
                _loading.value = false
            }
        }
    }

    fun loadMore() {
        val last = _feed.value.lastOrNull() ?: return
        if (!hasMore || _loading.value) return
        val before = runCatching { java.time.Instant.parse(last.createdAt).toEpochMilli() }.getOrNull() ?: return
        launch {
            _loading.value = true
            try {
                val page = Social.posts(client.social("GET", "feed?before=$before"))
                _feed.value = _feed.value + page.filter { post -> _feed.value.none { it.id == post.id } }
                hasMore = page.size >= 30
            } finally {
                _loading.value = false
            }
        }
    }

    fun search(query: String) {
        val text = query.trim()
        if (text.length < 2) {
            _results.value = emptyList()
            return
        }
        launch { _results.value = Social.people(client.social("GET", "search?q=${name(text)}"), "people") }
    }

    fun add(username: String, after: () -> Unit = {}) = launch {
        client.social("POST", "friends/${name(username)}", JsonObject(emptyMap()))
        after()
        refresh()
    }

    fun remove(username: String) = launch {
        client.social("DELETE", "friends/${name(username)}")
        refresh()
    }

    fun block(username: String) = launch {
        client.social("POST", "blocks/${name(username)}", JsonObject(emptyMap()))
        refresh()
    }

    fun shareWorkout(session: Session, note: String?, done: () -> Unit) = launch {
        val post = client.social("POST", "posts", Social.workout(session, note = note))
        (post["post"] as? JsonObject)?.let(Social::post)?.let { created -> _feed.value = listOf(created) + _feed.value }
        _message.value = "Mit deinen Freunden geteilt."
        done()
    }

    fun shareMeal(title: String, items: List<MealItem>, note: String?, done: () -> Unit) = launch {
        val post = client.social("POST", "posts", Social.meal(title, items, note))
        (post["post"] as? JsonObject)?.let(Social::post)?.let { created -> _feed.value = listOf(created) + _feed.value }
        _message.value = "Mit deinen Freunden geteilt."
        done()
    }

    fun delete(post: SocialPost) = launch {
        client.social("DELETE", "posts/${post.id}")
        _feed.value = _feed.value.filterNot { it.id == post.id }
    }

    /** Gleiche Reaktion nochmals: zurücknehmen. Die Anzeige ändert sich sofort. */
    fun react(post: SocialPost, emoji: String) {
        val removing = post.myReaction == emoji
        val updated = post.copy(
            myReaction = if (removing) null else emoji,
            reactions = post.reactions + when {
                post.myReaction == null -> 1
                removing -> -1
                else -> 0
            },
        )
        _feed.value = _feed.value.map { if (it.id == post.id) updated else it }
        scope.launch {
            try {
                if (removing) client.social("DELETE", "posts/${post.id}/reaction")
                else client.social("PUT", "posts/${post.id}/reaction", buildJsonObject { put("emoji", emoji) })
            } catch (error: WorkerException) {
                _feed.value = _feed.value.map { if (it.id == post.id) post else it }
                _message.value = error.message
            }
        }
    }

    fun comments(post: SocialPost, done: (List<SocialComment>) -> Unit) = launch {
        val json = client.social("GET", "posts/${post.id}/comments")
        done((json["comments"] as? JsonArray).orEmpty().mapNotNull { raw ->
            val obj = raw as? JsonObject ?: return@mapNotNull null
            SocialComment(
                (obj["id"] as? JsonPrimitive)?.content ?: return@mapNotNull null,
                (obj["text"] as? JsonPrimitive)?.content.orEmpty(),
                (obj["createdAt"] as? JsonPrimitive)?.content.orEmpty(),
                Social.person(obj["author"] as? JsonObject) ?: SocialPerson("?", "?"),
                (obj["canDelete"] as? JsonPrimitive)?.booleanOrNull ?: false,
            )
        })
    }

    fun comment(post: SocialPost, text: String, done: () -> Unit) = launch {
        client.social("POST", "posts/${post.id}/comments", buildJsonObject { put("text", text.trim().take(280)) })
        _feed.value = _feed.value.map { if (it.id == post.id) it.copy(comments = it.comments + 1) else it }
        done()
    }

    fun deleteComment(post: SocialPost, comment: SocialComment, done: () -> Unit) = launch {
        client.social("DELETE", "comments/${comment.id}")
        _feed.value = _feed.value.map { if (it.id == post.id) it.copy(comments = maxOf(0, it.comments - 1)) else it }
        done()
    }
}
