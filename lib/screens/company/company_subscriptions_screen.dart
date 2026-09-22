import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../utils/type_helpers.dart';

class CompanySubscriptionsScreen extends StatefulWidget {
  const CompanySubscriptionsScreen({super.key});
  @override
  State<CompanySubscriptionsScreen> createState() => _CompanySubscriptionsScreenState();
}

class _CompanySubscriptionsScreenState extends State<CompanySubscriptionsScreen> {
  List _subscriptions = [];
  List _apartments = [];
  List _plans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/subscriptions');
      dynamic data = res['data'];
      if (data is Map && data.containsKey('data')) data = data['data'];
      // Item 1: also load this Company's own apartments + plans so
      // "Assign Plan" below can offer a picker for both, instead of this
      // page only ever showing subscriptions that already exist.
      final aptsRes = await ApiService().get('/company/apartments');
      final plansRes = await ApiService().get('/company/plans');
      setState(() {
        _subscriptions = List.from(data ?? []);
        _apartments = List.from(aptsRes['data'] as List? ?? []);
        _plans = List.from((plansRes['data'] as List? ?? []).where((p) => (p as Map)['is_active'] != false));
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  String _money(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '0') ?? 0;
    return '₹${d.toStringAsFixed(0)}';
  }

  Color _statusColor(String? s) => switch (s) {
        'active'           => Colors.green,
        'pending_approval' => Colors.orange,
        'expired'          => Colors.grey,
        'cancelled'        => Colors.redAccent,
        _                  => Colors.grey,
      };

  Future<void> _approveCash(Map sub) async {
    final confirmed = await AmsDialog.confirm(
      context, title: LanguageService.t('confirm_cash_payment'),
      message: 'Confirm cash payment received for "${(sub['apartment'] as Map?)?['name'] ?? ''}"? This will activate the plan.',
      icon: Icons.payments_outlined, confirmText: LanguageService.t('confirm'),
    );
    if (confirmed != true) return;
    try {
      await ApiService().post('/company/subscriptions/${sub['id']}/approve-cash', {});
      _load();
    } catch (e) {
      if (mounted) AmsDialog.info(context, title: LanguageService.t('error'), message: e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Item 1: "In company app -> company login > Subscription page -> Not
  /// have any option to assign plan on apartment." — directly assigns one
  /// of this Company's own plans to one of its apartments (same
  /// POST /company/plans/assign the website's Super-Admin-style assign
  /// flow already uses), recording amount_paid/payment_reference and
  /// activating the plan immediately.
  void _showAssignForm() {
    if (_apartments.isEmpty) {
      AmsDialog.info(context, title: LanguageService.t('error'), message: LanguageService.t('no_apartments_yet'));
      return;
    }
    if (_plans.isEmpty) {
      AmsDialog.info(context, title: LanguageService.t('error'), message: LanguageService.t('no_plans_yet'));
      return;
    }
    Map? selectedApartment = _apartments.first as Map;
    Map? selectedPlan = _plans.first as Map;
    final amountCtrl = TextEditingController(text: (selectedPlan['price'] ?? 0).toString());
    final refCtrl = TextEditingController();
    bool saving = false;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormSheetHeader(
              icon: Icons.assignment_turned_in_outlined,
              title: LanguageService.t('assign_plan'),
              accent: BrandingService.primary,
              onClose: () => Navigator.pop(ctx),
            ),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: DropdownButtonFormField<int>(
                value: selectedApartment?['id'] as int?,
                isExpanded: true,
                decoration: appFieldDecoration(label: LanguageService.t('apartment'), icon: Icons.apartment, accent: BrandingService.primary),
                items: _apartments.map((a) => DropdownMenuItem(
                  value: (a as Map)['id'] as int,
                  child: Text(a['name'] as String? ?? '', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setS(() => selectedApartment = _apartments.firstWhere((a) => (a as Map)['id'] == v) as Map),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: DropdownButtonFormField<int>(
                value: selectedPlan?['id'] as int?,
                isExpanded: true,
                decoration: appFieldDecoration(label: LanguageService.t('plan'), icon: Icons.card_membership_rounded, accent: BrandingService.secondary),
                items: _plans.map((p) => DropdownMenuItem(
                  value: (p as Map)['id'] as int,
                  child: Text('${p['name']} · ${_money(p['price'])}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setS(() {
                  selectedPlan = _plans.firstWhere((p) => (p as Map)['id'] == v) as Map;
                  amountCtrl.text = (selectedPlan?['price'] ?? 0).toString();
                }),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: appFieldDecoration(label: LanguageService.t('amount_paid'), icon: Icons.currency_rupee, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: refCtrl,
                decoration: appFieldDecoration(label: LanguageService.t('payment_reference'), icon: Icons.receipt_long_outlined, accent: BrandingService.secondary),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(saving ? '' : LanguageService.t('assign_plan')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                if (selectedApartment == null || selectedPlan == null) return;
                setS(() { saving = true; formError = null; });
                try {
                  await ApiService().post('/company/plans/assign', {
                    'apartment_id': selectedApartment!['id'],
                    'plan_id': selectedPlan!['id'],
                    'amount_paid': toNum(amountCtrl.text),
                    'payment_reference': refCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  setS(() { saving = false; formError = e.toString().replaceAll('Exception: ', ''); });
                }
              },
            ),
          ]),
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('subscriptions'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _showAssignForm,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('assign_plan')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _subscriptions.isEmpty
                      ? ListView(children: [
                          Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.subscriptions_outlined, color: BrandingService.primary, title: LanguageService.t('no_subscriptions_yet'))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _subscriptions.length,
                          itemBuilder: (ctx, i) {
                            final s = _subscriptions[i];
                            final status = s['status'] as String?;
                            final apt = s['apartment'] as Map?;
                            final plan = s['plan'] as Map?;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text('${apt?['name'] ?? ''} · ${plan?['name'] ?? ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                    ),
                                    Chip(
                                      label: Text(status ?? '', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                      backgroundColor: _statusColor(status),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text('${_money(s['amount_paid'])} · ${s['payment_method'] ?? ''}'
                                      '${s['expires_at'] != null ? ' · ${LanguageService.t('expires_lc')} ${s['expires_at'].toString().split('T').first}' : ''}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  if (status == 'pending_approval' && s['payment_method'] == 'cash') ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _approveCash(s as Map),
                                        icon: const Icon(Icons.check_circle_outline, size: 16),
                                        label: Text(LanguageService.t('confirm_cash_payment')),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: BrandingService.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
