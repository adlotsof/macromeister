// AI client for the AI logging features: describe-a-meal parsing, recipe
// import/parsing from free text, and custom food creation. Talks to any
// OpenAI-compatible chat-completions endpoint — OpenRouter (default, cheap
// models) or OpenAI directly. The API key is stored in app settings (entered
// by the user on the More > AI screen); nothing is sent anywhere except the
// configured provider endpoint.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db.dart';
import '../models.dart';

class AiConfig {
  final String key;
  final String provider; // 'openrouter' | 'openai'
  final String model;
  const AiConfig(this.key, this.provider, this.model);

  String get endpoint => provider == 'openai'
      ? 'https://api.openai.com/v1/chat/completions'
      : 'https://openrouter.ai/api/v1/chat/completions';
}

class AiFoodGuess {
  final String name;
  final double grams;
  final double kcal, protein, carbs, fat, fiber;
  final String confidence; // low | medium | high
  AiFoodGuess(this.name, this.grams, this.kcal, this.protein, this.carbs,
      this.fat, this.fiber, this.confidence);
}

class Ai {
  static const defaultModel = 'google/gemini-2.0-flash-lite';

  /// Loads the AI configuration from app settings.
  static Future<AiConfig> config() async {
    final key = await Db.getSetting('openai_key') ?? '';
    final provider = await Db.getSetting('ai_provider') ?? 'openrouter';
    final model = await Db.getSetting('ai_model') ?? defaultModel;
    return AiConfig(key, provider, model);
  }

