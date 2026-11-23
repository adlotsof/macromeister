// Recipe editor: name, servings, ingredient list with per-100g macros,
// steps. Totals are computed live and stored per serving.
import 'dart:convert';

// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';

class _Ingredient {
  String name;
  double grams, kcal, protein, carbs, fat; // macros are per 100 g
  _Ingredient(
      {this.name = '',
      this.grams = 100,
      this.kcal = 0,
      this.protein = 0,
      this.carbs = 0,
      this.fat = 0});

  Map<String, Object?> toMap() => {
        'name': name,
        'grams': grams,
        'kcal': kcal * grams / 100,
        'protein': protein * grams / 100,
        'carbs': carbs * grams / 100,
        'fat': fat * grams / 100,
      };
}

class RecipeEditorScreen extends StatefulWidget {
  final Recipe? existing;
  const RecipeEditorScreen({super.key, this.existing});
  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _steps;
  late int _servings;
  late List<_Ingredient> _ings;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _name = TextEditingController(text: r?.name ?? '');
    _steps = TextEditingController(text: r?.steps ?? '');
    _servings = r?.servings ?? 1;
    _ings = r == null
        ? []
        : Recipe.decodeIngredients(r.ingredientsJson)
            .map((m) {
              final g = (m['grams'] as num?)?.toDouble() ?? 100;
              // Guard against 0-gram rows: division would produce NaN and
              // poison the recipe totals and every log entry made from it.
              final per100 = g > 0 ? 100.0 / g : 0.0;
              return _Ingredient(
                  name: (m['name'] ?? '') as String,
                  grams: g,
                  kcal: ((m['kcal'] as num?)?.toDouble() ?? 0) * per100,
                  protein: ((m['protein'] as num?)?.toDouble() ?? 0) * per100,
                  carbs: ((m['carbs'] as num?)?.toDouble() ?? 0) * per100,
                  fat: ((m['fat'] as num?)?.toDouble() ?? 0) * per100,
                );
            })
            .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _steps.dispose();
    super.dispose();
  }

  _Totals get _totals {
    double k = 0, p = 0, c = 0, f = 0;
    for (final i in _ings) {
      k += i.kcal * i.grams / 100;
      p += i.protein * i.grams / 100;
      c += i.carbs * i.grams / 100;
      f += i.fat * i.grams / 100;
    }
    final s = _servings < 1 ? 1 : _servings;
    return _Totals(kcal: k / s, protein: p / s, carbs: c / s, fat: f / s);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give the recipe a name')));
      return;
    }
    final t = _totals;
    final recipe = Recipe(
      id: widget.existing?.id,
      name: _name.text.trim(),
      servings: _servings < 1 ? 1 : _servings,
      ingredientsJson: jsonEncode(_ings.map((e) => e.toMap()).toList()),
      kcal: t.kcal,
      protein: t.protein,
      carbs: t.carbs,
      fat: t.fat,
      steps: _steps.text.trim(),
    );
    try {
      await Db.upsertRecipe(recipe);
      // ignore: avoid_print
      print('RECIPE saved id ok');
    } catch (e) {
      // ignore: avoid_print
      print('RECIPE save ERROR $e');
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editIngredient(int index) async {
    final ing = _ings[index];
    final c = {
      'name': TextEditingController(text: ing.name),
      'grams': TextEditingController(text: _num(ing.grams)),
      'kcal': TextEditingController(text: _num(ing.kcal)),
      'protein': TextEditingController(text: _num(ing.protein)),
      'carbs': TextEditingController(text: _num(ing.carbs)),
      'fat': TextEditingController(text: _num(ing.fat)),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Ingredient'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: c['name'],
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                  controller: c['grams'],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Grams')),
              const SizedBox(height: 8),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Macros per 100 g',
                      style: TextStyle(color: MtTheme.textDim, fontSize: 12))),
              for (final label in ['kcal', 'protein', 'carbs', 'fat'])
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                      controller: c[label],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: label)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Done')),
        ],
      ),
    );
    if (ok != true) return;
    double d(TextEditingController? ctl) =>
        double.tryParse(ctl?.text.replaceAll(',', '.') ?? '') ?? 0;
    setState(() {
      ing.name = c['name']!.text.trim();
      ing.grams = d(c['grams']);
      // A 0-gram ingredient cannot carry per-100g macros (division by zero).
      if (ing.grams <= 0) ing.grams = 1;
      ing.kcal = d(c['kcal']);
      ing.protein = d(c['protein']);
      ing.carbs = d(c['carbs']);
      ing.fat = d(c['fat']);
    });
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New recipe' : 'Edit recipe'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.check)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Recipe name'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Servings'),
              Expanded(
                child: Slider(
                  value: _servings.clamp(1, 20).toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: '$_servings',
                  onChanged: (v) => setState(() => _servings = v.round()),
                ),
              ),
              Text('$_servings'),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Text('Ingredients',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _ings.add(_Ingredient())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          for (var i = 0; i < _ings.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_ings[i].name.isEmpty
                    ? '(unnamed ingredient)'
                    : _ings[i].name),
                subtitle: Text(
                    '${_num(_ings[i].grams)} g · '
                    '${(_ings[i].kcal * _ings[i].grams / 100).toStringAsFixed(0)} kcal'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        onPressed: () => _editIngredient(i),
                        icon: const Icon(Icons.edit_outlined, size: 20)),
                    IconButton(
                        onPressed: () =>
                            setState(() => _ings.removeAt(i)),
                        icon: Icon(Icons.delete_outline,
                            size: 20, color: MtTheme.danger)),
                  ],
                ),
                onTap: () => _editIngredient(i),
              ),
            ),
          if (_ings.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No ingredients yet.',
                  style: TextStyle(color: MtTheme.textDim)),
            ),
          const Divider(height: 32),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MtTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Per serving: ${t.kcal.toStringAsFixed(0)} kcal · '
              'P ${t.protein.toStringAsFixed(1)} g · '
              'C ${t.carbs.toStringAsFixed(1)} g · '
              'F ${t.fat.toStringAsFixed(1)} g',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _steps,
            maxLines: 6,
            decoration: const InputDecoration(
                labelText: 'Steps', alignLabelWithHint: true),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save recipe'),
          ),
        ],
      ),
    );
  }
}

class _Totals {
  final double kcal, protein, carbs, fat;
  _Totals(
      {required this.kcal,
      required this.protein,
      required this.carbs,
      required this.fat});
}
