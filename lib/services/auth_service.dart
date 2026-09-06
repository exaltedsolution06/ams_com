import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'branding_service.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  static const _userKey = 'user_data';
  static const _viewModeKey = 'view_mode';
  static const _companyAptKey = 'company_selected_apartment_id';
  static const _dismissedAnnouncementsKey = 'dismissed_announcement_ids';

  // In-memory cache for the token, plus de-duplication of concurrent reads.
  //
  // flutter_secure_storage's web backend is not safe under concurrency -
  // several simultaneous .read() calls can stall indefinitely, or throw a
  // stray "Null check operator used on a null value" from inside the plugin
  // itself, instead of each resolving independently. Most screens only ever
  // issue one storage read at a time, so this never showed up - but the
  // Approvals screen mounts 4 tabs at once, each immediately calling
  // ApiService().get(), each calling getToken() - 4 concurrent reads fired
  // in the same frame (plus GoRouter's own isLoggedIn() check on the way
  // in). That's exactly the pattern that triggers it.
  //
  // Caching the value and sharing one in-flight read across callers means
  // only the very first call after app start ever touches storage directly;
  // everything else resolves instantly from memory.
  static String? _cachedToken;
  static Future<String?>? _tokenReadInFlight;

  // Same fix, same reason, for the user JSON blob. Without this, every call
  // to effectiveRole() (e.g. the voice-command mic button) fires a fresh
  // _storage.read(key: _userKey) - and for an apartment_admin, effectiveRole()
  // calls getUser() once for the role AND again inside hasDualRole(), which
  // combined with whatever else on screen is reading storage at the same
  // moment is enough to trigger the exact same web race, surfacing as
  // "Null check operator used on a null value" the instant the mic is tapped.
  static Map<String, dynamic>? _cachedUser;
  static bool _userCacheLoaded = false;
  static Future<Map<String, dynamic>?>? _userReadInFlight;

  /// Profile > "Voice Mic" personal on/off preference - synchronous (like
  /// BrandingService.voiceMicEnabled) so VoiceCommandOverlay's build() can
  /// read it directly without turning into a FutureBuilder. Only reflects
  /// whatever was last loaded into memory via saveUser()/getUser() (login,
  /// /me, or the Profile screen's toggle) - defaults to true (matches the
  /// backend's own default) if nothing's cached yet, e.g. very first frame
  /// before login finishes.
  static bool get wantsVoiceMic => (_cachedUser?['voice_mic_enabled'] as bool?) ?? true;

  /// Bumped only when switching to a sibling account (different apartment,
  /// same person) - see ProfileScreen._switchApartment(). The dashboard
  /// routes key themselves off this so GoRouter is forced to dispose the
  /// old DashboardScreen/AdminDashboardScreen State and build a fresh one
  /// (which reloads its data in initState()). Without it, going back to
  /// '/dashboard' after a switch just pops back to the *same* State object
  /// still sitting in the Navigator stack from the old apartment - same
  /// widget type, same (lack of) key, so Flutter reuses it rather than
  /// rebuilding, and the screen keeps showing the old apartment's data
  /// until a manual pull-to-refresh. Ordinary saveUser() calls (voice mic
  /// toggle, profile edits, etc.) deliberately don't touch this - those
  /// don't need a hard dashboard reload, just AppRefresh.bump()'s cosmetic
  /// rebuild.
  static int apartmentSwitchEpoch = 0;
  static void bumpApartmentSwitch() => apartmentSwitchEpoch++;

  /// The password most recently used to successfully authenticate (initial
  /// login, or a per-apartment retry via chooseAccount()) - kept in memory
  /// ONLY for this app run, never written to secure storage or disk. Lets
  /// ProfileScreen._switchApartment() try a sibling apartment silently with
  /// this same password first (the common case where every linked apartment
  /// shares one), only falling back to its own password-prompt dialog when
  /// that specific apartment turns out to use a different one - see
  /// AuthController::switchApartment() (API). Cleared on logout()below.
  static String? lastPassword;
  static void rememberPassword(String password) => lastPassword = password;

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    _tokenReadInFlight = null;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    _tokenReadInFlight ??= _storage.read(key: _tokenKey).then((v) {
      _cachedToken = v;
      _tokenReadInFlight = null;
      return v;
    });
    return _tokenReadInFlight;
  }

  /// Saves the user object (Map) as JSON so it can be read back later
  /// without re-fetching /me — used for prefill on payment screens etc.
  Future<void> saveUser(Map<String, dynamic> user) async {
    _cachedUser = user;
    _userCacheLoaded = true;
    _userReadInFlight = null;
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  /// Returns the cached user Map, or null if not logged in / not saved.
  Future<Map<String, dynamic>?> getUser() async {
    if (_userCacheLoaded) return _cachedUser;
    _userReadInFlight ??= _storage.read(key: _userKey).then((raw) {
      Map<String, dynamic>? parsed;
      if (raw != null) {
        try {
          parsed = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          parsed = null;
        }
      }
      _cachedUser = parsed;
      _userCacheLoaded = true;
      _userReadInFlight = null;
      return parsed;
    });
    return _userReadInFlight;
  }

  /// True when this user is an Apartment Admin who is ALSO a resident of a
  /// flat (marked as such when their resident record was created/edited).
  /// Only these accounts get the account-type switch — a plain admin with
  /// no flat has nothing to switch to.
  Future<bool> hasDualRole() async {
    final user = await getUser();
    if (user == null) return false;
    return (user['role'] == 'apartment_admin') && (user['flat_id'] != null);
  }

  /// Which experience a dual-role user wants to see right now: 'admin' or
  /// 'resident'. Defaults to 'admin' (their actual login role) until they
  /// explicitly switch. Meaningless for everyone else.
  // Same reasoning again: effectiveRole() calls this directly for any
  // dual-role apartment_admin, so it's still on the exact hot path the mic
  // button hits every tap. Left as a raw _storage.read() it was the one
  // remaining uncached call in that chain, and still enough on its own to
  // race with whatever else is reading storage at that moment. Cached and
  // de-duped the same way as getToken()/getUser() above.
  static String? _cachedViewMode;
  static Future<String>? _viewModeReadInFlight;

  Future<String> getViewMode() async {
    if (_cachedViewMode != null) return _cachedViewMode!;
    _viewModeReadInFlight ??= _storage.read(key: _viewModeKey).then((v) {
      final mode = v ?? 'admin';
      _cachedViewMode = mode;
      _viewModeReadInFlight = null;
      return mode;
    });
    return _viewModeReadInFlight!;
  }

  Future<void> setViewMode(String mode) async {
    _cachedViewMode = mode;
    _viewModeReadInFlight = null;
    await _storage.write(key: _viewModeKey, value: mode);
  }

  /// The role to actually route/build UI for, accounting for a dual-role
  /// user's current view-mode switch. Everyone else just gets their role.
  Future<String> effectiveRole() async {
    final user = await getUser();
    final role = user?['role'] as String? ?? 'resident';
    if (role == 'apartment_admin' && await hasDualRole() && await getViewMode() == 'resident') {
      return 'resident';
    }
    return role;
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// A Company Admin manages many apartments (Apartment::company_id), unlike
  /// every other admin role which has exactly one. When they tap into a
  /// specific apartment from the Company Dashboard, we remember that choice
  /// here - ApiService then attaches it as ?apartment_id=... to every
  /// /admin/* call, which is exactly the query param the existing
  /// apartment_admin endpoints already accept (see AdminApiController::apartment()).
  //
  // This is the one that actually explains the mic crash for a Company Admin
  // viewing one of their apartments: ApiService._withApartmentContext() calls
  // this on literally every /admin/*, /menu-settings/*, /branding, and
  // /announcements request - and that dashboard fires several of those at
  // once on load. Left as a raw _storage.read() with no caching, every one
  // of those concurrent calls hit storage at the same moment, which is
  // exactly the flutter_secure_storage-on-web race that throws "Null check
  // operator used on a null value". Cached and de-duped the same way as the
  // others above.
  static int? _cachedApartmentId;
  static bool _apartmentIdCacheLoaded = false;
  static Future<int?>? _apartmentIdReadInFlight;

  Future<int?> getSelectedApartmentId() async {
    if (_apartmentIdCacheLoaded) return _cachedApartmentId;
    _apartmentIdReadInFlight ??= _storage.read(key: _companyAptKey).then((v) {
      final id = v == null ? null : int.tryParse(v);
      _cachedApartmentId = id;
      _apartmentIdCacheLoaded = true;
      _apartmentIdReadInFlight = null;
      return id;
    });
    return _apartmentIdReadInFlight;
  }

  Future<void> setSelectedApartmentId(int id) async {
    _cachedApartmentId = id;
    _apartmentIdCacheLoaded = true;
    _apartmentIdReadInFlight = null;
    await _storage.write(key: _companyAptKey, value: id.toString());
  }

  Future<void> clearSelectedApartmentId() async {
    _cachedApartmentId = null;
    _apartmentIdCacheLoaded = true;
    _apartmentIdReadInFlight = null;
    await _storage.delete(key: _companyAptKey);
  }

  /// IDs of announcements the user has closed this "session" (i.e. since
  /// their last login) — the mobile equivalent of the web's PHP session
  /// flag. Persisted in the same secure storage as the JWT token, so it
  /// survives an app restart just like the web session survives a browser
  /// restart, but logout() below wipes it via _storage.deleteAll(), same
  /// as the web clears it via session()->invalidate() on logout.
  // Last remaining raw, non-deduped _storage.read() in this file - not on
  // the mic button's own call path, but any concurrent read is a potential
  // trigger for the same flutter_secure_storage-on-web race described above
  // (whichever calls happen to overlap it). Cached/de-duped the same way.
  static List<int>? _cachedDismissedIds;
  static Future<List<int>>? _dismissedIdsReadInFlight;

  Future<List<int>> getDismissedAnnouncementIds() async {
    if (_cachedDismissedIds != null) return _cachedDismissedIds!;
    _dismissedIdsReadInFlight ??= _storage.read(key: _dismissedAnnouncementsKey).then((raw) {
      List<int> ids = [];
      if (raw != null) {
        try {
          ids = (jsonDecode(raw) as List).map((e) => e as int).toList();
        } catch (_) {
          ids = [];
        }
      }
      _cachedDismissedIds = ids;
      _dismissedIdsReadInFlight = null;
      return ids;
    });
    return _dismissedIdsReadInFlight!;
  }

  Future<void> dismissAnnouncement(int id) async {
    final ids = await getDismissedAnnouncementIds();
    if (!ids.contains(id)) {
      ids.add(id);
      _cachedDismissedIds = ids;
      await _storage.write(key: _dismissedAnnouncementsKey, value: jsonEncode(ids));
    }
  }

  Future<void> logout() async {
    _cachedToken = null;
    _tokenReadInFlight = null;
    _cachedUser = null;
    _userCacheLoaded = false;
    _userReadInFlight = null;
    _cachedViewMode = null;
    _viewModeReadInFlight = null;
    _cachedApartmentId = null;
    _apartmentIdCacheLoaded = false;
    _apartmentIdReadInFlight = null;
    _cachedDismissedIds = null;
    _dismissedIdsReadInFlight = null;
    lastPassword = null;
    await _storage.deleteAll();
    // Reset to default branding - otherwise the next person to open the
    // login screen on this device (or a resident of a different apartment)
    // would briefly see the previous apartment's logo/colors.
    await BrandingService.reset();
  }
}
