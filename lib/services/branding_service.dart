import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_refresh.dart';
import 'auth_service.dart';

class _BrandingData {
  final String appName, poweredBy, poweredByUrl;
  final String? appLogoUrl, fontFamily, language, currencyCode, currencySymbol, appTagline;
  final bool curvedAppName;
  // Whether the current apartment uses Tower → Floor structure. Defaults to
  // true so nothing changes for apartments that already use towers, and for
  // the brief window before /branding has loaded after login.
  final bool hasTowers;
  // Apartment > Branding > "Assign Menu": modules the Super Admin switched
  // fully OFF for this apartment (e.g. no Parking, no Visitors, no Security
  // Guard). Used by AppDrawer/VoiceCommandCatalog (via ModuleGate) to hide
  // the matching menu entries client-side - the real gatekeeper is still the
  // `apt_module:<key>` middleware on the backend, this is just so the UI
  // doesn't offer something the tap would just get a 403 for.
  final Set<String> disabledModules;
  // Community Meeting (video conferencing) - opt-in per apartment, set by
  // Super Admin/Company Admin (Admin > Community Meeting Settings). Unlike
  // disabledModules (on unless switched off), this is off unless explicitly
  // granted - see ApartmentSetting::communityMeetingEnabled() server-side.
  final bool communityMeetingEnabled;
  final String communityMeetingProvider; // 'jitsi' (Default/Free) or 'zego' (Premium, Phase 2)
  // Apartment > Edit > "Show Voice Mic Icon in App" - on by default (fail
  // open server-side too, see ApartmentSetting::voiceMicEnabled()). When
  // false, VoiceCommandOverlay hides the floating mic entirely and the 3
  // dashboard screens' AppBottomNav drops back to its default, symmetric
  // leftInset instead of narrowing to leave room for the mic.
  final bool voiceMicEnabled;
  // Whether this apartment currently accepts UPI payments from residents -
  // both the Super Admin's Assign Menu 'upi' switch AND the Apartment
  // Admin's own UPI ID/payee/Status are on (see
  // ApartmentSetting::upiEnabled() server-side). Off by default/fail-safe:
  // an unconfigured or not-yet-loaded apartment shouldn't offer UPI.
  final bool upiEnabled;
  // Same fail-safe pattern as upiEnabled above, for Bank Transfer and the
  // Cashfree Easy Split "Pay Online" popup (bill / one-time-charge / wallet
  // payments) - mirrors ApartmentSetting::bankTransferEnabled()/
  // cashfreeSplitEnabled() server-side. cashfreeOnlineEnabled specifically
  // requires the apartment to have completed Easy Split vendor onboarding
  // (Admin > Bank Transfer Settings > Enable Automatic Online Collection),
  // not just a Cashfree gateway existing somewhere.
  final bool bankTransferEnabled;
  // The actual account to transfer to (holder/number/IFSC/bank name), from
  // Apartment::bankTransferDetails() server-side - same data the website
  // shows residents in its bank-transfer boxes. Null when bank transfer
  // isn't enabled or the Apartment Admin hasn't saved details yet.
  final Map<String, dynamic>? bankTransferDetails;
  final bool cashfreeOnlineEnabled;
  // Razorpay's counterpart to cashfreeOnlineEnabled above - no per-
  // apartment Easy Split vendor onboarding involved, see
  // ApartmentSetting::razorpayOnlineEnabled() server-side. Money collected
  // this way is settled to the apartment separately by Super Admin rather
  // than auto-split at payment time.
  final bool razorpayOnlineEnabled;
  // Admin/App > Settings > Date Format - a per-apartment preference (not
  // per-device like TextScaleService's font size), since this is really
  // "how does this apartment/country read dates", the same category as
  // currencyCode/currencySymbol above. Stored in `intl` DateFormat token
  // syntax (see ApartmentSetting::DATE_FORMATS server-side) so `dateFormat`
  // below can hand it straight to DateFormat(...) with no translation.
  final String dateFormat;
  // token -> human label (e.g. 'dd/MM/yyyy' -> 'DD/MM/YYYY (e.g.
  // 01/08/2027)'), for populating the Settings tab's dropdown without the
  // app needing its own hardcoded copy of the option list.
  final Map<String, String> dateFormatOptions;
  final Color primary, accent, secondary, sidebar, appBanner, cardBg, textPrimary, success, warning, danger;

