// Shared small widgets for the dashboard.
import 'dart:math' as math;

// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../theme.dart';

class MtCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const MtCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: MtTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class CardHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  const CardHeader(this.title, {super.key, required this.icon, this.iconColor, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? MtTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MtTheme.textDim,
                    letterSpacing: 0.3)),
          ),
          ?trailing,
        ],
      );
}

/// Circular progress ring showing [progress] (0..1) with centered content.
class RingProgress extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Color color;
  final Widget child;
  const RingProgress({
    super.key,
    required this.progress,
    required this.child,
    this.size = 168,
    this.strokeWidth = 14,
    this.color = MtTheme.accent,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
              progress: progress.clamp(0.0, 1.0), color: color, strokeWidth: strokeWidth),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  _RingPainter({required this.progress, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = MtTheme.surfaceHi;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Horizontal macro progress bar with label and value.
class MacroBar extends StatelessWidget {
  final String label;
  final double value; // consumed
  final double target; // target
  final Color color;
  final String unit; // display unit (g, mg, µg, ...)
  const MacroBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    this.unit = 'g',
  });

  @override
  Widget build(BuildContext context) {
    final frac = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: MtTheme.textDim)),
            const Spacer(),
            Text('${value.round()} / ${target.round()} $unit',
                style: const TextStyle(
                    fontSize: 12, color: MtTheme.text, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 6,
            backgroundColor: MtTheme.surfaceHi,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// Small statistic tile used in grids (weight, steps, trend, ...).
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color? iconColor;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MtTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(icon, size: 15, color: iconColor ?? MtTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: MtTheme.textDim)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: MtTheme.text)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: MtTheme.textDim)),
            ],
          ],
        ),
      );
}

String fmtKcal(double v) => v.round().toString();

String fmtKg(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 1 : 1);
