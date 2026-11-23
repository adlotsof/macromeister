// Dashboard: today's energy picture, macros, weight and quick actions.
import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../micros.dart';
import '../../models.dart';
import '../../services/health_sync.dart';
import '../../services/fasting.dart';
import '../../services/checkin.dart';
import '../../services/expenditure.dart';
import '../../theme.dart';
import 'dashboard_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) => _DashboardView(date: AppState.instance.selectedDate),
    );
  }
}

class _DashboardView extends StatefulWidget {
  final DateTime date;
  const _DashboardView({required this.date});
  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  static const _settingKeys = [
    'show_steps',
    'show_period',
    'show_photos',
    'show_body_metrics',
    'show_energy_balance',
    'show_water',
    'show_micros',
  ];

  Future<_DashData>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
    // Reload whenever any screen refreshes AppState (logging, check-in,
    // weight, settings) — otherwise the ring/cards show stale totals until
    // a manual pull-to-refresh.
    AppState.instance.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() => _reload();

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppStateChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(_DashboardView old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_DashData> _load() async {
    final settings = <String, bool>{};
    for (final k in _settingKeys) {
      final v = await Db.getSetting(k);
      settings[k] = v == null || v == '1';
    }
    // Period/cycle tracking is meaningless for a male profile — hide the
    // card unless the user explicitly turned it on.
    if (await Db.getSetting('show_period') == null) {
      final profile = await Db.loadProfile();
      if ((profile?.sex ?? 'male') != 'female') {
        settings['show_period'] = false;
      }
    }
    final state = AppState.instance;
    final dateStr = fmtDate(widget.date);
    final totals = await state.totalsFor(dateStr);
    final targets = await state.currentTargets();

    // Anchor the 7-day chart to the selected date, not today — viewing a
    // past day must show that day's week.
    final selectedDate = widget.date;
    final from7 = fmtDate(selectedDate.subtract(const Duration(days: 6)));
    final week7 =
        await Db.logsBetween(from7, fmtDate(selectedDate));

    List<WeightEntry> weights = [];
    List<PeriodEntry> period = [];
    List<ProgressPhoto> photos = [];
    Profile? profile;
    CheckIn? lastCheckIn;
    int steps = 0;
    int waterMl = 0;
    int waterGoal = 3000;

    // Profile is needed for the check-in prompt and program info regardless
    // of whether the body-metrics tile is visible.
    weights = await Db.weights();
    profile = await Db.loadProfile();
    lastCheckIn = await Db.lastCheckIn();
    if (settings['show_period']!) {
      period = await Db.periodEntries(limit: 30);
    }
    if (settings['show_photos']!) {
      photos = await Db.photos();
    }
    if (settings['show_steps']!) {
      steps = await HealthSync.stepsForDate(widget.date);
    }
    if (settings['show_water']!) {
      waterMl = await Db.waterMl(dateStr);
      waterGoal =
          int.tryParse(await Db.getSetting('water_goal_ml') ?? '') ?? 3000;
    }
    // Micronutrient intake for the selected day + user targets (defaults for
    // untracked ids). Only nutrients the user targets are shown.
    Map<String, double> microsEaten = {};
    Map<String, double> microTargets = {};
    if (settings['show_micros']!) {
      final logs = await Db.logsForDay(dateStr);
      microsEaten = Micros.sum(logs.map((l) => l.micros));
      final stored = await Db.microTargets();
      microTargets = {
        for (final def in Micros.all)
          def.id: stored[def.id] ?? def.defaultTarget,
      };
    }

    return _DashData(
      settings: settings,
      totals: totals,
      targets: targets,
      logs7: week7,
      weights: weights,
      profile: profile,
      lastCheckIn: lastCheckIn,
      period: period,
      photos: photos,
      steps: steps,
      waterMl: waterMl,
      waterGoal: waterGoal,
      microsEaten: microsEaten,
      microTargets: microTargets,
    );
  }

  Future<void> _shiftDate(int days) async {
    AppState.instance.selectedDate =
        AppState.instance.selectedDate.add(Duration(days: days));
  }

  @override
  Widget build(BuildContext context) {
    final selected = AppState.instance.selectedDate;
    final isToday = fmtDate(selected) == fmtDate(today());
    return FutureBuilder<_DashData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          backgroundColor: MtTheme.bg,
          body: RefreshIndicator(
            color: MtTheme.accent,
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _buildDateHeader(context, selected, isToday),
                if (snap.connectionState != ConnectionState.done && data == null)
                  Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                        child: CircularProgressIndicator(color: MtTheme.accent)),
                  )
                else if (data != null) ...[
                  const SizedBox(height: 12),
                  _EnergyCard(
                      data: data,
                      dateStr: fmtDate(widget.date),
                      onChanged: _reload),
                  _CheckInPrompt(data: data, onChanged: _reload),
                  const SizedBox(height: 12),
                  _MacroCard(data: data),
                  const SizedBox(height: 12),
                  if (data.settings['show_micros']!) ...[
                    _MicrosCard(data: data),
                    const SizedBox(height: 12),
                  ],
                  _WeekChartCard(data: data, dateStr: fmtDate(widget.date)),
                  if (data.settings['show_energy_balance']!) ...[
                    const SizedBox(height: 12),
                    _EnergyBalanceCard(data: data),
                  ],
                  if (data.settings['show_body_metrics']!) ...[
                    const SizedBox(height: 12),
                    _BodyMetricsCard(data: data, onChanged: _reload),
                  ],
                  if (data.settings['show_steps']!) ...[
                    const SizedBox(height: 12),
                    _StepsCard(data: data),
                  ],
                  if (data.settings['show_water']!) ...[
                    const SizedBox(height: 12),
                    _WaterCard(
                        data: data,
                        dateStr: fmtDate(widget.date),
                        onChanged: _reload),
                  ],
                  const SizedBox(height: 12),
                  _FastingCard(data: data, onChanged: _reload),

                  if (data.settings['show_period']!) ...[
                    const SizedBox(height: 12),
                    _PeriodCard(data: data, onChanged: _reload),
                  ],
                  if (data.settings['show_photos']!) ...[
                    const SizedBox(height: 12),
                    _PhotosCard(data: data, onChanged: _reload),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateHeader(BuildContext context, DateTime selected, bool isToday) {
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return Row(
      children: [
        IconButton(
          onPressed: () => _shiftDate(-1),
          icon: Icon(Icons.chevron_left, color: MtTheme.textDim),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                isToday
                    ? 'Today'
                    : '${weekdayNames[selected.weekday - 1]}, ${monthNames[selected.month - 1]} ${selected.day}',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: MtTheme.text),
              ),
              if (!isToday && fmtDate(selected) == fmtDate(today().subtract(const Duration(days: 1))))
                Text('Yesterday',
                    style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
            ],
          ),
        ),
        IconButton(
          onPressed: isToday ? null : () => _shiftDate(1),
          icon: Icon(Icons.chevron_right,
              color: isToday ? MtTheme.surfaceHi : MtTheme.textDim),
        ),
      ],
    );
  }
}

