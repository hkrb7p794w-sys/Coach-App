@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.LoggedExercise
import io.github.hkrb7p794w.gym.core.Progression
import io.github.hkrb7p794w.gym.core.Session
import io.github.hkrb7p794w.gym.core.SetEntry
import io.github.hkrb7p794w.gym.core.Stats
import io.github.hkrb7p794w.gym.core.Tracking
import io.github.hkrb7p794w.gym.core.Workouts
import kotlinx.coroutines.delay
import java.time.LocalDate

@Composable
fun TrainingScreen(viewModel: GymViewModel, data: AppData, modifier: Modifier, open: (Page) -> Unit) {
    val active = data.active
    if (active == null) {
        StartContent(viewModel, data, modifier, open)
    } else {
        ActiveWorkout(viewModel, data, active, modifier, open)
    }
}

@Composable
private fun StartContent(viewModel: GymViewModel, data: AppData, modifier: Modifier, open: (Page) -> Unit) {
    Column(modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Training") },
            actions = {
                val incoming by viewModel.social.incoming.collectAsState()
                TextButton(onClick = { open(Page.Friends) }) { Text(if (incoming.isEmpty()) "Freunde" else "Freunde (${incoming.size})") }
                IconButton(onClick = { open(Page.Settings) }) { Icon(Icons.Filled.Settings, contentDescription = "Einstellungen") }
            },
        )
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Button(
                    onClick = { viewModel.update { Workouts.start(it, System.currentTimeMillis()) } },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                ) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Freies Training starten")
                }
            }
            if (data.routines.isNotEmpty()) {
                item { SectionTitle("Mit Plan starten") }
                itemsIndexed(data.routines, key = { _, routine -> routine.id }) { _, routine ->
                    Card(Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(routine.name, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    routine.exercises.mapNotNull { viewModel.exercise(it.exerciseId)?.name }.joinToString(", "),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 2,
                                )
                            }
                            Button(onClick = {
                                viewModel.update { Workouts.start(it, System.currentTimeMillis(), routine, viewModel.library) }
                            }) { Text("Start") }
                        }
                    }
                }
            } else {
                item {
                    Text(
                        "Tipp: Unter „Pläne“ legst du feste Trainingspläne an, z. B. „Push“ oder „Ganzkörper A“. " +
                            "Oder du speicherst ein fertiges Training im Verlauf als Plan.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            data.sessions.firstOrNull()?.let { last ->
                item { SectionTitle("Letztes Training") }
                item { SessionCard(last) { open(Page.SessionDetail(last.id)) } }
            }
        }
    }
}

