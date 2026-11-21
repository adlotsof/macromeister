// Open Food Facts search (v2 API). Public, keyless — mirrors the original
// app's use of open food databases for packaged products + generic foods.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class OffSearchResult {
  final List<Food> foods;
  final int count;
  OffSearchResult(this.foods, this.count);
}

Future<OffSearchResult> searchOff(String query, {int limit = 25}) async {
  final uri = Uri.parse(
      'https://world.openfoodfacts.org/cgi/search.pl?search_terms=${Uri.encodeComponent(query)}'
      '&search_simple=1&action=process&json=1&page_size=$limit');
  try {
    final res = await http
        .get(uri, headers: {'User-Agent': 'MacroMeister - Android - Version 1.0'})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return OffSearchResult(const [], 0);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final products = (data['products'] as List? ?? []);
    final foods = <Food>[];
    for (final p in products) {
      final f = _foodFromProduct(p as Map<String, dynamic>);
      if (f != null) foods.add(f);
    }
    return OffSearchResult(foods, (data['count'] as num?)?.toInt() ?? 0);
  } catch (_) {
    return OffSearchResult(const [], 0);
  }
}

/// Barcode lookup by GTIN.
Future<Food?> lookupOffBarcode(String barcode) async {
  try {
    final res = await http
        .get(
            Uri.parse(
                'https://world.openfoodfacts.org/api/v2/product/$barcode.json'),
            headers: {'User-Agent': 'MacroMeister - Android - Version 1.0'})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (data['status'] != 1) return null;
    return _foodFromProduct(data['product'] as Map<String, dynamic>,
        offId: barcode);
  } catch (_) {
    return null;
  }
}

Food? _foodFromProduct(Map<String, dynamic> p, {String? offId}) {
  final nutriments = p['nutriments'] as Map<String, dynamic>? ?? {};
  double? numOf(dynamic v) =>
      v == null ? null : double.tryParse(v.toString().replaceAll(',', '.'));
  final kcal100 = numOf(nutriments['energy-kcal_100g']) ??
      (numOf(nutriments['energy_100g']) != null
          ? numOf(nutriments['energy_100g'])! / 4.184
          : null);
  if (kcal100 == null) return null;
  final name = (p['product_name'] ??
          p['product_name_en'] ??
          p['generic_name'] ??
          '') as String;
  if (name.trim().isEmpty) return null;
  final brands = (p['brands'] ?? '') as String;
  return Food(
    name: name.trim(),
    brand: brands.split(',').first.trim(),
    servingG: numOf(p['serving_quantity']) ?? 100,
    kcal: kcal100,
    protein: numOf(nutriments['proteins_100g']) ?? 0,
    carbs: numOf(nutriments['carbohydrates_100g']) ?? 0,
    fat: numOf(nutriments['fat_100g']) ?? 0,
    fiber: numOf(nutriments['fiber_100g']) ?? 0,
    source: 'off',
    offId: offId ?? (p['code'] as String?),
  );
}
