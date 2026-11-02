package io.github.hkrb7p794w.gym

import io.github.hkrb7p794w.gym.core.Progression
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val GERMAN = Locale.GERMANY
private val DATE = DateTimeFormatter.ofPattern("EEE, d. MMM yyyy", GERMAN)
private val SHORT_DATE = DateTimeFormatter.ofPattern("d. MMM", GERMAN)
private val TIME = DateTimeFormatter.ofPattern("HH:mm", GERMAN)

fun formatDate(millis: Long): String = DATE.format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

fun formatShortDate(millis: Long): String = SHORT_DATE.format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

fun formatTime(millis: Long): String = TIME.format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

/** „1:05:09“ bzw. „12:09“. */
fun formatDuration(millis: Long): String {
    val total = (millis / 1000).coerceAtLeast(0)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
}

fun formatKg(value: Double): String = Progression.kg(value)

/** „62,5“ oder „62.5“ → 62.5; leer → 0; sonst `null`. */
fun parseDecimal(text: String): Double? {
    val cleaned = text.trim().replace(',', '.')
    if (cleaned.isEmpty()) return 0.0
    return cleaned.toDoubleOrNull()?.takeIf { it >= 0 && it < 2000 }
}

fun formatVolume(kg: Double): String =
    if (kg >= 1000) "%.1f t".format(GERMAN, kg / 1000) else "${formatKg(kg)} kg"
