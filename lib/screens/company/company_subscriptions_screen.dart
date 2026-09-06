import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/empty_state.dart';

class CompanySubscriptionsScreen extends StatefulWidget {
  const CompanySubscriptionsScreen({super.key});
  @override
  State<CompanySubscriptionsScreen> createState() => _CompanySubscriptionsScreenState();
}

class _CompanySubscriptionsScreenState extends State<CompanySubscriptionsScreen> {
  List _subscriptions = [];
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
      setState(() { _subscriptions = List.from(data ?? []); _loading = false; });
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

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('subscriptions'))),
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
