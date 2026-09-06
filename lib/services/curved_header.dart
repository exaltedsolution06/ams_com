import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'branding_service.dart';

/// A gradient panel with a soft wave cut into its bottom edge, matching the
/// "curved header" look. Colors come from BrandingService (per-apartment),
/// not hardcoded, so every apartment's own primary/accent colors flow into
/// this same shape rather than everyone getting an identical hardcoded look.
///
/// Use as the top of a Scaffold body (not as an AppBar) - place page content
/// below it, optionally overlapping it slightly with a rounded-top white
/// card for the "header behind card" layered look.
class CurvedHeader extends StatelessWidget {
  final double height;
  final Widget? child;
  final List<Color>? colors;
  // Null (default) = the original wave cut (WaveClipper) - unchanged for
  // every existing call site (login, forgot-password, referral,
  // AdminScreenHeader). Pass a value (e.g. 20) to use a plain rounded
  // rectangle - only the bottom-left/bottom-right corners rounded by this
  // many pixels, flat otherwise - instead of the wave. Used by the
  // resident/admin dashboard headers so the panel reads as a clean, mostly
  // square card rather than a deep scalloped curve.
  final double? bottomRadius;

  const CurvedHeader({super.key, this.height = 220, this.child, this.colors, this.bottomRadius});

  @override
  Widget build(BuildContext context) {
    final grad = colors ?? [BrandingService.primary, _lighten(BrandingService.primary)];
    final content = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad),
      ),
      child: child,
    );

    if (bottomRadius != null) {
      return ClipRRect(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(bottomRadius!),
          bottomRight: Radius.circular(bottomRadius!),
        ),
        child: content,
      );
    }

    return ClipPath(clipper: WaveClipper(), child: content);
  }

  static Color _lighten(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0)).withSaturation((hsl.saturation + 0.1).clamp(0.0, 1.0)).toColor();
  }
}

/// Renders [text] curving along the underside of a circle, so it echoes
/// the downward dip of the [WaveClipper] header behind it — instead of
/// sitting on a flat, straight line. The middle of the text sits lowest
/// (matching the wave's dip); the ends curve upward, mirroring the shape
/// of the curved section it sits on top of.
///
/// Toggle: BrandingService.curvedAppName (Admin > Settings > General).
class ArcText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double radius;
  final double height;

  const ArcText({
    super.key,
    required this.text,
    required this.style,
    this.radius = 320,
    this.height = 32,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
      return CustomPaint(
        size: Size(width, height),
        painter: _ArcTextPainter(text: text, style: style, radius: radius),
      );
    });
  }
}

class _ArcTextPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final double radius;

  _ArcTextPainter({required this.text, required this.style, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (text.trim().isEmpty) return;

    // Measure each character individually so we can place it along the arc.
    final chars = text.split('');
    final painters = <TextPainter>[];
    double totalWidth = 0;
    for (final c in chars) {
      final tp = TextPainter(
        text: TextSpan(text: c, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      totalWidth += tp.width;
    }
    if (totalWidth == 0) return;

    // Arc length ≈ radius * angle, so angle = arcLength / radius. Capped low
    // and independent of radius/text length so the curve stays a gentle,
    // legible bow rather than swinging end letters through a steep tilt -
    // e.g. an uncapped 27-character name like "Apartment Management System"
    // would rotate its end letters ~25° each, which reads as messy rather
    // than as a smooth arc.
    final totalAngle = (totalWidth / radius).clamp(0.0, math.pi * 0.12);

    // Circle center sits well above the visible box; the text is drawn on
    // the underside of that (large, shallow) circle, so at the horizontal
    // center it sits right at the bottom of the box, and its ends curve
    // upward toward the top of the box — the same "valley" shape as the
    // wave header behind it.
    final center = Offset(size.width / 2, size.height - radius);

    double angle = -totalAngle / 2;
    for (final tp in painters) {
      final charAngle = totalAngle == 0 ? 0.0 : (tp.width / totalWidth) * totalAngle;
      final midAngle = angle + charAngle / 2;

      final point = center + Offset(radius * math.sin(midAngle), radius * math.cos(midAngle));

      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(midAngle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();

      angle += charAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _ArcTextPainter oldDelegate) =>
      oldDelegate.text != text || oldDelegate.style != style || oldDelegate.radius != radius;
}

class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 40);
    path.quadraticBezierTo(size.width * 0.5, size.height + 30, size.width, size.height - 40);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Rounded-pill gradient button for primary CTAs (Sign In, Sign Up, Send…),
/// matching the reference's pill-shaped gradient buttons.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final List<Color>? colors;

  const GradientButton({super.key, required this.label, required this.onPressed, this.loading = false, this.colors});

  @override
  Widget build(BuildContext context) {
    final grad = colors ?? [BrandingService.primary, CurvedHeader._lighten(BrandingService.primary)];
    return Opacity(
      opacity: onPressed == null && !loading ? 0.6 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: loading ? null : onPressed,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: grad, begin: Alignment.centerLeft, end: Alignment.centerRight),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: grad.last.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    );
  }
}
