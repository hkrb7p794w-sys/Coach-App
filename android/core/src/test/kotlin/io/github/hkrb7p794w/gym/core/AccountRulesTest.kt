package io.github.hkrb7p794w.gym.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Gleiche Fälle wie `AccountRulesTests` in CoachCore und `accounts.test.ts` im Worker.
class AccountRulesTest {
    @Test
    fun usernames() {
        assertNull(AccountRules.usernameProblem("lena"))
        assertNull(AccountRules.usernameProblem(" Max_Mustermann.1 "))
        assertNotNull(AccountRules.usernameProblem("ab"))
        assertNotNull(AccountRules.usernameProblem(".lena"))
        assertNotNull(AccountRules.usernameProblem("lena müller"))
        assertNotNull(AccountRules.usernameProblem("jörg"))
        assertEquals("Dieser Benutzername ist reserviert.", AccountRules.usernameProblem("admin"))
    }

    @Test
    fun passwords() {
        assertNull(AccountRules.passwordProblem("Sommer-Lauf-2026", "lena"))
        assertTrue(AccountRules.passwordProblem("kurz", "lena")!!.contains("mindestens 10"))
        assertTrue(AccountRules.passwordProblem("LENA-passwort-1", "lena")!!.contains("Benutzernamen"))
        assertEquals("Das Passwort ist zu einfach.", AccountRules.passwordProblem("aaaaaaaaaaaa", "lena"))
    }

    @Test
    fun namesCodesAndInvites() {
        assertEquals("Lena Sommer", AccountRules.displayName("  Lena   Sommer "))
        assertEquals("", AccountRules.displayName("   "))
        assertNull(AccountRules.displayName("x".repeat(41)))
        assertEquals("ABCDEFGHJK", AccountRules.normalizeCode("abcd-efgh jk"))
        assertEquals(
            "https://coach-ai.example.workers.dev" to "ABCDEFGHJK",
            AccountRules.parseInvite("ironludi", "account", "https://coach-ai.example.workers.dev/", "abcdefghjk"),
        )
        assertNull(AccountRules.parseInvite("ironludi", "account", "http://x.dev", "ABCDEFGHJK"))
        assertNull(AccountRules.parseInvite("ironludi", "connect", "https://x.dev", "ABCDEFGHJK"))
        assertNull(AccountRules.parseInvite("ironludi", "account", "https://x.dev", "ABC"))
    }
}
