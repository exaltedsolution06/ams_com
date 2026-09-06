import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../services/language_service.dart';
import '../../services/branding_service.dart';
import '../../utils/type_helpers.dart';

/// One-stop "Approvals" screen for everything an Apartment Admin needs to
/// review: pending Facility Bookings, Pending Payments, Pending One-Time
/// Charge claims, and Pending Advance/Wallet claims - each its own tab, so
/// there's a single menu entry instead of four separate pending-approval
/// screens.
///
/// [initialTab] lets other screens deep-link straight into a specific
/// section (0=Bookings, 1=Payments, 2=One-Time Charges, 3=Wallet) - e.g.
/// the dashboard's wallet-approvals banner opens straight to the Wallet tab.
class AdminApprovalsScreen extends StatefulWidget {
  final int initialTab;
  const AdminApprovalsScreen({super.key, this.initialTab = 0});
  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Fixed logical order/index (0=Bookings, 1=Payments, 2=One-Time Charges,
  // 3=Wallet) - matches what every call site (main.dart routes,
  // admin_wallet_screen.dart) already hardcodes via widget.initialTab.
  // 'visible' hides a tab whose module has been switched off for this
  // apartment under Super Admin > All Branding > Assign Menu - without
  // that, a disabled module's tab (e.g. Facility Booking) kept showing
  // here even though its own menu entry was correctly hidden elsewhere.
  // Billing (Payments/One-Time Charges/Wallet) isn't in
  // ApartmentModuleCatalog's toggleable list - a society can never fully
  // switch billing off - so only Bookings is ever conditionally hidden.
  late final List<_ApprovalTabSpec> _specs = [
    _ApprovalTabSpec('bookings', LanguageService.t('facility_bookings'), const _BookingsApprovalTab(),
        visible: !BrandingService.isModuleOff('facilities')),
    _ApprovalTabSpec('payments', LanguageService.t('pending_payments'), const _PaymentsApprovalTab()),
    _ApprovalTabSpec('charges', LanguageService.t('one_time_charges'), const _OneTimeChargesApprovalTab()),
    _ApprovalTabSpec('wallet', LanguageService.t('wallet'), const _WalletApprovalTab()),
  ];
  late final List<_ApprovalTabSpec> _visibleSpecs = _specs.where((s) => s.visible).toList();

  @override
  void initState() {
    super.initState();
    // Map the incoming logical index (fixed at every call site) to its
    // position among only the currently-visible tabs. Falls back to the
    // first visible tab if the requested one has been hidden (e.g. a deep
    // link straight to Bookings while Facility Booking is switched off).
    final requested = widget.initialTab.clamp(0, _specs.length - 1);
    final requestedKey = _specs[requested].key;
    final resolvedIndex = _visibleSpecs.indexWhere((s) => s.key == requestedKey);
    _tab = TabController(
      length: _visibleSpecs.length,
      vsync: this,
      initialIndex: resolvedIndex >= 0 ? resolvedIndex : 0,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('approvals')),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [for (final s in _visibleSpecs) Tab(text: s.label)],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [for (final s in _visibleSpecs) s.tab],
      ),
    );
  }
}

/// One entry in the Approvals tab bar - pairs a stable key (for
/// initialTab-index remapping) with its label/content and whether this
/// apartment currently has that module switched on.
class _ApprovalTabSpec {
  final String key;
  final String label;
  final Widget tab;
  final bool visible;
  const _ApprovalTabSpec(this.key, this.label, this.tab, {this.visible = true});
}

/// Shared "PENDING" pill used by every tab so all four sections look and
/// behave the same.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(LanguageService.t('pending_2'), style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

/// Shared empty-state used by every tab.
class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(this.message);
  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 120),
        const Icon(Icons.task_alt, size: 60, color: Colors.grey),
        const SizedBox(height: 12),
        Center(child: Text(message, style: const TextStyle(color: Colors.grey))),
      ]);
}

/// Shared approve/reject action row used by every tab.
class _ApprovalActions extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _ApprovalActions({required this.onApprove, required this.onReject});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: onReject,
            icon: const Icon(Icons.close, size: 16),
            label: Text(LanguageService.t('reject')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: onApprove,
            icon: const Icon(Icons.check, size: 16),
            label: Text(LanguageService.t('approve')),
          ),
        ),
      ]);
}

