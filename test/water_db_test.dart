// DB-layer tests for water tracking (dashboard Water card): addWater must
// accumulate per day, clamp at 0/10000, and be independently settable.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_water_test.db';
    await Db.resetForTest();
    final dir = await getDatabasesPath();
    final file = p.join(dir, Db.dbPathOverride!);
    if (await databaseFactory.databaseExists(file)) {
      await databaseFactory.deleteDatabase(file);
    }
  });

  test('addWater accumulates per day and returns the running total',
      () async {
    expect(await Db.waterMl('2026-11-20'), 0);
    expect(await Db.addWater('2026-11-20', 250), 250);
    expect(await Db.addWater('2026-11-20', 500), 750);
    expect(await Db.addWater('2026-11-20', 250), 1000);
    // Other days are independent.
    expect(await Db.waterMl('2026-11-19'), 0);
    expect(await Db.addWater('2026-11-19', 100), 100);
    expect(await Db.waterMl('2026-11-20'), 1000);
  });

  test('addWater clamps at zero on undo and never below', () async {
    expect(await Db.addWater('2026-11-20', 250), 250);
    expect(await Db.addWater('2026-11-20', -250), 0);
    expect(await Db.addWater('2026-11-20', -250), 0);
  });

  test('setWaterMl overwrites the total', () async {
    await Db.addWater('2026-11-20', 750);
    await Db.setWaterMl('2026-11-20', 1500);
    expect(await Db.waterMl('2026-11-20'), 1500);
    await Db.setWaterMl('2026-11-20', -5);
    expect(await Db.waterMl('2026-11-20'), 0);
  });
}
