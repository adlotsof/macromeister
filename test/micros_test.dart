// Unit tests for the micronutrient layer (lib/micros.dart + models.dart).
// Covers: canonical definitions, JSON encode/decode round-trips, sane-input
// filtering, per-gram scaling, and entry summation.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/micros.dart';
import 'package:macrotrack/models.dart';

void main() {
  test('canonical definitions: ids unique, targets positive', () {
    final ids = Micros.all.map((d) => d.id).toSet();
    expect(ids.length, Micros.all.length, reason: 'ids must be unique');
    for (final d in Micros.all) {
      expect(d.defaultTarget, greaterThan(0), reason: '${d.id} target');
      expect(d.unit, isNotEmpty);
    }
  });

  test('encode/decode round-trips a micros map', () {
    const micros = {'vitamin_c': 12.5, 'iron': 0.4, 'calcium': 120.0};
    final decoded = Micros.decode(Micros.encode(micros));
    expect(decoded, micros);
  });

  test('encode drops unknown ids and invalid values', () {
    final encoded = Micros.encode({
      'vitamin_c': 50.0,
      'made_up_nutrient': 1.0, // unknown id -> dropped
      'iron': -3.0, // negative -> dropped
      'zinc': double.nan, // non-finite -> dropped
      'selenium': 9999999.0, // above sane bound -> dropped
    });
    final decoded = Micros.decode(encoded);
    expect(decoded.keys, ['vitamin_c']);
  });

  test('decode of garbage returns an empty map, never throws', () {
    expect(Micros.decode(null), isEmpty);
    expect(Micros.decode(''), isEmpty);
    expect(Micros.decode('not json at all'), isEmpty);
    expect(Micros.decode('["array","not","map"]'), isEmpty);
  });

  test('scale converts per-100g values to grams and clamps', () {
    final scaled = Micros.scale({'vitamin_c': 50.0, 'iron': 0.3}, 200);
    expect(scaled['vitamin_c'], 100.0);
    expect(scaled['iron'], closeTo(0.6, 1e-9));
    // Zero or negative grams -> empty (no absurd numbers).
    expect(Micros.scale({'vitamin_c': 50.0}, 0), isEmpty);
    expect(Micros.scale({'vitamin_c': 50.0}, -5), isEmpty);
    // Huge per-100g typo stays clamped at the sane bound.
    final clamped = Micros.scale({'vitamin_c': 9999999.0}, 100);
    expect(clamped['vitamin_c'], 100000);
  });

  test('sum aggregates entries per nutrient', () {
    final total = Micros.sum([
      {'vitamin_c': 10.0, 'iron': 1.0},
      {'vitamin_c': 15.5},
      {},
    ]);
    expect(total['vitamin_c'], 25.5);
    expect(total['iron'], 1.0);
  });

  test('Food round-trip keeps micros through toMap/fromMap', () {
    final food = Food(
      id: 1,
      name: 'Kiwi',
      servingG: 100,
      kcal: 61,
      protein: 1.1,
      carbs: 14.7,
      fat: 0.5,
      fiber: 3.0,
      micros: {'vitamin_c': 92.7, 'vitamin_k': 40.3},
      source: 'custom',
    );
    final back = Food.fromMap(food.toMap());
    expect(back.micros, food.micros);
    // And scales with grams: 150 g of kiwi.
    expect(back.microsFor(150)['vitamin_c'], closeTo(139.05, 1e-9));
  });

  test('LogEntry round-trip keeps absolute micros', () {
    final entry = LogEntry(
      id: 7,
      date: '2026-11-20',
      meal: 'breakfast',
      name: 'Kiwi',
      grams: 150,
      kcal: 91.5,
      protein: 1.65,
      carbs: 22.05,
      fat: 0.75,
      micros: {'vitamin_c': 139.05},
    );
    final back = LogEntry.fromMap(entry.toMap());
    expect(back.micros, entry.micros);
    // Empty micros serialize as null, not '{}'.
    final plain = LogEntry(
        date: '2026-11-20',
        meal: 'lunch',
        name: 'X',
        grams: 100,
        kcal: 1,
        protein: 0,
        carbs: 0,
        fat: 0);
    expect(plain.toMap()['micros'], isNull);
  });
}
