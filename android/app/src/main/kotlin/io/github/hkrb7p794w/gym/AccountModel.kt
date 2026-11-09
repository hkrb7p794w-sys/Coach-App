package io.github.hkrb7p794w.gym

import android.app.Application
import android.content.Context
import android.os.Build
import io.github.hkrb7p794w.gym.core.AccountRules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

data class AccountInfo(val id: String, val username: String, val displayName: String, val isAdmin: Boolean)
data class AccountDevice(val device: String, val lastUsed: String, val current: Boolean)
data class OpenInvite(val code: String, val expiresAt: String)

/**
 * Eigenes Konto am Worker (`worker/src/accounts.ts`): Registrieren mit Einladung, Anmelden, Sitzungen. Das
 * Sitzungs-Token liegt in den privaten App-Einstellungen (ausgenommen von Android-Backups); Gesundheitsdaten gehen
 * dabei nicht an den Worker.
 */
class AccountModel(application: Application, private val scope: CoroutineScope, private val access: WorkerAccess, private val client: WorkerClient) {
    private val prefs = application.getSharedPreferences("account", Context.MODE_PRIVATE)

    private val _info = MutableStateFlow(loadInfo())
    val info: StateFlow<AccountInfo?> = _info.asStateFlow()
    private val _devices = MutableStateFlow<List<AccountDevice>>(emptyList())
    val devices: StateFlow<List<AccountDevice>> = _devices.asStateFlow()
    private val _invites = MutableStateFlow<List<OpenInvite>>(emptyList())
    val invites: StateFlow<List<OpenInvite>> = _invites.asStateFlow()
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()
    /** Wiederherstellungscode nach Registrierung oder Zurücksetzen – nur einmal anzeigen. */
    private val _recoveryCode = MutableStateFlow<String?>(null)
    val recoveryCode: StateFlow<String?> = _recoveryCode.asStateFlow()

    init {
        client.onSessionRejected = {
            if (_info.value != null) {
                clearLocal()
                _notice.value = "Du wurdest abgemeldet (Passwort geändert, auf einem anderen Gerät abgemeldet oder lange nicht genutzt)."
            }
        }
    }

    val isSignedIn: Boolean get() = _info.value != null && access.session.isNotEmpty()
    val hasGuestToken: Boolean get() = access.token.isNotEmpty()
    val server: String get() = access.url

    private val device = "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})".trim()

    private fun loadInfo(): AccountInfo? {
        if (access.session.isEmpty()) return null
        val id = prefs.getString("id", null) ?: return null
        return AccountInfo(
            id,
            prefs.getString("username", "").orEmpty(),
            prefs.getString("displayName", "").orEmpty(),
            prefs.getBoolean("isAdmin", false),
        )
    }

    private fun storeInfo(info: AccountInfo) {
        prefs.edit().putString("id", info.id).putString("username", info.username)
            .putString("displayName", info.displayName).putBoolean("isAdmin", info.isAdmin).apply()
        _info.value = info
    }

    private fun clearLocal() {
        access.saveSession(null)
        prefs.edit().clear().apply()
        _info.value = null
        _devices.value = emptyList()
        _invites.value = emptyList()
    }

    private fun parseAccount(json: JsonObject?): AccountInfo? {
        json ?: return null
        fun text(key: String) = (json[key] as? JsonPrimitive)?.content.orEmpty()
        return AccountInfo(text("id"), text("username"), text("displayName"), (json["isAdmin"] as? JsonPrimitive)?.booleanOrNull ?: false)
    }

    private fun run(block: suspend () -> Unit) {
        if (_busy.value) return
        scope.launch {
            _busy.value = true
            _error.value = null
            try {
                block()
            } catch (cancel: kotlinx.coroutines.CancellationException) {
                throw cancel
            } catch (error: Exception) {
                _error.value = error.message ?: "Unbekannter Fehler"
            } finally {
                _busy.value = false
            }
        }
    }

    private fun useServer(server: String) {
        val normalized = WorkerAccess.normalized(server) ?: throw WorkerException("Die Server-Adresse muss mit https:// beginnen.")
        if (normalized != access.url) access.save(normalized, "")
    }

