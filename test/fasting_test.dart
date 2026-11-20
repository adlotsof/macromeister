// Fasting timer service tests: start/end lifecycle, history integrity,
// elapsed computation across midnight, and duration formatting.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/services/fasting.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_fasting_test.db';
    await Db.resetForTest();
    final dir = await getDatabasesPath();
    final file = p.join(dir, Db.dbPathOverride!);
    if (await databaseFactory.databaseExists(file)) {
      await databaseFactory.deleteDatabase(file);
    }
  });

  test('start/elapsed/end lifecycle', () async {
    final start = DateTime(2026, 11, 20, 20, 0); // 20:00
    expect(await FastingService.isRunning(), isFalse);
    await FastingService.start(start);
    expect(await FastingService.isRunning(), isTrue);

    // Elapsed across midnight: 20:00 -> next day 04:30 = 8.5 h.
    final elapsed =
        await FastingService.elapsed(DateTime(2026, 11, 21, 4, 30));
    expect(elapsed!.inMinutes, 510);

    // start is a no-op while running.
    await FastingService.start(DateTime(2026, 11, 21, 5, 0));
    final still =
        await FastingService.elapsed(DateTime(2026, 11, 21, 5, 0));
    expect(still!.inMinutes, 540); // 9 h from the ORIGINAL start

    // End records to history and clears the marker.
    final duration =
        await FastingService.end(DateTime(2026, 11, 21, 6, 0)); // 10 h
    expect(duration!.inHours, 10);
    expect(await FastingService.isRunning(), isFalse);
    expect(await FastingService.elapsed(DateTime(2026, 11, 21, 7, 0)), isNull);
    final h = await FastingService.history();
    expect(h, hasLength(1));
    expect(h.first.end.difference(h.first.start).inHours, 10);
  });

  test('end with no running fast returns null and writes nothing', () async {
    expect(await FastingService.end(DateTime(2026, 11, 20, 12)), isNull);
    expect(await FastingService.history(), isEmpty);
  });

  test('history keeps newest first, capped at 30', () async {
    final base = DateTime(2026, 11, 1, 8);
    for (var i = 0; i < 35; i++) {
      final s = base.add(Duration(days: i));
      await FastingService.start(s);
      await FastingService.end(s.add(const Duration(hours: 16)));
    }
    final h = await FastingService.history();
    expect(h, hasLength(30));
    // Newest first: the last completed fast (Nov 35th ≈ Dec 4) is first.
    expect(h.first.start.isAfter(h.last.start), isTrue);
    // Each recorded fast is 16 h.
    for (final e in h) {
      expect(e.end.difference(e.start).inHours, 16);
    }
  });

  test('history garbage input yields empty list, never throws', () async {
    await Db.setSetting('fasting_history', 'garbage{{{');
    expect(await FastingService.history(), isEmpty);
    await Db.setSetting('fasting_history', '{"not":"a list"}');
    expect(await FastingService.history(), isEmpty);
  });

  test('fmtDuration formats hours+minutes and minutes-only', () {
    expect(FastingService.fmtDuration(const Duration(hours: 16, minutes: 42)),
        '16h 42m');
    expect(FastingService.fmtDuration(const Duration(minutes: 42)), '42m');
  });
}
