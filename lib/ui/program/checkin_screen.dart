// Weekly check-in: weigh in, review expenditure, get a new daily target.
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../services/expenditure.dart';
import '../../theme.dart';

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _weight = TextEditingController();
  String? _error; // inline — snackbars would be hidden on pressed states
  final _notes = TextEditingController();
  Profile? _profile;
  CheckIn? _last;
  List<LogEntry> _recent = [];
  List<WeightEntry> _weights = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await Db.loadProfile();
    final last = await Db.lastCheckIn();
    final recent = await Db.logsBetween(
        fmtDate(today().subtract(const Duration(days: 28))), fmtDate(today()));
    final weights = await Db.weights();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _last = last;
      _recent = recent;
      _weights = weights;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _exp {
    final p = _profile;
    if (p == null) return null;
    return ExpenditureEngine.expenditure(p, _recent, _weights,
        previousSmoothed: _last?.expenditure, windowDays: 28);
  }

  double? get _newTarget {
    final p = _profile;
    final e = _exp;
    if (p == null || e == null) return null;
    return ExpenditureEngine.dailyTarget(e, p.goalRateKgPerWeek);
  }

  double? get _kcalAvg7 {
    final byDay = <String, double>{};
    for (final l in _recent) {
      if (DateTime.now().difference(DateTime.parse(l.date)).inDays > 7) continue;
      byDay[l.date] = (byDay[l.date] ?? 0) + l.kcal;
    }
    if (byDay.isEmpty) return null;
    return byDay.values.fold(0.0, (a, b) => a + b) / byDay.length;
  }

  Future<void> _save() async {
    final p = _profile;
    if (p == null) return;
    final now = today();
    final w = double.tryParse(_weight.text.replaceAll(',', '.'));
    if (w != null && (w < 25 || w > 400)) {
      setState(() => _error =
          'Weight must be between 25 and 400 kg — check-in not saved.');
      return;
    }
    if (w != null) await Db.upsertWeight(WeightEntry(date: fmtDate(now), weightKg: w));
    final exp = _exp ?? p.initialTdee;
    final target =
        _newTarget ?? ExpenditureEngine.dailyTarget(exp, p.goalRateKgPerWeek);
    await Db.insertCheckIn(CheckIn(
      date: fmtDate(now),
      weekStart: fmtDate(weekStart(now)),
      weightKg: w,
      kcalAvg7d: _kcalAvg7 ?? 0,
      expenditure: exp,
      dailyTarget: target,
      notes: _notes.text.trim(),
    ));
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) {
      return const Scaffold(body: Center(child: Text('Set up a program first.')));
    }
    final lastWeight = _weights.isNotEmpty ? _weights.last.weightKg : null;
    final exp = _exp;
    final target = _newTarget;
    final avg = _kcalAvg7;
    return Scaffold(
      backgroundColor: MtTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Weekly check-in'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: MtTheme.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_error!,
                  style: const TextStyle(color: MtTheme.danger, fontSize: 13)),
            ),
            const SizedBox(height: 10),
          ],
          _card('Weight', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "Today's weight (kg)",
                  hintText: lastWeight != null
                      ? 'Last: ${lastWeight.toStringAsFixed(1)} kg'
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Optional — but keeps your trend accurate.',
                  style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
            ],
          )),
          _card('Last 7 days', child: Column(
            children: [
              _row('Average intake', avg == null ? '—' : '${avg.round()} kcal'),
              _row('Est. expenditure',
                  exp == null ? '—' : '${exp.round()} kcal'),
            ],
          )),
          _card('New daily target', accent: true, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target == null ? '—' : '${target.round()} kcal/day',
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold, color: MtTheme.accent),
              ),
              if (exp != null && target != null)
                Text(
                  'Expenditure ${exp.round()} kcal ${target < exp ? '−' : '+'} ${(target - exp).abs().round()} kcal for your goal.',
                  style: const TextStyle(color: MtTheme.textDim, fontSize: 13),
                ),
            ],
          )),
          _card('Notes', child: TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'How did the week go? (optional)'),
          )),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save check-in'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _card(String title, {required Widget child, bool accent = false}) =>
      Card(
        margin: const EdgeInsets.only(bottom: 14),
        color: accent ? MtTheme.surfaceHi : MtTheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: accent ? MtTheme.accent : MtTheme.textDim,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: MtTheme.textDim)),
            Text(value, style: const TextStyle(color: MtTheme.text)),
          ],
        ),
      );
}