class _DashData {
  final Map<String, bool> settings;
  final DayTotals totals;
  final MacroTargets targets;
  final List<LogEntry> logs7;
  final List<WeightEntry> weights;
  final Profile? profile;
  final CheckIn? lastCheckIn;
  final List<PeriodEntry> period;
  final List<ProgressPhoto> photos;
  final int steps;
  final int waterMl;
  final int waterGoal;
  final Map<String, double> microsEaten;
  final Map<String, double> microTargets;
  _DashData({
    required this.settings,
    required this.totals,
    required this.targets,
    required this.logs7,
    required this.weights,
    required this.profile,
    required this.lastCheckIn,
    required this.period,
    required this.photos,
    required this.steps,
    required this.waterMl,
    required this.waterGoal,
    required this.microsEaten,
    required this.microTargets,
  });

  double? get weightTrendKgPerWeek {
    final slope = ExpenditureEngine.weightSlopeKgPerDay(weights, 14);
    return slope == null ? null : slope * 7;
  }

  double? get meanIntake7 {
    final now = DateTime.now();
    final byDay = <String, double>{};
    for (final l in logs7) {
      if (now.difference(DateTime.parse(l.date)).inDays > 6) continue;
      byDay[l.date] = (byDay[l.date] ?? 0) + l.kcal;
    }
    if (byDay.isEmpty) return null;
    // Average over LOGGED days (matches the check-in screen),
    // not the calendar window — ÷7 understates intake when days are skipped.
    final logged = byDay.values.where((v) => v > 0).length;
    final sum = byDay.values.fold(0.0, (a, b) => a + b);
    return logged > 0 ? sum / logged : null;
  }
}

// ---------------------------------------------------------------- energy ring