  const _BrandingData({
    required this.appName,
    required this.primary,
    required this.accent,
    required this.secondary,
    required this.sidebar,
    required this.appBanner,
    required this.cardBg,
    required this.textPrimary,
    required this.success,
    required this.warning,
    required this.danger,
    this.appLogoUrl,
    this.fontFamily,
    this.language,
    this.currencyCode,
    this.currencySymbol,
    this.appTagline,
    this.curvedAppName = true,
    this.hasTowers = true,
    this.disabledModules = const {},
    this.communityMeetingEnabled = false,
    this.communityMeetingProvider = 'jitsi',
    this.voiceMicEnabled = true,
    this.upiEnabled = false,
    this.bankTransferEnabled = false,
    this.bankTransferDetails,
    this.cashfreeOnlineEnabled = false,
    this.razorpayOnlineEnabled = false,
    this.dateFormat = 'dd MMM yyyy',
    this.dateFormatOptions = const {},
    this.poweredBy = 'Powered by',
    this.poweredByUrl = 'https://exaltedsolution.com',
  });

  static _BrandingData get defaults => _BrandingData(
    appName:     'Apartment Management System',
    primary:     const Color(0xFF2563EB),
    accent:      const Color(0xFFE8A010),
    secondary:   const Color(0xFF1A3C5E),
    sidebar:     const Color(0xFF2563EB),
    appBanner:   const Color(0xFF2563EB),
    // Subtly off-white by default - just enough to separate a card from
    // the page behind it now that the page itself is pure white (see
    // scaffoldBackgroundColor in main.dart). Still fully overridable per
    // apartment via Branding > card_bg_color.
    cardBg:      const Color(0xFFF7F8FA),
    textPrimary: const Color(0xFF1A1A1A),
    success:     const Color(0xFF28A745),
    warning:     const Color(0xFFFFC107),
    danger:      const Color(0xFFDC3545),
    language:    'en',
    currencyCode:   'INR',
    currencySymbol: '₹',
    fontFamily:  'Poppins',
    curvedAppName: true,
    hasTowers: true,
    disabledModules: const {},
    dateFormat: 'dd MMM yyyy',
  );

