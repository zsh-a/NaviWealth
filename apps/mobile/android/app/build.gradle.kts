import groovy.json.JsonSlurper
import org.gradle.api.artifacts.dsl.RepositoryHandler
import org.gradle.api.artifacts.repositories.MavenArtifactRepository

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun RepositoryHandler.rustlsPlatformVerifier(): MavenArtifactRepository {
    val dependencyText = providers.exec {
        workingDir = rootProject.projectDir.parentFile
        commandLine(
            "cargo",
            "metadata",
            "--format-version",
            "1",
            "--filter-platform",
            "aarch64-linux-android",
            "--manifest-path",
            "native/lifeos_native/Cargo.toml",
        )
    }.standardOutput.asText.get()

    val dependencyJson = JsonSlurper().parseText(dependencyText) as Map<*, *>
    val packages = dependencyJson["packages"] as List<*>
    val manifestPath = packages
        .filterIsInstance<Map<*, *>>()
        .first {
            it["name"] == "rustls-platform-verifier-android"
        }["manifest_path"] as String
    val manifestFile = file(manifestPath)

    return maven {
        url = uri(file(manifestFile.parentFile.resolve("maven")))
        metadataSources.artifact()
    }
}

repositories {
    rustlsPlatformVerifier()
}

android {
    namespace = "com.naviwealth.naviwealth"
    // flutter_secure_storage and receive_sharing_intent currently publish
    // Android SDK 37 metadata. Keep the application compile SDK at the
    // highest dependency requirement instead of inheriting Flutter's SDK 36
    // default, while min/target SDK remain controlled by Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.naviwealth.naviwealth"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    // --target-platform only controls generated Flutter code. Prebuilt FFI
    // plugins can still contribute jniLibs for every ABI, so arm64 release
    // jobs opt into filtering those libraries at the packaging boundary.
    if (providers.gradleProperty("naviwealth-arm64-only").orNull == "true") {
        packaging {
            jniLibs {
                excludes += setOf(
                    "**/armeabi-v7a/**",
                    "**/x86/**",
                    "**/x86_64/**",
                )
            }
        }
    }

    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("KEYSTORE_FILE")
            if (!keystorePath.isNullOrBlank() && file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
                keyAlias = System.getenv("KEY_ALIAS") ?: ""
                keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        release {
            val releaseKeystore = System.getenv("KEYSTORE_FILE")
                ?.takeIf { it.isNotBlank() }
                ?.let { file(it) }
            signingConfig = if (releaseKeystore?.exists() == true) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("rustls:rustls-platform-verifier:latest.release")
}
