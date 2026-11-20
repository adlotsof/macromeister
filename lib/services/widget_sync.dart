// Home-screen glance widget sync (MacroFactor parity gap #4). Pushes the
// selected day's remaining kcal, macro line and water total into
// home_widget storage; the Android MediumWidgetProvider renders it.
//
// Pure formatting lives in [widgetStrings] and is unit-tested; the plugin
// calls are fire-and-forget guarded so a widget failure never breaks logging.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../app_state.dart';
import '../db.dart';

class WidgetSync {
  static const _androidWidgetName = 'MediumWidgetProvider';

  /// Formats the three widget lines from today's numbers. Unit-tested.
  static Map<String, String> widgetStrings({
    required double remainingKcal,
    required double protein,
    required double carbs,
    required double fat,
    required int waterMl,
  }) {
    String n(double v) => v.round().toString();
    return {
      'remaining': remainingKcal >= 0
          ? '${n(remainingKcal)} kcal left'
          : '${n(-remainingKcal)} kcal over',
      'macros': 'P${n(protein)} · C${n(carbs)} · F${n(fat)}',
      'water': 'Water: $waterMl ml',
    };
  }

  /// Recomputes the selected day's numbers and pushes them to the widget.
  /// Fire-and-forget: all failures silent. Android-only for now — the iOS
  /// widget needs a WidgetKit extension target (separate Xcode target +
  /// App Group), tracked as a follow-up.
  static Future<void> push() async {
    if (!Platform.isAndroid) return;
    try {
      final date = AppState.instance.selectedDateStr;
      final totals = await AppState.instance.totalsFor(date);
      final targets = await AppState.instance.currentTargets();
      final water = await Db.waterMl(date);
      final s = widgetStrings(
        remainingKcal: targets.dailyTargetKcal - totals.kcal,
        protein: totals.protein,
        carbs: totals.carbs,
        fat: totals.fat,
        waterMl: water,
      );
      // home_widget stores one value per id — save each field separately.
      await HomeWidget.saveWidgetData('remaining', s['remaining']);
      await HomeWidget.saveWidgetData('macros', s['macros']);
      await HomeWidget.saveWidgetData('water', s['water']);
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (e, st) {
      // Widget unavailable (tests, non-Android) — ignore. Debug builds log.
      assert(() {
        debugPrint('WidgetSync.push failed: $e\n$st');
        return true;
      }());
    }
  }
}
