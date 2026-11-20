// Daily food log: date navigation, per-meal sections with entries,
// day totals vs targets, swipe to delete.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';
import 'add_food_sheet.dart';
import 'edit_entry_sheet.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppState.instance,
        // NOT const: an identical const child would be skipped by
        // Element.updateChild, so date changes would never rebuild the body.
        builder: (context, _) => _LogBody(),
      );
}

class _LogBody extends StatelessWidget {
  const _LogBody();

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final selected = app.selectedDate;
    // Ensure a targets computation is in flight if the cache was invalidated
    // (e.g. after a program edit); when it completes AppState notifies and
    // this body rebuilds with the fresh snapshot.
    app.currentTargets();
    final dateStr = app.selectedDateStr;
    final isToday = dateStr == fmtDate(today());
    return FutureBuilder<List<LogEntry>>(
      future: Db.logsForDay(dateStr),
      builder: (context, snap) {
        final logs = snap.data ?? const <LogEntry>[];
        final totals = DayTotals.fromLogs(logs);
        return Column(
          children: [
            // ---- date header ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: MtTheme.textDim),
                    onPressed: () =>
                        app.selectedDate = selected.subtract(const Duration(days: 1)),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickDate(context, selected),
                      child: Column(
                        children: [
                          Text(
                            isToday
                                ? 'Today'
                                : _weekdayLabel(selected),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          Text(dateStr,
                              style: const TextStyle(
                                  fontSize: 12, color: MtTheme.textDim)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: isToday ? Colors.transparent : MtTheme.textDim,
                    ),
                    onPressed: isToday
                        ? null
                        : () =>
                            app.selectedDate = selected.add(const Duration(days: 1)),
                  ),
                ],
              ),
            ),
            // ---- totals summary ----
            _TotalsCard(
                totals: totals, targets: app.targetsSnapshot),
            // ---- meals ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  for (final meal in kMeals)
                    _MealSection(
                        date: dateStr,
                        meal: meal,
                        logs: logs.where((l) => l.meal == meal).toList()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: today(),
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) AppState.instance.selectedDate = picked;
  }
}

String _weekdayLabel(DateTime d) {
  const names = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  return names[d.weekday - 1];
}

// ------------------------------------------------------------------ totals

class _TotalsCard extends StatelessWidget {
  final DayTotals totals;
  final MacroTargets? targets;
  const _TotalsCard({required this.totals, this.targets});

  @override
  Widget build(BuildContext context) {
    final target = targets?.dailyTargetKcal ?? 0;
    final remaining = target - totals.kcal;
    final proteinT = targets?.protein ?? 0;
    final carbsT = targets?.carbs ?? 0;
    final fatT = targets?.fat ?? 0;

    Widget bar(double value, double target, Color color) {
      final frac = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_labelFor(color),
                    style: const TextStyle(fontSize: 11, color: MtTheme.textDim)),
                Text('${value.round()}${target > 0 ? '/${target.round()}' : ''}g',
                    style: const TextStyle(fontSize: 11, color: MtTheme.textDim)),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 4,
                backgroundColor: MtTheme.surfaceHi,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MtTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${totals.kcal.round()}',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: MtTheme.accent)),
                    const Text('kcal eaten',
                        style: TextStyle(fontSize: 11, color: MtTheme.textDim)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      target > 0
                          ? '${remaining >= 0 ? remaining.round() : '+${(-remaining).round()}'} kcal left'
                          : '— kcal left',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: remaining < 0 ? MtTheme.danger : MtTheme.text),
                    ),
                    if (target > 0)
                      Text('target ${target.round()} kcal',
                          style: const TextStyle(
                              fontSize: 11, color: MtTheme.textDim)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(children: [
              bar(totals.protein, proteinT, MtTheme.accent),
              const SizedBox(width: 12),
              bar(totals.carbs, carbsT, MtTheme.accentAlt),
              const SizedBox(width: 12),
              bar(totals.fat, fatT, const Color(0xFFFFC46B)),
            ]),
          ],
        ),
      ),
    );
  }

  String _labelFor(Color c) {
    if (c == MtTheme.accent) return 'Protein';
    if (c == MtTheme.accentAlt) return 'Carbs';
    return 'Fat';
  }
}

// ------------------------------------------------------------ meal section

class _MealSection extends StatelessWidget {
  final String date;
  final String meal;
  final List<LogEntry> logs;
  const _MealSection({required this.date, required this.meal, required this.logs});

  String get _label => _cap(meal);

  @override
  Widget build(BuildContext context) {
    final kcal = logs.fold<double>(0, (a, l) => a + l.kcal);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: MtTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
              child: Row(
                children: [
                  Text(_label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(width: 8),
                  if (logs.isNotEmpty)
                    Text('${kcal.round()} kcal',
                        style: const TextStyle(
                            fontSize: 12, color: MtTheme.textDim)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add to $_label',
                    icon: const Icon(Icons.add_circle_outline,
                        size: 22, color: MtTheme.accent),
                    onPressed: () =>
                        showAddFoodSheet(context, date: date, meal: meal),
                  ),
                ],
              ),
            ),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      showAddFoodSheet(context, date: date, meal: meal),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16, color: MtTheme.textDim.withValues(alpha: 0.7)),
                      const SizedBox(width: 6),
                      Text('Add food',
                          style: TextStyle(
                              fontSize: 13, color: MtTheme.textDim.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              )
            else
              for (final l in logs)
                _EntryTile(entry: l),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final LogEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final macroStr = entry.grams > 0
        ? 'P${entry.protein.round()} · C${entry.carbs.round()} · F${entry.fat.round()}'
        : 'P${entry.protein.round()}g C${entry.carbs.round()}g F${entry.fat.round()}g';
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: const BoxDecoration(
          color: MtTheme.danger,
          borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: MtTheme.surface,
                title: const Text('Delete entry?'),
                content: Text('Remove "${entry.name}" from the log?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        if (entry.id != null) await Db.deleteLog(entry.id!);
        AppState.instance.refresh();
      },
      child: ListTile(
        dense: true,
        onTap: () => showEditEntrySheet(context, entry),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.fasted && entry.kcal == 0 && entry.name != 'Fasted'
                    ? '${entry.name} (fasted)'
                    : entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            Text('${entry.kcal.round()} kcal',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MtTheme.accent)),
          ],
        ),
        subtitle: Text(
          entry.grams > 0
              ? '${_fmtG(entry.grams)}g · $macroStr'
              : '${entry.brand.isEmpty ? '' : '${entry.brand} · '}$macroStr',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: MtTheme.textDim),
        ),
      ),
    );
  }
}

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _fmtG(double g) =>
    g == g.roundToDouble() ? g.round().toString() : g.toStringAsFixed(1);
