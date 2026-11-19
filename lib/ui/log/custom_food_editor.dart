// Custom food editor: create a food manually, from a description with AI,
// or from a nutrition-label photo (OCR), then optionally log it right away.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../services/camera_permission.dart';
import '../../services/openai.dart';
import '../../theme.dart';

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class CustomFoodEditor extends StatefulWidget {
  final String date;
  final String meal;
  final Food? existing; // edit mode
  const CustomFoodEditor(
      {super.key, required this.date, required this.meal, this.existing});
  @override
  State<CustomFoodEditor> createState() => _CustomFoodEditorState();
}

class _CustomFoodEditorState extends State<CustomFoodEditor> {
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _serving;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _fiber;
  final _aiDesc = TextEditingController();
  bool _aiLoading = false;
  bool _deleting = false;
  String? _error; // inline error — snackbars hide behind the modal barrier

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    _name = TextEditingController(text: f?.name ?? '');
    _brand = TextEditingController(text: f?.brand ?? '');
    _serving = TextEditingController(text: _numStr(f?.servingG ?? 100));
    _kcal = TextEditingController(text: _numStr(f?.kcal ?? 0));
    _protein = TextEditingController(text: _numStr(f?.protein ?? 0));
    _carbs = TextEditingController(text: _numStr(f?.carbs ?? 0));
    _fat = TextEditingController(text: _numStr(f?.fat ?? 0));
    _fiber = TextEditingController(text: _numStr(f?.fiber ?? 0));
  }

  @override
  void dispose() {
    for (final c in [
      _name, _brand, _serving, _kcal, _protein, _carbs, _fat, _fiber, _aiDesc
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _val(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;

  String _numStr(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  // ---- label OCR -----------------------------------------------------------

  bool _ocrLoading = false;

  Future<void> _scanLabel(ImageSource src) async {
    if (src == ImageSource.camera) {
      final ok = await ensureCameraPermission();
      if (!ok) {
        if (mounted) {
          setState(() => _error =
                  'Camera permission denied. Enable it in system settings.');
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() => _ocrLoading = true);
    try {
      final x = await ImagePicker().pickImage(
          source: src, imageQuality: 88, maxWidth: 2400, maxHeight: 2400);
      if (!mounted) return;
      if (x == null) {
        setState(() => _ocrLoading = false);
        return;
      }
      final bytes = await File(x.path).readAsBytes();
      if (!mounted) return;
      final cfg = await Ai.config();
      final food = await Ai.parseLabelImage(cfg, bytes);
      if (!mounted) return;
      setState(() => _ocrLoading = false);
      if (food == null) {
        setState(() => _error = 'Could not read the label. Try better lighting '
                'or a sharper photo.');
        return;
      }
      setState(() {
        if (_name.text.trim().isEmpty) _name.text = food.name;
        if (_brand.text.trim().isEmpty && food.brand.isNotEmpty) {
          _brand.text = food.brand;
        }
        _serving.text = _numStr(food.servingG);
        _kcal.text = _numStr(food.kcal);
        _protein.text = _numStr(food.protein);
        _carbs.text = _numStr(food.carbs);
        _fat.text = _numStr(food.fat);
        _fiber.text = _numStr(food.fiber);
      });
      setState(() => _error = null); // success — clear any banner
    } catch (_) {
      if (mounted) {
        setState(() => _ocrLoading = false);
        setState(() => _error = 'Something went wrong reading the label.');
      }
    }
  }

  Future<void> _pickLabelSource() => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo of the label'),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanLabel(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pick from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanLabel(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      );

  Future<void> _aiFill() async {
    final cfg = await Ai.config();
    if (!mounted) return;
    if (cfg.key.isEmpty) {
      setState(() => _error = 'Set your OpenAI key in More → AI first.');
      return;
    }
    final text = _aiDesc.text.trim();
    if (text.isEmpty) return;
    setState(() => _aiLoading = true);
    final food = await Ai.createFoodFromDescription(cfg, text);
    if (!mounted) return;
    setState(() => _aiLoading = false);
    if (food == null) {
      setState(() => _error = 'AI could not generate a food. Try rephrasing.');
      return;
    }
    setState(() {
      _name.text = food.name;
      _serving.text = _numStr(food.servingG);
      _kcal.text = _numStr(food.kcal);
      _protein.text = _numStr(food.protein);
      _carbs.text = _numStr(food.carbs);
      _fat.text = _numStr(food.fat);
      _fiber.text = _numStr(food.fiber);
    });
  }

  Future<void> _save({required bool alsoLog}) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name.');
      return;
    }
    final serving = _val(_serving) <= 0 ? 100.0 : _val(_serving);
    final food = Food(
      id: widget.existing?.id,
      name: name,
      brand: _brand.text.trim(),
      servingG: serving,
      kcal: _val(_kcal),
      protein: _val(_protein),
      carbs: _val(_carbs),
      fat: _val(_fat),
      fiber: _val(_fiber),
      source: 'custom',
      offId: widget.existing?.offId,
      createdAt: widget.existing?.createdAt,
    );
    final id = await Db.upsertFood(food);
    if (alsoLog) {
      final g = serving;
      await Db.insertLog(LogEntry(
        date: widget.date,
        meal: widget.meal,
        foodId: id,
        name: food.name,
        brand: food.brand,
        grams: g,
        kcal: food.kcal * g / 100,
        protein: food.protein * g / 100,
        carbs: food.carbs * g / 100,
        fat: food.fat * g / 100,
        fiber: food.fiber * g / 100,
      ));
    }
    AppState.instance.refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: MtTheme.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(_error!,
                style: const TextStyle(color: MtTheme.danger, fontSize: 13)),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _aiDesc,
          decoration: const InputDecoration(
            labelText: 'Describe a food for AI fill (optional)',
            hintText: 'e.g. "Skyr vanilla 500g tub"',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _aiLoading ? null : _aiFill,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: MtTheme.accentAlt),
            foregroundColor: MtTheme.accentAlt,
          ),
          icon: _aiLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Fill fields with AI'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _ocrLoading ? null : _pickLabelSource,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: MtTheme.textDim.withOpacity(0.4)),
            foregroundColor: MtTheme.text,
          ),
          icon: _ocrLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.document_scanner, size: 16),
          label: Text(_ocrLoading ? 'Reading label…' : 'Scan nutrition label'),
        ),
        const SizedBox(height: 4),
        Text('Photo of the nutrition label — fills name and macros per 100 g.',
            style: TextStyle(color: MtTheme.textDim, fontSize: 11)),
        const Divider(height: 32, color: MtTheme.surfaceHi),
        TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 10),
        TextField(
            controller: _brand,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Brand (optional)')),
        const SizedBox(height: 10),
        TextField(
            controller: _serving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Serving size', suffixText: 'g')),
        const SizedBox(height: 10),
        Text('Macros per 100 g',
            style: TextStyle(color: MtTheme.textDim, fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _kcal,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'kcal', suffixText: 'kcal'))),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: _protein,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Protein', suffixText: 'g'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _carbs,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Carbs', suffixText: 'g'))),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: _fat,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Fat', suffixText: 'g'))),
        ]),
        const SizedBox(height: 10),
        TextField(
            controller: _fiber,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Fiber (optional)', suffixText: 'g')),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _save(alsoLog: true),
          icon: const Icon(Icons.add_circle, size: 18),
          label: Text('Save & add to ${_cap(widget.meal)}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _save(alsoLog: false),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: MtTheme.textDim.withOpacity(0.4)),
            foregroundColor: MtTheme.text,
          ),
          child: const Text('Save to my foods'),
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _deleting
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                              title: Text('Delete ${widget.existing!.name}?'),
                              content: const Text(
                                  'Existing log entries keep their values, '
                                  'but the food disappears from My foods.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete')),
                              ],
                            ));
                    if (ok != true || !mounted) return;
                    setState(() => _deleting = true);
                    await Db.deleteFood(widget.existing!.id!);
                    AppState.instance.refresh();
                    if (mounted) Navigator.of(context).pop();
                  },
            style: TextButton.styleFrom(foregroundColor: MtTheme.danger),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete food'),
          ),
        ],
      ],
    );
  }
}
