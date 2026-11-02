@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Routine
import io.github.hkrb7p794w.gym.core.RoutineExercise
import io.github.hkrb7p794w.gym.core.Workouts

@Composable
fun RoutinesScreen(viewModel: GymViewModel, data: AppData, modifier: Modifier, open: (Page) -> Unit, startTraining: () -> Unit) {
    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = { TopAppBar(title = { Text("Pläne") }) },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { open(Page.RoutineEditor(null)) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text("Neuer Plan") },
            )
        },
    ) { padding ->
        if (data.routines.isEmpty()) {
            Text(
                "Noch keine Pläne. Lege einen an oder speichere ein Training im Verlauf als Plan.",
                modifier = Modifier.padding(padding).padding(16.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            return@Scaffold
        }
        LazyColumn(
            Modifier.padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(data.routines, key = { it.id }) { routine ->
                Card(Modifier.fillMaxWidth().clickable { open(Page.RoutineEditor(routine.id)) }) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(routine.name, style = MaterialTheme.typography.titleMedium)
                            Text(
                                routine.exercises.joinToString(", ") { planned ->
                                    "${viewModel.exercise(planned.exerciseId)?.name ?: planned.exerciseId} ${planned.sets}×"
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Button(
                            onClick = {
                                viewModel.update { Workouts.start(it, System.currentTimeMillis(), routine, viewModel.library) }
                                startTraining()
                            },
                            enabled = data.active == null,
                        ) { Text("Start") }
                    }
                }
            }
        }
    }
}

@Composable
fun RoutineEditorScreen(viewModel: GymViewModel, data: AppData, id: String?, onBack: () -> Unit) {
    val existing = data.routines.firstOrNull { it.id == id }
    val newId = remember { Workouts.newId() }
    var name by rememberSaveable { mutableStateOf(existing?.name ?: "") }
    var items by remember { mutableStateOf(existing?.exercises ?: emptyList()) }
    var picking by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }

    fun save() {
        val routine = Routine(existing?.id ?: newId, name.trim().ifEmpty { "Plan" }, items)
        viewModel.update { Workouts.saveRoutine(it, routine) }
        onBack()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "Neuer Plan" else "Plan bearbeiten") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück ohne Speichern") } },
                actions = {
                    if (existing != null) {
                        IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Filled.Delete, contentDescription = "Plan löschen") }
                    }
                    TextButton(onClick = ::save, enabled = items.isNotEmpty()) { Text("Speichern") }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name, z. B. „Push“") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            itemsIndexed(items) { index, planned ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            viewModel.exercise(planned.exerciseId)?.name ?: planned.exerciseId,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        TextButton(onClick = { items = items.update(index) { it.copy(sets = (it.sets - 1).coerceAtLeast(1)) } }) { Text("−") }
                        Text("${planned.sets} Sätze", Modifier.width(64.dp))
                        TextButton(onClick = { items = items.update(index) { it.copy(sets = (it.sets + 1).coerceAtMost(10)) } }) { Text("+") }
                        IconButton(onClick = { items = items.move(index, -1) }, enabled = index > 0) {
                            Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Nach oben")
                        }
                        IconButton(onClick = { items = items.move(index, 1) }, enabled = index < items.lastIndex) {
                            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Nach unten")
                        }
                        IconButton(onClick = { items = items.filterIndexed { i, _ -> i != index } }) {
                            Icon(Icons.Filled.Delete, contentDescription = "Entfernen")
                        }
                    }
                }
            }
            item {
                OutlinedButton(onClick = { picking = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text(" Übung hinzufügen")
                }
            }
        }
    }
    if (picking) {
        ExercisePickerDialog(viewModel, onDismiss = { picking = false }, onPick = { exercise ->
            picking = false
            items = items + RoutineExercise(exercise.id, 3)
        })
    }
    if (confirmDelete && existing != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Plan löschen?") },
            text = { Text("„${existing.name}“ wird gelöscht. Bisherige Trainings bleiben erhalten.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    viewModel.update { Workouts.deleteRoutine(it, existing.id) }
                    onBack()
                }) { Text("Löschen") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Abbrechen") } },
        )
    }
}

private fun <T> List<T>.update(index: Int, change: (T) -> T): List<T> = mapIndexed { i, item -> if (i == index) change(item) else item }

private fun <T> List<T>.move(index: Int, offset: Int): List<T> {
    val target = index + offset
    if (index !in indices || target !in indices) return this
    return toMutableList().apply { add(target, removeAt(index)) }
}
