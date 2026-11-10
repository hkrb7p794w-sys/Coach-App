@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.Social
import io.github.hkrb7p794w.gym.core.SocialPerson
import io.github.hkrb7p794w.gym.core.SocialPost
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Freunde: Feed mit geteilten Trainings und Mahlzeiten, Freundesliste mit Suche und Anfragen. */
@Composable
fun FriendsScreen(viewModel: GymViewModel, onBack: () -> Unit, openAccount: () -> Unit) {
    val social = viewModel.social
    var tab by rememberSaveable { mutableStateOf(0) }
    val incoming by social.incoming.collectAsState()
    val message by social.message.collectAsState()
    LaunchedEffect(Unit) { social.refresh() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Freunde") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (!social.isAvailable) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Freunde brauchen ein Konto", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Mit einem eigenen Konto findest du Freunde über den Benutzernamen, siehst ihre Trainings und teilst Mahlzeiten. " +
                            "Nur du kennst dein Passwort.",
                    )
                    Button(onClick = openAccount) { Text("Anmelden oder Konto erstellen") }
                }
                return@Column
            }
            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = tab == 0, onClick = { tab = 0 }, label = { Text("Feed") })
                FilterChip(selected = tab == 1, onClick = { tab = 1 }, label = { Text(if (incoming.isEmpty()) "Freunde" else "Freunde (${incoming.size})") })
            }
            message?.let {
                Text(it, Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
            }
            if (tab == 0) FeedList(viewModel) else FriendList(viewModel, openAccount)
        }
    }
}

