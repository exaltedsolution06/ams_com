import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';

/// Company Admin > Bank Details - the Company's own bank/UPI details,
/// shown to Apartment Admins of THIS Company's own apartments on their "My
/// Subscription" page (as an alternative to Pay Cash), independent of the
/// platform's own bank details (Super Admin managed). Mirrors the web's
/// admin/bank-details/edit.blade.php for a company_admin.
class CompanyBankDetailsScreen extends StatefulWidget {
  const CompanyBankDetailsScreen({super.key});
  @override
  State<CompanyBankDetailsScreen> createState() => _CompanyBankDetailsScreenState();
}

class _CompanyBankDetailsScreenState extends State<CompanyBankDetailsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _existingQrUrl;
  XFile? _pickedQr;

  final _qrIdCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _swiftCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final c in [_qrIdCtrl, _bankNameCtrl, _ifscCtrl, _accountCtrl, _swiftCtrl, _branchCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/bank-details');
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      _existingQrUrl = data['qr_code_url'] as String?;
      _qrIdCtrl.text = data['qr_id'] as String? ?? '';
      _bankNameCtrl.text = data['bank_name'] as String? ?? '';
      _ifscCtrl.text = data['ifsc_code'] as String? ?? '';
      _accountCtrl.text = data['account_number'] as String? ?? '';
      _swiftCtrl.text = data['swift_code'] as String? ?? '';
      _branchCtrl.text = data['branch_name'] as String? ?? '';
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _pickQr() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _pickedQr = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final fields = <String, String>{
        'qr_id': _qrIdCtrl.text.trim(),
        'bank_name': _bankNameCtrl.text.trim(),
        'ifsc_code': _ifscCtrl.text.trim(),
        'account_number': _accountCtrl.text.trim(),
        'swift_code': _swiftCtrl.text.trim(),
        'branch_name': _branchCtrl.text.trim(),
      };
      await ApiService().uploadMultipart(
        '/company/bank-details', fields,
        filePath: _pickedQr?.path, fileField: 'qr_code', httpMethod: 'PUT',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('bank_details_updated')), backgroundColor: Colors.green));
      }
      _pickedQr = null;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/company/dashboard')),
        title: Text(LanguageService.t('bank_details')),
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
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          LanguageService.t('bank_details_shown_to_your_own_apartments'),
                          style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text(LanguageService.t('qr_code_optional'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
                    const SizedBox(height: 10),
                    Center(
                      child: GestureDetector(
                        onTap: _pickQr,
                        child: Container(
                          width: 160, height: 160,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          child: _pickedQr != null
                              ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_pickedQr!.path), fit: BoxFit.contain))
                              : (_existingQrUrl != null
                                  ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_existingQrUrl!, fit: BoxFit.contain))
                                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Icon(Icons.qr_code, size: 36, color: Colors.grey[400]),
                                      const SizedBox(height: 6),
                                      Text(LanguageService.t('tap_to_upload'), style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
                                    ])),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppFieldShell(accent: primary, child: TextField(
                      controller: _qrIdCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('upi_id'), icon: Icons.tag, accent: primary, hint: 'company@okhdfcbank'),
                    )),
                    const SizedBox(height: 22),
                    Row(children: [
                      Icon(Icons.account_balance_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(LanguageService.t('bank_account_optional'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
                    ]),
                    const SizedBox(height: 4),
                    Divider(color: Colors.grey.shade200, height: 1),
                    const SizedBox(height: 14),
                    AppFieldShell(accent: BrandingService.secondary, child: TextField(
                      controller: _bankNameCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('bank_name'), icon: Icons.account_balance, accent: BrandingService.secondary),
                    )),
                    const SizedBox(height: 14),
                    AppFieldShell(accent: primary, child: TextField(
                      controller: _accountCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('account_number'), icon: Icons.pin_outlined, accent: primary),
                    )),
                    const SizedBox(height: 14),
                    AppFieldShell(accent: BrandingService.secondary, child: TextField(
                      controller: _ifscCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('ifsc_code'), icon: Icons.code, accent: BrandingService.secondary),
                    )),
                    const SizedBox(height: 14),
                    AppFieldShell(accent: primary, child: TextField(
                      controller: _swiftCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('swift_code'), icon: Icons.public, accent: primary),
                    )),
                    const SizedBox(height: 14),
                    AppFieldShell(accent: BrandingService.secondary, child: TextField(
                      controller: _branchCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('branch_name'), icon: Icons.location_city_outlined, accent: BrandingService.secondary),
                    )),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? '' : LanguageService.t('save_changes')),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _saving ? null : _save,
                    ),
                  ]),
                ),
    );
  }
}
