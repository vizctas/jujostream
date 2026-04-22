plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val requestedTasks = gradle.startParameter.taskNames.map { it.lowercase() }
val isReleaseTaskRequested = requestedTasks.any {
    it.contains("release") || it.contains("bundle")
}

if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

if (isReleaseTaskRequested) {
    require(hasReleaseKeystore) {
        "Release builds require android/key.properties and a real keystore. Debug signing is blocked for release. Copy android/key.properties.example to android/key.properties and fill it before running a release build."
    }

    val requiredKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missingKeys = requiredKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    require(missingKeys.isEmpty()) {
        "android/key.properties is missing required keys: ${missingKeys.joinToString(", ")}"
    }

    val releaseStoreFile = file(keystoreProperties.getProperty("storeFile"))
    require(releaseStoreFile.exists()) {
        "Release keystore file not found: ${releaseStoreFile.path}"
    }
}

android {
    namespace = "com.vizcorp.moonlight_jujo_stream"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.vizcorp.moonlight_jujo_stream"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // NDK build for moonlight-common-c
        externalNativeBuild {
            cmake {
                cppFlags("-std=c++17")
                arguments(
                    "-DANDROID_STL=c++_shared"
                )
                abiFilters("armeabi-v7a", "arm64-v8a")
            }
        }

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                require(!storeFilePath.isNullOrBlank()) {
                    "Missing storeFile in android/key.properties"
                }
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Point to CMakeLists.txt for native build
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // AndroidX core (required for NotificationCompat, ServiceCompat, etc.)
    implementation("androidx.core:core-ktx:1.15.0")

    // Local JVM unit tests
    testImplementation("junit:junit:4.13.2")

    // Instrumented tests (run on device/emulator)
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
}

// Native .so files are already stripped by NDK/CMake during the release build.
// The extractNativeDebugMetadata task fails on pre-stripped binaries — disable it.
// Google Play generates native symbols independently when needed.
afterEvaluate {
    tasks.matching { it.name.contains("extractReleaseNativeDebugMetadata") }
        .configureEach { enabled = false }
}
