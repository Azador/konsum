allprojects {
    repositories {
        google()
        mavenCentral()
        // Tesseract4Android (Kassenbons) gibt es nur über JitPack; nur diese
        // Gruppe von dort laden.
        maven("https://jitpack.io") {
            content { includeGroup("cz.adaptech.tesseract4android") }
        }
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

// Native Teile der Plugins (zxing-cpp, jni) nur für die Architekturen bauen,
// die in die APK kommen. Flutters --target-platform wirkt sonst nur auf die
// App, und CMake übersetzt jedes Plugin für alle vier ABIs, auch x86.
val flutterAbis =
    mapOf(
        "android-arm" to "armeabi-v7a",
        "android-arm64" to "arm64-v8a",
        "android-x64" to "x86_64",
    )
val targetAbis: List<String> =
    (findProperty("target-platform") as String?)
        ?.split(",")
        ?.mapNotNull { flutterAbis[it.trim()] }
        ?.takeIf { it.isNotEmpty() }
        ?: flutterAbis.values.toList()
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            defaultConfig.ndk.abiFilters.apply {
                clear()
                addAll(targetAbis)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
