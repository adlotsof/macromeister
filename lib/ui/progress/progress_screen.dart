// Progress & analytics: weight trend, daily intake bars, and the progress
// photo timeline in one screen (MacroFactor parity gap #10). All data comes
// from the existing Db layer; charts use fl_chart like the dashboard.
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../models.dart';
import '../../theme.dart';
import '../dashboard/dashboard_widgets.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtTheme.bg,
      appBar: AppBar(title: const Text('Progress')),
      body: const _ProgressBody(),
    );
  }
}

class _ProgressData {
  final List<WeightEntry> weights;
  final Map<String, double> kcalByDay; // last 28 logged days, ascending
  final List<ProgressPhoto> photos;
  _ProgressData(this.weights, this.kcalByDay, this.photos);
}

class _ProgressBody extends StatefulWidget {
  const _ProgressBody();
  @override
  State<_ProgressBody> createState() => _ProgressBodyState();
}

class _ProgressBodyState extends State<_ProgressBody> {
  Future<_ProgressData>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
    AppState.instance.addListener(_reload);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_ProgressData> _load() async {
    final weights = await Db.weights(limit: 400);
    final from = fmtDate(today().subtract(const Duration(days: 27)));
    final logs = await Db.logsBetween(from, fmtDate(today()));
    final byDay = <String, double>{};
    for (final l in logs) {
      byDay[l.date] = (byDay[l.date] ?? 0) + l.kcal;
    }
    final photos = await Db.photos();
    return _ProgressData(weights, byDay, photos);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProgressData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (!snap.hasData || data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _WeightCard(weights: data.weights),
            const SizedBox(height: 14),
            _IntakeCard(kcalByDay: data.kcalByDay),
            const SizedBox(height: 14),
            _PhotosCard(photos: data.photos),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ weight

class _WeightCard extends StatelessWidget {
  final List<WeightEntry> weights;
  const _WeightCard({required this.weights});

  @override
  Widget build(BuildContext context) {
    final points = weights
        .map((w) => (date: DateTime.parse(w.date), kg: w.weightKg))
        .toList();
    if (points.length < 2) {
      return _emptyCard('Weight trend',
          icon: Icons.monitor_weight_outlined,
          hint: 'Log weights on at least two days to see the trend.');
    }
    final minY = points.map((p) => p.kg).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.kg).reduce((a, b) => a > b ? a : b);
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].kg),
    ];
    final delta = points.last.kg - points.first.kg;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
                child: CardHeader('Weight trend',
                    icon: Icons.monitor_weight_outlined)),
            Text('${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                style: TextStyle(
                    fontSize: 12,
                    color: delta <= 0 ? MtTheme.accent : MtTheme.danger)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: LineChart(LineChartData(
              minY: minY - 0.5,
              maxY: maxY + 0.5,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} kg',
                          TextStyle(
                              color: MtTheme.text, fontSize: 11,
                              fontWeight: FontWeight.w600)))
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 3,
                  color: MtTheme.accent,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true,
                      color: MtTheme.accent.withValues(alpha: 0.12)),
                ),
              ],
            )),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ intake

class _IntakeCard extends StatelessWidget {
  final Map<String, double> kcalByDay; // date -> kcal
  const _IntakeCard({required this.kcalByDay});

  @override
  Widget build(BuildContext context) {
    final days = List.generate(28, (i) {
      final d = today().subtract(Duration(days: 27 - i));
      final key = fmtDate(d);
      return (key: key, kcal: kcalByDay[key] ?? 0);
    });
    final hasData = days.any((d) => d.kcal > 0);
    if (!hasData) {
      return _emptyCard('Intake (28 days)',
          icon: Icons.bar_chart,
          hint: 'Log meals to see your daily intake history.');
    }
    final maxY = ([3000.0, ...days.map((d) => d.kcal)])
        .reduce((a, b) => a > b ? a : b) * 1.1;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader('Intake (28 days)', icon: Icons.bar_chart),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: BarChart(BarChartData(
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      '${rod.toY.round()} kcal',
                      TextStyle(
                          color: MtTheme.text, fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: days[i].kcal,
                      width: 6,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3)),
                      color: days[i].kcal > 0
                          ? MtTheme.accentAlt
                          : MtTheme.surfaceHi,
                    ),
                  ]),
              ],
            )),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ photos

class _PhotosCard extends StatelessWidget {
  final List<ProgressPhoto> photos;
  const _PhotosCard({required this.photos});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return _emptyCard('Photo timeline',
          icon: Icons.photo_outlined,
          hint:
              'No progress photos yet. Add one from the dashboard Photos card.');
    }
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader('Photo timeline', icon: Icons.photo_outlined),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final p = photos[i];
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(p.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                          color: MtTheme.surfaceHi,
                          child: Icon(Icons.broken_image_outlined,
                              color: MtTheme.textDim))),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black45,
                      padding: const EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: Text(p.date.substring(5),
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white)),
                    ),
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ shared

Widget _emptyCard(String title,
    {required IconData icon, required String hint}) {
  return MtCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardHeader(title, icon: icon),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(hint,
              style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
        ),
      ],
    ),
  );
}
