@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Exercise
import io.github.hkrb7p794w.gym.core.Library
import io.github.hkrb7p794w.gym.core.MUSCLE_GROUPS
import io.github.hkrb7p794w.gym.core.Progression
import io.github.hkrb7p794w.gym.core.Stats
import io.github.hkrb7p794w.gym.core.Tracking
import io.github.hkrb7p794w.gym.core.Workouts
import java.time.LocalDate

@Composable
fun ExercisesScreen(viewModel: GymViewModel, data: AppData, modifier: Modifier, open: (Page) -> Unit) {
    Column(modifier.fillMaxSize()) {
        TopAppBar(title = { Text("Übungen") })
        ExerciseList(viewModel, data, onPick = { open(Page.ExerciseDetail(it.id)) })
    }
}

/** Suche, Filter nach Muskelgruppe und „Eigene Übung anlegen“ – für die Liste und den Auswahldialog. */
@Composable
private fun ExerciseList(viewModel: GymViewModel, data: AppData, onPick: (Exercise) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var group by rememberSaveable { mutableStateOf<String?>(null) }
    var creating by rememberSaveable { mutableStateOf(false) }
    val all = viewModel.library + data.customExercises
    val results = remember(query, group, data.customExercises) { Library.search(all, query, group) }
    Column {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Übung suchen") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        )
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            MUSCLE_GROUPS.filter { name -> all.any { it.group == name } }.forEach { name ->
                FilterChip(selected = group == name, onClick = { group = if (group == name) null else name }, label = { Text(name) })
            }
        }
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                ListItem(
                    headlineContent = { Text(if (query.isBlank()) "Eigene Übung anlegen" else "„${query.trim()}“ als eigene Übung anlegen") },
                    leadingContent = { Icon(Icons.Filled.Add, contentDescription = null) },
                    modifier = Modifier.clickable { creating = true },
                )
                HorizontalDivider()
            }
            items(results, key = { it.id }) { exercise ->
                val last = Stats.last(exercise.id, data.sessions)
                ListItem(
                    headlineContent = { Text(exercise.name) },
                    supportingContent = {
                        Text(
                            exercise.group + (if (exercise.custom) " · eigene" else "") +
                                (last?.let { " · zuletzt ${formatShortDate(it.startedAt)}" } ?: ""),
                        )
                    },
                    modifier = Modifier.clickable { onPick(exercise) },
                )
            }
        }
    }
    if (creating) {
        CustomExerciseDialog(initialName = query.trim(), onDismiss = { creating = false }) { exercise ->
            creating = false
            var created = exercise
            viewModel.update { current ->
                val (next, used) = Workouts.addCustom(current, exercise, viewModel.library)
                created = used
                next
            }
            onPick(created)
        }
    }
}

@Composable
private fun CustomExerciseDialog(initialName: String, onDismiss: () -> Unit, onCreate: (Exercise) -> Unit) {
    var name by rememberSaveable { mutableStateOf(initialName) }
    var group by rememberSaveable { mutableStateOf("Sonstige") }
    var tracking by rememberSaveable { mutableStateOf(Tracking.WEIGHT_REPS) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Eigene Übung") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, singleLine = true)
                Text("Muskelgruppe", style = MaterialTheme.typography.labelMedium)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MUSCLE_GROUPS.forEach { FilterChip(selected = group == it, onClick = { group = it }, label = { Text(it) }) }
                }
                Text("Erfassung", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(Tracking.WEIGHT_REPS to "kg × Wdh.", Tracking.REPS to "Wdh.", Tracking.TIME to "Sekunden").forEach { (value, label) ->
                        FilterChip(selected = tracking == value, onClick = { tracking = value }, label = { Text(label) })
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onCreate(Exercise.custom(name, group, tracking)) }, enabled = name.isNotBlank()) { Text("Anlegen") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Abbrechen") } },
    )
}

@Composable
fun ExercisePickerDialog(viewModel: GymViewModel, onDismiss: () -> Unit, onPick: (Exercise) -> Unit) {
    val data = viewModel.data.value
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Übung wählen") },
                    navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Schließen") } },
                )
            },
        ) { padding ->
            Column(Modifier.padding(padding)) { ExerciseList(viewModel, data, onPick) }
        }
    }
}

@Composable
fun ExerciseDetailScreen(viewModel: GymViewModel, data: AppData, id: String, onBack: () -> Unit) {
    val exercise = viewModel.exercise(id)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(exercise?.name ?: "Übung") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
            )
        },
    ) { padding ->
        if (exercise == null) {
            Text("Übung nicht gefunden.", Modifier.padding(padding).padding(16.dp))
            return@Scaffold
        }
        val history = remember(data.sessions, id) {
            data.sessions.mapNotNull { session ->
                session.exercises.firstOrNull { it.exerciseId == id }?.let { session to it }
            }
        }
        val advice = remember(data.sessions, id) {
            Progression.evaluate(exercise, Progression.history(id, data.sessions), LocalDate.now())
        }
        val best = remember(data.sessions, id) { Stats.bestOneRepMax(id, data.sessions) }
        LazyColumn(
            Modifier.padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    listOfNotNull(
                        exercise.group,
                        exercise.secondary.takeIf { it.isNotEmpty() }?.joinToString(", ", prefix = "auch "),
                        "Ziel ${exercise.repRange.first}–${exercise.repRange.last} ${if (exercise.tracking == Tracking.TIME) "s" else "Wdh."}",
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (advice != null) {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp)) {
                            Text(advice.headline, style = MaterialTheme.typography.titleMedium)
                            Text(advice.detail, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
            if (best != null) {
                item { Text("Bestwert (geschätztes 1RM): ${formatKg(best)} kg", style = MaterialTheme.typography.bodyMedium) }
            }
            if (exercise.instructions.isNotEmpty()) {
                item { SectionTitle("Ausführung") }
                items(exercise.instructions) { Text("• $it", style = MaterialTheme.typography.bodyMedium) }
            }
            item { SectionTitle("Verlauf") }
            if (history.isEmpty()) {
                item { Text("Noch nicht trainiert.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            items(history.take(30)) { (session, logged) ->
                Text(
                    formatShortDate(session.startedAt) + ": " + Stats.describe(logged.sets, exercise.tracking),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}
