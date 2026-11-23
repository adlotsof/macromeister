// Food detail sheet: adjust grams/servings + meal, then log the entry.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../services/meal_memory.dart';
import '../../models.dart';
import '../../theme.dart';

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

Future<void> openFoodDetailSheet(BuildContext context, Food food,
    {required String date,
    required String meal,
    String unitLabel = 'g',
    String? brandOverride}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: MtTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _FoodDetailSheet(
        food: food,
        date: date,
        meal: meal,
        unitLabel: unitLabel,
        brandOverride: brandOverride),
  );
}

class _FoodDetailSheet extends StatefulWidget {
  final Food food;
  final String date;
  final String meal;

  /// 'g' for foods (macros per 100 g), 'servings' for recipes (macros per
  /// serving — the value IS the portion count).
  final String unitLabel;
  final String? brandOverride;
  const _FoodDetailSheet(
      {required this.food,
      required this.date,
      required this.meal,
      this.unitLabel = 'g',
      this.brandOverride});
  @override
  State<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<_FoodDetailSheet> {
  late final TextEditingController _grams;
  late String _meal;
  bool _fasted = false;

  double get _gramsValue {
    final v = double.tryParse(_grams.text.replaceAll(',', '.'));
    return (v == null || v < 0) ? 0 : v;
  }

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
    if (widget.unitLabel == 'servings') {
      _grams = TextEditingController(text: '1');
    } else {
      final s = widget.food.servingG;
      _grams = TextEditingController(
          text: s == s.roundToDouble() ? s.round().toString() : s.toStringAsFixed(1));
    }
    _grams.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double _for100(double per100) =>
      widget.unitLabel == 'servings'
          ? per100 * _gramsValue // per-serving values
          : per100 * _gramsValue / 100;

  Future<void> _log() async {
    final g = _gramsValue;
    if (g <= 0) {
      // A zero-gram entry is only valid as a fasted marker.
      if (!_fasted) return;
      await Db.insertLog(LogEntry(
        date: widget.date,
        meal: _meal,
        name: widget.food.name,
        brand: widget.food.brand,
        grams: 0,
        kcal: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        fiber: 0,
        fasted: true,
      ));
      AppState.instance.refresh();
      if (mounted) {
        Navigator.of(context)
          ..pop()
          ..pop();
      }
      return;
    }
    // Save non-custom foods locally so they show up in search later.
    // Recipes are derived values (per-serving) — never stored as foods.
    if (widget.food.source != 'custom' &&
        widget.food.source != 'recipe') {
      await Db.upsertFood(widget.food);
    }
    await Db.insertLog(LogEntry(
      date: widget.date,
      meal: _meal,
      foodId: widget.food.source == 'custom' ? widget.food.id : null,
      name: widget.food.name,
      brand: widget.food.brand,
      grams: g,
      kcal: _for100(widget.food.kcal),
      protein: _for100(widget.food.protein),
      carbs: _for100(widget.food.carbs),
      fat: _for100(widget.food.fat),
      fiber: _for100(widget.food.fiber),
      fasted: _fasted,
    ));
    AppState.instance.refresh();
    if (mounted) {
      Navigator.of(context)
        ..pop() // detail sheet
        ..pop(); // add-food sheet
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(f.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: MtTheme.textDim),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if ((widget.brandOverride ?? f.brand).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(widget.brandOverride ?? f.brand,
                    style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
              ),
            const SizedBox(height: 8),
            // Macro summary for the entered amount
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MtTheme.surfaceHi,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _macro('kcal', _for100(f.kcal), big: true),
                  _macro('Protein', _for100(f.protein)),
                  _macro('Carbs', _for100(f.carbs)),
                  _macro('Fat', _for100(f.fat)),
                  if (f.fiber > 0) _macro('Fiber', _for100(f.fiber)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Serving quick buttons + grams field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grams,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: widget.unitLabel == 'servings'
                          ? 'Servings'
                          : 'Amount (grams)',
                      suffixText: widget.unitLabel == 'servings' ? '' : 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.unitLabel != 'servings' &&
                    f.servingG > 0 &&
                    f.servingG != 100)
                  OutlinedButton(
                    onPressed: () => _grams.text = _gStr(f.servingG),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: MtTheme.accentAlt),
                      foregroundColor: MtTheme.accentAlt,
                    ),
                    child: Text('1 srv (${_gStr(f.servingG)}g)'),
                  ),
                if (f.servingG != 100) ...[
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => _grams.text = '100',
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: MtTheme.textDim.withValues(alpha: 0.4)),
                      foregroundColor: MtTheme.textDim,
                    ),
                    child: const Text('100g'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Meal selector
            Wrap(
              spacing: 8,
              children: [
                for (final m in kMeals)
                  ChoiceChip(
                    label: Text(_cap(m)),
                    selected: _meal == m,
                    selectedColor: MtTheme.accent,
                    backgroundColor: MtTheme.surfaceHi,
                    labelStyle: TextStyle(
                        color: _meal == m
                            ? const Color(0xFF0B1512)
                            : MtTheme.text,
                        fontWeight:
                            _meal == m ? FontWeight.w700 : FontWeight.w400),
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _meal = m);
                      rememberMeal(m);
                    },
                  ),
              ],
            ),
            if (_gramsValue == 0)
              SwitchListTile(
                value: _fasted,
                onChanged: (v) => setState(() => _fasted = v),
                activeThumbColor: MtTheme.accent,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Fasted (zero-calorie marker)',
                    style: TextStyle(fontSize: 14)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (_gramsValue > 0 || _fasted) ? _log : null,
              child: Text(_fasted && _gramsValue == 0
                  ? 'Log fasted marker'
                  : 'Add to ${_cap(_meal)}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macro(String label, double v, {bool big = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(v.round().toString(),
              style: TextStyle(
                  fontSize: big ? 22 : 16,
                  fontWeight: FontWeight.w700,
                  color: big ? MtTheme.accent : MtTheme.text)),
          Text(label,
              style: TextStyle(fontSize: 11, color: MtTheme.textDim)),
        ],
      );
}

String _gStr(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
