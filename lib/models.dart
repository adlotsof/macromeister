// Data models for MacroTrack. Plain classes with manual JSON maps.
import 'dart:convert';

import 'micros.dart';

class Food {
  final int? id;
  final String name;
  final String brand;
  final double servingG; // per-serving size in grams
  final double kcal, protein, carbs, fat, fiber; // per 100 g
  final Map<String, double> micros; // per 100 g; keys = Micros ids
  final String source; // custom | off | ai
  final String? offId;
  final String? createdAt;

  Food({
    this.id,
    required this.name,
    this.brand = '',
    required this.servingG,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0,
    this.micros = const {},
    this.source = 'custom',
    this.offId,
    this.createdAt,
  });

  // Nutrients for a given amount in grams.
  double kcalFor(double grams) => kcal * grams / 100;
  double proteinFor(double grams) => protein * grams / 100;
  double carbsFor(double grams) => carbs * grams / 100;
  double fatFor(double grams) => fat * grams / 100;
  double fiberFor(double grams) => fiber * grams / 100;
  Map<String, double> microsFor(double grams) => Micros.scale(micros, grams);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'brand': brand,
        'serving_g': servingG,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'micros': micros.isEmpty ? null : Micros.encode(micros),
        'source': source,
        'off_id': offId,
        'created_at': createdAt,
      };

  static Food fromMap(Map<String, Object?> m) => Food(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        brand: (m['brand'] ?? '') as String,
        servingG: (m['serving_g'] as num?)?.toDouble() ?? 100,
        kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
        protein: (m['protein'] as num?)?.toDouble() ?? 0,
        carbs: (m['carbs'] as num?)?.toDouble() ?? 0,
        fat: (m['fat'] as num?)?.toDouble() ?? 0,
        fiber: (m['fiber'] as num?)?.toDouble() ?? 0,
        micros: Micros.decode(m['micros'] as String?),
        source: (m['source'] ?? 'custom') as String,
        offId: m['off_id'] as String?,
        createdAt: m['created_at'] as String?,
      );
}

class LogEntry {
  final int? id;
  final String date; // yyyy-MM-dd
  final String meal; // breakfast | lunch | dinner | snack
  final int? foodId;
  final String name;
  final String brand;
  final double grams;
  final double kcal, protein, carbs, fat, fiber; // absolute for this entry
  final Map<String, double> micros; // absolute for this entry; keys = Micros ids
  final bool fasted; // zero-calorie day marker support
  final String? photo; // optional meal-photo path (custom foods etc.)
  final String? createdAt;

  LogEntry({
    this.id,
    required this.date,
    required this.meal,
    this.foodId,
    required this.name,
    this.brand = '',
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0,
    this.micros = const {},
    this.fasted = false,
    this.photo,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'meal': meal,
        'food_id': foodId,
        'name': name,
        'brand': brand,
        'grams': grams,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'micros': micros.isEmpty ? null : Micros.encode(micros),
        'fasted': fasted ? 1 : 0,
        if (photo != null) 'photo': photo,
        'created_at': createdAt,
      };

  static LogEntry fromMap(Map<String, Object?> m) => LogEntry(
        id: m['id'] as int?,
        date: (m['date'] ?? '') as String,
        meal: (m['meal'] ?? 'snack') as String,
        foodId: m['food_id'] as int?,
        name: (m['name'] ?? '') as String,
        brand: (m['brand'] ?? '') as String,
        grams: (m['grams'] as num?)?.toDouble() ?? 0,
        kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
        protein: (m['protein'] as num?)?.toDouble() ?? 0,
        carbs: (m['carbs'] as num?)?.toDouble() ?? 0,
        fat: (m['fat'] as num?)?.toDouble() ?? 0,
        fiber: (m['fiber'] as num?)?.toDouble() ?? 0,
        micros: Micros.decode(m['micros'] as String?),
        fasted: (m['fasted'] as int? ?? 0) == 1,
        photo: m['photo'] as String?,
        createdAt: m['created_at'] as String?,
      );
}

class WeightEntry {
  final int? id;
  final String date; // yyyy-MM-dd, one per day (latest wins)
  final double weightKg;
  final double? fatPercent; // body-fat %, from MacroFactor body-metrics import
  WeightEntry({this.id, required this.date, required this.weightKg,
      this.fatPercent});

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'weight_kg': weightKg,
        if (fatPercent != null) 'fat_percent': fatPercent,
      };
  static WeightEntry fromMap(Map<String, Object?> m) => WeightEntry(
      id: m['id'] as int?,
      date: (m['date'] ?? '') as String,
      weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
      fatPercent: (m['fat_percent'] as num?)?.toDouble());
}

class Profile {
  final int? id;
  final String name;
  final String sex; // male | female
  final int birthYear;
  final double heightCm;
  final double startWeightKg;
  final double goalWeightKg;
  final double goalRateKgPerWeek; // e.g. -0.5 lose, 0 gain, +0.25 gain
  final double activityFactor; // 1.2 sedentary .. 2.0 very active
  final String dietStyle; // anything (free text)
  final int checkinWeekday; // 1=Mon .. 7=Sun
  final String programType; // coached | manual
  final String? createdAt;

