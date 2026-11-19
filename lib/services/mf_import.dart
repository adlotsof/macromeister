// Import MacroFactor CSV exports: body metrics (weights + fat %) and daily
// nutrition totals. Dates are US format M/D/YYYY, CRLF line endings.
//
// Daily nutrition totals become one log entry per day ("MacroFactor daily
// total") — MF exports don't contain the individual foods, so the totals are
// preserved as a single entry that feeds expenditure/expenditure history.
import '../app_state.dart';
import '../db.dart';
import '../models.dart';

class MfImport {
  /// Minimal CSV split handling quotes (MF exports don't quote, but be safe).
  static List<String> _row(String line) {
    final cells = <String>[];
    var cur = StringBuffer();
    var inQ = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQ && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          inQ = !inQ;
        }
      } else if (c == ',' && !inQ) {
        cells.add(cur.toString());
        cur = StringBuffer();
      } else {
        cur.write(c);
      }
    }
    cells.add(cur.toString());
    return cells;
  }

  /// M/D/YYYY or M/D/YY -> yyyy-MM-dd.
  static String _isoDate(String s) {
    final parts = s.trim().split('/');
    if (parts.length != 3) return '';
    var y = int.tryParse(parts[2]);
    if (y == null) return '';
    if (y < 100) y = y < 70 ? 2000 + y : 1900 + y;
    final m = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    if (m == null || d == null) return '';
    return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  static double? _num(String s) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    return v != null && v > 0 ? v : null;
  }

  static List<List<String>> _parse(String csv) {
    final rows = <List<String>>[];
    for (final line in csv.replaceAll('\r\n', '\n').split('\n')) {
      if (line.trim().isEmpty) continue;
      rows.add(_row(line));
    }
    return rows;
  }

  /// Body-metrics CSV: Date, Weight (kg), Fat Percent. Upserts one weight
  /// entry per date. Returns imported count.
  static Future<int> importWeights(String csv) async {
    final rows = _parse(csv);
    if (rows.length < 2) throw const FormatException('No data rows.');
    final header = rows.first.map((h) => h.toLowerCase()).toList();
    final wCol = header.indexWhere((h) => h.contains('weight'));
    final fatCol = header.indexWhere((h) => h.contains('fat'));
    if (wCol < 0) throw const FormatException('No "Weight" column found.');
    var n = 0;
    for (final r in rows.skip(1)) {
      if (r.length <= wCol) continue;
      final date = _isoDate(r[0]);
      final kg = _num(r[wCol]);
      if (date.isEmpty || kg == null) continue;
      final fat = fatCol >= 0 && fatCol < r.length ? _num(r[fatCol]) : null;
      await Db.upsertWeight(WeightEntry(date: date, weightKg: kg, fatPercent: fat));
      n++;
    }
    if (n > 0) {
      // Seed the profile's start weight from the earliest import if unset.
      await _seedStartWeight();
      AppState.instance.refresh();
    }
    return n;
  }

  static Future<void> _seedStartWeight() async {
    final p = await Db.loadProfile();
    if (p == null) return;
    final weights = await Db.weights();
    if (weights.isEmpty) return;
    final earliest =
        weights.reduce((a, b) => a.date.compareTo(b.date) < 0 ? a : b);
    if (p.startWeightKg <= 0 || p.startWeightKg == 75) {
      await Db.saveProfile(p.copyWith(startWeightKg: earliest.weightKg));
    }
  }

  /// Daily-nutrition CSV: Date, Calories (kcal), Fat (g), Carbs (g),
  /// Protein (g). Creates one log entry per day as a quick-add style entry.
  /// Returns imported count.
  static Future<int> importDailyLog(String csv) async {
    final rows = _parse(csv);
    if (rows.length < 2) throw const FormatException('No data rows.');
    final header = rows.first.map((h) => h.toLowerCase()).toList();
    int col(String needle) => header.indexWhere((h) => h.contains(needle));
    final kcalCol = col('cal');
    final fatCol = col('fat');
    final carbCol = col('carb');
    final proCol = col('protein');
    if (kcalCol < 0) throw const FormatException('No "Calories" column found.');
    var n = 0;
    for (final r in rows.skip(1)) {
      if (r.length <= kcalCol) continue;
      final date = _isoDate(r[0]);
      final kcal = _num(r[kcalCol]);
      if (date.isEmpty || kcal == null) continue;
      final fat = fatCol >= 0 && fatCol < r.length ? ((_num(r[fatCol]) ?? 0) as num).toDouble() : 0.0;
      final carbs =
          carbCol >= 0 && carbCol < r.length ? ((_num(r[carbCol]) ?? 0) as num).toDouble() : 0.0;
      final protein =
          proCol >= 0 && proCol < r.length ? ((_num(r[proCol]) ?? 0) as num).toDouble() : 0.0;
      // Skip dates that already have logged entries — don't double-count.
      final existing = await Db.logsForDay(date);
      if (existing.isNotEmpty) continue;
      await Db.insertLog(LogEntry(
        date: date,
        meal: 'snack',
        name: 'MacroFactor daily total',
        brand: '',
        grams: 0,
        kcal: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        fiber: 0,
      ));
      n++;
    }
    if (n > 0) AppState.instance.refresh();
    return n;
  }
}
