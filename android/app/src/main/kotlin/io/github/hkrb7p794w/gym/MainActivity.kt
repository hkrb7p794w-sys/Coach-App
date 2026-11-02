package io.github.hkrb7p794w.gym

import android.content.Intent
import android.os.Build
import android.widget.Toast
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

class MainActivity : ComponentActivity() {
    private val viewModel: GymViewModel by viewModels()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLink(intent)
    }

    /** `ironludi://connect?worker=…&token=…` von der Download-Seite: KI-Zugang übernehmen. */
    private fun handleLink(intent: Intent?) {
        val uri = intent?.data ?: return
        val (worker, token) = WorkerAccess.fromLink(uri) ?: return
        viewModel.nutrition.connect(worker, token)
        Toast.makeText(this, "KI-Zugang verbunden", Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleLink(intent)
        setContent {
            GymTheme {
                GymApp(viewModel)
            }
        }
    }
}

/** Material 3, folgt Hell/Dunkel des Systems; ab Android 12 mit den Farben des Hintergrundbilds. */
@Composable
fun GymTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val scheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme(primary = Color(0xFF7FD6BF), secondary = Color(0xFFB2CCC3))
        else -> lightColorScheme(primary = Color(0xFF1F6F5C), secondary = Color(0xFF4B635B))
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
