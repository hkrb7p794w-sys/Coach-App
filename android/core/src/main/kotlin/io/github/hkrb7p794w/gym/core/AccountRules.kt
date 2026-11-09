package io.github.hkrb7p794w.gym.core

/**
 * Regeln für Konten, gleich wie im Worker (`worker/src/accounts.ts`) und in CoachCore (`AccountRules`), damit die App
 * Fehler schon beim Tippen zeigt. Entscheidend bleibt der Worker.
 */
object AccountRules {
    const val MIN_PASSWORD = 10
    const val MAX_PASSWORD = 128
    private val USERNAME = Regex("^[a-z0-9][a-z0-9_.]{2,19}$")
    private val RESERVED = setOf("admin", "administrator", "coach", "ironludi", "support", "system", "root", "owner")

    fun normalizeUsername(text: String): String = text.trim().lowercase()

    /** `null`, wenn der Benutzername passt; sonst der Hinweis für die Anzeige. */
    fun usernameProblem(raw: String): String? {
        val username = normalizeUsername(raw)
        if (!USERNAME.matches(username)) {
            return "Benutzername: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich, am Anfang ein Buchstabe oder eine Ziffer."
        }
        return if (username in RESERVED) "Dieser Benutzername ist reserviert." else null
    }

    fun passwordProblem(password: String, username: String): String? {
        if (password.length < MIN_PASSWORD) return "Das Passwort braucht mindestens 10 Zeichen."
        if (password.length > MAX_PASSWORD) return "Das Passwort darf höchstens 128 Zeichen haben."
        val name = normalizeUsername(username)
        if (name.isNotEmpty() && password.lowercase().contains(name)) return "Das Passwort darf den Benutzernamen nicht enthalten."
        if (password.toSet().size < 4) return "Das Passwort ist zu einfach."
        return null
    }

    /** Anzeigename: 1–40 Zeichen, Leerzeichen zusammengefasst; leer = Benutzername; `null` = zu lang. */
    fun displayName(raw: String): String? {
        val collapsed = raw.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        return if (collapsed.length <= 40) collapsed else null
    }

    /** Einladungs- bzw. Wiederherstellungscode vereinheitlichen. */
    fun normalizeCode(text: String): String = text.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' }

    /** Einladung aus `ironludi://account?worker=…&invite=…` (Einladungsseite des Workers): Server und Code. */
    fun parseInvite(scheme: String?, host: String?, worker: String?, invite: String?): Pair<String, String>? {
        if (scheme != "ironludi" || host != "account") return null
        val server = worker?.trim()?.trimEnd('/')?.takeIf { it.startsWith("https://") && it.length > 8 } ?: return null
        val code = normalizeCode(invite.orEmpty()).takeIf { it.length == 10 } ?: return null
        return server to code
    }
}
