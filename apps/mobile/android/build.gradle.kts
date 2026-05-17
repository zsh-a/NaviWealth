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

// Some third-party Flutter plugins (e.g. receive_sharing_intent) ship an
// android/build.gradle with no `compileOptions`, so AGP defaults their Java
// compilation to 1.8 while the project's Kotlin 2.x toolchain targets 17.
// Gradle 8's JVM-target validation (ERROR by default) then aborts the build
// with "Inconsistent JVM-target compatibility". Pin every subproject's Java
// compilation to 17 so plugins match the :app module (Java 17 / Kotlin 17)
// and their own Kotlin output.
subprojects {
    afterEvaluate {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
