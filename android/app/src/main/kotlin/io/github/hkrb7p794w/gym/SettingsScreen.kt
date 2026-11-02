@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Backup

@Composable
fun SettingsScreen(viewModel: GymViewModel, data: AppData, onBack: () -> Unit) {
    var message by rememberSaveable { mutableStateOf<String?>(null) }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            viewModel.exportBackup(uri) { ok -> message = if (ok) "Sicherung gespeichert." else "Sicherung fehlgeschlagen." }
        }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            viewModel.importBackup(uri) { added ->
                message = if (added == null) "Keine gültige Sicherung dieser App." else "Sicherung eingespielt: $added Trainings neu."
            }
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Einstellungen") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionTitle("Pause nach einem Satz")
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(0, 60, 90, 120, 180).forEach { seconds ->
                    FilterChip(
                        selected = data.settings.restSeconds == seconds,
                        onClick = { viewModel.update { it.copy(settings = it.settings.copy(restSeconds = seconds)) } },
                        label = { Text(if (seconds == 0) "Aus" else formatDuration(seconds * 1000L)) },
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Bildschirm im Training anlassen", Modifier.weight(1f))
                Switch(
                    checked = data.settings.keepScreenOn,
                    onCheckedChange = { on -> viewModel.update { it.copy(settings = it.settings.copy(keepScreenOn = on)) } },
                )
            }

            SectionTitle("Sicherung")
            Text(
                "Deine Trainings und Mahlzeiten liegen nur auf diesem Handy. Android sichert sie automatisch im Google-Konto, wenn " +
                    "„Sicherung“ in den Android-Einstellungen an ist. Zusätzlich kannst du hier eine Datei speichern " +
                    "(z. B. in Google Drive) und auf einem neuen Handy wieder einspielen – dabei geht nichts verloren.",
                style = MaterialTheme.typography.bodyMedium,
            )
            OutlinedButton(
                onClick = { exportLauncher.launch(Backup.fileName(System.currentTimeMillis())) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Sicherung speichern") }
            OutlinedButton(
                onClick = { importLauncher.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Sicherung einspielen") }
            message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

            SectionTitle("Über")
            Text(
                "IronLudi ${BuildConfig.VERSION_NAME} · ${data.sessions.size} Trainings · ${data.meals.size} Mahlzeiten · " +
                    "${viewModel.library.size} Übungen. Regeln wie in der iPhone-App (Doppelprogression, Ernährungsziele, BLS 4.0). " +
                    "Kein Konto; Internet nur für KI über deinen Worker und Barcodes (Open Food Facts).",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
