import 'dart:math';
import 'package:flutter/material.dart';

/// A pool of 50 visually distinct, saturated shades used to color things
/// like a dashboard's Quick Actions tiles - so every icon gets its own
/// color instead of a handful of colors repeating every 8-9 tiles once a
/// dashboard has more Quick Action items than the old short palette had.
///
/// Chosen to all read well with white icons/text on top (nothing too pale
/// or too close to yellow), while still spanning a wide range of hues and
/// a couple of shade weights per hue for extra variety.
class TileColorPalette {
  TileColorPalette._();

  static const List<Color> shades = [
    Color(0xFFE53935), Color(0xFFD81B60), Color(0xFF8E24AA), Color(0xFF5E35B1),
    Color(0xFF3949AB), Color(0xFF1E88E5), Color(0xFF039BE5), Color(0xFF00ACC1),
    Color(0xFF00897B), Color(0xFF43A047), Color(0xFF7CB342), Color(0xFFF4511E),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFEF5350), Color(0xFFEC407A),
    Color(0xFFAB47BC), Color(0xFF7E57C2), Color(0xFF5C6BC0), Color(0xFF42A5F5),
    Color(0xFF29B6F6), Color(0xFF26C6DA), Color(0xFF26A69A), Color(0xFF66BB6A),
    Color(0xFF9CCC65), Color(0xFFFF7043), Color(0xFF8D6E63), Color(0xFF78909C),
    Color(0xFFC62828), Color(0xFFAD1457), Color(0xFF6A1B9A), Color(0xFF4527A0),
    Color(0xFF283593), Color(0xFF1565C0), Color(0xFF0277BD), Color(0xFF00838F),
    Color(0xFF00695C), Color(0xFF2E7D32), Color(0xFF558B2F), Color(0xFFD84315),
    Color(0xFF4E342E), Color(0xFF37474F), Color(0xFFB71C1C), Color(0xFF880E4F),
    Color(0xFF4A148C), Color(0xFF311B92), Color(0xFF1A237E), Color(0xFF0D47A1),
    Color(0xFF01579B), Color(0xFFBF360C),
  ];

  /// Returns [count] colors from [shades], guaranteed unique as long as
  /// count <= 50 (any realistic Quick Actions grid). [seed] fixes the
  /// shuffle order so the same dashboard shows the same colors on every
  /// rebuild instead of re-randomizing on each setState/scroll - pass
  /// something stable per screen (e.g. the screen name's hashCode) so
  /// different dashboards can still land on different-looking orders.
  static List<Color> forCount(int count, {int seed = 0}) {
    final pool = List<Color>.from(shades)..shuffle(Random(seed));
    if (count <= pool.length) return pool.take(count).toList();

    // Extremely unlikely (>50 quick actions), but don't crash - cycle
    // through the shuffled pool again rather than repeating in original
    // palette order.
    return List<Color>.generate(count, (i) => pool[i % pool.length]);
  }

  /// Same as [forCount] but returned as a lookup by index, for call sites
  /// that build tiles with `_palette[i]` instead of iterating a list.
  static Color at(int index, int count, {int seed = 0}) =>
      forCount(count, seed: seed)[index % count.clamp(1, count)];
}
