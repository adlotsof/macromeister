// Saved recipes: list, log a serving, edit, delete, and AI import from text.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../services/openai.dart';
import '../../theme.dart';
import 'recipe_editor.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});
  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  List<Recipe> _recipes = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await Db.recipes();
    if (!mounted) return;
    setState(() => _recipes = r);
  }

  Future<void> _openEditor([Recipe? recipe]) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RecipeEditorScreen(existing: recipe)));
    _reload();
  }

  Future<void> _aiImport() async {
    final cfg = await Ai.config();
    if (!mounted) return;
    if (cfg.key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add an AI key in More > AI settings first')));
      return;
    }
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Import recipe with AI'),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLines: 8,
            decoration: const InputDecoration(
                hintText:
                    'Paste a recipe (ingredients + steps). AI estimates the '
                    'nutrition per ingredient.'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Parse')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parsing recipe with AI...')));
    final recipe = await AiBridge.parseRecipeViaKey(text);
    if (!mounted) return;
    if (recipe == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('AI could not parse that recipe'),
          backgroundColor: MtTheme.danger));
      return;
    }
    await Db.upsertRecipe(recipe);
    _reload();
  }

  Future<void> _logServing(Recipe r) async {
    final meal = await _pickMeal();
    if (meal == null || !mounted) return;
    final d = AppState.instance.selectedDateStr;
    await Db.insertLog(LogEntry(
      date: d,
      meal: meal,
      name: r.name,
      brand: 'recipe · ${r.servings} serving${r.servings == 1 ? '' : 's'}/batch',
      grams: 0,
      kcal: r.kcal,
      protein: r.protein,
      carbs: r.carbs,
      fat: r.fat,
    ));
    AppState.instance.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Logged 1 serving of ${r.name} ($meal)')));
  }

  Future<String?> _pickMeal() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: MtTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in kMeals)
              ListTile(
                title: Text(m[0].toUpperCase() + m.substring(1)),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: [
          IconButton(
              onPressed: _aiImport,
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Import with AI'),
          IconButton(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              tooltip: 'New recipe'),
        ],
      ),
      body: _recipes.isEmpty
          ? const Center(
              child: Text('No recipes yet.\nUse + to build one or ✨ to import.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MtTheme.textDim)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _recipes.length,
              itemBuilder: (context, i) {
                final r = _recipes[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                                onPressed: () => _openEditor(r),
                                icon: const Icon(Icons.edit_outlined,
                                    size: 20, color: MtTheme.textDim)),
                            IconButton(
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                            title: Text('Delete "${r.name}"?'),
                                            content: const Text(
                                                'Logged entries keep their values, '
                                                'but the recipe is removed from '
                                                'your recipes.'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('Cancel')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('Delete')),
                                            ],
                                          ));
                                  if (ok != true || r.id == null) return;
                                  await Db.deleteRecipe(r.id!);
                                  _reload();
                                },
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: MtTheme.danger)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${r.kcal.toStringAsFixed(0)} kcal · '
                          'P ${r.protein.toStringAsFixed(1)}g · '
                          'C ${r.carbs.toStringAsFixed(1)}g · '
                          'F ${r.fat.toStringAsFixed(1)}g per serving '
                          '(${r.servings} servings)',
                          style: const TextStyle(
                              color: MtTheme.textDim, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => _logServing(r),
                            icon: const Icon(Icons.add_circle_outline,
                                size: 18),
                            label: const Text('Log serving'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Small helper so screens only need Db.getSetting + Ai without importing
/// the AI service directly at call sites.
class AiBridge {
  static Future<Recipe?> parseRecipeViaKey(String text) async {
    final cfg = await Ai.config();
    if (cfg.key.isEmpty) return null;
    return Ai.parseRecipe(cfg, text);
  }
}
