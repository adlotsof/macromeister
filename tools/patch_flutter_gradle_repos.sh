#!/bin/sh
# Make the Flutter Gradle toolchain's buildscript resolve Kotlin artifacts from
# Maven Central as well as plugins.gradle.org. The included build
# ($FLUTTER_ROOT/packages/flutter_tools/gradle) defines no pluginManagement
# repositories, so its buildscript (kotlin-dsl -> kotlin-stdlib) is resolved
# from the Gradle plugin portal alone; when the portal's Maven-Central proxy
# misbehaves the build dies with
#   Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader']
#   > Could not find org.jetbrains.kotlin:kotlin-stdlib:<ver>
# Idempotent: the patch is guarded by a marker and safe on cached SDKs.
set -e
SETTINGS="$FLUTTER_ROOT/packages/flutter_tools/gradle/settings.gradle.kts"
if [ ! -f "$SETTINGS" ]; then
  echo "flutter gradle settings not found at $SETTINGS — nothing patched"
  exit 0
fi
if grep -q "MT-PATCH-PLUGIN-REPOS" "$SETTINGS"; then
  echo "flutter gradle plugin repos already patched"
  exit 0
fi
cat >> "$SETTINGS" <<'EOF'

// MT-PATCH-PLUGIN-REPOS: ensure buildscript/plugin deps (kotlin-dsl,
// kotlin-stdlib) also resolve from Maven Central, not just the portal.
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}
EOF
echo "patched flutter gradle plugin repositories (mavenCentral added)"
