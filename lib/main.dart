import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'services/auth_service.dart';
import 'services/branding_service.dart';
import 'services/language_service.dart';
import 'services/app_refresh.dart';
import 'services/fcm_service.dart';
import 'services/maintenance_service.dart';
import 'services/text_scale_service.dart';
import 'services/modal_visibility.dart';
import 'screens/maintenance/maintenance_screen.dart';
import 'widgets/voice_command_overlay.dart';

// ── Auth ──────────────────────────────────────────────────────────────────────
// No RegisterScreen here - Company Admin accounts are provisioned by Super
// Admin (Super Admin > Companies), never self-registered from this app.
import 'screens/auth/login_screen.dart';
import 'screens/update/force_update_screen.dart';
import 'services/app_update_service.dart';
import 'screens/legal/cms_page_screen.dart';
import 'screens/chat/group_chat_screen.dart';
import 'screens/forum/forum_screen.dart';
import 'screens/forum/forum_thread_screen.dart';
import 'screens/forum/forum_create_screen.dart';
import 'screens/auth/forgot_password_screen.dart';

// ── Shared ────────────────────────────────────────────────────────────────────
import 'screens/profile/profile_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/notifications/notification_settings_screen.dart';
import 'screens/emergency/emergency_numbers_screen.dart';
import 'screens/community_meeting/community_meeting_screen.dart';
import 'screens/agreements/agreements_screen.dart';
import 'screens/referral/referral_screen.dart';

// ── Admin — Dashboard ─────────────────────────────────────────────────────────
// A Company Admin manages one or more apartments and can "Enter" any of
// them from the Company Dashboard (see CompanyDashboardScreen._enterApartment())
// to act as that apartment's Admin - so this app needs the FULL admin
// panel, not just the company-level screens below.
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_subscription_screen.dart';
import 'screens/admin/admin_residents_screen.dart';
import 'screens/admin/admin_bills_screen.dart';
import 'screens/admin/admin_complaints_screen.dart';
import 'screens/admin/admin_visitors_screen.dart';
import 'screens/admin/admin_notices_screen.dart';
import 'screens/admin/admin_rules_screen.dart';

// ── Admin — Masters ───────────────────────────────────────────────────────────
import 'screens/admin/admin_towers_screen.dart';
import 'screens/admin/admin_floors_screen.dart';
import 'screens/admin/admin_flats_screen.dart';
import 'screens/admin/admin_charge_setup_screen.dart';

// ── Admin — Finance ───────────────────────────────────────────────────────────
import 'screens/admin/admin_expenses_screen.dart';
import 'screens/admin/admin_other_income_screen.dart';
import 'screens/admin/admin_treasurer_screen.dart';
import 'screens/admin/admin_upi_settings_screen.dart';
import 'screens/admin/admin_bank_transfer_settings_screen.dart';
import 'screens/admin/admin_general_categories_screen.dart';
import 'screens/admin/admin_vendors_screen.dart';
import 'screens/admin/admin_one_time_charges_screen.dart';

// ── Admin — Operations & Amenities ────────────────────────────────────────────
import 'screens/admin/admin_facilities_bookings_screen.dart';
import 'screens/admin/admin_booking_detail_screen.dart';
import 'screens/admin/admin_approvals_screen.dart';
import 'screens/admin/admin_wallet_screen.dart';
import 'screens/admin/admin_flat_charge_overrides_screen.dart';
import 'screens/admin/admin_tickets_screen.dart';
import 'screens/admin/admin_ticket_create_screen.dart';
import 'screens/admin/admin_ticket_thread_screen.dart';
import 'screens/admin/admin_parking_screen.dart';

// ── Admin — Reports ───────────────────────────────────────────────────────────
import 'screens/admin/admin_reports_financial_screen.dart';
// Complaints + Occupancy reports are in the same file
import 'screens/admin/admin_reports_occupancy_complaints_screen.dart';

// ── Admin — Settings ──────────────────────────────────────────────────────────
// Branding + BulkNotify are in the same file
import 'screens/admin/admin_branding_bulk_screen.dart';

