// Import MacroFactor's full Excel export (the .xlsx with 28 sheets).
// Imports everything the MacroTrack schema can hold:
//   Scale Weight -> weights (+ fat %)
//   Calories & Macros -> one log entry per day (daily totals)
//   Custom Foods -> foods table (per-100g, deduped by name)
//   Recipes -> recipes (macros converted to per-serving)
//   User Profile -> profile (sex, birth year, height, activity)
//   Weight Goals -> goal weight + rate from the latest goal
//   Nutrition Program Settings (last row) -> check-in with MF's daily target
//   Expenditure (last row) -> check-in expenditure, so the engine continues
//     from MacroFactor's own smoothed TDEE instead of cold-starting
// Sheets without a MacroTrack counterpart (Body Metrics, Micronutrients,
// Steps, Muscle Groups, Favorites, History, Fasting, notes, gym profiles)
// are skipped — documented in FEATURES.md.
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';

import '../app_state.dart';
import '../db.dart';
import '../models.dart';

class MfXlsxResult {
  final int weights, loggedDays, customFoods, recipes;
  final String profileNote;
  final List<String> skipped;
  MfXlsxResult(this.weights, this.loggedDays, this.customFoods, this.recipes,
      this.profileNote, this.skipped);
}

class MfXlsx {
  /// excel 4.x wraps cell values in typed cell objects; unwrap to raw
  /// String/num/DateTime so the helpers below see plain values.
  static Object? _unwrap(Object? v) {
    if (v is TextCellValue) return v.value.text ?? '';
    if (v is IntCellValue) return v.value;
    if (v is DoubleCellValue) return v.value;
    if (v is BoolCellValue) return v.value;
    if (v is DateCellValue) {
      return DateTime(v.year, v.month, v.day);
    }
    return v;
  }

  static String _s(Object? v) {
    if (v == null) return '';
    return v.toString().trim();
  }

  static double? _n(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static String _isoDate(Object? v) {
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is String && v.contains('/')) {
      final p = v.trim().split('/');
      if (p.length == 3) {
        final y = int.tryParse(p[2]);
        final m = int.tryParse(p[0]);
        final d = int.tryParse(p[1]);
        if (y != null && m != null && d != null) {
          return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
        }
      }
    }
    return '';
  }

  /// Returns the sheet's rows keyed by lowercase header.
  static List<Map<String, Object?>> _sheet(Excel excel, String name) {
    final sh = excel.tables[name];
    if (sh == null) return [];
    final rows = sh.rows;
    if (rows.isEmpty) return [];
    final header =
        rows.first.map((c) => _s(c?.value).toLowerCase()).toList();
    final out = <Map<String, Object?>>[];
    for (final r in rows.skip(1)) {
      final m = <String, Object?>{};
      var any = false;
      for (var i = 0; i < header.length && i < r.length; i++) {
        if (header[i].isEmpty) continue;
        final v = _unwrap(r[i]?.value);
        if (v != null && v.toString().isNotEmpty) any = true;
        m[header[i]] = v;
      }
      if (any) out.add(m);
    }
    return out;
  }

