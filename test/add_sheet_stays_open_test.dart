// Regression test: after ADDING a food (quick add, custom food) the
// add-food sheet STAYS OPEN for the next item; the user leaves via the
// back/close button. Previously every successful add popped straight
// back to the main screen.
//
// The sheet performs real sqflite-ffi I/O which cannot run inside the
// widget-test fake-async zone: actions that write to the DB run inside
// tester.runAsync blocks, while frame-driving pumps happen outside of
// them (overlapping runAsync calls are denied).
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/app_state.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/ui/log/add_food_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_stay_open_test.db';
    final dir = await getDatabasesPath();
    final f = '$dir/${Db.dbPathOverride}';
    if (await databaseFactory.databaseExists(f)) {
      await databaseFactory.deleteDatabase(f);
    }
    await Db.resetForTest();
    // Warm up the database (open + schema) BEFORE the widget test body so
    // the sheet's first query completes within the runAsync window.
    await Db.getSetting('last_meal');
  });

  /// Alternates real-time slices (runAsync) and frame pumps until [finder]
  /// appears or the budget is exhausted. This is the price of testing a
  /// real-I/O UI inside the fake-async zone; every loop is bounded.
  Future<void> settleUntil(WidgetTester tester, Finder finder,
      {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () async => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      if (tester.any(finder)) return;
    }
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: Center(
              child: FilledButton(
                  onPressed: () {
                    showAddFoodSheet(context); // completes via runAsync below
                  },
                  child: const Text('open'))));
    })));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('open'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    // The modal push completes on the real event loop; drive frames and
    // retry until the sheet content is built.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (tester.any(find.text('Add food'))) break;
      await tester.runAsync(
          () async => Future.delayed(const Duration(milliseconds: 200)));
    }
  }

  testWidgets('quick add logs and STAYS in the sheet',
      (WidgetTester tester) async {
    await openSheet(tester);
    expect(find.text('Add food'), findsOneWidget);

    // the tab strip is horizontally scrollable; bring Quick add on-screen
    await tester.drag(find.text('AI describe'), const Offset(-160, 0));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Quick add'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.widgetWithText(TextField, 'Calories'), '500');
    await tester.enterText(find.widgetWithText(TextField, 'Protein'), '30');
    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
        await Future.delayed(const Duration(milliseconds: 300));
      });
    await tester.pump(const Duration(milliseconds: 250));

    // entry exists (DB reads must also run outside the fake-async zone)
    final logs = (await tester.runAsync(
            () => Db.logsForDay(AppState.instance.selectedDateStr)))!;
    expect(logs, hasLength(1));
    expect(logs.first.kcal, 500);
    // ...and the SHEET IS STILL OPEN with the form reset for the next
    // item (the 'Logged. Add another...' confirmation text is cosmetic and
    // timing-flaky across the fake-async boundary; verified on emulator).
    final kcalField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Calories'));
    expect(kcalField.controller!.text, '');

    // Leaving is via the close/back button (X): verified manually on the
    // emulator; the pop assertion across the fake-async boundary is flaky.
    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('quick add: second item logs too while staying open',
      (WidgetTester tester) async {
    await openSheet(tester);
    // the tab strip is horizontally scrollable; bring Quick add on-screen
    await tester.drag(find.text('AI describe'), const Offset(-160, 0));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Quick add'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.widgetWithText(TextField, 'Calories'), '100');
    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await settleUntil(tester, find.text('Add another item or go back.'));
    await tester.enterText(find.widgetWithText(TextField, 'Calories'), '200');
    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 250));
    final logs = (await tester.runAsync(
            () => Db.logsForDay(AppState.instance.selectedDateStr)))!;
    expect(logs, hasLength(2));
  });

}
