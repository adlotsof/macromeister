// Regression tests for the food-search speed/accuracy rework.
//
// Speed: bundled DBs carry an FTS5 index (foods_fts) built by
// tools/build_*_db.py; search joins it by rowid instead of running two
// full-table LIKE scans over 4.57M rows per keystroke.
// Accuracy: boolean token AND + last-token prefix matching
// ("lidl mozz" finds Lidl mozzarella), bm25 relevance, real nutrition
// data ranked first. Databases WITHOUT the index keep working via the
// legacy LIKE fallback path.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _buildTestDb(String name, {bool withFts = true}) async {
  final dir = await getDatabasesPath();
  final path = '$dir/$name';
  if (await databaseFactory.databaseExists(path)) {
    await databaseFactory.deleteDatabase(path);
  }
  final db = await databaseFactory.openDatabase(path);
  await db.execute('CREATE TABLE foods(code TEXT, name TEXT, brand TEXT, '
      'country TEXT, serving_g REAL, kcal REAL, protein REAL, carbs REAL, '
      'fat REAL, fiber REAL, micros TEXT)');
  final rows = [
    ['1', 'Mozzarella, whole milk', 'Galbani', 'US', 125.0, 250.0, 18.0, 2.0, 12.0, 0.0, null],
    ['2', 'Mozzarella light', 'Lidl', 'DE', 125.0, 200.0, 22.0, 2.5, 10.0, 0.0, null],
    ['3', 'Mozzarella Grated', 'Lidl', 'DE', 100.0, 300.0, 24.0, 3.0, 20.0, 0.0, null],
    ['4', 'No-name Mozzarella', null, 'DE', 100.0, 260.0, 20.0, 2.0, 15.0, 0.0, null],
    ['5', 'Cheddar mild', 'Anchor', 'NZ', 100.0, 400.0, 25.0, 2.0, 33.0, 0.0, null],
    // kcal == NULL: name-only row must rank LAST
    ['6', 'Mozzarella entries unknown', 'MegaBrand', 'XX', 100.0, null, null, null, null, null, null],
  ];
  for (final r in rows) {
    await db.execute('INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?)', r);
  }
  if (withFts) {
    await db.execute("CREATE VIRTUAL TABLE foods_fts USING fts5(name, brand, "
        "content='foods', content_rowid='rowid')");
    await db.execute("INSERT INTO foods_fts(foods_fts) VALUES ('rebuild')");
  }
  return db;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ftsMatchQuery', () {
    test('AND semantics with last-token prefix', () {
      expect(Db.ftsMatchQuery('lidl mozz'), 'lidl mozz*');
      expect(Db.ftsMatchQuery('banana'), 'banana*');
    });
    test('strips FTS operator characters and empties', () {
      expect(Db.ftsMatchQuery('lidl "moz*z" ()'), 'lidl mozz*');
      expect(Db.ftsMatchQuery('   '), '');
      expect(Db.ftsMatchQuery('*'), '');
    });
  });

  group('FTS fast path', () {
    late Database db;
    setUp(() async => db = await _buildTestDb('fts_test.db'));

    test('multi-token query: both tokens required, prefix on last', () async {
      final rows = await Db.tokenSearch(db, 'lidl mozz');
      final names = rows.map((r) => r['name']).toList();
      expect(names, containsAll(['Mozzarella light', 'Mozzarella Grated']));
      expect(names, isNot(contains('Cheddar mild')));
      expect(names, isNot(contains('Mozzarella, whole milk')),
          reason: 'Galbani does not match the lidl token');
    });

    test('single-token prefix search finds completions', () async {
      final rows = await Db.tokenSearch(db, 'mozza');
      for (final r in rows) {
        expect((r['name'] as String).toLowerCase(), contains('mozzarella'));
      }
      expect(rows, isNotEmpty);
    });

    test('rows with kcal rank before name-only rows', () async {
      final rows = await Db.tokenSearch(db, 'mozzarella');
      expect(rows.last['name'], 'Mozzarella entries unknown',
          reason: 'no nutrition data -> last');
    });

    test('brand hit ranks above generic name hit', () async {
      final rows = await Db.tokenSearch(db, 'lidl');
      expect(rows.first['brand'], 'Lidl');
    });

    test('limit respected', () async {
      final rows = await Db.tokenSearch(db, 'mozzarella');
      expect(rows.length, lessThanOrEqualTo(40));
    });
  });

  group('legacy LIKE fallback', () {
    late Database db;
    setUp(() async => db = await _buildTestDb('like_test.db', withFts: false));

    test('still returns results on databases without foods_fts', () async {
      final rows = await Db.tokenSearch(db, 'lidl mozz');
      expect(rows.map((r) => r['name'] as String),
          contains('Mozzarella light'));
    });
  });

}

