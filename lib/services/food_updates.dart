// Incremental updates for the bundled Open Food Facts database.
//
// OFF publishes daily delta exports (JSONL, one full product JSON object per
// line) for the previous 14 days; the list of available files is in
// static.openfoodfacts.org/data/delta/index.txt. Filenames encode the UNIX
// timestamp range of the changes: products_<start>_<end>.jsonl.gz, and must be
// applied in alphabetical order. Deletions are NOT included in deltas (OFF
// limitation) — a fresh full dump is the only way to drop deleted products.
//
// We track the last applied end-timestamp in app settings and apply each newer
// delta file as an upsert into the local foods database.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../db.dart';

class FoodUpdateResult {
  final int appliedDeltas;
  final int rowsUpserted;
  final int lastTs;
  final String? error;
  FoodUpdateResult(this.appliedDeltas, this.rowsUpserted, this.lastTs,
      {this.error});
}

class FoodUpdates {
  static const _deltaBase =
      'https://static.openfoodfacts.org/data/delta/';

  /// Fetches the available delta list and applies every file newer than the
  /// last applied one. Applies each file immediately so a mid-download
  /// failure keeps progress.
  static Future<FoodUpdateResult> update({int maxFiles = 20}) async {
    final db = await Db.foodsDb();
    final lastTs = int.tryParse(
            await Db.getSetting('foods_delta_ts') ?? '') ??
        0;
    final http.Response index;
    try {
      index = await http
          .get(Uri.parse('$_deltaBase/index.txt'))
          .timeout(const Duration(minutes: 2));
    } catch (_) {
      return FoodUpdateResult(0, 0, lastTs, error: 'network');
    }
    if (index.statusCode != 200) {
      return FoodUpdateResult(0, 0, lastTs, error: 'HTTP ${index.statusCode}');
    }
    // Filenames: openfoodfacts_products_<start>_<end>.json.gz — apply in
    // name order (equals chronological order).
    final files = index.body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.endsWith('.json.gz'))
        .toList()
      ..sort();
    int applied = 0, rows = 0;
    int ts = lastTs;
    String? error;
    for (final name in files) {
      if (applied >= maxFiles) break;
      // end timestamp = last number in openfoodfacts_products_<start>_<end>.json.gz
      final m = RegExp(r'products_(\d+)_(\d+)\.json\.gz').firstMatch(name);
      if (m == null) continue;
      final endTs = int.parse(m.group(2)!);
      if (endTs <= lastTs) continue; // already applied
      final http.Response res;
      try {
        res = await http
            .get(Uri.parse('$_deltaBase$name'))
            .timeout(const Duration(minutes: 5));
      } catch (_) {
        error = 'network';
        break;
      }
      if (res.statusCode == 404) continue; // vanished from the 14-day window
      if (res.statusCode != 200) {
        error = 'HTTP ${res.statusCode}';
        break;
      }
      final List<int> plain;
      try {
        plain = gzip.decode(res.bodyBytes);
      } catch (_) {
        error = 'corrupt delta $name';
        break;
      }
      final n = await _applyJsonl(db, utf8.decode(plain, allowMalformed: true));
      rows += n;
      applied++;
      ts = endTs;
      await Db.setSetting('foods_delta_ts', '$ts');
    }
    if (applied > 0) {
      await Db.setSetting('foods_updated_at',
          DateTime.now().toIso8601String().substring(0, 10));
    }
    return FoodUpdateResult(applied, rows, ts, error: error);
  }

  static Future<int> _applyJsonl(Database db, String jsonl) async {
    int rows = 0;
    const batch = 2000;
    final batchArgs = <List<Object?>>[];
    for (final line in jsonl.split('\n')) {
      if (line.trim().isEmpty) continue;
      final Map<String, dynamic> p;
      try {
        p = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final name = ((p['product_name'] ?? p['product_name_en'] ?? '') as String)
          .trim();
      if (name.isEmpty || name.length > 120) continue;
      final nutr = (p['nutriments'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      double? _n(String key) {
        final v = nutr[key];
        if (v is num) {
          final d = v.toDouble();
          return (d >= 0 && d < 10000) ? d : null;
        }
        return null;
      }

      var kcal = _n('energy-kcal_100g');
      if (kcal == null) {
        final kj = _n('energy_100g');
        if (kj != null) kcal = kj / 4.184;
      }
      if (kcal != null && kcal <= 0) kcal = null;
      final brand = ((p['brands'] ?? '') as String).split(',').first.trim();
      final countries = (p['countries_tags'] as List? ?? const []);
      final country = countries.isEmpty
          ? ''
          : (countries.first as String).replaceFirst('en:', '').trim();
      double? _g(String key) {
        final v = p[key];
        if (v is num) {
          final d = v.toDouble();
          return (d >= 0 && d < 10000) ? d : null;
        }
        return null;
      }

      final code = (p['code'] ?? '').toString().trim();
      if (code.isEmpty || code.length > 40) continue;
      batchArgs.add([
        code,
        name,
        brand.isEmpty ? null : brand.substring(0, brand.length.clamp(0, 80)),
        country.isEmpty
            ? null
            : country.substring(0, country.length.clamp(0, 24)),
        _g('serving_quantity'),
        kcal == null ? null : (kcal * 10).round() / 10,
        _n('proteins_100g') == null
            ? null
            : (_n('proteins_100g')! * 10).round() / 10,
        _n('carbohydrates_100g') == null
            ? null
            : (_n('carbohydrates_100g')! * 10).round() / 10,
        _n('fat_100g') == null ? null : (_n('fat_100g')! * 10).round() / 10,
        _n('fiber_100g') ?? 0.0,
      ]);
      if (batchArgs.length >= batch) {
        await _execBatch(db, batchArgs);
        rows += batchArgs.length;
        batchArgs.clear();
      }
    }
    if (batchArgs.isNotEmpty) {
      await _execBatch(db, batchArgs);
      rows += batchArgs.length;
    }
    return rows;
  }

  static Future<void> _execBatch(Database db, List<List<Object?>> batch) =>
      db.transaction((txn) async {
        for (final a in batch) {
          await txn.execute(
              'INSERT OR REPLACE INTO foods '
              '(code, name, brand, country, serving_g, kcal, protein, carbs, fat, fiber) '
              'VALUES (?,?,?,?,?,?,?,?,?,?)',
              a);
        }
      });

  static Future<String?> lastUpdated() async =>
      Db.getSetting('foods_updated_at');
  static Future<int> lastTs() async =>
      int.tryParse(await Db.getSetting('foods_delta_ts') ?? '') ?? 0;
}
