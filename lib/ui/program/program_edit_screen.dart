// Program editor: edit profile fields after onboarding.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../services/expenditure.dart';
import '../../theme.dart';

class ProgramEditScreen extends StatefulWidget {
  const ProgramEditScreen({super.key});

  @override
  State<ProgramEditScreen> createState() => _ProgramEditScreenState();
}

class _ProgramEditScreenState extends State<ProgramEditScreen> {
  final _name = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _goalWeight = TextEditingController();
  final _birthYear = TextEditingController();
  final _dietStyle = TextEditingController();
  final _proteinG = TextEditingController();
  final _fatG = TextEditingController();
  Profile? _profile;
  bool _loaded = false;
  bool _customMacros = false;
  int _macroTargetKcal = 0;
  double _expKcal = 0;
  final _goalRate = TextEditingController();

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await Db.loadProfile();
    if (p == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _name.text = p.name;
    _height.text = p.heightCm.toStringAsFixed(0);
    _weight.text = p.startWeightKg.toStringAsFixed(1);
    _goalWeight.text = p.goalWeightKg.toStringAsFixed(1);
    _birthYear.text = p.birthYear.toString();
    _dietStyle.text = p.dietStyle;
    final custom = await Db.getSetting('macro_custom') == '1';
    final pg = await Db.getSetting('macro_protein_g');
    final fg = await Db.getSetting('macro_fat_g');
    _proteinG.text = pg ?? '';
    _fatG.text = fg ?? '';
    _goalRate.text = p.goalRateKgPerWeek.toStringAsFixed(2);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loaded = true;
      _customMacros = custom;
    });
    _refreshMacroKcal();
  }

  /// Live kcal preview for the macro editor (expenditure + goal-rate offset —
  /// the same formula the weekly check-in uses).
  Future<void> _refreshMacroKcal() async {
    final p = _profile;
    if (p == null || !mounted) return;
    final last = await Db.lastCheckIn();
    final weights = await Db.weights();
    final recent = await Db.logsBetween(
        fmtDate(today().subtract(const Duration(days: 60))), fmtDate(today()));
    final exp = ExpenditureEngine.expenditure(p, recent, weights,
        previousSmoothed: last?.expenditure);
    if (!mounted) return;
    setState(() => _macroTargetKcal =
        ExpenditureEngine.dailyTarget(exp, p.goalRateKgPerWeek).round());
    setState(() => _expKcal = exp);
  }

  /// Persists goal-rate changes and recomputes the displayed target.
  Future<void> _saveGoalParams() async {
    final rate = double.tryParse(_goalRate.text.replaceAll(',', '.'));
    if (rate == null || _profile == null) return;
    final updated = _profile!.copyWith(goalRateKgPerWeek: rate.clamp(-1.0, 1.0));
    setState(() => _profile = updated);
    await Db.saveProfile(updated);
    AppState.instance.refresh();
    await _refreshMacroKcal();
  }

  Future<void> _setCustomMacros(bool v) async {
    setState(() => _customMacros = v);
    await Db.setSetting('macro_custom', v ? '1' : '0');
    // Seed the fields with the current auto-computed split the first time
    // customization is enabled, so the user starts from sane values.
    if (v && _proteinG.text.isEmpty) {
      final t = await AppState.instance.currentTargets();
      if (!mounted) return;
      setState(() {
        _proteinG.text = t.protein.round().toString();
        _fatG.text = t.fat.round().toString();
      });
      await Db.setSetting('macro_protein_g', _proteinG.text);
      await Db.setSetting('macro_fat_g', _fatG.text);
    }
    await _refreshMacroKcal();
  }

  Future<void> _saveMacros() async {
    if (!_customMacros) return;
    final pg = double.tryParse(_proteinG.text.replaceAll(',', '.'));
    final fg = double.tryParse(_fatG.text.replaceAll(',', '.'));
    if (pg != null) {
      await Db.setSetting('macro_protein_g', pg.clamp(20, 500).toString());
    }
    if (fg != null) {
      await Db.setSetting('macro_fat_g', fg.clamp(10, 300).toString());
    }
    AppState.instance.refresh();
    await _refreshMacroKcal();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _height, _weight, _goalWeight, _birthYear, _dietStyle,
      _proteinG, _fatG, _goalRate
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final p = _profile;
    if (p == null) return;
    final h = double.tryParse(_height.text.replaceAll(',', '.'));
    final w = double.tryParse(_weight.text.replaceAll(',', '.'));
    final gw = double.tryParse(_goalWeight.text.replaceAll(',', '.'));
    final by = int.tryParse(_birthYear.text);
    String? err;
    if (h != null && (h < 80 || h > 260)) err = 'Height must be 80-260 cm.';
    if (w != null && (w < 25 || w > 500)) err = 'Weight must be 25-500 kg.';
    if (gw != null && (gw < 25 || gw > 500)) err = 'Goal weight must be 25-500 kg.';
    if (by != null && (by < 1900 || by > DateTime.now().year)) {
      err = 'Birth year must be 1900-${DateTime.now().year}.';
    }
    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: MtTheme.danger));
      }
      return;
    }
    final updated = p.copyWith(
      name: _name.text.trim(),
      heightCm: double.tryParse(_height.text.replaceAll(',', '.')) ?? p.heightCm,
      startWeightKg:
          double.tryParse(_weight.text.replaceAll(',', '.')) ?? p.startWeightKg,
      goalWeightKg: double.tryParse(_goalWeight.text.replaceAll(',', '.')) ??
          p.goalWeightKg,
      birthYear: int.tryParse(_birthYear.text) ?? p.birthYear,
      dietStyle: _dietStyle.text.trim(),
    );
    await Db.saveProfile(updated);
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (p == null) return const SizedBox.shrink();
    final exp = ExpenditureEngine.expenditure(p, [], []);
    return Scaffold(
      backgroundColor: MtTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Edit program'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estimates from current data',
                      style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
                  const SizedBox(height: 10),
                  _row('Starting TDEE estimate',
                      '${(_expKcal > 0 ? _expKcal : exp).round()} kcal/day'),
                  _row('Current target',
                      '${ExpenditureEngine.dailyTarget(exp, p.goalRateKgPerWeek).round()} kcal/day'),
                  _row('Goal rate',
                      '${p.goalRateKgPerWeek > 0 ? '+' : ''}${p.goalRateKgPerWeek.toStringAsFixed(2)} kg/week'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _customMacros,
                    activeThumbColor: MtTheme.accent,
                    title: const Text('Customize macro targets'),
                    subtitle: const Text(
                        'Fixed protein & fat grams/day, carbs fill the rest'),
                    onChanged: _setCustomMacros,
                  ),
                  if (_customMacros) ...[
                    Text('Target $_macroTargetKcal kcal/day',
                        style:
                            const TextStyle(color: MtTheme.textDim, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _proteinG,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Protein', suffixText: 'g/day'),
                          onChanged: (_) => _saveMacros(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _fatG,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Fat', suffixText: 'g/day'),
                          onChanged: (_) => _saveMacros(),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final pg = double.tryParse(
                              _proteinG.text.replaceAll(',', '.')) ??
                          0;
                      final fg = double.tryParse(
                              _fatG.text.replaceAll(',', '.')) ??
                          0;
                      final carbs =
                          (((_macroTargetKcal - pg * 4 - fg * 9) / 4)
                                  .floorToDouble())
                              .clamp(0.0, 2000.0);
                      return Text(
                          'Carbs auto: ${carbs.round()} g/day  ·  '
                          'P${(pg * 4).round()} F${(fg * 9).round()} C${(carbs * 4).round()} kcal',
                          style: const TextStyle(
                              color: MtTheme.textDim, fontSize: 12));
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _labeled('Name', TextField(controller: _name)),
          _labeled('Height (cm)', TextField(controller: _height, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          _labeled('Starting weight (kg)', TextField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          _labeled('Goal weight (kg)', TextField(controller: _goalWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          _labeled('Goal rate (kg/week, negative = losing)', TextField(controller: _goalRate, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), onChanged: (_) => _saveGoalParams())),
          const Text('Activity level',
              style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
          Slider(
            value: (_profile?.activityFactor ?? 1.4).clamp(1.2, 1.9),
            min: 1.2,
            max: 1.9,
            divisions: 7,
            label: '×${(_profile?.activityFactor ?? 1.4).toStringAsFixed(1)}',
            activeColor: MtTheme.accent,
            onChanged: (v) {
              setState(() =>
                  _profile = _profile!.copyWith(activityFactor: v));
              Db.saveProfile(_profile!.copyWith(activityFactor: v));
              _refreshMacroKcal();
            },
          ),
          _labeled('Birth year', TextField(controller: _birthYear, keyboardType: TextInputType.number)),
          _labeled('Diet style', TextField(controller: _dietStyle)),
          const SizedBox(height: 8),
          const Text('Weekly check-in day',
              style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              final d = i + 1;
              return ChoiceChip(
                label: Text(_weekdayNames[i].substring(0, 3)),
                selected: p.checkinWeekday == d,
                onSelected: (_) {
                  setState(() => _profile = p.copyWith(checkinWeekday: d));
                  Db.saveProfile(p.copyWith(checkinWeekday: d));
                },
                selectedColor: MtTheme.accent,
              );
            }),
          ),
          const SizedBox(height: 10),
          const Text('Coaching style',
              style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'coached', label: Text('Coached')),
              ButtonSegment(value: 'manual', label: Text('Manual')),
            ],
            selected: {p.programType},
            onSelectionChanged: (s) {
              setState(() => _profile = p.copyWith(programType: s.first));
              Db.saveProfile(p.copyWith(programType: s.first));
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _labeled(String label, Widget field) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: MtTheme.textDim, fontSize: 13)),
            const SizedBox(height: 6),
            field,
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: MtTheme.textDim)),
            Text(value, style: const TextStyle(color: MtTheme.text)),
          ],
        ),
      );
}
