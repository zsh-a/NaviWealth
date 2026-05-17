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
// NOTE: stale third-party plugins (e.g. receive_sharing_intent, Kotlin
// 1.9.22) compile Java at 1.8 / Kotlin at 17 and trip Gradle's JVM-target
// validation. This is handled ordering-independently by
// `kotlin.jvm.target.validation.mode=warning` in gradle.properties — a
// root-script subprojects/afterEvaluate override is NOT used here because
// Flutter's plugin-loader + evaluationDependsOn(":app") evaluates some
// subprojects before this script runs ("project is already evaluated").

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