@Composable
private fun FeedList(viewModel: GymViewModel) {
    val social = viewModel.social
    val feed by social.feed.collectAsState()
    val loading by social.loading.collectAsState()
    var commentsFor by remember { mutableStateOf<SocialPost?>(null) }
    LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (feed.isEmpty() && !loading) {
            item {
                Text(
                    "Noch nichts geteilt. Teile ein Training (Verlauf › Training › Teilen) oder eine Mahlzeit (Menü an der Mahlzeit › Mit Freunden teilen).",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(feed, key = { it.id }) { post ->
            PostCard(viewModel, post, onComments = { commentsFor = post })
            if (post.id == feed.lastOrNull()?.id) LaunchedEffect(post.id) { social.loadMore() }
        }
        item {
            TextButton(onClick = social::refresh, enabled = !loading) { Text(if (loading) "Wird geladen …" else "Aktualisieren") }
        }
    }
    commentsFor?.let { post -> CommentsDialog(viewModel, post) { commentsFor = null } }
}

@Composable
private fun PostCard(viewModel: GymViewModel, post: SocialPost, onComments: () -> Unit) {
    val social = viewModel.social
    val context = androidx.compose.ui.platform.LocalContext.current
    var confirmDelete by remember { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(post.author)
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    Text(if (post.mine) "Du" else post.author.displayName, style = MaterialTheme.typography.titleSmall)
                    Text(relative(post.createdAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (post.mine) TextButton(onClick = { confirmDelete = true }) { Text("Löschen") }
            }
            Text(post.headline, style = MaterialTheme.typography.titleMedium)
            if (post.facts.isNotEmpty()) Text(post.facts, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (post.exercises.isNotEmpty()) Text(post.exercises.joinToString(" · "), style = MaterialTheme.typography.bodySmall)
            post.records.forEach { Text("🏆 $it", style = MaterialTheme.typography.bodySmall) }
            post.note?.let { Text(it) }
            val meal = post.meal
            if (meal != null && !post.mine) {
                OutlinedButton(onClick = {
                    viewModel.nutrition.newDraft(java.time.LocalDate.now(), meal.second, title = meal.first, hint = "Von ${post.author.displayName} – Mengen prüfen")
                    android.widget.Toast.makeText(context, "Als Entwurf unter Ernährung angelegt – Mengen prüfen und speichern.", android.widget.Toast.LENGTH_LONG).show()
                }) { Text("In mein Tagebuch übernehmen") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Social.REACTIONS.forEach { emoji ->
                    val selected = post.myReaction == emoji
                    TextButton(
                        onClick = { social.react(post, emoji) },
                        modifier = Modifier.background(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent, CircleShape),
                    ) { Text(emoji, style = MaterialTheme.typography.titleMedium) }
                }
                Spacer(Modifier.weight(1f))
                if (post.reactions > 0) Text("${post.topReactions} ${post.reactions}", style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = onComments) { Text("💬 ${post.comments}") }
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Beitrag löschen?") },
            confirmButton = { TextButton(onClick = { confirmDelete = false; social.delete(post) }) { Text("Löschen") } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun CommentsDialog(viewModel: GymViewModel, post: SocialPost, onClose: () -> Unit) {
    val social = viewModel.social
    var comments by remember { mutableStateOf<List<SocialComment>>(emptyList()) }
    var text by rememberSaveable { mutableStateOf("") }
    fun load() = social.comments(post) { comments = it }
    LaunchedEffect(post.id) { load() }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(post.headline) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (comments.isEmpty()) Text("Noch keine Kommentare.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                comments.forEach { comment ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(comment.author.displayName, style = MaterialTheme.typography.labelLarge)
                            Text(comment.text)
                        }
                        if (comment.canDelete) TextButton(onClick = { social.deleteComment(post, comment) { load() } }) { Text("✕") }
                    }
                }
                OutlinedTextField(text, { text = it.take(280) }, label = { Text("Kommentar") }, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(onClick = { social.comment(post, text) { text = ""; load() } }, enabled = text.isNotBlank()) { Text("Senden") }
        },
        dismissButton = { TextButton(onClick = onClose) { Text("Schließen") } },
    )
}

@Composable
private fun FriendList(viewModel: GymViewModel, openAccount: () -> Unit) {
    val social = viewModel.social
    val friends by social.friends.collectAsState()
    val incoming by social.incoming.collectAsState()
    val outgoing by social.outgoing.collectAsState()
    val results by social.results.collectAsState()
    var query by rememberSaveable { mutableStateOf("") }
    var removing by remember { mutableStateOf<SocialPerson?>(null) }
    LaunchedEffect(query) {
        kotlinx.coroutines.delay(300)
        social.search(query)
    }
    LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            OutlinedTextField(query, { query = it }, label = { Text("Benutzername suchen") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        if (query.trim().length >= 2) {
            if (results.isEmpty()) item { Text("Niemand gefunden.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            items(results, key = { "r-${it.username}" }) { person ->
                PersonRow(person) {
                    when (person.relation) {
                        "friends" -> Text("Befreundet", style = MaterialTheme.typography.bodySmall)
                        "outgoing" -> Text("Angefragt", style = MaterialTheme.typography.bodySmall)
                        "incoming" -> Button(onClick = { social.add(person.username) { social.search(query) } }) { Text("Annehmen") }
                        "blocked" -> Text("Gesperrt", style = MaterialTheme.typography.bodySmall)
                        else -> Button(onClick = { social.add(person.username) { social.search(query) } }) { Text("Hinzufügen") }
                    }
                }
            }
        }
        if (incoming.isNotEmpty()) {
            item { SectionTitle("Anfragen an dich") }
            items(incoming, key = { "i-${it.username}" }) { person ->
                PersonRow(person) {
                    Button(onClick = { social.add(person.username) }) { Text("Annehmen") }
                    TextButton(onClick = { social.remove(person.username) }) { Text("Ablehnen") }
                }
            }
        }
        item { SectionTitle("Freunde (${friends.size})") }
        if (friends.isEmpty()) item { Text("Noch keine Freunde. Suche oben nach einem Benutzernamen.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(friends, key = { "f-${it.username}" }) { person ->
            PersonRow(person) { TextButton(onClick = { removing = person }) { Text("…") } }
        }
        if (outgoing.isNotEmpty()) {
            item { SectionTitle("Gesendete Anfragen") }
            items(outgoing, key = { "o-${it.username}" }) { person ->
                PersonRow(person) { TextButton(onClick = { social.remove(person.username) }) { Text("Zurückziehen") } }
            }
        }
        item {
            OutlinedButton(onClick = openAccount, modifier = Modifier.fillMaxWidth()) { Text("Jemanden ohne Konto einladen") }
            Text(
                "Freunde sehen nur, was du ausdrücklich teilst – nie Gewicht, Puls oder andere Körperwerte.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    removing?.let { person ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(person.displayName) },
            text = { Text("Wer gesperrt ist, sieht deine Beiträge nicht und kann dir keine Anfragen schicken. Es gibt keine Mitteilung.") },
            confirmButton = { TextButton(onClick = { removing = null; social.remove(person.username) }) { Text("Freundschaft beenden") } },
            dismissButton = { TextButton(onClick = { removing = null; social.block(person.username) }) { Text("Sperren") } },
        )
    }
}

@Composable
private fun PersonRow(person: SocialPerson, actions: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Avatar(person)
        Column(Modifier.padding(start = 10.dp).weight(1f)) {
            Text(person.displayName)
            Text("@${person.username}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        actions()
    }
}

@Composable
private fun Avatar(person: SocialPerson) {
    val palette = listOf(Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFFD81B60), Color(0xFF8E24AA), Color(0xFF00897B))
    val color = palette[person.username.sumOf { it.code } % palette.size]
    Box(Modifier.size(36.dp).background(color, CircleShape), contentAlignment = Alignment.Center) {
        Text(person.initial, color = Color.White, style = MaterialTheme.typography.titleSmall)
    }
}

/** „gerade eben“, „vor 5 Min.“, „vor 3 Std.“, sonst Datum. */
private fun relative(iso: String): String {
    val instant = runCatching { Instant.parse(iso) }.getOrNull() ?: return ""
    val minutes = Duration.between(instant, Instant.now()).toMinutes()
    return when {
        minutes < 1 -> "gerade eben"
        minutes < 60 -> "vor $minutes Min."
        minutes < 24 * 60 -> "vor ${minutes / 60} Std."
        else -> DateTimeFormatter.ofPattern("d. MMM", Locale.GERMAN).withZone(ZoneId.systemDefault()).format(instant)
    }
}

/** „Mit Freunden teilen“ mit optionaler Notiz. */
@Composable
fun ShareWithFriendsDialog(title: String, preview: String, onShare: (String) -> Unit, onDismiss: () -> Unit) {
    var note by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Mit Freunden teilen") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                if (preview.isNotEmpty()) Text(preview, style = MaterialTheme.typography.bodySmall)
                OutlinedTextField(note, { note = it.take(280) }, label = { Text("Notiz (optional)") }, modifier = Modifier.fillMaxWidth())
                Text("Keine Körperwerte: Gewicht, Puls und Schlaf bleiben auf deinem Handy.", style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = { onShare(note) }) { Text("Teilen") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Abbrechen") } },
    )
}
