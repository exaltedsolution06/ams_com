import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/empty_state.dart';

/// Company Admin > Referrer Commissions - read-only "how much have we
/// earned, how much has actually been paid out" ledger for referrers
/// linked to this company's own apartments. Mirrors the web's
/// admin/referrer-commissions/index.blade.php for a company_admin; payout
/// recording itself stays a website-only action (see
/// Admin\ReferrerCommissionController::storePayout), same as before.
class CompanyReferrerCommissionsScreen extends StatefulWidget {
  const CompanyReferrerCommissionsScreen({super.key});
  @override
  State<CompanyReferrerCommissionsScreen> createState() => _CompanyReferrerCommissionsScreenState();
}

class _CompanyReferrerCommissionsScreenState extends State<CompanyReferrerCommissionsScreen> {
  List _referrers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/referrer-commissions');
      setState(() { _referrers = List.from(res['data'] as List? ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  String _money(num? v) => '₹${(v ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/company/dashboard')),
        title: Text(LanguageService.t('referrer_commissions')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                ]))
              : _referrers.isEmpty
                  ? EmptyState(icon: Icons.badge_outlined, title: LanguageService.t('no_referrers_yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _referrers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final r = _referrers[i] as Map;
                          final apartments = List.from(r['apartments'] as List? ?? []);
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: primary.withOpacity(0.12),
                                  child: Icon(Icons.person_outline, color: primary, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(r['name'] as String? ?? '-',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ),
                                Text('${r['apartments_count'] ?? 0} ${LanguageService.t('apartments')}',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                              ]),
                              if (apartments.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(spacing: 6, runSpacing: 6, children: apartments.map((a) => Chip(
                                  label: Text((a as Map)['name'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Colors.grey.shade100,
                                  padding: EdgeInsets.zero,
                                )).toList()),
                              ],
                              const SizedBox(height: 10),
                              Divider(color: Colors.grey.shade200, height: 1),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(LanguageService.t('earned'), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                    Text(_money(r['earned'] as num?), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  ]),
                                ),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(LanguageService.t('paid'), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                    Text(_money(r['paid'] as num?), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ]),
                                ),
                              ]),
                            ]),
                          );
                        },
                      ),
                    ),
    );
  }
}
