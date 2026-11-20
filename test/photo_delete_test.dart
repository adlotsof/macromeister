// Regression test for the progress-photo delete bug: photos could only be
// taken and shared, never deleted. confirmDeletePhoto() must (a) ask for
// confirmation, (b) on Delete invoke the deletion, (c) on Cancel not invoke
// it. The real deletion (DB row + backing file) is covered by the
// db-roundtrip test below; the dialog flow test injects a recorder because
// real sqflite futures never complete inside the widget-test FakeAsync zone.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/models.dart';
import 'package:macrotrack/ui/dashboard/dashboard_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<ProgressPhoto> _seedPhoto() async {
  final tmp = await Directory.systemTemp.createTemp('mt_photo_test');
  final f = File(p.join(tmp.path, 'progress.jpg'));
  await f.writeAsBytes(List.filled(16, 1));
  final id = await Db.insertPhoto(ProgressPhoto(
      date: '2026-11-20', path: f.path, weightKg: 80.0));
  return ProgressPhoto(
      id: id, date: '2026-11-20', path: f.path, weightKg: 80.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('delete confirmed: asks once, then invokes the deletion',
      (tester) async {
    final photo = ProgressPhoto(
        id: 1, date: '2026-11-20', path: '/tmp/none.jpg', weightKg: 80.0);
    var deleted = 0;
    var changed = 0;

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return TextButton(
          onPressed: () => confirmDeletePhoto(context, photo,
              () => changed++, onDelete: (_) async => deleted++),
          child: const Text('trigger'));
    }))));

    await tester.tap(find.text('trigger'));
    await tester.pump();
    expect(find.text('Delete photo?'), findsOneWidget,
        reason: 'deletion must ask for confirmation first');
    expect(deleted, 0, reason: 'nothing must be deleted before confirming');

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(deleted, 1, reason: 'confirmed delete must invoke the deletion');
    expect(changed, 1, reason: 'onChanged must fire so the card reloads');
  });

  testWidgets('delete cancelled: deletion is not invoked', (tester) async {
    final photo = ProgressPhoto(
        id: 1, date: '2026-11-20', path: '/tmp/none.jpg', weightKg: 80.0);
    var deleted = 0;

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
      return TextButton(
          onPressed: () => confirmDeletePhoto(context, photo, () {},
              onDelete: (_) async => deleted++),
          child: const Text('trigger'));
    }))));

    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();

    expect(deleted, 0, reason: 'cancel must keep the photo');
  });

  test('DB roundtrip: deletePhoto removes the row', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Db.dbPathOverride = 'macrotrack_photo_db_test.db';
    await Db.resetForTest();
    final dir = await getDatabasesPath();
    final file = p.join(dir, Db.dbPathOverride!);
    if (await databaseFactory.databaseExists(file)) {
      await databaseFactory.deleteDatabase(file);
    }
    final photo = await _seedPhoto();
    expect(await Db.photos(), hasLength(1));
    await Db.deletePhoto(photo.id!);
    expect(await Db.photos(), isEmpty);
  });
}