  static Future<String?> _chat(AiConfig cfg, List<Map<String, String>> messages,
      {bool json = true}) async {
    try {
      final res = await http
          .post(Uri.parse(cfg.endpoint),
              headers: {
                'Authorization': 'Bearer ${cfg.key}',
                'Content-Type': 'application/json',
                if (cfg.provider == 'openrouter') ...{
                  'HTTP-Referer': 'https://macrotrack.local',
                  'X-Title': 'MacroMeister',
                },
              },
              body: jsonEncode({
                'model': cfg.model,
                'messages': messages,
                if (json) 'response_format': {'type': 'json_object'},
                'temperature': 0.2,
              }))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        // Some models reject response_format — retry once without it.
        if (json && res.statusCode == 400) {
          return await _chat(cfg, messages, json: false);
        }
        return null;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      return body['choices'][0]['message']['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// "Describe your meal" -> list of food estimates.
  static Future<List<AiFoodGuess>> parseMealDescription(
      AiConfig cfg, String description) async {
    final content = await _chat(cfg, [
      {
        'role': 'system',
        'content': 'You are a nutrition estimation engine. The user describes '
            'what they ate. Return JSON: {"items": [{"name": str, "grams": num, '
            '"kcal_per_100g": num, "protein_per_100g": num, "carbs_per_100g": num, '
            '"fat_per_100g": num, "fiber_per_100g": num, "confidence": "low|medium|high"}]}. '
            'Estimate portions in grams realistically. Be conservative with energy. '
            'Only include plausible edible items.'
      },
      {'role': 'user', 'content': description},
    ]);
    if (content == null) return const [];
    try {
      final items = (jsonDecode(content)['items'] as List? ?? []);
      return items.whereType<Map>().map((raw) {
        final m = raw.cast<String, dynamic>();
        double d(String k) => (m[k] is num) ? (m[k] as num).toDouble() : 0;
        return AiFoodGuess(
          (m['name'] ?? 'food') as String,
          d('grams') == 0 ? 100 : d('grams'),
          d('kcal_per_100g'),
          d('protein_per_100g'),
          d('carbs_per_100g'),
          d('fat_per_100g'),
          d('fiber_per_100g'),
          (m['confidence'] ?? 'medium') as String,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Estimate a meal from a photo: vision-capable model identifies items and
  /// portions. Same item schema as parseMealDescription.
  static Future<List<AiFoodGuess>> parseMealPhoto(
      AiConfig cfg, List<int> imageBytes) async {
    final b64 = base64Encode(imageBytes);
    final content = await _chatVision(cfg, [
      {
        'role': 'system',
        'content': 'You are a nutrition estimation engine. The user sends a '
            'photo of a meal. Identify every plausible edible item and estimate '
            'portions. Return JSON: {"items": [{"name": str, "grams": num, '
            '"kcal_per_100g": num, "protein_per_100g": num, "carbs_per_100g": num, '
            '"fat_per_100g": num, "fiber_per_100g": num, "confidence": "low|medium|high"}]}. '
            'Be conservative with energy. Only include plausible edible items.'
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'What foods are in this photo? Estimate macros per 100 g '
                'and portion sizes in grams for each item.'
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$b64'}
          }
        ],
      },
    ]);
    return _parseMealItems(content);
  }

  static List<AiFoodGuess> _parseMealItems(String? content) {
    if (content == null) return const [];
    try {
      final items = (jsonDecode(content)['items'] as List? ?? []);
      return items.whereType<Map>().map((raw) {
        final m = raw.cast<String, dynamic>();
        double d(String k) => (m[k] is num) ? (m[k] as num).toDouble() : 0;
        return AiFoodGuess(
          (m['name'] ?? 'food') as String,
          d('grams') == 0 ? 100 : d('grams'),
          d('kcal_per_100g'),
          d('protein_per_100g'),
          d('carbs_per_100g'),
          d('fat_per_100g'),
          d('fiber_per_100g'),
          (m['confidence'] ?? 'medium') as String,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Free-text recipe (or recipe URL text) -> structured recipe per serving.
  static Future<Recipe?> parseRecipe(AiConfig cfg, String text) async {
    final content = await _chat(cfg, [
      {
        'role': 'system',
        'content': 'Extract a recipe. Return JSON: {"name": str, "servings": num, '
            '"steps": str, "ingredients": [{"name": str, "grams": num, '
            '"kcal_per_100g": num, "protein_per_100g": num, "carbs_per_100g": num, '
            '"fat_per_100g": num}]}. Estimate nutrition per ingredient.'
      },
      {'role': 'user', 'content': text},
    ]);
    if (content == null) return null;
    try {
      final m = jsonDecode(content) as Map<String, dynamic>;
      final ings = (m['ingredients'] as List? ?? []).whereType<Map>().toList();
      double tk = 0, tp = 0, tc = 0, tf = 0;
      final ingMaps = <Map<String, Object?>>[];
      for (final i in ings) {
        double n(dynamic v) => (v is num) ? v.toDouble() : 0;
        final grams = n(i['grams']);
        final k = n(i['kcal_per_100g']) * grams / 100;
        final p = n(i['protein_per_100g']) * grams / 100;
        final c = n(i['carbs_per_100g']) * grams / 100;
        final f = n(i['fat_per_100g']) * grams / 100;
        tk += k;
        tp += p;
        tc += c;
        tf += f;
        ingMaps.add({
          'name': i['name'] ?? '',
          'grams': grams,
          'kcal': k,
          'protein': p,
          'carbs': c,
          'fat': f,
        });
      }
      final servings = ((m['servings'] as num?) ?? 1).toInt().clamp(1, 50);
      return Recipe(
        name: (m['name'] ?? 'Recipe') as String,
        servings: servings,
        ingredientsJson: jsonEncode(ingMaps),
        kcal: tk / servings,
        protein: tp / servings,
        carbs: tc / servings,
        fat: tf / servings,
        steps: (m['steps'] ?? '') as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// OCR a nutrition-label photo: pick a vision-capable model, send the image
  /// as a data URL, and extract name/brand/serving + per-100g macros.
  static Future<Food?> parseLabelImage(AiConfig cfg, List<int> imageBytes) async {
    final b64 = base64Encode(imageBytes);
    final content = await _chatVision(cfg, [
      {
        'role': 'system',
        'content': 'You read nutrition labels from photos. Return JSON: '
            '{"name": str (product name), "brand": str (may be empty), '
            '"serving_g": num (per-piece/per-serving size in grams if stated, else 100), '
            '"basis": "per_100g" | "per_serving", '
            '"kcal": num, "protein": num, "carbs": num, "fat": num, "fiber": num, '
            '"confidence": "low|medium|high"}. '
            'If the label states values per 100 g, use those. If it only states '
            'per serving, set basis to per_serving and give per-serving values; '
            'convert energy to kcal. Do not invent values you cannot read — use 0.'
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'Extract the nutrition values from this label photo.'
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$b64'}
          }
        ],
      },
    ]);
    if (content == null) return null;
    try {
      final m = (jsonDecode(content) as Map).cast<String, dynamic>();
      double n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
      final name = (m['name'] ?? '') as String;
      if (name.trim().isEmpty) return null;
      final basis = (m['basis'] ?? 'per_100g') as String;
      double per100(double v) => basis == 'per_serving' && n(m['serving_g']) > 0 ? v * 100 / n(m['serving_g']) : v;
      return Food(
        name: name.trim(),
        brand: ((m['brand'] ?? '') as String).trim(),
        servingG: n(m['serving_g']) <= 0 ? 100 : n(m['serving_g']),
        kcal: per100(n(m['kcal'])),
        protein: per100(n(m['protein'])),
        carbs: per100(n(m['carbs'])),
        fat: per100(n(m['fat'])),
        fiber: per100(n(m['fiber'])),
        source: 'ocr',
      );
    } catch (_) {
      return null;
    }
  }

  /// Vision-capable chat call (multimodal content parts). Falls back to
  /// retrying without response_format on 400.
  static Future<String?> _chatVision(AiConfig cfg, List<Map<String, dynamic>> messages) async {
    for (final useJson in [true, false]) {
      try {
        final res = await http
            .post(Uri.parse(cfg.endpoint),
                headers: {
                  'Authorization': 'Bearer ${cfg.key}',
                  'Content-Type': 'application/json',
                  if (cfg.provider == 'openrouter') ...{
                    'HTTP-Referer': 'https://macrotrack.local',
                    'X-Title': 'MacroMeister',
                  },
                },
                body: jsonEncode({
                  'model': cfg.model,
                  'messages': messages,
                  if (useJson) 'response_format': {'type': 'json_object'},
                  'temperature': 0.1,
                }))
            .timeout(const Duration(seconds: 90));
        if (res.statusCode == 200) {
          final body = jsonDecode(utf8.decode(res.bodyBytes));
          return body['choices'][0]['message']['content'] as String?;
        }
        if (res.statusCode == 400 && useJson) continue; // model may reject response_format
        return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Given a food name/description, generate a custom food entry with
  /// per-100g macros (used for quick custom food creation).
  static Future<Food?> createFoodFromDescription(AiConfig cfg, String text) async {
    final content = await _chat(cfg, [
      {
        'role': 'system',
        'content': 'Return JSON for a food: {"name": str, "serving_g": num, '
            '"kcal": per-100g, "protein": per-100g, "carbs": per-100g, '
            '"fat": per-100g, "fiber": per-100g}.'
      },
      {'role': 'user', 'content': text},
    ]);
    if (content == null) return null;
    try {
      final m = jsonDecode(content) as Map<String, dynamic>;
      double n(dynamic v) => (v is num) ? v.toDouble() : 0;
      final name = (m['name'] ?? '') as String;
      if (name.isEmpty) return null;
      return Food(
        name: name,
        servingG: n(m['serving_g']) == 0 ? 100 : n(m['serving_g']),
        kcal: n(m['kcal']),
        protein: n(m['protein']),
        carbs: n(m['carbs']),
        fat: n(m['fat']),
        fiber: n(m['fiber']),
        source: 'ai',
      );
    } catch (_) {
      return null;
    }
  }
}
