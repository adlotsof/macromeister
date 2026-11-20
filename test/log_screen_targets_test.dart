// Widget-level regression test: the log screen totals card must show the
// program-set macro targets, and must keep them across AppState
// notifications (the old implementation re-created the FutureBuilder future
// on every rebuild, which dropped the completed snapshot and flashed the
// card to "no targets").
//
// DB access runs inside tester.runAsync() because widget tests execute in a
// FakeAsync zone in which sqflite_ffi futures otherwise never complete.
// Because AppState.currentTargets() caches its future until the next
// refresh(), pre-warming the cache via runAsync() means the widget tree
// receives an already-completed future on its first build — the exact
// guarantee the cache was added for.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/app_state.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:macrotrack/ui/log/log_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _resetDb() async {
  Db.dbPathOverride = 'macrotrack_log_screen_test.db';
  await Db.resetForTest();
  final dir = await getDatabasesPath();
  final file = p.join(dir, Db.dbPathOverride!);
  if (await databaseFactory.databaseExists(file)) {
    await databaseFactory.deleteDatabase(file);
  }
  AppState.instance.refresh();
}

Future<void> _seed({String protein = '333'}) async {
  await _resetDb();
  await Db.saveProfile(Profile(
    name: 'Test',
    sex: 'male',
    birthYear: 1987,
    heightCm: 180,
    startWeightKg: 80,
    goalWeightKg: 78,
    goalRateKgPerWeek: -0.25,
    activityFactor: 1.4,
  ));
  await Db.setSetting('macro_custom', '1');
  await Db.setSetting('macro_protein_g', protein);
  await Db.setSetting('macro_fat_g', '20');
  // Warm the cache exactly like a screen that loaded before this one.
  await AppState.instance.currentTargets();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('log screen shows the program-set protein target',
      (tester) async {
    await tester.runAsync(() => _seed(protein: '333'));
    await _pump(tester, const LogScreen());

    expect(find.textContaining('333'), findsWidgets,
        reason: 'the protein target (333 g set in the program editor) must '
            'be visible on the log screen totals card');
  });

  testWidgets('log screen shows updated targets after refresh()',
      (tester) async {
    await tester.runAsync(() => _seed(protein: '333'));
    await _pump(tester, const LogScreen());
    expect(find.textContaining('333'), findsWidgets);

    // The program editor saves the new grams and calls AppState.refresh().
    await tester.runAsync(() async {
      await Db.setSetting('macro_protein_g', '444');
      AppState.instance.refresh(); // invalidate + notify, as the editor does
      // The log screen kicks off the recompute on its next build; here we
      // let it complete outside FakeAsync so the snapshot is ready.
      await AppState.instance.currentTargets();
    });
    await _pump(tester, const LogScreen()); // rebuild with invalidated cache

    expect(find.textContaining('444'), findsWidgets,
        reason: 'after a program edit + refresh, the log screen must show '
            'the new target (444 g), not the stale cached one');
    expect(find.textContaining('333/'), findsNothing,
        reason: 'the stale protein target must not linger');
  });
}
