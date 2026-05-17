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

// Some third-party Flutter plugins (e.g. receive_sharing_intent, which still
// targets Kotlin 1.9.22) ship an android/build.gradle with no
// `compileOptions`, so AGP defaults their Java compilation to 1.8 while this
// project's Kotlin 2.x toolchain targets 17. Gradle 8's JVM-target
// validation (ERROR by default) then aborts the build with "Inconsistent
// JVM-target compatibility".
//
// AGP derives the Java target from the `android.compileOptions` DSL, and the
// Kotlin validator reads that — not a late-mutated JavaCompile task — so the
// override has to go through each subproject's `android` extension. The root
// script has no AGP classpath, so reach the extension dynamically via
// withGroovyBuilder. This aligns every plugin to Java 17 (= the :app module
// and the plugins' own Kotlin 17 output).
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        androidExt.withGroovyBuilder {
            "compileOptions" {
                setProperty("sourceCompatibility", JavaVersion.VERSION_17)
                setProperty("targetCompatibility", JavaVersion.VERSION_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
