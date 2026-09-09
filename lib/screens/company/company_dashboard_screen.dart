import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/announcement_banner.dart';
import '../../widgets/empty_state.dart';

class CompanyDashboardScreen extends StatefulWidget {
  const CompanyDashboardScreen({super.key});
  @override
  State<CompanyDashboardScreen> createState() => _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends State<CompanyDashboardScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _platformBankDetails;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/dashboard');
      final bank = await ApiService().get('/company/platform-bank-details');
      setState(() {
        _data = (res['data'] as Map?)?.cast<String, dynamic>();
        _platformBankDetails = (bank['data'] as Map?)?.cast<String, dynamic>();
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

  List<Widget> _platformBankRow(String label, dynamic value) {
    if (value == null || (value is String && value.isEmpty)) return [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          Expanded(child: Text('$value', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final company = (_data?['company'] as Map?) ?? {};
    final apartments = (_data?['apartments'] as List?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        title: Text(company['name'] as String? ?? LanguageService.t('company_dashboard')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const AnnouncementBanner(),
                      if (company['active_subscription'] == null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.shade200)),
                          child: Row(children: [
                            const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(LanguageService.t('no_active_platform_subscription'), style: const TextStyle(fontSize: 12.5))),
                          ]),
                        ),
                      if (_platformBankDetails?['has_details'] == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.account_balance_outlined, size: 18, color: primary),
                              const SizedBox(width: 6),
                              Expanded(child: Text(LanguageService.t('pay_your_platform_subscription'),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5))),
                            ]),
                            const SizedBox(height: 10),
                            if (_platformBankDetails?['has_qr'] == true) ...[
                              if (_platformBankDetails?['qr_code_url'] != null)
                                Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(_platformBankDetails!['qr_code_url'], height: 130, width: 130, fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const SizedBox()),
                                  ),
                                ),
                              if (_platformBankDetails?['qr_id'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Center(child: Text('UPI ID: ${_platformBankDetails!['qr_id']}', style: const TextStyle(fontSize: 12))),
                                ),
                              if (_platformBankDetails?['has_bank_account'] == true) const SizedBox(height: 10),
                            ],
                            if (_platformBankDetails?['has_bank_account'] == true) ...[
                              ..._platformBankRow('Bank Name', _platformBankDetails?['bank_name']),
                              ..._platformBankRow('Account No.', _platformBankDetails?['account_number']),
                              ..._platformBankRow('IFSC Code', _platformBankDetails?['ifsc_code']),
                              ..._platformBankRow('SWIFT Code', _platformBankDetails?['swift_code']),
                              ..._platformBankRow('Branch', _platformBankDetails?['branch_name']),
                            ],
                          ]),
                        ),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10, crossAxisSpacing: 10,
                        childAspectRatio: 1.5,
                        children: [
                          _StatCard(label: LanguageService.t('apartments'), value: '${_data?['total_apartments'] ?? 0}', icon: Icons.business, color: Colors.blue),
                          _StatCard(label: LanguageService.t('active'), value: '${_data?['active_apartments'] ?? 0}', icon: Icons.check_circle_outline, color: Colors.green),
                          _StatCard(label: LanguageService.t('total_flats'), value: '${_data?['total_flats'] ?? 0}', icon: Icons.door_front_door_outlined, color: Colors.purple),
                          _StatCard(label: LanguageService.t('residents'), value: '${_data?['total_residents'] ?? 0}', icon: Icons.people_outline, color: Colors.amber[800]!),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(LanguageService.t('subscription_earnings'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(_money(_data?['subscription_earnings']),
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                              Text(LanguageService.t('from_your_apartments_plans'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ])),
                            OutlinedButton(onPressed: () => context.push('/company/report'), child: Text(LanguageService.t('full_report'))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(LanguageService.t('your_apartments'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('${apartments.length} ${LanguageService.t('total_lc')}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                      const SizedBox(height: 4),
                      if (apartments.isEmpty)
                        EmptyRow(icon: Icons.apartment_outlined, text: LanguageService.t('no_apartments_yet'), color: BrandingService.primary)
                      else
                        ...apartments.map((apt) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: primary.withOpacity(0.12), child: Icon(Icons.apartment, color: primary)),
                                title: Text(apt['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${apt['flats_count'] ?? 0} ${LanguageService.t('flats')} · ${apt['users_count'] ?? 0} ${LanguageService.t('residents')}'),
                              ),
                            )),
                    ]),
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: Text(LanguageService.t('retry'))),
        ]),
      ),
    );
  }
}
