@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.DayType
import io.github.hkrb7p794w.gym.core.Diary
import io.github.hkrb7p794w.gym.core.Diet
import io.github.hkrb7p794w.gym.core.Nutrient
import io.github.hkrb7p794w.gym.core.NutritionGoal
import io.github.hkrb7p794w.gym.core.NutritionSettings
import io.github.hkrb7p794w.gym.core.get
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

@Composable
fun NutritionSettingsScreen(viewModel: GymViewModel, data: AppData, onBack: () -> Unit) {
    val settings = data.nutrition
    fun change(transform: (NutritionSettings) -> NutritionSettings) =
        viewModel.update { it.copy(nutrition = transform(it.nutrition).copy(configured = true)) }

    var weight by rememberSaveable { mutableStateOf(formatKg(settings.weightKg)) }
    var height by rememberSaveable { mutableStateOf(formatKg(settings.heightCm)) }
    var age by rememberSaveable { mutableStateOf(settings.age.toString()) }
    var bodyFat by rememberSaveable { mutableStateOf(settings.bodyFatPercent?.let(::formatKg).orEmpty()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Ernährung einstellen") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).imePadding().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SectionTitle("Körperwerte")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NumberField("Gewicht kg", weight, Modifier.weight(1f)) { text ->
                    weight = text
                    parseDecimal(text)?.takeIf { it in 30.0..300.0 }?.let { value -> change { it.copy(weightKg = value) } }
                }
                NumberField("Größe cm", height, Modifier.weight(1f)) { text ->
                    height = text
                    parseDecimal(text)?.takeIf { it in 120.0..230.0 }?.let { value -> change { it.copy(heightCm = value) } }
                }
                NumberField("Alter", age, Modifier.weight(1f)) { text ->
                    age = text.filter(Char::isDigit)
                    age.toIntOrNull()?.takeIf { it in 14..100 }?.let { value -> change { it.copy(age = value) } }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                FilterChip(selected = !settings.isFemale, onClick = { change { it.copy(isFemale = false) } }, label = { Text("Mann") })
                FilterChip(selected = settings.isFemale, onClick = { change { it.copy(isFemale = true) } }, label = { Text("Frau") })
            }
            NumberField("Körperfett % (optional, für die Schutzgrenze)", bodyFat, Modifier.fillMaxWidth()) { text ->
                bodyFat = text
                val value = parseDecimal(text)
                change { it.copy(bodyFatPercent = if (text.isBlank()) null else value?.takeIf { v -> v in 3.0..60.0 } ?: it.bodyFatPercent) }
            }
            Text("Alltag ohne Sport", style = MaterialTheme.typography.labelLarge)
            ChipRow(
                listOf(1.2 to "sitzend", 1.4 to "Büro, etwas Bewegung", 1.6 to "viel auf den Beinen", 1.8 to "körperliche Arbeit"),
                selected = settings.activityFactor,
            ) { value -> change { it.copy(activityFactor = value) } }

            SectionTitle("Ziel")
            ChipRow(NutritionGoal.entries.map { it to it.label }, selected = settings.goal) { goal ->
                change { it.copy(goal = goal, weeklyChangePercent = null) }
            }
            if (settings.goal == NutritionGoal.LOSE || settings.goal == NutritionGoal.GAIN) {
                Text("Tempo pro Woche (in % des Körpergewichts)", style = MaterialTheme.typography.labelLarge)
                val options = if (settings.goal == NutritionGoal.LOSE) {
                    listOf<Double?>(null, -0.25, -0.5, -0.75, -1.0)
                } else {
                    listOf<Double?>(null, 0.25, 0.5)
                }
                ChipRow(options.map { it to (it?.let { v -> "${formatKg(v)} %" } ?: "Standard") }, selected = settings.weeklyChangePercent) { value ->
                    change { it.copy(weeklyChangePercent = value) }
                }
                Text(
                    "Höchstens 1 % Abnahme bzw. 0,5 % Zunahme pro Woche; an harten Trainingstagen kein Defizit, und nie " +
                        "unter 30 kcal je kg fettfreie Masse (Schutz vor Energiemangel, IOC 2023).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text("Ernährungsweise (für die KI-Auswertung)", style = MaterialTheme.typography.labelLarge)
            ChipRow(Diet.entries.map { it to it.label }, selected = settings.diet) { diet -> change { it.copy(diet = diet) } }

            val today = Diary.targets(data, LocalDate.now())
            Text(
                "Heute (${today.dayType.label}): ${formatKg(today.values[Nutrient.KCAL] ?: 0.0)} kcal · Protein " +
                    "${formatKg(today.values[Nutrient.PROTEIN] ?: 0.0)} g (${formatKg(today.proteinPerKg)} g/kg) · Grundumsatz " +
                    "${formatKg(today.basalMetabolicRate)} kcal" + if (today.energyFloorApplied) " · auf Schutzgrenze angehoben" else "",
                style = MaterialTheme.typography.bodyMedium,
            )

            SectionTitle("Tagestyp je Wochentag")
            Text(
                "Ohne Uhr weiß die App nicht, wann du trainierst. Lege fest, was an welchem Tag meist ansteht – " +
                    "einzelne Tage änderst du auf der Ernährungsseite.",
                style = MaterialTheme.typography.bodySmall,
            )
            DayOfWeek.entries.forEach { weekday ->
                val current = data.weekDayTypes[weekday.value] ?: DayType.REST
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(weekday.getDisplayName(TextStyle.FULL, Locale.GERMANY), Modifier.width(110.dp))
                    TextButton(onClick = {
                        val next = DayType.entries[(current.ordinal + 1) % DayType.entries.size]
                        viewModel.update { it.copy(weekDayTypes = it.weekDayTypes + (weekday.value to next)) }
                    }) { Text(current.label) }
                }
            }

            WorkerAccessSection(viewModel)
        }
    }
}

@Composable
private fun WorkerAccessSection(viewModel: GymViewModel) {
    val model = viewModel.nutrition
    val status by model.connection.collectAsState()
    var url by rememberSaveable { mutableStateOf(model.access.url) }
    var token by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(Unit) { model.checkConnection() }
    SectionTitle("KI-Zugang")
    Text(
        "Für Foto- und Textauswertung. Am einfachsten über den Link „In der App verbinden“ auf der Download-Seite. " +
            "Gesendet werden nur Beschreibung bzw. Foto der Mahlzeit und deine Ernährungsweise – keine Körperwerte.",
        style = MaterialTheme.typography.bodySmall,
    )
    Text("Status: ${status ?: "wird geprüft …"}", style = MaterialTheme.typography.bodyMedium)
    OutlinedTextField(value = url, onValueChange = { url = it }, label = { Text("Worker-Adresse (https://…)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(
        value = token,
        onValueChange = { token = it.trim() },
        label = { Text(if (model.access.token.isNotEmpty()) "Zugangstoken (gespeichert)" else "Zugangstoken") },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        modifier = Modifier.fillMaxWidth(),
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = { model.connect(url, token).also { token = "" } }, enabled = WorkerAccess.normalized(url) != null) { Text("Speichern und prüfen") }
        if (model.access.isConfigured) OutlinedButton(onClick = model::disconnect) { Text("Trennen") }
    }
}

@Composable
private fun <T> ChipRow(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEach { (value, label) ->
            FilterChip(selected = selected == value, onClick = { onSelect(value) }, label = { Text(label) })
        }
    }
}
