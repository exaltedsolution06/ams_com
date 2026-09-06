import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/app_refresh.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/language_service.dart';
import '../services/module_gate.dart';
import 'ams_dialog.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // Every `const AppDrawer()` call site resolves to the same canonical
    // instance, so when a parent screen rebuilds after e.g. a subscription
    // plan change, Flutter's element diffing sees an identical widget and
    // skips rebuilding this subtree entirely - the FutureBuilder below
    // never re-runs, and the sidebar keeps showing whatever role/module
    // state was true at its last real build until a full logout/login.
    // Listening to AppRefresh here guarantees a rebuild (and a fresh
    // _loadDrawerData() call, plus fresh ModuleGate/BrandingService reads)
    // any time global app state changes - see BrandingService.load() and
    // AdminSubscriptionScreen's plan-change flow, which both call
    // AppRefresh.bump().
    return ValueListenableBuilder<int>(
      valueListenable: AppRefresh.tick,
      builder: (context, _, __) => FutureBuilder<_DrawerData>(
        future: _loadDrawerData(),
        builder: (context, snap) {
        final data = snap.data;
        final user  = data?.user ?? {};
        final role  = data?.effectiveRole ?? 'resident';
        final name  = user['name']  as String? ?? '';
        final email = user['email'] as String? ?? '';
        final dualRole = data?.hasDualRole ?? false;
        return Drawer(
          backgroundColor: Colors.white,
          child: Column(children: [
            _Header(name: name, email: email, role: role),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  ..._menu(context, role, data?.selectedApartmentId, user),
                  const Divider(),
                  _Sec('ACCOUNT'),
                  if (dualRole)
                    ListTile(
                      dense: true,
                      leading: Icon(role == 'resident' ? Icons.admin_panel_settings_outlined : Icons.home_outlined,
                          color: BrandingService.primary, size: 20),
                      title: Text(
                        role == 'resident' ? 'Switch to Admin View' : 'Switch to Resident View',
                        style: TextStyle(color: BrandingService.primary, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      onTap: () async {
                        final newMode = role == 'resident' ? 'admin' : 'resident';
                        await AuthService().setViewMode(newMode);
                        if (context.mounted) {
                          Navigator.pop(context);
                          context.go(newMode == 'admin' ? '/admin/dashboard' : '/dashboard');
                        }
                      },
                    ),
                  _Tile(icon: Icons.person_outline, label: LanguageService.t('profile'),         route: '/profile',          push: true),
                  _Tile(icon: Icons.lock_outline,   label: LanguageService.t('change_password'), route: '/profile',          push: true),
                  _Tile(icon: Icons.notifications_active_outlined, label: LanguageService.t('notification_settings'), route: '/notification-settings', push: true),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout, color: Colors.red, size: 20),
              title: Text(LanguageService.t('logout'), style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 14)),
              onTap: () async {
                final confirmed = await AmsDialog.confirm(
                  context,
                  title: LanguageService.t('logout'),
                  message: LanguageService.t('voice_confirm_logout'),
                  icon: Icons.logout_rounded,
                  confirmText: 'Logout',
                  danger: true,
                );
                if (confirmed != true) return;
                if (context.mounted) Navigator.pop(context);
                await AuthService().logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ]),
        );
        },
      ),
    );
  }

  Future<_DrawerData> _loadDrawerData() async {
    final auth = AuthService();
    final user = await auth.getUser() ?? {};
    final effectiveRole = await auth.effectiveRole();
    final hasDualRole = await auth.hasDualRole();
    final selectedApartmentId = effectiveRole == 'company_admin' ? await auth.getSelectedApartmentId() : null;
    return _DrawerData(user: user, effectiveRole: effectiveRole, hasDualRole: hasDualRole, selectedApartmentId: selectedApartmentId);
  }

  List<Widget> _menu(BuildContext context, String role, int? selectedApartmentId, Map user) {
    final raw = switch (role) {
      'apartment_admin' => _adminMenu(isApartmentAdmin: true),
      'company_admin'   => selectedApartmentId != null
          ? _companyInsideApartmentMenu()
          : _companyMenu(),
      'super_admin'     => _superAdminMenu(),
      'security'        => _secMenu(),
      _                 => _resMenu(isActiveTreasurer: (user['is_active_treasurer'] as bool?) ?? false),
    };
    return _render(_filter(raw));
  }

  // Drops any entry whose `module` has been switched OFF for this apartment
  // (Apartment > Branding > "Assign Menu"), then drops any section header
  // left with no visible tile following it - so we never show a lone
  // "PARKING" heading over nothing, for example.
  List<_MenuEntry> _filter(List<_MenuEntry> items) {
    final visible = items
        .where((e) => e.isSection || e.module == null || !ModuleGate.isOff(e.module!))
        .toList();
    final out = <_MenuEntry>[];
    for (var i = 0; i < visible.length; i++) {
      final e = visible[i];
      if (e.isSection && (i + 1 >= visible.length || visible[i + 1].isSection)) {
        continue; // empty section, drop the heading
      }
      out.add(e);
    }
    return out;
  }

  List<Widget> _render(List<_MenuEntry> items) => items
      .map((e) => e.isSection
          ? _Sec(e.label)
          : _Tile(icon: e.icon!, label: e.label, route: e.route!, push: e.push, beforeNavigate: e.beforeNavigate))
      .toList();

  // ── ADMIN MENU ──────────────────────────────────────────────────────────────
  // Home routes use push: false (context.go — resets stack to dashboard)
  // All sub-screens use push: true (context.push — back button works)
  // `module:` tags an entry with the ApartmentModuleCatalog key that gates
  // it (see ModuleGate) — omitted for core/ungated features.
  List<_MenuEntry> _adminMenu({required bool isApartmentAdmin}) => [
    _MenuEntry.tile(icon: Icons.dashboard_outlined,           label: LanguageService.t('dashboard'),          route: '/admin/dashboard',       push: false),

    // ── QUICK ACTIONS ──────────────────────────────────────────────────
    // One-tap shortcuts to the most-used day-to-day screens: Billing,
    // Approvals, Expenses, Financial Report, Complaints, Notices. Each
    // tile reuses the exact same `module:` gate as its full entry further
    // down, so a shortcut never exposes something the apartment's plan
    // has locked (see ModuleGate / _filter above).
    _MenuEntry.section('QUICK ACTIONS'),
    _MenuEntry.tile(icon: Icons.receipt_long,                  label: LanguageService.t('billing'),            route: '/admin/bills',           push: true),
    _MenuEntry.tile(icon: Icons.fact_check_outlined,           label: LanguageService.t('approvals'),          route: '/admin/approvals',       push: true),
    _MenuEntry.tile(icon: Icons.account_balance_wallet_outlined, label: LanguageService.t('expenses'),         route: '/admin/expenses',        push: true),
    _MenuEntry.tile(icon: Icons.bar_chart_outlined,            label: LanguageService.t('financial'),          route: '/admin/reports/financial',   push: true, module: 'reports_financial'),
    _MenuEntry.tile(icon: Icons.chat_bubble_outline,           label: LanguageService.t('complaints'),         route: '/admin/complaints',      push: true, module: 'complaints'),
    _MenuEntry.tile(icon: Icons.campaign_outlined,             label: LanguageService.t('notices'),            route: '/admin/notices',         push: true, module: 'notices'),

    // ── APARTMENT MANAGEMENT ──────────────────────────────────────────
    // Towers, Floors, Flats, Residents, Facilities, Parking, Visitors,
    // SOS Helpline, Agreements, Rules, General Categories.
    _MenuEntry.section('APARTMENT MANAGEMENT'),
    // Floors belong directly to the apartment now, not only to a Tower -
    // see FloorController (web) which already handles towerless apartments
    // fine. Only Towers should be hidden when the apartment has no towers.
    if (BrandingService.hasTowers)
      _MenuEntry.tile(icon: Icons.cell_tower_outlined,         label: LanguageService.t('towers'),             route: '/admin/towers',          push: true),
    _MenuEntry.tile(icon: Icons.layers_outlined,               label: LanguageService.t('floors'),             route: '/admin/floors',          push: true),
    _MenuEntry.tile(icon: Icons.door_front_door_outlined,      label: LanguageService.t('flats'),              route: '/admin/flats',           push: true),
    _MenuEntry.tile(icon: Icons.people_outline,                label: LanguageService.t('residents'),          route: '/admin/residents',       push: true),
    _MenuEntry.tile(icon: Icons.meeting_room_outlined,         label: LanguageService.t('facilities'),         route: '/admin/facilities',      push: true, module: 'facilities'),
    _MenuEntry.tile(icon: Icons.local_parking_outlined,        label: LanguageService.t('parking'),            route: '/admin/parking',         push: true, module: 'parking'),
    _MenuEntry.tile(icon: Icons.badge_outlined,                label: LanguageService.t('visitors'),           route: '/admin/visitors',        push: true, module: 'visitors'),
    _MenuEntry.tile(icon: Icons.contact_phone_outlined,        label: LanguageService.t('emergency_numbers'),  route: '/admin/emergency-numbers', push: true, module: 'emergency_numbers'),
    _MenuEntry.tile(icon: Icons.file_present_outlined,         label: LanguageService.t('agreements'),         route: '/admin/agreements',      push: true, module: 'agreements'),
    // Apartment Admin only - Company Admin viewing this same menu inside
    // an apartment doesn't get edit rights on Rules (see RulesApiController).
    if (isApartmentAdmin)
      _MenuEntry.tile(icon: Icons.menu_book_outlined,           label: LanguageService.t('rules'),              route: '/admin/rules',            push: true),
    _MenuEntry.tile(icon: Icons.tag,                           label: LanguageService.t('general_categories'), route: '/admin/general-categories', push: true),

    // ── BILLING & FINANCE ─────────────────────────────────────────────
    // Charge Setup, One-Time Charges, Wallet, Other Income,
    // Vendors / Payees, Fund & Treasurer. (Billing, Expenses, Financial
    // Report and General Categories now live as Quick Actions /
    // Apartment Management shortcuts above.)
    _MenuEntry.section('BILLING & FINANCE'),
    _MenuEntry.tile(icon: Icons.currency_rupee,                label: LanguageService.t('charge_setup'),       route: '/admin/charge-setup',    push: true),
    _MenuEntry.tile(icon: Icons.event_note_outlined,           label: LanguageService.t('one_time_charges'),   route: '/admin/one-time-charges', push: true),
    _MenuEntry.tile(icon: Icons.savings_outlined,               label: LanguageService.t('wallet'),   route: '/admin/wallet',          push: true),
    _MenuEntry.tile(icon: Icons.cell_tower,                     label: LanguageService.t('other_income'),      route: '/admin/other-income',    push: true),
    _MenuEntry.tile(icon: Icons.badge_outlined,                label: LanguageService.t('vendors_payees'),   route: '/admin/vendors',         push: true),
    _MenuEntry.tile(icon: Icons.badge_outlined,                 label: LanguageService.t('fund_treasurer'), route: '/admin/treasurer', push: true),

    // ── PAYMENT ────────────────────────────────────────────────────────
    // UPI, Bank Transfer. Approvals now lives as a Quick Action above;
    // Payment Gateways is intentionally NOT in this menu - managed
    // exclusively from Super Admin now.
    _MenuEntry.section('PAYMENT'),
    _MenuEntry.tile(icon: Icons.qr_code,                        label: LanguageService.t('upi'),               route: '/admin/upi-settings',    push: true, module: 'upi'),
    _MenuEntry.tile(icon: Icons.account_balance_outlined,       label: LanguageService.t('bank_transfer'),     route: '/admin/bank-transfer-settings', push: true, module: 'bank_transfer'),

    // ── REPORTS ────────────────────────────────────────────────────────
    // Complaints Report, Occupancy Report. (Financial Report now lives as
    // a Quick Action above.)
    _MenuEntry.section('REPORTS'),
    _MenuEntry.tile(icon: Icons.assignment_outlined,           label: LanguageService.t('complaints'),         route: '/admin/reports/complaints',  push: true, module: 'reports_complaints'),
    _MenuEntry.tile(icon: Icons.pie_chart_outline,             label: LanguageService.t('occupancy'),          route: '/admin/reports/occupancy',   push: true, module: 'reports_occupancy'),

    // ── SETTINGS ───────────────────────────────────────────────────────
    // Branding, Meet Live, Notification Settings, Bulk Notify. SMS
    // Gateways / Payment Gateways intentionally removed - Super Admin
    // manages both now.
    _MenuEntry.section('SETTINGS'),
    _MenuEntry.tile(icon: Icons.palette_outlined,              label: LanguageService.t('branding'),           route: '/admin/branding',        push: true),
    // Opt-in per apartment (Super Admin > Community Meeting Settings) - see
    // the matching resident-menu entry for why this uses BrandingService
    // directly instead of `module:`.
    if (BrandingService.communityMeetingEnabled)
      _MenuEntry.tile(icon: Icons.video_camera_front_outlined, label: LanguageService.t('community_meeting'), route: '/admin/community-meeting', push: true),
    _MenuEntry.tile(icon: Icons.notifications_outlined,        label: LanguageService.t('bulk_notify'),        route: '/admin/bulk-notify',     push: true),

    // ── ACCOUNT ────────────────────────────────────────────────────────
    _MenuEntry.section('ACCOUNT'),
    _MenuEntry.tile(icon: Icons.credit_card,                   label: LanguageService.t('my_subscription'),    route: '/admin/subscription',    push: true),
    _MenuEntry.tile(icon: Icons.card_giftcard_outlined,        label: LanguageService.t('refer_a_society'),    route: '/admin/referral',        push: true, module: 'referral'),
    _MenuEntry.tile(icon: Icons.support_agent_outlined,        label: LanguageService.t('support_tickets'),    route: '/admin/tickets',         push: true),
  ];

  // ── COMPANY ADMIN: company-level menu (no apartment selected) ───────────
  List<_MenuEntry> _companyMenu() => [
    _MenuEntry.tile(icon: Icons.dashboard_outlined,   label: LanguageService.t('company_dashboard'), route: '/company/dashboard', push: false),
    _MenuEntry.section('MANAGE'),
    _MenuEntry.tile(icon: Icons.business_outlined,    label: LanguageService.t('my_apartments'),     route: '/company/dashboard', push: false),
    _MenuEntry.tile(icon: Icons.apartment,            label: LanguageService.t('manage_apartments'), route: '/company/apartments', push: true),
    _MenuEntry.tile(icon: Icons.person_add_alt_outlined, label: LanguageService.t('apartment_admins'), route: '/company/apt-admins', push: true),
    _MenuEntry.tile(icon: Icons.sell_outlined,        label: LanguageService.t('my_plans'),          route: '/company/plans',     push: true),
    _MenuEntry.tile(icon: Icons.receipt_long,         label: LanguageService.t('subscriptions'),     route: '/company/subscriptions', push: true),
    _MenuEntry.section('REPORTS'),
    _MenuEntry.tile(icon: Icons.bar_chart_outlined,   label: LanguageService.t('company_report'),    route: '/company/report',    push: true),
    _MenuEntry.section('SETTINGS'),
    _MenuEntry.tile(icon: Icons.settings_outlined,    label: LanguageService.t('company_profile'),  route: '/company/profile',    push: true),
    _MenuEntry.tile(icon: Icons.account_balance_outlined, label: LanguageService.t('bank_details'), route: '/company/bank-details', push: true),
  ];

  // ── COMPANY ADMIN: inside a specific apartment - same as an
  // apartment_admin's menu, plus a way back out to the Company level. ─────
  List<_MenuEntry> _companyInsideApartmentMenu() => [
    _MenuEntry.tile(
      icon: Icons.swap_horiz,
      label: LanguageService.t('switch_apartment'),
      route: '/company/dashboard',
      push: false,
      beforeNavigate: () async {
        await AuthService().clearSelectedApartmentId();
        await BrandingService.load();
      },
    ),
    // isApartmentAdmin: false - Rules editing is Apartment Admin-only (per
    // backend RulesApiController::update), so Company Admin doesn't get
    // the "Rules" tile here even though they otherwise see the same menu.
    ..._adminMenu(isApartmentAdmin: false),
  ];

  // ── SUPER ADMIN: platform-wide menu (MVP) ────────────────────────────────
  List<_MenuEntry> _superAdminMenu() => [
    _MenuEntry.tile(icon: Icons.dashboard_outlined,      label: LanguageService.t('dashboard'),        route: '/super-admin/dashboard',     push: false),
    _MenuEntry.section('MANAGE'),
    _MenuEntry.tile(icon: Icons.corporate_fare,          label: LanguageService.t('companies'),        route: '/super-admin/companies',     push: true),
    _MenuEntry.tile(icon: Icons.business_outlined,       label: LanguageService.t('apartments'),       route: '/super-admin/apartments',    push: true),
    _MenuEntry.tile(icon: Icons.sell_outlined,           label: LanguageService.t('plans'),            route: '/super-admin/plans',         push: true),
    _MenuEntry.tile(icon: Icons.person_add_alt_outlined, label: LanguageService.t('apartment_admins'), route: '/super-admin/apt-admins',    push: true),
    _MenuEntry.section('BILLING'),
    _MenuEntry.tile(icon: Icons.receipt_long,            label: LanguageService.t('subscriptions'),    route: '/super-admin/subscriptions', push: true),
  ];

  List<_MenuEntry> _secMenu() => [
    _MenuEntry.tile(icon: Icons.dashboard_outlined,            label: LanguageService.t('dashboard'),          route: '/security/dashboard',    push: false),
    _MenuEntry.section('GATE CONTROL'),
    _MenuEntry.tile(icon: Icons.badge_outlined,                label: LanguageService.t('visitors'),           route: '/security/visitors',     push: true, module: 'visitors'),
    _MenuEntry.tile(icon: Icons.people_outline,                label: LanguageService.t('resident_directory'), route: '/security/residents',    push: true),
    _MenuEntry.section('OPERATIONS'),
    _MenuEntry.tile(icon: Icons.local_parking_outlined,        label: LanguageService.t('parking'),            route: '/security/parking',      push: true, module: 'parking'),
    _MenuEntry.tile(icon: Icons.chat_bubble_outline,           label: LanguageService.t('complaints'),         route: '/security/complaints',   push: true, module: 'complaints'),
    _MenuEntry.tile(icon: Icons.event_available_outlined,      label: LanguageService.t('facility_bookings'),  route: '/security/bookings',     push: true, module: 'bookings'),
  ];

  List<_MenuEntry> _resMenu({bool isActiveTreasurer = false}) => [
    _MenuEntry.tile(icon: Icons.dashboard_outlined,            label: LanguageService.t('dashboard'),          route: '/dashboard',             push: false),
    _MenuEntry.section('FINANCE'),
    _MenuEntry.tile(icon: Icons.receipt_long,                  label: LanguageService.t('my_bills'),           route: '/billing',               push: true),
    _MenuEntry.tile(icon: Icons.account_balance_wallet_outlined, label: LanguageService.t('wallet'), route: '/wallet',                push: true),
    // Treasurer & Fund Allocation module - only shown when the login/profile
    // response flagged this resident as a currently-active Treasurer. See
    // AuthController::respondWithToken() / ResidentApiController::profile().
    if (isActiveTreasurer)
      _MenuEntry.tile(icon: Icons.account_balance_outlined,    label: LanguageService.t('my_fund'), route: '/my-fund',              push: true),
    _MenuEntry.tile(icon: Icons.pie_chart_outline,             label: LanguageService.t('society_finances'),   route: '/financial',             push: true, module: 'financial'),
    _MenuEntry.section('OPERATIONS'),
    _MenuEntry.tile(icon: Icons.chat_bubble_outline,           label: LanguageService.t('my_complaints'),      route: '/complaints',            push: true, module: 'complaints'),
    _MenuEntry.tile(icon: Icons.add_comment_outlined,          label: LanguageService.t('raise_complaint'),    route: '/complaints/raise',      push: true, module: 'complaint_raise'),
    _MenuEntry.tile(icon: Icons.badge_outlined,                label: LanguageService.t('my_visitors'),        route: '/visitors',              push: true, module: 'visitors'),
    _MenuEntry.tile(icon: Icons.local_parking_outlined,        label: LanguageService.t('parking'),            route: '/resident/parking',      push: true, module: 'parking'),
    _MenuEntry.tile(icon: Icons.forum_outlined,                label: LanguageService.t('community_chat'),     route: '/chat',                  push: true, module: 'chat'),
    // Opt-in per apartment (Super Admin > Community Meeting Settings) -
    // uses BrandingService directly rather than `module:` since its
    // enablement isn't an ApartmentModuleCatalog on/off toggle. See
    // MenuSetting::resolveQuickAction server-side for the same reasoning.
    if (BrandingService.communityMeetingEnabled)
      _MenuEntry.tile(icon: Icons.video_camera_front_outlined, label: LanguageService.t('community_meeting'),  route: '/community-meeting',     push: true),
    _MenuEntry.section('INFO'),
    _MenuEntry.tile(icon: Icons.campaign_outlined,             label: LanguageService.t('notices'),            route: '/notices',               push: true, module: 'notices'),
    _MenuEntry.tile(icon: Icons.meeting_room_outlined,         label: LanguageService.t('facilities'),         route: '/facilities',            push: true, module: 'facilities'),
    _MenuEntry.tile(icon: Icons.event_note_outlined,           label: LanguageService.t('my_bookings'),        route: '/my-bookings',           push: true, module: 'my_bookings'),
    _MenuEntry.tile(icon: Icons.contact_phone_outlined,        label: LanguageService.t('emergency_numbers'),  route: '/emergency-numbers',     push: true, module: 'emergency_numbers'),
    _MenuEntry.tile(icon: Icons.file_present_outlined,         label: LanguageService.t('agreements'),         route: '/agreements',            push: true, module: 'agreements'),
    _MenuEntry.tile(icon: Icons.menu_book_outlined,             label: LanguageService.t('rules'),              route: '/rules',                 push: true),
    _MenuEntry.tile(icon: Icons.card_giftcard_outlined,        label: LanguageService.t('referral'),           route: '/referral',              push: true, module: 'referral'),
    _MenuEntry.tile(icon: Icons.notifications_outlined,        label: LanguageService.t('notifications'),      route: '/notifications',         push: true),
  ];
}

