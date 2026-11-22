import 'package:macrotrack/app_state.dart';

/// Whether the weekly check-in prompt is due TODAY for a coached program.
///
/// The prompt shows only on the user's chosen check-in weekday (1 = Monday,
/// 7 = Sunday) — MacroFactor semantics. An earlier implementation compared
/// `now.weekday >= checkinWeekday`, which made the prompt appear every day
/// from the chosen weekday onward (e.g. all week for a Monday check-in).
///
/// A check-in already completed this calendar week (compare via week-start
/// date) suppresses the prompt even on the weekday itself.
bool isCheckInDue(DateTime now, int checkinWeekday,
    {DateTime? lastCheckIn, String? lastCheckInWeekStart}) {
  final wd = checkinWeekday.clamp(1, 7);
  if (now.weekday != wd) return false;
  if (lastCheckInWeekStart != null) {
    return fmtDate(weekStart(now)) != lastCheckInWeekStart;
  }
  if (lastCheckIn != null) {
    return fmtDate(weekStart(now)) != fmtDate(weekStart(lastCheckIn));
  }
  return true;
}