    private fun signedIn(response: JsonObject) {
        val token = (response["token"] as? JsonPrimitive)?.content ?: throw WorkerException("Keine Sitzung erhalten")
        val info = parseAccount(response["account"] as? JsonObject) ?: throw WorkerException("Kein Konto erhalten")
        access.saveSession(token)
        storeInfo(info)
        _notice.value = null
        _recoveryCode.value = (response["recoveryCode"] as? JsonPrimitive)?.content
    }

    fun register(server: String, username: String, displayName: String, password: String, invite: String) = run {
        useServer(server)
        val body = buildJsonObject {
            put("username", AccountRules.normalizeUsername(username))
            put("displayName", AccountRules.displayName(displayName).orEmpty())
            put("password", password)
            put("invite", AccountRules.normalizeCode(invite))
            put("device", device)
        }
        // Mit Gast-Token geht es ohne Einladungscode (je Gast-Token einmal).
        signedIn(client.account("POST", "register", body, if (access.token.isNotEmpty()) WorkerClient.Auth.GUEST else WorkerClient.Auth.NONE))
    }

    fun login(server: String, username: String, password: String) = run {
        useServer(server)
        val body = buildJsonObject {
            put("username", AccountRules.normalizeUsername(username))
            put("password", password)
            put("device", device)
        }
        signedIn(client.account("POST", "login", body, WorkerClient.Auth.NONE))
    }

    fun recover(server: String, username: String, code: String, newPassword: String) = run {
        useServer(server)
        val body = buildJsonObject {
            put("username", AccountRules.normalizeUsername(username))
            put("recoveryCode", code)
            put("newPassword", newPassword)
            put("device", device)
        }
        signedIn(client.account("POST", "recover", body, WorkerClient.Auth.NONE))
    }

    fun dismissRecoveryCode() {
        _recoveryCode.value = null
    }

    fun refresh() {
        if (!isSignedIn) return
        run {
            val me = client.account("GET", "me")
            parseAccount(me["account"] as? JsonObject)?.let(::storeInfo)
            _devices.value = (me["sessions"] as? JsonArray).orEmpty().mapNotNull { item ->
                val obj = item as? JsonObject ?: return@mapNotNull null
                AccountDevice(
                    (obj["device"] as? JsonPrimitive)?.content.orEmpty(),
                    (obj["lastUsed"] as? JsonPrimitive)?.content.orEmpty(),
                    (obj["current"] as? JsonPrimitive)?.booleanOrNull ?: false,
                )
            }
            loadInvites()
        }
    }

    private suspend fun loadInvites() {
        val list = client.account("GET", "invites")
        _invites.value = (list["invites"] as? JsonArray).orEmpty().mapNotNull { item ->
            val obj = item as? JsonObject ?: return@mapNotNull null
            OpenInvite((obj["code"] as? JsonPrimitive)?.content.orEmpty(), (obj["expiresAt"] as? JsonPrimitive)?.content.orEmpty())
        }
    }

    fun logout(everywhere: Boolean = false) {
        scope.launch {
            runCatching { client.account("POST", "logout", buildJsonObject { put("all", everywhere) }) }
            clearLocal()
        }
    }

    fun changePassword(old: String, new: String, done: () -> Unit) = run {
        client.account("POST", "password", buildJsonObject {
            put("oldPassword", old)
            put("newPassword", new)
        })
        done()
    }

    fun updateDisplayName(name: String) = run {
        val response = client.account("POST", "profile", buildJsonObject { put("displayName", AccountRules.displayName(name).orEmpty()) })
        parseAccount(response["account"] as? JsonObject)?.let(::storeInfo)
    }

    fun delete(password: String) = run {
        client.account("POST", "delete", buildJsonObject { put("password", password) })
        clearLocal()
    }

    /** Neue Einladung; liefert den Link zur Einladungsseite des Workers. */
    fun createInvite(done: (String) -> Unit) = run {
        val invite = client.account("POST", "invites", JsonObject(emptyMap()))
        val code = (invite["code"] as? JsonPrimitive)?.content ?: throw WorkerException("Keine Einladung erhalten")
        loadInvites()
        done(inviteLink(code))
    }

    fun deleteInvite(code: String) = run {
        client.account("DELETE", "invites/$code")
        loadInvites()
    }

    fun inviteLink(code: String): String = "${access.url}/i/$code"
}
