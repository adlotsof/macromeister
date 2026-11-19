// Health integration (Health Connect on Android). Reads steps + weight,
// writes weight. The original also syncs nutrition/hydration both ways and
// supports Apple Health / Fitbit / Google Fit (iOS-only ecosystems) — see
// FEATURES.md for the difference list.
import 'package:health/health.dart';

class HealthSync {
  static final _health = Health();

  /// Extracts a numeric value from a HealthDataPoint's value, which can be
  /// a num or a NumericHealthValue depending on the platform.
  static double? _numOf(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  static Future<bool> requestPermissions() async {
    try {
      await _health.requestAuthorization(
        [
          HealthDataType.STEPS,
          HealthDataType.WEIGHT,
          HealthDataType.BODY_FAT_PERCENTAGE,
        ],
        permissions: [
          HealthDataAccess.READ,
          HealthDataAccess.READ_WRITE,
          HealthDataAccess.READ,
        ],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Total steps for a given date (local midnight to midnight).
  static Future<int> stepsForDate(DateTime day) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );
      return data.fold<int>(
        0,
        (sum, d) => sum + (_numOf(d.value) ?? 0).toInt(),
      );
    } catch (_) {
      return 0;
    }
  }

  /// Latest Health Connect weight of the day, if any.
  static Future<double?> weightForDate(DateTime day) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: start,
        endTime: end,
      );
      if (data.isEmpty) return null;
      return _numOf(data.last.value);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> writeWeight(DateTime day, double kg) async {
    try {
      return await _health.writeHealthData(
        value: kg,
        type: HealthDataType.WEIGHT,
        startTime: day,
        endTime: day,
      );
    } catch (_) {
      return false;
    }
  }
}
