plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH")
val releaseStorePassword =
    System.getenv("INTERCITY_ANDROID_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("INTERCITY_ANDROID_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("INTERCITY_ANDROID_RELEASE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val debugKeystoreFile = file("${System.getProperty("user.home")}/.android/debug.keystore")

android {
    namespace = "com.milanium.intercity"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.milanium.intercity"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
            if (hasReleaseSigning) {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            } else {
                storeFile = debugKeystoreFile
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
            if (!hasReleaseSigning) {
                logger.warn(
                    "Release signing env vars are not fully configured; using debug signing for installable test APK.",
                )
            }
        }
    }
}

flutter {
    source = "../.."
}

val hasGoogleServicesJson = listOf(
    file("google-services.json"),
    file("src/debug/google-services.json"),
    file("src/release/google-services.json"),
).any { it.exists() }

if (hasGoogleServicesJson) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("google-services.json not found, building without Google Services plugin")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
