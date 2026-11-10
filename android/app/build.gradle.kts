import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.exists()) {
    releaseSigningPropertiesFile.inputStream().use { input ->
        releaseSigningProperties.load(input)
    }
}

val requiredReleaseSigningProperties =
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val missingReleaseSigningProperties = requiredReleaseSigningProperties.filter {
    releaseSigningProperties.getProperty(it).isNullOrBlank()
}
val releaseStoreFilePath =
    releaseSigningProperties.getProperty("storeFile").orEmpty().trim()
val releaseStoreFile =
    if (releaseStoreFilePath.isEmpty()) null else rootProject.file(releaseStoreFilePath)
val releaseSigningError = when {
    !releaseSigningPropertiesFile.exists() ->
        "Create android/key.properties from android/key.properties.example to sign a release."
    missingReleaseSigningProperties.isNotEmpty() ->
        "Missing release signing properties: ${missingReleaseSigningProperties.joinToString()}."
    releaseStoreFile?.isFile != true ->
        "The release keystore referenced by android/key.properties does not exist."
    else -> null
}

android {
    namespace = "com.luminhaw.plantcare"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.luminhaw.plantcare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningError == null) {
            create("release") {
                keyAlias = releaseSigningProperties.getProperty("keyAlias").trim()
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
                storeFile = releaseStoreFile
                storePassword = releaseSigningProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningError == null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

tasks.configureEach {
    if (name in setOf("assembleRelease", "bundleRelease", "packageRelease")) {
        doFirst {
            if (releaseSigningError != null) {
                throw GradleException(releaseSigningError)
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
