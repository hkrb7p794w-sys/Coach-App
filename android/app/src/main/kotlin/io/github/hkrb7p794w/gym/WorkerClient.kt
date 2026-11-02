package io.github.hkrb7p794w.gym

import android.content.Context
import android.net.Uri
import io.github.hkrb7p794w.gym.core.GymJson
import io.github.hkrb7p794w.gym.core.OpenFoodFacts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Zugang zum Cloudflare Worker des Bruders/der Schwester (KI für Mahlzeiten). KI-Keys liegen nur im Worker; die App
 * kennt nur Adresse und Gast-Token. Gespeichert in den privaten App-Einstellungen, ausgenommen von Android-Backups
 * (`res/xml/backup_rules.xml`).
 */
class WorkerAccess(context: Context) {
    private val prefs = context.getSharedPreferences("worker", Context.MODE_PRIVATE)

    val url: String get() = prefs.getString("url", "").orEmpty()
    val token: String get() = prefs.getString("token", "").orEmpty()
    val isConfigured: Boolean get() = normalized(url) != null && token.isNotEmpty()

    fun save(url: String, token: String) {
        val editor = prefs.edit().putString("url", normalized(url) ?: url.trim())
        if (token.isNotBlank()) editor.putString("token", token.trim())
        editor.apply()
    }

    fun clear() = prefs.edit().clear().apply()

    companion object {
        /** Nur https, ohne Schrägstrich am Ende. */
        fun normalized(text: String): String? {
            val trimmed = text.trim().trimEnd('/')
            val uri = runCatching { Uri.parse(trimmed) }.getOrNull() ?: return null
            return if (uri.scheme == "https" && !uri.host.isNullOrEmpty()) trimmed else null
        }

        /** Verbindungslink `ironludi://connect?worker=…&token=…` (von der Download-Seite). */
        fun fromLink(uri: Uri): Pair<String, String>? {
            if (uri.scheme != "ironludi" || uri.host != "connect") return null
            val worker = uri.getQueryParameter("worker")?.let(::normalized) ?: return null
            val token = uri.getQueryParameter("token")?.takeIf { it.isNotBlank() } ?: return null
            return worker to token
        }
    }
}

class WorkerException(message: String, val isNetwork: Boolean = false) : Exception(message)

/** HTTP ohne Zusatzbibliothek (HttpURLConnection), immer im IO-Thread. */
class WorkerClient(private val access: WorkerAccess) {
    data class Image(val mimeType: String, val base64: String)

    /** KI-Aufgabe des Workers (`POST /v1/ai/generate`); liefert `output`. */
    suspend fun run(task: String, input: JsonObject, images: List<Image> = emptyList()): JsonElement {
        if (!access.isConfigured) throw WorkerException("KI ist nicht verbunden (Einstellungen › KI-Zugang).")
        val body = buildJsonObject {
            put("task", task)
            put("input", input)
            put("provider", "auto")
            if (images.isNotEmpty()) {
                put(
                    "images",
                    buildJsonArray {
                        images.forEach { image ->
                            add(buildJsonObject {
                                put("mimeType", image.mimeType)
                                put("data", image.base64)
                            })
                        }
                    },
                )
            }
        }
        val (status, text) = request("POST", "${access.url}/v1/ai/generate", body.toString(), auth = true, timeoutMs = 120_000)
        val json = runCatching { GymJson.parseToJsonElement(text) }.getOrNull() as? JsonObject
        if (status == 401) throw WorkerException("Zugang ungültig oder entzogen – bitte neuen Link anfordern.")
        if (status !in 200..299) {
            val message = (json?.get("error") as? JsonPrimitive)?.content ?: "Fehler $status"
            throw WorkerException(message)
        }
        return json?.get("output") ?: throw WorkerException("Leere Antwort vom Worker")
    }

    /** Zugang prüfen ohne KI-Kontingent: Einladen dürfen Gäste nicht (403), ein falsches Token ergibt 401. */
    suspend fun check(): String {
        if (!access.isConfigured) return "Nicht verbunden"
        return try {
            val (status, _) = request("POST", "${access.url}/v1/invite", "", auth = true, timeoutMs = 15_000)
            when (status) {
                200, 403 -> "Verbunden"
                401 -> "Zugang ungültig oder entzogen"
                else -> "Worker antwortet mit $status"
            }
        } catch (error: WorkerException) {
            error.message ?: "Keine Verbindung"
        }
    }

    /** Mahlzeit teilen (`POST /v1/share/meal`); liefert den Code. */
    suspend fun share(body: JsonObject): String {
        if (!access.isConfigured) throw WorkerException("Zum Teilen muss der KI-Zugang verbunden sein.")
        val (status, text) = request("POST", "${access.url}/v1/share/meal", body.toString(), auth = true, timeoutMs = 20_000)
        val json = runCatching { GymJson.parseToJsonElement(text) }.getOrNull() as? JsonObject
        if (status !in 200..299) throw WorkerException((json?.get("error") as? JsonPrimitive)?.content ?: "Teilen fehlgeschlagen ($status)")
        return (json?.get("code") as? JsonPrimitive)?.content ?: throw WorkerException("Kein Code erhalten")
    }

    /** Geteilte Mahlzeit holen (`GET /v1/share/meal/<code>`). */
    suspend fun shared(code: String): JsonElement {
        if (!access.isConfigured) throw WorkerException("Zum Öffnen muss der KI-Zugang verbunden sein.")
        val (status, text) = request("GET", "${access.url}/v1/share/meal/$code", null, auth = true, timeoutMs = 20_000)
        if (status == 404) throw WorkerException("Code unbekannt oder abgelaufen (Mahlzeiten gelten 7 Tage).")
        if (status !in 200..299) throw WorkerException("Fehler $status")
        return GymJson.parseToJsonElement(text)
    }

    /** Link zur Weiterleitungsseite des Workers (`/m/<code>`). */
    fun shareLink(code: String): String = "${access.url}/m/$code"

    /** Produkt bei Open Food Facts (öffentlich, ohne Token; eigener User-Agent laut OFF-Regeln). */
    suspend fun openFoodFacts(barcode: String): JsonElement? {
        val (status, text) = request("GET", OpenFoodFacts.url(barcode), null, auth = false, timeoutMs = 15_000)
        if (status == 404) return null
        if (status !in 200..299) throw WorkerException("Open Food Facts antwortet mit $status")
        return runCatching { GymJson.parseToJsonElement(text) }.getOrNull()
    }

    private suspend fun request(method: String, url: String, body: String?, auth: Boolean, timeoutMs: Int): Pair<Int, String> =
        withContext(Dispatchers.IO) {
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.requestMethod = method
                connection.connectTimeout = 15_000
                connection.readTimeout = timeoutMs
                connection.setRequestProperty("User-Agent", OpenFoodFacts.USER_AGENT)
                connection.setRequestProperty("Accept", "application/json")
                if (auth) connection.setRequestProperty("Authorization", "Bearer ${access.token}")
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    connection.outputStream.use { it.write(body.toByteArray()) }
                }
                val status = connection.responseCode
                val stream = if (status in 200..399) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                connection.disconnect()
                status to text
            } catch (error: IOException) {
                throw WorkerException("Keine Verbindung: ${error.message ?: "Netzwerkfehler"}", isNetwork = true)
            }
        }
}
