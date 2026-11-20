// Full backup/restore: every MacroTrack table (profile, goals, food log,
// weights, check-ins, habits, recipes, workouts, period entries, photo
// metadata, settings) as a single JSON file, shared via the system sheet.
// Import restores a backup file, replacing current data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db.dart';

class Backup {
  static const _marker = 'macrotrack-backup';
  static const _version = 1;

  static const _tables = [
    'profile',
    'foods',
    'log_entries',
    'weights',
    'checkins',
    'habits',
    'habit_days',
    'recipes',
    'workout_programs',
    'workout_sessions',
    'period_entries',
    'photos',
    'hydration',
    'settings',
  ];

  /// Collects every table and returns the JSON string.
  static Future<String> build() async {
    final db = await Db.instance;
    final out = <String, dynamic>{
      'app': _marker,
      'version': _version,
      'exported_at': DateTime.now().toIso8601String(),
    };
    for (final t in _tables) {
      out[t] = await db.query(t);
    }
    return jsonEncode(out);
  }

  /// Builds the backup JSON and shares it as a file. Returns the file path.
  static Future<String> exportAndShare() async {
    final json = await build();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/macrotrack_backup_$stamp.json');
    await file.writeAsString(json, flush: true);
    return file.path;
  }

  /// Settings-gated daily auto-backup into the app's documents dir with
  /// rotation (keeps the last [keep] files). Runs at most once per day
  /// (tracked via the 'auto_backup_last' setting); every failure is silent —
  /// a backup problem must never block the app. Default: ON.
  static Future<void> runAutoBackup({int keep = 7, Directory? docsOverride}) async {
    try {
      if (await Db.getSetting('auto_backup') == '0') return;
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      if (await Db.getSetting('auto_backup_last') == todayStr) return;
      final docs = docsOverride ?? await getApplicationDocumentsDirectory();
      final backupDir = Directory('${docs.path}/backups');
      await backupDir.create(recursive: true);
      final file = File('${backupDir.path}/macrotrack_auto_$todayStr.json');
      await file.writeAsString(await build(), flush: true);
      await rotate(backupDir, keep: keep);
      await Db.setSetting('auto_backup_last', todayStr);
    } catch (_) {
      // silent
    }
  }

  /// Deletes the oldest auto-backup files, keeping the newest [keep].
  @visibleForTesting
  static Future<void> rotate(Directory dir, {int keep = 7}) async {
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.contains('macrotrack_auto_') &&
            f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path)); // dated names sort by age
    for (var i = 0; i < files.length - keep; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }

  /// Reads and validates a backup file, then restores it, replacing current
  /// data. Row ids are preserved so references stay intact. Returns the
  /// number of restored rows.
  static Future<int> importFrom(String path) async {
    final raw = await File(path).readAsString();
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException('Not a valid backup file.');
    }
    if (data['app'] != _marker) {
      throw FormatException('Not a MacroTrack backup file.');
    }
    final version = data['version'];
    if (version is! int || version > _version) {
      // Missing or non-int version means the file is not a backup this
      // build produced — refuse rather than importing blindly.
      throw FormatException('Unsupported backup version.');
    }
    final db = await Db.instance;
    int restored = 0;
    await db.transaction((txn) async {
      for (final t in _tables) {
        final rows = data[t];
        if (rows is! List) continue;
        await txn.delete(t);
        for (final r in rows) {
          if (r is! Map) continue;
          await txn.insert(t, r.cast<String, Object?>(),
              conflictAlgorithm: ConflictAlgorithm.replace);
          restored++;
        }
      }
    });
    return restored;
  }
}
