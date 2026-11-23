// MANUAL reproduction harness for a REAL MacroFactor export on disk.
// Skips silently when the export file is not present (never committed).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/services/mf_xlsx_import.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    Db.dbPathOverride = 'macrotrack_mf_real_test.db';
    await Db.resetForTest();
  });
  test('imports real MF export', () async {
    const src = '/Users/sonnenbergt/Repos/myfactor/MacroFactor-20261118192136.xlsx';
    final f = File(src);
    // ignore: avoid_print
    if (!f.existsSync()) { print('SKIP: export not present'); return; }
    final dir = await getDatabasesPath();
    final dst = p.join(dir, 'mf_export.xlsx');
    f.copySync(dst);
    final r = await MfXlsx.importFile(dst);
    // ignore: avoid_print
    print('RESULT w=${r.weights} log=${r.loggedDays} food=${r.customFoods} '
        'rec=${r.recipes} skipped=${r.skipped} note=${r.profileNote}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
