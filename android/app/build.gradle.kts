plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.copra.viby"
    // Compile against the latest stable API (must be >= targetSdk below).
    // 36 (Android 16) is required by flutter_secure_storage 10.x.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.copra.viby"
        // minSdk 24 (Android 7.0): floor required by just_audio / audio_service
        // and a sensible baseline for a modern media app.
        minSdk = 24
        // Target the latest stable Android API. Kept explicit (not
        // flutter.targetSdkVersion) so store-compliance behaviour is pinned and
        // does not silently shift when the Flutter SDK bumps its default.
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
