plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.krishimitra.krishi_mitra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.krishimitra.krishi_mitra"
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += listOf("arm64-v8a") } // POCO X5 Pro: Snapdragon 778G, ARMv8.2-A
    }

    buildTypes {
        release {
            // Debug keys so `flutter build apk --release` is directly sideloadable.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs { useLegacyPackaging = true }
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

dependencies {
    // ExecuTorch Android runtime (XNNPACK + LLM runner, arm64-v8a). Keep in
    // step with the ExecuTorch version used to export the .pte (release/1.0).
    implementation("org.pytorch:executorch-android:1.0.0")
}
