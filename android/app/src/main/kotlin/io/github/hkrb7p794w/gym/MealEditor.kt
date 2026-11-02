@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.FoodSource
import io.github.hkrb7p794w.gym.core.MealCategory
import io.github.hkrb7p794w.gym.core.MealItem
import io.github.hkrb7p794w.gym.core.Nutrient
import io.github.hkrb7p794w.gym.core.Nutrition
import io.github.hkrb7p794w.gym.core.PortionGuess
import io.github.hkrb7p794w.gym.core.get
import java.time.LocalDate

@Composable
fun MealEditorDialog(viewModel: GymViewModel, data: AppData, draft: MealDraft) {
    val model = viewModel.nutrition
    val meal = draft.meal
    val bls by model.bls.collectAsState()
    var amendText by rememberSaveable(meal.id) { mutableStateOf("") }
    var replacing by remember { mutableStateOf<MealItem?>(null) }
    var adding by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    val totals = Nutrition.totals(meal.items)

    fun changeItem(id: String, change: (MealItem) -> MealItem) =
        model.changeDraft { it.copy(items = it.items.map { item -> if (item.id == id) change(item) else item }) }

    Dialog(onDismissRequest = model::closeDraft, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(if (draft.isNew) "Neue Mahlzeit" else "Mahlzeit") },
                    navigationIcon = { IconButton(onClick = model::closeDraft) { Icon(Icons.Filled.Close, contentDescription = "Ohne Speichern schließen") } },
                    actions = {
                        if (!draft.isNew) {
                            IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Filled.Delete, contentDescription = "Mahlzeit löschen") }
                        }
                        Button(onClick = model::saveDraft, enabled = meal.items.isNotEmpty(), modifier = Modifier.padding(end = 8.dp)) { Text("Speichern") }
                    },
                )
            },
        ) { padding ->
            LazyColumn(
                Modifier.padding(padding).fillMaxSize().imePadding(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item {
                    OutlinedTextField(
                        value = meal.title,
                        onValueChange = { title -> model.changeDraft { it.copy(title = title.take(80)) } },
                        label = { Text("Titel") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        MealCategory.entries.forEach { category ->
                            FilterChip(selected = meal.category == category, onClick = { model.changeDraft { it.copy(category = category) } }, label = { Text(category.label) })
                        }
                    }
                }
                item {
                    Text(
                        "${formatKg(Math.rint(totals[Nutrient.KCAL] ?: 0.0))} kcal · Protein ${formatKg(Math.rint(totals[Nutrient.PROTEIN] ?: 0.0))} g · " +
                            "KH ${formatKg(Math.rint(totals[Nutrient.CARBS] ?: 0.0))} g · Fett ${formatKg(Math.rint(totals[Nutrient.FAT] ?: 0.0))} g",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    val missingKcal = meal.items.count { it.per100g[Nutrient.KCAL] == null }
                    if (missingKcal > 0) {
                        Text("$missingKcal Position(en) ohne Kalorienangabe – zählen als 0.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    }
                    if (meal.hint.isNotBlank()) {
                        Text(meal.hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (draft.possiblyMissing.isNotEmpty() && model.access.isConfigured) {
                    item {
                        Text("Vielleicht vergessen? Antippen ergänzt per KI:", style = MaterialTheme.typography.labelMedium)
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            draft.possiblyMissing.forEach { thing -> AssistChip(onClick = { model.amend(thing) }, label = { Text("+ $thing") }) }
                        }
                    }
                }
                items(meal.items, key = { it.id }) { item ->
                    ItemCard(
                        item = item,
                        onGrams = { grams -> changeItem(item.id) { it.copy(grams = grams, plannedGrams = null) } },
                        onPortions = { count -> changeItem(item.id) { it.withPortions(count).copy(plannedGrams = null) } },
                        onReplace = { replacing = item },
                        onRemove = { model.changeDraft { it.copy(items = it.items.filter { other -> other.id != item.id }) } },
                    )
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { adding = true }) { Text("Lebensmittel hinzufügen") }
                    }
                }
                if (model.access.isConfigured) {
                    item {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(
                                value = amendText,
                                onValueChange = { amendText = it },
                                label = { Text("Ergänzen (KI)") },
                                placeholder = { Text("z. B. noch 1 EL Olivenöl") },
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(onClick = {
                                model.amend(amendText)
                                amendText = ""
                            }, enabled = amendText.isNotBlank()) { Text("Los") }
                        }
                    }
                }
            }
        }
    }

    replacing?.let { item ->
        FoodSearchDialog(
            title = "BLS-Lebensmittel für „${item.name}“",
            initial = item.searchTerm ?: item.name,
            viewModel = viewModel,
            data = data,
            onDismiss = { replacing = null },
        ) { food ->
            val current = bls
            if (current != null && food.source == FoodSource.BLS) {
                val blsFood = food.blsCode?.let(current::food)
                if (blsFood != null) changeItem(item.id) { current.apply(blsFood, it).copy(name = blsFood.name) }
            } else {
                changeItem(item.id) { food.copy(id = it.id, grams = it.grams) }
            }
            replacing = null
        }
    }
    if (adding) {
        FoodSearchDialog(title = "Lebensmittel hinzufügen", initial = "", viewModel = viewModel, data = data, onDismiss = { adding = false }) { food ->
            model.addToDraft(food.copy(id = java.util.UUID.randomUUID().toString(), grams = food.portion?.grams ?: 100.0), LocalDate.now())
            adding = false
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Mahlzeit löschen?") },
            text = { Text("„${meal.title}“ wird aus dem Tagebuch entfernt.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    model.deleteDraft()
                }) { Text("Löschen") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun ItemCard(
    item: MealItem,
    onGrams: (Double) -> Unit,
    onPortions: (Double) -> Unit,
    onReplace: () -> Unit,
    onRemove: () -> Unit,
) {
    var gramsText by remember(item.id) { mutableStateOf(formatKg(item.grams)) }
    // Menge von außen geändert (Portions-Chip): Feld nachziehen, ohne das Tippen zu stören.
    LaunchedEffect(item.grams) { if (parseDecimal(gramsText) != item.grams) gramsText = formatKg(item.grams) }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(item.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    val source = when {
                        item.source == FoodSource.AI -> "KI-Schätzung" + (item.confidence?.let { " (Sicherheit $it)" } ?: "")
                        item.isQuickEstimate -> "Schätzung"
                        else -> item.source.label
                    }
                    Text(
                        "${formatKg(Math.rint(item.amounts[Nutrient.KCAL] ?: 0.0))} kcal · P ${formatKg(Math.rint(item.amounts[Nutrient.PROTEIN] ?: 0.0))} g · $source",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (item.source == FoodSource.AI) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = onRemove) { Icon(Icons.Filled.Delete, contentDescription = "Entfernen") }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (!item.isQuickEstimate) {
                    OutlinedTextField(
                        value = gramsText,
                        onValueChange = { text ->
                            gramsText = text
                            parseDecimal(text)?.let(onGrams)
                        },
                        label = { Text(if (item.isDrink) "ml" else "g") },
                        singleLine = true,
                        modifier = Modifier.width(110.dp),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    )
                }
                if (!item.isQuickEstimate) TextButton(onClick = onReplace) { Text("Zuordnung ändern") }
            }
            item.portion?.let { portion ->
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    PortionGuess.quickCounts.forEach { count ->
                        FilterChip(
                            selected = item.portionCount?.let { Math.abs(it - count) < 0.01 } == true,
                            onClick = { onPortions(count) },
                            label = { Text("${PortionGuess.format(count)} × ${portion.name}") },
                        )
                    }
                }
            }
        }
    }
}

/** Suche in eigenen Lebensmitteln und im BLS; liefert eine Position (Menge wird vom Aufrufer gesetzt). */
@Composable
fun FoodSearchDialog(
    title: String,
    initial: String,
    viewModel: GymViewModel,
    data: AppData,
    onDismiss: () -> Unit,
    onPick: (MealItem) -> Unit,
) {
    val bls by viewModel.nutrition.bls.collectAsState()
    var query by rememberSaveable { mutableStateOf(initial) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(title, maxLines = 1) },
                    navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Schließen") } },
                )
            },
        ) { padding ->
            LazyColumn(Modifier.padding(padding).fillMaxSize().imePadding(), contentPadding = PaddingValues(16.dp)) {
                item {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text("Suchen") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                val own = data.foods.filter { io.github.hkrb7p794w.gym.core.FoodSearch.normalized(it.name).contains(io.github.hkrb7p794w.gym.core.FoodSearch.normalized(query)) && query.isNotBlank() }.take(5)
                items(own, key = { "own-" + it.id }) { FoodRow(it) { onPick(it) } }
                val results = bls?.search(query, 30).orEmpty()
                items(results, key = { "bls-" + it.code }) { food -> FoodRow(food.item()) { onPick(food.item()) } }
                if (bls == null) item { Text("BLS wird geladen …") }
            }
        }
    }
}
