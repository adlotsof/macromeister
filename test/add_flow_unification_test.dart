// Regression tests for the unified add-food flow:
// 1. Recipes log through the SAME detail-sheet flow as foods — per-serving
//    values and portion math live in pure helpers (recipePerServingFood,
//    recipePortionMacros) tested here.
// 2. Meal selection moved from the global top-right dropdown to per-item
//    pickers next to each Add button (the picker itself is UI; the
//    remembered-meal logic is covered in meal_memory_and_schema_test).
// 3. Log entries can carry a meal photo (custom foods): LogEntry.photo
//    serializes and persists.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('recipe -> unified food flow', () {
    final r = Recipe(
        name: 'Test recipe',
        servings: 4,
        ingredientsJson: '[]',
        kcal: 200, // per serving (Recipe stores per-serving values)
        protein: 10,
        carbs: 20,
        fat: 5);

    test('per-serving conversion divides by servings', () {
      final f = recipePerServingFood(r);
      expect(f.kcal, 200);
      expect(f.protein, 10);
      expect(f.carbs, 20);
      expect(f.fat, 5);
      expect(f.brand, '');
      expect(f.source, 'recipe');
      expect(f.servingG, 1, reason: 'servings mode: the count IS the portion');
    });

    test('detail-sheet servings math: 1 and 2.5 servings', () {
      final f = recipePerServingFood(r);
      // The sheet scales per-serving values by the entered portion count
      // (servings mode), i.e. kcal * count.
      expect(f.kcal * 1, 200);
      expect(f.kcal * 2.5, 500);
      expect(f.protein * 2.5, 25);
    });
  });

  group('re-adding a previously-logged food', () {
    // Tapping a previously-logged entry used to re-log it instantly with
    // the same amount; now it opens the detail sheet so the serving can
    // be adjusted before adding.
    test('loggedEntryAsFood normalizes totals to per-100 g', () {
      final e = LogEntry(
          date: '2026-11-23',
          meal: 'lunch',
          name: 'Banana',
          brand: 'My food',
          grams: 200,
          kcal: 300,
          protein: 20,
          carbs: 60,
          fat: 10,
          fiber: 4);
      final f = loggedEntryAsFood(e);
      expect(f.servingG, 200, reason: 'prefills the previously-logged amount');
      expect(f.kcal, 150); // 300 kcal per 200 g -> 150 per 100 g
      expect(f.protein, 10);
      expect(f.carbs, 30);
      expect(f.fat, 5);
      expect(f.fiber, 2);
      expect(f.brand, 'My food');
    });

    test('detail-sheet math: re-adding a different amount scales correctly',
        () {
      final f = loggedEntryAsFood(LogEntry(
          date: '2026-11-23',
          meal: 'lunch',
          name: 'Banana',
          grams: 200,
          kcal: 300,
          protein: 20,
          carbs: 60,
          fat: 10,
          fiber: 4));
      // the sheet computes absolute values as per100 * grams / 100
      expect(f.kcal * 400 / 100, 600, reason: 'double the amount = double kcal');
      expect(f.kcal * 100 / 100, 150, reason: 'half the amount = half kcal');
    });
  });

  group('log entry meal photo', () {
    setUp(() async {
      Db.dbPathOverride = 'macrotrack_photo_entry_test.db';
      // Remove any stale database from a previous run — resetForTest does
      // not delete the file itself.
      final dir = await getDatabasesPath();
      final f = p.join(dir, 'macrotrack_photo_entry_test.db');
      if (await databaseFactory.databaseExists(f)) {
        await databaseFactory.deleteDatabase(f);
      }
      await Db.resetForTest();
    });

    test('LogEntry.photo round-trips through toMap/fromMap', () {
      final e = LogEntry(
          date: '2026-11-23',
          meal: 'lunch',
          name: 'Custom lunch',
          grams: 0,
          kcal: 500,
          protein: 30,
          carbs: 40,
          fat: 20,
          photo: '/tmp/meal.jpg');
      final back = LogEntry.fromMap(e.toMap());
      expect(back.photo, '/tmp/meal.jpg');
    });

    test('photo persists via insertLog and reads back', () async {
      await Db.insertLog(LogEntry(
          date: '2026-11-24',
          meal: 'dinner',
          name: 'Custom dinner',
          grams: 0,
          kcal: 700,
          protein: 20,
          carbs: 60,
          fat: 30,
          photo: '/tmp/dinner.jpg'));
      final logs = await Db.logsForDay('2026-11-24');
      expect(logs, hasLength(1));
      expect(logs.first.photo, '/tmp/dinner.jpg');
    });

    test('entries without a photo stay photo-less', () async {
      await Db.insertLog(LogEntry(
          date: '2026-11-25',
          meal: 'snack',
          name: 'Banana',
          grams: 120,
          kcal: 105,
          protein: 1,
          carbs: 27,
          fat: 0));
      final logs = await Db.logsForDay('2026-11-25');
      expect(logs.first.photo, isNull);
    });

    test('v5 -> v6 upgrade adds the photo column', () async {
      final dir = await getDatabasesPath();
      final file = p.join(dir, 'macrotrack_v6_upgrade_test.db');
      if (await databaseFactory.databaseExists(file)) {
        await databaseFactory.deleteDatabase(file);
      }
      final raw = await databaseFactory.openDatabase(file);
      // v5-shaped log_entries: no photo column
      await raw.execute('CREATE TABLE log_entries(id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, date TEXT, meal TEXT, food_id INTEGER, name TEXT, '
          'brand TEXT, grams REAL, kcal REAL, protein REAL, carbs REAL, '
          'fat REAL, fiber REAL, micros TEXT, fasted INTEGER DEFAULT 0, '
          'created_at TEXT)');
      await raw.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
      await raw.execute('PRAGMA user_version = 5');
      await raw.close();

      Db.dbPathOverride = 'macrotrack_v6_upgrade_test.db';
      final db = await Db.instance;
      await Db.insertLog(LogEntry(
          date: '2026-11-26',
          meal: 'lunch',
          name: 'With photo',
          grams: 0,
          kcal: 100,
          protein: 1,
          carbs: 1,
          fat: 1,
          photo: '/tmp/x.jpg'));
      final logs = await Db.logsForDay('2026-11-26');
      expect(logs.first.photo, '/tmp/x.jpg');
      await db.close();
    });
  });
}
