// Widget line formatting tests (lib/services/widget_sync.dart): the home-
// screen widget displays these strings verbatim, so negative remaining
// (over target), rounding and zero handling must be exact.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/services/widget_sync.dart';

void main() {
  test('normal day: remaining positive, macros rounded', () {
    final s = WidgetSync.widgetStrings(
        remainingKcal: 2061.4,
        protein: 133.6,
        carbs: 244.9,
        fat: 66.4,
        waterMl: 750);
    expect(s['remaining'], '2061 kcal left');
    expect(s['macros'], 'P134 · C245 · F66');
    expect(s['water'], 'Water: 750 ml');
  });

  test('over target: kcal over is shown positive with "over"', () {
    final s = WidgetSync.widgetStrings(
        remainingKcal: -42.6,
        protein: 100,
        carbs: 100,
        fat: 100,
        waterMl: 0);
    expect(s['remaining'], '43 kcal over',
        reason: 'no "-42 kcal left" — the user is over the target');
    expect(s['water'], 'Water: 0 ml');
  });

  test('zero macros render as 0, not dashes', () {
    final s = WidgetSync.widgetStrings(
        remainingKcal: 2000,
        protein: 0,
        carbs: 0,
        fat: 0,
        waterMl: 0);
    expect(s['macros'], 'P0 · C0 · F0');
  });
}
