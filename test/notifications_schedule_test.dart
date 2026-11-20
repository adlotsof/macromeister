// Scheduling-math tests for the reminders feature (pure functions, no
// plugin): daily occurrences across midnight and weekly overdue semantics
// (a missed check-in day must not vanish until next week).
import 'package:flutter_test/flutter_test.dart';
import 'package:macrotrack/services/notifications.dart';

void main() {
  group('nextDaily', () {
    test('same day when the time is still ahead', () {
      final now = DateTime(2026, 11, 20, 14, 0);
      final next = Notifications.nextDaily(now, 20, 0);
      expect(next, DateTime(2026, 11, 20, 20, 0));
    });

    test('tomorrow when the time has passed', () {
      final now = DateTime(2026, 11, 20, 21, 0);
      final next = Notifications.nextDaily(now, 20, 0);
      expect(next, DateTime(2026, 11, 21, 20, 0));
    });

    test('exactly now is in the past -> tomorrow', () {
      final now = DateTime(2026, 11, 20, 20, 0);
      final next = Notifications.nextDaily(now, 20, 0);
      expect(next, DateTime(2026, 11, 21, 20, 0),
          reason: 'a reminder scheduled for this instant must fire tomorrow, '
              'not be dropped');
    });

    test('across month boundary', () {
      final now = DateTime(2026, 11, 30, 22, 0);
      expect(Notifications.nextDaily(now, 9, 30),
          DateTime(2026, 12, 1, 9, 30));
    });
  });

  group('nextWeekly', () {
    // 2026-11-20 is a Friday (weekday 5).

    test('later the same due day', () {
      final now = DateTime(2026, 11, 20, 8, 0); // Friday morning
      final next = Notifications.nextWeekly(now, 5, 9, 0);
      expect(next, DateTime(2026, 11, 20, 9, 0)); // today 09:00
    });

    test('due day already past -> next week same weekday', () {
      final now = DateTime(2026, 11, 20, 10, 0); // Friday 10:00
      final next = Notifications.nextWeekly(now, 5, 9, 0);
      expect(next, DateTime(2026, 11, 27, 9, 0));
    });

    test('not the due day yet this week -> upcoming due day', () {
      final now = DateTime(2026, 11, 18, 12, 0); // Wednesday
      final next = Notifications.nextWeekly(now, 5, 9, 0);
      expect(next, DateTime(2026, 11, 20, 9, 0)); // Friday
    });

    test('missed due day earlier this week -> next due weekday', () {
      final now = DateTime(2026, 11, 20, 7, 0); // Friday 07:00
      final next = Notifications.nextWeekly(now, 1, 9, 0); // Monday
      // Weekly repeat fires on the due weekday; a missed Monday is covered
      // by the in-app overdue check-in prompt, so the notification targets
      // the next Monday.
      expect(next, DateTime(2026, 11, 23, 9, 0));
    });

    test('weekday wraps over the week boundary', () {
      final now = DateTime(2026, 11, 22, 12, 0); // Sunday
      final next = Notifications.nextWeekly(now, 1, 9, 0); // Monday
      expect(next, DateTime(2026, 11, 23, 9, 0)); // tomorrow
    });
  });
}
