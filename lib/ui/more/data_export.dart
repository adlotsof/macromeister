// Data export: per-area CSVs plus a full JSON backup (profile, goals, weights,
// log, habits, recipes, workouts, settings) with import/restore.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../services/backup.dart';
import '../../services/mf_xlsx_import.dart';
import '../../theme.dart';

String _csvRow(List<Object?> cells) => cells
    .map((c) {
      final s = c?.toString() ?? '';
      return s.contains(',') || s.contains('"') || s.contains('\n')
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    })
    .join(',');

class DataExportScreen extends StatelessWidget {
  const DataExportScreen({super.key});

  Future<void> _exportAll(BuildContext context) async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Building backup...')));
    try {
      await Backup.exportAndShare();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: MtTheme.danger));
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Import backup?'),
              content: const Text(
                  'Picking a backup file REPLACES all current data: profile, '
                  'goals, food log, weights, check-ins, habits, recipes, '
                  'workouts and settings. This cannot be undone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Choose file')),
              ],
            ));
    if (confirmed != true || !context.mounted) return;
    try {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json']);
      final path = res?.files.single.path;
      if (path == null || !context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Restoring...')));
      final n = await Backup.importFrom(path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restored $n rows from backup')));
      AppState.instance.refresh();
    } catch (e, st) {
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('Import failed'),
                  content: SingleChildScrollView(
                      child: Text('$e\n\n$st')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK')),
                  ],
                ));
      }
    }
  }

  Future<void> _importMfXlsx(BuildContext context) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      final path = res?.files.single.path;
      if (path == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Importing MacroFactor export...')));
      final r = await MfXlsx.importFile(path);
      if (!context.mounted) return;
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('MacroFactor import done'),
                content: Text(
                    'Weights: ${r.weights} days\n'
                    'Logged days: ${r.loggedDays}\n'
                    'Custom foods: ${r.customFoods}\n'
                    'Recipes: ${r.recipes}\n'
                    '${r.profileNote}\n\n'
                    'Skipped (no counterpart):\n'
                    '${r.skipped.join(', ')}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK')),
                ],
              ));
    } catch (e, st) {
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('Import failed'),
                  content: SingleChildScrollView(
                      child: Text('$e\n\n$st')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK')),
                  ],
                ));
      }
    }
  }

  Future<void> _export(BuildContext context, String name,
      Future<String> Function() build) async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Building CSV...')));
    try {
      final csv = await build();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/macrotrack_$name.csv');
      await file.writeAsString('\uFEFF$csv', encoding: utf8);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
          text: 'MacroTrack export: $name');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: MtTheme.danger));
      }
    }
  }

  Future<String> _exportLogs() async {
    final logs = await Db.logsBetween('0000-01-01', '9999-12-31');
    final buf = StringBuffer(
        'date,meal,name,brand,grams,kcal,protein,carbs,fat,fiber\n');
    for (final l in logs) {
      buf.writeln(_csvRow([
        l.date, l.meal, l.name, l.brand, l.grams,
        l.kcal.toStringAsFixed(1), l.protein.toStringAsFixed(1),
        l.carbs.toStringAsFixed(1), l.fat.toStringAsFixed(1),
        l.fiber.toStringAsFixed(1),
      ]));
    }
    return buf.toString();
  }

  Future<String> _exportWeights() async {
    final w = await Db.weights(limit: 10000);
    final buf = StringBuffer('date,weight_kg\n');
    for (final e in w) {
      buf.writeln(_csvRow([e.date, e.weightKg.toStringAsFixed(2)]));
    }
    return buf.toString();
  }

  Future<String> _exportCheckIns() async {
    final c = await Db.checkIns();
    final buf = StringBuffer(
        'date,week_start,weight_kg,kcal_avg_7d,expenditure,daily_target,notes\n');
    for (final e in c) {
      buf.writeln(_csvRow([
        e.date, e.weekStart, e.weightKg?.toStringAsFixed(2) ?? '',
        e.kcalAvg7d.toStringAsFixed(0), e.expenditure.toStringAsFixed(0),
        e.dailyTarget.toStringAsFixed(0), e.notes,
      ]));
    }
    return buf.toString();
  }

  Future<String> _exportWorkouts() async {
    final s = await Db.workoutSessions(limit: 10000);
    final buf = StringBuffer('date,name,duration_min,exercise,set,reps,weight_kg\n');
    for (final sess in s) {
      final List exercises;
      try {
        exercises = (jsonDecode(sess.exercisesJson) as List? ?? []);
      } catch (_) {
        continue; // one corrupt row must not abort the whole export
      }
      for (final e in exercises.whereType<Map>()) {
        final sets = (e['sets'] as List? ?? []);
        for (var i = 0; i < sets.length; i++) {
          final st = (sets[i] as Map?)?.cast<String, dynamic>() ?? const {};
          buf.writeln(_csvRow([
            sess.date, sess.name, sess.durationMin,
            e['name'] ?? '', i + 1, st['reps'] ?? '', st['weight'] ?? '',
          ]));
        }
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export data')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: MtTheme.surfaceHi,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: const Text('Full backup',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'Everything as one JSON file: profile & goals, height, '
                  'weights, food log, check-ins, habits, recipes, '
                  'period entries and settings.',
                  style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
              trailing: const Icon(Icons.backup, color: MtTheme.accent),
              onTap: () => _exportAll(context),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: const Text('Import backup',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'Restore from a full-backup JSON file. Replaces current data.',
                  style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
              trailing: const Icon(Icons.restore, color: MtTheme.accentAlt),
              onTap: () => _import(context),
            ),
          ),
          const _SectionLabel('Import from MacroFactor'),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: const Text('MacroFactor Excel export (.xlsx)'),
              subtitle: const Text(
                  'Imports the full MF export: profile & goals, weights + '
                  'body-fat, custom foods, recipes, daily totals, expenditure '
                  '.',
                  style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
              trailing: const Icon(Icons.upload_file, color: MtTheme.accent),
              onTap: () => _importMfXlsx(context),
            ),
          ),
          const _SectionLabel('CSV exports'),
          for (final item in [
            ('Food log', 'All logged entries with absolute macros.',
                _exportLogs),
            ('Body weight', 'Daily weight entries.', _exportWeights),
            ('Check-ins', 'Weekly check-ins with expenditure and targets.',
                _exportCheckIns),
            ('Workout sessions', 'One row per set.', _exportWorkouts),
          ])
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(item.$1),
                subtitle: Text(item.$2,
                    style:
                        const TextStyle(color: MtTheme.textDim, fontSize: 13)),
                trailing: const Icon(Icons.ios_share, color: MtTheme.accent),
                onTap: () => _export(context, item.$1, item.$3),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                color: MtTheme.textDim,
                fontWeight: FontWeight.w700)),
      );
}