// ── Company ───────────────────────────────────────────────────────────────────
import 'screens/company/company_dashboard_screen.dart';
import 'screens/company/company_report_screen.dart';
import 'screens/company/company_plans_screen.dart';
import 'screens/company/company_apt_admins_screen.dart';
import 'screens/company/company_apartments_screen.dart';
import 'screens/company/company_menu_settings_screen.dart';
import 'screens/company/company_menu_settings_edit_screen.dart';
import 'screens/company/company_profile_screen.dart';
import 'screens/company/company_subscriptions_screen.dart';
import 'screens/company/company_bank_details_screen.dart';
import 'screens/company/company_referrer_commissions_screen.dart';
import 'screens/company/company_send_email_screen.dart';
import 'screens/company/company_subscription_screen.dart';
import 'screens/splash/splash_screen.dart';

/// Set once at startup (before the router builds) - non-null means a
/// mandatory update is pending. See AppUpdateService for the
/// version-comparison logic and ForceUpdateScreen for the blocking
/// screen this routes to.
UpdateInfo? _mandatoryUpdate;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AppBootstrap());
}

/// Shown first, in place of `ApartmentManagementApp`, so the splash
/// graphic + loader is what the user sees for the entire startup
/// sequence below - checking for a mandatory update, maintenance mode,
/// and the current session - instead of a blank/frozen frame while
/// that work happens off in `main()` before anything is drawn.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();
  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _ready = false;
  String _status = 'Loading…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await LanguageService.loadSaved();
    await TextScaleService.loadSaved();
    await BrandingService.load();
    await FcmService.init();

    setState(() => _status = 'Checking for updates…');
    _mandatoryUpdate = await AppUpdateService.checkForMandatoryUpdate();
    if (_mandatoryUpdate != null) {
      // Force logout: whoever was signed in must see the update screen
      // first, on every app open, until they update.
      await AuthService().logout();
    } else {
      setState(() => _status = 'Checking session…');
      await MaintenanceService.check();
      final blockedByMaintenance = MaintenanceService.current?.enabled == true;

      if (blockedByMaintenance) {
        // Unlike the full app, there's no Super Admin role in this build to
        // exempt from Maintenance Mode - a Company Admin session is always
        // signed out immediately, same as everyone else.
        await AuthService().logout();
      } else if (await AuthService().isLoggedIn()) {
        // If the user is already logged in (app restart, not a fresh login),
        // re-register the current token in case it rotated while the app was
        // closed — FCM tokens aren't guaranteed stable across reinstalls/restores.
        FcmService.registerToken();
      }
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // No branding/theme yet at this point (that's one of the things
      // `_init` above is loading), so this MaterialApp only exists to
      // give SplashScreen a Directionality/Theme to sit inside — it
      // deliberately doesn't share ApartmentManagementApp's ThemeData.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(message: _status),
      );
    }
    return const ApartmentManagementApp();
  }
}