  Profile({
    this.id,
    this.name = '',
    this.sex = 'male',
    this.birthYear = 1990,
    this.heightCm = 175,
    this.startWeightKg = 75,
    this.goalWeightKg = 70,
    this.goalRateKgPerWeek = -0.25,
    this.activityFactor = 1.4,
    this.dietStyle = '',
    this.checkinWeekday = 1,
    this.programType = 'coached',
    this.createdAt,
  });

  int get age => DateTime.now().year - birthYear;

  // Mifflin-St Jeor BMR.
  double get bmr {
    final base = 10 * startWeightKg + 6.25 * heightCm - 5 * age;
    return sex == 'male' ? base + 5 : base - 161;
  }

  double get initialTdee => bmr * activityFactor;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'sex': sex,
        'birth_year': birthYear,
        'height_cm': heightCm,
        'start_weight_kg': startWeightKg,
        'goal_weight_kg': goalWeightKg,
        'goal_rate_kg_per_week': goalRateKgPerWeek,
        'activity_factor': activityFactor,
        'diet_style': dietStyle,
        'checkin_weekday': checkinWeekday,
        'program_type': programType,
        'created_at': createdAt,
      };

  static Profile fromMap(Map<String, Object?> m) => Profile(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        sex: (m['sex'] ?? 'male') as String,
        birthYear: (m['birth_year'] as num?)?.toInt() ?? 1990,
        heightCm: (m['height_cm'] as num?)?.toDouble() ?? 175,
        startWeightKg: (m['start_weight_kg'] as num?)?.toDouble() ?? 75,
        goalWeightKg: (m['goal_weight_kg'] as num?)?.toDouble() ?? 70,
        goalRateKgPerWeek:
            (m['goal_rate_kg_per_week'] as num?)?.toDouble() ?? -0.25,
        activityFactor: (m['activity_factor'] as num?)?.toDouble() ?? 1.4,
        dietStyle: (m['diet_style'] ?? '') as String,
        checkinWeekday: (m['checkin_weekday'] as num?)?.toInt() ?? 1,
        programType: (m['program_type'] ?? 'coached') as String,
        createdAt: m['created_at'] as String?,
      );

  Profile copyWith({
    String? name,
    String? sex,
    int? birthYear,
    double? heightCm,
    double? startWeightKg,
    double? goalWeightKg,
    double? goalRateKgPerWeek,
    double? activityFactor,
    String? dietStyle,
    int? checkinWeekday,
    String? programType,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        sex: sex ?? this.sex,
        birthYear: birthYear ?? this.birthYear,
        heightCm: heightCm ?? this.heightCm,
        startWeightKg: startWeightKg ?? this.startWeightKg,
        goalWeightKg: goalWeightKg ?? this.goalWeightKg,
        goalRateKgPerWeek: goalRateKgPerWeek ?? this.goalRateKgPerWeek,
        activityFactor: activityFactor ?? this.activityFactor,
        dietStyle: dietStyle ?? this.dietStyle,
        checkinWeekday: checkinWeekday ?? this.checkinWeekday,
        programType: programType ?? this.programType,
        createdAt: createdAt,
      );
}

class CheckIn {
  final int? id;
  final String date; // yyyy-MM-dd of the check-in
  final String weekStart; // yyyy-MM-dd Monday of that week
  final double? weightKg;
  final double kcalAvg7d;
  final double expenditure; // smoothed TDEE used at this check-in
  final double dailyTarget; // new energy target after this check-in
  final String notes;
  CheckIn({
    this.id,
    required this.date,
    required this.weekStart,
    this.weightKg,
    required this.kcalAvg7d,
    required this.expenditure,
    required this.dailyTarget,
    this.notes = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'week_start': weekStart,
        'weight_kg': weightKg,
        'kcal_avg_7d': kcalAvg7d,
        'expenditure': expenditure,
        'daily_target': dailyTarget,
        'notes': notes,
      };

  static CheckIn fromMap(Map<String, Object?> m) => CheckIn(
        id: m['id'] as int?,
        date: (m['date'] ?? '') as String,
        weekStart: (m['week_start'] ?? '') as String,
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        kcalAvg7d: (m['kcal_avg_7d'] as num?)?.toDouble() ?? 0,
        expenditure: (m['expenditure'] as num?)?.toDouble() ?? 0,
        dailyTarget: (m['daily_target'] as num?)?.toDouble() ?? 0,
        notes: (m['notes'] ?? '') as String,
      );
}

class Recipe {
  final int? id;
  final String name;
  final int servings;
  final String ingredientsJson; // [{name, grams, kcal,p,c,f}]
  final double kcal, protein, carbs, fat; // per serving
  final String? steps;
  Recipe({
    this.id,
    required this.name,
    this.servings = 1,
    required this.ingredientsJson,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.steps,
  });

