// Regression tests for:
// 1. Meal-selector memory: the add-food / food-detail sheets remember the
//    meal the user selected last time (explicit meal requests still win).
// 2. Habits feature removal: fresh installs must not create the habits
//    tables; upgrades from <=v4 must drop them.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:path/path.dart' as p;
import 'package:macrotrack/services/meal_memory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('meal selector memory', () {
    setUp(() async {
      Db.dbPathOverride = 'macrotrack_meal_memory_test.db';
      await Db.resetForTest();
    });

    test('defaults to snack when nothing remembered', () async {
      expect(await initialMeal(), 'snack');
    });

    test('remembers the last selection for the next sheet', () async {
      await rememberMeal('dinner');
      expect(await initialMeal(), 'dinner');
      await rememberMeal('breakfast');
      expect(await initialMeal(), 'breakfast');
    });

    test('an explicit meal request wins over the remembered one', () async {
      await rememberMeal('dinner');
      expect(await initialMeal(explicit: 'lunch'), 'lunch');
      // ...and the remembered value is untouched until a new selection.
      expect(await initialMeal(), 'dinner');
    });

    test('adding a food sets the remembered meal to the meal added to',
        () async {
      // The picker must follow the LAST meal something was ADDED to —
      // e.g. after adding to dinner, the next sheet starts at dinner,
      // even if the user tapped other chips on the way.
      await Db.insertLog(LogEntry(
          date: '2026-11-23',
          meal: 'dinner',
          name: 'Banana',
          grams: 120,
          kcal: 105,
          protein: 1,
          carbs: 27,
          fat: 0));
      // a later chip tap without an add does not override the last add
      await rememberMeal('lunch');
      await Db.insertLog(LogEntry(
          date: '2026-11-23',
          meal: 'snack',
          name: 'Yogurt',
          grams: 150,
          kcal: 90,
          protein: 8,
          carbs: 6,
          fat: 4));
      expect(await initialMeal(), 'snack',
          reason: 'the most recent ADD wins, not the most recent tap');
    });

    test('stale/invalid stored values fall back to snack', () async {
      await Db.setSetting(lastMealKey, 'brunch');
      expect(validMeal('brunch'), isNull);
      expect(await initialMeal(), 'snack');
      expect(validMeal('snack'), 'snack');
      expect(validMeal(null), isNull);
    });
  });

  group('habits removal (schema v5)', () {
    setUp(() async {
      Db.dbPathOverride = 'macrotrack_habits_removal_test.db';
      await Db.resetForTest();
    });

    test('fresh installs have no habits tables', () async {
      final db = await Db.instance;
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name IN ('habits','habit_days')");
      expect(rows, isEmpty);
    });

    test('weights table on a fresh install carries fat_percent', () async {
      final db = await Db.instance;
      final cols = await db.rawQuery('PRAGMA table_info(weights)');
      final names = cols.map((c) => c['name']).toSet();
      expect(names, contains('fat_percent'));
      expect(names, contains('weight_kg'));
    });

    test('v4 install upgrading to v5 gains fat_percent and loses habits',
        () async {
      final dir = await getDatabasesPath();
      final file = p.join(dir, 'macrotrack_v4_upgrade_test.db');
      if (await databaseFactory.databaseExists(file)) {
        await databaseFactory.deleteDatabase(file);
      }
      // Build a v4-shaped database exactly like a v4-era install had it:
      // no fat_percent column, habits tables present.
      final db = await databaseFactory.openDatabase(file);
      await db.execute('CREATE TABLE weights(id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, date TEXT UNIQUE, weight_kg REAL)');
      await db.execute(
          'CREATE TABLE habits(id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT, type TEXT, active INTEGER)');
      await db.insert('habits', {'id': 1, 'name': 'Meditate', 'type': 'daily',
          'active': 1});
      await db.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
      await db.close();

      // Re-open through the app's own Db layer (stamp it at version 4 via
      // userVersion so the app's onUpgrade 4->5 runs).
      final raw = await databaseFactory.openDatabase(file);
      await raw.execute('PRAGMA user_version = 4');
      await raw.close();

      Db.dbPathOverride = 'macrotrack_v4_upgrade_test.db';
      final appDb = await Db.instance;
      final cols =
          (await appDb.rawQuery('PRAGMA table_info(weights)'))
              .map((c) => c['name'])
              .toSet();
      expect(cols, contains('fat_percent'),
          reason: 'v4 installs must gain fat_percent on upgrade');
      final habits = await appDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND "
          "name IN ('habits','habit_days')");
      expect(habits, isEmpty);
      await appDb.close();
    });
  });
}
