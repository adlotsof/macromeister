// Program screen: program overview, current targets, check-in history.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';
import 'checkin_screen.dart';
import 'onboarding_screen.dart';
import 'program_edit_screen.dart';

class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  Profile? _profile;
  List<CheckIn> _checkIns = [];
  List<WeightEntry> _weights = [];
  MacroTargets? _targets;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onChanged);
    _load();
  }

  void _onChanged() => _load();

  @override
  void dispose() {
    AppState.instance.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await Db.loadProfile();
    final checkIns = await Db.checkIns();
    final weights = await Db.weights();
    final targets = profile == null ? null : await AppState.instance.currentTargets();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _checkIns = checkIns;
      _weights = weights;
      _targets = targets;
      _loaded = true;
    });
  }

  /// Next check-in: same weekday as the profile's setting, on or after today.
  DateTime _nextCheckIn(Profile p) {
    final t = today();
    var diff = p.checkinWeekday - t.weekday;
    if (diff < 0) diff += 7;
    if (diff == 0 && _checkIns.isNotEmpty &&
        _checkIns.first.date == fmtDate(t)) {
      diff = 7;
    }
    return t.add(Duration(days: diff));
  }

  Future<void> _openCheckIn() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CheckInScreen()));
    _load();
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProgramEditScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _profile;
    if (p == null) return _noProgram();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _header(p),
          const SizedBox(height: 16),
          _targetsCard(),
          const SizedBox(height: 16),
          _checkInCard(p),
          const SizedBox(height: 16),
          _programCard(p),
          const SizedBox(height: 16),
          if (_checkIns.isNotEmpty) ...[
            Text('Check-in history',
                style: TextStyle(
                    color: MtTheme.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._checkIns.map(_historyTile),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _noProgram() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flag_outlined, size: 64, color: MtTheme.textDim),
              const SizedBox(height: 16),
              const Text('No program yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Answer a few questions and get a personalized calorie & macro program.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MtTheme.textDim),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const OnboardingScreen()));
                  _load();
                },
                icon: const Icon(Icons.rocket_launch_outlined),
                label: const Text('Start setup'),
              ),
            ],
          ),
        ),
      );

  Widget _header(Profile p) {
    final days = _daysUntilGoal(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your program',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          p.goalRateKgPerWeek < -0.05
              ? 'Losing ${p.goalRateKgPerWeek.abs().toStringAsFixed(2)} kg/week'
              : p.goalRateKgPerWeek > 0.05
                  ? 'Gaining ${p.goalRateKgPerWeek.toStringAsFixed(2)} kg/week'
                  : 'Maintaining weight',
          style: TextStyle(color: MtTheme.textDim),
        ),
        if (days != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Goal weight ${p.goalWeightKg.toStringAsFixed(1)} kg · $days',
              style: TextStyle(color: MtTheme.textDim, fontSize: 13),
            ),
          ),
      ],
    );
  }

  double _currentWeight() =>
      _weights.isNotEmpty ? _weights.last.weightKg : (_profile?.startWeightKg ?? 0);

  String? _daysUntilGoal(Profile p) {
    final current = _currentWeight();
    final remaining = (p.goalWeightKg - current).abs();
    if (p.goalRateKgPerWeek.abs() < 0.01 || remaining < 0.05) return null;
    final weeks = remaining / p.goalRateKgPerWeek.abs();
    return '~${weeks.toStringAsFixed(0)} weeks to go';
  }

  Widget _targetsCard() {
    final t = _targets;
    final p = _profile;
    if (t == null || p == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Current targets',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (p.programType == 'coached')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: MtTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Coached',
                        style: TextStyle(color: MtTheme.accent, fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _big('Calories', '${t.dailyTargetKcal.round()}'),
                _big('Expenditure', '${t.expenditure.round()}'),
                _big('Weight', '${_currentWeight().toStringAsFixed(1)} kg'),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                _macro('Protein', t.protein, MtTheme.accent),
                _macro('Carbs', t.carbs, MtTheme.accentAlt),
                _macro('Fat', t.fat, const Color(0xFFFFC46B)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _big(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _macro(String label, double grams, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
            ]),
            Text('${grams.round()} g',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _checkInCard(Profile p) {
    final next = _nextCheckIn(p);
    final dueToday = fmtDate(next) == fmtDate(today());
    return Card(
      color: dueToday ? MtTheme.surfaceHi : MtTheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.event_available,
                  color: dueToday ? MtTheme.accent : MtTheme.textDim, size: 20),
              const SizedBox(width: 8),
              Text(dueToday ? 'Check-in is due today' : 'Next check-in',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(
              dueToday
                  ? 'Weigh in and update your targets.'
                  : '${_weekdayName(p.checkinWeekday)}, ${fmtDate(next)}',
              style: TextStyle(color: MtTheme.textDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openCheckIn,
                icon: const Icon(Icons.scale),
                label: const Text('Do check-in'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _programCard(Profile p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Program settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _row('Goal weight', '${p.goalWeightKg.toStringAsFixed(1)} kg'),
              _row('Rate',
                  '${p.goalRateKgPerWeek > 0 ? '+' : ''}${p.goalRateKgPerWeek.toStringAsFixed(2)} kg/week'),
              _row('Activity', '×${p.activityFactor.toStringAsFixed(1)}'),
              if (p.dietStyle.isNotEmpty)
                _row('Diet style', p.dietStyle),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Edit program'),
              ),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: MtTheme.textDim)),
            Text(value, style: TextStyle(color: MtTheme.text)),
          ],
        ),
      );

  Widget _historyTile(CheckIn c) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(fmtDate(DateTime.parse(c.date)),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Target ${c.dailyTarget.round()} kcal · Expenditure ${c.expenditure.round()} kcal'
                  '${c.weightKg != null ? ' · ${c.weightKg!.toStringAsFixed(1)} kg' : ''}',
                  style: const TextStyle(fontSize: 12)),
              if (c.notes.isNotEmpty)
                Text(c.notes,
                    style:
                        TextStyle(color: MtTheme.textDim, fontSize: 12),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          isThreeLine: c.notes.isNotEmpty,
        ),
      );

  String _weekdayName(int d) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ][d - 1];
}
