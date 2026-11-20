// Data visibility: toggles that show/hide optional dashboard cards.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../db.dart';
import '../../theme.dart';

class DataVisibilityScreen extends StatefulWidget {
  const DataVisibilityScreen({super.key});
  @override
  State<DataVisibilityScreen> createState() => _DataVisibilityScreenState();
}

class _VisibilityItem {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  _VisibilityItem(this.key, this.title, this.subtitle, this.icon);
}

class _DataVisibilityScreenState extends State<DataVisibilityScreen> {
  static final _items = [
    _VisibilityItem('show_habits', 'Habits',
        'Daily habit checklist card', Icons.checklist),
    _VisibilityItem('show_steps', 'Steps',
        'Step count from Health Connect', Icons.directions_walk),
    _VisibilityItem('show_period', 'Period tracking',
        'Cycle logging and predictions', Icons.calendar_month),
    _VisibilityItem('show_photos', 'Progress photos',
        'Photo timeline card', Icons.photo_outlined),
    _VisibilityItem('show_body_metrics', 'Body metrics',
        'Weight and body-fat trends', Icons.monitor_weight_outlined),
    _VisibilityItem('show_energy_balance', 'Energy balance',
        'Intake vs. expenditure chart', Icons.swap_vert),
    _VisibilityItem('show_water', 'Water',
        'Daily hydration tracking with quick +250/+500 ml buttons',
        Icons.water_drop),
  ];

  final Map<String, bool> _values = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await Db.allSettings();
    if (!mounted) return;
    setState(() {
      for (final item in _items) {
        _values[item.key] = settings[item.key] != '0'; // default on
      }
    });
  }

  Future<void> _toggle(String key, bool value) async {
    await Db.setSetting(key, value ? '1' : '0');
    setState(() => _values[key] = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data visibility')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
                'Choose which optional cards appear on the dashboard.',
                style: TextStyle(color: MtTheme.textDim, fontSize: 13)),
          ),
          for (final item in _items)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                secondary: Icon(item.icon, color: MtTheme.accent),
                title: Text(item.title),
                subtitle: Text(item.subtitle,
                    style: TextStyle(
                        color: MtTheme.textDim, fontSize: 12)),
                value: _values[item.key] ?? true,
                onChanged: (v) => _toggle(item.key, v),
              ),
            ),
        ],
      ),
    );
  }
}
