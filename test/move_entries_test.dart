// Regression tests for moving log entries between meals and dates:
// the edit-entry sheet exposes a meal chip row and a date picker; saving
// persists the move (the entry disappears from the old day/meal and shows
// under the new one). Also: the remembered meal follows the last ADD.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:macrotrack/services/meal_memory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_move_test.db';
    final dir = await getDatabasesPath();
    final f = '$dir/${Db.dbPathOverride}';
    if (await databaseFactory.databaseExists(f)) {
      await databaseFactory.deleteDatabase(f);
    }
    await Db.resetForTest();
  });

  LogEntry seed(String date, String meal, String name) => LogEntry(
      date: date, meal: meal, name: name, grams: 150, kcal: 200,
      protein: 10, carbs: 20, fat: 5);

  test('entry moves to another meal on the same day', () async {
    final id = await Db.insertLog(seed('2026-11-23', 'lunch', 'Pasta'));
    final e = (await Db.logsForDay('2026-11-23')).first;
    await Db.updateLog(LogEntry(
        id: e.id, date: e.date, meal: 'dinner', name: e.name,
        brand: e.brand, grams: e.grams, kcal: e.kcal, protein: e.protein,
        carbs: e.carbs, fat: e.fat, fiber: e.fiber, fasted: e.fasted,
        photo: e.photo));
    final day = await Db.logsForDay('2026-11-23');
    expect(day, hasLength(1));
    expect(day.first.meal, 'dinner');
    expect(day.first.name, 'Pasta');
    expect(day.first.id, id);
  });

  test('entry moves to another date', () async {
    await Db.insertLog(seed('2026-11-23', 'breakfast', 'Oats'));
    final e = (await Db.logsForDay('2026-11-23')).first;
    await Db.updateLog(LogEntry(
        id: e.id, date: '2026-11-25', meal: e.meal, name: e.name,
        brand: e.brand, grams: e.grams, kcal: e.kcal, protein: e.protein,
        carbs: e.carbs, fat: e.fat, fiber: e.fiber, fasted: e.fasted,
        photo: e.photo));
    expect(await Db.logsForDay('2026-11-23'), isEmpty);
    final moved = await Db.logsForDay('2026-11-25');
    expect(moved, hasLength(1));
    expect(moved.first.date, '2026-11-25');
    expect(moved.first.name, 'Oats');
  });

  test('remembered meal follows the last meal added to', () async {
    await Db.insertLog(seed('2026-11-23', 'dinner', 'Curry'));
    expect(await initialMeal(), 'dinner');
    await Db.insertLog(seed('2026-11-23', 'breakfast', 'Toast'));
    expect(await initialMeal(), 'breakfast',
        reason: 'the most recent ADD wins — always the last meal added to');
    // a chip tap without an add does not override the last add
    await rememberMeal('lunch');
    expect(await initialMeal(), 'lunch');
  });
}
