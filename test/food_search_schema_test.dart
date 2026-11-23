// Regression test: token search must work on BOTH bundled-DB schemas.
// The micronutrients feature added a `micros` column to the foods tables,
// but devices still hold copies built by the older asset builders (the
// schema version markers force a re-copy only when a NEW bundle ships).
// _tokenSearch must fall back to a micros-less query instead of throwing
// "no such column: micros" (which broke search entirely on those installs).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _oldFoods = '''
CREATE TABLE foods (
  code TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, country TEXT,
  serving_g REAL, kcal REAL, protein REAL, carbs REAL,
  fat REAL, fiber REAL)
''';
const _newFoods = '''
CREATE TABLE foods (
  code TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, country TEXT,
  serving_g REAL, kcal REAL, protein REAL, carbs REAL,
  fat REAL, fiber REAL, micros TEXT)
''';

Future<void> _seed(String dbName, String markerName, String createSql,
    List<List<Object?>> rows) async {
  final dir = await getDatabasesPath();
  final file = p.join(dir, dbName);
  if (await databaseFactory.databaseExists(file)) {
    await databaseFactory.deleteDatabase(file);
  }
  final db = await databaseFactory.openDatabase(file);
  await db.execute(createSql);
  for (final r in rows) {
    await db.execute(
        'INSERT INTO foods VALUES (${List.filled(r.length, '?').join(',')})', r);
  }
  await db.close();
  // Version marker present -> foodsDb()/commonDb() open the seeded file
  // instead of attempting the (test-impossible) asset copy.
  await File(p.join(dir, markerName)).writeAsString('seed', flush: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_schema_test.db';
    await Db.resetForTest();
    final dir = await getDatabasesPath();
    // Remove seeds + markers so each test starts clean.
    for (final name in [
      'foods_off.db', 'foods_off.db.v5',
      'foods_common.db', 'foods_common.db.v3',
    ]) {
      final f = File(p.join(dir, name));
      if (f.existsSync()) f.deleteSync();
    }
  });

  test('searchOffLocal works on the OLD schema (no micros column)', () async {
    await _seed('foods_off.db', 'foods_off.db.v5', _oldFoods, [
      ['1', 'Banana raw', '', 'usda', 120, 105.0, 1.3, 27.0, 0.4, 3.1],
      ['2', 'Lidl Mozzarella light', 'Lidl', 'de', 100, 254.0, 19.0, 2.0, 19.0, 0.0],
    ]);
    final res = await Db.searchOffLocal('banana');
    expect(res, hasLength(1));
    expect(res.first.name, 'Banana raw');
    expect(res.first.micros, isEmpty); // schema has no micros -> untracked
    final brand = await Db.searchOffLocal('lidl mozzarella');
    expect(brand, hasLength(1));
    expect(brand.first.name, contains('Mozzarella'));
  });

  test('searchOffLocal works on the NEW schema (micros column present)',
      () async {
    await _seed('foods_off.db', 'foods_off.db.v5', _newFoods, [
      ['1', 'Banana raw', '', 'usda', 120, 105.0, 1.3, 27.0, 0.4, 3.1,
       '{"potassium_mg":358}'],
    ]);
    final res = await Db.searchOffLocal('banana');
    expect(res, hasLength(1));
    expect(res.first.micros, isNotEmpty);
    expect(res.first.micros['potassium_mg'], 358.0);
  });

  test('searchCommonLocal works on the OLD schema', () async {
    await _seed('foods_common.db', 'foods_common.db.v3', _oldFoods, [
      ['usda-1', 'Chicken breast grilled', '', 'usda', 100, 165.0, 31.0, 0.0, 3.6, 0.0],
    ]);
    final res = await Db.searchCommonLocal('chicken');
    expect(res, hasLength(1));
    expect(res.first.name, 'Chicken breast grilled');
  });
}
