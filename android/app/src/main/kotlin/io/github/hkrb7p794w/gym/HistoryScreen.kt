@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Stats
import io.github.hkrb7p794w.gym.core.Tracking
import io.github.hkrb7p794w.gym.core.Workouts

@Composable
fun HistoryScreen(data: AppData, modifier: Modifier, open: (Page) -> Unit) {
    Column(modifier.fillMaxSize()) {
        TopAppBar(title = { Text("Verlauf") })
        if (data.sessions.isEmpty()) {
            Text(
                "Noch keine Trainings. Starte unter „Training“ dein erstes – nach „Beenden“ erscheint es hier.",
                modifier = Modifier.padding(16.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            return@Column
        }
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                val weekAgo = System.currentTimeMillis() - 7L * 24 * 3600 * 1000
                val week = data.sessions.filter { it.startedAt >= weekAgo }
                Text(
                    "Letzte 7 Tage: ${week.size} Trainings · ${week.sumOf { it.workingSets }} Sätze · " +
                        formatVolume(week.sumOf { it.volumeKg }),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            items(data.sessions, key = { it.id }) { session ->
                SessionCard(session) { open(Page.SessionDetail(session.id)) }
            }
        }
    }
}

@Composable
fun SessionDetailScreen(viewModel: GymViewModel, data: AppData, id: String, onBack: () -> Unit, open: (Page) -> Unit) {
    val session = data.sessions.firstOrNull { it.id == id }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    var routineName by rememberSaveable { mutableStateOf<String?>(null) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(session?.name ?: "Training") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
                actions = {
                    if (session != null) {
                        IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Filled.Delete, contentDescription = "Training löschen") }
                    }
                },
            )
        },
    ) { padding ->
        if (session == null) {
            Text("Training nicht gefunden.", Modifier.padding(padding).padding(16.dp))
            return@Scaffold
        }
        LazyColumn(
            Modifier.padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                val duration = session.endedAt?.let { formatDuration(it - session.startedAt) }
                Text(
                    formatDate(session.startedAt) + ", " + formatTime(session.startedAt) + (duration?.let { " · $it" } ?: ""),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text("${session.workingSets} Sätze · ${formatVolume(session.volumeKg)}", style = MaterialTheme.typography.bodyMedium)
            }
            items(session.exercises) { logged ->
                val tracking = viewModel.exercise(logged.exerciseId)?.tracking ?: Tracking.WEIGHT_REPS
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        TextButton(onClick = { open(Page.ExerciseDetail(logged.exerciseId)) }, contentPadding = PaddingValues(0.dp)) {
                            Text(logged.name, style = MaterialTheme.typography.titleMedium)
                        }
                        logged.sets.forEachIndexed { index, set ->
                            val label = if (set.warmup) "Aufwärmen" else "Satz ${index + 1}"
                            Text("$label: " + Stats.describe(listOf(set), tracking), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
            item {
                OutlinedButton(onClick = { routineName = session.name }, modifier = Modifier.fillMaxWidth()) {
                    Text("Als Plan speichern")
                }
            }
        }
    }
    if (confirmDelete && session != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Training löschen?") },
            text = { Text("Das Training vom ${formatDate(session.startedAt)} wird endgültig gelöscht.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    viewModel.update { Workouts.deleteSession(it, session.id) }
                    onBack()
                }) { Text("Löschen") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Abbrechen") } },
        )
    }
    val name = routineName
    if (name != null && session != null) {
        AlertDialog(
            onDismissRequest = { routineName = null },
            title = { Text("Als Plan speichern") },
            text = { OutlinedTextField(value = name, onValueChange = { routineName = it }, label = { Text("Name des Plans") }, singleLine = true) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.update { Workouts.saveRoutine(it, Workouts.routineFrom(session, name)) }
                    routineName = null
                }) { Text("Speichern") }
            },
            dismissButton = { TextButton(onClick = { routineName = null }) { Text("Abbrechen") } },
        )
    }
}
