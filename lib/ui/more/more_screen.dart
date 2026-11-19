// More tab: hub for recipes, workouts, data export, integrations, AI, visibility.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../services/food_updates.dart';
import '../../theme.dart';
import 'ai_settings.dart';
import 'data_export.dart';
import 'data_sources_screen.dart';
import 'data_visibility.dart';
import 'habits_screen.dart';
import 'integrations.dart';
import 'recipes_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          const _SectionLabel('Track'),
          ListTile(
            leading: const Icon(Icons.restaurant_menu, color: MtTheme.accent),
            title: const Text('Recipes'),
            subtitle: const Text('Saved recipes and AI recipe import'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecipesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.track_changes, color: MtTheme.accent),
            title: const Text('Habits'),
            subtitle: const Text('Create habits and build streaks'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HabitsScreen())),
          ),
          const _SectionLabel('Data'),
          ListTile(
            leading: const Icon(Icons.ios_share, color: MtTheme.accent),
            title: const Text('Export data'),
            subtitle: const Text('CSV exports via share sheet'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataExportScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.visibility, color: MtTheme.accent),
            title: const Text('Data visibility'),
            subtitle: const Text('Show or hide dashboard cards'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataVisibilityScreen())),
          ),
          const _FoodDbTile(),
          ListTile(
            leading: const Icon(Icons.dangerous, color: MtTheme.danger),
            title: const Text('Clear food log', style: TextStyle(color: MtTheme.danger)),
            subtitle: const Text('Delete all logged entries'),
            onTap: () => _confirmClearLogs(context),
          ),
          const _SectionLabel('Settings'),
          ListTile(
            leading: const Icon(Icons.smart_toy, color: MtTheme.accent),
            title: const Text('AI settings'),
            subtitle: const Text('OpenAI key and connection test'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.watch, color: MtTheme.accentAlt),
            title: const Text('Integrations'),
            subtitle: const Text('Health Connect (steps, weight)'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const IntegrationsScreen())),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.menu_book, color: MtTheme.textDim),
            title: const Text('Data sources & licenses'),
            subtitle: const Text('Open Food Facts (ODbL), USDA FoodData Central (CC0)'),
            trailing: const Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataSourcesScreen())),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmClearLogs(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Clear food log?'),
        content: const Text(
            'All logged food entries will be permanently deleted. Weights, '
            'check-ins and other data are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: MtTheme.danger),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await Db.clearLogs('0000-01-01', '9999-12-31');
    AppState.instance.refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food log cleared')));
    }
  }
}

class _FoodDbTile extends StatefulWidget {
  const _FoodDbTile();
  @override
  State<_FoodDbTile> createState() => _FoodDbTileState();
}

class _FoodDbTileState extends State<_FoodDbTile> {
  bool _updating = false;
  String? _subtitle;

  @override
  void initState() {
    super.initState();
    _refreshSubtitle();
  }

  Future<void> _refreshSubtitle() async {
    final updated = await FoodUpdates.lastUpdated();
    if (!mounted) return;
    setState(() {
      _subtitle = updated == null
          ? 'Bundled database · updates: never checked'
          : 'Updated $updated (daily deltas)';
    });
  }

  Future<void> _update() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _subtitle = 'Checking for updates…';
    });
    try {
      final res = await FoodUpdates.update();
      if (!mounted) return;
      setState(() {
        _updating = false;
        _subtitle = res.appliedDeltas > 0
            ? 'Updated — ${res.appliedDeltas} delta(s), ${res.rowsUpserted} products'
            : 'Already up to date';
        if (res.error != null) _subtitle = 'Error: ${res.error}';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _updating = false;
          _subtitle = 'Update failed — check connection';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.cloud_download, color: MtTheme.accent),
        title: const Text('Update food database'),
        subtitle: Text(_subtitle ?? 'Checking…'),
        trailing: _updating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh, color: MtTheme.textDim),
        onTap: _updating ? null : _update,
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: MtTheme.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );
}