class _EnergyCard extends StatelessWidget {
  final _DashData data;
  final String dateStr;
  final VoidCallback onChanged;
  const _EnergyCard({required this.data, required this.dateStr, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final consumed = data.totals.kcal;
    final target = data.targets.dailyTargetKcal;
    final remaining = target - consumed;
    final over = remaining < 0;
    final progress = target <= 0 ? 0.0 : (consumed / target).clamp(0.0, 1.0);
    final fasted = dateStr == fmtDate(today());
    return MtCard(
      child: Column(
        children: [
          RingProgress(
            progress: progress,
            color: over ? MtTheme.accentAlt : MtTheme.accent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(over ? '+${fmtKcal(-remaining)}' : fmtKcal(remaining),
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: over ? MtTheme.accentAlt : MtTheme.text)),
                Text(over ? 'kcal over' : 'kcal left',
                    style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _kcol('Eaten', fmtKcal(consumed), MtTheme.text),
              _kcol('Target', fmtKcal(target), MtTheme.textDim),
              _kcol('Burned', fmtKcal(data.targets.expenditure), MtTheme.textDim),
            ],
          ),
          if (data.totals.kcal == 0 && fasted) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: MtTheme.accent),
                  foregroundColor: MtTheme.accent,
                ),
                onPressed: () => _markFasted(context),
                child: const Text('Mark fasted (zero-calorie day)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kcol(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: MtTheme.textDim)),
        ],
      );

  Future<void> _markFasted(BuildContext context) async {
    // Idempotent: never stack duplicate 'Fasted' markers for the same day.
    final existing = await Db.logsForDay(dateStr);
    if (existing.any((l) => l.fasted)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Already marked as fasted today.')));
      }
      return;
    }
    await Db.insertLog(LogEntry(
      date: dateStr,
      meal: 'breakfast',
      name: 'Fasted',
      grams: 0,
      kcal: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      fasted: true,
    ));
    AppState.instance.refresh();
    onChanged();
  }
}

// ---------------------------------------------------------------- macros

class _MacroCard extends StatelessWidget {
  final _DashData data;
  const _MacroCard({required this.data});