@Composable
private fun ActiveWorkout(viewModel: GymViewModel, data: AppData, active: Session, modifier: Modifier, open: (Page) -> Unit) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(active.id) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1_000)
        }
    }
    // Bildschirm bleibt während des Trainings an (abschaltbar in den Einstellungen).
    val view = LocalView.current
    val keepOn = data.settings.keepScreenOn
    DisposableEffect(keepOn) {
        view.keepScreenOn = keepOn
        onDispose { view.keepScreenOn = false }
    }
    val rest by viewModel.rest.collectAsStateWithLifecycle()
    var picking by rememberSaveable { mutableStateOf(false) }
    var confirmFinish by rememberSaveable { mutableStateOf(false) }
    var confirmDiscard by rememberSaveable { mutableStateOf(false) }

    Column(modifier.fillMaxSize().imePadding()) {
        TopAppBar(
            title = {
                Column {
                    Text(active.name)
                    Text(
                        formatDuration(now - active.startedAt) + " · ${active.workingSets} Sätze erledigt",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            actions = {
                TextButton(onClick = { confirmDiscard = true }) { Text("Verwerfen") }
                Button(onClick = { confirmFinish = true }, modifier = Modifier.padding(end = 8.dp)) { Text("Beenden") }
            },
        )
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            itemsIndexed(active.exercises, key = { index, item -> "$index-${item.exerciseId}" }) { index, logged ->
                ExerciseCard(viewModel, data, active, index, logged, open)
            }
            item {
                OutlinedButton(onClick = { picking = true }, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Übung hinzufügen")
                }
            }
        }
        rest?.let { seconds -> RestBar(seconds, viewModel) }
    }

    if (picking) {
        ExercisePickerDialog(
            viewModel = viewModel,
            onDismiss = { picking = false },
            onPick = { exercise ->
                picking = false
                viewModel.update { Workouts.addExercise(it, exercise) }
            },
        )
    }
    if (confirmFinish) {
        val done = active.workingSets
        AlertDialog(
            onDismissRequest = { confirmFinish = false },
            title = { Text(if (done > 0) "Training beenden?" else "Noch kein Satz erledigt") },
            text = {
                Text(
                    if (done > 0) {
                        "$done erledigte Sätze werden gespeichert. Nicht abgehakte Sätze fallen weg."
                    } else {
                        "Hake Sätze mit ✓ ab, damit sie gespeichert werden. Ohne erledigten Satz wird das Training verworfen."
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmFinish = false
                    viewModel.stopRest()
                    viewModel.update { Workouts.finish(it, System.currentTimeMillis()) }
                }) { Text(if (done > 0) "Speichern" else "Verwerfen") }
            },
            dismissButton = { TextButton(onClick = { confirmFinish = false }) { Text("Weiter trainieren") } },
        )
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Training verwerfen?") },
            text = { Text("Alle Einträge dieses Trainings werden gelöscht.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDiscard = false
                    viewModel.stopRest()
                    viewModel.update(Workouts::discard)
                }) { Text("Verwerfen") }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun ExerciseCard(
    viewModel: GymViewModel,
    data: AppData,
    active: Session,
    index: Int,
    logged: LoggedExercise,
    open: (Page) -> Unit,
) {
    val exercise = viewModel.exercise(logged.exerciseId)
    val tracking = exercise?.tracking ?: Tracking.WEIGHT_REPS
    val last = remember(data.sessions, logged.exerciseId) { Stats.last(logged.exerciseId, data.sessions) }
    val advice = remember(data.sessions, logged.exerciseId) {
        exercise?.let { Progression.evaluate(it, Progression.history(it.id, data.sessions), LocalDate.now()) }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(
                    Modifier.weight(1f).clickable(enabled = exercise != null) { open(Page.ExerciseDetail(logged.exerciseId)) },
                ) {
                    Text(logged.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    exercise?.let {
                        Text(
                            "Ziel ${it.repRange.first}–${it.repRange.last} ${if (tracking == Tracking.TIME) "s" else "Wdh."}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                IconButton(onClick = { viewModel.update { Workouts.moveExercise(it, index, -1) } }, enabled = index > 0) {
                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Nach oben")
                }
                IconButton(
                    onClick = { viewModel.update { Workouts.moveExercise(it, index, 1) } },
                    enabled = index < active.exercises.lastIndex,
                ) { Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Nach unten") }
                IconButton(onClick = { viewModel.update { Workouts.removeExercise(it, index) } }) {
                    Icon(Icons.Filled.Delete, contentDescription = "Übung entfernen")
                }
            }
            if (last != null) {
                Text(
                    "Letztes Mal (${formatShortDate(last.startedAt)}): ${Stats.describe(last.sets, tracking)}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (advice != null) {
                Text(
                    advice.headline,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (advice.status == Progression.Status.INCREASE) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Satz", Modifier.width(44.dp), style = MaterialTheme.typography.labelMedium)
                if (tracking != Tracking.TIME) {
                    Text(if (tracking == Tracking.REPS) "+kg" else "kg", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center)
                }
                Text(if (tracking == Tracking.TIME) "Sek." else "Wdh.", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center)
                Spacer(Modifier.width(96.dp))
            }
            logged.sets.forEachIndexed { setIndex, set ->
                // Textfelder neu aufsetzen, wenn sich Reihenfolge oder Anzahl ändert (sonst stünden alte Werte darin).
                val rowKey = "${active.id}/$index/${logged.exerciseId}/${logged.sets.size}/$setIndex"
                SetRow(rowKey, setIndex, set, tracking, onChange = { change ->
                    viewModel.update { Workouts.updateSet(it, index, setIndex, change) }
                }, onDone = { done ->
                    viewModel.update { Workouts.updateSet(it, index, setIndex) { s -> s.copy(done = done) } }
                    if (done && !set.warmup) viewModel.startRest(data.settings.restSeconds)
                }, onRemove = {
                    viewModel.update { Workouts.removeSet(it, index, setIndex) }
                })
            }
            TextButton(onClick = { viewModel.update { Workouts.addSet(it, index) } }) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(4.dp))
                Text("Satz")
            }
        }
    }
}

@Composable
private fun SetRow(
    rowKey: String,
    setIndex: Int,
    set: SetEntry,
    tracking: Tracking,
    onChange: ((SetEntry) -> SetEntry) -> Unit,
    onDone: (Boolean) -> Unit,
    onRemove: () -> Unit,
) {
    var weightText by remember(rowKey) { mutableStateOf(if (set.weightKg > 0) formatKg(set.weightKg) else "") }
    var repsText by remember(rowKey) { mutableStateOf(if (set.reps > 0) set.reps.toString() else "") }
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        // Tippen auf die Nummer: Aufwärmsatz (zählt nicht für Volumen und Steigerung).
        Box(
            Modifier.width(44.dp).clickable { onChange { it.copy(warmup = !it.warmup) } },
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(
                if (set.warmup) "A" else "${setIndex + 1}",
                style = MaterialTheme.typography.titleMedium,
                color = if (set.warmup) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurface,
            )
        }
        if (tracking != Tracking.TIME) {
            OutlinedTextField(
                value = weightText,
                onValueChange = { text ->
                    weightText = text
                    parseDecimal(text)?.let { value -> onChange { it.copy(weightKg = value) } }
                },
                modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
                singleLine = true,
                placeholder = { Text("0") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
        }
        OutlinedTextField(
            value = repsText,
            onValueChange = { text ->
                val digits = text.filter(Char::isDigit).take(4)
                repsText = digits
                onChange { it.copy(reps = digits.toIntOrNull() ?: 0) }
            },
            modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
            singleLine = true,
            placeholder = { Text("0") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        FilledIconToggleButton(
            checked = set.done,
            onCheckedChange = { checked -> if (!checked || set.reps > 0) onDone(checked) },
            modifier = Modifier.size(48.dp),
        ) { Icon(Icons.Filled.Check, contentDescription = if (set.done) "Erledigt" else "Als erledigt markieren") }
        IconButton(onClick = onRemove, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Filled.Close, contentDescription = "Satz entfernen")
        }
    }
}

@Composable
private fun RestBar(seconds: Int, viewModel: GymViewModel) {
    Surface(color = MaterialTheme.colorScheme.primaryContainer, tonalElevation = 3.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Pause " + formatDuration(seconds * 1000L),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f),
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            TextButton(onClick = { viewModel.extendRest(-15) }) { Text("−15 s") }
            TextButton(onClick = { viewModel.extendRest(15) }) { Text("+15 s") }
            TextButton(onClick = { viewModel.stopRest() }) { Text("Fertig") }
        }
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
}

@Composable
fun SessionCard(session: Session, onClick: () -> Unit) {
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(session.name, style = MaterialTheme.typography.titleMedium)
            val duration = session.endedAt?.let { " · " + formatDuration(it - session.startedAt) }.orEmpty()
            Text(
                formatDate(session.startedAt) + duration,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "${session.exercises.size} Übungen · ${session.workingSets} Sätze · ${formatVolume(session.volumeKg)}",
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                session.exercises.joinToString(", ") { it.name },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
            )
        }
    }
}
