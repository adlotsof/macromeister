// More tab: hub for recipes, workouts, data export, integrations, AI, visibility.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../main.dart' show applyThemeMode;
import '../../services/food_updates.dart';
import '../../theme.dart';
import 'ai_settings.dart';
import 'data_export.dart';
import 'data_sources_screen.dart';
import 'data_visibility.dart';
import 'habits_screen.dart';
import 'integrations.dart';
import '../progress/progress_screen.dart';
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
            leading: Icon(Icons.restaurant_menu, color: MtTheme.accent),
            title: const Text('Recipes'),
            subtitle: const Text('Saved recipes and AI recipe import'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecipesScreen())),
          ),
          ListTile(
            leading: Icon(Icons.track_changes, color: MtTheme.accent),
            title: const Text('Habits'),
            subtitle: const Text('Create habits and build streaks'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HabitsScreen())),
          ),
          const _SectionLabel('Data'),
          _AutoBackupTile(),
          ListTile(
            leading: Icon(Icons.insights, color: MtTheme.accent),
            title: Text('Progress'),
            subtitle: Text('Weight trend, intake history, photos'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProgressScreen())),
          ),
          ListTile(
            leading: Icon(Icons.ios_share, color: MtTheme.accent),
            title: const Text('Export data'),
            subtitle: const Text('CSV exports via share sheet'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataExportScreen())),
          ),
          ListTile(
            leading: Icon(Icons.visibility, color: MtTheme.accent),
            title: const Text('Data visibility'),
            subtitle: const Text('Show or hide dashboard cards'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataVisibilityScreen())),
          ),
          const _FoodDbTile(),
          ListTile(
            leading: Icon(Icons.dangerous, color: MtTheme.danger),
            title: Text('Clear food log', style: TextStyle(color: MtTheme.danger)),
            subtitle: const Text('Delete all logged entries'),
            onTap: () => _confirmClearLogs(context),
          ),
          const _SectionLabel('Settings'),
          const _ThemeTile(),
          ListTile(
            leading: Icon(Icons.smart_toy, color: MtTheme.accent),
            title: const Text('AI settings'),
            subtitle: const Text('OpenAI key and connection test'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
          ),
          ListTile(
            leading: Icon(Icons.watch, color: MtTheme.accentAlt),
            title: const Text('Integrations'),
            subtitle: const Text('Health Connect (steps, weight)'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const IntegrationsScreen())),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.menu_book, color: MtTheme.textDim),
            title: const Text('Data sources & licenses'),
            subtitle: const Text('Open Food Facts (ODbL), USDA FoodData Central (CC0)'),
            trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
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

/// Settings toggle for the daily auto-backup (default ON, keeps 7 files).
class _AutoBackupTile extends StatefulWidget {
  const _AutoBackupTile();
  @override
  State<_AutoBackupTile> createState() => _AutoBackupTileState();
}

class _AutoBackupTileState extends State<_AutoBackupTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await Db.getSetting('auto_backup');
    if (!mounted) return;
    setState(() => _enabled = v != '0'); // default on
  }

  Future<void> _set(bool value) async {
    await Db.setSetting('auto_backup', value ? '1' : '0');
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary:
          Icon(Icons.backup_outlined, color: MtTheme.accent),
      title: const Text('Daily auto-backup'),
      subtitle: const Text('Keeps the last 7 backups on this device'),
      value: _enabled ?? true,
      onChanged: (v) => _set(v),
    );
  }
}

/// Theme mode selector: system / light / dark, persisted in settings.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile();

  Future<void> _pick(BuildContext context) async {
    final current = await Db.getSetting('theme_mode') ?? 'dark';
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label, icon) in const [
              ('system', 'Follow system', Icons.brightness_auto),
              ('light', 'Light', Icons.light_mode),
              ('dark', 'Dark', Icons.dark_mode),
            ])
              ListTile(
                leading: Icon(icon,
                    color: current == value
                        ? MtTheme.accent
                        : MtTheme.textDim),
                title: Text(label),
                trailing: current == value
                    ? Icon(Icons.check, color: MtTheme.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, value),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await Db.setSetting('theme_mode', picked);
    // Repaint the whole app with the new palette.
    if (await applyThemeMode()) AppState.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.palette_outlined, color: MtTheme.accent),
      title: Text('Theme'),
      subtitle: Text('Light, dark, or follow system'),
      trailing: Icon(Icons.chevron_right, color: MtTheme.textDim),
      onTap: () => _pick(context),
    );
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
        leading: Icon(Icons.cloud_download, color: MtTheme.accent),
        title: const Text('Update food database'),
        subtitle: Text(_subtitle ?? 'Checking…'),
        trailing: _updating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.refresh, color: MtTheme.textDim),
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
            style: TextStyle(
                color: MtTheme.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );
}
