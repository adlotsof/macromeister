// Onboarding: first-run program setup wizard.
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _height = TextEditingController(text: '175');
  final _weight = TextEditingController(text: '75');
  final _goalWeight = TextEditingController(text: '70');
  final _birthYear = TextEditingController(text: '1990');
  final _dietStyle = TextEditingController();
  String _sex = 'male';
  double _goalRate = -0.25;
  double _activity = 1.4;
  int _checkinWeekday = 1;
  String _programType = 'coached';
  int _step = 0;

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  Profile get _profile => Profile(
        name: _name.text.trim(),
        sex: _sex,
        birthYear: int.tryParse(_birthYear.text) ?? 1990,
        heightCm: double.tryParse(_height.text) ?? 175,
        startWeightKg: double.tryParse(_weight.text) ?? 75,
        goalWeightKg: double.tryParse(_goalWeight.text) ?? 70,
        goalRateKgPerWeek: _goalRate,
        activityFactor: _activity,
        dietStyle: _dietStyle.text.trim(),
        checkinWeekday: _checkinWeekday,
        programType: _programType,
      );

  @override
  void dispose() {
    for (final c in [
      _name, _height, _weight, _goalWeight, _birthYear, _dietStyle
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _finish() async {
    final p = _profile;
    await Db.saveProfile(p);
    await Db.upsertWeight(WeightEntry(date: fmtDate(today()), weightKg: p.startWeightKg));
    await Db.setSetting('onboarding_done', '1');
    if (!mounted) return;
    AppState.instance.refresh();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  bool _validateStep() {
    if (_step == 0) {
      final y = int.tryParse(_birthYear.text.trim());
      // Empty or out-of-range birth year must block Next — otherwise BMR is
      // silently computed with a default year.
      return y != null && y >= 1900 && y <= DateTime.now().year;
    }
    if (_step == 1) {
      return (double.tryParse(_height.text) ?? 0) > 80 &&
          (double.tryParse(_weight.text) ?? 0) > 25;
    }
    if (_step == 2) {
      final goal = double.tryParse(_goalWeight.text) ?? 0;
      if (goal <= 25) return false;
      // Goal must be in the direction of the goal rate: losing to a weight
      // above the current one (or gaining to one below) is contradictory.
      final start = double.tryParse(_weight.text) ?? 0;
      if (_goalRate < -0.01 && goal >= start) return false;
      if (_goalRate > 0.01 && goal <= start) return false;
      return true;
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid values.')));
      return;
    }
    if (_step < 4) {
      setState(() => _step += 1);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Set up your program'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 5,
              backgroundColor: MtTheme.surface,
              color: MtTheme.accent,
              minHeight: 3,
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [_stepBody()],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step -= 1),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_step == 4 ? 'Create program' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _about();
      case 1:
        return _body();
      case 2:
        return _goal();
      case 3:
        return _activityStep();
      default:
        return _prefs();
    }
  }

  Widget _title(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: MtTheme.text)),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(sub, style: const TextStyle(color: MtTheme.textDim, fontSize: 14)),
              ),
          ],
        ),
      );

  Widget _about() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('About you', 'Used to estimate your starting metabolism.'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', label: Text('Male')),
              ButtonSegment(value: 'female', label: Text('Female')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _birthYear,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Birth year'),
          ),
        ],
      );

  Widget _body() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Your body'),
          TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Height (cm)'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Current weight (kg)'),
          ),
        ],
      );

  Widget _goal() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Your goal'),
          TextField(
            controller: _goalWeight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Goal weight (kg)'),
          ),
          const SizedBox(height: 20),
          Text('Weekly rate: ${_goalRate.toStringAsFixed(2)} kg/week',
              style: const TextStyle(color: MtTheme.text)),
          Slider(
            value: _goalRate,
            min: -1.0,
            max: 0.5,
            divisions: 30,
            label: '${_goalRate > 0 ? '+' : ''}${_goalRate.toStringAsFixed(2)}',
            onChanged: (v) => setState(() => _goalRate = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Lose', style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
              const Text('Maintain', style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
              const Text('Gain', style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
            ],
          ),
        ],
      );

  static const _activityLevels = [
    ('Sedentary', 1.2),
    ('Light', 1.4),
    ('Moderate', 1.6),
    ('High', 1.8),
    ('Very high', 2.0),
  ];

  Widget _activityStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Activity level', 'Your typical day-to-day movement, outside training.'),
          ..._activityLevels.map((a) => RadioListTile<double>(
                value: a.$2,
                groupValue: _activity,
                onChanged: (v) => setState(() => _activity = v!),
                title: Text(a.$1),
                subtitle: Text('×${a.$2.toStringAsFixed(1)}',
                    style: const TextStyle(color: MtTheme.textDim, fontSize: 12)),
                activeColor: MtTheme.accent,
              )),
        ],
      );

  Widget _prefs() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Program preferences'),
          TextField(
            controller: _dietStyle,
            decoration: const InputDecoration(
                labelText: 'Diet style (e.g. high protein, vegetarian)'),
          ),
          const SizedBox(height: 18),
          const Text('Weekly check-in day', style: TextStyle(color: MtTheme.textDim)),
          Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              final d = i + 1;
              return ChoiceChip(
                label: Text(_weekdayNames[i].substring(0, 3)),
                selected: _checkinWeekday == d,
                onSelected: (_) => setState(() => _checkinWeekday = d),
                selectedColor: MtTheme.accent,
              );
            }),
          ),
          const SizedBox(height: 18),
          const Text('Coaching style', style: TextStyle(color: MtTheme.textDim)),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'coached', label: Text('Coached')),
              ButtonSegment(value: 'manual', label: Text('Manual')),
            ],
            selected: {_programType},
            onSelectionChanged: (s) => setState(() => _programType = s.first),
          ),
        ],
      );
}
