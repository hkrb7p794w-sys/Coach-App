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
    /** Sitzung des eigenen Kontos (`s1.…`, siehe worker/src/accounts.ts); hat Vorrang vor dem Gast-Token. */
    val session: String get() = prefs.getString("session", "").orEmpty()
    val isConfigured: Boolean get() = normalized(url) != null && (token.isNotEmpty() || session.isNotEmpty())

    /** Token für Anfragen: Sitzung, sonst Gast-Token. */
    val bearer: String get() = session.ifEmpty { token }

    fun save(url: String, token: String) {
        val next = normalized(url) ?: url.trim()
        val editor = prefs.edit().putString("url", next)
        val serverChanged = next != this.url
        if (token.isNotBlank()) editor.putString("token", token.trim())
        // Token und Sitzung gehören zu genau einem Server: nie an eine andere Adresse schicken.
        else if (serverChanged) editor.remove("token")
        if (serverChanged) editor.remove("session")
        editor.apply()
    }

    fun saveSession(token: String?) {
        prefs.edit().apply { if (token.isNullOrEmpty()) remove("session") else putString("session", token) }.apply()
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

class WorkerException(message: String, val isNetwork: Boolean = false, val status: Int = 0) : Exception(message)

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
        if (status == 401) throw unauthorized()
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

    /** Abgelehnte Sitzung: abmelden und klar sagen, was zu tun ist. */
    private fun unauthorized(): WorkerException {
        if (access.session.isNotEmpty()) {
            access.saveSession(null)
            onSessionRejected()
            return WorkerException("Deine Anmeldung gilt nicht mehr. Bitte unter Einstellungen › Konto neu anmelden.", status = 401)
        }
        return WorkerException("Zugang ungültig oder entzogen – bitte neuen Link anfordern.", status = 401)
    }

    /** Wird aufgerufen, wenn der Worker die Sitzung ablehnt (Konto zeigt dann „abgemeldet“). */
    var onSessionRejected: () -> Unit = {}

    enum class Auth { PREFERRED, GUEST, SESSION, NONE }

    /** Konto-Anfrage (`/v1/account/…`); liefert die JSON-Antwort oder wirft mit der Meldung des Workers. */
    suspend fun account(method: String, path: String, body: JsonObject? = null, auth: Auth = Auth.SESSION): JsonObject {
        if (WorkerAccess.normalized(access.url) == null) throw WorkerException("Bitte zuerst die Server-Adresse eintragen.")
        val token = when (auth) {
            Auth.PREFERRED -> access.bearer
            Auth.GUEST -> access.token
            Auth.SESSION -> access.session
            Auth.NONE -> ""
        }
        if (auth != Auth.NONE && token.isEmpty()) throw WorkerException("Bitte zuerst anmelden.")
        val (status, text) = request(method, "${access.url}/v1/account/$path", body?.toString(), auth = token.isNotEmpty(), timeoutMs = 20_000, token = token)
        val json = runCatching { GymJson.parseToJsonElement(text) }.getOrNull() as? JsonObject
        if (status == 401 && auth == Auth.SESSION) throw unauthorized()
        if (status !in 200..299) {
            throw WorkerException((json?.get("error") as? JsonPrimitive)?.content ?: "Fehler $status", status = status)
        }
        return json ?: JsonObject(emptyMap())
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

    private suspend fun request(
        method: String,
        url: String,
        body: String?,
        auth: Boolean,
        timeoutMs: Int,
        token: String = access.bearer,
    ): Pair<Int, String> =
        withContext(Dispatchers.IO) {
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.requestMethod = method
                connection.connectTimeout = 15_000
                connection.readTimeout = timeoutMs
                connection.setRequestProperty("User-Agent", OpenFoodFacts.USER_AGENT)
                connection.setRequestProperty("Accept", "application/json")
                if (auth) connection.setRequestProperty("Authorization", "Bearer $token")
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
