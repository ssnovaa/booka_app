// --- imports для Kotlin DSL ---
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter Gradle Plugin должен идти после Android и Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // ⛔️ НЕ добавляем здесь id("com.google.gms.google-services")
}

// Читаем версии из local.properties (flutter.versionCode / flutter.versionName)
val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) {
        FileInputStream(f).use { load(it) }
    }
}
val flutterVersionCode = (localProperties.getProperty("flutter.versionCode") ?: "1").toInt()
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0.0"

// 🔐 читаем key.properties (если есть)
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        FileInputStream(f).use { load(it) }
    }
}
val hasReleaseKeystore =
    !keystoreProperties.getProperty("storeFile").isNullOrBlank() &&
            !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
            !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
            !keystoreProperties.getProperty("keyPassword").isNullOrBlank()

android {
    // Лучше, чтобы namespace совпадал с applicationId
    namespace = "com.booka_app"

    // Требования Play на 2025
    compileSdk = 36

    defaultConfig {
        applicationId = "com.booka_app"
        // Flutter сам проставляет minSdk из .metadata; оставим не ниже 21
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = 36

        versionCode = flutterVersionCode      // увеличивай перед каждой загрузкой
        versionName = flutterVersionName

        multiDexEnabled = true
        vectorDrawables { useSupportLibrary = true }
    }

    signingConfigs {
        getByName("debug") { /* default debug.keystore */ }
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                if (!storeFilePath.isNullOrBlank()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            // 🔧 Оптимизация релиза
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // ❗ Релиз должен подписываться настоящим ключом
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "Release signing is not configured. " +
                            "Создай key.properties и release keystore перед сборкой Play (.aab)."
                )
            }
        }
    }

    // Десугаринг (java.time и пр.)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    // Убираем дубли лицензий
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    // Чуть тише линтер в CI
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    // Если хочешь единый языковой split:
    // bundle { language { enableSplit = false } }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ требуется для современных API (java.time и т.п.)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ Google Play Billing — обязательная зависимость, чтобы консоль увидела поддержку подписок
    implementation("com.android.billingclient:billing-ktx:6.1.0")
}

// ⬇️ Подключаем Google Services через apply
// (версия плагина объявлена в корневом build.gradle.kts → buildscript { classpath(...) })
apply(plugin = "com.google.gms.google-services")
