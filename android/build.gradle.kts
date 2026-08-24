group = "dev.steenbakker.flutter_ble_central"
version = "1.0-SNAPSHOT"

plugins {
    id("com.android.library")
}

// AGP 9 ships its own Kotlin support, but only when android.builtInKotlin is
// left enabled. Flutter's templates set it to false, in which case the Kotlin
// plugin still has to be applied the old way.
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
val builtInKotlin = agpMajor >= 9 &&
    (findProperty("android.builtInKotlin")?.toString() ?: "true").toBoolean()
if (!builtInKotlin) {
    apply(plugin = "kotlin-android")
}

android {
    namespace = "dev.steenbakker.flutter_ble_central"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 21
    }
}

fun configureKotlin() {
    extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
}

// With AGP 9 and builtInKotlin=false the Flutter Gradle Plugin applies KGP
// after this script is evaluated, so the extension may not exist yet.
if (extensions.findByName("kotlin") != null) {
    configureKotlin()
} else {
    plugins.withId("org.jetbrains.kotlin.android") { configureKotlin() }
}
