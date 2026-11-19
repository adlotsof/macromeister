// Dynamic expenditure (TDEE) estimation — documented approximation.
//
// The exact algorithm of the commercial app this mirrors is proprietary;
// these are the documented principles reproduced here:
//   1. Before enough data exists: BMR equation (Mifflin-St Jeor) x activity factor.
//   2. After ~2-4 weeks of consistent tracking: energy-balance calculation,
//      TDEE = mean(calories in) - energy from weight change,
//      where 1 kg body mass change ~ 7700 kcal (changing as body gets smaller/larger).
//   3. The estimate is smoothed (a "smoothed TDEE") so week-to-week noise
//      doesn't swing the target; here: exponential moving average, alpha = 0.25.
//   4. Fasted / zero-calorie days still count as intake = 0 (they are valid data).
//   5. Rate of change is bounded so bad data can't spike the estimate
//      (clamp to [bmr*1.0, bmr*3.0] and max 150 kcal/day change per update).
import '../models.dart';

class DayIntake {
  final String date;
  final double kcal;
  DayIntake(this.date, this.kcal);
}

class ExpenditureEngine {
  static const kcalPerKg = 7700.0;
  static const emaAlpha = 0.25;

  /// Weight trend slope (kg/day) via least squares over entries within `windowDays`.
  static double? weightSlopeKgPerDay(List<WeightEntry> weights, int windowDays) {
    if (weights.length < 4) return null;
    final now = DateTime.now();
    final pts = weights
        .where((w) =>
            now.difference(DateTime.parse(w.date)).inDays <= windowDays)
        .toList();
    if (pts.length < 4) return null;
    final t0 = DateTime.parse(pts.first.date);
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    for (final w in pts) {
      final x = DateTime.parse(w.date).difference(t0).inDays.toDouble();
      sx += x;
      sy += w.weightKg;
      sxx += x * x;
      sxy += x * w.weightKg;
    }
    final n = pts.length.toDouble();
    final denom = n * sxx - sx * sx;
    if (denom.abs() < 1e-9) return null;
    return (n * sxy - sx * sy) / denom;
  }

  /// Mean daily intake over logged days inside the window.
  /// Only days with any logging count as data (consistent-tracking requirement).
  static double? meanIntake(List<LogEntry> logs, int windowDays) {
    final now = DateTime.now();
    final byDay = <String, double>{};
    for (final l in logs) {
      final d = DateTime.parse(l.date);
      if (now.difference(d).inDays > windowDays) continue;
      byDay[l.date] = (byDay[l.date] ?? 0) + l.kcal;
    }
    if (byDay.length < 7) return null;
    final total = byDay.values.fold(0.0, (a, b) => a + b);
    return total / byDay.length;
  }

  /// Dynamic TDEE from energy balance, or null when not enough data.
  static double? dynamicTdee(
      List<LogEntry> logs, List<WeightEntry> weights, int windowDays) {
    final intake = meanIntake(logs, windowDays);
    final slope = weightSlopeKgPerDay(weights, windowDays);
    if (intake == null || slope == null) return null;
    // Clamp implausible weight slopes (data entry errors): +/- 1 kg/day.
    final s = slope.clamp(-1.0, 1.0);
    return intake - s * kcalPerKg;
  }

  /// Current expenditure estimate for the profile.
  /// Returns smoothed value when data supports it, otherwise initial estimate.
  static double expenditure(
      Profile profile, List<LogEntry> logs, List<WeightEntry> weights,
      {double? previousSmoothed, int windowDays = 28}) {
    final raw = dynamicTdee(logs, weights, windowDays);
    if (raw == null) return profile.initialTdee;
    final lo = profile.bmr * 1.0, hi = profile.bmr * 3.0;
    final bounded = raw.clamp(lo, hi);
    if (previousSmoothed == null) return bounded;
    final updated =
        previousSmoothed + emaAlpha * (bounded - previousSmoothed);
    // Bound the per-update change.
    final maxStep = 150.0;
    final delta = (updated - previousSmoothed).clamp(-maxStep, maxStep);
    return previousSmoothed + delta;
  }

  /// Daily energy target: expenditure adjusted for the goal rate.
  /// Positive rate = gaining, negative = losing. kg/week -> kcal/day.
  static double dailyTarget(double expenditure, double goalRateKgPerWeek) =>
      expenditure + goalRateKgPerWeek * kcalPerKg / 7.0;

  /// Macro split for an energy target. Protein emphasised (g/kg of goal weight),
  /// fat 25-30% of calories, carbs fill the remainder. Documented approximation:
  /// the original computes macro goals from your program + diet preferences.
  static ({double protein, double fat, double carbs}) macroGoals(
      {required double dailyTargetKcal,
      required double bodyWeightKg,
      required String goalType, // lose | maintain | gain
      required String sex}) {
    final proteinPerKg = goalType == 'maintain' ? 1.8 : 2.0;
    var proteinG = proteinPerKg * bodyWeightKg;
    // Never below a sane floor, never above 45% of calories.
    final pFloor = sex == 'male' ? 120.0 : 100.0;
    proteinG = proteinG.clamp(pFloor, dailyTargetKcal * 0.45 / 4);
    var fatKcal = dailyTargetKcal * (goalType == 'lose' ? 0.30 : 0.27);
    // Fat floor ~0.5 g/kg.
    final fatFloorKcal = 0.5 * bodyWeightKg * 9;
    if (fatKcal < fatFloorKcal) fatKcal = fatFloorKcal;
    final carbsKcal = dailyTargetKcal - proteinG * 4 - fatKcal;
    return (
      protein: proteinG,
      fat: fatKcal / 9,
      carbs: carbsKcal < 0 ? 0 : carbsKcal / 4,
    );
  }
}
