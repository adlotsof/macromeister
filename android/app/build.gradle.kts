import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is injected via key.properties (gitignored). On CI the
// workflow decodes ANDROID_KEYSTORE_BASE64 + writes key.properties; without
// it the release build falls back to the debug key (side-loadable, still
// uploadable to the internal track only if Play App Signing is on).
val keystoreProps = Properties()
val keystorePropsFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropsFile.exists()
if (hasReleaseSigning) {
    keystorePropsFile.inputStream().use { keystoreProps.load(it) }
}

android {
    namespace = "com.trsonn.macrotrack"
    compileSdk = 36  // health plugin's Health Connect client requires API 35+
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.trsonn.macrotrack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // Health Connect requires API 26+ (health plugin)

        lint {
            // AGP lint crashes (CommentDetector NoSuchMethodError) on plugin
            // sources with JDK 17 — not our code; don't fail the release build.
            checkReleaseBuilds = false
            abortOnError = false
        }
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with key.properties when present (CI/production); falls
            // back to the debug key so local release builds still run.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.create("release") {
                    storeFile = file(keystoreProps["storeFile"] as String)
                    storePassword = keystoreProps["storePassword"] as String
                    keyAlias = keystoreProps["keyAlias"] as String
                    keyPassword = keystoreProps["keyPassword"] as String
                }
            } else {
                signingConfigs.getByName("debug")
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
