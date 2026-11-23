import 'package:macrotrack/app_state.dart';
import 'package:macrotrack/db.dart';

/// Remembers the meal the user last selected in the add-food / food-detail
/// sheets so the meal selector starts from that state next time.
///
/// Precedence when opening a sheet: an explicitly requested meal (e.g. a
/// meal section header in the Log tab) wins; otherwise the remembered
/// value; otherwise 'snack'.
const lastMealKey = 'last_meal';

/// Guards against a stale/invalid stored value.
String? validMeal(String? stored) =>
    stored == null || kMeals.contains(stored) ? stored : null;

/// The meal a newly opened sheet should start with.
Future<String> initialMeal({String? explicit}) async {
  final remembered = explicit ?? validMeal(await Db.getSetting(lastMealKey));
  return remembered ?? 'snack';
}

/// Persists the user's selection for the next sheet.
Future<void> rememberMeal(String meal) => Db.setSetting(lastMealKey, meal);