  static Set<String> _modules(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toSet() : const {};

  static Map<String, String> _dateFormatOptions(dynamic v) =>
      v is Map ? v.map((k, val) => MapEntry(k.toString(), val.toString())) : const {};

  static _BrandingData fromMap(Map<String, dynamic> m) => _BrandingData(
    appName:         m['app_name']    as String? ?? 'AMS',
    appLogoUrl:      m['app_logo_url'] as String?,
    appTagline:      m['app_tagline']  as String?,
    curvedAppName:   m['curved_app_name'] as bool? ?? true,
    hasTowers:       m['has_towers'] as bool? ?? true,
    disabledModules: _modules(m['disabled_modules']),
    communityMeetingEnabled:  (m['community_meeting'] as Map?)?['enabled'] as bool? ?? false,
    communityMeetingProvider: (m['community_meeting'] as Map?)?['provider'] as String? ?? 'jitsi',
    voiceMicEnabled: m['voice_mic_enabled'] as bool? ?? true,
    upiEnabled: m['upi_enabled'] as bool? ?? false,
    bankTransferEnabled: m['bank_transfer_enabled'] as bool? ?? false,
    bankTransferDetails: (m['bank_transfer_details'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)),
    cashfreeOnlineEnabled: m['cashfree_online_enabled'] as bool? ?? false,
    razorpayOnlineEnabled: m['razorpay_online_enabled'] as bool? ?? false,
    dateFormat:        m['date_format'] as String? ?? 'dd MMM yyyy',
    dateFormatOptions: _dateFormatOptions(m['date_format_options']),
    primary:         _hex(m['primary_color'],      const Color(0xFF2563EB)),
    accent:          _hex(m['accent_color'],        const Color(0xFFE8A010)),
    secondary:       _hex(m['secondary_color'],     const Color(0xFF1A3C5E)),
    sidebar:         _hex(m['sidebar_color'],       const Color(0xFF2563EB)),
    appBanner:       _hex(m['app_banner_color'],    const Color(0xFF2563EB)),
    cardBg:          _hex(m['card_bg_color'],       const Color(0xFFF7F8FA)),
    textPrimary:     _hex(m['text_primary_color'],  const Color(0xFF1A1A1A)),
    success:         _hex(m['success_color'],        const Color(0xFF28A745)),
    warning:         _hex(m['warning_color'],        const Color(0xFFFFC107)),
    danger:          _hex(m['danger_color'],         const Color(0xFFDC3545)),
    fontFamily:      m['font_family']    as String? ?? 'Poppins',
    language:        m['language']        as String? ?? 'en',
    currencyCode:    m['currency_code']   as String? ?? 'INR',
    currencySymbol:  m['currency_symbol'] as String? ?? '₹',
    poweredBy:       m['powered_by']      as String? ?? 'Powered by',
    poweredByUrl:    m['powered_by_url']  as String? ?? 'https://exaltedsolution.com',
  );

  /// Merge just the pre-login identity fields (name/logo/tagline/curve) from
  /// the public /app-info endpoint onto the current data, keeping whatever
  /// colors are already in effect (defaults, until a real apartment logs in).
  _BrandingData withPublicInfo(Map<String, dynamic> m) => _BrandingData(
    appName:       m['app_name'] as String? ?? appName,
    appLogoUrl:    m['app_logo_url'] as String? ?? appLogoUrl,
    appTagline:    m['app_tagline'] as String? ?? appTagline,
    curvedAppName: m['curved_app_name'] as bool? ?? curvedAppName,
    primary: primary, accent: accent, secondary: secondary, sidebar: sidebar,
    appBanner: appBanner, cardBg: cardBg, textPrimary: textPrimary,
    success: success, warning: warning, danger: danger,
    fontFamily: fontFamily, language: language,
    currencyCode: currencyCode, currencySymbol: currencySymbol,
    hasTowers: hasTowers,
    disabledModules: disabledModules,
    communityMeetingEnabled: communityMeetingEnabled,
    communityMeetingProvider: communityMeetingProvider,
    voiceMicEnabled: voiceMicEnabled,
    upiEnabled: upiEnabled,
    bankTransferEnabled: bankTransferEnabled,
    bankTransferDetails: bankTransferDetails,
    cashfreeOnlineEnabled: cashfreeOnlineEnabled,
    razorpayOnlineEnabled: razorpayOnlineEnabled,
    dateFormat: dateFormat,
    dateFormatOptions: dateFormatOptions,
    poweredBy: m['powered_by'] as String? ?? poweredBy,
    poweredByUrl: m['powered_by_url'] as String? ?? poweredByUrl,
  );

  static Color _hex(dynamic v, Color fallback) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    if (!s.startsWith('#') || s.length != 7) return fallback;
    try {
      return Color(int.parse('FF${s.substring(1)}', radix: 16));
    } catch (_) { return fallback; }
  }
}

class BrandingService {
  static _BrandingData _data = _BrandingData.defaults;

  static _BrandingData get current   => _data;
  static Color get primary    => _data.primary;
  static Color get accent     => _data.accent;
  static Color get secondary  => _data.secondary;
  static Color get sidebar    => _data.sidebar;
  static Color get appBanner  => _data.appBanner;
  static Color get cardBg     => _data.cardBg;
  static Color get textPrimary=> _data.textPrimary;
  static Color get success    => _data.success;
  static Color get warning    => _data.warning;
  static Color get danger     => _data.danger;
  static String? get appLogoUrl   => _data.appLogoUrl;
  static String  get appName      => _data.appName;
  static String? get appTagline   => _data.appTagline;
  static bool    get curvedAppName=> _data.curvedAppName;
  static String  get currencySymbol => _data.currencySymbol ?? '₹';
  static String  get language       => _data.language ?? 'en';
  static bool    get hasTowers      => _data.hasTowers;
  static Set<String> get disabledModules => _data.disabledModules;
  static bool   get communityMeetingEnabled  => _data.communityMeetingEnabled;
  static String get communityMeetingProvider => _data.communityMeetingProvider;
  static bool   get voiceMicEnabled          => _data.voiceMicEnabled;
  static bool   get upiEnabled               => _data.upiEnabled;
  static bool   get bankTransferEnabled      => _data.bankTransferEnabled;
  static Map<String, dynamic>? get bankTransferDetails => _data.bankTransferDetails;
  static bool   get cashfreeOnlineEnabled    => _data.cashfreeOnlineEnabled;
  static bool   get razorpayOnlineEnabled    => _data.razorpayOnlineEnabled;
  static String get dateFormat               => _data.dateFormat;

