// Add-food hub sheet: search (local + Open Food Facts), barcode scan,
// AI describe-a-meal (text or photo), quick add, custom food, recipe.
import 'dart:async';
import 'dart:io';

// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../services/camera_permission.dart';
import '../../services/meal_memory.dart';
import 'meal_picker.dart';
import '../../services/food_search.dart';
import '../../services/openai.dart';
import '../../theme.dart';
import 'barcode_screen.dart';
import 'custom_food_editor.dart';
import 'food_detail_sheet.dart';

/// Route args so the flow knows which day/meal to log into.
class AddFoodArgs {
  final String date;
  final String meal;
  AddFoodArgs({required this.date, this.meal = 'snack'});
}

Future<void> showAddFoodSheet(BuildContext context, {String? date, String? meal}) async {
  final d = date ?? AppState.instance.selectedDateStr;
  // The meal selector remembers its last state: when the caller does not
  // request a specific meal (the generic "+" button), start from the
  // meal the user chose last time; explicit calls (meal section headers)
  // still win. See lib/services/meal_memory.dart.
  final remembered = await initialMeal(explicit: meal);
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: MtTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddFoodSheet(date: d, meal: remembered),
  );
}

class _AddFoodSheet extends StatefulWidget {
  final String date;
  final String meal;
  const _AddFoodSheet({required this.date, required this.meal});
  @override
  State<_AddFoodSheet> createState() => _AddFoodSheetState();
}

enum _Tab { search, ai, quick, custom, recipe }

class _AddFoodSheetState extends State<_AddFoodSheet> {
  _Tab _tab = _Tab.search;
  String _meal = 'snack'; // initial meal for tabs; picker lives per-tab

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Add food',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: MtTheme.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Tab strip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tabChip(_Tab.search, 'Search', Icons.search),
                    const SizedBox(width: 8),
                    _tabChip(_Tab.ai, 'AI describe', Icons.auto_awesome),
                    const SizedBox(width: 8),
                    _tabChip(_Tab.quick, 'Quick add', Icons.bolt),
                    const SizedBox(width: 8),
                    _tabChip(_Tab.custom, 'Custom', Icons.edit_note),
                    const SizedBox(width: 8),
                    _tabChip(_Tab.recipe, 'Recipe', Icons.menu_book),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: MtTheme.surfaceHi),
            Expanded(
              child: switch (_tab) {
                _Tab.search => _SearchTab(date: widget.date, meal: _meal),
                _Tab.ai => _AiTab(date: widget.date, meal: _meal),
                _Tab.quick => _QuickAddTab(date: widget.date, meal: _meal),
                _Tab.custom => _CustomTab(date: widget.date, meal: _meal),
                _Tab.recipe => _RecipeTab(date: widget.date, meal: _meal),
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _tabChip(_Tab t, String label, IconData icon) => ChoiceChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: _tab == t ? const Color(0xFF0B1512) : MtTheme.textDim),
          const SizedBox(width: 5),
          Text(label),
        ]),
        selected: _tab == t,
        selectedColor: MtTheme.accent,
        backgroundColor: MtTheme.surfaceHi,
        labelStyle: TextStyle(
          color: _tab == t ? const Color(0xFF0B1512) : MtTheme.text,
          fontWeight: _tab == t ? FontWeight.w700 : FontWeight.w400,
        ),
        showCheckmark: false,
        onSelected: (_) => setState(() => _tab = t),
      );
}


// ---------------------------------------------------------------- search tab

class _SearchTab extends StatefulWidget {
  final String date;
  final String meal;
  const _SearchTab({required this.date, required this.meal});
  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Food> _local = [];
  List<Food> _common = [];
  List<Food> _off = [];
  int _offCount = 0;
  bool _loadingOff = false;
  bool _scanned = false;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  String _searchedFor = '';

