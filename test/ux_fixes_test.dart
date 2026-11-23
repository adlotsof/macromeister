// ignore_for_file: deprecated_member_use -- material_ui replacement not published
// Regression tests for the UX-fix batch:
// 1. Search dedupe by name+brand (identical rows from My food/Common
//    foods/Open Food Facts collapsed; distinct names stay).
// 2. Log-entry photos survive Db.updateLog (the edit-entry sheet edit).
// 3. Data-sources screen attributes all THREE food datasets
//    (OFF/ODbL, USDA FNDDS, USDA SR Legacy) — the license requirement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:macrotrack/ui/more/data_sources_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Food _f(String name, String brand, {String? offId}) => Food(
    name: name,
    brand: brand,
    servingG: 100,
    kcal: 100,
    protein: 5,
    carbs: 10,
    fat: 2,
    source: 'test',
    offId: offId);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('search dedupe (name+brand)', () {
    test('identical food from two sources collapses to one row', () {
      final merged = dedupeFoodsByName([
        _f('Banana, raw', '', offId: null), // saved locally after first add
        _f('Banana, raw', ''), // same one from USDA common foods
        _f('Banana chips', ''),
      ]);
      expect(merged, hasLength(2));
      expect(merged.first.name, 'Banana, raw',
          reason: 'first occurrence (My food) wins');
      expect(merged.last.name, 'Banana chips');
    });

    test('distinct names stay even when close (Banana raw vs Bananas raw)',
        () {
      final merged = dedupeFoodsByName([
        _f('Banana, raw', ''),
        _f('Bananas, raw', ''),
      ]);
      expect(merged, hasLength(2));
    });

    test('case/whitespace variants of the same food collapse', () {
      final merged = dedupeFoodsByName([
        _f('banana, raw', ''),
        _f('Banana,  Raw', ' '),
      ]);
      expect(merged, hasLength(1));
    });

    test('same name with different brands are separate foods', () {
      final merged = dedupeFoodsByName([
        _f('Mozzarella', 'Lidl'),
        _f('Mozzarella', 'Galbani'),
      ]);
      expect(merged, hasLength(2));
    });
  });

  group('edit-entry keeps the meal photo', () {
    setUp(() async {
      Db.dbPathOverride = 'macrotrack_edit_photo_test.db';
      final dir = await getDatabasesPath();
      final f = '$dir/${Db.dbPathOverride}';
      if (await databaseFactory.databaseExists(f)) {
        await databaseFactory.deleteDatabase(f);
      }
      await Db.resetForTest();
    });

    test('updateLog preserves an attached photo', () async {
      await Db.insertLog(LogEntry(
          date: '2026-11-23',
          meal: 'lunch',
          name: 'Custom soup',
          grams: 0,
          kcal: 250,
          protein: 12,
          carbs: 30,
          fat: 5,
          photo: '/tmp/soup.jpg'));
      final e = (await Db.logsForDay('2026-11-23')).first;
      await Db.updateLog(LogEntry(
          id: e.id,
          date: e.date,
          meal: e.meal,
          name: e.name,
          brand: e.brand,
          grams: e.grams,
          kcal: 300,
          protein: e.protein,
          carbs: e.carbs,
          fat: e.fat,
          fiber: e.fiber,
          fasted: e.fasted,
          photo: e.photo));
      final after = (await Db.logsForDay('2026-11-23')).first;
      expect(after.kcal, 300);
      expect(after.photo, '/tmp/soup.jpg',
          reason: 'editing macros must not lose the meal photo');
    });

    test('updateLog can remove the photo', () async {
      await Db.insertLog(LogEntry(
          date: '2026-11-24',
          meal: 'dinner',
          name: 'Custom dinner',
          grams: 0,
          kcal: 400,
          protein: 10,
          carbs: 40,
          fat: 10,
          photo: '/tmp/dinner.jpg'));
      final e = (await Db.logsForDay('2026-11-24')).first;
      await Db.updateLog(LogEntry(
          id: e.id,
          date: e.date,
          meal: e.meal,
          name: e.name,
          brand: e.brand,
          grams: e.grams,
          kcal: e.kcal,
          protein: e.protein,
          carbs: e.carbs,
          fat: e.fat,
          fiber: e.fiber,
          fasted: e.fasted,
          photo: null));
      final after = (await Db.logsForDay('2026-11-24')).first;
      expect(after.photo, isNull);
    });
  });

  group('data sources screen: three attributed datasets', () {
    testWidgets('lists OFF/ODbL, USDA FNDDS and USDA SR Legacy',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: DataSourcesScreen()));
      await tester.pump();
      expect(find.text('Open Food Facts', skipOffstage: false), findsOneWidget);
      // the ListView builds lazily — scroll to reach the lower blocks
      await tester.scrollUntilVisible(
          find.textContaining('Central — SR Legacy'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      // title-only match (the body text mentions the datasets without the dash)
      expect(find.textContaining('Central — FNDDS', skipOffstage: false),
          findsOneWidget);
      expect(find.textContaining('Central — SR Legacy', skipOffstage: false),
          findsOneWidget);
      
      // license statements present
      expect(find.textContaining('ODbL', skipOffstage: false), findsWidgets);
      expect(find.textContaining('CC0 1.0 Universal', skipOffstage: false),
          findsNWidgets(2));
    });
  });
}
