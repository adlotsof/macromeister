// Regression tests for the "macro targets set in program are not shown in
// dashboard / log" bug and related cross-screen staleness.
//
// Bug 1: currentTargets() preferred the last check-in's stored dailyTarget,
// so after editing the program (goal rate / activity / goal weight) the
// dashboard and log kept showing the check-in-era target while the program
// editor preview showed the new one.
//
// Bug 2: screens rebuild FutureBuilders with a fresh currentTargets() future
// on every AppState notification, which flashed the targets card to
// "no targets" (and hid them while the DB round-trip ran). currentTargets()
// is now cached until the next refresh() — tests assert the caching and
// invalidation behavior.
//
// These use sqflite_common_ffi against a real temp SQLite file.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/app_state.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:macrotrack/services/expenditure.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _resetDb() async {
  Db.dbPathOverride = 'macrotrack_current_targets_test.db';
  await Db.resetForTest();
  final dir = await getDatabasesPath();
  final file = p.join(dir, Db.dbPathOverride!);
  if (await databaseFactory.databaseExists(file)) {
    await databaseFactory.deleteDatabase(file);
  }
  // Fresh cache, like a fresh app start.
  AppState.instance.refresh();
}

Future<Profile> _profile(double goalRate) async {
  final p = Profile(
    name: 'Test',
    sex: 'male',
    birthYear: 1987,
    heightCm: 180,
    startWeightKg: 80,
    goalWeightKg: 78,
    goalRateKgPerWeek: goalRate,
    activityFactor: 1.4,
  );
  await Db.saveProfile(p);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('custom macro targets set in program are used by currentTargets',
      () async {
    await _resetDb();
    await _profile(-0.25);

    final auto = await AppState.instance.currentTargets();

    await Db.setSetting('macro_custom', '1');
    await Db.setSetting('macro_protein_g', '150');
    await Db.setSetting('macro_fat_g', '60');
    AppState.instance.refresh(); // as the program editor does

    final custom = await AppState.instance.currentTargets();

    expect(custom.protein, 150,
        reason: 'custom protein from the program editor must be the target');
    expect(custom.fat, 60,
        reason: 'custom fat from the program editor must be the target');
    final carbsKcal = custom.dailyTargetKcal - 150 * 4 - 60 * 9;
    expect(custom.carbs, carbsKcal < 0 ? 0.0 : (carbsKcal / 4).floor());
    expect(auto.protein, isNot(150));
  });

  test('disabling custom macros falls back to auto targets', () async {
    await _resetDb();
    await _profile(-0.25);
    final auto = await AppState.instance.currentTargets();

    await Db.setSetting('macro_custom', '1');
    // Deliberately extreme values that can never collide with the auto split.
    await Db.setSetting('macro_protein_g', '333');
    await Db.setSetting('macro_fat_g', '20');
    AppState.instance.refresh();
    final custom = await AppState.instance.currentTargets();
    expect(custom.protein, 333);
    expect(custom.fat, 20);

    await Db.setSetting('macro_custom', '0');
    AppState.instance.refresh();
    final after = await AppState.instance.currentTargets();
    expect(after.protein, auto.protein);
    expect(after.fat, auto.fat);
  });

  test('program edits are reflected immediately, not only at the next '
      'check-in (stale check-in dailyTarget)', () async {
    await _resetDb();
    final p = await _profile(-0.25);
    final before = await AppState.instance.currentTargets();

    // Weekly check-in stored a target from the profile at check-in time.
    await Db.insertCheckIn(CheckIn(
      date: fmtDate(today()),
      weekStart: fmtDate(weekStart(today())),
      weightKg: 80,
      kcalAvg7d: 2000,
      expenditure: before.expenditure,
      dailyTarget: before.dailyTargetKcal,
    ));

    // User edits the program: switch to aggressive gaining (+0.75/week).
    // The program editor calls AppState.refresh() after saving the profile.
    await Db.saveProfile(p.copyWith(goalRateKgPerWeek: 0.75));
    AppState.instance.refresh();
    final after = await AppState.instance.currentTargets();

    // BUG REGRESSION: the old implementation returned lastCheckIn.dailyTarget
    // (the pre-edit value), so the dashboard kept showing the old target.
    expect(after.dailyTargetKcal, isNot(before.dailyTargetKcal),
        reason: 'editing the program must change the daily target on '
            'dashboard/log immediately, not only at the next check-in');
    // Must equal the fresh computation the program editor preview shows.
    expect(after.dailyTargetKcal,
        ExpenditureEngine.dailyTarget(after.expenditure, 0.75));
  });

  test('currentTargets() is cached until refresh() (no flicker to '
      '"no targets" between rebuilds)', () async {
    await _resetDb();
    await _profile(-0.25);
    final app = AppState.instance;

    final t1 = await app.currentTargets();
    final t2 = await app.currentTargets();
    expect(identical(t1, t2), isTrue,
        reason: 'repeated calls must return the same cached future/result '
            'so FutureBuilders keep their completed snapshot across '
            'rebuilds');

    // Changing a setting without refresh() is invisible until refresh —
    // that is fine; refresh() (sent by the program editor) must invalidate.
    await Db.setSetting('macro_protein_g', '333');
    await Db.setSetting('macro_custom', '1');
    final stale = await app.currentTargets();
    expect(stale.protein, t1.protein, reason: 'cache serves the old value');

    app.refresh();
    final fresh = await app.currentTargets();
    expect(fresh.protein, 333,
        reason: 'refresh() must invalidate the cached targets');
  });
}
