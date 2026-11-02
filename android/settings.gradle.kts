// Android-App „IronLudi Gym“: Gym-Logging. `core` ist reine Kotlin-Logik (lokal und auf Linux testbar),
// `app` die Android-Oberfläche (Jetpack Compose). Siehe docs/android.md.
pluginManagement {
    repositories {
        google {
            // Nur Android-/Google-Pakete von Google laden, alles andere von Maven Central.
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
    // Versionen zentral; aufgelöst wird ein Plugin erst, wenn ein Modul es anwendet (`coreOnly` braucht kein AGP).
    plugins {
        id("com.android.application") version "8.11.1"
        id("org.jetbrains.kotlin.android") version "2.2.10"
        id("org.jetbrains.kotlin.jvm") version "2.2.10"
        id("org.jetbrains.kotlin.plugin.compose") version "2.2.10"
        id("org.jetbrains.kotlin.plugin.serialization") version "2.2.10"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            // Nur Android-/Google-Pakete von Google laden, alles andere von Maven Central.
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "IronLudiGym"

include(":core")
// Ohne Android-SDK (z. B. in Claude-Code-Sitzungen) nur die Logik bauen: `-PcoreOnly`.
if (!providers.gradleProperty("coreOnly").isPresent) {
    include(":app")
}
