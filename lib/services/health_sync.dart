// Health integration (Health Connect on Android). Reads steps + weight,
// writes weight, meal nutrition (macros + micronutrients) and hydration.
//
// Unit notes (verified against health 13.3.2 native writer):
//  - writeMeal expects macros/fiber in GRAMS and micronutrients in GRAMS
//    too (NutritionRecord Mass fields) — this file converts our mg/µg.
//  - WATER records are in LITERS.
//  - clientRecordId gives upsert semantics: rewriting the same id replaces
//    the record, so day totals and edited entries stay drift-free.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../app_state.dart' show fmtDate;
import '../models.dart';

class HealthSync {
  static final _health = Health();

  /// Extracts a numeric value from a HealthDataPoint's value, which can be
  /// a num or a NumericHealthValue depending on the platform.
  static double? _numOf(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  /// True when the platform's health store is usable: Health Connect on
  /// Android, HealthKit (present on every iOS 8+ device) on iOS.
  static Future<bool> isAvailable() {
    if (Platform.isIOS) return Future.value(true);
    return _health.isHealthConnectAvailable();
  }

  static Future<bool> requestPermissions() async {
    // Without Health Connect installed the authorization call may silently
    // "succeed" — never claim a connection that cannot exist.
    if (!await isAvailable()) return false;
    try {
      await _health.requestAuthorization(
        [
          HealthDataType.STEPS,
          HealthDataType.WEIGHT,
          HealthDataType.BODY_FAT_PERCENTAGE,
          HealthDataType.WATER,
          HealthDataType.NUTRITION,
        ],
        permissions: [
          HealthDataAccess.READ,
          HealthDataAccess.READ_WRITE,
          HealthDataAccess.READ,
          HealthDataAccess.READ_WRITE,
          HealthDataAccess.READ_WRITE,
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

  // ---- hydration ----

  /// Mirrors the app's hydration DAY TOTAL into Health Connect. The record
  /// id is stable per day, so re-writing replaces the previous total —
  /// undo/reset stay drift-free.
  static Future<bool> writeWater(DateTime day, int totalMl) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      return await _health.writeHealthData(
        value: totalMl / 1000, // liters
        type: HealthDataType.WATER,
        startTime: start,
        endTime: end,
        clientRecordId: 'mt-water-${fmtDate(day)}',
      );
    } catch (_) {
      return false;
    }
  }

  // ---- nutrition ----

  static MealType _mealTypeOf(String meal) {
    switch (meal) {
      case 'breakfast':
        return MealType.BREAKFAST;
      case 'lunch':
        return MealType.LUNCH;
      case 'dinner':
        return MealType.DINNER;
      default:
        return MealType.SNACK;
    }
  }

  /// Mirrors one log entry as a Health Connect meal. Stable clientRecordId
  /// per entry: editing an entry and re-writing replaces the old record.
  static Future<bool> writeMealFromEntry(LogEntry e) async {
    final id = e.id;
    if (id == null) return false;
    try {
      final day = DateTime.parse(e.date);
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final m = microsToMealGrams(e.micros);
      return await _health.writeMeal(
        mealType: _mealTypeOf(e.meal),
        startTime: start,
        endTime: end,
        name: e.name,
        clientRecordId: 'mt-log-$id',
        caloriesConsumed: e.kcal > 0 ? e.kcal : null,
        protein: e.protein > 0 ? e.protein : null,
        carbohydrates: e.carbs > 0 ? e.carbs : null,
        fatTotal: e.fat > 0 ? e.fat : null,
        fiber: e.fiber > 0 ? e.fiber : null,
        vitaminA: m['vitamin_a'],
        vitaminC: m['vitamin_c'],
        vitaminD: m['vitamin_d'],
        vitaminE: m['vitamin_e'],
        vitaminK: m['vitamin_k'],
        b1Thiamin: m['thiamin'],
        b2Riboflavin: m['riboflavin'],
        b3Niacin: m['niacin'],
        b6Pyridoxine: m['vitamin_b6'],
        b9Folate: m['folate'],
        b12Cobalamin: m['vitamin_b12'],
        calcium: m['calcium'],
        iron: m['iron'],
        magnesium: m['magnesium'],
        zinc: m['zinc'],
        potassium: m['potassium'],
        sodium: m['sodium'],
        selenium: m['selenium'],
      );
    } catch (_) {
      return false;
    }
  }

  /// Converts app micros (mg/µg, per entry) to the grams that the health
  /// plugin's writeMeal expects (NutritionRecord Mass fields). Only the ids
  /// writeMeal supports are mapped; everything else is dropped.
  @visibleForTesting
  static Map<String, double> microsToMealGrams(Map<String, double> micros) {
    const mgIds = {
      'vitamin_c', 'thiamin', 'riboflavin', 'niacin', 'vitamin_b6',
      'calcium', 'iron', 'magnesium', 'zinc', 'potassium', 'sodium',
    };
    const ugIds = {
      'vitamin_a', 'vitamin_d', 'vitamin_e', 'vitamin_k',
      'folate', 'vitamin_b12', 'selenium',
    };
    final out = <String, double>{};
    micros.forEach((id, v) {
      if (!v.isFinite || v < 0) return;
      if (mgIds.contains(id)) {
        out[id] = v / 1000; // mg -> g
      } else if (ugIds.contains(id)) {
        out[id] = v / 1000000; // µg -> g
      }
    });
    return out;
  }

  /// Removes the Health Connect meal record for a deleted/edited log entry.
  static Future<bool> deleteMealForEntry(int entryId) async {
    try {
      return await _health.deleteByClientRecordId(
        dataTypeKey: HealthDataType.NUTRITION,
        clientRecordId: 'mt-log-$entryId',
      );
    } catch (_) {
      return false;
    }
  }
}

/// Fire-and-forget guard for health writes triggered from the data layer:
/// a Health Connect failure must never break logging or make a test flake.
Future<void> hcSync(Future<bool> Function() write) async {
  if (kIsWeb) return;
  try {
    await write();
  } catch (_) {
    // Unavailable/no permission in tests or on devices without HC.
  }
}
