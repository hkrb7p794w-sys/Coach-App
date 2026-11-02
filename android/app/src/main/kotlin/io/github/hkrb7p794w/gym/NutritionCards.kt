@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Diary
import io.github.hkrb7p794w.gym.core.Nutrient
import io.github.hkrb7p794w.gym.core.NutrientMap
import io.github.hkrb7p794w.gym.core.NutritionGoal
import io.github.hkrb7p794w.gym.core.NutritionPlanner
import io.github.hkrb7p794w.gym.core.WeightForecast
import io.github.hkrb7p794w.gym.core.WeightTrend
import io.github.hkrb7p794w.gym.core.get
import java.time.LocalDate

@Composable
fun PendingCard(count: Int, onRetry: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("$count Mahlzeit(en) ohne Netz gespeichert", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            TextButton(onClick = onRetry) { Text("Jetzt auswerten") }
        }
    }
}

/** „Was esse ich jetzt?“ – drei Gerichte zum Rest des Tages; die App prüft Ernährungsweise und Allergene. */
@Composable
fun NowCard(viewModel: GymViewModel, day: LocalDate) {
    val model = viewModel.nutrition
    val now by model.now.collectAsState()
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Was esse ich jetzt?", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                if (now != null) TextButton(onClick = model::clearNow) { Text("Ausblenden") }
            }
            val result = now
            if (result == null) {
                Text("Drei Ideen passend zu dem, was heute noch übrig ist.", style = MaterialTheme.typography.bodySmall)
                OutlinedButton(onClick = { model.suggestNow(day) }) { Text("Vorschläge holen") }
            } else {
                result.recipes.forEach { recipe ->
                    Column(
                        Modifier.fillMaxWidth().clickable { model.draftFrom(recipe, day, "Vorschlag „Was jetzt?“ (Nährwerte KI-geschätzt)") }.padding(vertical = 4.dp),
                    ) {
                        Text(recipe.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${formatKg(Math.rint(recipe.totals[Nutrient.KCAL] ?: 0.0))} kcal · Protein ${formatKg(Math.rint(recipe.totals[Nutrient.PROTEIN] ?: 0.0))} g · ${recipe.minutes} min",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(recipe.ingredients.joinToString(", ") { "${it.name} ${formatKg(it.grams)} g" }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("Tippen übernimmt als Entwurf", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    }
                }
                result.notes.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                TextButton(onClick = { model.suggestNow(day) }) { Text("Neue Vorschläge") }
            }
        }
    }
}

/** Abends: Ernährung des Tages auswerten (Worker `nutrition_review`, nur gestützt auf die Regeln der App). */
@Composable
fun ReviewCard(viewModel: GymViewModel, day: LocalDate) {
    val model = viewModel.nutrition
    val review by model.review.collectAsState()
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Tag auswerten", style = MaterialTheme.typography.titleMedium)
            val current = review?.takeIf { it.day == day.toString() }
            if (current == null) {
                Text("Hat das Essen zum Training gepasst? Was fehlt noch?", style = MaterialTheme.typography.bodySmall)
                OutlinedButton(onClick = { model.reviewDay(day) }) { Text("Auswerten") }
            } else {
                current.points.forEach { Text("• $it", style = MaterialTheme.typography.bodyMedium) }
                if (current.sources.isNotEmpty()) {
                    Text("Grundlagen: " + current.sources.joinToString(", ") { it.title }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(onClick = { model.reviewDay(day) }) { Text("Neu auswerten") }
            }
        }
    }
}

