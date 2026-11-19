// Simple observable app state + date helpers + shared computations.
import 'package:flutter/foundation.dart';

import 'db.dart';
import 'models.dart';
import 'services/expenditure.dart';

const kMeals = ['breakfast', 'lunch', 'dinner', 'snack'];

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class DayTotals {
  final double kcal, protein, carbs, fat, fiber;
  DayTotals(
      {this.kcal = 0,
      this.protein = 0,
      this.carbs = 0,
      this.fat = 0,
      this.fiber = 0});

  static DayTotals fromLogs(List<LogEntry> logs) => DayTotals(
        kcal: logs.fold(0, (a, l) => a + l.kcal),
        protein: logs.fold(0, (a, l) => a + l.protein),
        carbs: logs.fold(0, (a, l) => a + l.carbs),
        fat: logs.fold(0, (a, l) => a + l.fat),
        fiber: logs.fold(0, (a, l) => a + l.fiber),
      );
}

/// Global mutable app state (selected day + change broadcasting).
class AppState extends ChangeNotifier {
  static final instance = AppState._();
  AppState._();

  DateTime _selected = today();
  DateTime get selectedDate => _selected;
  set selectedDate(DateTime d) {
    _selected = DateTime(d.year, d.month, d.day);
    notifyListeners();
  }

  void refresh() => notifyListeners();

  String get selectedDateStr => fmtDate(_selected);

  Future<DayTotals> totalsFor(String date) async =>
      DayTotals.fromLogs(await Db.logsForDay(date));

  Future<MacroTargets> currentTargets() async {
    final profile = await Db.loadProfile();
    final last = await Db.lastCheckIn();
    final weights = await Db.weights();
    final recent = await Db.logsBetween(
        fmtDate(today().subtract(const Duration(days: 60))), fmtDate(today()));
    final exp = ExpenditureEngine.expenditure(
      profile ?? Profile(),
      recent,
      weights,
      previousSmoothed: last?.expenditure,
    );
    final p = profile ?? Profile();
    final goalType = p.goalRateKgPerWeek < -0.05
        ? 'lose'
        : p.goalRateKgPerWeek > 0.05
            ? 'gain'
            : 'maintain';
    final target = last?.dailyTarget ??
        ExpenditureEngine.dailyTarget(exp, p.goalRateKgPerWeek);
    final macros0 = ExpenditureEngine.macroGoals(
      dailyTargetKcal: target,
      bodyWeightKg: weights.isNotEmpty ? weights.last.weightKg : p.startWeightKg,
      goalType: goalType,
      sex: p.sex,
    );
    // Optional user override (program edit screen → "Customize macro targets").
    // Protein and fat are fixed grams/day; carbs fill the remaining energy.
    var macros = macros0;
    if (await Db.getSetting('macro_custom') == '1') {
      final pg = double.tryParse(
              await Db.getSetting('macro_protein_g') ?? '') ??
          macros0.protein;
      final fg = double.tryParse(await Db.getSetting('macro_fat_g') ?? '') ??
          macros0.fat;
      final carbsKcal = target - pg * 4 - fg * 9;
      macros = (
        protein: pg.clamp(20, 500),
        fat: fg.clamp(10, 300),
        // Quantized to whole grams so the editor preview, program card and
        // dashboard all display the identical number (no 278-vs-279 drift).
        carbs: carbsKcal < 0 ? 0.0 : (carbsKcal / 4).floorToDouble(),
      );
    }
    return MacroTargets(
      expenditure: exp,
      dailyTargetKcal: target,
      protein: macros.protein,
      carbs: macros.carbs,
      fat: macros.fat,
    );
  }
}

class MacroTargets {
  final double expenditure, dailyTargetKcal, protein, carbs, fat;
  MacroTargets({
    required this.expenditure,
    required this.dailyTargetKcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Monday of the week containing [d].
DateTime weekStart(DateTime d) {
  final days = d.weekday - 1;
  return DateTime(d.year, d.month, d.day).subtract(Duration(days: days));
}
