plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.booka_app"
    compileSdk = 35 // <-- явно фиксируем, чтобы как на скриншоте

    ndkVersion = "27.0.12077973" // <-- как ты хотел (или оставь свою)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17 // <-- Java 17
        targetCompatibility = JavaVersion.VERSION_17 // <-- Java 17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString() // <-- Java 17
    }

    defaultConfig {
        applicationId = "com.example.booka_app"
        minSdk = 26 // <-- явно фиксируем
        targetSdk = 34 // <-- явно фиксируем
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
