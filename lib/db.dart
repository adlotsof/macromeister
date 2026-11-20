// SQLite data layer (sqflite). Single shared database.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class Db {
  static Database? _db;
  static Database? _foodsDb;
  static Database? _commonDb;

  /// Overrides the main database filename. Tests set a unique name per suite
  /// so suites running in parallel under `flutter test` don't lock each
  /// other's database file.
  static String? dbPathOverride;

  /// The bundled USDA SR Legacy COMMON-FOODS database (7.7k generic whole
  /// foods: "Eggplant, raw", "Salad greens, mixed raw", chicken breast, rice,
  /// … — the barcode-less basics a macro tracker needs alongside the
  /// packaged products OFF covers).
  /// Copied out of the APK on first use, same crash-safe native streaming as
  /// the big OFF database.
  static const int _commonDbVersion = 1;
  static Future<Database> commonDb() async {
    if (_commonDb != null) return _commonDb!;
    final dir = await getDatabasesPath();
    final file = p.join(dir, 'foods_common.db');
    final marker = p.join(dir, 'foods_common.db.v$_commonDbVersion');
    if (!File(marker).existsSync()) {
      const channel = MethodChannel('com.trsonn.macrotrack/asset_copy');
      await channel.invokeMethod<void>('copyAsset', {
        'asset': 'flutter_assets/assets/foods_common.db',
        'dest': file,
      });
      await File(marker).writeAsString('$_commonDbVersion', flush: true);
      final stale = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) =>
              p.basename(f.path).startsWith('foods_common.db.v') &&
              f.path != marker);
      for (final f in stale) {
        f.deleteSync();
      }
    }
    _commonDb = await openDatabase(file, readOnly: true);
    return _commonDb!;
  }

  /// Shared token-based search over a foods table (used for both the OFF
  /// database and the USDA common-foods database).
  static Future<List<Map<String, Object?>>> _tokenSearch(
      Database db, String q) async {
    final esc = q.replaceAll('%', '').replaceAll('_', '').trim();
    final tokens = esc.split(RegExp(r'\s+')).where((t) => t.length >= 2).toList();
    if (tokens.isEmpty) {
      tokens.add(esc);
    }
    final wheres = <String>[];
    final args = <Object?>[];
    for (final t in tokens) {
      wheres.add('(name LIKE ? OR brand LIKE ?)');
      args.addAll(['%$t%', '%$t%']);
    }
    // Rank: rows with real nutrition data first (name-only rows with no
    // kcal would otherwise flood the top with "0 kcal" junk), then products
    // whose brand matches a query token (brand IS the query word), then
    // shorter names within a tier.
    final rankExprs = <String>[
      'CASE WHEN kcal IS NOT NULL THEN 0 ELSE 1 END',
    ];
    final rankArgs = <Object?>[];
    for (final t in tokens) {
      rankExprs.add('CASE WHEN brand LIKE ? THEN 0 ELSE 1 END');
      rankArgs.add('%$t%');
    }
    rankExprs.add('CASE WHEN name LIKE ? THEN 0 ELSE 1 END');
    rankArgs.add('${tokens.last}%');
    return db.rawQuery('''
      SELECT code, name, brand, country, serving_g, kcal, protein, carbs, fat, fiber
      FROM foods
      WHERE ${wheres.join(' AND ')}
      ORDER BY ${rankExprs.join(', ')}, LENGTH(name)
      LIMIT 30
    ''', [...args, ...rankArgs]);
  }

  static Food _foodFromRow(Map<String, Object?> r, String source) => Food(
        name: (r['name'] ?? '') as String,
        brand: (r['brand'] ?? '') as String,
        servingG: (r['serving_g'] as num?)?.toDouble() ?? 100,
        kcal: (r['kcal'] as num?)?.toDouble() ?? 0,
        protein: (r['protein'] as num?)?.toDouble() ?? 0,
        carbs: (r['carbs'] as num?)?.toDouble() ?? 0,
        fat: (r['fat'] as num?)?.toDouble() ?? 0,
        fiber: (r['fiber'] as num?)?.toDouble() ?? 0,
        source: source,
        offId: (r['code'] ?? '') as String,
      );

  /// Token-based search over the bundled USDA common-foods database
  /// (barcode-less whole foods). Results come back before OFF results.
  static Future<List<Food>> searchCommonLocal(String q) async {
    final db = await commonDb();
    final rows = await _tokenSearch(db, q);
    return rows.map((r) => _foodFromRow(r, 'common')).toList();
  }

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  /// Closes the cached connections and drops the cached singletons so a
  /// later [instance]/search call reopens fresh. Used by tests.
  @visibleForTesting
  static Future<void> resetForTest() async {
    await _db?.close();
    _db = null;
    await _foodsDb?.close();
    _foodsDb = null;
    await _commonDb?.close();
    _commonDb = null;
  }

  /// The bundled full Open Food Facts database (all ~4.9M named products).
  /// Copied out of the APK on first use; re-copied when the bundled version
  /// changes (marker file `foods_off.db.v<N>`).
  static const int _foodsDbVersion = 3;
  /// Newest OFF delta end-timestamp at bundle build time (updates after this
  /// are applied from the daily deltas; see lib/services/food_updates.dart).
  static const int _bundledDeltaTs = 1794984251;
  static Future<Database> foodsDb() async {
    if (_foodsDb != null) return _foodsDb!;
    final dir = await getDatabasesPath();
    final file = p.join(dir, 'foods_off.db');
    final marker = p.join(dir, 'foods_off.db.v$_foodsDbVersion');
    if (!File(marker).existsSync()) {
      // Stream the 668 MB asset out of the APK via a native Android method
      // channel (AssetManager streams; the Dart AssetBundle API would load
      // the whole file into RAM and OOM-kill the app). The native side is
      // crash-safe: temp file -> atomic rename, so a mid-copy death redoes
      // the copy cleanly on next launch.
      const channel = MethodChannel('com.trsonn.macrotrack/asset_copy');
      await channel.invokeMethod<void>('copyAsset', {
        // Flutter packs assets under 'flutter_assets/' inside the APK, so the
        // host AssetManager must use that prefix (bare 'assets/...' throws
        // FileNotFoundException).
        'asset': 'flutter_assets/assets/foods_off.db',
        'dest': file,
      });
      await File(marker).writeAsString('$_foodsDbVersion', flush: true);
      if (await getSetting('foods_delta_ts') == null) {
        await setSetting('foods_delta_ts', '$_bundledDeltaTs');
      }
      // Clean markers from older versions so only one copy lifecycle exists.
      final stale = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) =>
              p.basename(f.path).startsWith('foods_off.db.v') &&
              f.path != marker);
      for (final f in stale) {
        f.deleteSync();
      }
    }
    // Read-write: the delta updater (lib/services/food_updates.dart) applies
    // OFF incremental updates into this copy.
    _foodsDb = await openDatabase(file);
    return _foodsDb!;
  }

  /// Token-based search over the bundled OFF database. Every token ("lidl",
  /// "mozzarella") must match somewhere in name or brand, so "lidl mozzarella"
  /// finds Lidl mozzarella products. Ranking: rows with real nutrition data
  /// first, then brand-token hits, then shorter names. Best 30.
  static Future<List<Food>> searchOffLocal(String q) async {
    final db = await foodsDb();
    final rows = await _tokenSearch(db, q);
    return rows.map((r) => _foodFromRow(r, 'off')).toList();
  }

  static Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
        p.join(dir, dbPathOverride ?? 'macrotrack.db'),
        version: 3,
        onUpgrade: (db, from, to) async {
      if (from < 2) {
        // MacroFactor body-metrics import carries body-fat %; add the column.
        await db.execute(
            'ALTER TABLE weights ADD COLUMN fat_percent REAL');
      }
      if (from < 3) {
        await db.execute(
            'CREATE TABLE IF NOT EXISTS hydration(date TEXT PRIMARY KEY, ml INTEGER)');
      }
    },
        onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE profile(
          id INTEGER PRIMARY KEY, name TEXT, sex TEXT, birth_year INTEGER,
          height_cm REAL, start_weight_kg REAL, goal_weight_kg REAL,
          goal_rate_kg_per_week REAL, activity_factor REAL, diet_style TEXT,
          checkin_weekday INTEGER, program_type TEXT, created_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE foods(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, brand TEXT,
          serving_g REAL, kcal REAL, protein REAL, carbs REAL, fat REAL,
          fiber REAL, source TEXT, off_id TEXT, created_at TEXT
        )''');
      await db.execute('CREATE UNIQUE INDEX foods_off ON foods(off_id) WHERE off_id IS NOT NULL');
      await db.execute('''
        CREATE TABLE log_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, meal TEXT,
          food_id INTEGER, name TEXT, brand TEXT, grams REAL, kcal REAL,
          protein REAL, carbs REAL, fat REAL, fiber REAL,
          fasted INTEGER DEFAULT 0, created_at TEXT
        )''');
      await db.execute(
          'CREATE INDEX log_date ON log_entries(date, meal)');
      await db.execute('''
        CREATE TABLE weights(
          id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, weight_kg REAL
        )''');
      await db.execute('''
        CREATE TABLE checkins(
          id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, week_start TEXT,
          weight_kg REAL, kcal_avg_7d REAL, expenditure REAL,
          daily_target REAL, notes TEXT
        )''');
      await db.execute('''
        CREATE TABLE habits(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, active INTEGER
        )''');
      await db.execute(
          'CREATE TABLE habit_days(habit_id INTEGER, date TEXT, UNIQUE(habit_id, date))');
      await db.execute('''
        CREATE TABLE recipes(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, servings INTEGER,
          ingredients_json TEXT, kcal REAL, protein REAL, carbs REAL, fat REAL, steps TEXT
        )''');
      await db.execute('''
        CREATE TABLE workout_programs(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, days_json TEXT, type TEXT
        )''');
      await db.execute('''
        CREATE TABLE workout_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT, program_id INTEGER, date TEXT,
          name TEXT, exercises_json TEXT, duration_min INTEGER
        )''');
      await db.execute('''
        CREATE TABLE period_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, flow INTEGER, symptoms TEXT
        )''');
      await db.execute(
          'CREATE TABLE photos(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, path TEXT, weight_kg REAL)');
      await db.execute(
          'CREATE TABLE hydration(date TEXT PRIMARY KEY, ml INTEGER)');
      await db.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
    });
    return db;
  }

  // ---- profile ----
  static Future<Profile?> loadProfile() async {
    final rows = await (await instance)
        .query('profile', where: 'id = 0', limit: 1);
    if (rows.isEmpty) return null;
    return Profile.fromMap(rows.first);
  }

  static Future<void> saveProfile(Profile p) async {
    final db = await instance;
    await db.insert('profile', {...p.toMap(), 'id': 0},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- foods ----
  static Future<void> deleteFood(int id) async {
    await (await instance).delete('foods', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> upsertFood(Food f) async {
    final db = await instance;
    if (f.id != null) {
      final m = f.toMap()..remove('id');
      await db.update('foods', m, where: 'id = ?', whereArgs: [f.id]);
      return f.id!;
    }
    if (f.offId != null) {
      final existing = await db
          .query('foods', where: 'off_id = ?', whereArgs: [f.offId], limit: 1);
      if (existing.isNotEmpty) return existing.first['id'] as int;
    }
    return db.insert('foods', f.toMap());
  }

  static Future<List<Food>> searchLocalFoods(String q) async {
    final rows = await (await instance).query('foods',
        where: 'name LIKE ? OR brand LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
        limit: 30);
    return rows.map(Food.fromMap).toList();
  }

  static Future<Food?> foodById(int id) async {
    final rows = await (await instance)
        .query('foods', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Food.fromMap(rows.first);
  }

  static Future<List<Food>> customFoods() async {
    final rows = await (await instance)
        .query('foods', where: "source = 'custom'", limit: 500);
    return rows.map(Food.fromMap).toList();
  }

  // ---- log entries ----
  static Future<int> insertLog(LogEntry e) async =>
      (await instance).insert('log_entries', e.toMap());

  static Future<void> updateLog(LogEntry e) async {
    if (e.id == null) return;
    final m = e.toMap()..remove('id');
    await (await instance)
        .update('log_entries', m, where: 'id = ?', whereArgs: [e.id]);
  }

  static Future<void> deleteLog(int id) async =>
      (await instance).delete('log_entries', where: 'id = ?', whereArgs: [id]);

  static Future<List<LogEntry>> logsForDay(String date) async {
    final rows = await (await instance)
        .query('log_entries', where: 'date = ?', whereArgs: [date]);
    return rows.map(LogEntry.fromMap).toList();
  }

  static Future<List<LogEntry>> logsBetween(String from, String to) async {
    final rows = await (await instance).query('log_entries',
        where: 'date >= ? AND date <= ?', whereArgs: [from, to]);
    return rows.map(LogEntry.fromMap).toList();
  }

  static Future<void> clearLogs(String from, String to) async {
    await (await instance).delete(
        'log_entries',
        where: 'date >= ? AND date <= ?',
        whereArgs: [from, to]);
  }

  // ---- weights ----
  static Future<void> upsertWeight(WeightEntry e) async {
    final db = await instance;
    final existing = await db
        .query('weights', where: 'date = ?', whereArgs: [e.date], limit: 1);
    if (existing.isEmpty) {
      await db.insert('weights', e.toMap());
    } else {
      final m = e.toMap()..remove('id');
      await db.update('weights', m, where: 'date = ?', whereArgs: [e.date]);
    }
  }

  static Future<List<WeightEntry>> weights({int limit = 400}) async {
    final rows = await (await instance)
        .query('weights', orderBy: 'date DESC', limit: limit);
    return rows.map(WeightEntry.fromMap).toList().reversed.toList();
  }

  // ---- checkins ----
  static Future<int> insertCheckIn(CheckIn c) async =>
      (await instance).insert('checkins', c.toMap());

  static Future<CheckIn?> lastCheckIn() async {
    final rows = await (await instance)
        .query('checkins', orderBy: 'date DESC', limit: 1);
    return rows.isEmpty ? null : CheckIn.fromMap(rows.first);
  }

  static Future<List<CheckIn>> checkIns() async {
    final rows =
        await (await instance).query('checkins', orderBy: 'date DESC');
    return rows.map(CheckIn.fromMap).toList();
  }

  // ---- habits ----
  static Future<int> upsertHabit(Habit h) async =>
      (await instance).insert('habits', h.toMap());

  static Future<List<Habit>> habits() async {
    final rows = await (await instance)
        .query('habits', where: 'active = 1', orderBy: 'id');
    return rows.map(Habit.fromMap).toList();
  }

  static Future<void> deleteHabit(int id) async =>
      (await instance).delete('habits', where: 'id = ?', whereArgs: [id]);

  /// Marks/unmarks a habit done on a date. Returns the new done-state.
  static Future<bool> toggleHabitDay(int habitId, String date) async {
    final db = await instance;
    final rows = await db.query('habit_days',
        where: 'habit_id = ? AND date = ?', whereArgs: [habitId, date]);
    if (rows.isEmpty) {
      await db.insert('habit_days', {'habit_id': habitId, 'date': date});
      return true;
    }
    await db.delete('habit_days',
        where: 'habit_id = ? AND date = ?', whereArgs: [habitId, date]);
    return false;
  }

  /// Set of dates (yyyy-MM-dd) the habit was done, ascending.
  static Future<List<String>> habitDays(int habitId) async {
    final rows = await (await instance).query('habit_days',
        where: 'habit_id = ?', whereArgs: [habitId], orderBy: 'date');
    return rows.map((r) => r['date'] as String).toList();
  }

  // ---- recipes ----
  static Future<int> upsertRecipe(Recipe r) async =>
      (await instance).insert('recipes', r.toMap());

  static Future<void> deleteRecipe(int id) async =>
      (await instance).delete('recipes', where: 'id = ?', whereArgs: [id]);

  static Future<List<Recipe>> recipes() async {
    final rows = await (await instance).query('recipes', orderBy: 'name');
    return rows.map(Recipe.fromMap).toList();
  }

  // ---- workouts ----
  static Future<int> upsertWorkoutProgram(WorkoutProgram p) async =>
      (await instance).insert('workout_programs', p.toMap());

  static Future<void> deleteWorkoutProgram(int id) async =>
      (await instance)
          .delete('workout_programs', where: 'id = ?', whereArgs: [id]);

  static Future<List<WorkoutProgram>> workoutPrograms() async {
    final rows = await (await instance).query('workout_programs', orderBy: 'id');
    return rows.map(WorkoutProgram.fromMap).toList();
  }

  static Future<int> insertWorkoutSession(WorkoutSession s) async =>
      (await instance).insert('workout_sessions', s.toMap());

  static Future<void> deleteWorkoutSession(int id) async => (await instance)
      .delete('workout_sessions', where: 'id = ?', whereArgs: [id]);

  static Future<List<WorkoutSession>> workoutSessions({int limit = 200}) async {
    final rows = await (await instance)
        .query('workout_sessions', orderBy: 'date DESC', limit: limit);
    return rows.map(WorkoutSession.fromMap).toList();
  }

  // ---- period ----
  static Future<void> upsertPeriod(PeriodEntry e) async =>
      (await instance).insert('period_entries', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<List<PeriodEntry>> periodEntries({int limit = 200}) async {
    final rows = await (await instance)
        .query('period_entries', orderBy: 'date DESC', limit: limit);
    return rows.map(PeriodEntry.fromMap).toList();
  }

  // ---- photos ----
  static Future<int> insertPhoto(ProgressPhoto p) async =>
      (await instance).insert('photos', p.toMap());

  static Future<void> deletePhoto(int id) async =>
      (await instance).delete('photos', where: 'id = ?', whereArgs: [id]);

  static Future<List<ProgressPhoto>> photos() async {
    final rows = await (await instance).query('photos', orderBy: 'date DESC');
    return rows.map(ProgressPhoto.fromMap).toList();
  }

  // ---- hydration ----
  /// Adds [ml] to the day's hydration total (default 0) and returns the new
  /// total. Negative values subtract but never go below 0.
  static Future<int> addWater(String date, int ml) async {
    final db = await instance;
    final newMl = (await waterMl(date) + ml).clamp(0, 10000);
    await db.insert('hydration', {'date': date, 'ml': newMl},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return newMl;
  }

  static Future<int> waterMl(String date) async {
    final rows = await (await instance)
        .query('hydration', where: 'date = ?', whereArgs: [date], limit: 1);
    return (rows.isEmpty ? null : rows.first['ml'] as int?) ?? 0;
  }

  /// Sets the day's total explicitly (used by the card's reset/undo).
  static Future<void> setWaterMl(String date, int ml) async {
    await (await instance).insert('hydration',
        {'date': date, 'ml': ml.clamp(0, 10000)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- settings ----
  static Future<String?> getSetting(String key) async {
    final rows = await (await instance)
        .query('settings', where: 'k = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  static Future<void> setSetting(String key, String value) async {
    await (await instance).insert('settings', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, String>> allSettings() async {
    final rows = await (await instance).query('settings');
    return {for (final r in rows) r['k'] as String: (r['v'] ?? '') as String};
  }
}