  // Mirrors ApartmentSetting::DATE_FORMATS server-side. Used only as a
  // fallback for the one request cycle where a cached branding_cache from
  // before this feature existed hasn't been refreshed yet - the moment
  // BrandingService.load() succeeds even once, the real server-provided
  // list below takes over.
  static const Map<String, String> _fallbackDateFormatOptions = {
    'dd/MM/yyyy':   'DD/MM/YYYY (e.g. 01/08/2027)',
    'MM/dd/yyyy':   'MM/DD/YYYY (e.g. 08/01/2027)',
    'yyyy-MM-dd':   'YYYY-MM-DD (e.g. 2027-08-01)',
    'dd.MM.yyyy':   'DD.MM.YYYY (e.g. 01.08.2027)',
    'yyyy/MM/dd':   'YYYY/MM/DD (e.g. 2027/08/01)',
    'dd MMM yyyy':  'DD MMM YYYY (e.g. 01 Aug 2027)',
    'MMM dd, yyyy': 'MMM DD, YYYY (e.g. Aug 01, 2027)',
  };

  static Map<String, String> get dateFormatOptions =>
      _data.dateFormatOptions.isEmpty ? _fallbackDateFormatOptions : _data.dateFormatOptions;

  /// Formats [d] using this apartment's chosen Date Format (Admin/App >
  /// Settings > Date Format). Use this instead of hand-rolling a
  /// DateFormat(...) call so every screen picks up the apartment's
  /// preference automatically instead of drifting into its own hardcoded
  /// style. Returns '' for a null date.
  static String formatDate(DateTime? d) => d == null ? '' : DateFormat(_data.dateFormat).format(d);

  /// Same as [formatDate], but for the raw ISO ('yyyy-MM-dd' or full
  /// ISO-8601) strings the API returns - most date fields come back this
  /// way rather than as a DateTime already. Returns the raw string
  /// unchanged if it isn't parseable, so a bad value degrades to "shows
  /// something" rather than a blank field.
  static String formatDateString(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    return d == null ? raw : formatDate(d);
  }

  /// Same as [formatDate], but also includes the time (e.g. "01 Aug 2027,
  /// 2:30 PM") - for screens showing a timestamp (transactions, bookings,
  /// notifications, ledgers) rather than a bare date. The time portion
  /// (h:mm a) stays fixed regardless of Date Format - that setting is
  /// about day/month/year order, not clock style.
  static String formatDateTime(DateTime? d) =>
      d == null ? '' : DateFormat('${_data.dateFormat}, h:mm a').format(d);

  static String formatDateTimeString(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    return d == null ? raw : formatDateTime(d);
  }

  // Same day/month order as dateFormat, with the year stripped out - for
  // "recent" displays (this year's notifications, a meeting scheduled a
  // few days out) that intentionally don't show a year. Built by removing
  // the year token(s) and cleaning up whatever separator is left dangling
  // next to them, e.g. 'dd/MM/yyyy' -> 'dd/MM', 'MMM dd, yyyy' -> 'MMM dd'.
  static String get _dateFormatNoYear {
    var f = _data.dateFormat.replaceAll('yyyy', '').replaceAll('yy', '');
    f = f.replaceAll(RegExp(r'^[\s/,\-.]+'), '').replaceAll(RegExp(r'[\s/,\-.]+$'), '');
    return f.isEmpty ? 'd MMM' : f;
  }

  static String formatDateShort(DateTime? d) =>
      d == null ? '' : DateFormat(_dateFormatNoYear).format(d);

  static String formatDateTimeShort(DateTime? d) =>
      d == null ? '' : DateFormat('$_dateFormatNoYear, h:mm a').format(d);

  static String formatDateTimeShortString(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    return d == null ? raw : formatDateTimeShort(d);
  }

  /// True when the Super Admin switched [module] fully OFF for this
  /// apartment (Apartment > Branding > "Assign Menu"). See ModuleGate for
  /// mapping a Drawer tile / voice command key to its module.
  static bool isModuleOff(String module) => _data.disabledModules.contains(module);

