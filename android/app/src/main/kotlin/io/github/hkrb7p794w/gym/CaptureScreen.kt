@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.FoodSearch
import io.github.hkrb7p794w.gym.core.FoodSource
import io.github.hkrb7p794w.gym.core.MealItem
import io.github.hkrb7p794w.gym.core.MealSuggestions
import io.github.hkrb7p794w.gym.core.Nutrient
import io.github.hkrb7p794w.gym.core.Nutrition
import io.github.hkrb7p794w.gym.core.get
import kotlinx.coroutines.launch
import java.io.File
import java.time.LocalDate

/** Erfassen: Text oder Foto per KI, Barcode, Suche (eigene + BLS), Zuletzt/Häufig/Favoriten, Schnell-Eintrag. */
@Composable
fun CaptureDialog(viewModel: GymViewModel, data: AppData, day: LocalDate, onDismiss: () -> Unit) {
    val model = viewModel.nutrition
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val bls by model.bls.collectAsState()
    var text by rememberSaveable { mutableStateOf("") }
    var query by rememberSaveable { mutableStateOf("") }
    var manualBarcode by rememberSaveable { mutableStateOf<String?>(null) }
    var quickEntry by rememberSaveable { mutableStateOf(false) }
    var ownFood by rememberSaveable { mutableStateOf(false) }
    var sharedCode by rememberSaveable { mutableStateOf<String?>(null) }
    // Über Neustarts der Aktivität hinweg merken (die Kamera-App kann sie beenden).
    var photoUri by rememberSaveable { mutableStateOf<String?>(null) }
    val connected = model.access.isConfigured
    val category = model.category()

    fun analyzePhoto(uri: Uri) {
        scope.launch {
            val photo = model.photoBase64(uri)
            if (photo == null) return@launch
            model.analyze(text, photo, day)
            onDismiss()
        }
    }

    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val uri = photoUri
        if (saved && uri != null) analyzePhoto(Uri.parse(uri))
    }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) analyzePhoto(uri)
    }

    fun takePhoto() {
        val file = File(context.cacheDir, "photos").apply { mkdirs() }.let { File(it, "mahlzeit.jpg") }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        photoUri = uri.toString()
        try {
            camera.launch(uri)
        } catch (_: ActivityNotFoundException) {
            gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }
    }

    fun scanBarcode() {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8, Barcode.FORMAT_UPC_A)
            .build()
        GmsBarcodeScanning.getClient(context, options).startScan()
            .addOnSuccessListener { barcode ->
                barcode.rawValue?.let {
                    model.lookupBarcode(it, day)
                    onDismiss()
                }
            }
            // Ohne Google-Play-Dienste oder abgebrochen: Nummer von Hand eingeben.
            .addOnFailureListener { manualBarcode = "" }
    }

    fun pick(item: MealItem) {
        val grams = item.portion?.grams ?: item.grams.takeIf { it > 0 } ?: 100.0
        model.addToDraft(item.copy(id = java.util.UUID.randomUUID().toString(), grams = grams), day)
        onDismiss()
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Erfassen · ${category.label}") },
                    navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Schließen") } },
                )
            },
        ) { padding ->
            LazyColumn(
                Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item {
                    OutlinedTextField(
                        value = text,
                        onValueChange = { text = it },
                        label = { Text("Was hast du gegessen?") },
                        placeholder = { Text("z. B. 2 Eier, 1 Scheibe Vollkornbrot mit Butter, Kaffee mit Milch") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                    )
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                model.analyze(text, null, day)
                                onDismiss()
                            },
                            enabled = connected && text.isNotBlank(),
                        ) { Text("Mit KI auswerten") }
                        OutlinedButton(onClick = ::takePhoto, enabled = connected) { Text("Foto") }
                        OutlinedButton(
                            onClick = { gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                            enabled = connected,
                        ) { Text("Galerie") }
                    }
                }
                if (!connected) {
                    item {
                        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
                            Text(
                                "KI ist nicht verbunden. Öffne den Link von der Download-Seite („In der App verbinden“) " +
                                    "oder trage den Zugang unter Ernährung › Zahnrad › KI-Zugang ein. Suche, Barcode und " +
                                    "Schnell-Einträge gehen auch ohne.",
                                Modifier.padding(12.dp),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = ::scanBarcode) { Text("Barcode scannen") }
                        TextButton(onClick = { manualBarcode = "" }) { Text("Nummer eingeben") }
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { quickEntry = true }) { Text("Schnell-Eintrag (kcal)") }
                        OutlinedButton(onClick = { ownFood = true }) { Text("Eigenes Lebensmittel") }
                    }
                    if (connected) {
                        TextButton(onClick = { sharedCode = "" }) { Text("Geteilte Mahlzeit öffnen") }
                    }
                }
                item { HorizontalDivider() }
                item {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text("Lebensmittel suchen") },
                        placeholder = { Text("z. B. Haferflocken, Banane, Skyr") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (query.isNotBlank()) {
                    val own = FoodSearch.rank(
                        FoodSearch.ownFoods(data.meals) + data.foods.map { FoodSearch.Candidate(FoodSearch.normalized(it.name), it.name, 0, 0, it) },
                        query,
                        limit = 8,
                    ).distinctBy { it.id }
                    if (own.isNotEmpty()) {
                        item { SectionTitle("Deine Lebensmittel") }
                        items(own, key = { "own-" + it.id }) { candidate ->
                            FoodRow(candidate.item) { pick(candidate.item) }
                        }
                    }
                    val results = bls?.search(query, 25).orEmpty()
                    item { SectionTitle(if (bls == null) "BLS wird geladen …" else "BLS 4.0 (${results.size})") }
                    items(results, key = { "bls-" + it.code }) { food ->
                        FoodRow(food.item()) { pick(food.item()) }
                    }
                } else {
                    if (data.recipes.isNotEmpty()) {
                        item { SectionTitle("Rezepte") }
                        items(data.recipes, key = { "rec-" + it.id }) { recipe ->
                            QuickRow(
                                recipe.name + (recipe.remainingPortions?.let { " · Vorrat ${formatKg(it)}" } ?: ""),
                                recipe.item().amounts[Nutrient.KCAL],
                            ) {
                                viewModel.update { io.github.hkrb7p794w.gym.core.Diary.logRecipe(it, recipe, null, category, System.currentTimeMillis()) }
                                onDismiss()
                            }
                        }
                    }
                    val yesterday = MealSuggestions.yesterday(data.meals, category, LocalDate.now())
                    if (yesterday.isNotEmpty()) {
                        item { SectionTitle("Wie gestern") }
                        items(yesterday, key = { "y-" + it.id }) { meal ->
                            QuickRow(meal.title, meal.totals[Nutrient.KCAL]) {
                                model.logCopy(meal.title, meal.items, category, day)
                                onDismiss()
                            }
                        }
                    }
                    val frequent = MealSuggestions.frequentAll(data.meals, LocalDate.now())
                    if (frequent.isNotEmpty()) {
                        item { SectionTitle("Häufig") }
                        items(frequent, key = { "f-" + it.id }) { suggestion ->
                            QuickRow("${suggestion.title} (${suggestion.count}×)", suggestion.kcal) {
                                model.logCopy(suggestion.title, suggestion.items, category, day)
                                onDismiss()
                            }
                        }
                    }
                    if (data.favorites.isNotEmpty()) {
                        item { SectionTitle("Favoriten") }
                        items(data.favorites, key = { "fav-" + it.id }) { favorite ->
                            QuickRow(favorite.title, Nutrition.totals(favorite.items)[Nutrient.KCAL]) {
                                model.logCopy(favorite.title, favorite.items, favorite.category ?: category, day)
                                onDismiss()
                            }
                        }
                    }
                    val recent = MealSuggestions.recent(data.meals.filterNot { meal -> meal.items.all { it.name == "Wasser" } })
                    if (recent.isNotEmpty()) {
                        item { SectionTitle("Zuletzt") }
                        items(recent, key = { "r-" + it.id }) { meal ->
                            QuickRow(meal.title, meal.totals[Nutrient.KCAL]) {
                                model.logCopy(meal.title, meal.items, category, day)
                                onDismiss()
                            }
                        }
                    }
                }
                item {
                    Text(
                        "Nährwerte: ${io.github.hkrb7p794w.gym.core.Bls.ATTRIBUTION}; Barcodes: Open Food Facts (ODbL).",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    manualBarcode?.let { value ->
        AlertDialog(
            onDismissRequest = { manualBarcode = null },
            title = { Text("Barcode eingeben") },
            text = {
                OutlinedTextField(
                    value = value,
                    onValueChange = { manualBarcode = it.filter(Char::isDigit).take(14) },
                    label = { Text("8 oder 13 Ziffern") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    model.lookupBarcode(value, day)
                    manualBarcode = null
                    onDismiss()
                }, enabled = value.length >= 8) { Text("Suchen") }
            },
            dismissButton = { TextButton(onClick = { manualBarcode = null }) { Text("Abbrechen") } },
        )
    }
    sharedCode?.let { value ->
        AlertDialog(
            onDismissRequest = { sharedCode = null },
            title = { Text("Geteilte Mahlzeit öffnen") },
            text = {
                OutlinedTextField(
                    value = value,
                    onValueChange = { sharedCode = it.trim() },
                    label = { Text("Link oder Code (10 Zeichen)") },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    model.openShared(value, day)
                    sharedCode = null
                    onDismiss()
                }, enabled = value.isNotBlank()) { Text("Öffnen") }
            },
            dismissButton = { TextButton(onClick = { sharedCode = null }) { Text("Abbrechen") } },
        )
    }
    if (quickEntry) {
        NutrientInputDialog(
            title = "Schnell-Eintrag",
            hint = "Werte für die ganze Portion (z. B. Restaurant). Wird als Schätzung markiert.",
            withName = true,
            onDismiss = { quickEntry = false },
        ) { name, kcal, protein, carbs, fat ->
            model.logCopy(name.ifBlank { "Schnell-Eintrag" }, listOf(MealItem.quick(name.ifBlank { "Schnell-Eintrag" }, kcal, protein, carbs, fat)), category, day)
            quickEntry = false
            onDismiss()
        }
    }
    if (ownFood) {
        NutrientInputDialog(
            title = "Eigenes Lebensmittel (je 100 g)",
            hint = "Werte vom Etikett je 100 g. Die Menge stellst du danach im Entwurf ein.",
            withName = true,
            onDismiss = { ownFood = false },
        ) { name, kcal, protein, carbs, fat ->
            val values = mutableMapOf(Nutrient.KCAL.key to kcal)
            protein?.let { values[Nutrient.PROTEIN.key] = it }
            carbs?.let { values[Nutrient.CARBS.key] = it }
            fat?.let { values[Nutrient.FAT.key] = it }
            ownFood = false
            pick(MealItem(name = name.ifBlank { "Eigenes Lebensmittel" }, grams = 100.0, source = FoodSource.MANUAL, per100g = values))
        }
    }
}

@Composable
fun FoodRow(item: MealItem, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(item.name) },
        supportingContent = {
            Text(
                "${formatKg(Math.rint(item.per100g[Nutrient.KCAL] ?: 0.0))} kcal · P ${formatKg(item.per100g[Nutrient.PROTEIN] ?: 0.0)} g je 100 " +
                    (if (item.isDrink) "ml" else "g") + " · " + item.source.label,
            )
        },
        modifier = Modifier.clickable(onClick = onClick),
    )
}

