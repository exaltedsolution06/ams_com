import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/app_refresh.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/curved_header.dart';
import '../../services/menu_config_service.dart';
import '../../services/tile_color_palette.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/announcement_banner.dart';
import '../../widgets/dashboard_graphics.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;
  List<QuickActionItem>? _quickActions;
  ResolvedBottomNav? _bottomNav;

  @override
  void initState() {
    super.initState();
    _load();
    // Popping back to this dashboard (e.g. from My Subscription after
    // changing the plan) doesn't re-run initState, so without this the
    // Quick Action/Bottom Nav "locked" flags here would stay stale until
    // a full logout/login. AdminSubscriptionScreen calls AppRefresh.bump()
    // after a successful plan change - listening here re-fetches
    // MenuConfigService so this screen reflects the new plan immediately.
    AppRefresh.tick.addListener(_onAppRefresh);
  }

  @override
  void dispose() {
    AppRefresh.tick.removeListener(_onAppRefresh);
    super.dispose();
  }

  void _onAppRefresh() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api   = ApiService();
      final me    = await api.get('/me');
      final stats = await api.get('/admin/dashboard');
      final menu  = await MenuConfigService.load('apartment_admin');
      setState(() {
        _user    = (me['data']    as Map?)?.cast<String, dynamic>();
        _stats   = (stats['data'] as Map?)?.cast<String, dynamic>();
        _quickActions = menu?.quickActions;
        _bottomNav    = menu?.bottomNav;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary   = BrandingService.primary;
    final adminName = (_user?['name'] as String? ?? '').split(' ').first;
    final aptName   = (_stats?['apartment'] as Map?)?['name'] as String? ?? 'Apartment';

    return Scaffold(
      key: _scaffoldKey,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bottomNav != null
              ? AppBottomNav(
                  currentRoute: '/admin/dashboard',
                  // Same treatment as the resident dashboard: narrower pill,
                  // shifted right, so the voice mic has clear space to dock
                  // in on the left by default.
                  leftInset: (BrandingService.voiceMicEnabled && AuthService.wantsVoiceMic) ? 64 : 12,
                  items: _bottomNav!.flanking
                      .map((n) => NavItem(icon: n.icon, label: n.label, route: n.route, isHome: n.isHome, locked: n.locked))
                      .toList(),
                  centerItem: NavItem(icon: _bottomNav!.center.icon, label: _bottomNav!.center.label, route: _bottomNav!.center.route, locked: _bottomNav!.center.locked),
                )
              : AppBottomNav(
                  currentRoute: '/admin/dashboard',
                  leftInset: (BrandingService.voiceMicEnabled && AuthService.wantsVoiceMic) ? 64 : 12,
                  items: [
                    NavItem(icon: Icons.home_rounded,       label: LanguageService.t('home'),      route: '/admin/dashboard', isHome: true),
                    NavItem(icon: Icons.people_rounded,      label: LanguageService.t('residents'), route: '/admin/residents'),
                    NavItem(icon: Icons.badge_rounded,       label: LanguageService.t('visitors'),  route: '/admin/visitors'),
                    NavItem(icon: Icons.person_rounded,      label: LanguageService.t('profile'),   route: '/profile'),
                  ],
                  centerItem: NavItem(icon: Icons.chat_bubble_rounded, label: LanguageService.t('complaints'), route: '/admin/complaints'),
                ),
        ],
      ),
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CurvedHeader(
                    height: 168,
                    colors: [BrandingService.appBanner, BrandingService.sidebar],
                    // Same "clean, mostly-square card" treatment as the
                    // resident dashboard header - see its comment.
                    bottomRadius: 24,
                    child: Stack(children: [
                      const Positioned.fill(child: HeaderGeometricPattern()),
                      SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            // The Scaffold's `drawer:` was only ever reachable by an
                            // edge-swipe gesture on this screen - there was no visible
                            // button for it, since this header replaces the AppBar
                            // that would normally show one automatically.
                            IconButton(
                              icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                              padding: EdgeInsets.zero,
                              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                            ),
                            if (_user?['role'] == 'apartment_admin' && _user?['flat_id'] != null) ...[
                              TextButton.icon(
                                onPressed: () async {
                                  await AuthService().setViewMode('resident');
                                  if (context.mounted) context.go('/dashboard');
                                },
                                icon: const Icon(Icons.swap_horiz_rounded, color: Colors.amber, size: 16),
                                label: Text(LanguageService.t('resident_view'), style: TextStyle(color: Colors.amber, fontSize: 11.5, fontWeight: FontWeight.w600)),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const Spacer(),
                            ] else
                              const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 21),
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                              padding: EdgeInsets.zero,
                              onPressed: () => context.push('/notifications'),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                            Expanded(
                              child: Text('Hello, $adminName 👋',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                            ),
                            Icon(Icons.admin_panel_settings_rounded, color: Colors.white.withOpacity(0.8), size: 17),
                          ]),
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(aptName, maxLines: 1,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    ]),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _error != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Column(children: [
                                const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey),
                                const SizedBox(height: 12),
                                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: Text(LanguageService.t('retry')),
                                  onPressed: _load,
                                ),
                              ]),
                            )
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const AnnouncementBanner(),
                              if (_stats?['subscription'] != null) ...[
                                _buildSubscriptionBanner(_stats!['subscription'] as Map),
                                const SizedBox(height: 16),
                              ] else
                                const SizedBox(height: 40),
                              if ((_stats?['pending_wallet_approvals'] ?? 0) > 0) ...[
                                _buildWalletApprovalsBanner(_stats!['pending_wallet_approvals'] as int),
                                const SizedBox(height: 16),
                              ],
                              Row(children: [
                                Container(width: 4, height: 16, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
                                const SizedBox(width: 8),
                                Text(LanguageService.t('overview'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ]),
                              const SizedBox(height: 12),
                              _buildStatsGrid(),
                              const SizedBox(height: 20),
                              Row(children: [
                                Container(width: 4, height: 16, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
                                const SizedBox(width: 8),
                                Text(LanguageService.t('insights'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ]),
                              const SizedBox(height: 10),
                              _buildInsights(),
                              const SizedBox(height: 20),
                              Row(children: [
                                Container(width: 4, height: 16, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
                                const SizedBox(width: 8),
                                Text(LanguageService.t('quick_actions'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ]),
                              const SizedBox(height: 10),
                              _buildActions(),
                              const SizedBox(height: 8),
                            ]),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }


  Widget _buildSubscriptionBanner(Map sub) {
    final pending = sub['pending_approval'] == true;
    final days = sub['days_until_expiry'] as int?;
    final showWarning = pending || (days != null && days <= 30);
    if (!showWarning) return const SizedBox.shrink();

    final urgent = !pending && days != null && days <= 7;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: urgent ? Colors.red.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: urgent ? Colors.red.shade200 : Colors.amber.shade300),
      ),
      child: Row(children: [
        Icon(pending ? Icons.hourglass_top : Icons.warning_amber_rounded,
            color: urgent ? Colors.red : Colors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            pending
                ? 'Your plan change is pending Super Admin approval.'
                : '"${sub['plan_name']}" plan expires in $days day(s). Renew to avoid losing access.',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () => context.push('/admin/subscription'),
          child: Text(LanguageService.t('view'), style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildWalletApprovalsBanner(int count) {
    return GestureDetector(
      onTap: () => context.push('/admin/approvals?tab=3'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(children: [
          const Icon(Icons.hourglass_top, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count advance wallet ${count == 1 ? 'request' : 'requests'} awaiting your approval.',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final s = _stats ?? {};
    final items = [
      {'label': 'Total Flats',    'value': (s['total_flats'] as num?) ?? 0,           'icon': Icons.home_outlined,       'color': Colors.blue},
      {'label': 'Residents',      'value': (s['total_residents'] as num?) ?? 0,       'icon': Icons.people_outline,      'color': Colors.green},
      {'label': 'Pending Bills',  'value': (s['pending_bills_count'] as num?) ?? 0,   'icon': Icons.receipt_outlined,    'color': Colors.orange},
      {'label': 'Dues',           'value': double.tryParse(s['pending_amount']?.toString() ?? '') ?? 0, 'icon': Icons.currency_rupee, 'color': Colors.red, 'format': _fmtAmt},
      {'label': 'Complaints',     'value': (s['open_complaints'] as num?) ?? 0,       'icon': Icons.chat_bubble_outline, 'color': Colors.purple},
      {'label': 'Visitors Today', 'value': (s['visitors_today'] as num?) ?? 0,        'icon': Icons.badge_outlined,      'color': Colors.teal},
      {'label': 'Awaiting',       'value': (s['pending_visitors'] as num?) ?? 0,      'icon': Icons.pending_outlined,    'color': Colors.amber},
      {'label': 'Vacant Flats',   'value': (s['vacant_flats'] as num?) ?? 0,          'icon': Icons.house_outlined,      'color': Colors.grey},
      {'label': 'Wallet Approvals', 'value': (s['pending_wallet_approvals'] as num?) ?? 0, 'icon': Icons.account_balance_wallet_outlined, 'color': Colors.indigo, 'route': '/admin/approvals?tab=3'},
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.9,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item  = items[i];
        final route = item['route'] as String?;
        return GradientStatTile(
          label: item['label'] as String,
          value: item['value'] as num,
          icon: item['icon'] as IconData,
          color: item['color'] as Color,
          format: item['format'] as String Function(num)?,
          onTap: route != null ? () => context.push(route) : null,
        );
      },
    );
  }

  Widget _buildInsights() {
    final s = _stats ?? {};
    final total   = (s['total_flats'] as num?)?.toInt() ?? 0;
    final vacant  = (s['vacant_flats'] as num?)?.toInt() ?? 0;
    final occupied = (total - vacant).clamp(0, total);
    final rate = total > 0 ? occupied / total : 0.0;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: InsightCard(
          child: Column(children: [
            StatRing(
              percent: rate,
              color: BrandingService.primary,
              center: Text('${(rate * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: BrandingService.primary)),
            ),
            const SizedBox(height: 8),
            Text(LanguageService.t('occupancy'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
            Text('$occupied of $total flats', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: InsightCard(
          child: Column(children: [
            Text(LanguageService.t('this_week'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 6),
            ComparisonBarChart(items: [
              BarChartItem(label: LanguageService.t('bills'), value: (s['pending_bills_count'] as num?) ?? 0, color: Colors.orange),
              BarChartItem(label: LanguageService.t('compl'), value: (s['open_complaints'] as num?) ?? 0, color: Colors.purple),
              BarChartItem(label: LanguageService.t('visitors'), value: (s['pending_visitors'] as num?) ?? 0, color: Colors.amber.shade700),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildActions() {
    // Prefer the Super Admin's resolved allocation; fall back to the app's
    // original hard-coded set for apartments that haven't been configured
    // yet or if the fetch failed.
    // 50-shade no-repeat palette (see TileColorPalette) - the old 8-color
    // list cycled back to the start once an apartment had more than 8
    // Quick Action items configured (Super Admin > Menu Config).
    final List<Map<String, dynamic>> actions;
    if (_quickActions != null) {
      final colors = TileColorPalette.forCount(_quickActions!.length, seed: 202);
      actions = List.generate(_quickActions!.length, (i) {
        final item = _quickActions![i];
        return {'label': item.label, 'icon': item.icon, 'route': item.route, 'color': colors[i], 'locked': item.locked};
      });
    } else {
      actions = [
        {'label': 'Residents',  'icon': Icons.people_outline,      'route': '/admin/residents',  'color': BrandingService.primary},
        {'label': 'Bills',      'icon': Icons.receipt_long,        'route': '/admin/bills',      'color': BrandingService.accent},
        {'label': 'Complaints', 'icon': Icons.chat_bubble_outline, 'route': '/admin/complaints', 'color': Colors.purple},
        {'label': 'Visitors',   'icon': Icons.badge_outlined,      'route': '/admin/visitors',   'color': Colors.teal},
        {'label': 'Parking',    'icon': Icons.local_parking_outlined, 'route': '/admin/parking',  'color': Colors.indigo},
        {'label': 'Bookings',   'icon': Icons.event_available_outlined, 'route': '/admin/bookings', 'color': Colors.deepPurple},
        {'label': 'Forum',      'icon': Icons.groups_outlined,     'route': '/forum',            'color': Colors.cyan},
        {'label': 'Approvals',  'icon': Icons.fact_check_outlined, 'route': '/admin/approvals', 'color': Colors.brown},
        {'label': 'Notices',    'icon': Icons.campaign_outlined,   'route': '/admin/notices',    'color': Colors.red},
        {'label': 'Profile',    'icon': Icons.person_outline,      'route': '/profile',          'color': Colors.grey},
      ];
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 100, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.15,
      ),
      itemCount: actions.length,
      itemBuilder: (_, i) {
        final a = actions[i];
        final c = a['color'] as Color;
        final locked = a['locked'] == true;
        return GestureDetector(
          onTap: () => locked ? _showLockedNotice(a['label'] as String) : context.push(a['route'] as String),
          child: Container(
            decoration: BoxDecoration(
              // The whole tile now carries the tile's own color as a
              // gradient (previously just a small 40x40 icon box did, on
              // an otherwise plain white card) - matches the resident
              // dashboard's identical Quick Access grid.
              gradient: LinearGradient(colors: [c, c.withOpacity(0.78)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: c.withOpacity(0.28), blurRadius: 10, offset: const Offset(0,4))],
            ),
            child: Opacity(
              opacity: locked ? 0.5 : 1,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                SizedBox(
                  width: 40, height: 40,
                  child: Icon(a['icon'] as IconData, color: Colors.white, size: 26),
                ),
                if (locked)
                  Positioned(
                    right: -4, bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
                      child: const Icon(Icons.lock, size: 10, color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(a['label'] as String,
                    // White now that the tile's own color fills the whole
                    // background instead of just the icon.
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, height: 1.15),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _showLockedNotice(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label isn\'t included in your apartment\'s current plan. Contact Super Admin to upgrade.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmtAmt(num v) {
    final d = v.toDouble();
    if (d >= 100000) return '${(d/100000).toStringAsFixed(1)}L';
    if (d >= 1000)   return '${(d/1000).toStringAsFixed(1)}K';
    return d.toStringAsFixed(0);
  }
}
