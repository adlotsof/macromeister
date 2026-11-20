// Habits: create, delete, mark done, streak counts. Backs the dashboard
// habits card (previously the DB layer existed but no management UI).
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  List<Habit> _habits = [];
  Map<int, List<String>> _days = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final habits = await Db.habits();
    final days = <int, List<String>>{};
    for (final h in habits) {
      days[h.id!] = await Db.habitDays(h.id!);
    }
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _days = days;
      _loading = false;
    });
  }

  /// Consecutive done-days ending today (or yesterday if today not yet done).
  int _streak(List<String> days) {
    if (days.isEmpty) return 0;
    final set = days.toSet();
    var d = today();
    if (!set.contains(fmtDate(d))) d = d.subtract(const Duration(days: 1));
    var streak = 0;
    while (set.contains(fmtDate(d))) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> _add() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('New habit'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Habit name',
              hintText: 'e.g. Log every meal, Weigh in'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await Db.upsertHabit(Habit(name: name, type: 'custom', active: true));
    AppState.instance.refresh();
    _load();
  }

  Future<void> _delete(Habit h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: Text('Delete "${h.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: MtTheme.danger),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.deleteHabit(h.id!);
    AppState.instance.refresh();
    _load();
  }

  Future<void> _toggle(Habit h) async {
    await Db.toggleHabitDay(h.id!, fmtDate(today()));
    AppState.instance.refresh();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Habits'), actions: [
        IconButton(icon: const Icon(Icons.add), onPressed: _add),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _habits.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.track_changes,
                          size: 40, color: MtTheme.textDim),
                      const SizedBox(height: 12),
                      Text('No habits yet. Tap + to create one — '
                          'build streaks for logging and weigh-ins.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MtTheme.textDim)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final h in _habits)
                      Card(
                        child: ListTile(
                          title: Text(h.name),
                          subtitle: Text(
                              'Streak: ${_streak(_days[h.id] ?? [])} day(s) · '
                              '${(_days[h.id] ?? []).length} total'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Mark done today',
                              icon: Icon(
                                  (_days[h.id] ?? [])
                                          .contains(fmtDate(today()))
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: MtTheme.accent),
                              onPressed: () => _toggle(h),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: Icon(Icons.delete_outline,
                                  color: MtTheme.textDim),
                              onPressed: () => _delete(h),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}