/// Plain-data description of one Drawer row, resolved to a Widget only
/// after filtering (see AppDrawer._filter/_render). Keeping this as data
/// first - rather than building Widgets directly - is what lets us drop
/// disabled-module tiles and their now-empty section headers in one pass.
class _MenuEntry {
  final IconData? icon;
  final String label;
  final String? route;
  final bool push;
  final String? module; // ApartmentModuleCatalog key gating this tile, if any
  final bool isSection;
  final Future<void> Function()? beforeNavigate;

  const _MenuEntry.tile({
    required this.icon,
    required this.label,
    required this.route,
    required this.push,
    this.module,
    this.beforeNavigate,
  }) : isSection = false;

  const _MenuEntry.section(this.label)
      : icon = null, route = null, push = false, module = null, isSection = true, beforeNavigate = null;
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String name, email, role;
  const _Header({required this.name, required this.email, required this.role});
  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.sidebar;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 14,
          left: 16, right: 16, bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [primary, BrandingService.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30, height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: BrandingService.appLogoUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.network(
                      BrandingService.appLogoUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.apartment, color: primary, size: 15),
                    ),
                  )
                : Icon(Icons.apartment, color: primary, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(BrandingService.appName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(width: 6),
                _Badge(role),
              ]),
              const SizedBox(height: 2),
              Text(email,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _Sec extends StatelessWidget {
  final String label;
  const _Sec(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Text(label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 0.8, color: Colors.grey[500])),
  );
}

