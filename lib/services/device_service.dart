import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Identifies THIS app installation as its own trusted environment, for the
/// Account + Platform + Device + Login Method verification model (see
/// DeviceVerificationService / the user_device_verifications table on the
/// backend, and the identical DeviceService in the resident/admin app).
///
/// This is the Company app's copy of that same identifier scheme. It
/// matters just as much here: a Company Admin signed in on the website in
/// a browser and signed in on THIS app on the same phone are two separate
/// trusted environments, verified independently.
///
/// ── Storage choice ───────────────────────────────────────────────────────
/// SharedPreferences, deliberately NOT secure storage. AuthService's
/// logout() calls _storage.deleteAll(), which would wipe the id along with
/// the token - and then every logout would read as a brand-new device and
/// re-ask for OTP verification. The id identifies the INSTALL, not the
/// session, so it has to outlive logout.
///
/// It does NOT outlive an uninstall/reinstall or a "clear app data" - no
/// reliable way to survive those, and failing toward "ask again" is the
/// safe direction.
///
/// ── What this is NOT ─────────────────────────────────────────────────────
/// Not derived from the model name, IMEI, advertising id, or anything else
/// about the physical handset (that would collapse the website and this
/// app on one phone into a single record, exactly what the model exists to
/// avoid). Just a random UUID minted once. [deviceName] is a physical
/// description, but purely a display label for the Linked Devices list -
/// never matched on.
class DeviceService {
  static const _deviceIdKey = 'ams_company_device_id';

  static String? _cachedId;
  static String? _cachedName;

  /// Call once during app startup (see main()), before the first API call,
  /// so [deviceId] is available synchronously to ApiService afterwards.
  static Future<void> init() async {
    await deviceId();
    _cachedName = _buildDeviceName();
  }

  /// The stable per-install identifier, minting and persisting one on first
  /// call. Safe to call repeatedly - after the first it's an in-memory read.
  static Future<String> deviceId() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);

      if (id == null || id.length < 20) {
        id = _generateUuidV4();
        await prefs.setString(_deviceIdKey, id);
      }

      _cachedId = id;
      return id;
    } catch (_) {
      // Storage unavailable for some reason - fall back to a per-session
      // id rather than throwing. Worst case the person is asked to verify
      // once more than strictly necessary, which is the safe failure.
      return _cachedId ??= _generateUuidV4();
    }
  }

  /// Synchronous accessor for whatever [init]/[deviceId] already resolved.
  /// Null only before init() has completed.
  static String? get cachedDeviceId => _cachedId;

  /// Display-only label for the Linked Devices list ("Android app",
  /// "iPhone app"). Never used for matching - see the class doc comment.
  static String get deviceName => _cachedName ??= _buildDeviceName();

  /// Coarse type for the Linked Devices list's icon.
  static String get deviceType {
    if (kIsWeb) return 'desktop';
    try {
      return (Platform.isAndroid || Platform.isIOS) ? 'mobile' : 'desktop';
    } catch (_) {
      return 'mobile';
    }
  }

  static String _buildDeviceName() {
    if (kIsWeb) return 'Company App (Web build)';
    try {
      if (Platform.isAndroid) return 'Android app';
      if (Platform.isIOS)     return 'iPhone / iPad app';
      if (Platform.isWindows) return 'Windows app';
      if (Platform.isMacOS)   return 'macOS app';
      if (Platform.isLinux)   return 'Linux app';
    } catch (_) {
      // Platform is unavailable on some targets - fall through.
    }
    return 'Company App';
  }

  /// Small self-contained RFC-4122 v4 generator, so this doesn't pull in a
  /// uuid package just for one string. Random.secure() where available,
  /// falling back to Random() on platforms that don't provide it.
  static String _generateUuidV4() {
    Random rnd;
    try {
      rnd = Random.secure();
    } catch (_) {
      rnd = Random();
    }

    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
