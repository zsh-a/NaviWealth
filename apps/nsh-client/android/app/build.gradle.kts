import groovy.json.JsonSlurper
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val appMetadata = JsonSlurper().parse(file("../../nsh.json")) as Map<*, *>
android {
    namespace = "com.naviwealth.app"
    compileSdk = 35
    buildToolsVersion = "35.0.1"
    defaultConfig {
        applicationId = appMetadata["id"] as String
        minSdk = 26
        targetSdk = 35
        versionCode = (appMetadata["build"] as Number).toInt()
        versionName = appMetadata["version"] as String
        ndk { abiFilters += "arm64-v8a" }
    }
    buildTypes {
        getByName("debug") { applicationIdSuffix = ".bledev" }
        getByName("release") { isMinifyEnabled = false; isDebuggable = false }
    }
    sourceSets.getByName("main") {
        assets.srcDir("generated/assets")
        jniLibs.srcDir("generated/jniLibs")
        res.srcDir("generated/res")
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17"; allWarningsAsErrors = true }
    packaging { jniLibs { useLegacyPackaging = false } }
    testOptions { unitTests.isReturnDefaultValues = true }
    lint {
        warningsAsErrors = true
        // Keep target API 35 pinned for the app-owned NSH host. A newer SDK
        // installed on a CI runner must not silently change this compatibility
        // decision; upgrading it requires separate platform acceptance.
        // Android phone/arm64 releases and the approved Folio artwork are deliberate.
        disable += setOf("OldTargetApi", "ChromeOsAbiSupport", "IconLauncherShape")
    }
}
dependencies {
    implementation(files("generated/nsh/classes.jar"))
    testImplementation("junit:junit:4.13.2")
}
tasks.named("preBuild") {
    doFirst {
        check(file("generated/nsh/classes.jar").isFile) { "Run tool/build-nsh-android-host.sh first to prepare the pinned NSH Java runtime." }
    }
}

tasks.matching { it.name == "packageRelease" || it.name == "packageDebug" }.configureEach {
    doFirst {
        check(file("generated/jniLibs/arm64-v8a/libnsh.so").isFile) { "The mixed app-linked NSH library is missing." }
        check(file("generated/assets/nsh/bundle.nshc").isFile) { "The mixed TSX bundle is missing." }
    }
}