/** Alle Nährstoffe mit Ziel (eingeklappt). */
@Composable
fun NutrientsCard(targets: NutrientMap, totals: NutrientMap) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth().clickable { expanded = !expanded }) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (expanded) "Alle Nährstoffe ▲" else "Alle Nährstoffe ▼", style = MaterialTheme.typography.titleMedium)
            if (expanded) {
                Nutrient.entries.filter { targets[it] != null }.forEach { nutrient ->
                    val actual = totals[nutrient] ?: 0.0
                    val target = targets[nutrient] ?: 0.0
                    val percent = if (target > 0) Math.rint(actual / target * 100).toInt() else 0
                    val warn = if (nutrient.isUpperLimit) actual > target else percent < 50
                    Row {
                        Text(nutrient.label + if (nutrient.isUpperLimit) " (max.)" else "", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                        Text(
                            "${formatKg(Math.rint(actual))} / ${formatKg(target)} ${nutrient.unit} ($percent %)",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (warn) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                Text("Ziele nach DGE-Referenzwerten; Werte sind nur so vollständig wie die Einträge.", style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

/** Gewicht: Eingabe, Trend über 28 Tage, Vorschlag zur Tagesenergie, Prognose beim Abnehmen. */
@Composable
fun WeightCard(viewModel: GymViewModel, data: AppData) {
    var entering by rememberSaveable { mutableStateOf(false) }
    val today = LocalDate.now()
    val latest = data.weights.lastOrNull()
    val trend = WeightTrend.trend(data.weights, today)
    val planned = data.nutrition.weeklyChangePercent ?: when (data.nutrition.goal) {
        NutritionGoal.LOSE -> -0.5
        NutritionGoal.GAIN -> 0.25
        else -> null
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Gewicht", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                TextButton(onClick = { entering = true }) { Text("Eintragen") }
            }
            if (latest == null) {
                Text("Am besten morgens nach dem Aufstehen wiegen. Ab 8 Wägungen in 2 Wochen zeigt die App den Trend.", style = MaterialTheme.typography.bodySmall)
            } else {
                Text("Zuletzt ${formatKg(latest.kilograms)} kg (${formatShortDate(java.time.LocalDate.parse(latest.day).atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli())})", style = MaterialTheme.typography.bodyMedium)
            }
            if (trend != null) {
                Text("Trend ${formatKg(trend.trendKilograms)} kg · ${formatKg(trend.weeklyPercent)} % pro Woche", style = MaterialTheme.typography.bodyMedium)
                val advice = WeightTrend.advice(trend, planned, data.nutrition.energyAdjustmentKcal)
                Text(advice.message, style = MaterialTheme.typography.bodySmall)
                if (advice.kcal != 0.0) {
                    Button(onClick = { viewModel.update { Diary.applyAdjustment(it, advice.kcal) } }) {
                        Text("Übernehmen (${if (advice.kcal > 0) "+" else ""}${advice.kcal.toInt()} kcal/Tag)")
                    }
                }
            }
            if (data.nutrition.energyAdjustmentKcal != 0.0) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Angepasst: ${data.nutrition.energyAdjustmentKcal.toInt()} kcal/Tag", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                    TextButton(onClick = { viewModel.update { it.copy(nutrition = it.nutrition.copy(energyAdjustmentKcal = 0.0)) } }) { Text("Zurücksetzen") }
                }
            }
            if (planned != null && planned < 0) {
                val maintenance = NutritionPlanner.compute(data.nutrition.copy(goal = NutritionGoal.MAINTAIN, weeklyChangePercent = null, energyAdjustmentKcal = 0.0), Diary.dayType(data, today)).values[Nutrient.KCAL]
                WeightForecast.compute(latest?.kilograms ?: data.nutrition.weightKg, planned, data.nutrition.heightCm, maintenance, data.nutrition.targetWeightKg, today)?.let { forecast ->
                    Text(
                        "Prognose bei ${formatKg(forecast.weeklyPercent)} % pro Woche (≈ ${forecast.dailyDeficit.toInt()} kcal Defizit am Tag): " +
                            forecast.points.joinToString(" · ") { "${it.weeks} Wo. ${formatKg(it.kilograms)} kg" } +
                            (forecast.weeksToTarget?.let { " · Ziel in etwa $it Wochen" } ?: "") +
                            (if (forecast.deficitCapped) " (Defizit auf 25 % des Bedarfs begrenzt)" else ""),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
    if (entering) {
        var text by rememberSaveable { mutableStateOf(latest?.kilograms?.let(::formatKg).orEmpty()) }
        AlertDialog(
            onDismissRequest = { entering = false },
            title = { Text("Gewicht heute") },
            text = { NumberField("kg", text, Modifier.width(160.dp)) { text = it } },
            confirmButton = {
                TextButton(onClick = {
                    parseDecimal(text)?.let { kg -> viewModel.update { Diary.addWeight(it, today, kg) } }
                    entering = false
                }, enabled = parseDecimal(text)?.let { it in 25.0..300.0 } == true) { Text("Speichern") }
            },
            dismissButton = { TextButton(onClick = { entering = false }) { Text("Abbrechen") } },
        )
    }
}
