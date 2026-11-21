#!/bin/sh
# Make the Flutter Gradle toolchain's buildscript resolve Kotlin artifacts
# from Google's Maven Central mirror instead of relying on plugins.gradle.org.
# The included build ($FLUTTER_ROOT/packages/flutter_tools/gradle) defines no
# pluginManagement repositories, so its buildscript (kotlin-dsl ->
# kotlin-stdlib) resolves from the Gradle plugin portal alone, whose proxy
# redirects to repo.maven.apache.org. Sonatype throttles/blocks some
# hosted-runner egress IPs, which makes the build die with
#   Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader']
#   > Could not find org.jetbrains.kotlin:kotlin-stdlib:<ver>
# Google's mirror (maven.google.com) hosts the identical Maven Central
# content on Google's network and is not affected.
# Idempotent: the patch is guarded by a marker and safe on cached SDKs.
set -e
SETTINGS="$FLUTTER_ROOT/packages/flutter_tools/gradle/settings.gradle.kts"
if [ ! -f "$SETTINGS" ]; then
  echo "flutter gradle settings not found at $SETTINGS - nothing patched"
  exit 0
fi
if grep -q "MT-PATCH-PLUGIN-REPOS" "$SETTINGS"; then
  echo "flutter gradle plugin repos already patched"
  exit 0
fi
cat >> "$SETTINGS" <<'EOF'

// MT-PATCH-PLUGIN-REPOS: resolve buildscript/plugin deps (kotlin-dsl,
// kotlin-stdlib) from Google's Maven Central mirror first; the portal's
// Central proxy is unreliable from hosted runners.
pluginManagement {
    repositories {
        exclusiveContent {
            forRepository {
                maven { url = uri("https://maven.google.com/maven2") }
            }
            filter { includeGroupByRegex("org\\.jetbrains\\..*") }
        }
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}
EOF
echo "patched flutter gradle plugin repositories (Google Central mirror added)"
