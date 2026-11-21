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

// MT-PATCH-PLUGIN-REPOS: declare repositories explicitly for the included
// build's plugin resolution (it defines none of its own, so it would default
// to the Gradle plugin portal only, whose Central proxy gets HTTP 429
// rate-limited from shared runner egress IPs). JetBrains' cache-redirector
// is a CDN-backed mirror of repo.maven.apache.org without such limits.
pluginManagement {
    repositories {
        maven { url = uri("https://cache-redirector.jetbrains.com/repo.maven.apache.org/maven2") }
        google()
        gradlePluginPortal()
    }
}
EOF
echo "patched flutter gradle plugin repositories (Google Central mirror added)"
