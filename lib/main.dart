import 'dart:async';

// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'db.dart';
import 'services/backup.dart';
import 'services/food_updates.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/program/onboarding_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MacroTrackApp());
}

class MacroTrackApp extends StatelessWidget {
  const MacroTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: 'MacroTrack',
        debugShowCheckedModeBanner: false,
        theme: MtTheme.theme(),
        home: const _AppRoot(),
      ),
    );
  }
}

/// Reads the persisted theme mode ('system' | 'light' | 'dark') and applies
/// it to the palette. Returns true when the palette CHANGED — the caller
/// then repaints (AppState.refresh()); false means stable, no repaint.
Future<bool> applyThemeMode() async {
  try {
    final mode = await Db.getSetting('theme_mode') ?? 'dark';
  final Brightness b;
  switch (mode) {
    case 'light':
      b = Brightness.light;
      break;
    case 'system':
      b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      break;
    default:
      b = Brightness.dark;
  }
    return MtTheme.apply(b);
  } catch (_) {
    return false; // no DB yet (tests) — keep the current palette
  }
}

/// First-run gate: shows the onboarding wizard until it has been completed,
/// then hands off to the main navigation shell. Listens to AppState so the
/// hand-off happens immediately when onboarding finishes (a plain
/// FutureBuilder would keep showing the wizard until app restart).
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  Future<bool> _onboardingDone() async {
    final v = await Db.getSetting('onboarding_done');
    return v == '1';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        // Re-apply the persisted theme mode on every root rebuild; a mode
        // change (More → Theme) flips the palette and triggers exactly one
        // repaint via the change signal below.
        applyThemeMode().then((changed) {
          if (changed) AppState.instance.refresh();
        });
        return FutureBuilder<bool>(
          future: _onboardingDone(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return snap.data == true
                ? const _HomeWithUpdates()
                : const OnboardingScreen();
          },
        );
      },
    );
  }
}

/// HomeShell plus a weekly background check for Open Food Facts deltas
/// (fire-and-forget; the More → 'Update food database' tile shows status).
class _HomeWithUpdates extends StatefulWidget {
  const _HomeWithUpdates();
  @override
  State<_HomeWithUpdates> createState() => _HomeWithUpdatesState();
}

class _HomeWithUpdatesState extends State<_HomeWithUpdates> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _maybeUpdate();
    // Daily auto-backup (settings-gated, rotated, silent).
    Backup.runAutoBackup();
    // Re-check on each app resume, at most every 7 days.
    _timer = Timer.periodic(
        const Duration(hours: 168), (_) => _maybeUpdate());
    AppLifecycleListener(onResume: _maybeUpdate);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _maybeUpdate() async {
    try {
      final last = await Db.getSetting('foods_delta_ts');
      final updated = await Db.getSetting('foods_updated_at');
      // Auto-check only once the bundled DB has been initialized at all
      // (first launch copies 668 MB — don't pile a download on top) and at
      // most weekly.
      if (last == null) return;
      if (updated != null) {
        final t = DateTime.tryParse(updated);
        if (t != null && DateTime.now().difference(t).inDays < 7) return;
      }
      await FoodUpdates.update();
    } catch (_) {
      // silent — the More tile shows manual status
    }
  }

  @override
  Widget build(BuildContext context) => const HomeShell();
}
