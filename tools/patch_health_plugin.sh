#!/usr/bin/env bash
# health 13.3.2's android/build.gradle unconditionally applies
# 'kotlin-android', which fails under AGP 9 with built-in Kotlin
# (android.builtInKotlin=true in android/gradle.properties).
# Make it conditional on the AGP major version. Run after `flutter pub get`
# whenever the pub cache is re-populated (also locally).
set -euo pipefail

F="$HOME/.pub-cache/hosted/pub.dev/health-13.3.2/android/build.gradle"
if [ ! -f "$F" ]; then
  echo "health android build.gradle not found at $F — skipping patch" >&2
  exit 0
fi

if grep -q "agpMajor" "$F"; then
  echo "health plugin already patched"
  exit 0
fi

python3 - "$F" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace(
    """apply plugin: 'com.android.library'
apply plugin: 'kotlin-android'
""",
    """apply plugin: 'com.android.library'
// AGP 9+ provides Kotlin support natively; applying kotlin-android then fails.
def agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.split(/[.]/)[0].toInteger()
if (agpMajor < 9) {
  apply plugin: 'kotlin-android'
}
""")
s = s.replace(
    """    kotlinOptions {
        jvmTarget = '11'
    }
""",
    """    if (agpMajor < 9) {
      kotlinOptions {
        jvmTarget = '11'
      }
    }
""")
open(p, 'w').write(s)
print("health plugin patched for built-in Kotlin")
EOF
