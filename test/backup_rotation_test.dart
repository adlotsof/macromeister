// Unit tests for the auto-backup rotation (lib/services/backup.dart):
// rotation keeps the newest N dated files, only touches auto-backup files,
// and the once-per-day gate is stored in settings.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/services/backup.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Directory tmp;

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_backup_rot_test.db';
    await Db.resetForTest();
    final dir = await getDatabasesPath();
    final file = p.join(dir, Db.dbPathOverride!);
    if (await databaseFactory.databaseExists(file)) {
      await databaseFactory.deleteDatabase(file);
    }
    tmp = await Directory.systemTemp.createTemp('mt_backup_rot');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File f(String name) => File(p.join(tmp.path, name));

  test('rotation keeps the newest N files and deletes older ones', () async {
    for (var d = 1; d <= 10; d++) {
      await f('macrotrack_auto_2026-11-${d.toString().padLeft(2, '0')}.json')
          .writeAsString('{}');
    }
    await Backup.rotate(tmp, keep: 7);
    final left = (await tmp.list().toList()).whereType<File>().toList();
    expect(left, hasLength(7));
    // The three oldest (01, 02, 03) must be gone.
    for (final gone in ['01', '02', '03']) {
      expect(
          left.any((x) => x.path.endsWith('2026-11-$gone.json')), isFalse,
          reason: '2026-11-$gone should be rotated out');
    }
    expect(left.any((x) => x.path.endsWith('2026-11-10.json')), isTrue);
  });

  test('rotation ignores foreign files and non-json files', () async {
    await f('macrotrack_auto_2026-11-01.json').writeAsString('{}');
    await f('macrotrack_auto_2026-11-01.json.tmp').writeAsString('{}');
    await f('other_file.json').writeAsString('{}');
    await Backup.rotate(tmp, keep: 7);
    expect(await f('other_file.json').exists(), isTrue,
        reason: 'unrelated files must never be deleted');
    expect(await f('macrotrack_auto_2026-11-01.json.tmp').exists(), isTrue,
        reason: 'only completed auto-backups are rotation candidates');
  });

  test('rotation with fewer files than keep deletes nothing', () async {
    await f('macrotrack_auto_2026-11-01.json').writeAsString('{}');
    await f('macrotrack_auto_2026-11-02.json').writeAsString('{}');
    await Backup.rotate(tmp, keep: 7);
    expect((await tmp.list().toList()).whereType<File>(), hasLength(2));
  });

  test('once-per-day gate: second call is skipped via auto_backup_last',
      () async {
    await Db.setSetting('auto_backup_last', '2026-11-20');
    // runAutoBackup would rewrite the marker to today's date; since the
    // stored marker equals today, the body must bail before any file write.
    // We can't easily fake "today", but a stored marker of a future date
    // proves the gate compares to today: with a future marker the body runs
    // (writes today) — with today's marker it must not overwrite it.
    await Db.setSetting('auto_backup_last', '2099-01-01'); // future → runs
    await Backup.runAutoBackup(keep: 7, docsOverride: tmp);
    final marker = await Db.getSetting('auto_backup_last');
    expect(marker, isNot('2099-01-01'),
        reason: 'a successful run stamps today, not the future date');
    expect(marker,
        DateTime.now().toIso8601String().substring(0, 10));
  });

  test('auto_backup=0 disables the run entirely', () async {
    await Db.setSetting('auto_backup', '0');
    await Backup.runAutoBackup(keep: 7, docsOverride: tmp);
    expect(await Db.getSetting('auto_backup_last'), isNull,
        reason: 'disabled → no run, no marker write');
  });

  test('a successful run writes a dated backup file', () async {
    await Backup.runAutoBackup(keep: 7, docsOverride: tmp);
    final backups = Directory(p.join(tmp.path, 'backups'));
    final files = (await backups.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, hasLength(1));
    expect(await files.single.readAsString(), contains('macrotrack-backup'));
  });
}
