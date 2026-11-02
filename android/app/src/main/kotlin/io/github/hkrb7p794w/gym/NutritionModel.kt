package io.github.hkrb7p794w.gym

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Bls
import io.github.hkrb7p794w.gym.core.Diary
import io.github.hkrb7p794w.gym.core.FoodSearch
import io.github.hkrb7p794w.gym.core.Meal
import io.github.hkrb7p794w.gym.core.MealAnalysis
import io.github.hkrb7p794w.gym.core.MealCategory
import io.github.hkrb7p794w.gym.core.MealItem
import io.github.hkrb7p794w.gym.core.Nutrition
import io.github.hkrb7p794w.gym.core.OpenFoodFacts
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.time.LocalDateTime

/** Entwurf einer Mahlzeit, der im Editor geprüft und dann gespeichert wird. */
data class MealDraft(
    val meal: Meal,
    val isNew: Boolean,
    /** Foto der KI-Analyse (JPEG, Base64), damit Ergänzungen dieselbe Mahlzeit sehen. */
    val photo: String? = null,
    val possiblyMissing: List<String> = emptyList(),
)

/** Zustand und Abläufe der Ernährung; Datenänderungen laufen über `update` des GymViewModel (speichert sofort). */
class NutritionModel(
    private val application: Application,
    private val scope: CoroutineScope,
    private val update: ((AppData) -> AppData) -> Unit,
    private val current: () -> AppData,
) {
    val access = WorkerAccess(application)
    private val client = WorkerClient(access)

    private val _bls = MutableStateFlow<Bls?>(null)
    /** BLS-Tabelle (rund 7.000 Lebensmittel), im Hintergrund geladen. */
    val bls: StateFlow<Bls?> = _bls.asStateFlow()

    private val _draft = MutableStateFlow<MealDraft?>(null)
    val draft: StateFlow<MealDraft?> = _draft.asStateFlow()

    private val _busy = MutableStateFlow<String?>(null)
    /** Läuft gerade etwas (Text für die Anzeige, z. B. „KI wertet aus …“)? */
    val busy: StateFlow<String?> = _busy.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _connection = MutableStateFlow<String?>(null)
    val connection: StateFlow<String?> = _connection.asStateFlow()

    /** Zuletzt per Schnell-Eintrag gespeichert – für „Rückgängig“. */
    private val _lastLogged = MutableStateFlow<Meal?>(null)
    val lastLogged: StateFlow<Meal?> = _lastLogged.asStateFlow()

    init {
        scope.launch(Dispatchers.Default) {
            val text = application.assets.open("bls.tsv").bufferedReader().use { it.readText() }
            _bls.value = Bls.parse(text)
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    fun clearUndo() {
        _lastLogged.value = null
    }

    private fun now(day: LocalDate): Long = Diary.timestamp(day, LocalDateTime.now())

    fun category(): MealCategory {
        val time = LocalDateTime.now()
        return MealCategory.guess(time.hour, time.minute)
    }

    // MARK: Entwurf

    fun newDraft(day: LocalDate, items: List<MealItem> = emptyList(), title: String = "", hint: String = "") {
        val at = now(day)
        _draft.value = MealDraft(Meal(createdAt = at, day = Nutrition.dayKey(at), category = category(), title = title, hint = hint, items = items), isNew = true)
    }

    fun edit(meal: Meal) {
        _draft.value = MealDraft(meal, isNew = false)
    }

    fun changeDraft(change: (Meal) -> Meal) {
        _draft.value = _draft.value?.let { it.copy(meal = change(it.meal)) }
    }

    fun addToDraft(item: MealItem, day: LocalDate) {
        val draft = _draft.value
        if (draft == null) newDraft(day, listOf(item), title = item.name) else changeDraft { it.copy(items = it.items + item) }
    }

    fun saveDraft() {
        val draft = _draft.value ?: return
        update { Diary.save(it, draft.meal) }
        _draft.value = null
    }

    fun deleteDraft() {
        val draft = _draft.value ?: return
        if (!draft.isNew) update { Diary.delete(it, draft.meal.id) }
        _draft.value = null
    }

    fun closeDraft() {
        _draft.value = null
    }

    // MARK: Schnell eintragen

    fun logCopy(title: String, items: List<MealItem>, category: MealCategory, day: LocalDate) {
        var logged: Meal? = null
        update { data ->
            val (next, meal) = Diary.logCopy(data, title, items, category, now(day))
            logged = meal
            next
        }
        _lastLogged.value = logged
    }

    fun undoLast() {
        val meal = _lastLogged.value ?: return
        update { Diary.delete(it, meal.id) }
        _lastLogged.value = null
    }

    fun logWater(milliliters: Double, day: LocalDate) {
        update { Diary.logWater(it, milliliters, now(day)) }
    }

    // MARK: KI

    private fun personalFoods(data: AppData): List<String> =
        FoodSearch.ownFoods(data.meals).sortedByDescending { it.useCount }.take(40).map { it.title }

    /** Mahlzeit per Text und/oder Foto auswerten (Worker-Aufgabe `meal_analyze`, wie auf dem iPhone). */
    fun analyze(text: String, photo: String?, day: LocalDate) {
        scope.launch {
            _busy.value = "KI wertet aus …"
            try {
                val data = current()
                val input = buildJsonObject {
                    put("text", text)
                    put("diet", data.nutrition.diet.serialName())
                    put("personalFoods", buildJsonArray { personalFoods(data).forEach { add(JsonPrimitive(it)) } })
                }
                val images = photo?.let { listOf(WorkerClient.Image("image/jpeg", it)) }.orEmpty()
                val output = client.run("meal_analyze", input, images)
                val analysis = MealAnalysis.parse(output, _bls.value) ?: throw WorkerException("Die KI hat keine Lebensmittel erkannt.")
                val at = now(day)
                _draft.value = MealDraft(
                    meal = Meal(
                        createdAt = at,
                        day = Nutrition.dayKey(at),
                        category = analysis.category ?: category(),
                        title = analysis.title.ifEmpty { text.take(60) },
                        hint = analysis.hint,
                        items = analysis.items.map { preferKnownFood(it, data) },
                    ),
                    isNew = true,
                    photo = photo,
                    possiblyMissing = analysis.possiblyMissing,
                )
            } catch (error: WorkerException) {
                _message.value = error.message
            } finally {
                _busy.value = null
            }
        }
    }

    /** Entwurf ergänzen („noch 1 EL Olivenöl“): nur neue Positionen, Bestehendes bleibt unangetastet. */
    fun amend(text: String) {
        val draft = _draft.value ?: return
        val request = text.trim().takeIf { it.isNotEmpty() } ?: return
        scope.launch {
            _busy.value = "KI ergänzt …"
            try {
                val data = current()
                val input = buildJsonObject {
                    put("text", request)
                    put("diet", data.nutrition.diet.serialName())
                    put(
                        "bestand",
                        buildJsonArray {
                            draft.meal.items.forEach { item ->
                                add(buildJsonObject {
                                    put("name", item.name)
                                    put("menge_g", item.grams)
                                })
                            }
                        },
                    )
                }
                val images = draft.photo?.let { listOf(WorkerClient.Image("image/jpeg", it)) }.orEmpty()
                val (items, hint) = MealAnalysis.amendment(client.run("meal_amend", input, images), _bls.value)
                changeDraft { meal ->
                    meal.copy(items = meal.items + items.map { preferKnownFood(it, data) }, hint = listOf(meal.hint, hint).filter { it.isNotBlank() }.joinToString(" "))
                }
                _draft.value = _draft.value?.copy(possiblyMissing = _draft.value?.possiblyMissing.orEmpty().filterNot { request.contains(it, ignoreCase = true) })
                if (items.isEmpty()) _message.value = hint.ifEmpty { "Nichts Neues erkannt." }
            } catch (error: WorkerException) {
                _message.value = error.message
            } finally {
                _busy.value = null
            }
        }
    }

    /** Eigenes Lebensmittel mit gleichem Namen (z. B. früher per Barcode erfasst) statt KI-Schätzung. */
    private fun preferKnownFood(item: MealItem, data: AppData): MealItem {
        val key = FoodSearch.normalized(item.name)
        val known = data.foods.firstOrNull { FoodSearch.normalized(it.name) == key } ?: return item
        return known.copy(id = item.id, grams = item.grams, amountText = item.amountText)
    }

    // MARK: Barcode

    fun lookupBarcode(barcode: String, day: LocalDate) {
        val code = barcode.filter { it.isDigit() }
        if (!OpenFoodFacts.isValidBarcode(code)) {
            _message.value = "Ungültiger Barcode: $barcode"
            return
        }
        Diary.food(current(), code)?.let {
            addToDraft(it.copy(id = java.util.UUID.randomUUID().toString()), day)
            return
        }
        scope.launch {
            _busy.value = "Suche bei Open Food Facts …"
            try {
                val json = client.openFoodFacts(code)
                val item = json?.let { OpenFoodFacts.item(it, code) }
                if (item == null) {
                    _message.value = "Produkt $code ist bei Open Food Facts nicht bekannt. Tipp: Etikett fotografieren und per KI auswerten oder als eigene Angabe eintragen."
                } else {
                    update { Diary.rememberFoods(it, listOf(item)) }
                    addToDraft(item, day)
                }
            } catch (error: WorkerException) {
                _message.value = error.message
            } finally {
                _busy.value = null
            }
        }
    }

    // MARK: Zugang

    fun connect(url: String, token: String) {
        access.save(url, token)
        checkConnection()
    }

    fun disconnect() {
        access.clear()
        _connection.value = "Nicht verbunden"
    }

    fun checkConnection() {
        scope.launch { _connection.value = client.check() }
    }

    // MARK: Fotos

    /** Foto verkleinern (längste Seite 1280 px, JPEG 80 %) und als Base64 für den Worker. */
    suspend fun photoBase64(uri: Uri): String? = withContext(Dispatchers.IO) {
        runCatching {
            val resolver = application.contentResolver
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1280) sample *= 2
            val bitmap = resolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            } ?: return@runCatching null
            val scale = minOf(1f, 1280f / maxOf(bitmap.width, bitmap.height))
            val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        }.getOrNull()
    }
}

/** Wert wie im Worker/CoachCore („alles“, „vegan“ …). */
private fun io.github.hkrb7p794w.gym.core.Diet.serialName(): String = when (this) {
    io.github.hkrb7p794w.gym.core.Diet.OMNIVORE -> "alles"
    io.github.hkrb7p794w.gym.core.Diet.PESCETARIAN -> "pescetarisch"
    io.github.hkrb7p794w.gym.core.Diet.VEGETARIAN -> "vegetarisch"
    io.github.hkrb7p794w.gym.core.Diet.VEGAN -> "vegan"
}
