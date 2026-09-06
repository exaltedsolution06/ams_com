import 'module_gate.dart';
import 'branding_service.dart';

/// Catalog of every screen that can be opened by voice, per role.
///
/// This intentionally mirrors `app/Services/MenuRegistry.php` on the backend
/// (same keys, same routes) - see that file's docblock. It's kept as a
/// separate Dart-side list rather than fetched from `/menu-settings/{role}`
/// because voice needs to work even for items the Super Admin didn't put on
/// this apartment's Quick Action grid (a resident should still be able to
/// say "open profile" even if Profile isn't one of their configured tiles),
/// and because it needs to include the "Dashboard/Home" item, which
/// MenuConfigService deliberately excludes from the selectable catalog.
///
/// `labelKey` is a `LanguageService` translation key - NOT the display text
/// itself - so the label used for fuzzy-matching heard speech is always in
/// the app's current language automatically.
class VoiceNavCommand {
  final String key;
  final String labelKey;
  final String route;
  const VoiceNavCommand({required this.key, required this.labelKey, required this.route});
}

class VoiceCommandCatalog {
  static const List<VoiceNavCommand> _resident = [
    VoiceNavCommand(key: 'home', labelKey: 'dashboard', route: '/dashboard'),
    VoiceNavCommand(key: 'billing', labelKey: 'billing', route: '/billing'),
    VoiceNavCommand(key: 'wallet', labelKey: 'wallet', route: '/wallet'),
    VoiceNavCommand(key: 'complaints', labelKey: 'complaints', route: '/complaints'),
    VoiceNavCommand(key: 'complaint_raise', labelKey: 'submit_complaint', route: '/complaints/raise'),
    VoiceNavCommand(key: 'visitors', labelKey: 'visitors', route: '/visitors'),
    VoiceNavCommand(key: 'notices', labelKey: 'notices', route: '/notices'),
    VoiceNavCommand(key: 'facilities', labelKey: 'facilities', route: '/facilities'),
    VoiceNavCommand(key: 'my_bookings', labelKey: 'bookings', route: '/my-bookings'),
    VoiceNavCommand(key: 'chat', labelKey: 'chat', route: '/chat'),
    VoiceNavCommand(key: 'forum', labelKey: 'forum', route: '/forum'),
    VoiceNavCommand(key: 'financial', labelKey: 'financial', route: '/financial'),
    VoiceNavCommand(key: 'emergency_numbers', labelKey: 'emergency_numbers', route: '/emergency-numbers'),
    VoiceNavCommand(key: 'agreements', labelKey: 'agreements', route: '/agreements'),
    VoiceNavCommand(key: 'referral', labelKey: 'referral', route: '/referral'),
    VoiceNavCommand(key: 'notifications', labelKey: 'notifications', route: '/notifications'),
    VoiceNavCommand(key: 'parking', labelKey: 'parking', route: '/resident/parking'),
    // Opt-in per apartment (Super Admin > Community Meeting Settings) -
    // filtered by BrandingService.communityMeetingEnabled in forRole()
    // below rather than ModuleGate, same reasoning as AppDrawer's matching
    // entry (see app_drawer.dart's comment on its 'Meet Live' tiles).
    VoiceNavCommand(key: 'community_meeting', labelKey: 'community_meeting', route: '/community-meeting'),
    VoiceNavCommand(key: 'profile', labelKey: 'profile', route: '/profile'),
  ];

  static const List<VoiceNavCommand> _admin = [
    VoiceNavCommand(key: 'home', labelKey: 'dashboard', route: '/admin/dashboard'),
    VoiceNavCommand(key: 'residents', labelKey: 'residents', route: '/admin/residents'),
    VoiceNavCommand(key: 'bills', labelKey: 'bills', route: '/admin/bills'),
    VoiceNavCommand(key: 'complaints', labelKey: 'complaints', route: '/admin/complaints'),
    VoiceNavCommand(key: 'visitors', labelKey: 'visitors', route: '/admin/visitors'),
    VoiceNavCommand(key: 'parking', labelKey: 'parking', route: '/admin/parking'),
    VoiceNavCommand(key: 'bookings', labelKey: 'bookings', route: '/admin/bookings'),
    VoiceNavCommand(key: 'notices', labelKey: 'notices', route: '/admin/notices'),
    VoiceNavCommand(key: 'approvals', labelKey: 'approvals', route: '/admin/approvals'),
    VoiceNavCommand(key: 'forum', labelKey: 'forum', route: '/forum'),
    VoiceNavCommand(key: 'wallet', labelKey: 'wallet', route: '/admin/wallet'),
    VoiceNavCommand(key: 'flat_charges', labelKey: 'flat_charges', route: '/admin/flat-charges'),
    VoiceNavCommand(key: 'tickets', labelKey: 'support_tickets', route: '/admin/tickets'),
    VoiceNavCommand(key: 'towers', labelKey: 'towers', route: '/admin/towers'),
    VoiceNavCommand(key: 'floors', labelKey: 'floors', route: '/admin/floors'),
    VoiceNavCommand(key: 'flats', labelKey: 'flats', route: '/admin/flats'),
    VoiceNavCommand(key: 'charge_setup', labelKey: 'charge_setup', route: '/admin/charge-setup'),
    VoiceNavCommand(key: 'expenses', labelKey: 'expenses', route: '/admin/expenses'),
    VoiceNavCommand(key: 'general_categories', labelKey: 'general_categories', route: '/admin/general-categories'),
    VoiceNavCommand(key: 'vendors', labelKey: 'vendors_payees', route: '/admin/vendors'),
    VoiceNavCommand(key: 'one_time_charges', labelKey: 'one_time_charges', route: '/admin/one-time-charges'),
    VoiceNavCommand(key: 'reports_financial', labelKey: 'financial', route: '/admin/reports/financial'),
    VoiceNavCommand(key: 'reports_complaints', labelKey: 'complaints_report', route: '/admin/reports/complaints'),
    VoiceNavCommand(key: 'reports_occupancy', labelKey: 'occupancy', route: '/admin/reports/occupancy'),
    VoiceNavCommand(key: 'branding', labelKey: 'app_identity', route: '/admin/branding'),
    VoiceNavCommand(key: 'bulk_notify', labelKey: 'send_notification_to_residents', route: '/admin/bulk-notify'),
    VoiceNavCommand(key: 'emergency_numbers', labelKey: 'emergency_numbers', route: '/admin/emergency-numbers'),
    VoiceNavCommand(key: 'agreements', labelKey: 'agreements', route: '/admin/agreements'),
    VoiceNavCommand(key: 'referral', labelKey: 'referral', route: '/admin/referral'),
    VoiceNavCommand(key: 'subscription', labelKey: 'subscription', route: '/admin/subscription'),
    // See the matching resident-catalog entry above for why this is
    // filtered via BrandingService rather than ModuleGate.
    VoiceNavCommand(key: 'community_meeting', labelKey: 'community_meeting', route: '/admin/community-meeting'),
    VoiceNavCommand(key: 'profile', labelKey: 'profile', route: '/profile'),
  ];

