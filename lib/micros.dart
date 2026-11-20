// Canonical micronutrient definitions for MacroTrack (MacroFactor parity).
// Stored as JSON on foods/log_entries via lib/models.dart `micros` maps:
// keys are ids from [Micros.all], values are absolute amounts per 100 g
// (foods) or per entry (log entries). Targets live in the settings table
// under 'micro_targets' (JSON id -> target amount per day).
import 'dart:convert';

class MicroDef {
  final String id;
  final String label;
  final String unit;
  final double defaultTarget; // per day, for an average adult
  const MicroDef(this.id, this.label, this.unit, this.defaultTarget);
}

class Micros {
  /// Display/entry order. Kept to the commonly tracked set; extendable.
  static const all = <MicroDef>[
    MicroDef('vitamin_a', 'Vitamin A', 'µg', 900),
    MicroDef('vitamin_c', 'Vitamin C', 'mg', 90),
    MicroDef('vitamin_d', 'Vitamin D', 'µg', 20),
    MicroDef('vitamin_e', 'Vitamin E', 'mg', 15),
    MicroDef('vitamin_k', 'Vitamin K', 'µg', 120),
    MicroDef('thiamin', 'Thiamin (B1)', 'mg', 1.2),
    MicroDef('riboflavin', 'Riboflavin (B2)', 'mg', 1.3),
    MicroDef('niacin', 'Niacin (B3)', 'mg', 16),
    MicroDef('vitamin_b6', 'Vitamin B6', 'mg', 1.7),
    MicroDef('folate', 'Folate', 'µg', 400),
    MicroDef('vitamin_b12', 'Vitamin B12', 'µg', 2.4),
    MicroDef('calcium', 'Calcium', 'mg', 1000),
    MicroDef('iron', 'Iron', 'mg', 18),
    MicroDef('magnesium', 'Magnesium', 'mg', 420),
    MicroDef('zinc', 'Zinc', 'mg', 11),
    MicroDef('potassium', 'Potassium', 'mg', 3400),
    MicroDef('sodium', 'Sodium', 'mg', 2300),
    MicroDef('selenium', 'Selenium', 'µg', 55),
  ];

  static final _byId = {for (final d in all) d.id: d};

  static MicroDef? byId(String id) => _byId[id];

  static String labelOf(String id) => _byId[id]?.label ?? id;
  static String unitOf(String id) => _byId[id]?.unit ?? '';

  /// Serialize a micros map to the JSON stored in the DB. Drops unknown ids
  /// and non-finite values so the column always parses.
  static String encode(Map<String, double> micros) =>
      jsonEncode({
        for (final e in micros.entries)
          if (_byId.containsKey(e.key) &&
              e.value.isFinite &&
              e.value >= 0 &&
              e.value < 1000000)
            e.key: e.value
      });

  static Map<String, double> decode(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final m = jsonDecode(json);
      if (m is! Map<String, dynamic>) return {};
      return {
        for (final e in m.entries)
          if (e.value is num && (e.value as num).toDouble() >= 0)
            e.key: (e.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Scales per-100 g values to [grams]. Each value clamped to the sane
  /// upper bound so a typo in the editor can't produce absurd numbers.
  static Map<String, double> scale(Map<String, double> per100g, double grams) {
    if (per100g.isEmpty || grams <= 0) return {};
    return {
      for (final e in per100g.entries)
        e.key: (e.value * grams / 100).clamp(0, 100000),
    };
  }

  /// Sums absolute entry maps (log entries for a day).
  static Map<String, double> sum(Iterable<Map<String, double>> maps) {
    final out = <String, double>{};
    for (final m in maps) {
      m.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }
}
