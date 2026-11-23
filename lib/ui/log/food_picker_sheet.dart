// Food picker: the SAME search (my foods / USDA common / Open Food Facts)
// and barcode scan as the add-food sheet, returning a Food. Used by the
// recipe editor so ingredients can consist of existing foods instead of
// hand-typed macros.
import 'dart:async';

// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../db.dart';
import '../../models.dart';
import '../../services/food_search.dart';
import '../../theme.dart';
import 'barcode_screen.dart';

Future<Food?> showFoodPickerSheet(BuildContext context) {
  return showModalBottomSheet<Food>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MtTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _FoodPickerSheet(),
  );
}

class _FoodPickerSheet extends StatefulWidget {
  const _FoodPickerSheet();
  @override
  State<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends State<_FoodPickerSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<Food> _local = [], _common = [], _off = [];
  int _offCount = 0;
  bool _loadingOff = false, _scanned = false;
  String _searchedFor = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

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
    if (trimmed.length < 3) {
      _scanned = true;
      return;
    }
    if (mounted) setState(() => _loadingOff = true);
    final res = await searchOff(trimmed);
    if (!mounted || _searchedFor != trimmed) return;
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
    if (!mounted) return;
    if (food != null) Navigator.pop(context, food);
  }

  Widget _tile(Food f, String? highlight) => ListTile(
        dense: true,
        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          highlight == null || highlight.isEmpty
              ? '${f.kcal.round()} kcal/100g · P${f.protein.round()} C${f.carbs.round()} F${f.fat.round()}'
              : '$highlight · ${f.kcal.round()} kcal/100g',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: MtTheme.textDim, fontSize: 12),
        ),
        trailing: Icon(Icons.check_circle_outline,
            size: 20, color: MtTheme.accent),
        onTap: () => Navigator.pop(context, f),
      );

  @override
  Widget build(BuildContext context) {
    final localIds = _off.map((f) => f.offId).toSet();
    final localShown =
        _local.where((f) => f.offId == null || !localIds.contains(f.offId)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                const Expanded(
                    child: Text('Pick a food for the ingredient',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                    icon: Icon(Icons.close, color: MtTheme.textDim),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
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
                              icon: Icon(Icons.clear,
                                  size: 18, color: MtTheme.textDim),
                              onPressed: () {
                                _controller.clear();
                                _search('');
                              }),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Scan barcode',
                  style: IconButton.styleFrom(
                      backgroundColor: MtTheme.surfaceHi,
                      foregroundColor: MtTheme.accent),
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  onPressed: _scan,
                ),
              ]),
            ),
            Divider(height: 1, color: MtTheme.surfaceHi),
            Expanded(
              child: _controller.text.trim().isEmpty
                  ? ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        const SizedBox(height: 32),
                        Center(
                            child: Text('Search for the ingredient\'s food.',
                                style: TextStyle(color: MtTheme.textDim))),
                      ])
                  : _results(localShown),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(List<Food> localShown) {
    // Same dedupe rule as the add sheet: one row per name+brand.
    final merged = dedupeFoodsByName([
      ...localShown.map((f) => f),
      ..._common,
      ..._off,
    ]);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_offCount > merged.length)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Open Food Facts ($_offCount results)',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      color: MtTheme.textDim,
                      fontWeight: FontWeight.w700))),
        for (final f in merged)
          _tile(
              f,
              localShown.contains(f)
                  ? 'My food'
                  : _common.contains(f)
                      ? 'Common food'
                      : f.brand),
        if (_loadingOff)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))))
        else if (_scanned && merged.isEmpty)
          Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text('No results.',
                      style: TextStyle(color: MtTheme.textDim)))),
      ],
    );
  }
}