Future<String?> _promptRejectReason(BuildContext context, {required String title}) {
  return AmsDialog.promptText(
    context,
    title: title,
    label: LanguageService.t('reason_shown_to_resident'),
    icon: Icons.block_rounded,
    danger: true,
    confirmText: LanguageService.t('reject'),
    cancelText: LanguageService.t('cancel'),
    maxLines: 3,
  );
}

// ─────────────────────────── Facility Bookings ───────────────────────────

class _BookingsApprovalTab extends StatefulWidget {
  const _BookingsApprovalTab();
  @override
  State<_BookingsApprovalTab> createState() => _BookingsApprovalTabState();
}

class _BookingsApprovalTabState extends State<_BookingsApprovalTab> {
  List _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().get('/admin/bookings?status=pending');
      final data = res['data'];
      setState(() {
        _bookings = (data is Map ? data['data'] : data) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _act(Map b, String action, {String? reason}) async {
    try {
      await ApiService().post('/admin/bookings/${b['id']}/action', {
        'action': action,
        if (reason != null) 'rejection_reason': reason,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _approve(Map b) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('approve_booking_q'),
      message: 'Approve this booking for ${(b['facility'] as Map?)?['name'] ?? ''}?',
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      confirmText: LanguageService.t('approve'),
    );
    if (confirm != true) return;
    _act(b, 'approve');
  }

  Future<void> _reject(Map b) async {
    final reason = await _promptRejectReason(context, title: LanguageService.t('reject_booking'));
    if (reason == null) return;
    _act(b, 'reject', reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/admin/bookings'),
                icon: const Icon(Icons.history, size: 16),
                label: Text(LanguageService.t('view_all_bookings')),
              ),
            ),
          ),
          if (_bookings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 100),
              child: Column(children: [
                const Icon(Icons.task_alt, size: 60, color: Colors.grey),
                const SizedBox(height: 12),
                Text(LanguageService.t('no_bookings_awaiting_approval'), style: const TextStyle(color: Colors.grey)),
              ]),
            )
          else
            ..._bookings.map((b) {
              final facility = (b['facility'] as Map?);
              final user = (b['user'] as Map?);
              final fee = (facility?['booking_fee'] ?? 0);
              final startTime = (b['start_time'] ?? '').toString();
              final timeLabel = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(facility?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          const _PendingBadge(),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          '${user?['name'] ?? ''}  ·  ${friendlyDate(b['booking_date'])}  ·  $timeLabel',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (fee is num && fee > 0) ? '${BrandingService.currencySymbol}${fee.toStringAsFixed(2)} booking fee' : LanguageService.t('free'),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _ApprovalActions(onApprove: () => _approve(b), onReject: () => _reject(b)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Payments ─────────────────────────────────

class _PaymentsApprovalTab extends StatefulWidget {
  const _PaymentsApprovalTab();
  @override
  State<_PaymentsApprovalTab> createState() => _PaymentsApprovalTabState();
}

class _PaymentsApprovalTabState extends State<_PaymentsApprovalTab> {
  List _payments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().get('/admin/payments/pending');
      setState(() {
        _payments = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _approve(Map p) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('approve_payment_q'),
      message: 'Confirm ${BrandingService.currencySymbol}${p['amount']} payment for bill ${p['bill']?['bill_number'] ?? ''}? This will credit the bill.',
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      confirmText: LanguageService.t('approve'),
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/admin/payments/${p['id']}/approve', {});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _reject(Map p) async {
    final reason = await _promptRejectReason(context, title: LanguageService.t('reject_payment'));
    if (reason == null) return;
    try {
      await ApiService().post('/admin/payments/${p['id']}/reject', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)));
    return RefreshIndicator(
      onRefresh: _load,
      child: _payments.isEmpty
          ? _EmptyState(LanguageService.t('no_payments_awaiting_confirmation'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _payments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = _payments[i];
                final bill = (p['bill'] as Map?);
                final flat = (bill?['flat'] as Map?);
                final user = (p['user'] as Map?);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('${BrandingService.currencySymbol}${p['amount']}  ·  ${(p['payment_method'] ?? '').toString().replaceAll('_', ' ')}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          const _PendingBadge(),
                        ]),
                        const SizedBox(height: 6),
                        Text('${user?['name'] ?? ''}  ·  Flat ${flat?['flat_number'] ?? ''}  ·  Bill ${bill?['bill_number'] ?? ''}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        if (p['notes'] != null && p['notes'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(p['notes'], style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                          ),
                        const SizedBox(height: 10),
                        _ApprovalActions(onApprove: () => _approve(p), onReject: () => _reject(p)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ───────────────────────────── One-Time Charges ───────────────────────────

class _OneTimeChargesApprovalTab extends StatefulWidget {
  const _OneTimeChargesApprovalTab();
  @override
  State<_OneTimeChargesApprovalTab> createState() => _OneTimeChargesApprovalTabState();
}

class _OneTimeChargesApprovalTabState extends State<_OneTimeChargesApprovalTab> {
  List _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().get('/admin/one-time-charges/pending-approvals');
      setState(() {
        _items = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _approve(Map item) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('approve_payment_q'),
      message: 'Confirm ${BrandingService.currencySymbol}${item['outstanding'] ?? item['amount']} payment for "${(item['charge'] as Map?)?['title'] ?? ''}"?',
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      confirmText: LanguageService.t('approve'),
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/admin/one-time-charges/items/${item['id']}/approve', {});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _reject(Map item) async {
    final reason = await _promptRejectReason(context, title: LanguageService.t('reject_payment'));
    if (reason == null) return;
    try {
      await ApiService().post('/admin/one-time-charges/items/${item['id']}/reject', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)));
    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? _EmptyState(LanguageService.t('no_payments_awaiting_confirmation'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = _items[i];
                final charge = (item['charge'] as Map?);
                final flat = (item['flat'] as Map?);
                final user = (item['user'] as Map?);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                                '${BrandingService.currencySymbol}${item['outstanding'] ?? item['amount']}  ·  ${(item['payment_method'] ?? '').toString().replaceAll('_', ' ')}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          const _PendingBadge(),
                        ]),
                        const SizedBox(height: 6),
                        Text('${user?['name'] ?? ''}  ·  Flat ${flat?['flat_number'] ?? ''}  ·  ${charge?['title'] ?? ''}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 10),
                        _ApprovalActions(onApprove: () => _approve(item), onReject: () => _reject(item)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ────────────────────────── Advance / Wallet ───────────────────────────

class _WalletApprovalTab extends StatefulWidget {
  const _WalletApprovalTab();
  @override
  State<_WalletApprovalTab> createState() => _WalletApprovalTabState();
}

class _WalletApprovalTabState extends State<_WalletApprovalTab> {
  List _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/admin/wallet/pending-approvals');
      setState(() {
        _transactions = res['data']['data'] ?? res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _approve(Map t) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('approve_advance_payment_q'),
      message: "Confirm ${BrandingService.currencySymbol}${t['amount']} claimed by ${t['user']?['name'] ?? ''}? It will be credited and auto-adjusted against any dues across all their flats.",
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      confirmText: LanguageService.t('approve'),
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/admin/wallet/transactions/${t['id']}/approve', {});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _reject(Map t) async {
    final reason = await _promptRejectReason(context, title: LanguageService.t('reject_advance_claim'));
    if (reason == null) return;
    try {
      await ApiService().post('/admin/wallet/transactions/${t['id']}/reject', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: _transactions.isEmpty
          ? _EmptyState(LanguageService.t('no_advance_requests_awaiting_confirmation'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _transactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final t = _transactions[i];
                final user = t['user'] as Map?;
                final flats = (user?['flats'] as List?) ?? [];
                final flatLabel = flats.isNotEmpty ? flats.map((f) => f['flat_number']).join(', ') : '—';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('${BrandingService.currencySymbol}${t['amount']}  ·  ${(t['payment_method'] ?? '').toString().replaceAll('_', ' ')}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          const _PendingBadge(),
                        ]),
                        const SizedBox(height: 6),
                        Text('${user?['name'] ?? ''}  ·  Flat $flatLabel', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        if (t['notes'] != null && t['notes'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(t['notes'], style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                          ),
                        const SizedBox(height: 10),
                        _ApprovalActions(onApprove: () => _approve(t), onReject: () => _reject(t)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
