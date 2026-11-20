// Regression tests for infrastructure/defects found outside app logic:
// - CI food-data script failing with "cp: cannot create regular file
//   '../assets/foods_off.db': No such file or directory" (assets/ had no
//   tracked files, so it was absent in a fresh CI checkout)
// - plugin upgrades to built-in Kotlin (android.builtInKotlin) breaking the
//   health plugin, and the pub-cache patch that fixes it
// - GitHub Actions pinned to mutable tags (drift risk)
// - analyze/test originally non-blocking / bundled in the build job
// - parallel test suites deadlocking on one shared database file
// - Open Food Facts ODbL attribution requirements (NOTICE + in-app notice)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tools/fetch_food_data.sh (CI "No such file or directory" fix)', () {
    final script = _read('tools/fetch_food_data.sh');

    test('creates assets/ before copying built DBs', () {
      expect(script, contains('mkdir -p ../assets'),
          reason: 'assets/ contains no tracked files and does not exist in a '
              'fresh CI checkout; the script must create it before cp');
      final mkdir = script.indexOf('mkdir -p ../assets');
      final firstCp = script.indexOf('cp ');
      expect(mkdir, lessThan(firstCp),
          reason: 'mkdir must run before the first cp into ../assets');
    });

    test('aborts on errors so failures surface in CI', () {
      expect(script, contains('set -euo pipefail'));
    });

    test('copies both bundled databases', () {
      expect(script, contains('../assets/foods_off.db'));
      expect(script, contains('../assets/foods_common.db'));
    });
  });

  group('built-in Kotlin migration (health/share_plus AGP 9 fix)', () {
    test('android/gradle.properties enables built-in Kotlin', () {
      final props = _read('android/gradle.properties');
      expect(props, contains('android.builtInKotlin=true'),
          reason: 'the upgraded plugins require AGP 9 built-in Kotlin; with '
              'builtInKotlin=false the share_plus compile fails');
    });

    test('health plugin patch script exists, is idempotent and guards KGP',
        () {
      final s = _read('tools/patch_health_plugin.sh');
      expect(s, contains('agpMajor'),
          reason: 'patch must apply kotlin-android conditionally on AGP < 9');
      expect(s, contains('already patched'),
          reason: 're-running the patch must not corrupt the build file');
      expect(s, contains('health-13.3.2'),
          reason: 'patch targets the pub-cache copy of the health plugin');
    });

    test('CI test job runs the health plugin patch after pub get', () {
      final yml = _read('.github/workflows/build.yml');
      expect(yml, contains('tools/patch_health_plugin.sh'),
          reason: 'CI pub cache is clean; without the patch the health '
              'plugin fails to configure under AGP 9');
    });
  });

  group('GitHub Actions workflow', () {
    final yml = _read('.github/workflows/build.yml');

    test('every action is pinned to a full commit SHA', () {
      final uses = RegExp(r'^\s*-?\s*uses:\s*(\S+)', multiLine: true)
          .allMatches(yml)
          .map((m) => m.group(1)!)
          .toList();
      expect(uses, isNotEmpty);
      for (final u in uses) {
        expect(u, matches(RegExp(r'@[0-9a-f]{40}')),
            reason: 'action "$u" must be pinned to a 40-char commit SHA, '
                'not a mutable tag like @v4');
      }
    });

    test('analyze and test run in a dedicated, blocking test job', () {
      expect(yml, matches(RegExp(r'^\s+test:\s*$', multiLine: true)),
          reason: 'a dedicated test job must exist');
      expect(yml, contains('flutter test'));
      expect(yml, contains('flutter analyze'));
      // The build job must not duplicate them.
      final buildIdx = yml.indexOf('  build:');
      final buildPart = yml.substring(buildIdx);
      expect(buildPart, isNot(contains('flutter test')),
          reason: 'tests belong in the test job, not the build job');
      expect(
          buildPart
              .substring(buildPart.indexOf('Build release APK'))
              .contains('flutter analyze'),
          isFalse,
          reason: 'analyze must be blocking in the test job, not '
              'continue-on-error noise in the build job');
    });
  });

  group('test infrastructure', () {
    test('sqflite_common_ffi is available for DB-backed tests', () {
      final pubspec = _read('pubspec.yaml');
      expect(pubspec, contains('sqflite_common_ffi'),
          reason: 'the regression tests run against a real SQLite file');
    });

    test('parallel test suites use per-suite database files', () {
      // flutter test runs suites concurrently; a shared macrotrack.db made
      // the full-suite run deadlock on file locks.
      expect(_read('lib/db.dart'), contains('dbPathOverride'));
      expect(_read('test/current_targets_test.dart'), contains('dbPathOverride'));
      expect(_read('test/log_screen_targets_test.dart'), contains('dbPathOverride'));
    });
  });

  group('Open Food Facts / USDA data licenses', () {
    test('NOTICE.md documents ODbL and CC0 obligations', () {
      final notice = _read('NOTICE.md');
      expect(notice, contains('ODbL'));
      expect(notice, contains('share-alike'));
      expect(notice, contains('CC0'));
      expect(notice, contains('Open Database License'));
    });

    test('in-app attribution carries the required OFF notice', () {
      final screen = _read('lib/ui/more/data_sources_screen.dart');
      expect(screen, contains('world.openfoodfacts.org'));
      expect(screen, contains('Open Database License (ODbL) 1.0'),
          reason: 'OFF requires the attribution text where users encounter '
              'the data');
    });
  });
}
