// Reminders (MacroFactor parity, gap #9 remainder): a daily food-logging
// reminder at a user-chosen time and a weekly check-in reminder on the
// program's check-in weekday. Uses flutter_local_notifications with
// exact-match zonedSchedule calls; ids are stable so re-scheduling replaces.
//
// The pure scheduling math (next occurrence across midnight, overdue weekly
// semantics) lives in [nextDaily] / [nextWeekly] and is unit-tested; the
// plugin calls are thin wrappers.
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _dailyId = 1;
  static const _weeklyId = 2;
  static const _channelId = 'reminders';

  static Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones(); // required before tz.getLocation
      await _plugin.initialize(InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false, // permission asked on first toggle
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      if (Platform.isIOS) {
        // iOS 12+ provisional/notification authorization.
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else {
        // Android 13+ needs the runtime permission.
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _initialized = true;
    } catch (_) {
      // Plugin unavailable (tests) — reminders silently off.
    }
  }

  // ---- pure scheduling math (unit-tested) ----

  /// The next occurrence of a daily reminder at [hour]:[minute], strictly
  /// after [now] (same day if still in the future, otherwise tomorrow).
  static DateTime nextDaily(DateTime now, int hour, int minute) {
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  /// The next occurrence of a weekly reminder on [weekday] (1 = Monday) at
  /// [hour]:[minute], strictly after [now]. The plugin repeats it weekly on
  /// that weekday (dayOfWeekAndTime); a missed day is covered by the in-app
  /// overdue check-in prompt, not by shifting the notification weekday.
  static DateTime nextWeekly(DateTime now, int weekday, int hour, int minute) {
    final todayCand = DateTime(now.year, now.month, now.day, hour, minute);
    final daysAhead = (weekday - now.weekday) % 7;
    var cand = todayCand.add(Duration(days: daysAhead));
    if (!cand.isAfter(now)) {
      cand = cand.add(const Duration(days: 7));
    }
    return cand;
  }

  // ---- plugin wrappers ----

  static tz.TZDateTime _tz(DateTime d) {
    // The plugin wants a TZDateTime instant. We only know the device's UTC
    // offset (no tz-name lookup without an extra plugin), so convert the
    // local wall time to the UTC instant. Standard caveat: a fixed-offset
    // conversion can drift up to 1 h across a DST change.
    final utc = d.subtract(DateTime.now().timeZoneOffset);
    return tz.TZDateTime.from(utc, tz.getLocation('UTC'));
  }

  static Future<bool> _requestPermission() async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// (Re)schedules the daily log reminder. [enabled] false cancels it.
  /// Returns true when the requested state was actually applied (permission
  /// granted and schedule written), so callers can reflect the real state.
  static Future<bool> setDailyReminder(
      {required bool enabled, int hour = 20, int minute = 0}) async {
    await init();
    if (!enabled) {
      try {
        await _plugin.cancel(_dailyId);
      } catch (e, st) {
        _debugLog('cancel daily reminder failed', e, st);
      }
      await Db.setSetting('reminder_daily', '0');
      return true;
    }
    if (!await _requestPermission()) return false;
    try {
      final at = nextDaily(DateTime.now(), hour, minute);
      await _plugin.zonedSchedule(
        _dailyId,
        'Time to log your meals',
        'Keep your MacroMeister streak going — log today\'s food.',
        _tz(at),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Reminders',
            channelDescription: 'Logging and check-in reminders',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // repeats daily
      );
      await Db.setSetting('reminder_daily', '1');
      await Db.setSetting('reminder_daily_time', '$hour:$minute');
      return true;
    } catch (e, st) {
      _debugLog('schedule daily reminder failed', e, st);
      return false;
    }
  }

  /// (Re)schedules the weekly check-in reminder for the program's weekday.
  /// Returns true when the requested state was actually applied.
  static Future<bool> setWeeklyReminder(
      {required bool enabled, int weekday = 1, int hour = 9}) async {
    await init();
    if (!enabled) {
      try {
        await _plugin.cancel(_weeklyId);
      } catch (e, st) {
        _debugLog('cancel weekly reminder failed', e, st);
      }
      await Db.setSetting('reminder_weekly', '0');
      return true;
    }
    if (!await _requestPermission()) return false;
    try {
      final at = nextWeekly(DateTime.now(), weekday, hour, 0);
      await _plugin.zonedSchedule(
        _weeklyId,
        'Weekly check-in',
        'Confirm your weight to update your program targets.',
        _tz(at),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Reminders',
            channelDescription: 'Logging and check-in reminders',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      await Db.setSetting('reminder_weekly', '1');
      return true;
    } catch (e, st) {
      _debugLog('schedule weekly reminder failed', e, st);
      return false;
    }
  }

  /// Re-applies both reminders from their persisted settings. Called on app
  /// resume so DST changes (the schedule is a fixed UTC wall time) and lost
  /// alarms self-heal without a timezone-name plugin.
  static Future<void> refreshFromSettings() async {
    try {
      final daily = await Db.getSetting('reminder_daily') == '1';
      final timeStr = await Db.getSetting('reminder_daily_time');
      final parts = (timeStr ?? '20:0').split(':');
      await setDailyReminder(
        enabled: daily,
        hour: int.tryParse(parts[0]) ?? 20,
        minute: int.tryParse(parts[1]) ?? 0,
      );
      final weekly = await Db.getSetting('reminder_weekly') == '1';
      if (weekly) {
        final profile = await Db.loadProfile();
        await setWeeklyReminder(
            enabled: true, weekday: profile?.checkinWeekday ?? 1);
      }
    } catch (e, st) {
      _debugLog('refresh reminders failed', e, st);
    }
  }

  static void _debugLog(String what, Object e, StackTrace st) {
    assert(() {
      // ignore: avoid_print
      print('Notifications: $what: $e\n$st');
      return true;
    }());
  }
}
