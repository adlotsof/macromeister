// Minimal, producer-tolerant .xlsx reader.
//
// Replaces the `excel` package, whose parser crashed with
// "Null check operator used on a null value" (Parser._parseTable) on
// standard workbooks written by openpyxl / MacroFactor's exporter.
// This reader only relies on the OOXML spec: zip archive, workbook sheet
// list, relationships, shared strings, styles (for date detection) and
// worksheet cell tables.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxBook {
  /// Sheet name -> rows of cell values (String, num, DateTime, bool or null).
  /// Row 0 is the header row.
  final Map<String, List<List<Object?>>> tables;
  XlsxBook(this.tables);
}

class XlsxReader {
  static XlsxBook decodeBytes(Uint8List bytes) => _parse(bytes);

  static XlsxBook decodeFile(String path) =>
      _parse(File(path).readAsBytesSync());

  static const _empty = '';

  static XlsxBook _parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String entryText(String name) {
      for (final f in archive.files) {
        if (f.name == name) {
          return utf8.decode(f.content as List<int>, allowMalformed: true);
        }
      }
      return _empty;
    }

    ArchiveFile findEntry(String name) {
      for (final f in archive.files) {
        if (f.name == name) return f;
      }
      throw ArgumentError('xlsx: missing entry $name');
    }

    // ---- sheet name -> target ----
    final relsXml = entryText('xl/_rels/workbook.xml.rels');
    final rels = <String, String>{};
    for (final rel in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
      rels[rel.getAttribute('Id') ?? ''] = rel.getAttribute('Target') ?? '';
    }
    final tables = <String, List<List<Object?>>>{};
    final wb = XmlDocument.parse(entryText('xl/workbook.xml'));
    for (final sheet in wb.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? '';
      final rid = sheet.getAttribute('r:id') ?? '';
      final target = rels[rid] ?? '';
      if (target.isEmpty) continue;
      final wanted = target.startsWith('/')
          ? target.substring(1)
          : 'xl/$target'; // e.g. xl/worksheets/sheet1.xml
      String path;
      try {
        findEntry(wanted);
        path = wanted;
      } on ArgumentError {
        // Some producers differ in case/base dir; fall back to a suffix match.
        final suffix = wanted.split('/').last.toLowerCase();
        ArchiveFile? hit;
        for (final f in archive.files) {
          if (f.name.toLowerCase().endsWith(suffix) &&
              f.name.contains('worksheets')) {
            hit = f;
            break;
          }
        }
        if (hit == null) continue;
        path = hit.name;
      }

      // ---- shared strings ----
      final shared = <String>[];
      final ssXml = entryText('xl/sharedStrings.xml');
      if (ssXml.isNotEmpty) {
        for (final si in XmlDocument.parse(ssXml).findAllElements('si')) {
          final buf = StringBuffer();
          for (final t in si.descendants.whereType<XmlElement>()) {
            if (t.name.local == 't') buf.write(t.innerText);
          }
          shared.add(buf.toString());
        }
      }

      // ---- styles: which cell styles carry a date format ----
      final dateStyles = <String>{};
      final stylesXml = entryText('xl/styles.xml');
      if (stylesXml.isNotEmpty) {
        final st = XmlDocument.parse(stylesXml);
        final custom = <String, bool>{};
        for (final nf in st.findAllElements('numFmt')) {
          final code = (nf.getAttribute('formatCode') ?? '').toLowerCase();
          custom[nf.getAttribute('numFmtId') ?? ''] =
              code.contains('y') || code.contains('d') || code.contains('h');
        }
        // The cell's s="N" attribute indexes into cellXfs — a style is a
        // date style when the xf AT THAT INDEX has a date numFmt.
        for (final xfsEl in st.findAllElements('cellXfs')) {
          var i = 0;
          for (final xf in xfsEl.findElements('xf')) {
            final id = xf.getAttribute('numFmtId') ?? '0';
            final n = int.tryParse(id) ?? 0;
            final isDate = custom[id] ??
                ((n >= 14 && n <= 22) ||
                    (n >= 27 && n <= 36) ||
                    (n >= 45 && n <= 47));
            if (isDate) dateStyles.add('$i');
            i++;
          }
        }
      }

      // ---- worksheet rows ----
      final sheetXml = entryText(path);
      if (sheetXml.isEmpty) continue;
      final doc = XmlDocument.parse(sheetXml);
      final rows = <List<Object?>>[];
      for (final rowEl in doc.findAllElements('row')) {
        final cells = <Object?>[];
        var nextCol = 0;
        for (final c in rowEl.findElements('c')) {
          final ref = c.getAttribute('r') ?? '';
          final col = _colIndex(ref, nextCol);
          while (nextCol < col) {
            cells.add(null);
            nextCol++;
          }
          final style = c.getAttribute('s') ?? '';
          final type = c.getAttribute('t') ?? 'n';
          Object? value;
          if (type == 'inlineStr') {
            value = c.findAllElements('t').map((t) => t.innerText).join();
          } else {
            final vEl = c.findElements('v').isNotEmpty
                ? c.findElements('v').first.innerText
                : null;
            switch (type) {
              case 's':
                value = vEl == null ? null : shared[int.tryParse(vEl) ?? 0];
                break;
              case 'b':
                value = vEl == '1';
                break;
              case 'str':
                value = vEl ?? _empty;
                break;
              default:
                final num = double.tryParse(vEl ?? '');
                if (num == null) {
                  value = null;
                } else if (dateStyles.contains(style)) {
                  value = _serialToDateTime(num); // date-styled cell
                } else {
                  value = num.truncateToDouble() == num ? num.toInt() : num;
                }
            }
          }
          cells.add(value);
          nextCol++;
        }
        rows.add(cells);
      }
      if (name.isNotEmpty) tables[name] = rows;
    }
    return XlsxBook(tables);
  }

  static int _colIndex(String ref, int fallback) {
    var col = 0;
    var sawLetter = false;
    for (final rune in ref.runes) {
      final c = String.fromCharCode(rune);
      if (RegExp('[A-Za-z]').hasMatch(c)) {
        final upper = c.toUpperCase().codeUnitAt(0);
        col = col * 26 + (upper - 64);
        sawLetter = true;
      } else if (sawLetter) {
        break;
      }
    }
    return sawLetter ? col - 1 : fallback;
  }

  static DateTime _serialToDateTime(double serial) {
    final days = serial.floor();
    final frac = serial - days;
    final base = DateTime.utc(1899, 12, 30).add(Duration(days: days));
    return base.add(Duration(seconds: (frac * 86400).round())).toLocal();
  }
}
