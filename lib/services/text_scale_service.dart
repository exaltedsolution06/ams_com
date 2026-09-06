import 'package:shared_preferences/shared_preferences.dart';
import 'app_refresh.dart';

/// TextScaleService
///
/// Lets the user increase/decrease the app's overall font size from the
/// Profile screen. The chosen scale is applied app-wide via a MediaQuery
/// override in main.dart (see ApartmentManagementApp's builder), so every
/// screen picks it up automatically — no per-screen changes needed.
///
/// Usage:
///   TextScaleService.scale                 → current multiplier (e.g. 1.15)
///   TextScaleService.label                 → 'Normal' / 'Large' / ...
///   await TextScaleService.setScale(1.15)   → persist + refresh whole app
class TextScaleService {
  static const _prefsKey = 'text_scale_factor';

  // Fixed set of steps, similar to iOS/Android system text-size pickers.
  static const Map<String, double> steps = {
    'Small':        0.85,
    'Normal':       1.0,
    'Large':        1.15,
    'Extra Large':  1.30,
    'Huge':         1.45,
  };

  static double _scale = 1.0;

  static double get scale => _scale;

  static String get label {
    for (final entry in steps.entries) {
      if ((entry.value - _scale).abs() < 0.001) return entry.key;
    }
    return 'Normal';
  }

  /// Load the saved scale on app start (call before runApp, alongside the
  /// other *.loadSaved()/*.load() calls in main.dart).
  static Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _scale = prefs.getDouble(_prefsKey) ?? 1.0;
  }

  /// Set a new scale, persist it, and force the whole app to rebuild so
  /// every currently-mounted screen picks up the new size immediately.
  static Future<void> setScale(double value) async {
    _scale = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, value);
    AppRefresh.bump();
  }
}
