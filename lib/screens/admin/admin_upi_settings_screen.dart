import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../services/drawer_state.dart';

import '../../services/language_service.dart';
/// Apartment Admin > UPI - manage this apartment's UPI ID/payee name and
/// switch UPI payments on/off for residents. Mirrors the web's
/// admin/upi/edit.blade.php. Only reachable when the Super Admin has left
/// the 'upi' module switched on for this apartment (Branding > Assign Menu).
class AdminUpiSettingsScreen extends StatefulWidget {
  const AdminUpiSettingsScreen({super.key});
  @override
  State<AdminUpiSettingsScreen> createState() => _State();
}

class _State extends State<AdminUpiSettingsScreen> {
  bool _loading = true;
  bool _saving  = false;
  String? _error;
  final _upiIdCtrl    = TextEditingController();
  final _payeeCtrl    = TextEditingController();
  bool  _statusActive = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res  = await ApiService().get('/admin/upi-settings');
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      _upiIdCtrl.text = data['upi_id'] as String? ?? '';
      _payeeCtrl.text = data['upi_payee_name'] as String? ?? '';
      setState(() { _statusActive = data['upi_status'] == true; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_upiIdCtrl.text.trim().isEmpty || _payeeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('upi_id_and_payee_name_are_required')), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService().put('/admin/upi-settings', {
        'upi_id': _upiIdCtrl.text.trim(),
        'upi_payee_name': _payeeCtrl.text.trim(),
        'upi_status': _statusActive,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('upi_payment_details_updated')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')),
        title: Text(LanguageService.t('upi_payment_settings')),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
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
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          LanguageService.t('set_your_apartments_upi_id_and_payee_name_then'),
                          style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    AppFieldShell(accent: BrandingService.primary, child: TextField(
                      controller: _upiIdCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('upi_id'), icon: Icons.qr_code, accent: BrandingService.primary, hint: 'society@okhdfcbank'),
                    )),
                    const SizedBox(height: 14),
                    AppFieldShell(accent: BrandingService.secondary, child: TextField(
                      controller: _payeeCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('payee_name'), icon: Icons.badge_outlined, accent: BrandingService.secondary, hint: 'Green Valley Apartments Association'),
                    )),
                    const SizedBox(height: 20),
                    SwitchListTile.adaptive(
                      value: _statusActive,
                      onChanged: (v) => setState(() => _statusActive = v),
                      title: Text(LanguageService.t('status_active'), style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(LanguageService.t('residents_only_see_upi_as_a_payment_option'), style: TextStyle(fontSize: 12)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ]),
                ),
    );
  }
}