  Future<void> _search(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      _searchedFor = '';
      if (mounted) {
        setState(() {
          _local = [];
          _common = [];
          _off = [];
          _offCount = 0;
          _loadingOff = false;
        });
      }
      return;
    }
    _searchedFor = trimmed;
    // Bundled databases (local user foods, USDA common foods, full OFF
    // database) searched CONCURRENTLY — sequentially this tripled the
    // time-to-first-result. Each result is applied as soon as it arrives.
    final localF = Db.searchLocalFoods(trimmed);
    final commonF = Db.searchCommonLocal(trimmed);
    final offLocalF = Db.searchOffLocal(trimmed);
    final local = await localF;
    if (!mounted || _searchedFor != trimmed) return;
    setState(() => _local = local);
    final common = await commonF;
    if (!mounted || _searchedFor != trimmed) return;
    setState(() => _common = common);
    final offLocal = await offLocalF;
    if (!mounted || _searchedFor != trimmed) return;
    setState(() {
      _off = offLocal;
      _offCount = offLocal.length;
    });
    // Remote Open Food Facts: only from 3 characters on — shorter queries
    // return noise and just delay the fresher remote results of a longer
    // query (MacroFactor gates remote search the same way).
    if (trimmed.length < 3) {
      _scanned = true;
      return;
    }
    if (mounted) setState(() => _loadingOff = true);
    final res = await searchOff(trimmed);
    if (!mounted || _searchedFor != trimmed) return;
    // Merge: online results first (freshest), then local-only rows not
    // already present (dedupe by barcode).
    final seen = res.foods.map((f) => f.offId).toSet();
    final merged = [
      ...res.foods,
      ...offLocal.where((f) => !seen.contains(f.offId)),
    ];
    setState(() {
      _off = merged;
      _offCount = merged.length;
      _loadingOff = false;
      _scanned = true;
    });
  }

  Future<void> _scan() async {
    final food = await showBarcodeScanner(context);
    if (food == null) return;
    if (!mounted) return;
    await openFoodDetailSheet(context, food, date: widget.date, meal: widget.meal);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search foods…',
                    prefixIcon: Icon(Icons.search, color: MtTheme.textDim),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.clear, size: 18, color: MtTheme.textDim),
                            onPressed: () {
                              _controller.clear();
                              _search('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Scan barcode',
                style: IconButton.styleFrom(
                  backgroundColor: MtTheme.surfaceHi,
                  foregroundColor: MtTheme.accent,
                ),
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _scan,
              ),
            ],
          ),
        ),
        Expanded(
          child: _controller.text.trim().isEmpty
              ? _recentAndSuggestions()
              : _results(),
        ),
      ],
    );
  }

  Widget _recentAndSuggestions() {
    return FutureBuilder<List<LogEntry>>(
      future: Db.logsForDay(fmtDate(today().subtract(const Duration(days: 1)))),
      builder: (context, snap) {
        final recentNames = <String, LogEntry>{};
        for (final l in snap.data ?? const <LogEntry>[]) {
          recentNames.putIfAbsent('${l.brand}|${l.name}', () => l);
        }
        return FutureBuilder<List<Food>>(
          future: Db.customFoods(),
          builder: (context, snap2) {
            final custom = snap2.data ?? const <Food>[];
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (recentNames.isNotEmpty) ...[
                  const _SectionLabel('Yesterday'),
                  for (final l in recentNames.values.take(6))
                    ListTile(
                      leading: Icon(Icons.history, color: MtTheme.textDim),
                      title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: l.brand.isEmpty
                          ? null
                          : Text(l.brand, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(
                          '${l.kcal.round()} kcal · ${_fmtG(l.grams)}g',
                          style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
                      onTap: () {
                        // Zero-gram entries (quick add / fasted / recipes)
                        // store totals directly — dividing by grams would
                        // produce Infinity/NaN and corrupt the day totals.
                        if (l.grams <= 0) {
                          _insert(
                            name: l.name,
                            brand: l.brand,
                            grams: l.grams,
                            kcal: l.kcal,
                            protein: l.protein,
                            carbs: l.carbs,
                            fat: l.fat,
                            fiber: l.fiber,
                          );
                          return;
                        }
                        _logQuick(
                          name: l.name,
                          brand: l.brand,
                          grams: l.grams,
                          kcal: l.kcal / l.grams * 100,
                          protein: l.protein / l.grams * 100,
                          carbs: l.carbs / l.grams * 100,
                          fat: l.fat / l.grams * 100,
                          fiber: l.fiber / l.grams * 100,
                        );
                      },
                    ),
                ],
                if (custom.isNotEmpty) ...[
                  const _SectionLabel('My foods'),
                  for (final f in custom.take(10))
                    ListTile(
                      leading: Icon(Icons.edit_note, color: MtTheme.accentAlt),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Long-press to edit',
                          style:
                              TextStyle(color: MtTheme.textDim, fontSize: 11)),
                      trailing: Text(
                          f.kcal > 0 ? '${f.kcal.round()} kcal/100g' : '—',
                          style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
                      onTap: () => openFoodDetailSheet(context, f,
                          date: widget.date, meal: widget.meal),
                      onLongPress: () {
                        // Capture the navigator BEFORE popping: after the
                        // pop this context is deactivated.
                        final nav = Navigator.of(context);
                        nav.pop();
                        // CustomFoodEditor has no Scaffold of its own (it is
                        // normally embedded in this sheet) — wrap it so the
                        // pushed route provides Material.
                        nav.push(MaterialPageRoute(
                            builder: (_) => Scaffold(
                                  backgroundColor: MtTheme.bg,
                                  appBar: AppBar(
                                      title: Text('Edit ${f.name}')),
                                  body: CustomFoodEditor(
                                      date: widget.date,
                                      meal: widget.meal,
                                      existing: f),
                                )));
                      },
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _results() {
    final localIds = _off.map((f) => f.offId).toSet();
    final localShown =
        _local.where((f) => f.offId == null || !localIds.contains(f.offId)).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (localShown.isNotEmpty) ...[
          const _SectionLabel('My foods & saved'),
          for (final f in localShown)
            _foodTile(f, highlight: 'My food'),
        ],
        if (_common.isNotEmpty) ...[
          const _SectionLabel('Common foods'),
          for (final f in _common)
            _foodTile(f, highlight: 'Common food'),
        ],
        if (_loadingOff)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_off.isNotEmpty) ...[
          _SectionLabel(
              'Open Food Facts${_offCount > _off.length ? ' ($_offCount results)' : ''}'),
          for (final f in _off)
            _foodTile(f, highlight: f.brand),
        ] else if (_scanned && localShown.isEmpty)
          Padding(
            padding: EdgeInsets.all(32),
            child: Center(
                child: Text('No results. Try the AI describe tab instead.',
                    style: TextStyle(color: MtTheme.textDim))),
          ),
      ],
    );
  }

  Widget _foodTile(Food f, {String? highlight}) => ListTile(
        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          highlight == null || highlight.isEmpty
              ? '${f.kcal.round()} kcal/100g · P${f.protein.round()} C${f.carbs.round()} F${f.fat.round()}'
              : '$highlight · ${f.kcal.round()} kcal/100g',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: MtTheme.textDim, fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
        onTap: () => openFoodDetailSheet(context, f, date: widget.date, meal: widget.meal),
      );

  Future<void> _logQuick({
    required String name,
    required String brand,
    required double grams,
    required double kcal, // per 100g
    required double protein,
    required double carbs,
    required double fat,
    required double fiber,
  }) async {
    await _insert(
      name: name,
      brand: brand,
      grams: grams,
      kcal: kcal * grams / 100,
      protein: protein * grams / 100,
      carbs: carbs * grams / 100,
      fat: fat * grams / 100,
      fiber: fiber * grams / 100,
    );
  }

  Future<void> _insert({
    required String name,
    required String brand,
    required double grams,
    required double kcal,
    required double protein,
    required double carbs,
    required double fat,
    required double fiber,
  }) async {
    await Db.insertLog(LogEntry(
      date: widget.date,
      meal: widget.meal,
      name: name,
      brand: brand,
      grams: grams,
      kcal: kcal,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
    ));
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                color: MtTheme.textDim,
                fontWeight: FontWeight.w700)),
      );
}

String _fmtG(double g) =>
    g == g.roundToDouble() ? g.round().toString() : g.toStringAsFixed(1);

// -------------------------------------------------------------------- AI tab

class _AiTab extends StatefulWidget {
  final String date;
  final String meal; // initial meal (remembered)
  const _AiTab({required this.date, required this.meal});
  @override
  State<_AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<_AiTab> {
  // Selected via the MealPicker next to the estimate action; initialized
  // from the remembered meal the sheet was opened with.
  String _meal = 'snack';
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
  }
  bool _loading = false;
  List<AiFoodGuess> _guesses = [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _parsePhoto() async {
    setState(() => _error = null);
    // Show the source picker FIRST — the no-key error is displayed inline in
    // this tab (a snackbar would be hidden behind this modal sheet).
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take a photo of the meal'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Pick from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    if (src == ImageSource.camera) {
      final camOk = await ensureCameraPermission();
      if (!mounted) return;
      if (!camOk) {
        setState(() => _error =
            'Camera permission denied. Enable it in system settings, or pick from the gallery.');
        return;
      }
    }
    setState(() => _loading = true);
    try {
      final x = await ImagePicker()
          .pickImage(source: src, imageQuality: 85, maxWidth: 2400, maxHeight: 2400);
      if (x == null || !mounted) {
        setState(() => _loading = false);
        return;
      }
      final cfg = await Ai.config();
      if (!mounted) return;
      if (cfg.key.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No AI key set — add one in More → AI settings first.';
        });
        return;
      }
      final bytes = await File(x.path).readAsBytes();
      final guesses = await Ai.parseMealPhoto(cfg, bytes);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _guesses = guesses;
      });
      if (guesses.isEmpty && mounted) {
        setState(() => _error =
            'AI could not identify foods in the photo. Try a clearer shot or describe it instead.');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong with the photo.';
        });
      }
    }
  }

  Future<void> _parse() async {
    final cfg = await Ai.config();
    if (!mounted) return;
    if (cfg.key.isEmpty) {
      // Inline: a snackbar here is hidden behind the modal sheet barrier.
      setState(() => _error =
          'No AI key set — add one in More → AI settings first.');
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Describe what you ate first.');
      return;
    }
    setState(() => _loading = true);
    final guesses = await Ai.parseMealDescription(cfg, text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _guesses = guesses;
    });
  }

  Future<void> _logAll() async {
    for (final g in _guesses) {
      await _logGuess(g, pop: false);
    }
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _logGuess(AiFoodGuess g, {bool pop = true}) async {
    await Db.insertLog(LogEntry(
      date: widget.date,
      meal: _meal,
      name: g.name,
      grams: g.grams,
      kcal: g.kcal * g.grams / 100,
      protein: g.protein * g.grams / 100,
      carbs: g.carbs * g.grams / 100,
      fat: g.fat * g.grams / 100,
      fiber: g.fiber * g.grams / 100,
    ));
    if (pop && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText:
                  'Describe what you ate, e.g. "2 eggs, a slice of toast with butter and a latte"'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _loading ? null : _parse,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Estimate with AI'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Estimate from photo',
            style: IconButton.styleFrom(
              backgroundColor: MtTheme.surfaceHi,
              foregroundColor: MtTheme.accent,
            ),
            icon: const Icon(Icons.photo_camera),
            onPressed: _loading ? null : _parsePhoto,
          ),
        ]),
        const SizedBox(height: 4),
        Text('Camera icon: let the AI estimate a meal from a photo.',
            style: TextStyle(color: MtTheme.textDim, fontSize: 11)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: MtTheme.danger, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        for (final g in _guesses) _guessTile(g),
        if (_guesses.length > 1) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _logAll,
            icon: const Icon(Icons.done_all, size: 18),
            label: Text('Log all ${_guesses.length} items'),
          ),
        ],
      ],
    );
  }

  Widget _guessTile(AiFoodGuess g) {
    final kcal = g.kcal * g.grams / 100;
    final confColor = switch (g.confidence) {
      'high' => MtTheme.accent,
      'low' => MtTheme.danger,
      _ => MtTheme.accentAlt,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: MtTheme.surfaceHi,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_fmtG(g.grams)}g · ${kcal.round()} kcal · P${(g.protein * g.grams / 100).round()} '
          'C${(g.carbs * g.grams / 100).round()} F${(g.fat * g.grams / 100).round()}',
          style: TextStyle(color: MtTheme.textDim, fontSize: 12),
        ),
        leading: Icon(Icons.circle, size: 10, color: confColor),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Adjust',
              icon: Icon(Icons.tune, size: 20, color: MtTheme.textDim),
              onPressed: () async {
                final food = Food(
                  name: g.name,
                  servingG: g.grams,
                  kcal: g.kcal,
                  protein: g.protein,
                  carbs: g.carbs,
                  fat: g.fat,
                  fiber: g.fiber,
                  source: 'ai',
                );
                await openFoodDetailSheet(context, food,
                    date: widget.date, meal: widget.meal);
              },
            ),
            IconButton(
              tooltip: 'Log',
              icon: Icon(Icons.add_circle, color: MtTheme.accent),
              onPressed: () async {
                await _logGuess(g);
                AppState.instance.refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- quick add

class _QuickAddTab extends StatefulWidget {
  final String date;
  final String meal;
  const _QuickAddTab({required this.date, required this.meal});
  @override
  State<_QuickAddTab> createState() => _QuickAddTabState();
}

class _QuickAddTabState extends State<_QuickAddTab> {
  late String _meal = widget.meal;
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _fasted = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  // Comma-decimal locales: '1,5' must parse as 1.5 everywhere.
  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final kcal = _num(_kcal);
    final p = _num(_protein);
    final c = _num(_carbs);
    final f = _num(_fat);
    if (kcal == 0 && !_fasted) {
      // Snackbar would render behind the modal barrier — show inline.
      setState(() => _error = 'Enter at least calories (or mark fasted).');
      return;
    }
    await Db.insertLog(LogEntry(
      date: widget.date,
      meal: _meal,
      name: _fasted ? 'Fasted' : 'Quick add',
      grams: 0,
      kcal: _fasted ? 0 : kcal,
      protein: _fasted ? 0 : p,
      carbs: _fasted ? 0 : c,
      fat: _fasted ? 0 : f,
      fasted: _fasted,
    ));
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
              child: _numField(_kcal, 'Calories', suffix: 'kcal',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _numField(_protein, 'Protein', suffix: 'g',
              keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 10),
          Expanded(child: _numField(_carbs, 'Carbs', suffix: 'g',
              keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 10),
          Expanded(child: _numField(_fat, 'Fat', suffix: 'g',
              keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        ]),
        const SizedBox(height: 8),
        MealPicker(initial: widget.meal, onChanged: (m) => _meal = m),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _fasted,
          onChanged: (v) => setState(() {
            _fasted = v;
            if (v) _error = null; // stale validation error is confusing
          }),
          activeThumbColor: MtTheme.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text('Fasted (zero-calorie marker)'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: MtTheme.danger, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.bolt, size: 18),
          label: const Text('Log it'),
        ),
      ],
    );
  }

  Widget _numField(TextEditingController c, String label,
          {String? suffix, TextInputType? keyboardType}) =>
      TextField(
        controller: c,
        keyboardType: keyboardType ?? TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );
}