@Composable
private fun QuickRow(title: String, kcal: Double?, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title, maxLines = 2) },
        supportingContent = { Text("${formatKg(Math.rint(kcal ?: 0.0))} kcal · Tippen trägt ein") },
        modifier = Modifier.clickable(onClick = onClick),
    )
}

/** Name, kcal und optional Makros eingeben. */
@Composable
fun NutrientInputDialog(
    title: String,
    hint: String,
    withName: Boolean,
    onDismiss: () -> Unit,
    onSave: (name: String, kcal: Double, protein: Double?, carbs: Double?, fat: Double?) -> Unit,
) {
    var name by rememberSaveable { mutableStateOf("") }
    var kcal by rememberSaveable { mutableStateOf("") }
    var protein by rememberSaveable { mutableStateOf("") }
    var carbs by rememberSaveable { mutableStateOf("") }
    var fat by rememberSaveable { mutableStateOf("") }
    fun optional(text: String) = if (text.isBlank()) null else parseDecimal(text)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(hint, style = MaterialTheme.typography.bodySmall)
                if (withName) OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, singleLine = true)
                NumberField("kcal", kcal) { kcal = it }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    NumberField("Protein g", protein, Modifier.weight(1f)) { protein = it }
                    NumberField("KH g", carbs, Modifier.weight(1f)) { carbs = it }
                    NumberField("Fett g", fat, Modifier.weight(1f)) { fat = it }
                }
            }
        },
        confirmButton = {
            val value = parseDecimal(kcal)
            TextButton(onClick = { value?.let { onSave(name.trim(), it, optional(protein), optional(carbs), optional(fat)) } }, enabled = kcal.isNotBlank() && value != null) {
                Text("Speichern")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Abbrechen") } },
    )
}

@Composable
fun NumberField(label: String, value: String, modifier: Modifier = Modifier, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = { onChange(it.filter { c -> c.isDigit() || c == ',' || c == '.' }.take(7)) },
        label = { Text(label) },
        singleLine = true,
        modifier = modifier,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
    )
}