  @override
  Widget build(BuildContext context) => MtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader('Macros', icon: Icons.pie_chart_outline),
            const SizedBox(height: 14),
            MacroBar(
                label: 'Protein',
                value: data.totals.protein,
                target: data.targets.protein,
                color: MtTheme.accent),
            const SizedBox(height: 12),
            MacroBar(
                label: 'Carbs',
                value: data.totals.carbs,
                target: data.targets.carbs,
                color: MtTheme.accentAlt),
            const SizedBox(height: 12),
            MacroBar(
                label: 'Fat',
                value: data.totals.fat,
                target: data.targets.fat,
                color: const Color(0xFFF2B75C)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- micros

/// Micronutrient intake vs. daily targets for the selected day. Bars render
/// for every tracked nutrient (defaults unless customized), matching the
/// MacroFactor micronutrient summary. Tap the header to edit targets.
class _MicrosCard extends StatelessWidget {
  final _DashData data;
  const _MicrosCard({required this.data});

  Future<void> _editTargets(BuildContext context) async {
    final stored = await Db.microTargets();
    if (!context.mounted) return;
    final controllers = {
      for (final def in Micros.all)
        def.id: TextEditingController(
            text: stored.containsKey(def.id)
                ? _fmt(stored[def.id]!)
                : ''), // empty = use default
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Micronutrient targets', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Empty = default target. Values are per day.',
                style: TextStyle(fontSize: 12, color: MtTheme.textDim),
              ),
              const SizedBox(height: 10),
              for (final def in Micros.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controllers[def.id],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${def.label} (default ${_fmt(def.defaultTarget)})',
                      suffixText: def.unit,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text('Cancel', style: TextStyle(color: MtTheme.textDim))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) {
      for (final c in controllers.values) {
        c.dispose();
      }
      return;
    }
    // Persist only the customized ids; empty strings revert to defaults.
    final targets = <String, double>{};
    for (final def in Micros.all) {
      final t = controllers[def.id]!.text.trim();
      if (t.isEmpty) continue;
      final v = double.tryParse(t.replaceAll(',', '.'));
      if (v != null && v > 0) targets[def.id] = v;
    }
    for (final c in controllers.values) {
      c.dispose();
    }
    await Db.setMicroTargets(targets);
    AppState.instance.refresh();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final eaten = data.microsEaten;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader('Micronutrients',
              icon: Icons.medication_liquid,
              trailing: InkWell(
                onTap: () => _editTargets(context),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('edit targets',
                      style:
                          TextStyle(fontSize: 11, color: MtTheme.textDim)),
                ),
              )),
          const SizedBox(height: 12),
          if (eaten.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Log foods with micronutrient data (custom foods → '
                'Micronutrients per 100 g) to see intake here.',
                style: TextStyle(fontSize: 12, color: MtTheme.textDim),
              ),
            )
          else
            for (final def in Micros.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MacroBar(
                  label: def.label,
                  value: eaten[def.id] ?? 0,
                  target: data.microTargets[def.id] ?? def.defaultTarget,
                  color: MtTheme.accentAlt,
                  unit: def.unit,
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- week chart

class _WeekChartCard extends StatelessWidget {
  final _DashData data;
  final String dateStr;
  const _WeekChartCard({required this.data, required this.dateStr});

  @override
  Widget build(BuildContext context) {
    final byDay = <String, double>{};
    for (final l in data.logs7) {
      byDay[l.date] = (byDay[l.date] ?? 0) + l.kcal;
    }
    final target = data.targets.dailyTargetKcal;
    final days = List.generate(7, (i) {
      // Anchor to the SELECTED date so past-day views show the right window.
      final d = DateTime.parse(dateStr).subtract(Duration(days: 6 - i));
      final key = fmtDate(d);
      return (date: d, kcal: byDay[key] ?? 0, isSel: key == dateStr);
    });
    final hasData = days.any((d) => d.kcal > 0);

    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: CardHeader('Last 7 days', icon: Icons.bar_chart)),
              Text('target ${fmtKcal(target)}',
                  style: TextStyle(fontSize: 11, color: MtTheme.textDim)),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            child: hasData
                ? BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: ([
                        target * 1.15,
                        ...days.map((d) => d.kcal),
                      ]).reduce((a, b) => a > b ? a : b) *
                          1.05,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles:
                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              const names = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
                              final d = days[i].date;
                              final txt = names[d.weekday % 7];
                              final sel = days[i].isSel;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(txt,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: sel
                                            ? MtTheme.accent
                                            : MtTheme.textDim,
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.w400)),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < days.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: days[i].kcal,
                              width: 14,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                              color: days[i].isSel
                                  ? MtTheme.accent
                                  : MtTheme.accent.withValues(alpha: 0.45),
                            ),
                          ]),
                      ],
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                            '${fmtKcal(rod.toY)} kcal',
                            TextStyle(
                                color: MtTheme.text, fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.insights, color: MtTheme.textDim, size: 28),
                        SizedBox(height: 6),
                        Text('Log meals to see your weekly trend',
                            style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- energy balance

class _EnergyBalanceCard extends StatelessWidget {
  final _DashData data;
  const _EnergyBalanceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final intake = data.meanIntake7;
    final exp = data.targets.expenditure;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader('Energy balance', icon: Icons.balance),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Avg intake (7d)',
                  value: intake == null ? '—' : '${fmtKcal(intake)} kcal',
                  icon: Icons.restaurant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: 'Est. expenditure',
                  value: '${fmtKcal(exp)} kcal',
                  icon: Icons.local_fire_department,
                  iconColor: MtTheme.accentAlt,
                ),
              ),
            ],
          ),
          if (intake != null) ...[
            const SizedBox(height: 12),
            Text(
              'Daily net: ${intake - exp >= 0 ? '+' : ''}${fmtKcal(intake - exp)} kcal '
              '(${(intake - exp) >= 0 ? 'surplus' : 'deficit'})',
              style: TextStyle(fontSize: 12, color: MtTheme.textDim),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Keep logging — a 7-day average appears once you have data.',
              style: TextStyle(fontSize: 12, color: MtTheme.textDim),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- body metrics

class _BodyMetricsCard extends StatelessWidget {
  final _DashData data;
  final VoidCallback onChanged;
  const _BodyMetricsCard({required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final weights = data.weights;
    final latest = weights.isEmpty ? null : weights.last;
    final profile = data.profile;
    final goal = profile?.goalWeightKg;
    final trend = data.weightTrendKgPerWeek;
    final start = profile?.startWeightKg;

    double? progressPct;
    if (latest != null && goal != null && start != null && (start - goal).abs() > 0.01) {
      progressPct = ((start - latest.weightKg) / (start - goal)).clamp(0.0, 1.0) * 100;
    }

    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader('Body', icon: Icons.monitor_weight_outlined,
              trailing: TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero),
                onPressed: () => _addWeight(context),
                child: Text('+ Log weight',
                    style: TextStyle(fontSize: 12, color: MtTheme.accent)),
              )),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Weight',
                  value: latest == null ? '—' : '${latest.weightKg.toStringAsFixed(1)} kg',
                  sub: latest == null
                      ? null
                      : fmtDate(DateTime.parse(latest.date)) == fmtDate(today())
                          ? 'today'
                          : 'as of ${fmtDate(DateTime.parse(latest.date)).substring(5)}',
                  icon: Icons.scale_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: 'Trend (14d)',
                  value: trend == null
                      ? '—'
                      : '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(2)} kg/wk',
                  icon: Icons.trending_down,
                  iconColor: MtTheme.accentAlt,
                ),
              ),
            ],
          ),
          if (goal != null && progressPct != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Goal ${goal.toStringAsFixed(1)} kg',
                    style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
                Text('${progressPct.toStringAsFixed(0)}% of the way',
                    style: TextStyle(fontSize: 12, color: MtTheme.accent)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressPct / 100,
                minHeight: 6,
                backgroundColor: MtTheme.surfaceHi,
                valueColor: AlwaysStoppedAnimation(MtTheme.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addWeight(BuildContext context) async {
    final controller = TextEditingController(
        text: data.weights.isEmpty ? '' : data.weights.last.weightKg.toStringAsFixed(1));
    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Log weight', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Weight (kg)'),
          onSubmitted: (v) =>
              Navigator.pop(ctx, double.tryParse(v.replaceAll(',', '.'))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: MtTheme.textDim))),
          FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(controller.text.replaceAll(',', '.'))),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (kg == null || kg <= 0) return;
    final date = AppState.instance.selectedDateStr;
    await Db.upsertWeight(WeightEntry(date: date, weightKg: kg));
    await HealthSync.writeWeight(AppState.instance.selectedDate, kg);
    AppState.instance.refresh();
    onChanged();
  }
}