  static Future<MfXlsxResult> importFile(String path) async {
    final bytes = await _readBytes(path);
    final excel = Excel.decodeBytes(bytes);
    final skipped = <String>[];

    // ---- User Profile ----
    var profileNote = '';
    final profileRows = _sheet(excel, 'User Profile');
    var profile = await Db.loadProfile();
    for (final r in profileRows) {
      profile ??= Profile(
          name: '', sex: 'male', birthYear: 1990, heightCm: 170, startWeightKg: 0,
          goalWeightKg: 0, goalRateKgPerWeek: 0, activityFactor: 1.4,
          dietStyle: '', checkinWeekday: 1, programType: 'coached');
      final sex = _s(r['sex']).toLowerCase();
      final bday = _s(r['birthday']);
      final year = int.tryParse(bday.split('-').first);
      final height = _n(r['height (cm)']);
      profile = profile.copyWith(
          sex: sex.contains('fem') ? 'female' : 'male',
          birthYear: year ?? profile.birthYear,
          heightCm: height != null && height > 50
              ? height.round().toDouble()
              : profile.heightCm);
      profileNote = 'Profile imported from User Profile sheet';
    }

    // ---- Weight Goals (latest goal) ----
    final goalRows = _sheet(excel, 'Weight Goals');
    if (goalRows.isNotEmpty) {
      final last = goalRows.last;
      final gw = _n(last['goal weight (kg)']);
      final ratePct = _n(last['goal rate per week (%)']);
      final base = _n(last['starting scale weight (kg)']);
      if (profile != null) {
        double? rate;
        if (ratePct != null && (base != null || gw != null)) {
          final w = base ?? gw!;
          rate = ratePct * w / 100; // %/week -> kg/week at goal weight
          final kind = _s(last['goal']);
          if (kind == 'Weight Loss') rate = -rate.abs();
          if (kind == 'Weight Gain') rate = rate.abs();
          if (kind == 'Maintenance') rate = 0;
        }
        profile = profile.copyWith(
            goalWeightKg: gw != null && gw > 30 ? gw : profile.goalWeightKg,
            goalRateKgPerWeek: rate ?? profile.goalRateKgPerWeek);
      }
    }

    if (profile != null) await Db.saveProfile(profile);

    // ---- Scale Weight ----
    var wCount = 0;
    final wRows = _sheet(excel, 'Scale Weight');
    final wCol = wRows.isNotEmpty && wRows.first.containsKey('weight (kg)');
    for (final r in wRows) {
      final date = _isoDate(r['date']);
      final kg = _n(r['weight (kg)']);
      if (date.isEmpty || kg == null) continue;
      final fat = _n(r['fat percent']);
      await Db.upsertWeight(
          WeightEntry(date: date, weightKg: kg, fatPercent: fat));
      wCount++;
    }
    if (!wCol) skipped.add('Scale Weight');
    // Seed start weight from the earliest imported weight.
    if (wCount > 0) {
      final p = await Db.loadProfile();
      if (p != null) {
        final weights = await Db.weights();
        if (weights.isNotEmpty) {
          final earliest =
              weights.reduce((a, b) => a.date.compareTo(b.date) < 0 ? a : b);
          await Db.saveProfile(p.copyWith(startWeightKg: earliest.weightKg));
        }
      }
    }

    // ---- Custom Foods ----
    var fCount = 0;
    final customNames =
        (await Db.customFoods()).map((f) => f.name.toLowerCase()).toSet();
    for (final r in _sheet(excel, 'Custom Foods')) {
      final name = _s(r['food name']);
      if (name.isEmpty) continue;
      final sw = _n(r['serving weight (g)']);
      final kcal = _n(r['calories (kcal)']);
      if (sw == null || sw <= 0) continue;
      double per100(double? perServing) =>
          perServing == null ? 0 : (perServing / sw * 100);
      final kcal100 = kcal == null ? 0.0 : per100(kcal);
      if (kcal100 <= 0) continue;
      if (customNames.contains(name.toLowerCase())) continue;
      customNames.add(name.toLowerCase());
      await Db.upsertFood(Food(
          name: name,
          brand: '',
          servingG: sw,
          kcal: kcal100,
          protein: per100(_n(r['protein (g)'])),
          carbs: per100(_n(r['carbs (g)'])),
          fat: per100(_n(r['fat (g)'])),
          fiber: per100(_n(r['fiber (g)'])),
          source: 'custom'));
      fCount++;
    }

    // ---- Recipes ----
    var rCount = 0;
    final recipeNames =
        (await Db.recipes()).map((r) => r.name.toLowerCase()).toSet();
    for (final r in _sheet(excel, 'Recipes')) {
      final name = _s(r['recipe name']);
      if (name.isEmpty) continue;
      final servings = _n(r['serving qty']) ?? 1;
      double div(Object? k) => (_n(r[k]) ?? 0) / servings;
      final ing = _s(r['ingredients'])
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => {'name': l.trim(), 'grams': 0})
          .toList();
      if (recipeNames.contains(name.toLowerCase())) continue;
      recipeNames.add(name.toLowerCase());
      await Db.upsertRecipe(Recipe(
          name: name,
          servings: servings.round(),
          ingredientsJson: jsonEncode(ing),
          kcal: div('calories (kcal)'),
          protein: div('protein (g)'),
          carbs: div('carbs (g)'),
          fat: div('fat (g)'),
          steps: ''));
      rCount++;
    }

    // ---- Calories & Macros -> daily totals ----
    var logCount = 0;
    for (final r in _sheet(excel, 'Calories & Macros')) {
      final date = _isoDate(r['date']);
      final kcal = _n(r['calories (kcal)']);
      if (date.isEmpty || kcal == null) continue;
      final existing = await Db.logsForDay(date);
      if (existing.isNotEmpty) continue;
      await Db.insertLog(LogEntry(
          date: date,
          meal: 'snack',
          name: 'MacroFactor daily total',
          brand: '',
          grams: 0,
          kcal: kcal,
          protein: _n(r['protein (g)']) ?? 0,
          carbs: _n(r['carbs (g)']) ?? 0,
          fat: _n(r['fat (g)']) ?? 0,
          fiber: 0));
      logCount++;
    }

    // ---- latest Nutrition Program Settings -> a check-in carrying MF's
    // current target; Expenditure's last value -> engine prior ----
    final progRows = _sheet(excel, 'Nutrition Program Settings');
    final expRows = _sheet(excel, 'Expenditure');
    final today = fmtDate(DateTime.now());
    final weekStart = _mondayOf(DateTime.now());
    double? exp;
    if (expRows.isNotEmpty) exp = _n(expRows.last['expenditure']);
    if (progRows.isNotEmpty) {
      final last = progRows.last;
      final target = _n(last['calories (kcal)']);
      final weights = await Db.weights();
      final latestW =
          weights.isNotEmpty ? weights.last.weightKg : null;
      if (target != null || exp != null) {
        await Db.insertCheckIn(CheckIn(
            date: today,
            weekStart: weekStart,
            weightKg: latestW,
            kcalAvg7d: target ?? 0,
            expenditure: exp ?? 0,
            dailyTarget: target ?? 0,
            notes: 'Imported from MacroFactor program settings'));
      }
    }

    AppState.instance.refresh();
    final hasBodyMetrics = excel.tables['Body Metrics'] != null;
    if (hasBodyMetrics) {
      skipped.add('Body Metrics (girth measurements — no schema table yet)');
    }
    for (final s in [
      'Micronutrients', 'Weight Trend', 'Steps', 'Muscle Groups - Sets',
      'Muscle Groups - Volume', 'Exercises - Total Sets', 'Favorites',
      'History', 'Workouts', 'Fasting', 'Micronutrient Goals',
      'Food Log Notes', 'Workout Log Notes', 'Partial Logging',
      'Exercise Settings', 'Workout Settings', 'Gym Profiles',
      'Custom Exercises'
    ]) {
      if (excel.tables[s] != null) skipped.add(s);
    }
    return MfXlsxResult(
        wCount, logCount, fCount, rCount, profileNote, skipped);
  }

  static String _mondayOf(DateTime d) {
    final day = d.weekday; // 1 = Monday
    final m = DateTime(d.year, d.month, d.day - (day - 1));
    return fmtDate(m);
  }
}

Future<List<int>> _readBytes(String path) => File(path).readAsBytes();