// See navigatorKey usage below.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
	// Needed so widgets that sit OUTSIDE the routed page in the widget tree
	// (e.g. VoiceCommandOverlay, plugged in via MaterialApp.router's
	// `builder`, puts VoiceCommandButton in a Stack as a SIBLING of the
	// router's child, not a descendant) can still reach a valid Navigator.
	navigatorKey: rootNavigatorKey,
	observers: [ModalVisibilityObserver()],
	initialLocation: _mandatoryUpdate != null ? '/force-update' : '/login',
	redirect: (context, state) async {
	  final loc = state.matchedLocation;

	  // 1. Force update has highest priority
	  if (_mandatoryUpdate != null) {
		if (loc != '/force-update') {
		  return '/force-update';
		}
		return null;
	  }

	  // 1.5 Maintenance mode - blocks EVERYONE in this build (no Super
	  // Admin exemption here - see main() above). /login and the
	  // forgot-password screen stay reachable so the maintenance message
	  // from the server still surfaces clearly rather than a dead screen.
	  if (MaintenanceService.current?.enabled == true) {
		const reachableDuringMaintenance = ['/maintenance', '/login', '/forgot-password-elevated'];
		if (!reachableDuringMaintenance.contains(loc)) {
		  return '/maintenance';
		}
		return null;
	  }

	  // 2. Authentication logic
	  final isLoggedIn = await AuthService().isLoggedIn();

	  const alwaysPublic = ['/terms', '/privacy', '/cookie-policy', '/refund-cancellation', '/eula', '/account-deletion'];
	  const authOnlyPages = ['/login', '/forgot-password-elevated'];

	  if (alwaysPublic.contains(loc)) {
		return null;
	  }

	  if (!isLoggedIn) {
		return authOnlyPages.contains(loc) ? null : '/login';
	  }

	  // This app is Company Admin only - a token saved by some other means
	  // (e.g. a stale session) for any other role is never allowed through,
	  // even though login_screen.dart already refuses to save one in the
	  // first place. Defense in depth costs nothing here.
	  final user = await AuthService().getUser();
	  if (user?['role'] != 'company_admin') {
		await AuthService().logout();
		return '/login';
	  }

	  if (authOnlyPages.contains(loc)) {
		return '/company/dashboard';
	  }

	  return null;
	},
  routes: [
    GoRoute(path: '/force-update', builder: (_, __) => _mandatoryUpdate != null ? ForceUpdateScreen(update: _mandatoryUpdate!) : const LoginScreen()),
    GoRoute(path: '/maintenance', builder: (_, __) => MaintenanceScreen(message: MaintenanceService.current?.message)),

    GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
    // Safety-net aliases: a couple of shared widgets/screens copied over
    // from the full app (drawer's dual-role dashboard toggle, profile's
    // apartment-switch redirect, voice commands) reference these two paths
    // in code branches that only ever fire for Resident/Apartment Admin
    // accounts - never reachable for a real Company Admin login - but
    // registering them anyway means an unreachable branch can never hard-
    // crash the router (GoRouter throws on an unregistered path) if some
    // future change makes one of them reachable after all.
    GoRoute(path: '/dashboard', builder: (_, __) => const CompanyDashboardScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen(elevated: true)),
    GoRoute(path: '/terms',   builder: (_, __) => const CmsPageScreen(slug: 'terms', fallbackTitle: 'Terms & Conditions')),
    GoRoute(path: '/privacy', builder: (_, __) => const CmsPageScreen(slug: 'privacy', fallbackTitle: 'Privacy Policy')),
    GoRoute(path: '/cookie-policy',       builder: (_, __) => const CmsPageScreen(slug: 'cookie-policy', fallbackTitle: 'Cookie Policy')),
    GoRoute(path: '/refund-cancellation', builder: (_, __) => const CmsPageScreen(slug: 'refund-cancellation', fallbackTitle: 'Refund & Cancellation')),
    GoRoute(path: '/eula',                builder: (_, __) => const CmsPageScreen(slug: 'eula', fallbackTitle: 'EULA')),
    GoRoute(path: '/account-deletion',    builder: (_, __) => const CmsPageScreen(slug: 'account-deletion', fallbackTitle: 'Account Deletion')),
    GoRoute(path: '/chat', builder: (_, __) => const GroupChatScreen()),
    GoRoute(path: '/forum', builder: (_, __) => const ForumScreen()),
    GoRoute(path: '/forum/new', builder: (_, __) => const ForumCreateScreen()),
    GoRoute(path: '/forum/:slug', builder: (_, state) => ForumThreadScreen(slug: state.pathParameters['slug']!)),
    // Only the elevated (email-only, no apartment) flow is used here -
    // see PasswordResetOtpService::resolveElevatedUser() on the backend,
    // which covers both super_admin and company_admin.
    GoRoute(path: '/forgot-password-elevated', builder: (_, __) => const ForgotPasswordScreen(elevated: true)),

    GoRoute(path: '/profile',         builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/notifications',        builder: (_, __) => const NotificationsScreen()),
    GoRoute(path: '/notification-settings', builder: (_, __) => const NotificationSettingsScreen()),
    GoRoute(path: '/admin/emergency-numbers', builder: (_, __) => const EmergencyNumbersScreen()),
    GoRoute(path: '/admin/community-meeting', builder: (_, __) => const CommunityMeetingScreen()),
    GoRoute(path: '/admin/agreements', builder: (_, __) => const AgreementsScreen()),
    GoRoute(path: '/admin/rules', builder: (_, __) => const AdminRulesScreen()),
    GoRoute(path: '/admin/referral', builder: (_, __) => const ReferralScreen()),

    // ── Admin (Company Admin acting as a specific apartment's Admin, via
    // Company Dashboard > Enter Apartment) ──────────────────────────────
    GoRoute(path: '/admin/dashboard',      builder: (_, __) => AdminDashboardScreen(key: ValueKey('admin_dash_${AuthService.apartmentSwitchEpoch}'))),
    GoRoute(path: '/admin/residents',      builder: (_, __) => const AdminResidentsScreen()),
    GoRoute(path: '/admin/bills',          builder: (_, __) => const AdminBillsScreen()),
    GoRoute(path: '/admin/complaints',     builder: (_, __) => const AdminComplaintsScreen()),
    GoRoute(path: '/admin/visitors',       builder: (_, __) => const AdminVisitorsScreen()),
    GoRoute(path: '/admin/notices',        builder: (_, __) => const AdminNoticesScreen()),

    GoRoute(path: '/admin/towers',         builder: (_, __) => const AdminTowersScreen()),
    GoRoute(path: '/admin/floors',         builder: (_, __) => const AdminFloorsScreen()),
    GoRoute(path: '/admin/flats',          builder: (_, __) => const AdminFlatsScreen()),
    GoRoute(path: '/admin/charge-setup',   builder: (_, __) => const AdminChargeSetupScreen()),

    GoRoute(path: '/admin/expenses',            builder: (_, __) => const AdminExpensesScreen()),
    GoRoute(path: '/admin/other-income',        builder: (_, __) => const AdminOtherIncomeScreen()),
    GoRoute(path: '/admin/treasurer',           builder: (_, __) => const AdminTreasurerScreen()),
    GoRoute(path: '/admin/upi-settings',        builder: (_, __) => const AdminUpiSettingsScreen()),
    GoRoute(path: '/admin/bank-transfer-settings', builder: (_, __) => const AdminBankTransferSettingsScreen()),
    GoRoute(path: '/admin/general-categories',  builder: (_, __) => const AdminGeneralCategoriesScreen()),
    GoRoute(path: '/admin/vendors',             builder: (_, __) => const AdminVendorsScreen()),
    GoRoute(path: '/admin/one-time-charges',    builder: (_, __) => const AdminOneTimeChargesScreen()),

    GoRoute(path: '/admin/one-time-charges/pending', builder: (_, __) => const AdminApprovalsScreen(initialTab: 2)),

    GoRoute(path: '/admin/facilities',     builder: (_, __) => const AdminFacilitiesScreen()),
    GoRoute(path: '/admin/bookings',       builder: (_, __) => const AdminBookingsScreen()),
    GoRoute(path: '/admin/bookings/:id',   builder: (_, state) => AdminBookingDetailScreen(bookingId: int.parse(state.pathParameters['id']!))),

    GoRoute(path: '/admin/approvals',        builder: (_, state) => AdminApprovalsScreen(initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0)),
    GoRoute(path: '/admin/payments/pending', builder: (_, __) => const AdminApprovalsScreen(initialTab: 1)),
    GoRoute(path: '/admin/wallet',           builder: (_, __) => const AdminWalletScreen()),
    GoRoute(path: '/admin/wallet/pending',   builder: (_, __) => const AdminApprovalsScreen(initialTab: 3)),
    GoRoute(path: '/admin/flat-charges', builder: (_, __) => const AdminFlatChargeOverridesScreen()),
    GoRoute(path: '/admin/tickets', builder: (_, __) => const AdminTicketsScreen()),
    GoRoute(path: '/admin/subscription', builder: (_, __) => const AdminSubscriptionScreen()),
    GoRoute(path: '/admin/tickets/create', builder: (_, __) => const AdminTicketCreateScreen()),
    GoRoute(path: '/admin/tickets/:id', builder: (_, state) => AdminTicketThreadScreen(ticketId: int.parse(state.pathParameters['id']!))),
    GoRoute(path: '/admin/parking',        builder: (_, __) => const AdminParkingScreen()),

    GoRoute(path: '/admin/reports/financial',  builder: (_, __) => const AdminReportsFinancialScreen()),
    GoRoute(path: '/admin/reports/complaints', builder: (_, __) => const AdminReportsComplaintsScreen()),
    GoRoute(path: '/admin/reports/occupancy',  builder: (_, __) => const AdminReportsOccupancyScreen()),

    GoRoute(path: '/admin/branding',       builder: (_, __) => const AdminBrandingScreen()),
    GoRoute(path: '/admin/bulk-notify',    builder: (_, __) => const AdminBulkNotifyScreen()),

    // ── Company (own level - across all managed apartments) ─────────────
    GoRoute(path: '/company/dashboard',    builder: (_, __) => const CompanyDashboardScreen()),
    GoRoute(path: '/company/report',       builder: (_, __) => const CompanyReportScreen()),
    GoRoute(path: '/company/plans',        builder: (_, __) => const CompanyPlansScreen()),
    GoRoute(path: '/company/apt-admins',   builder: (_, __) => const CompanyAptAdminsScreen()),
    GoRoute(path: '/company/apartments',   builder: (_, __) => const CompanyApartmentsScreen()),
    GoRoute(path: '/company/menu-settings', builder: (_, __) => const CompanyMenuSettingsScreen()),
    GoRoute(path: '/company/menu-settings/:id', builder: (_, state) => CompanyMenuSettingsEditScreen(
      apartmentId: int.parse(state.pathParameters['id']!),
      apartmentName: state.extra as String?,
    )),
    GoRoute(path: '/company/profile',      builder: (_, __) => const CompanyProfileScreen()),
    GoRoute(path: '/company/subscriptions',builder: (_, __) => const CompanySubscriptionsScreen()),
    GoRoute(path: '/company/bank-details', builder: (_, __) => const CompanyBankDetailsScreen()),
    GoRoute(path: '/company/referrer-commissions', builder: (_, __) => const CompanyReferrerCommissionsScreen()),
    GoRoute(path: '/company/send-email',   builder: (_, __) => const CompanySendEmailScreen()),
    GoRoute(path: '/company/subscription', builder: (_, __) => const CompanySubscriptionScreen()),
  ],
);

