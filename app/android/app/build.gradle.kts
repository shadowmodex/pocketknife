import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties").let {
    if (it.exists()) it else project.file("key.properties")
}
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.pocketknife.pocketknife"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pocketknife.pocketknife"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyPasswordProp = keystoreProperties.getProperty("keyPassword")
            val keyAliasProp = keystoreProperties.getProperty("keyAlias")
            val storeFileProp = keystoreProperties.getProperty("storeFile")
            val storePasswordProp = keystoreProperties.getProperty("storePassword")

            val keyPasswordEnv = System.getenv("KEY_PASSWORD")
            val keyAliasEnv = System.getenv("KEY_ALIAS")
            val storeFileEnv = System.getenv("KEYSTORE_PATH") ?: System.getenv("STORE_FILE")
            val storePasswordEnv = System.getenv("STORE_PASSWORD")

            val rawStoreFile = storeFileProp ?: storeFileEnv
            val rawStorePassword = storePasswordProp ?: storePasswordEnv
            val rawKeyAlias = keyAliasProp ?: keyAliasEnv
            val rawKeyPassword = keyPasswordProp ?: keyPasswordEnv

            val resolvedStoreFile = rawStoreFile?.replace("\ufeff", "")?.trim()
            val resolvedStorePassword = rawStorePassword?.replace("\ufeff", "")?.trim()
            val resolvedKeyAlias = rawKeyAlias?.replace("\ufeff", "")?.trim()
            val resolvedKeyPassword = rawKeyPassword?.replace("\ufeff", "")?.trim()

            if (!resolvedStoreFile.isNullOrBlank() &&
                !resolvedStorePassword.isNullOrBlank() &&
                !resolvedKeyAlias.isNullOrBlank() &&
                !resolvedKeyPassword.isNullOrBlank()
            ) {
                val f = file(resolvedStoreFile)
                val targetFile = when {
                    f.exists() -> f
                    rootProject.file(resolvedStoreFile).exists() -> rootProject.file(resolvedStoreFile)
                    rootProject.file("../../$resolvedStoreFile").exists() -> rootProject.file("../../$resolvedStoreFile")
                    else -> f
                }
                if (targetFile.exists()) {
                    storeFile = targetFile
                    storePassword = resolvedStorePassword
                    keyAlias = resolvedKeyAlias
                    keyPassword = resolvedKeyPassword
                }
            }
        }
    }

    buildTypes {
        release {
            val releaseConfig = signingConfigs.getByName("release")
            if (releaseConfig.storeFile != null && releaseConfig.storeFile!!.exists()) {
                signingConfig = releaseConfig
            } else {
                if (System.getenv("CI") == "true" || System.getenv("GITHUB_ACTIONS") == "true") {
                    throw GradleException("Release build in CI requires a valid release signing configuration! Failing build.")
                }
                // Graceful fallback to debug signing for local development if release key is not configured
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
