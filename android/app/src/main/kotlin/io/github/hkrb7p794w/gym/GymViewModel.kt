package io.github.hkrb7p794w.gym

import android.app.Application
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Backup
import io.github.hkrb7p794w.gym.core.Exercise
import io.github.hkrb7p794w.gym.core.Library
import io.github.hkrb7p794w.gym.core.Workouts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Hält den gesamten Stand (eine JSON-Datei im App-Speicher) und speichert nach jeder Änderung. Kein Netz, kein Konto:
 * Die Daten bleiben auf dem Handy (plus optional Android Auto Backup und eigene Sicherungsdatei).
 */
class GymViewModel(application: Application) : AndroidViewModel(application) {
    private val file = File(application.filesDir, "gym.json")
    private val saveLock = Mutex()

    /** Übungsbibliothek aus CoachCore (assets/exercises.json). */
    val library: List<Exercise> = application.assets.open("exercises.json").bufferedReader().use { Library.parse(it.readText()) }

    /** Datei war vorhanden, aber nicht lesbar: nichts überschreiben, sondern warnen (die Datei bleibt liegen). */
    var loadFailed = false
        private set

    // Nach `loadFailed` deklariert: Kotlin initialisiert in Reihenfolge, `load()` setzt das Feld.
    private val _data = MutableStateFlow(load())
    val data: StateFlow<AppData> = _data.asStateFlow()

    private val _rest = MutableStateFlow<Int?>(null)
    /** Verbleibende Pause in Sekunden, `null` = keine Pause. */
    val rest: StateFlow<Int?> = _rest.asStateFlow()
    private var restJob: Job? = null

    val allExercises: List<Exercise> get() = library + _data.value.customExercises

    /** Ernährung: BLS, KI über den Worker, Barcodes (siehe NutritionModel.kt). */
    val nutrition = NutritionModel(application, viewModelScope, ::update) { _data.value }
    val account = AccountModel(application, viewModelScope, nutrition.access, nutrition.client)
    val social = SocialModel(viewModelScope, nutrition.client, account)

    /** Einladungslink `ironludi://account?…` (Server und Code), bis der Kontobildschirm ihn übernimmt. */
    val pendingInvite = kotlinx.coroutines.flow.MutableStateFlow<Pair<String, String>?>(null)

    fun exercise(id: String): Exercise? = Workouts.find(id, library, _data.value.customExercises)

    private fun load(): AppData {
        if (!file.exists()) return AppData()
        val decoded = Backup.decode(file.readText())
        if (decoded == null) {
            loadFailed = true
            // Unlesbare Datei aufheben statt überschreiben.
            file.copyTo(File(file.parentFile, "gym-unlesbar-${System.currentTimeMillis()}.json"), overwrite = false)
            return AppData()
        }
        return decoded
    }

    fun update(change: (AppData) -> AppData) {
        val previous = _data.value
        val next = change(previous)
        if (next == previous) return
        _data.value = next
        viewModelScope.launch { save(next) }
        // Erinnerungen hängen an Einstellungen und Einträgen (eingetragene Mahlzeiten lösen keine aus).
        if (next.reminders != previous.reminders || next.meals.size != previous.meals.size) {
            ReminderScheduler.schedule(getApplication(), next)
        }
    }

    /** Atomar schreiben: erst Zwischendatei, dann umbenennen – ein Absturz beim Speichern zerstört nichts. */
    private suspend fun save(data: AppData) = withContext(Dispatchers.IO) {
        saveLock.withLock {
            if (data != _data.value) return@withLock
            val temp = File(file.parentFile, "gym.json.tmp")
            temp.writeText(Backup.encode(data))
            if (!temp.renameTo(file)) {
                file.delete()
                temp.renameTo(file)
            }
        }
    }

    fun startRest(seconds: Int) {
        restJob?.cancel()
        if (seconds <= 0) {
            _rest.value = null
            return
        }
        restJob = viewModelScope.launch {
            var left = seconds
            while (left > 0) {
                _rest.value = left
                delay(1_000)
                left = (_rest.value ?: 0) - 1
            }
            _rest.value = null
            vibrate()
        }
    }

    fun extendRest(seconds: Int) {
        _rest.value?.let { _rest.value = (it + seconds).coerceAtLeast(1) }
    }

    fun stopRest() {
        restJob?.cancel()
        _rest.value = null
    }

    private fun vibrate() {
        val context = getApplication<Application>()
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
        vibrator?.vibrate(VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    /** Sicherung in eine vom Nutzer gewählte Datei schreiben (Speicherzugriff-Dialog). */
    fun exportBackup(uri: Uri, done: (Boolean) -> Unit) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    getApplication<Application>().contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write(Backup.encode(_data.value).toByteArray())
                    } != null
                }.getOrDefault(false)
            }
            done(ok)
        }
    }

    /** Sicherung einlesen und zusammenführen (nichts geht verloren); Ergebnis: Zahl neuer Trainings oder `null`. */
    fun importBackup(uri: Uri, done: (Int?) -> Unit) {
        viewModelScope.launch {
            val imported = withContext(Dispatchers.IO) {
                runCatching {
                    getApplication<Application>().contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }
                }.getOrNull()?.let(Backup::decode)
            }
            if (imported == null) {
                done(null)
                return@launch
            }
            val before = _data.value.sessions.size
            update { Backup.merge(it, imported) }
            done(_data.value.sessions.size - before)
        }
    }
}
