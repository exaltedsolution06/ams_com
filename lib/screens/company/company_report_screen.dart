import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/empty_state.dart';

class CompanyReportScreen extends StatefulWidget {
  const CompanyReportScreen({super.key});
  @override
  State<CompanyReportScreen> createState() => _CompanyReportScreenState();
}

class _CompanyReportScreenState extends State<CompanyReportScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/report');
      setState(() { _data = (res['data'] as Map?)?.cast<String, dynamic>(); _loading = false; });
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
        _                  => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final company = (_data?['company'] as Map?) ?? {};
    final apartments = (_data?['apartments'] as List?) ?? [];
    final ownedPlans = (_data?['owned_plans'] as List?) ?? [];
    final subHistoryRaw = _data?['subscription_history'];
    final subHistory = (subHistoryRaw is Map ? subHistoryRaw['data'] as List? : subHistoryRaw as List?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('company_report'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(company['name'] as String? ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Row(children: [
                              _MiniStat(label: LanguageService.t('apartments'), value: '${apartments.length}'),
                              _MiniStat(label: LanguageService.t('flats'), value: '${apartments.fold<int>(0, (s, a) => s + ((a['flats_count'] ?? 0) as int))}'),
                              _MiniStat(label: LanguageService.t('residents'), value: '${apartments.fold<int>(0, (s, a) => s + ((a['users_count'] ?? 0) as int))}'),
                            ]),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionHeader(LanguageService.t('apartments')),
                      ...apartments.map((apt) {
                        final sub = apt['active_subscription'] as Map?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                          child: ListTile(
                            title: Text(apt['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${apt['flats_count'] ?? 0} ${LanguageService.t('flats')} · ${apt['users_count'] ?? 0} ${LanguageService.t('residents')}'),
                            trailing: Chip(
                              label: Text((sub?['plan'] as Map?)?['name'] as String? ?? LanguageService.t('no_plan'), style: const TextStyle(fontSize: 11)),
                              backgroundColor: sub != null ? Colors.green[50] : Colors.grey[200],
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      _SectionHeader(LanguageService.t('your_plans_sold_to_your_apartments')),
                      if (ownedPlans.isEmpty)
                        EmptyRow(icon: Icons.card_membership_outlined, text: LanguageService.t('no_plans_created_yet'), color: BrandingService.primary)
                      else
                        ...ownedPlans.map((p) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                              child: ListTile(
                                title: Text(p['name'] as String? ?? ''),
                                subtitle: Text('${_money(p['price'])} · ${p['duration_days']} ${LanguageService.t('days_lc')} · ${LanguageService.t('max_lc')} ${p['max_flats'] == 0 ? '∞' : p['max_flats']} ${LanguageService.t('flats_lc')}'),
                                trailing: Icon(Icons.circle, size: 10, color: (p['is_active'] == true) ? Colors.green : Colors.grey),
                              ),
                            )),
                      const SizedBox(height: 12),
                      _SectionHeader(LanguageService.t('subscription_history')),
                      if (subHistory.isEmpty)
                        EmptyRow(icon: Icons.history, text: LanguageService.t('no_history_yet'), color: BrandingService.primary)
                      else
                        ...subHistory.map((s) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                              child: ListTile(
                                dense: true,
                                title: Text('${(s['apartment'] as Map?)?['name'] ?? ''} · ${(s['plan'] as Map?)?['name'] ?? ''}'),
                                subtitle: Text(_money(s['amount_paid'])),
                                trailing: Chip(
                                  label: Text(s['status'] as String? ?? '', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  backgroundColor: _statusColor(s['status'] as String?),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
      );
}