// ---------------------------------------------------------------- steps

class _StepsCard extends StatelessWidget {
  final _DashData data;
  const _StepsCard({required this.data});

  @override
  Widget build(BuildContext context) => MtCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: MtTheme.surfaceHi,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.directions_walk, color: MtTheme.accentAlt),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Steps',
                      style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
                  const SizedBox(height: 2),
                  Text('${data.steps}',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: MtTheme.text)),
                ],
              ),
            ),
            Icon(Icons.watch_outlined, color: MtTheme.textDim, size: 18),
            const SizedBox(width: 6),
            Text('Health Connect',
                style: TextStyle(fontSize: 11, color: MtTheme.textDim)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- water

class _WaterCard extends StatelessWidget {
  final _DashData data;
  final String dateStr;
  final VoidCallback onChanged;
  const _WaterCard(
      {required this.data, required this.dateStr, required this.onChanged});

  Future<void> _add(BuildContext context, int ml) async {
    await Db.addWater(dateStr, ml);
    AppState.instance.refresh();
    onChanged();
  }

  Future<void> _editGoal(BuildContext context) async {
    final controller =
        TextEditingController(text: data.waterGoal.toString());
    final goal = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Daily water goal', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(),
          decoration: const InputDecoration(labelText: 'Goal (ml)'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Cancel', style: TextStyle(color: MtTheme.textDim))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (goal == null || goal <= 0) return;
    await Db.setSetting('water_goal_ml', '$goal');
    AppState.instance.refresh();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final ml = data.waterMl;
    final goal = data.waterGoal;
    final progress = goal <= 0 ? 0.0 : (ml / goal).clamp(0.0, 1.0);
    final done = ml >= goal;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader('Water', icon: Icons.water_drop_outlined,
              iconColor: const Color(0xFF5BB8F0),
              trailing: InkWell(
                onTap: () => _editGoal(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('goal ${(goal / 1000).toStringAsFixed(1)} L',
                      style: TextStyle(
                          fontSize: 11, color: MtTheme.textDim)),
                ),
              )),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${ml >= 1000 ? (ml / 1000).toStringAsFixed(1) : ml}'
                      '${ml >= 1000 ? ' L' : ' ml'}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: MtTheme.text)),
              const SizedBox(width: 6),
              Text(done ? '· goal reached' : 'of ${(goal / 1000).toStringAsFixed(1)} L',
                  style:
                      TextStyle(fontSize: 12, color: MtTheme.textDim)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MtTheme.surfaceHi,
              valueColor:
                  const AlwaysStoppedAnimation(Color(0xFF5BB8F0)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final amount in const [250, 500]) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _add(context, amount),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF5BB8F0)),
                        foregroundColor: const Color(0xFF5BB8F0),
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                    child: Text('+$amount ml'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      ml <= 0 ? null : () => _add(context, -250),
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: ml <= 0
                              ? MtTheme.textDim.withValues(alpha: 0.3)
                              : MtTheme.textDim),
                      foregroundColor: MtTheme.textDim,
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                  child: const Text('Undo 250'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- period

class _PeriodCard extends StatelessWidget {
  final _DashData data;
  final VoidCallback onChanged;
  const _PeriodCard({required this.data, required this.onChanged});

  static const _flowNames = ['None', 'Light', 'Medium', 'Heavy'];

  @override
  Widget build(BuildContext context) {
    final latest = data.period.isEmpty ? null : data.period.first;
    final selectedStr = AppState.instance.selectedDateStr;
    final todayEntry = data.period
        .where((p) => p.date == selectedStr)
        .cast<PeriodEntry?>()
        .firstWhere((_) => true, orElse: () => null);

    // Cycle length estimate from the two most recent flow>0 starts.
    String? cycleInfo;
    final starts = data.period
        .where((p) => p.flow > 0)
        .map((p) => DateTime.parse(p.date))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (starts.length >= 2) {
      final days = starts.first.difference(starts[1]).inDays;
      if (days > 0 && days < 90) cycleInfo = 'last cycle: $days days';
    }

    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader('Cycle', icon: Icons.calendar_today_outlined,
              iconColor: Color(0xFFF08CAE)),
          const SizedBox(height: 12),
          Text(
            latest == null
                ? 'No entries yet. Track flow and symptoms to see patterns.'
                : 'Last entry ${latest.date.substring(5)} — ${_flowNames[latest.flow.clamp(0, 3)]}'
                  '${cycleInfo == null ? '' : ' · $cycleInfo'}',
            style: TextStyle(fontSize: 13, color: MtTheme.textDim),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: todayEntry != null && todayEntry.flow > 0
                        ? MtTheme.textDim
                        : const Color(0xFFF08CAE)),
                foregroundColor: todayEntry != null && todayEntry.flow > 0
                    ? MtTheme.textDim
                    : const Color(0xFFF08CAE),
              ),
              onPressed: () => _logFlow(context),
              child: Text(todayEntry != null && todayEntry.flow > 0
                  ? 'Edit today (${'None Light Medium Heavy'.split(' ')[todayEntry.flow.clamp(1, 3)]})'
                  : 'Log flow for ${selectedStr.substring(5)}'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logFlow(BuildContext context) async {
    final selectedStr = AppState.instance.selectedDateStr;
    final existing = data.period
        .where((p) => p.date == selectedStr)
        .cast<PeriodEntry?>()
        .firstWhere((_) => true, orElse: () => null);
    final symptomsCtl = TextEditingController(text: existing?.symptoms ?? '');
    var flow = existing?.flow ?? 0;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: MtTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flow on ${selectedStr.substring(5)}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              SegmentedButton<int>(
                segments: [
                  for (var i = 1; i <= 3; i++)
                    ButtonSegment(value: i, label: Text(_flowNames[i])),
                ],
                selected: {flow == 0 ? 1 : flow},
                onSelectionChanged: (s) => setSheet(() => flow = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: const Color(0xFFF08CAE),
                  selectedForegroundColor: const Color(0xFF20101A),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: symptomsCtl,
                decoration: const InputDecoration(
                    labelText: 'Symptoms (comma separated)'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    await Db.upsertPeriod(PeriodEntry(
        date: selectedStr, flow: flow, symptoms: symptomsCtl.text.trim()));
    AppState.instance.refresh();
    onChanged();
  }
}

// ---------------------------------------------------------------- photos

class _PhotosCard extends StatelessWidget {
  final _DashData data;
  final VoidCallback onChanged;
  const _PhotosCard({required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final photos = data.photos;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader('Progress photos',
              icon: Icons.photo_camera_outlined,
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _addPhoto(context),
                icon: Icon(Icons.add_a_photo_outlined,
                    size: 20, color: MtTheme.accent),
              )),
          const SizedBox(height: 8),
          if (photos.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No photos yet. Add one to track visual progress.',
                  style: TextStyle(fontSize: 12, color: MtTheme.textDim)),
            )
          else
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = photos[i];
                  return GestureDetector(
                    onTap: () => SharePlus.instance.share(ShareParams(
                        files: [XFile(p.path)],
                        text: 'Progress photo ${p.date}')),
                    onLongPress: () => confirmDeletePhoto(context, p, onChanged),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 88,
                        height: 108,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(p.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                      color: MtTheme.surfaceHi,
                                      child: Icon(Icons.broken_image_outlined,
                                          color: MtTheme.textDim),
                                    )),
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
                            Positioned(
                              top: 0,
                              right: 0,
                              child: _PhotoDeleteButton(
                                  photo: p, onChanged: onChanged),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addPhoto(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
          source: ImageSource.camera, maxWidth: 1200, imageQuality: 80);
      final picked = x ?? await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final w = data.weights.isNotEmpty ? data.weights.last.weightKg : null;
      await Db.insertPhoto(ProgressPhoto(
          date: AppState.instance.selectedDateStr, path: picked.path, weightKg: w));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MtTheme.surfaceHi,
          content: Text('Photo added')));
      AppState.instance.refresh();
      onChanged();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: MtTheme.danger,
            content: Text('Could not add photo')));
      }
    }
  }
}

/// Deletes the photo's DB row and backing file.
Future<void> _deletePhotoEverywhere(ProgressPhoto photo) async {
  final id = photo.id;
  if (id == null) {
    throw StateError('progress photo has no DB id; cannot delete');
  }
  await Db.deletePhoto(id);
  final f = File(photo.path);
  if (await f.exists()) await f.delete();
}

/// Confirmation + delete of a progress photo (DB row and backing file).
/// [onDelete] defaults to the real deletion; tests can inject a recorder.
Future<void> confirmDeletePhoto(
    BuildContext context, ProgressPhoto photo, VoidCallback onChanged,
    {Future<void> Function(ProgressPhoto)? onDelete}) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: MtTheme.surface,
          title: const Text('Delete photo?'),
          content: Text('Remove the progress photo from ${photo.date}?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: MtTheme.danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      ) ??
      false;
  if (!ok || !context.mounted) return;
  try {
    if (onDelete != null) {
      await onDelete(photo);
    } else {
      await _deletePhotoEverywhere(photo);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MtTheme.surfaceHi,
        content: Text('Photo deleted')));
    AppState.instance.refresh();
    onChanged();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MtTheme.danger,
          content: Text('Could not delete photo')));
    }
  }
}

