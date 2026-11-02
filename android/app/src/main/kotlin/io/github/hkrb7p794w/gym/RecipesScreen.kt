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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.Allergen
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Diary
import io.github.hkrb7p794w.gym.core.Nutrient
import io.github.hkrb7p794w.gym.core.OwnRecipe
import io.github.hkrb7p794w.gym.core.RecipePlanner
import io.github.hkrb7p794w.gym.core.ShoppingAisle
import io.github.hkrb7p794w.gym.core.get
import io.github.hkrb7p794w.gym.core.weekdayLong
import java.time.LocalDate

@Composable
fun RecipesScreen(viewModel: GymViewModel, data: AppData, onBack: () -> Unit) {
    var tab by rememberSaveable { mutableStateOf(0) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Rezepte & Woche") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            TabRow(selectedTabIndex = tab) {
                listOf("Meine Rezepte", "Wochenplan", "Einkaufsliste").forEachIndexed { index, label ->
                    Tab(selected = tab == index, onClick = { tab = index }, text = { Text(label) })
                }
            }
            when (tab) {
                0 -> OwnRecipesTab(viewModel, data)
                1 -> WeeklyPlanTab(viewModel, data)
                else -> ShoppingTab(viewModel, data)
            }
        }
    }
}

@Composable
private fun OwnRecipesTab(viewModel: GymViewModel, data: AppData) {
    var editing by remember { mutableStateOf<OwnRecipe?>(null) }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (data.recipes.isEmpty()) {
            item {
                Text(
                    "Noch keine Rezepte. Auf der Ernährungsseite bei einer Mahlzeit ⋮ › „Als Rezept speichern“: Zutaten " +
                        "für den ganzen Topf, dann hier Portionen und gekochtes Gewicht eintragen. Beim Eintragen zählt " +
                        "der Vorrat mit.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(data.recipes, key = { it.id }) { recipe ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).clickable { editing = recipe }) {
                            Text(recipe.name, style = MaterialTheme.typography.titleMedium)
                            Text(
                                "${recipe.portions} Portionen à ${formatKg(Math.rint(recipe.portionGrams))} g · " +
                                    "${formatKg(Math.rint(recipe.item().amounts[Nutrient.KCAL] ?: 0.0))} kcal je Portion" +
                                    (recipe.remainingPortions?.let { " · Vorrat ${formatKg(it)}" } ?: ""),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        IconButton(onClick = { viewModel.update { Diary.deleteRecipe(it, recipe.id) } }) { Icon(Icons.Filled.Delete, contentDescription = "Rezept löschen") }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            viewModel.update { Diary.logRecipe(it, recipe, null, viewModel.nutrition.category(), System.currentTimeMillis()) }
                        }) { Text("1 Portion eintragen") }
                        OutlinedButton(onClick = {
                            viewModel.update { Diary.saveRecipe(it, recipe.copy(remainingPortions = recipe.portions.toDouble())) }
                        }) { Text("Gekocht") }
                    }
                }
            }
        }
    }
    editing?.let { recipe ->
        var name by rememberSaveable(recipe.id) { mutableStateOf(recipe.name) }
        var portions by rememberSaveable(recipe.id) { mutableStateOf(recipe.portions.toString()) }
        var cooked by rememberSaveable(recipe.id) { mutableStateOf(recipe.cookedGrams?.let(::formatKg).orEmpty()) }
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text("Rezept bearbeiten") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, singleLine = true)
                    NumberField("Portionen", portions) { portions = it.filter(Char::isDigit) }
                    NumberField("Gewicht gekocht in g (optional)", cooked) { cooked = it }
                    Text("Zutaten: " + recipe.ingredients.joinToString(", ") { "${it.name} ${formatKg(it.grams)} g" }, style = MaterialTheme.typography.bodySmall)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val updated = recipe.copy(
                        name = name.trim().ifEmpty { recipe.name },
                        portions = portions.toIntOrNull()?.coerceIn(1, 30) ?: recipe.portions,
                        cookedGrams = if (cooked.isBlank()) null else parseDecimal(cooked)?.takeIf { it > 0 },
                    )
                    viewModel.update { Diary.saveRecipe(it, updated) }
                    editing = null
                }) { Text("Speichern") }
            },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun WeeklyPlanTab(viewModel: GymViewModel, data: AppData) {
    val model = viewModel.nutrition
    val prefs = data.recipePreferences
    var dislikes by rememberSaveable { mutableStateOf(prefs.dislikes) }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Text(
                "Rezeptideen für die nächsten 7 Tage, passend zu Tageszielen und Tagestyp. Die App verwirft Gerichte, " +
                    "die nicht zu Ernährungsweise oder Allergenen passen, und passt die Mengen ans Tagesziel an.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Text("Allergene", style = MaterialTheme.typography.labelLarge)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Allergen.entries.forEach { allergen ->
                    FilterChip(
                        selected = allergen in prefs.allergens,
                        onClick = {
                            viewModel.update { data ->
                                val set = data.recipePreferences.allergens
                                data.copy(recipePreferences = data.recipePreferences.copy(allergens = if (allergen in set) set - allergen else set + allergen))
                            }
                        },
                        label = { Text(allergen.label) },
                    )
                }
            }
        }
        item {
            OutlinedTextField(
                value = dislikes,
                onValueChange = { text ->
                    dislikes = text.take(200)
                    viewModel.update { it.copy(recipePreferences = it.recipePreferences.copy(dislikes = dislikes)) }
                },
                label = { Text("Mag ich nicht (z. B. Pilze, Koriander)") },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Kochzeit bis", style = MaterialTheme.typography.labelLarge)
                listOf(15, 30, 45).forEach { minutes ->
                    FilterChip(selected = prefs.maxMinutes == minutes, onClick = { viewModel.update { it.copy(recipePreferences = it.recipePreferences.copy(maxMinutes = minutes)) } }, label = { Text("$minutes min") })
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Personen", style = MaterialTheme.typography.labelLarge)
                listOf(1, 2, 3, 4).forEach { count ->
                    FilterChip(selected = prefs.servings == count, onClick = { viewModel.update { it.copy(recipePreferences = it.recipePreferences.copy(servings = count)) } }, label = { Text("$count") })
                }
                FilterChip(selected = prefs.mealPrep, onClick = { viewModel.update { it.copy(recipePreferences = it.recipePreferences.copy(mealPrep = !prefs.mealPrep)) } }, label = { Text("Meal-Prep") })
            }
        }
        item {
            Button(onClick = { model.planWeek(LocalDate.now()) }, enabled = model.access.isConfigured) {
                Text(if (data.weeklyPlan == null) "Wochenplan erstellen (KI)" else "Neu planen (KI)")
            }
            if (!model.access.isConfigured) Text("Dafür muss der KI-Zugang verbunden sein.", style = MaterialTheme.typography.bodySmall)
        }
        val plan = data.weeklyPlan
        if (plan != null) {
            plan.notes.forEach { note -> item { Text(note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
            items(plan.days, key = { it.day }) { day ->
                val date = LocalDate.parse(day.day)
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("${date.weekdayLong()} · ${formatKg(Math.rint(day.totals[Nutrient.KCAL] ?: 0.0))} kcal", style = MaterialTheme.typography.titleMedium)
                        day.recipes.forEach { recipe ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text("${recipe.meal.label}: ${recipe.title}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                    Text(recipe.ingredients.joinToString(", ") { "${it.name} ${formatKg(it.grams)} g" }, style = MaterialTheme.typography.bodySmall)
                                    if (recipe.steps.isNotEmpty()) Text(recipe.steps.joinToString(" "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                TextButton(onClick = { model.draftFrom(recipe, LocalDate.now(), "Aus dem Wochenplan (Nährwerte teils KI-geschätzt)") }) { Text("Eintragen") }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ShoppingTab(viewModel: GymViewModel, data: AppData) {
    val plan = data.weeklyPlan
    if (plan == null) {
        Text("Erst einen Wochenplan erstellen – daraus entsteht die Einkaufsliste.", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val items = RecipePlanner.shoppingList(plan, data.recipePreferences.servings)
    val byAisle = items.groupBy { it.aisle }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        item {
            Text("Für ${data.recipePreferences.servings} Person(en), ${items.size} Zutaten.", style = MaterialTheme.typography.bodySmall)
        }
        ShoppingAisle.entries.forEach { aisle ->
            val inAisle = byAisle[aisle].orEmpty()
            if (inAisle.isNotEmpty()) {
                item(key = "aisle-$aisle") { SectionTitle(aisle.label) }
                items(inAisle, key = { "item-" + it.name.lowercase() }) { item ->
                    val key = item.name.lowercase()
                    val done = key in data.shoppingDone
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable {
                        viewModel.update { it.copy(shoppingDone = if (done) it.shoppingDone - key else it.shoppingDone + key) }
                    }) {
                        Checkbox(checked = done, onCheckedChange = null)
                        Text(
                            "${item.name} – ${formatKg(item.grams)} g",
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (done) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
        }
    }
}
