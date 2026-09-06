import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';

class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});
  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/report');
      final company = (res['data'] as Map)['company'] as Map;
      _nameCtrl.text = company['name'] as String? ?? '';
      _contactNameCtrl.text = company['contact_name'] as String? ?? '';
      _contactPhoneCtrl.text = company['contact_phone'] as String? ?? '';
      _contactEmailCtrl.text = company['contact_email'] as String? ?? '';
      _addressCtrl.text = company['address'] as String? ?? '';
      _cityCtrl.text = company['city'] as String? ?? '';
      _stateCtrl.text = company['state'] as String? ?? '';
      _pincodeCtrl.text = company['pincode'] as String? ?? '';
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      AmsDialog.info(context, title: LanguageService.t('error'), message: LanguageService.t('company_name_required'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService().put('/company/profile', {
        'name': _nameCtrl.text.trim(),
        'contact_name': _contactNameCtrl.text.trim(),
        'contact_phone': _contactPhoneCtrl.text.trim(),
        'contact_email': _contactEmailCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
        'pincode': _pincodeCtrl.text.trim(),
      });
      setState(() => _saving = false);
      if (mounted) AmsDialog.info(context, title: LanguageService.t('saved'), message: LanguageService.t('company_profile_updated'));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) AmsDialog.info(context, title: LanguageService.t('error'), message: e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _contactNameCtrl, _contactPhoneCtrl, _contactEmailCtrl, _addressCtrl, _cityCtrl, _stateCtrl, _pincodeCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('company_profile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Identity header — a soft gradient banner instead of a
                    // bare label, echoing the treatment used on other admin
                    // "profile/summary" cards elsewhere in the app.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [primary, primary.withOpacity(0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: Row(children: [
                        Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                          child: const Icon(Icons.corporate_fare, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(LanguageService.t('company_profile'), style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(_nameCtrl.text.isEmpty ? LanguageService.t('company_name') : _nameCtrl.text,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    AppFieldShell(
                      accent: BrandingService.primary,
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('company_name'), icon: Icons.corporate_fare, accent: BrandingService.primary),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(children: [
                      Icon(Icons.contact_phone_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(LanguageService.t('contact'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
                    ]),
                    const SizedBox(height: 4),
                    Divider(color: Colors.grey.shade200, height: 1),
                    const SizedBox(height: 14),
                    AppFieldShell(
                      accent: BrandingService.secondary,
                      child: TextField(
                        controller: _contactNameCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('contact_name'), icon: Icons.person_outline, accent: BrandingService.secondary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppFieldShell(
                      accent: BrandingService.primary,
                      child: TextField(
                        controller: _contactPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: appFieldDecoration(label: LanguageService.t('contact_phone'), icon: Icons.phone_outlined, accent: BrandingService.primary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppFieldShell(
                      accent: BrandingService.secondary,
                      child: TextField(
                        controller: _contactEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: appFieldDecoration(label: LanguageService.t('contact_email'), icon: Icons.email_outlined, accent: BrandingService.secondary),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(LanguageService.t('address'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
                    ]),
                    const SizedBox(height: 4),
                    Divider(color: Colors.grey.shade200, height: 1),
                    const SizedBox(height: 14),
                    AppFieldShell(
                      accent: BrandingService.primary,
                      child: TextField(
                        controller: _addressCtrl,
                        maxLines: 2,
                        decoration: appFieldDecoration(label: LanguageService.t('address'), icon: Icons.home_outlined, accent: BrandingService.primary).copyWith(alignLabelWithHint: true),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: AppFieldShell(
                          accent: BrandingService.secondary,
                          child: TextField(controller: _cityCtrl, decoration: appFieldDecoration(label: LanguageService.t('city'), icon: Icons.location_city_outlined, accent: BrandingService.secondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppFieldShell(
                          accent: BrandingService.primary,
                          child: TextField(controller: _stateCtrl, decoration: appFieldDecoration(label: LanguageService.t('state'), icon: Icons.map_outlined, accent: BrandingService.primary)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    AppFieldShell(
                      accent: BrandingService.secondary,
                      child: TextField(
                        controller: _pincodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: appFieldDecoration(label: LanguageService.t('pincode'), icon: Icons.pin_drop_outlined, accent: BrandingService.secondary),
                      ),
                    ),
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
