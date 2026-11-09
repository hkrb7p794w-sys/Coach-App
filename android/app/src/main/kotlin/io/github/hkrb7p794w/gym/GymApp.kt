package io.github.hkrb7p794w.gym

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.compose.collectAsStateWithLifecycle

enum class Tab(val label: String, val icon: ImageVector) {
    TRAINING("Training", Icons.Filled.PlayArrow),
    NUTRITION("Ernährung", Icons.Filled.Favorite),
    HISTORY("Verlauf", Icons.Filled.DateRange),
    ROUTINES("Pläne", Icons.AutoMirrored.Filled.List),
    EXERCISES("Übungen", Icons.Filled.Search),
}

/** Unterseiten über den Reitern (einfacher Stapel ohne Navigationsbibliothek). */
sealed interface Page {
    data class SessionDetail(val id: String) : Page
    data class ExerciseDetail(val id: String) : Page
    data class RoutineEditor(val id: String?) : Page
    data object Settings : Page
    data object NutritionSettings : Page
    data object Recipes : Page
    data object Account : Page
    data object Friends : Page
}

@Composable
fun GymApp(viewModel: GymViewModel) {
    val data by viewModel.data.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(Tab.TRAINING) }
    var pages by rememberSaveable(stateSaver = PageStackSaver) { mutableStateOf(listOf<Page>()) }
    var showLoadWarning by rememberSaveable { mutableStateOf(viewModel.loadFailed) }
    val invite by viewModel.pendingInvite.collectAsStateWithLifecycle()

    fun open(page: Page) {
        pages = pages + page
    }

    fun back() {
        pages = pages.dropLast(1)
    }

    BackHandler(enabled = pages.isNotEmpty()) { back() }

    // Serie und Punkte nach jeder Änderung neu berechnen und (mit Konto) melden.
    val friendCount by viewModel.social.friends.collectAsStateWithLifecycle()
    LaunchedEffect(data.sessions.size, data.meals.size, friendCount.size) {
        viewModel.game.report(data, friendCount.size)
    }

    // Einladungslink geöffnet: Kontobildschirm zeigen.
    LaunchedEffect(invite) {
        if (invite != null && pages.lastOrNull() != Page.Account) pages = pages + Page.Account
    }

    if (showLoadWarning) {
        AlertDialog(
            onDismissRequest = { showLoadWarning = false },
            confirmButton = { TextButton(onClick = { showLoadWarning = false }) { Text("Verstanden") } },
            title = { Text("Gespeicherte Daten nicht lesbar") },
            text = {
                Text(
                    "Die Datei mit deinen Trainings ließ sich nicht öffnen. Sie wurde unverändert aufgehoben. " +
                        "Spiele eine Sicherung über Einstellungen › Sicherung einspielen ein.",
                )
            },
        )
    }

    when (val page = pages.lastOrNull()) {
        is Page.SessionDetail -> SessionDetailScreen(viewModel, data, page.id, onBack = ::back, open = ::open)
        is Page.ExerciseDetail -> ExerciseDetailScreen(viewModel, data, page.id, onBack = ::back)
        is Page.RoutineEditor -> RoutineEditorScreen(viewModel, data, page.id, onBack = ::back)
        Page.Settings -> SettingsScreen(viewModel, data, onBack = ::back, openAccount = { open(Page.Account) })
        Page.Friends -> FriendsScreen(viewModel, onBack = ::back, openAccount = { open(Page.Account) })
        Page.Account -> AccountScreen(viewModel, invite, onBack = {
            viewModel.pendingInvite.value = null
            back()
        })
        Page.NutritionSettings -> NutritionSettingsScreen(viewModel, data, onBack = ::back)
        Page.Recipes -> RecipesScreen(viewModel, data, onBack = ::back)
        // Ränder: Die Reiter haben eigene Titelleisten (Statusleiste), die Navigationsleiste den unteren Rand.
        null -> Scaffold(
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            bottomBar = {
                NavigationBar {
                    Tab.entries.forEach { item ->
                        NavigationBarItem(
                            selected = tab == item,
                            onClick = { tab = item },
                            icon = { Icon(item.icon, contentDescription = null) },
                            label = { Text(item.label) },
                        )
                    }
                }
            },
        ) { padding ->
            val modifier = Modifier.padding(padding)
            when (tab) {
                Tab.TRAINING -> TrainingScreen(viewModel, data, modifier, open = ::open)
                Tab.NUTRITION -> NutritionScreen(viewModel, data, modifier, open = ::open)
                Tab.HISTORY -> HistoryScreen(data, modifier, open = ::open)
                Tab.ROUTINES -> RoutinesScreen(viewModel, data, modifier, open = ::open, startTraining = { tab = Tab.TRAINING })
                Tab.EXERCISES -> ExercisesScreen(viewModel, data, modifier, open = ::open)
            }
        }
    }
}

/** Seitenstapel über Drehungen und Prozessende hinweg merken. */
private val PageStackSaver = androidx.compose.runtime.saveable.listSaver<List<Page>, String>(
    save = { stack ->
        stack.map { page ->
            when (page) {
                is Page.SessionDetail -> "s:${page.id}"
                is Page.ExerciseDetail -> "e:${page.id}"
                is Page.RoutineEditor -> "r:${page.id.orEmpty()}"
                Page.Settings -> "settings"
                Page.NutritionSettings -> "nutrition-settings"
                Page.Recipes -> "recipes"
                Page.Account -> "account"
                Page.Friends -> "friends"
            }
        }
    },
    restore = { saved ->
        saved.mapNotNull { text ->
            when {
                text.startsWith("s:") -> Page.SessionDetail(text.removePrefix("s:"))
                text.startsWith("e:") -> Page.ExerciseDetail(text.removePrefix("e:"))
                text.startsWith("r:") -> Page.RoutineEditor(text.removePrefix("r:").ifEmpty { null })
                text == "settings" -> Page.Settings
                text == "nutrition-settings" -> Page.NutritionSettings
                text == "recipes" -> Page.Recipes
                text == "account" -> Page.Account
                text == "friends" -> Page.Friends
                else -> null
            }
        }
    },
)
