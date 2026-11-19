// Edit an existing log entry: tap an entry in the diary to change the
// serving size (gram-based entries) or the absolute macros (zero-gram
// quick-add entries), or delete the entry.
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';

Future<void> showEditEntrySheet(BuildContext context, LogEntry entry) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _EditEntrySheet(entry: entry),
  );
}

class _EditEntrySheet extends StatefulWidget {
  final LogEntry entry;
  const _EditEntrySheet({required this.entry});
  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  late final TextEditingController _grams;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _grams = TextEditingController(
        text: e.grams > 0 ? _numStr(e.grams) : '');
    _kcal = TextEditingController(text: _numStr(e.kcal));
    _protein = TextEditingController(text: _numStr(e.protein));
    _carbs = TextEditingController(text: _numStr(e.carbs));
    _fat = TextEditingController(text: _numStr(e.fat));
  }

  static String _numStr(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    for (final c in [_grams, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  double _p(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final e = widget.entry;
    if (e.grams > 0) {
      final g = _p(_grams);
      if (g <= 0) {
        setState(() => _error = 'Enter a serving size above 0 g.');
        return;
      }
      // Per-100g values from the stored absolute amounts, then re-scale.
      final per100 = 100.0 / e.grams;
      final updated = LogEntry(
        id: e.id,
        date: e.date,
        meal: e.meal,
        name: e.name,
        brand: e.brand,
        grams: g,
        kcal: e.kcal * per100 * g / 100,
        protein: e.protein * per100 * g / 100,
        carbs: e.carbs * per100 * g / 100,
        fat: e.fat * per100 * g / 100,
        fiber: e.fiber * per100 * g / 100,
        fasted: e.fasted,
      );
      setState(() => _saving = true);
      await Db.updateLog(updated);
    } else {
      // Quick-add style entries carry absolute totals.
      final kcal = _p(_kcal);
      final updated = LogEntry(
        id: e.id,
        date: e.date,
        meal: e.meal,
        name: e.name,
        brand: e.brand,
        grams: 0,
        kcal: kcal,
        protein: _p(_protein),
        carbs: _p(_carbs),
        fat: _p(_fat),
        fiber: e.fiber,
        fasted: e.fasted,
      );
      setState(() => _saving = true);
      await Db.updateLog(updated);
    }
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await Db.deleteLog(widget.entry.id!);
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Logged in ${_cap(e.meal)} · ${e.date}',
              style:
                  const TextStyle(color: MtTheme.textDim, fontSize: 12)),
          const SizedBox(height: 12),
          if (e.grams > 0) ...[
            TextField(
              controller: _grams,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Serving size (g)',
                suffixText: 'g',
                helperText:
                    'Macros scale with the serving — currently '
                    '${e.kcal.round()} kcal',
              ),
            ),
          ] else ...[
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _kcal,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Calories'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _protein,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Protein g'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _carbs,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Carbs g'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _fat,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Fat g'))),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: MtTheme.danger, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: MtTheme.danger),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ]),
        ],
      ),
    );
  }
}

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
