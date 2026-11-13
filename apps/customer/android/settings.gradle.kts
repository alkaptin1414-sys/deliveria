pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")

// Pub packages live on D: with the project. Android Studio may rewrite
// plugin paths back to C:\Users\...\Pub\Cache, and Gradle cannot relativize
// a build directory on D: against sources on C:.
val relocatedPubCache = file("D:/pub-cache/hosted/pub.dev")
if (relocatedPubCache.isDirectory) {
    for (project in rootProject.children) {
        val current = project.projectDir.absolutePath
        val marker = "\\hosted\\pub.dev\\"
        val index = current.indexOf(marker)
        if (index < 0) continue
        val relocated = file("$relocatedPubCache/${current.substring(index + marker.length)}")
        if (relocated.isDirectory) {
            project.projectDir = relocated
        }
    }
}
