import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/empty_state.dart';
import 'admin_wallet_ledger_screen.dart';
import 'admin_approvals_screen.dart';
import '../../services/language_service.dart';

class AdminWalletScreen extends StatefulWidget {
  const AdminWalletScreen({super.key});
  @override
  State<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends State<AdminWalletScreen> {
  List _residents = [];
  double _totalHeld = 0;
  int _pendingCount = 0;
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = _searchCtrl.text.trim().isNotEmpty ? '?search=${_searchCtrl.text.trim()}' : '';
    try {
      final res = await ApiService().get('/admin/wallet/residents$q');
      setState(() {
        _residents = res['data']['data'] ?? res['data'] ?? [];
        _totalHeld = double.tryParse(res['total_held'].toString()) ?? 0;
        _pendingCount = res['pending_count'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('wallet')),
        actions: [
          IconButton(
            tooltip: LanguageService.t('pending_approvals'),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminApprovalsScreen(initialTab: 3)));
              _load();
            },
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.hourglass_top_outlined),
              if (_pendingCount > 0)
                Positioned(right: -2, top: -2, child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text('$_pendingCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9)),
                )),
            ]),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [BrandingService.secondary, BrandingService.secondary.withOpacity(0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: BrandingService.secondary.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                    child: Row(children: [
                      Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(LanguageService.t('total_advance_held_all_flats'), style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('${BrandingService.currencySymbol}${_totalHeld.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  AppFieldShell(
                    accent: BrandingService.secondary,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: appFieldDecoration(
                        label: LanguageService.t('search_resident_or_flat'),
                        icon: Icons.search_rounded, accent: BrandingService.secondary,
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_residents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        color: BrandingService.secondary,
                        title: LanguageService.t('no_residents_found'),
                      ),
                    )
                  else
                    ..._residents.map((r) => _ResidentCard(
                      resident: r,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminWalletLedgerScreen(resident: r)));
                        _load();
                      },
                    )),
                ],
              ),
            ),
    );
  }
}

class _ResidentCard extends StatelessWidget {
  final Map resident;
  final VoidCallback onTap;
  const _ResidentCard({required this.resident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final flats = (resident['flats'] as List?) ?? [];
    final flatLabel = flats.isNotEmpty ? flats.map((f) => f['flat_number']).join(', ') : 'No flat linked';
    final balance = double.tryParse((resident['wallet']?['balance'] ?? 0).toString()) ?? 0;
    final name = resident['name']?.toString() ?? '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: BrandingService.secondary.withOpacity(0.1),
          child: Text(name.isNotEmpty ? name.substring(0, 1) : '?', style: TextStyle(color: BrandingService.secondary, fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Flat $flatLabel', style: const TextStyle(fontSize: 12)),
        trailing: Text('${BrandingService.currencySymbol}${balance.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: balance > 0 ? Colors.green : Colors.grey)),
      ),
    );
  }
}
