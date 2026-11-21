// Onboarding: first-run program setup wizard.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
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
  double _rateMag = 0.25;
  double _activity = 1.4;
  int _checkinWeekday = 1;
  String _programType = 'coached';
  int _step = 0;

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  double get _currentW => double.tryParse(_weight.text) ?? 75;
  double get _goalW => double.tryParse(_goalWeight.text) ?? 70;

  /// Rate with the sign derived from the goal direction: goal below the
  /// current weight means losing (negative), above means gaining, equal
  /// means maintain (0). The slider only picks the magnitude, so a
  /// contradictory "gaining towards a lower goal" can't be created.
  double get _signedRate {
    if ((_goalW - _currentW).abs() < 0.01) return 0;
    return (_goalW > _currentW ? 1 : -1) * _rateMag;
  }

  String get _directionLabel {
    final r = _signedRate;
    if (r.abs() < 0.01) return 'Maintain weight';
    return r < 0 ? 'Lose ${r.abs().toStringAsFixed(2)} kg/week'
                 : 'Gain ${r.toStringAsFixed(2)} kg/week';
  }

  Profile get _profile => Profile(
        name: _name.text.trim(),
        sex: _sex,
        birthYear: int.tryParse(_birthYear.text) ?? 1990,
        heightCm: double.tryParse(_height.text) ?? 175,
        startWeightKg: double.tryParse(_weight.text) ?? 75,
        goalWeightKg: double.tryParse(_goalWeight.text) ?? 70,
        goalRateKgPerWeek: _signedRate,
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
            Text(t, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: MtTheme.text)),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(sub, style: TextStyle(color: MtTheme.textDim, fontSize: 14)),
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
          Text(_directionLabel, style: TextStyle(color: MtTheme.text)),
          const SizedBox(height: 8),
          Slider(
            value: _rateMag,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '${_rateMag.toStringAsFixed(2)} kg/week',
            onChanged: (v) => setState(() => _rateMag = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Slow', style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
              Text('Balanced', style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
              Text('Fast', style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Direction is derived from your goal: '
            '${_goalW < _currentW ? 'goal below your current weight = losing' : _goalW > _currentW ? 'goal above your current weight = gaining' : 'goal equals your current weight = maintaining'}.',
            style: TextStyle(color: MtTheme.textDim, fontSize: 12),
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
          RadioGroup<double>(
            groupValue: _activity,
            onChanged: (v) => setState(() => _activity = v!),
            child: Column(
              children: _activityLevels
                  .map((a) => RadioListTile<double>(
                        value: a.$2,
                        title: Text(a.$1),
                        subtitle: Text('×${a.$2.toStringAsFixed(1)}',
                            style: TextStyle(
                                color: MtTheme.textDim, fontSize: 12)),
                        activeColor: MtTheme.accent,
                      ))
                  .toList(),
            ),
          ),
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
          Text('Weekly check-in day', style: TextStyle(color: MtTheme.textDim)),
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
          Text('Coaching style', style: TextStyle(color: MtTheme.textDim)),
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
