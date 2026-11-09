@file:OptIn(ExperimentalMaterial3Api::class)

package io.github.hkrb7p794w.gym

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import io.github.hkrb7p794w.gym.core.AccountRules

/** Konto: anmelden, registrieren, Passwort vergessen bzw. verwalten (Einladungen, Geräte, Passwort, Löschen). */
@Composable
fun AccountScreen(viewModel: GymViewModel, invite: Pair<String, String>?, onBack: () -> Unit) {
    val model = viewModel.account
    val info by model.info.collectAsState()
    val recovery by model.recoveryCode.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Konto") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück") } },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).padding(16.dp).verticalScroll(rememberScrollState()).imePadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (info != null && model.isSignedIn) AccountManage(model) else AccountAuth(model, invite)
        }
    }
    recovery?.let { code -> RecoveryCodeDialog(code, onDone = model::dismissRecoveryCode) }
}

private enum class AuthMode(val label: String) { LOGIN("Anmelden"), REGISTER("Registrieren"), RECOVER("Vergessen") }

@Composable
private fun AccountAuth(model: AccountModel, invite: Pair<String, String>?) {
    val busy by model.busy.collectAsState()
    val error by model.error.collectAsState()
    val notice by model.notice.collectAsState()
    var mode by rememberSaveable { mutableStateOf(if (invite != null) AuthMode.REGISTER else AuthMode.LOGIN) }
    var server by rememberSaveable { mutableStateOf(invite?.first ?: model.server) }
    var username by rememberSaveable { mutableStateOf("") }
    var displayName by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var repeated by rememberSaveable { mutableStateOf("") }
    var inviteCode by rememberSaveable { mutableStateOf(invite?.second.orEmpty()) }
    var recoveryInput by rememberSaveable { mutableStateOf("") }
    val sameServer = WorkerAccess.normalized(server) == model.server && model.server.isNotEmpty()
    val needsInvite = mode == AuthMode.REGISTER && (!model.hasGuestToken || !sameServer)

    notice?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    if (invite != null) {
        Text("Du wurdest eingeladen. Lege dein eigenes Konto an – nur du kennst dein Passwort.", style = MaterialTheme.typography.bodyMedium)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        AuthMode.entries.forEach { option ->
            FilterChip(selected = mode == option, onClick = { mode = option }, label = { Text(option.label) }, enabled = invite == null)
        }
    }
    if (!sameServer || model.server.isEmpty()) {
        OutlinedTextField(server, { server = it.trim() }, label = { Text("Server (https://…)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
    OutlinedTextField(
        username,
        { username = it },
        label = { Text("Benutzername") },
        singleLine = true,
        supportingText = hintText(if (mode != AuthMode.LOGIN && username.isNotEmpty()) AccountRules.usernameProblem(username) else null),
        modifier = Modifier.fillMaxWidth(),
    )
    if (mode == AuthMode.REGISTER) {
        OutlinedTextField(displayName, { displayName = it }, label = { Text("Anzeigename (z. B. Vorname)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
    if (mode == AuthMode.RECOVER) {
        OutlinedTextField(recoveryInput, { recoveryInput = it }, label = { Text("Wiederherstellungscode") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
    val passwordHint = when {
        mode == AuthMode.LOGIN || password.isEmpty() -> null
        else -> AccountRules.passwordProblem(password, username)
            ?: if (repeated.isNotEmpty() && repeated != password) "Die Passwörter stimmen nicht überein." else null
    }
    PasswordField(password, { password = it }, if (mode == AuthMode.RECOVER) "Neues Passwort" else "Passwort", passwordHint)
    if (mode != AuthMode.LOGIN) PasswordField(repeated, { repeated = it }, "Passwort wiederholen", null)
    if (needsInvite) {
        OutlinedTextField(inviteCode, { inviteCode = it }, label = { Text("Einladungscode") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
    when (mode) {
        AuthMode.REGISTER -> Text("Freunde finden dich über den Benutzernamen. Passwort: mindestens 10 Zeichen.", style = MaterialTheme.typography.bodySmall)
        AuthMode.RECOVER -> Text(
            "Den Wiederherstellungscode hast du bei der Registrierung erhalten. Ohne Code kann die Person, die den Server betreibt, dir einen neuen ausstellen.",
            style = MaterialTheme.typography.bodySmall,
        )
        AuthMode.LOGIN -> Unit
    }
    val ready = !busy && WorkerAccess.normalized(server) != null && username.isNotBlank() && password.isNotEmpty() && when (mode) {
        AuthMode.LOGIN -> true
        AuthMode.REGISTER -> AccountRules.usernameProblem(username) == null && AccountRules.passwordProblem(password, username) == null &&
            repeated == password && AccountRules.displayName(displayName) != null &&
            (!needsInvite || AccountRules.normalizeCode(inviteCode).length == 10)
        AuthMode.RECOVER -> AccountRules.passwordProblem(password, username) == null && repeated == password &&
            AccountRules.normalizeCode(recoveryInput).length == 16
    }
    Button(
        onClick = {
            when (mode) {
                AuthMode.LOGIN -> model.login(server, username, password)
                AuthMode.REGISTER -> model.register(server, username, displayName, password, if (needsInvite) inviteCode else "")
                AuthMode.RECOVER -> model.recover(server, username, recoveryInput, password)
            }
        },
        enabled = ready,
        modifier = Modifier.fillMaxWidth(),
    ) { Text(if (busy) "Bitte warten …" else when (mode) { AuthMode.LOGIN -> "Anmelden"; AuthMode.REGISTER -> "Konto erstellen"; AuthMode.RECOVER -> "Passwort zurücksetzen" }) }
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    Text(
        "Nur du kennst dein Passwort. Deine Trainings, Mahlzeiten und Körperwerte bleiben auf diesem Handy.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** Hinweis unter einem Eingabefeld (oder keiner). */
private fun hintText(text: String?): (@Composable () -> Unit)? = text?.let { value -> @Composable { Text(value) } }

@Composable
private fun PasswordField(value: String, onChange: (String) -> Unit, label: String, hint: String?) {
    OutlinedTextField(
        value,
        onChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        supportingText = hintText(hint),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun AccountManage(model: AccountModel) {
    val context = LocalContext.current
    val info by model.info.collectAsState()
    val devices by model.devices.collectAsState()
    val invites by model.invites.collectAsState()
    val busy by model.busy.collectAsState()
    val error by model.error.collectAsState()
    var name by rememberSaveable { mutableStateOf(info?.displayName.orEmpty()) }
    var changingPassword by rememberSaveable { mutableStateOf(false) }
    var deleting by rememberSaveable { mutableStateOf(false) }
    var confirmAll by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.refresh() }

    fun share(link: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "Komm zu IronLudi! Mit diesem Link legst du dein Konto an (14 Tage gültig, einmalig): $link")
        }
        context.startActivity(Intent.createChooser(intent, "Einladung teilen"))
    }

    SectionTitle("Profil")
    Text("@${info?.username.orEmpty()}", style = MaterialTheme.typography.titleMedium)
    OutlinedTextField(name, { name = it }, label = { Text("Anzeigename") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    if (name != info?.displayName && AccountRules.displayName(name) != null) {
        OutlinedButton(onClick = { model.updateDisplayName(name) }, enabled = !busy) { Text("Anzeigenamen speichern") }
    }
    Text("Freunde sehen Benutzernamen und Anzeigenamen.", style = MaterialTheme.typography.bodySmall)

    SectionTitle("Freunde und Familie einladen")
    Button(onClick = { model.createInvite(::share) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Neue Einladung teilen") }
    invites.forEach { item ->
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(item.code, fontFamily = FontFamily.Monospace)
                Text("gültig bis ${item.expiresAt.take(10)}", style = MaterialTheme.typography.bodySmall)
            }
            TextButton(onClick = { share(model.inviteLink(item.code)) }) { Text("Teilen") }
            TextButton(onClick = { model.deleteInvite(item.code) }) { Text("Löschen") }
        }
    }
    Text("Jede Einladung gilt einmal und 14 Tage. Höchstens 5 offene Einladungen.", style = MaterialTheme.typography.bodySmall)

    SectionTitle("Angemeldete Geräte")
    devices.forEach { device ->
        Column {
            Text(device.device + if (device.current) " · dieses Gerät" else "")
            Text("zuletzt aktiv ${device.lastUsed.take(10)}", style = MaterialTheme.typography.bodySmall)
        }
    }
    OutlinedButton(onClick = { confirmAll = true }, modifier = Modifier.fillMaxWidth()) { Text("Auf allen Geräten abmelden") }

    SectionTitle("Sicherheit")
    OutlinedButton(onClick = { changingPassword = true }, modifier = Modifier.fillMaxWidth()) { Text("Passwort ändern") }
    OutlinedButton(onClick = { model.logout() }, modifier = Modifier.fillMaxWidth()) { Text("Auf diesem Gerät abmelden") }
    TextButton(onClick = { deleting = true }) { Text("Konto löschen", color = MaterialTheme.colorScheme.error) }
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

    if (confirmAll) {
        AlertDialog(
            onDismissRequest = { confirmAll = false },
            title = { Text("Auf allen Geräten abmelden?") },
            text = { Text("Du musst dich danach auf jedem Gerät neu anmelden.") },
            confirmButton = { TextButton(onClick = { confirmAll = false; model.logout(everywhere = true) }) { Text("Überall abmelden") } },
            dismissButton = { TextButton(onClick = { confirmAll = false }) { Text("Abbrechen") } },
        )
    }
    if (changingPassword) ChangePasswordDialog(model, info?.username.orEmpty()) { changingPassword = false }
    if (deleting) {
        var password by rememberSaveable { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { deleting = false },
            title = { Text("Konto löschen?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Konto, Anmeldungen und offene Einladungen werden auf dem Server gelöscht. Deine Daten auf diesem Handy bleiben.")
                    PasswordField(password, { password = it }, "Passwort", null)
                }
            },
            confirmButton = {
                TextButton(onClick = { deleting = false; model.delete(password) }, enabled = password.isNotEmpty()) {
                    Text("Endgültig löschen", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { deleting = false }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun ChangePasswordDialog(model: AccountModel, username: String, onClose: () -> Unit) {
    var old by rememberSaveable { mutableStateOf("") }
    var new by rememberSaveable { mutableStateOf("") }
    var repeated by rememberSaveable { mutableStateOf("") }
    val hint = if (new.isEmpty()) null else AccountRules.passwordProblem(new, username)
        ?: if (repeated.isNotEmpty() && repeated != new) "Die Passwörter stimmen nicht überein." else null
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Passwort ändern") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PasswordField(old, { old = it }, "Bisheriges Passwort", null)
                PasswordField(new, { new = it }, "Neues Passwort", hint)
                PasswordField(repeated, { repeated = it }, "Neues Passwort wiederholen", null)
                Text("Andere Geräte werden danach abgemeldet.", style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = {
            TextButton(onClick = { model.changePassword(old, new, onClose) }, enabled = old.isNotEmpty() && new.isNotEmpty() && hint == null && repeated == new) {
                Text("Ändern")
            }
        },
        dismissButton = { TextButton(onClick = onClose) { Text("Abbrechen") } },
    )
}

@Composable
private fun RecoveryCodeDialog(code: String, onDone: () -> Unit) {
    val context = LocalContext.current
    var saved by rememberSaveable { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = {},
        title = { Text("Dein Wiederherstellungscode") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(code, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace)
                Text(
                    "Mit diesem Code setzt du dein Passwort zurück, falls du es vergisst. Er wird nur jetzt angezeigt. Bewahre ihn sicher auf, " +
                        "z. B. im Passwort-Manager, und gib ihn niemandem.",
                    style = MaterialTheme.typography.bodySmall,
                )
                TextButton(onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("Wiederherstellungscode", code))
                }) { Text("Kopieren") }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = saved, onCheckedChange = { saved = it })
                    Text("Ich habe den Code sicher aufbewahrt")
                }
            }
        },
        confirmButton = { TextButton(onClick = onDone, enabled = saved) { Text("Fertig") } },
    )
}
