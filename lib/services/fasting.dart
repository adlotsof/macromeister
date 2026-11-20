// Fasting timer (MacroFactor parity gap #5). State lives in the settings
// table: 'fasting_start' (ISO 8601 while a fast is running, absent when not)
// and 'fasting_history' (JSON list of {start, end} ISO pairs, newest first).
// All timestamps are stored UTC-safe ISO strings and computed locally.
import 'dart:convert';

import '../db.dart';

class FastingService {
  /// Common fast lengths (hours) — surfaced in the UI copy.

  /// ISO timestamp of the running fast's start, or null when not fasting.
  static Future<DateTime?> runningStart() async {
    final s = await Db.getSetting('fasting_start');
    return s == null ? null : DateTime.tryParse(s);
  }

  static Future<bool> isRunning() async => await runningStart() != null;

  static Future<List<({DateTime start, DateTime end})>> history() async {
    final raw = await Db.getSetting('fasting_history');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = <({DateTime start, DateTime end})>[];
      for (final e in list) {
        if (e is! Map) continue;
        final s = DateTime.tryParse(e['start'] as String? ?? '');
        final en = DateTime.tryParse(e['end'] as String? ?? '');
        if (s != null && en != null && !en.isBefore(s)) {
          out.add((start: s, end: en));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Starts a fast from [now]. No-op if one is already running.
  static Future<void> start(DateTime now) async {
    if (await runningStart() != null) return;
    await Db.setSetting('fasting_start', now.toIso8601String());
  }

  /// Ends the running fast (started at or before [now]); appends it to the
  /// history and clears the marker. Returns the fast duration (clamped at
  /// zero against clock skew), or null when no fast was running.
  static Future<Duration?> end(DateTime now) async {
    final start = await runningStart();
    if (start == null) return null;
    final duration = now.isBefore(start) ? Duration.zero : now.difference(start);
    final h = await history();
    if (duration > Duration.zero) {
      final entries = [
        {'start': start.toIso8601String(), 'end': now.toIso8601String()},
        for (final e in h.take(29))
          {'start': e.start.toIso8601String(), 'end': e.end.toIso8601String()},
      ];
      await Db.setSetting(
          'fasting_history', jsonEncode(entries));
    }
    await Db.deleteSetting('fasting_start');
    return duration;
  }

  /// Elapsed duration of the running fast, or null.
  static Future<Duration?> elapsed(DateTime now) async {
    final start = await runningStart();
    if (start == null) return null;
    final d = now.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  /// Formats a duration as "16h 42m" (or "42m" under an hour).
  static String fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