  /// Saves a new Date Format choice (Admin/App > Settings > Date Format).
  /// The /branding endpoint is a single combined "save everything" form
  /// (app name, colors, currency, date format...), so this refills every
  /// other required field from what's already loaded rather than needing
  /// its own dedicated endpoint - apartment_admin only, same as the rest
  /// of /branding's update().
  static Future<void> updateDateFormat(String format) async {
    final res = await ApiService().post('/branding', {
      'app_name':           _data.appName,
      'primary_color':      _colorToHex(_data.primary),
      'accent_color':       _colorToHex(_data.accent),
      'secondary_color':    _colorToHex(_data.secondary),
      'sidebar_color':      _colorToHex(_data.sidebar),
      'app_banner_color':   _colorToHex(_data.appBanner),
      'card_bg_color':      _colorToHex(_data.cardBg),
      'text_primary_color': _colorToHex(_data.textPrimary),
      'success_color':      _colorToHex(_data.success),
      'warning_color':      _colorToHex(_data.warning),
      'danger_color':       _colorToHex(_data.danger),
      'currency_code':      _data.currencyCode ?? 'INR',
      'currency_symbol':    _data.currencySymbol ?? '₹',
      'date_format':        format,
    });
    final data = res['data'] as Map<String, dynamic>?;
    if (data != null) {
      _data = _BrandingData.fromMap(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('branding_cache', jsonEncode(data));
      AppRefresh.bump();
    }
  }

  static String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  /// Load branding from API and cache to SharedPreferences.
  /// Before login there's no apartment context yet, so /branding (which
  /// needs an authenticated user's apartment_id) would just fail silently —
  /// use the public /app-info endpoint for the pre-login identity instead.
  static Future<void> load() async {
    // First try loading from cache (for offline use)
    await _loadFromCache();

    final loggedIn = await _hasToken();
    if (!loggedIn) {
      await loadPublicDefaults();
      return;
    }

    // Then refresh from API in background
    try {
      final res  = await ApiService().get('/branding');
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null) {
        _data = _BrandingData.fromMap(data);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('branding_cache', jsonEncode(data));
        AppRefresh.bump();
      }
    } catch (_) {
      // API failed — keep cached or default values
    }
  }

  /// Pre-login only: fetches the platform-wide default app name/logo/tagline
  /// (Admin > Settings > General) shown on the login screen before anyone
  /// has signed in. Safe to call repeatedly (e.g. every time the login
  /// screen mounts) - it's a light, unauthenticated GET.
  static Future<void> loadPublicDefaults() async {
    try {
      final res  = await ApiService().get('/app-info');
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null) {
        _data = _data.withPublicInfo(data);
        AppRefresh.bump();
      }
    } catch (_) {
      // Offline or API not reachable yet — keep cached/default values.
    }
  }

  static Future<bool> _hasToken() async {
    // Was its own raw `FlutterSecureStorage().read(key: 'jwt_token')` here -
    // a second, uncached read of the same key AuthService already
    // caches/de-dupes. Firing both concurrently (e.g. BrandingService.load()
    // and AuthService().getToken() both mid-flight when the dashboard loads)
    // is exactly the flutter_secure_storage-on-web race that throws "Null
    // check operator used on a null value". Routing through AuthService's
    // shared cache instead of a separate instance closes that gap.
    final token = await AuthService().getToken();
    return token != null && token.isNotEmpty;
  }

  /// Apply branding received inline in login response (no extra API call)
  static Future<void> applyFromLogin(Map<String, dynamic> branding) async {
    _data = _BrandingData.fromMap(branding);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('branding_cache', jsonEncode(branding));
    AppRefresh.bump();
  }

  /// Reset to the default (unbranded) look - used on logout so the login
  /// screen always shows the neutral default logo/name, never a previous
  /// apartment's uploaded branding.
  static Future<void> reset() async {
    _data = _BrandingData.defaults;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('branding_cache');
    AppRefresh.bump();
  }

  static Future<void> _loadFromCache() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cached = prefs.getString('branding_cache');
      if (cached != null) {
        _data = _BrandingData.fromMap(jsonDecode(cached) as Map<String, dynamic>);
      }
    } catch (_) {}
  }
}