  static const List<VoiceNavCommand> _security = [
    VoiceNavCommand(key: 'home', labelKey: 'dashboard', route: '/security/dashboard'),
    VoiceNavCommand(key: 'visitors', labelKey: 'visitors', route: '/security/visitors'),
    VoiceNavCommand(key: 'residents', labelKey: 'residents', route: '/security/residents'),
    VoiceNavCommand(key: 'parking', labelKey: 'parking', route: '/security/parking'),
    VoiceNavCommand(key: 'complaints', labelKey: 'complaints', route: '/security/complaints'),
    VoiceNavCommand(key: 'bookings', labelKey: 'bookings', route: '/security/bookings'),
    VoiceNavCommand(key: 'profile', labelKey: 'profile', route: '/profile'),
  ];

  // Previously missing entirely - forRole()'s `_ => _resident` fallback
  // meant a Company Admin saying "open dashboard" (or anything else) was
  // silently matched against the RESIDENT catalog and sent to '/dashboard'
  // instead of their own '/company/dashboard' - none of a Company Admin's
  // actual screens were reachable by voice at all.
  static const List<VoiceNavCommand> _companyAdmin = [
    VoiceNavCommand(key: 'home', labelKey: 'company_dashboard', route: '/company/dashboard'),
    VoiceNavCommand(key: 'apartments', labelKey: 'apartments', route: '/company/apartments'),
    VoiceNavCommand(key: 'apt_admins', labelKey: 'apartment_admins', route: '/company/apt-admins'),
    VoiceNavCommand(key: 'plans', labelKey: 'my_plans', route: '/company/plans'),
    VoiceNavCommand(key: 'subscriptions', labelKey: 'subscriptions', route: '/company/subscriptions'),
    VoiceNavCommand(key: 'report', labelKey: 'company_report', route: '/company/report'),
    VoiceNavCommand(key: 'company_profile', labelKey: 'company_profile', route: '/company/profile'),
    VoiceNavCommand(key: 'profile', labelKey: 'profile', route: '/profile'),
  ];

  // Same gap as Company Admin above - a Super Admin saying "open companies"
  // (or any other command) fell through to the resident catalog and never
  // matched, or worse, fuzzy-matched something unrelated and navigated to a
  // resident screen a Super Admin has no business being on.
  static const List<VoiceNavCommand> _superAdmin = [
    VoiceNavCommand(key: 'home', labelKey: 'dashboard', route: '/super-admin/dashboard'),
    VoiceNavCommand(key: 'companies', labelKey: 'companies', route: '/super-admin/companies'),
    VoiceNavCommand(key: 'apartments', labelKey: 'apartments', route: '/super-admin/apartments'),
    VoiceNavCommand(key: 'apt_admins', labelKey: 'apartment_admins', route: '/super-admin/apt-admins'),
    VoiceNavCommand(key: 'plans', labelKey: 'plans', route: '/super-admin/plans'),
    VoiceNavCommand(key: 'subscriptions', labelKey: 'subscriptions', route: '/super-admin/subscriptions'),
    VoiceNavCommand(key: 'profile', labelKey: 'profile', route: '/profile'),
  ];

  /// [role] is 'resident', 'apartment_admin', 'security', 'company_admin',
  /// or 'super_admin'. Drops commands whose underlying module has been
  /// switched OFF for this apartment (Apartment > Branding > "Assign Menu")
  /// - mirrors AppDrawer's filtering so voice never opens a screen the
  /// Drawer wouldn't even show. (Module gating is a no-op for the Company
  /// Admin / Super Admin catalogs below since none of their keys are in
  /// ModuleGate's map - those screens aren't apartment-scoped.)
  static List<VoiceNavCommand> forRole(String role) {
    final base = switch (role) {
      'apartment_admin' => _admin,
      'security' => _security,
      'company_admin' => _companyAdmin,
      'super_admin' => _superAdmin,
      _ => _resident,
    };
    return base
        .where((c) => !ModuleGate.isOff(c.key))
        // Community Meeting is opt-in/off-by-default rather than an
        // ApartmentModuleCatalog on-off toggle, so ModuleGate (which only
        // knows about "on unless switched off" modules) can't gate it -
        // check BrandingService directly instead, same as AppDrawer does
        // for its own 'Meet Live' tiles.
        .where((c) => c.key != 'community_meeting' || BrandingService.communityMeetingEnabled)
        .toList();
  }
}
