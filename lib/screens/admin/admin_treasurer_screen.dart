import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/admin_screen_header.dart';
import '../../widgets/dashboard_graphics.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

/// Apartment Admin > Fund & Treasurer. See App\Services\TreasurerService
/// (Laravel) for the balance model this all reflects. Three tabs keep the
/// whole doc's "recommended menu" (Dashboard / Treasurers / Allocate /
/// Balances / Expenses / Approvals / Fund Requests / Fund Returns /
/// History / Reports) reachable from one screen instead of ~9 separate ones.
class AdminTreasurerScreen extends StatefulWidget {
  const AdminTreasurerScreen({super.key});
  @override
  State<AdminTreasurerScreen> createState() => _State();
}

class _State extends State<AdminTreasurerScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String? _error;

  Map _summary = {};
  List _treasurers = [];
  List _eligibleResidents = [];
  List _transactions = [];
  List _categories = [];
  String? _filterStatus;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ApiService();
      final dash = await api.get('/admin/treasurer/dashboard');
      final trs  = await api.get('/admin/treasurer/treasurers');
      final elig = await api.get('/admin/treasurer/eligible-residents');
      final cats = await api.get('/admin/treasurer/categories');
      await _loadTransactions();
      setState(() {
        _summary = Map.from(dash['summary'] ?? {});
        _treasurers = List.from(trs['data'] ?? []);
        _eligibleResidents = List.from(elig['data'] ?? []);
        _categories = List.from(cats['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadTransactions() async {
    final qp = <String>[];
    if (_filterStatus != null) qp.add('status=$_filterStatus');
    if (_filterType != null) qp.add('type=$_filterType');
    final res = await ApiService().get('/admin/treasurer/transactions${qp.isNotEmpty ? '?${qp.join('&')}' : ''}');
    setState(() => _transactions = List.from(res['data']?['data'] ?? []));
  }

  double _numOf(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
  String _money(dynamic v) => '${BrandingService.currencySymbol}${_numOf(v).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')),
        title: Text(LanguageService.t('fund_treasurer')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: pillTabBar(_tab, [
          LanguageService.t('dashboard').toUpperCase(),
          LanguageService.t('treasurers').toUpperCase(),
          LanguageService.t('transactions').toUpperCase(),
        ]),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: !_loading && _tab.index == 1
          ? FloatingActionButton.extended(onPressed: _showAddTreasurerSheet, icon: const Icon(Icons.person_add), label: Text(LanguageService.t('add_treasurer')), backgroundColor: BrandingService.primary)
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey), const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.grey)), const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                ]))
              : TabBarView(controller: _tab, children: [
                  _dashboardTab(),
                  _treasurersTab(),
                  _transactionsTab(),
                ]),
    );
  }

  // ── Dashboard tab ──────────────────────────────────────────────────

  Widget _dashboardTab() {
    final pending = (_summary['pending_expense_requests'] ?? 0) + (_summary['pending_fund_requests'] ?? 0);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        GradientHeroCard(
          icon: Icons.account_balance,
          title: LanguageService.t('apartment_available_balance'),
          amount: _numOf(_summary['available_balance']),
          subtitle: LanguageService.t('total_apartment_money') + ': ${_money(_summary['total_apartment_money'])}',
          color: Colors.green,
          currencySymbol: BrandingService.currencySymbol,
        ),
        const SizedBox(height: 12),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.5, children: [
          GradientStatTile(
            label: LanguageService.t('held_by_treasurers'), value: _numOf(_summary['total_held_by_treasurers']),
            icon: Icons.people, color: Colors.blue,
            format: (v) => '${BrandingService.currencySymbol}${v.toStringAsFixed(2)}',
          ),
          GradientStatTile(
            label: LanguageService.t('active_treasurers'), value: _numOf(_summary['active_treasurers_count']),
            icon: Icons.badge, color: Colors.orange,
            onTap: () => setState(() => _tab.index = 1),
          ),
        ]),
        if (pending > 0) ...[
          const SizedBox(height: 14),
          AdminListCard(
            color: Colors.orange,
            child: Row(children: [
              AdminTileIcon(icon: Icons.warning_amber_rounded, color: Colors.orange, size: 42),
              const SizedBox(width: 12),
              Expanded(child: Text('$pending ${LanguageService.t('items_awaiting_review')}', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () { setState(() { _filterStatus = 'pending'; _tab.index = 2; }); _loadTransactions(); },
                child: Text(LanguageService.t('review_now')),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Treasurers tab ─────────────────────────────────────────────────

  Widget _treasurersTab() {
    if (_treasurers.isEmpty) {
      return EmptyState(icon: Icons.people_outline, title: LanguageService.t('no_treasurers_yet'), color: BrandingService.primary);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _treasurers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final tr = _treasurers[i] as Map;
          final user = (tr['user'] as Map?) ?? {};
          final active = tr['status'] == 'active';
          final balance = _numOf(tr['current_balance']);
          final trColor = active ? Colors.green : Colors.grey;
          return AdminListCard(
            color: trColor,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AdminTileIcon(icon: Icons.person, color: trColor, size: 46),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user['name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: trColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(active ? LanguageService.t('active') : LanguageService.t('inactive'),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: trColor)),
                    ),
                  ]),
                ])),
                Text(_money(balance), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: balance >= 0 ? Colors.black87 : Colors.red)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (active) ...[
                  OutlinedButton.icon(onPressed: () => _showAllocateSheet(tr), icon: const Icon(Icons.send, size: 16), label: Text(LanguageService.t('allocate'))),
                  OutlinedButton.icon(onPressed: () => _showAdjustSheet(tr), icon: const Icon(Icons.tune, size: 16), label: Text(LanguageService.t('adjust'))),
                ],
                OutlinedButton.icon(
                  onPressed: () => _toggleTreasurer(tr),
                  icon: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 16, color: active ? Colors.red : Colors.green),
                  label: Text(active ? LanguageService.t('deactivate') : LanguageService.t('activate'), style: TextStyle(color: active ? Colors.red : Colors.green)),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _toggleTreasurer(Map tr) async {
    try {
      await ApiService().post('/admin/treasurer/treasurers/${tr['id']}/toggle', {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _showAddTreasurerSheet() {
    int? userId;
    final maxCtrl = TextEditingController();
    String? formError;
    bool saving = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormSheetHeader(icon: Icons.person_add, title: LanguageService.t('add_treasurer'), accent: BrandingService.primary, onClose: () => Navigator.pop(ctx)),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: BrandingService.primary, child: DropdownButtonFormField<int>(
            value: userId,
            decoration: appFieldDecoration(label: LanguageService.t('resident'), icon: Icons.person_outline, accent: BrandingService.primary),
            hint: Text(LanguageService.t('select_resident')),
            items: _eligibleResidents.map<DropdownMenuItem<int>>((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name']?.toString() ?? ''))).toList(),
            onChanged: (v) => setS(() => userId = v),
          )),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: maxCtrl, keyboardType: TextInputType.number,
              decoration: appFieldDecoration(label: LanguageService.t('max_holding_amount_optional'), icon: Icons.speed, accent: BrandingService.secondary))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
            label: Text(saving ? '' : LanguageService.t('add')),
            style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: saving ? null : () async {
              if (userId == null) { setS(() => formError = LanguageService.t('select_resident')); return; }
              setS(() { saving = true; formError = null; });
              try {
                await ApiService().post('/admin/treasurer/treasurers', {
                  'user_id': userId,
                  if (maxCtrl.text.trim().isNotEmpty) 'max_holding_amount': double.tryParse(maxCtrl.text.trim()),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                setS(() { saving = false; formError = e.toString().replaceFirst('Exception: ', ''); });
              }
            },
          ),
        ]))),
      ),
    );
  }

  void _showAllocateSheet(Map tr) {
    final amtCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    String? formError;
    bool saving = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormSheetHeader(icon: Icons.send, title: '${LanguageService.t('allocate_fund_to')} ${(tr['user'] as Map?)?['name'] ?? ''}', accent: BrandingService.primary, onClose: () => Navigator.pop(ctx)),
          Text('${LanguageService.t('available_to_allocate')}: ${_money(_summary['available_balance'])}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: amtCtrl, keyboardType: TextInputType.number,
              decoration: appFieldDecoration(label: '${LanguageService.t('amount_2')} (${BrandingService.currencySymbol})', icon: Icons.currency_rupee, accent: BrandingService.primary))),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: purposeCtrl,
              decoration: appFieldDecoration(label: LanguageService.t('purpose'), icon: Icons.short_text_rounded, accent: BrandingService.secondary))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
            label: Text(saving ? '' : LanguageService.t('allocate')),
            style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: saving ? null : () async {
              final amt = double.tryParse(amtCtrl.text.trim());
              if (amt == null || amt <= 0) { setS(() => formError = LanguageService.t('enter_a_valid_amount')); return; }
              setS(() { saving = true; formError = null; });
              try {
                await ApiService().post('/admin/treasurer/allocate', {
                  'treasurer_id': tr['id'], 'amount': amt,
                  if (purposeCtrl.text.trim().isNotEmpty) 'purpose': purposeCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                setS(() { saving = false; formError = e.toString().replaceFirst('Exception: ', ''); });
              }
            },
          ),
        ]))),
      ),
    );
  }

  void _showAdjustSheet(Map tr) {
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String direction = 'credit';
    String? formError;
    bool saving = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormSheetHeader(icon: Icons.tune, title: LanguageService.t('manual_adjustment'), accent: Colors.orange, onClose: () => Navigator.pop(ctx)),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<String>(
            value: direction,
            decoration: appFieldDecoration(label: LanguageService.t('direction'), icon: Icons.swap_vert, accent: BrandingService.secondary),
            items: [
              DropdownMenuItem(value: 'credit', child: Text(LanguageService.t('credit_increase'))),
              DropdownMenuItem(value: 'debit', child: Text(LanguageService.t('debit_decrease'))),
            ],
            onChanged: (v) => setS(() => direction = v ?? 'credit'),
          )),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: amtCtrl, keyboardType: TextInputType.number,
              decoration: appFieldDecoration(label: '${LanguageService.t('amount_2')} (${BrandingService.currencySymbol})', icon: Icons.currency_rupee, accent: BrandingService.primary))),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: reasonCtrl, maxLines: 2,
              decoration: appFieldDecoration(label: LanguageService.t('reason'), icon: Icons.info_outline, accent: BrandingService.secondary))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
            label: Text(saving ? '' : LanguageService.t('save_adjustment')),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: saving ? null : () async {
              final amt = double.tryParse(amtCtrl.text.trim());
              if (amt == null || amt <= 0) { setS(() => formError = LanguageService.t('enter_a_valid_amount')); return; }
              if (reasonCtrl.text.trim().isEmpty) { setS(() => formError = LanguageService.t('reason_required')); return; }
              setS(() { saving = true; formError = null; });
              try {
                await ApiService().post('/admin/treasurer/adjust', {
                  'treasurer_id': tr['id'], 'amount': amt, 'direction': direction, 'reason': reasonCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                setS(() { saving = false; formError = e.toString().replaceFirst('Exception: ', ''); });
              }
            },
          ),
        ]))),
      ),
    );
  }

  // ── Transactions tab ───────────────────────────────────────────────

  Widget _transactionsTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Row(children: [
          Expanded(child: AppFieldShell(accent: BrandingService.primary, child: DropdownButtonFormField<String?>(
            value: _filterStatus,
            decoration: appFieldDecoration(label: LanguageService.t('status'), icon: Icons.flag_outlined, accent: BrandingService.primary),
            items: [null, 'pending', 'approved', 'rejected'].map((s) => DropdownMenuItem(value: s, child: Text(s == null ? LanguageService.t('all_statuses') : s[0].toUpperCase() + s.substring(1), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { setState(() => _filterStatus = v); _loadTransactions(); },
          ))),
          const SizedBox(width: 10),
          Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<String?>(
            value: _filterType,
            decoration: appFieldDecoration(label: LanguageService.t('type'), icon: Icons.category_outlined, accent: BrandingService.secondary),
            items: [null, 'fund_allocation', 'expense', 'fund_return', 'additional_fund', 'expense_reversal', 'fund_adjustment']
                .map((s) => DropdownMenuItem(value: s, child: Text(s == null ? LanguageService.t('all_types') : s.replaceAll('_', ' '), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { setState(() => _filterType = v); _loadTransactions(); },
          ))),
        ]),
      ),
      Expanded(
        child: _transactions.isEmpty
            ? EmptyState(icon: Icons.list_alt, title: LanguageService.t('no_transactions_found'), color: BrandingService.primary)
            : RefreshIndicator(onRefresh: _loadTransactions, child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                itemCount: _transactions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _txnCard(_transactions[i] as Map),
              )),
      ),
    ]);
  }

  Widget _txnCard(Map txn) {
    final isCredit = txn['direction'] == 'credit';
    final amount = _numOf(txn['amount']);
    final status = txn['status']?.toString() ?? 'approved';
    final type = (txn['type']?.toString() ?? '').replaceAll('_', ' ');
    final treasurerName = ((txn['treasurer'] as Map?)?['user'] as Map?)?['name']?.toString() ?? '—';
    Color statusColor = status == 'pending' ? Colors.orange : (status == 'rejected' ? Colors.red : Colors.green);
    final txnIcon = isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final txnColor = isCredit ? Colors.green : Colors.red;

    return AdminListCard(
      color: txnColor,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AdminTileIcon(icon: txnIcon, color: txnColor, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(treasurerName, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(type, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            if (txn['description'] != null) Text(txn['description'].toString(), style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${isCredit ? '+' : '-'}${_money(amount)}', style: TextStyle(fontWeight: FontWeight.bold, color: txnColor)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor)),
            ),
          ]),
        ]),
        if (status == 'pending') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: () => _approve(txn), icon: const Icon(Icons.check, size: 16), label: Text(LanguageService.t('approve')), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _reject(txn), icon: const Icon(Icons.close, size: 16, color: Colors.red), label: Text(LanguageService.t('reject'), style: const TextStyle(color: Colors.red)))),
          ]),
        ] else if (txn['type'] == 'expense' && status == 'approved') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => _reverse(txn), icon: const Icon(Icons.undo, size: 16), label: Text(LanguageService.t('reverse'))),
        ],
      ]),
    );
  }

  Future<void> _approve(Map txn) async {
    try {
      await ApiService().post('/admin/treasurer/transactions/${txn['id']}/approve', {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _reject(Map txn) async {
    try {
      await ApiService().post('/admin/treasurer/transactions/${txn['id']}/reject', {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _reverse(Map txn) async {
    try {
      await ApiService().post('/admin/treasurer/transactions/${txn['id']}/reverse', {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
}
