import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
// NOTE: stale third-party plugins can still publish Kotlin compile tasks with
// languageVersion/apiVersion 1.6. Flutter stable now runs KGP 2.2.x, where
// 1.6 is rejected before tests even install on the emulator. Configure every
// Kotlin Android task lazily so already-created and future plugin tasks are
// normalized without afterEvaluate ordering traps.
subprojects {
    fun normalizeKotlinCompileLanguage() {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                languageVersion.set(KotlinVersion.KOTLIN_1_8)
                apiVersion.set(KotlinVersion.KOTLIN_1_8)
            }
        }
    }
    plugins.withId("org.jetbrains.kotlin.android") {
        normalizeKotlinCompileLanguage()
    }
    plugins.withId("kotlin-android") {
        normalizeKotlinCompileLanguage()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