// ---------------------------------------------------------------- custom tab

class _CustomTab extends StatelessWidget {
  final String date;
  final String meal;
  const _CustomTab({required this.date, required this.meal});
  @override
  Widget build(BuildContext context) => CustomFoodEditor(date: date, meal: meal);
}

// ---------------------------------------------------------------- recipe tab

class _RecipeTab extends StatefulWidget {
  final String date;
  final String meal;
  const _RecipeTab({required this.date, required this.meal});
  @override
  State<_RecipeTab> createState() => _RecipeTabState();
}

class _RecipeTabState extends State<_RecipeTab> {
  List<Recipe> _recipes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.recipes();
    if (mounted) {
      setState(() {
        _recipes = r;
        _loading = false;
      });
    }
  }

  // Recipes log through the SAME flow as foods: the detail sheet with the
  // per-item meal chips next to the Add button and a Servings editor.
  Future<void> _logRecipe(Recipe r) async {
    // Recipe macros are stored per serving; the sheet scales them by the
    // logged portion count.
    final f = recipePerServingFood(r);
    await openFoodDetailSheet(context, f,
        date: widget.date,
        meal: widget.meal,
        unitLabel: 'servings',
        brandOverride: 'Recipe');
    if (mounted) _load();
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: SizedBox(
              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_recipes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, size: 40, color: MtTheme.textDim),
            const SizedBox(height: 12),
            Text(
                'No saved recipes yet. Create one from paste or AI import on the More → Recipes screen, or paste a recipe below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MtTheme.textDim)),
            const SizedBox(height: 16),
              FilledButton.icon(
              onPressed: () => showAddFoodSheet(context,
                  date: widget.date, meal: widget.meal),
              icon: const Icon(Icons.search),
              label: const Text('Search or describe a food instead'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final r in _recipes)
          ListTile(
            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${r.servings} servings · ${r.kcal.round()} kcal · P${r.protein.round()} C${r.carbs.round()} F${r.fat.round()} per serving',
                style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
            trailing: Icon(Icons.add_circle, color: MtTheme.accent),
            onTap: () => _logRecipe(r),
          ),
      ],
    );
  }
}
