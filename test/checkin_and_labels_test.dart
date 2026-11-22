// Regression tests for the weekly check-in prompt scheduling and the
// fasting-card goal label.
//
// check-in regression: the prompt used `now.weekday >= checkinWeekday`,
// which made it appear EVERY day from the chosen weekday onward (all week
// for a Monday check-in — visible on a Sunday in the tester walkthrough).
// MacroFactor semantics: prompt only on the chosen weekday.
//
// fasting-goal regression: the card header rendered the literal string
// 'goal h' because the hours value was never interpolated.
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/app_state.dart';
import 'package:macrotrack/services/checkin.dart';
import 'package:macrotrack/ui/dashboard/dashboard_screen.dart';

void main() {
  group('isCheckInDue', () {
    // 2026-11-22 is a Sunday; 2026-11-23 the Monday after.
    final sun = DateTime(2026, 11, 22);
    final mon = DateTime(2026, 11, 23);
    final tue = DateTime(2026, 11, 24);

    test('due only on the chosen weekday', () {
      // check-in day Monday: due Monday, NOT Sunday/Tuesday.
      expect(isCheckInDue(mon, 1), isTrue);
      expect(isCheckInDue(sun, 1), isFalse, reason: 'BUG: card showed all week');
      expect(isCheckInDue(tue, 1), isFalse);
      // check-in day Sunday: due Sunday only.
      expect(isCheckInDue(sun, 7), isTrue);
      expect(isCheckInDue(mon, 7), isFalse);
      // check-in day Wednesday.
      expect(isCheckInDue(DateTime(2026, 11, 25), 3), isTrue);
      expect(isCheckInDue(tue, 3), isFalse);
    });

    test('out-of-range weekday is clamped into 1..7', () {
      expect(isCheckInDue(mon, 0), isTrue); // clamps to Monday
      expect(isCheckInDue(sun, 9), isTrue); // clamps to Sunday
      expect(isCheckInDue(tue, 99), isFalse);
    });

    test('a check-in already done this week suppresses the prompt', () {
      // checked in earlier the same day
      expect(
          isCheckInDue(DateTime(2026, 11, 23, 20), 1,
              lastCheckIn: DateTime(2026, 11, 23, 8)),
          isFalse);
      // a check-in from LAST week does not suppress this week's prompt
      expect(
          isCheckInDue(mon, 1,
              lastCheckIn: mon.subtract(const Duration(days: 8))), isTrue);
    });

    test('weekStart is Monday-based and normalizes to midnight', () {
      final ws = weekStart(DateTime(2026, 11, 22, 15, 30)); // Sunday
      expect(ws.weekday, DateTime.monday);
      expect(fmtDate(ws), '2026-11-16');
      expect(fmtDate(weekStart(mon)), '2026-11-23');
    });
  });

  group('fastingGoalLabel', () {
    test('interpolates the hours value (was literal "goal h")', () {
      expect(fastingGoalLabel(16), 'goal 16 h');
      expect(fastingGoalLabel(12), 'goal 12 h');
    });
  });
}