  static List<Map<String, Object?>> decodeIngredients(String json) {
    try {
      return (jsonDecode(json) as List)
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'servings': servings,
        'ingredients_json': ingredientsJson,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'steps': steps,
      };

  static Recipe fromMap(Map<String, Object?> m) => Recipe(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        servings: (m['servings'] as num?)?.toInt() ?? 1,
        ingredientsJson: (m['ingredients_json'] ?? '[]') as String,
        kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
        protein: (m['protein'] as num?)?.toDouble() ?? 0,
        carbs: (m['carbs'] as num?)?.toDouble() ?? 0,
        fat: (m['fat'] as num?)?.toDouble() ?? 0,
        steps: m['steps'] as String?,
      );
}

/// Wraps a recipe as a Food so it logs through the SAME detail-sheet flow
/// as foods (per-item meal chips next to the Add button, Servings editor).
/// Recipe macros are per serving, so servingG is 1 and the detail sheet
/// runs in 'servings' mode (the amount IS the portion count).
/// Dedupes a merged search-result list by normalized name+brand:
/// the same food arrives from multiple sources ('My food' after the
/// first add, USDA common foods, Open Food Facts) and used to render
/// identical duplicate rows. First occurrence wins, so locally saved
/// foods rank ahead of remote copies.
List<Food> dedupeFoodsByName(Iterable<Food> foods) {
  final seen = <String>{};
  String norm(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  String key(Food f) => '${norm(f.name)}|${norm(f.brand)}';
  return foods.where((f) => seen.add(key(f))).toList();
}

/// Wraps a previously-logged entry as a Food so re-adding it goes through
/// the detail sheet (amount editable before adding). The entry's totals are
/// normalized to per-100 g (or per-unit for zero-gram entries).
Food loggedEntryAsFood(LogEntry l) => Food(
      name: l.name,
      brand: l.brand,
      servingG: l.grams > 0 ? l.grams : 1,
      kcal: l.grams > 0 ? l.kcal / l.grams * 100 : l.kcal,
      protein: l.grams > 0 ? l.protein / l.grams * 100 : l.protein,
      carbs: l.grams > 0 ? l.carbs / l.grams * 100 : l.carbs,
      fat: l.grams > 0 ? l.fat / l.grams * 100 : l.fat,
      fiber: l.grams > 0 ? l.fiber / l.grams * 100 : l.fiber,
      source: 'logged',
    );

Food recipePerServingFood(Recipe r) => Food(
      name: r.name,
      brand: '',
      servingG: 1,
      kcal: r.kcal,
      protein: r.protein,
      carbs: r.carbs,
      fat: r.fat,
      fiber: 0,
      source: 'recipe',
    );


class WorkoutProgram {
  final int? id;
  final String name;
  final String daysJson; // [{dayName, exercises:[{name, sets, reps}]}]
  final String type; // coached | manual
  WorkoutProgram({this.id, required this.name, required this.daysJson, this.type = 'manual'});

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'days_json': daysJson, 'type': type};
  static WorkoutProgram fromMap(Map<String, Object?> m) => WorkoutProgram(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        daysJson: (m['days_json'] ?? '[]') as String,
        type: (m['type'] ?? 'manual') as String,
      );
}

class WorkoutSession {
  final int? id;
  final int? programId;
  final String date;
  final String name;
  final String exercisesJson; // [{name, sets:[{reps, weight}]}]
  final int durationMin;
  WorkoutSession({
    this.id,
    this.programId,
    required this.date,
    required this.name,
    required this.exercisesJson,
    this.durationMin = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'program_id': programId,
        'date': date,
        'name': name,
        'exercises_json': exercisesJson,
        'duration_min': durationMin,
      };

  static WorkoutSession fromMap(Map<String, Object?> m) => WorkoutSession(
        id: m['id'] as int?,
        programId: m['program_id'] as int?,
        date: (m['date'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        exercisesJson: (m['exercises_json'] ?? '[]') as String,
        durationMin: (m['duration_min'] as num?)?.toInt() ?? 0,
      );
}

class PeriodEntry {
  final int? id;
  final String date;
  final int flow; // 0 none, 1 light, 2 medium, 3 heavy
  final String symptoms; // csv
  PeriodEntry({this.id, required this.date, this.flow = 0, this.symptoms = ''});

  Map<String, Object?> toMap() =>
      {'id': id, 'date': date, 'flow': flow, 'symptoms': symptoms};
  static PeriodEntry fromMap(Map<String, Object?> m) => PeriodEntry(
        id: m['id'] as int?,
        date: (m['date'] ?? '') as String,
        flow: (m['flow'] as num?)?.toInt() ?? 0,
        symptoms: (m['symptoms'] ?? '') as String,
      );
}

class ProgressPhoto {
  final int? id;
  final String date;
  final String path;
  final double? weightKg;
  ProgressPhoto({this.id, required this.date, required this.path, this.weightKg});

  Map<String, Object?> toMap() =>
      {'id': id, 'date': date, 'path': path, 'weight_kg': weightKg};
  static ProgressPhoto fromMap(Map<String, Object?> m) => ProgressPhoto(
        id: m['id'] as int?,
        date: (m['date'] ?? '') as String,
        path: (m['path'] ?? '') as String,
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
      );
}
