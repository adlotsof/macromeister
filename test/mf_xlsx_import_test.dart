// Regression test for the MacroFactor Excel import.
//
// The `excel` package's parser crashed with "Null check operator used on a
// null value" (Parser._parseTable) on xlsx files written by openpyxl /
// MacroFactor's exporter — i.e. on every real MF export. The importer now
// uses the in-repo XlsxReader; this test BUILDS a MacroFactor-format
// workbook in memory (real datetime cells, openpyxl-style structure) and
// asserts the import result, so a parser regression can't ship silently.
//
// The fixture is generated, never committed (binary test files are noise in
// git and the repo must stay free of anything resembling an MF export).
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/db.dart';
import 'package:macrotrack/services/mf_xlsx_import.dart';
import 'package:macrotrack/services/xlsx_reader.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
</Types>''';

const _rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

const _workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
<sheet name="User Profile" sheetId="1" r:id="rId1"/>
<sheet name="Scale Weight" sheetId="2" r:id="rId2"/>
<sheet name="Custom Foods" sheetId="3" r:id="rId3"/>
<sheet name="Recipes" sheetId="4" r:id="rId4"/>
<sheet name="Calories &amp; Macros" sheetId="5" r:id="rId5"/>
<sheet name="Nutrition Program Settings" sheetId="6" r:id="rId6"/>
</sheets>
</workbook>''';

const _wbRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/>
<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet5.xml"/>
<Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet6.xml"/>
</Relationships>''';

// Date-styled column A (custom numFmt with y/d, like MacroFactor's exporter
// writes its Date columns).
const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/></numFmts>
<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="164"/></cellXfs>
</styleSheet>''';

/// rows: first entry is the header row. Date cells are raw serials with
/// style s="1" (matches how Excel/openpyxl store datetime values).
String _sheetXml(List<List<Object?>> rows) {
  final b = StringBuffer();
  b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
  b.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
  for (var ri = 0; ri < rows.length; ri++) {
    b.write('<row r="${ri + 1}">');
    for (var ci = 0; ci < rows[ri].length; ci++) {
      final v = rows[ri][ci];
      final ref = '${String.fromCharCode(65 + ci)}${ri + 1}';
      if (v == null) continue;
      if (v is DateTime) {
        final serial =
            v.toUtc().difference(DateTime.utc(1899, 12, 30)).inDays;
        b.write('<c r="$ref" s="1"><v>$serial</v></c>');
      } else if (v is num) {
        b.write('<c r="$ref"><v>$v</v></c>');
      } else {
        final t = v
            .toString()
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');
        b.write('<c r="$ref" t="inlineStr"><is><t>$t</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

/// Builds a MacroFactor-format workbook at [path]. Returns the bytes.
Uint8List _buildMfWorkbook(String path) {
  final archive = Archive();
  void add(String name, String content) =>
      archive.add(ArchiveFile.string(name, content));
  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rels);
  add('xl/workbook.xml', _workbook);
  add('xl/_rels/workbook.xml.rels', _wbRels);
  add('xl/styles.xml', _styles);
    add('xl/worksheets/sheet1.xml',
        _sheetXml([
          ['Field', 'Value'],
          ['Name', 'Tim'],
          ['Sex', 'Male'],
          ['Birthday', DateTime(1987, 8, 29)],
          ['Height (cm)', 178],
          ['Activity Level', 'Moderate'],
        ]));
    add('xl/worksheets/sheet2.xml',
        _sheetXml([
          ['Date', 'Weight (kg)'],
          [DateTime(2026, 11, 1), 84.4],
          [DateTime(2026, 11, 8), 83.9],
        ]));
    add('xl/worksheets/sheet3.xml',
        _sheetXml([
          ['Food Name', 'Serving Weight (g)', 'Calories (kcal)', 'Protein (g)',
           'Carbs (g)', 'Fat (g)'],
          ['Test custom food', 100, 200, 20, 10, 8],
        ]));
    add('xl/worksheets/sheet4.xml',
        _sheetXml([
          ['Recipe Name'],
          ['Test recipe'],
        ]));
    add('xl/worksheets/sheet5.xml',
        _sheetXml([
          ['Date', 'Calories (kcal)', 'Protein (g)', 'Carbs (g)', 'Fat (g)'],
          [DateTime(2026, 11, 1), 2200, 160, 200, 70],
        ]));
    add('xl/worksheets/sheet6.xml',
        _sheetXml([
          ['K', 'V'],
        ]));
  final zip = ZipEncoder().encode(archive);
  File(path).writeAsBytesSync(zip);
  return Uint8List.fromList(zip);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Db.dbPathOverride = 'macrotrack_mfxlsx_test.db';
    await Db.resetForTest();
    final dir = await getDatabasesPath();
    final file = p.join(dir, Db.dbPathOverride!);
    if (await databaseFactory.databaseExists(file)) {
      await databaseFactory.deleteDatabase(file);
    }
  });

  final tmp = '${Directory.systemTemp.path}/mf_test_export.xlsx';

  test('XlsxReader decodes a MacroFactor-format workbook with date cells',
      () {
    _buildMfWorkbook(tmp);
    final book = XlsxReader.decodeFile(tmp);
    expect(book.tables.keys, containsAll([
      'User Profile', 'Scale Weight', 'Custom Foods', 'Recipes',
      'Calories & Macros',
    ]));
    final weights = book.tables['Scale Weight']!;
    expect(weights.length, 3); // header + 2 rows
    // Date cells decode to DateTime (style-based detection).
    expect(weights[1][0], isA<DateTime>());
  });

  test('MfXlsx.importFile imports the MF export end to end', () async {
    _buildMfWorkbook(tmp);
    final r = await MfXlsx.importFile(tmp);
    expect(r.weights, 2); // Scale Weight rows
    expect(r.loggedDays, 1); // Calories & Macros rows
    expect(r.customFoods, 1);
    expect(r.recipes, 1);
    expect(r.profileNote, contains('User Profile'));
  });

}