/// [push] = true  → context.push (sub-screens, back button works)
/// [push] = false → context.go   (home/dashboard, resets stack)
class _Tile extends StatelessWidget {
  final IconData icon;
  final String   label, route;
  final bool     push;
  final Future<void> Function()? beforeNavigate;
  const _Tile({required this.icon, required this.label, required this.route, required this.push, this.beforeNavigate});

  @override
  Widget build(BuildContext context) {
    final current = GoRouterState.of(context).matchedLocation;
    final active  = current == route;
    final primary = BrandingService.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? primary.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(icon, size: 19, color: active ? primary : Colors.grey[600]),
          title: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  color: active ? primary : Colors.black87)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () async {
            Navigator.pop(context); // close drawer first
            if (beforeNavigate != null) await beforeNavigate!();
            if (!context.mounted) return;
            if (push) {
              context.push(route);
            } else {
              context.go(route);
            }
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String role;
  const _Badge(this.role);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'apartment_admin' => ('Admin', Colors.orange),
      'company_admin'   => ('Company', Colors.deepPurple),
      'super_admin'     => ('Super Admin', Colors.red),
      'security'        => ('Security', Colors.blue),
      _                 => ('Resident', Colors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _DrawerData {
  final Map<String, dynamic> user;
  final String effectiveRole;
  final bool hasDualRole;
  final int? selectedApartmentId;
  _DrawerData({required this.user, required this.effectiveRole, required this.hasDualRole, this.selectedApartmentId});
}