class ApartmentManagementApp extends StatelessWidget {
  const ApartmentManagementApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppRefresh.tick,
      builder: (context, _, __) {
        final primary = BrandingService.primary;
        final accent  = BrandingService.accent;
        return MaterialApp.router(
      title: BrandingService.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary, primary: primary, secondary: accent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        splashFactory: InkRipple.splashFactory,

        appBarTheme: AppBarTheme(
          backgroundColor: primary, foregroundColor: Colors.white, elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),

        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          foregroundColor: Colors.white,
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary, foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300], disabledForegroundColor: Colors.grey[500],
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: primary.withOpacity(0.5), width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: Colors.grey[700]),
        ),

        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withOpacity(0.05)),
          ),
          color: BrandingService.cardBg,
          margin: EdgeInsets.zero,
          shadowColor: Colors.black.withOpacity(0.08),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: Colors.grey[100],
          selectedColor: primary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          secondaryLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: BorderSide.none,
        ),

        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary, width: 1.8)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.red.shade300)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.red.shade400, width: 1.8)),
          errorStyle: TextStyle(color: Colors.red.shade600, fontSize: 12, fontWeight: FontWeight.w500),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
          floatingLabelStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
          hintStyle: TextStyle(color: Colors.grey[500]),
          fillColor: Colors.white, filled: true,
        ),

        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: Colors.white,
          titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          contentTextStyle: TextStyle(fontSize: 14, color: Colors.grey[800]),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          elevation: 4,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),
        drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
        tabBarTheme: TabBarThemeData(
          labelColor: primary, unselectedLabelColor: Colors.grey[500],
          indicatorColor: primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1E1E1E)),
          bodyMedium: TextStyle(color: Color(0xFF1E1E1E)),
        ),
      ),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(TextScaleService.scale)
              .clamp(minScaleFactor: 0.8, maxScaleFactor: 1.6),
        ),
        child: _MaintenancePoller(child: VoiceCommandOverlay(child: child)),
      ),
        );
      },
    );
  }
}

/// Periodically checks Maintenance Mode while the app is in the
/// foreground - see the identical class in the main app for why this
/// exists alongside ApiService's reactive check.
class _MaintenancePoller extends StatefulWidget {
  final Widget? child;
  const _MaintenancePoller({required this.child});

  @override
  State<_MaintenancePoller> createState() => _MaintenancePollerState();
}

class _MaintenancePollerState extends State<_MaintenancePoller> with WidgetsBindingObserver {
  Timer? _timer;
  static const _interval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  Future<void> _poll() async {
    final info = await MaintenanceService.check();
    if (info == null || !info.enabled) return;

    // No Super Admin exemption in this build - see main().
    final loc = router.routerDelegate.currentConfiguration.uri.toString();
    if (loc == '/maintenance') return; // already there

    await AuthService().logout();
    router.go('/maintenance');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poll();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
