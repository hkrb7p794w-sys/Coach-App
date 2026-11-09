package io.github.hkrb7p794w.gym.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Audit AND-14: `GymJson` ignoriert unbekannte Felder („spätere Versionen bleiben lesbar“, Gym.kt:10), aber ein
 * unbekannter Enum-Wert (z. B. ein neuer Tagestyp oder eine neue Mahlzeitkategorie einer neueren App-Version) macht
 * die ganze Datei unlesbar: `Backup.decode` liefert `null` (Gym.kt:191–198). Beim Start meldet die App dann
 * „Gespeicherte Daten nicht lesbar“ und arbeitet mit leeren Daten weiter (GymViewModel.kt:59–68); beim Einspielen
 * „Keine gültige Sicherung“. Ein einzelner unbekannter Wert darf nicht alle Trainings unlesbar machen.
 */
class AuditBackupTest {
    @Test
    fun unknownEnumValueDoesNotDiscardWholeBackup() {
        val json = """{"version":1,"sessions":[{"id":"a","startedAt":1,"endedAt":2}],"dayTypes":{"2026-11-02":"extrem"}}"""
        val data = assertNotNull(Backup.decode(json), "eine unbekannte Tagestyp-Angabe verwirft die ganze Sicherung")
        assertEquals(1, data.sessions.size)
    }
}
