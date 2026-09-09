import 'package:flutter/material.dart';

/// Full-page texture for the splash screen: a uniform grid of soft rounded
/// squares over the brand gradient, matching the reference splash design
/// (blue background, evenly spaced square tiles, no fading). Deliberately
/// kept separate from LoginWindowGrid (login_hero_painter.dart), which
/// fades toward the top and is sized for a short hero strip rather than
/// a full page — reusing it here would change the login header's look too.
class SplashWindowGrid extends StatelessWidget {
  const SplashWindowGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SplashGridPainter(),
      ),
    );
  }
}

class _SplashGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 46.0;
    const gap = 18.0;
    const step = cell + gap;

    final cols = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;
    final tileRect = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, cell, cell), const Radius.circular(10));
    final paint = Paint()..color = Colors.white.withOpacity(0.08);

    // Centered offset so the grid reads as intentionally tiled rather than
    // clipped/cut off at the top-left edge of the screen.
    final offsetX = (size.width - (cols - 1) * step - cell) / 2;
    final offsetY = (size.height - (rows - 1) * step - cell) / 2;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.save();
        canvas.translate(offsetX + c * step, offsetY + r * step);
        canvas.drawRRect(tileRect, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplashGridPainter oldDelegate) => false;
}
