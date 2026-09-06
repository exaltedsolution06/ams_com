import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared "eye-candy" building blocks for the Resident / Admin / Security
/// dashboards. Everything here is pure Flutter (no new pubspec dependency,
/// same spirit as this project's other hand-rolled bits like the fuzzy
/// voice-command matcher) so it drops in without touching `flutter pub get`.

/// Soft, translucent decorative circles for a gradient header. Purely
/// visual — sits behind the real header content in a Stack and never
/// intercepts taps.
class HeaderBlobs extends StatelessWidget {
  const HeaderBlobs({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(children: [
        Positioned(right: -30, top: -46, child: _Blob(150, 0.10)),
        Positioned(right: 54, top: 18, child: _Blob(46, 0.09)),
        Positioned(left: -46, bottom: -54, child: _Blob(140, 0.07)),
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob(this.size, this.opacity);

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)),
      );
}

/// Subtle geometric header pattern - a more professional alternative to
/// [HeaderBlobs]' flat translucent circles: a sparse technical-drafting-
/// style dot grid plus a couple of thin hexagon outlines (not filled), in
/// low-opacity white. Positioned to echo where HeaderBlobs' circles sat
/// (top-right, bottom-left) so header balance/composition is unchanged.
/// Purely visual — sits behind the real header content and never
/// intercepts taps.
class HeaderGeometricPattern extends StatelessWidget {
  const HeaderGeometricPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        painter: _GeometricPatternPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _GeometricPatternPainter extends CustomPainter {
  const _GeometricPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Sparse dot grid, confined to the right ~55% of the header so it
    // never sits under the greeting/title text that always starts at the
    // left edge — mirrors a technical/engineering drafting grid rather
    // than a decorative pattern.
    final dotPaint = Paint()..color = Colors.white.withOpacity(0.11);
    const spacing = 20.0;
    final gridLeft = size.width * 0.45;
    var row = 0;
    for (double y = -10; y < size.height + spacing; y += spacing) {
      final rowOffset = row.isOdd ? spacing / 2 : 0.0;
      for (double x = gridLeft + rowOffset; x < size.width + spacing; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.3, dotPaint);
      }
      row++;
    }

    // Two large hexagon outlines, echoing HeaderBlobs' top-right /
    // bottom-left circle placement.
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    _drawHexagon(canvas, Offset(size.width - 4, -30), 76, linePaint);
    _drawHexagon(canvas, Offset(-28, size.height - 2), 56, linePaint);
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 6;
      final point = center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GeometricPatternPainter oldDelegate) => false;
}

/// A prominent, full-width "hero" card for a single headline figure (e.g.
/// pending dues, wallet balance) — gradient tint, icon badge, a ghost icon
/// watermark, and the number counting up from zero the first time it renders.
class GradientHeroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final double amount;
  final String subtitle;
  final Color color;
  final String currencySymbol;
  final int decimals;
  final String? actionLabel;
  final VoidCallback? onAction;

  const GradientHeroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.color,
    this.currencySymbol = '',
    this.decimals = 2,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.16), color.withOpacity(0.045)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(right: -16, bottom: -20, child: Icon(icon, size: 86, color: color.withOpacity(0.09))),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: color.withOpacity(0.9))),
              const SizedBox(height: 2),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: amount),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  '$currencySymbol${v.toStringAsFixed(decimals)}',
                  style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.w800),
                ),
              ),
              Text(subtitle, style: TextStyle(color: color.withOpacity(0.75), fontSize: 11.5)),
            ]),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                backgroundColor: color.withOpacity(0.14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(actionLabel!, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ]),
      ]),
    );
  }
}

/// A compact, wide "stat tile" — gradient icon badge, a ghost icon
/// watermark, and a count-up number. `format` lets a raw numeric value be
/// rendered as e.g. "1.2L" or "₹450" while still animating smoothly, since
/// the formatter is re-applied every animation frame against the live value.
class GradientStatTile extends StatelessWidget {
  final String label;
  final num value;
  final IconData icon;
  final Color color;
  final String Function(num v)? format;
  final VoidCallback? onTap;

  const GradientStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.format,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? (v) => v.round().toString();
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.12), Colors.white],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.14)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(right: -10, top: -14, child: Icon(icon, size: 54, color: color.withOpacity(0.08))),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text(
                    fmt(v),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color.withOpacity(0.95)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: color.withOpacity(0.5), size: 18),
        ]),
      ]),
    );
    return onTap != null ? GestureDetector(onTap: onTap, child: tile) : tile;
  }
}

/// Animated circular progress ring (donut), e.g. for an occupancy or
/// approval rate. Sweeps in from zero the first time it's built.
class StatRing extends StatelessWidget {
  final double percent; // 0..1
  final Color color;
  final Color trackColor;
  final double size;
  final double strokeWidth;
  final Widget? center;

  const StatRing({
    super.key,
    required this.percent,
    required this.color,
    this.trackColor = const Color(0xFFEDEFF3),
    this.size = 76,
    this.strokeWidth = 9,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(percent: v, color: color, trackColor: trackColor, strokeWidth: strokeWidth),
          ),
          if (center != null) center!,
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  _RingPainter({required this.percent, required this.color, required this.trackColor, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    final sweep = 2 * math.pi * percent;
    if (sweep > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, fg);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
}

/// One column in a [ComparisonBarChart].
class BarChartItem {
  final String label;
  final num value;
  final Color color;
  const BarChartItem({required this.label, required this.value, required this.color});
}

/// Small animated vertical bar-comparison chart — a lightweight "at a
/// glance" visual for 2-4 related counters (e.g. pending bills / open
/// complaints / awaiting visitors) sitting side by side.
class ComparisonBarChart extends StatelessWidget {
  final List<BarChartItem> items;
  final double height;
  const ComparisonBarChart({super.key, required this.items, this.height = 96});

  @override
  Widget build(BuildContext context) {
    double maxVal = 1;
    for (final it in items) {
      final v = it.value.toDouble();
      if (v > maxVal) maxVal = v;
    }
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items.map((item) {
          final frac = item.value.toDouble() / maxVal;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(children: [
                Text('${item.value}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: item.color)),
                const SizedBox(height: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: frac.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => FractionallySizedBox(
                        heightFactor: v.clamp(0.045, 1.0),
                        widthFactor: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [item.color, item.color.withOpacity(0.55)],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(item.label,
                    style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A small white "insight card" wrapper used to host a [StatRing] or
/// [ComparisonBarChart] side by side, matching the app's existing card
/// styling (white bg, soft shadow, rounded corners).
class InsightCard extends StatelessWidget {
  final Widget child;
  const InsightCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: child,
      );
}
