// Unit tests for the Health Connect sync unit conversions. The health
// plugin's writeMeal expects NutritionRecord Mass fields in GRAMS, while the
// app stores micronutrients in mg (minerals, most vitamins) or µg
// (A/D/E/K, folate, B12, selenium). A wrong exponent poisons Health Connect
// by a factor of 1000 or 1000000, so this conversion is correctness-critical.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/services/health_sync.dart';

void main() {
  test('mg nutrients convert to grams (÷1000)', () {
    final out = HealthSync.microsToMealGrams({
      'vitamin_c': 90, // mg
      'calcium': 1000,
      'iron': 18,
      'potassium': 3400,
    });
    expect(out['vitamin_c'], closeTo(0.09, 1e-12));
    expect(out['calcium'], 1.0);
    expect(out['iron'], closeTo(0.018, 1e-12));
    expect(out['potassium'], 3.4);
  });

  test('µg nutrients convert to grams (÷1e6)', () {
    final out = HealthSync.microsToMealGrams({
      'vitamin_a': 900,
      'vitamin_d': 20,
      'folate': 400,
      'vitamin_b12': 2.4,
      'selenium': 55,
    });
    expect(out['vitamin_a'], closeTo(0.0009, 1e-12));
    expect(out['vitamin_d'], closeTo(0.00002, 1e-12));
    expect(out['folate'], closeTo(0.0004, 1e-12));
    expect(out['vitamin_b12'], closeTo(0.0000024, 1e-12));
    expect(out['selenium'], closeTo(0.000055, 1e-12));
  });

  test('unsupported ids and invalid values are dropped', () {
    final out = HealthSync.microsToMealGrams({
      'made_up': 5.0,
      'iron': -1.0, // negative
      'zinc': double.nan, // non-finite
      'vitamin_k': 120.0,
    });
    expect(out.keys, ['vitamin_k']);
  });

  test('empty and null-safe: empty map in, empty map out', () {
    expect(HealthSync.microsToMealGrams({}), isEmpty);
  });
}
