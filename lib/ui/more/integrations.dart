// Integrations: Health Connect connect/sync status.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../db.dart';
import '../../services/health_sync.dart';
import '../../theme.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});
  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  bool _connected = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // Persisted connect state — the volatile field was always false on open.
    Db.getSetting('hc_connected').then((v) {
      if (mounted) setState(() => _connected = v == '1');
    });
  }

  Future<void> _connect() async {
    setState(() => _working = true);
    if (!await HealthSync.isAvailable()) {
      if (!mounted) return;
      setState(() => _working = false);
      await Db.setSetting('hc_connected', '0');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MtTheme.danger,
          content: Text(
              'Health Connect is not installed on this device — install it '
              'from the Play Store, then try again.')));
      return;
    }
    final ok = await HealthSync.requestPermissions();
    if (!mounted) return;
    setState(() {
      _working = false;
      _connected = ok;
    });
    await Db.setSetting('hc_connected', ok ? '1' : '0');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(ok
            ? 'Health Connect connected'
            : 'Could not connect to Health Connect'),
        backgroundColor: ok ? null : MtTheme.danger));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.monitor_heart_outlined,
                          color: MtTheme.accent),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Health Connect',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      if (_connected)
                        const Chip(
                          label: Text('Connected'),
                          backgroundColor: MtTheme.surfaceHi,
                          labelStyle: TextStyle(
                              color: MtTheme.accent, fontSize: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Reads steps and body weight, and writes weigh-ins back '
                    'to Health Connect. Requires the Health Connect app on '
                    'this Android device.',
                    style: TextStyle(color: MtTheme.textDim, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _working ? null : _connect,
                    icon: _working
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link, size: 18),
                    label: Text(_connected ? 'Reconnect' : 'Connect'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Apple Health, Fitbit and Google Fit are not supported in this '
              'version; two-way nutrition/hydration sync is also not available.',
              style: TextStyle(color: MtTheme.textDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
