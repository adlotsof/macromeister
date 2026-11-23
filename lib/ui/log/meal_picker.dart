// Meal chip row: the per-item meal selector that sits next to every
// add/save button (search detail, quick add, AI, custom food, recipe).
// Replaces the old global top-right dropdown in the add-food sheet.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../services/meal_memory.dart';
import '../../theme.dart';

String capMeal(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class MealPicker extends StatefulWidget {
  final String initial;
  final ValueChanged<String>? onChanged;
  const MealPicker({super.key, required this.initial, this.onChanged});
  @override
  State<MealPicker> createState() => _MealPickerState();
}

class _MealPickerState extends State<MealPicker> {
  late String _meal;

  @override
  void initState() {
    super.initState();
    _meal = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in kMeals)
          ChoiceChip(
            label: Text(capMeal(m),
                style: TextStyle(
                    fontSize: 12,
                    color: _meal == m ? const Color(0xFF0B1512) : MtTheme.text,
                    fontWeight:
                        _meal == m ? FontWeight.w700 : FontWeight.w400)),
            selected: _meal == m,
            showCheckmark: false,
            selectedColor: MtTheme.accent,
            onSelected: (_) {
              setState(() => _meal = m);
              rememberMeal(m);
              widget.onChanged?.call(m);
            },
          ),
      ],
    );
  }
}
