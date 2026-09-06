import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The login hero's signature element: a faint grid of "windows" rising
/// from the bottom of the header, like a building facade at dusk - some
/// lit, some dark, thinning out toward the top like a real skyline receding
/// into the sky. Grounded directly in the product's actual subject matter
/// (this is an apartment/building management app) rather than a generic
/// gradient-and-blob header, while staying quiet enough to sit behind the
/// logo and name without competing with them.
///
/// Deterministic (fixed seed) so the pattern is stable across rebuilds
/// instead of flickering into a new random layout every frame.
class LoginWindowGrid extends StatelessWidget {
  const LoginWindowGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WindowGridPainter(),
      ),
    );
  }
}

class _WindowGridPainter extends CustomPainter {
  static final _rng = math.Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 22.0;
    const gap = 10.0;
    const step = cell + gap;

    final cols = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;
    final windowRect = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, cell, cell), const Radius.circular(3));
    final paint = Paint();

    for (var r = 0; r < rows; r++) {
      // Fades out toward the top of the header, like a skyline receding
      // into the sky - the strongest "lit windows" sit near the bottom.
      final rowFade = 1 - (r / rows) * 0.85;
      for (var c = 0; c < cols; c++) {
        final lit = _rng.nextDouble();
        // Roughly 1 in 3 windows reads as "lit"; the rest stay near-invisible.
        final opacity = (lit > 0.66 ? 0.16 + lit * 0.10 : 0.03 + lit * 0.03) * rowFade;
        paint.color = Colors.white.withOpacity(opacity.clamp(0.0, 0.28));

        canvas.save();
        canvas.translate(c * step, size.height - (r + 1) * step);
        canvas.drawRRect(windowRect, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WindowGridPainter oldDelegate) => false;
}
