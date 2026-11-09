@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.DayType
import io.github.hkrb7p794w.gym.core.Diary
import io.github.hkrb7p794w.gym.core.Meal
import io.github.hkrb7p794w.gym.core.MealCategory
import io.github.hkrb7p794w.gym.core.MealPortion
import io.github.hkrb7p794w.gym.core.Nutrient
import io.github.hkrb7p794w.gym.core.Nutrition
import io.github.hkrb7p794w.gym.core.NutritionBudget
import io.github.hkrb7p794w.gym.core.get
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val DAY_FORMAT = DateTimeFormatter.ofPattern("EEEE, d. MMMM", Locale.GERMANY)
private val WEEKDAY_SHORT = DateTimeFormatter.ofPattern("EE", Locale.GERMANY)

@Composable
fun NutritionScreen(viewModel: GymViewModel, data: AppData, modifier: Modifier, open: (Page) -> Unit) {
    val model = viewModel.nutrition
    var dayText by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    val day = LocalDate.parse(dayText)
    val today = LocalDate.now()
    var capturing by rememberSaveable { mutableStateOf(false) }
    var choosingDayType by rememberSaveable { mutableStateOf(false) }
    var portionFor by remember { mutableStateOf<Meal?>(null) }
    var friendMeal by remember { mutableStateOf<Meal?>(null) }
    val draft by model.draft.collectAsStateWithLifecycle()
    val busy by model.busy.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val lastLogged by model.lastLogged.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    val shareText by model.shareText.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(shareText) {
        val text = shareText ?: return@LaunchedEffect
        val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, text)
        context.startActivity(android.content.Intent.createChooser(send, "Mahlzeit teilen"))
        model.clearShareText()
    }
    LaunchedEffect(lastLogged) {
        val meal = lastLogged ?: return@LaunchedEffect
        val result = snackbar.showSnackbar("„${meal.title}“ eingetragen", actionLabel = "Rückgängig", duration = SnackbarDuration.Short)
        if (result == SnackbarResult.ActionPerformed) model.undoLast() else model.clearUndo()
    }

    val targets = Diary.targets(data, day)
    val totals = Diary.totals(data, day)
    // Reines Wasser steht in der Übersicht, nicht als Mahlzeit.
    val meals = Nutrition.meals(day, data.meals).filterNot { meal -> meal.items.all { it.isDrink && it.name == "Wasser" } }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text("Ernährung") },
                actions = {
                    TextButton(onClick = { open(Page.Recipes) }) { Text("Rezepte & Woche") }
                    IconButton(onClick = { open(Page.NutritionSettings) }) { Icon(Icons.Filled.Settings, contentDescription = "Ernährung einstellen") }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { capturing = true },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text("Erfassen") },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { dayText = day.minusDays(1).toString() }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Tag davor")
                    }
                    Text(
                        if (day == today) "Heute" else DAY_FORMAT.format(day),
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f).clickable { dayText = today.toString() },
                    )
                    IconButton(onClick = { dayText = day.plusDays(1).toString() }, enabled = day < today) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Tag danach")
                    }
                }
                WeekStrip(data, day) { dayText = it.toString() }
            }
            if (!data.nutrition.configured) {
                item {
                    Card(
                        Modifier.fillMaxWidth().clickable { open(Page.NutritionSettings) },
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Text("Körperwerte eintragen", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "Die Ziele rechnen bisher mit Standardwerten (75 kg, 180 cm, 35 Jahre). Tippe hier, " +
                                    "um Gewicht, Größe, Alter und Ziel einzutragen.",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                }
            }
            item {
                SummaryCard(data, day, targets.values, totals, onDayType = { choosingDayType = true }, onWater = { model.logWater(it, day) })
            }
            if (data.pending.isNotEmpty()) {
                item { PendingCard(data.pending.size, onRetry = model::retryPending) }
            }
            if (model.access.isConfigured) {
                item { NowCard(viewModel, day) }
            }
            if (meals.isEmpty()) {
                item {
                    Text(
                        "Noch nichts eingetragen. Tippe auf „Erfassen“: Text, Foto, Barcode oder Suche in 7.000 " +
                            "Lebensmitteln (BLS).",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            MealCategory.entries.forEach { category ->
                val inCategory = meals.filter { it.category == category }
                if (inCategory.isNotEmpty()) {
                    item(key = "header-${category.name}") {
                        val kcal = inCategory.sumOf { it.totals[Nutrient.KCAL] ?: 0.0 }
                        SectionTitle("${category.label} · ${formatKg(Math.rint(kcal))} kcal")
                    }
                    items(inCategory, key = { it.id }) { meal ->
                        MealCard(
                            meal = meal,
                            isFavorite = Diary.isFavorite(data, meal),
                            onClick = { model.edit(meal) },
                            onFavorite = { viewModel.update { Diary.toggleFavorite(it, meal) } },
                            onPortion = { portionFor = meal },
                            onShare = if (model.access.isConfigured) ({ model.share(meal) }) else null,
                            onShareFriends = if (viewModel.social.isAvailable) ({ friendMeal = meal }) else null,
                            onRecipe = {
                                viewModel.update { Diary.saveRecipe(it, io.github.hkrb7p794w.gym.core.OwnRecipe.from(meal.title, meal.items)) }
                                open(Page.Recipes)
                            },
                        )
                    }
                }
            }
            if (model.access.isConfigured && meals.isNotEmpty()) {
                item { ReviewCard(viewModel, day) }
            }
            item { NutrientsCard(targets.values, totals) }
            item { WeightCard(viewModel, data) }
        }
    }

    if (capturing) {
        CaptureDialog(viewModel, data, day, onDismiss = { capturing = false })
    }
    draft?.let { MealEditorDialog(viewModel, data, it) }
    busy?.let { text ->
        AlertDialog(onDismissRequest = {}, confirmButton = {}, title = { Text(text) }, text = { LinearProgressIndicator(Modifier.fillMaxWidth()) })
    }
    message?.let { text ->
        AlertDialog(
            onDismissRequest = model::clearMessage,
            confirmButton = { TextButton(onClick = model::clearMessage) { Text("OK") } },
            text = { Text(text) },
        )
    }
    if (choosingDayType) {
        AlertDialog(
            onDismissRequest = { choosingDayType = false },
            title = { Text("Tagestyp") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Bestimmt Kalorien und Kohlenhydrate des Tages.", style = MaterialTheme.typography.bodySmall)
                    DayType.entries.forEach { type ->
                        FilterChip(
                            selected = Diary.dayType(data, day) == type,
                            onClick = {
                                viewModel.update { Diary.setDayType(it, day, type) }
                                choosingDayType = false
                            },
                            label = { Text("${type.label} – ${type.example}") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = { choosingDayType = false }) { Text("Schließen") } },
        )
    }
    friendMeal?.let { meal ->
        ShareWithFriendsDialog(
            title = meal.title,
            preview = "${meal.items.size} Positionen · ${formatKg(Math.rint(meal.totals[Nutrient.KCAL] ?: 0.0))} kcal – Freunde können sie übernehmen.",
            onShare = { note -> viewModel.social.shareMeal(meal.title, meal.items, note) { friendMeal = null } },
            onDismiss = { friendMeal = null },
        )
    }
    portionFor?.let { meal ->
        AlertDialog(
            onDismissRequest = { portionFor = null },
            title = { Text("Wie viel davon gegessen?") },
            text = {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MealPortion.presets.forEach { fraction ->
                        FilterChip(
                            selected = Math.abs(MealPortion.eatenFraction(meal.items) - fraction) < 0.01,
                            onClick = {
                                viewModel.update { Diary.save(it, meal.copy(items = MealPortion.adjusted(meal.items, fraction))) }
                                portionFor = null
                            },
                            label = { Text("${(fraction * 100).toInt()} %") },
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = { portionFor = null }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun WeekStrip(data: AppData, selected: LocalDate, onSelect: (LocalDate) -> Unit) {
    val today = LocalDate.now()
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Diary.week(data, selected).forEach { (date, kcal) ->
            FilterChip(
                selected = date == selected,
                onClick = { if (date <= today) onSelect(date) },
                enabled = date <= today,
                label = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(WEEKDAY_SHORT.format(date), style = MaterialTheme.typography.labelSmall)
                        Text(if (kcal > 0) formatKg(Math.rint(kcal)) else "–", style = MaterialTheme.typography.labelSmall)
                    }
                },
            )
        }
    }
}

@Composable
private fun SummaryCard(
    data: AppData,
    day: LocalDate,
    targets: Map<String, Double>,
    totals: Map<String, Double>,
    onDayType: () -> Unit,
    onWater: (Double) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val kcal = NutritionBudget.line(Nutrient.KCAL, targets, totals)
            if (kcal != null) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${formatKg(Math.rint(kcal.actual))}", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                    Text(" / ${formatKg(kcal.target)} kcal", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.weight(1f))
                    Text(
                        NutritionBudget.remainingText(kcal),
                        color = if (kcal.isOver) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                        style = MaterialTheme.typography.titleSmall,
                    )
                }
                LinearProgressIndicator(progress = { kcal.progress.toFloat() }, modifier = Modifier.fillMaxWidth())
            }
            NutritionBudget.main.forEach { nutrient ->
                NutritionBudget.line(nutrient, targets, totals)?.let { line ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(nutrient.label, Modifier.width(120.dp), style = MaterialTheme.typography.bodyMedium)
                        LinearProgressIndicator(progress = { line.progress.toFloat() }, modifier = Modifier.weight(1f))
                        Text(
                            NutritionBudget.remainingText(line),
                            Modifier.width(96.dp).padding(start = 8.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = if (line.isOver) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            targets[Nutrient.WATER]?.let { target ->
                val hydration = Diary.hydration(data, day)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Wasser ${liters(hydration.total)} / ${liters(target)} l", style = MaterialTheme.typography.bodyMedium)
                        if (hydration.food >= 50) {
                            Text("davon ${liters(hydration.food)} l aus Essen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    TextButton(onClick = { onWater(250.0) }) { Text("+250 ml") }
                    TextButton(onClick = { onWater(500.0) }) { Text("+500 ml") }
                }
            }
            AssistChip(onClick = onDayType, label = { Text("Tagestyp: ${Diary.dayType(data, day).label}") })
        }
    }
}

@Composable
private fun MealCard(
    meal: Meal,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onFavorite: () -> Unit,
    onPortion: () -> Unit,
    onShare: (() -> Unit)?,
    onRecipe: () -> Unit,
    onShareFriends: (() -> Unit)? = null,
) {
    var menu by remember { mutableStateOf(false) }
    val totals = meal.totals
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(meal.title, style = MaterialTheme.typography.titleMedium, maxLines = 2)
                Text(
                    "${formatTime(meal.createdAt)} · ${formatKg(Math.rint(totals[Nutrient.KCAL] ?: 0.0))} kcal · " +
                        "P ${formatKg(Math.rint(totals[Nutrient.PROTEIN] ?: 0.0))} · KH ${formatKg(Math.rint(totals[Nutrient.CARBS] ?: 0.0))} · " +
                        "F ${formatKg(Math.rint(totals[Nutrient.FAT] ?: 0.0))} g",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val fraction = MealPortion.eatenFraction(meal.items)
                if (Math.abs(fraction - 1) > 0.01) {
                    Text("${(fraction * 100).toInt()} % gegessen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.tertiary)
                }
            }
            IconButton(onClick = onFavorite) {
                Icon(
                    if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (isFavorite) "Favorit entfernen" else "Als Favorit merken",
                )
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, contentDescription = "Mehr") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Portion anpassen") }, onClick = { menu = false; onPortion() })
                    if (onShare != null) DropdownMenuItem(text = { Text("Teilen …") }, onClick = { menu = false; onShare() })
                    if (onShareFriends != null) DropdownMenuItem(text = { Text("Mit Freunden teilen") }, onClick = { menu = false; onShareFriends() })
                    DropdownMenuItem(text = { Text("Als Rezept speichern") }, onClick = { menu = false; onRecipe() })
                }
            }
        }
    }
}

private fun liters(milliliters: Double): String = io.github.hkrb7p794w.gym.core.German.number(milliliters / 1000, 2)