/// Visible delete affordance for one progress photo. Re-entry guard so a
/// rapid double-tap cannot stack two confirmation dialogs.
class _PhotoDeleteButton extends StatefulWidget {
  final ProgressPhoto photo;
  final VoidCallback onChanged;
  const _PhotoDeleteButton({required this.photo, required this.onChanged});

  @override
  State<_PhotoDeleteButton> createState() => _PhotoDeleteButtonState();
}

class _PhotoDeleteButtonState extends State<_PhotoDeleteButton> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          if (_asking) return;
          _asking = true;
          try {
            await confirmDeletePhoto(
                context, widget.photo, widget.onChanged);
          } finally {
            _asking = false;
          }
        },
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------- fasting

/// Fasting timer card: start/stop, elapsed time against the selected preset
/// goal, and the last few completed fasts. Live ticks every second.
class _FastingCard extends StatefulWidget {
  final _DashData data;
  final VoidCallback onChanged;
  const _FastingCard({required this.data, required this.onChanged});

  @override
  State<_FastingCard> createState() => _FastingCardState();
}

class _FastingCardState extends State<_FastingCard> {
  static const _goalH = 'fasting_goal_h'; // user goal, default 16
  Timer? _tick;
  DateTime? _start;
  int _goalH_ = 16;

  @override
  void initState() {
    super.initState();
    _load();
    // 1-minute granularity is plenty; 30 s avoids visible clock drift.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _start != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _start = await FastingService.runningStart();
    _goalH_ =
        int.tryParse(await Db.getSetting(_goalH) ?? '') ?? 16;
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_start != null) {
      final duration = await FastingService.end(DateTime.now());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MtTheme.surfaceHi,
          content: Text(duration == null
              ? 'Fast ended'
              : 'Fast ended: ${FastingService.fmtDuration(duration)}')));
    } else {
      await FastingService.start(DateTime.now());
      if (!mounted) return;
    }
    AppState.instance.refresh();
    widget.onChanged();
    await _load();
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: '$_goalH_');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title:
            const Text('Fasting goal', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(),
          decoration: const InputDecoration(labelText: 'Goal (hours)'),
          onSubmitted: (s) =>
              Navigator.pop(ctx, int.tryParse(s)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Cancel', style: TextStyle(color: MtTheme.textDim))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (v == null || v <= 0 || v > 168) return;
    await Db.setSetting(_goalH, '$v');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _start == null
        ? null
        : DateTime.now().difference(_start!);
    final clamped = elapsed == null || elapsed.isNegative
        ? Duration.zero
        : elapsed;
    final goal = Duration(hours: _goalH_);
    final progress =
        elapsed == null ? 0.0 : (clamped.inMinutes / goal.inMinutes).clamp(0.0, 1.0);
    final remaining = elapsed == null
        ? goal
        : (goal - clamped).isNegative ? Duration.zero : goal - clamped;
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader('Fasting',
              icon: Icons.hourglass_top,
              trailing: InkWell(
                onTap: _editGoal,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(fastingGoalLabel(_goalH_),
                      style:
                          TextStyle(fontSize: 11, color: MtTheme.textDim)),
                ),
              )),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                elapsed == null
                    ? 'Not fasting'
                    : FastingService.fmtDuration(elapsed),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: MtTheme.text),
              ),
              const SizedBox(width: 6),
              Text(
                elapsed == null
                    ? '· $_goalH_ h presets'
                    : '· ${FastingService.fmtDuration(remaining)} to $_goalH_ h goal',
                style: TextStyle(fontSize: 12, color: MtTheme.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MtTheme.surfaceHi,
              valueColor: AlwaysStoppedAnimation(
                  progress >= 1.0 ? MtTheme.accent : MtTheme.accentAlt),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: elapsed == null
                      ? MtTheme.accent
                      : MtTheme.danger),
              icon: Icon(elapsed == null
                  ? Icons.play_arrow
                  : Icons.stop),
              onPressed: _toggle,
              label: Text(elapsed == null ? 'Start fast' : 'End fast'),
            ),
          ),
          if (elapsed == null && widget.data.lastCheckIn != null) ...[
            const SizedBox(height: 8),
            FutureBuilder<List<({DateTime start, DateTime end})>>(
              future: FastingService.history(),
              builder: (context, snap) {
                final h = snap.data ?? const [];
                if (h.isEmpty) return const SizedBox.shrink();
                final last = h.first;
                return Text(
                  'Last fast: ${FastingService.fmtDuration(last.end.difference(last.start))} '
                  '(${fmtDate(last.end)})',
                  style: TextStyle(
                      fontSize: 11, color: MtTheme.textDim),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Fasting-card goal label ('goal 16 h'). Regression for a missing string
/// interpolation that rendered the literal text 'goal h'.
String fastingGoalLabel(int goalHours) => 'goal $goalHours h';

// ---------------------------------------------------------------- check-in prompt

class _CheckInPrompt extends StatelessWidget {
  final _DashData data;
  final VoidCallback onChanged;
  const _CheckInPrompt({required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    if (profile == null || profile.programType != 'coached') return const SizedBox.shrink();
    final now = DateTime.now();
    // Prompt shows only on the chosen check-in weekday (MacroFactor
    // semantics); lib/services/checkin.dart documents the regression this
    // fixes (it used to stay visible all week with a Monday check-in).
    final due = isCheckInDue(now, profile.checkinWeekday,
        lastCheckInWeekStart: data.lastCheckIn?.weekStart);
    if (!due) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader('Weekly check-in',
                icon: Icons.event_available, iconColor: MtTheme.accentAlt),
            const SizedBox(height: 10),
            Text(
              'It\'s check-in day. Confirm your weight to update your program targets.',
              style: TextStyle(fontSize: 13, color: MtTheme.textDim),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _doCheckIn(context),
                child: const Text('Start check-in'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doCheckIn(BuildContext context) async {
    final controller = TextEditingController(
        text: data.weights.isEmpty
            ? data.profile?.startWeightKg.toStringAsFixed(1) ?? ''
            : data.weights.last.weightKg.toStringAsFixed(1));
    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtTheme.surface,
        title: const Text('Weekly check-in', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.meanIntake7 != null)
              Text('7-day average intake: ${fmtKcal(data.meanIntake7!)} kcal',
                  style: TextStyle(fontSize: 13, color: MtTheme.textDim)),
            Text(
                'Current expenditure estimate: ${fmtKcal(data.targets.expenditure)} kcal',
                style: TextStyle(fontSize: 13, color: MtTheme.textDim)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Today\'s weight (kg)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: MtTheme.textDim))),
          FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(controller.text.replaceAll(',', '.'))),
              child: const Text('Confirm')),
        ],
      ),
    );
    controller.dispose();
    if (kg == null || kg <= 0) return;
    final now = DateTime.now();
    await Db.upsertWeight(WeightEntry(date: fmtDate(now), weightKg: kg));
    await HealthSync.writeWeight(now, kg);
    await Db.insertCheckIn(CheckIn(
      date: fmtDate(now),
      weekStart: fmtDate(weekStart(now)),
      weightKg: kg,
      kcalAvg7d: data.meanIntake7 ?? 0,
      expenditure: data.targets.expenditure,
      dailyTarget: ExpenditureEngine.dailyTarget(
          data.targets.expenditure, data.profile!.goalRateKgPerWeek),
    ));
    AppState.instance.refresh();
    onChanged();
  }
}
