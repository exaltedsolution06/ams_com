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

class CompanyAptAdminsScreen extends StatefulWidget {
  const CompanyAptAdminsScreen({super.key});
  @override
  State<CompanyAptAdminsScreen> createState() => _CompanyAptAdminsScreenState();
}

class _CompanyAptAdminsScreenState extends State<CompanyAptAdminsScreen> {
  List _admins = [];
  List _apartments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ApiService();
      final adminsRes = await api.get('/company/apt-admins');
      final aptsRes = await api.get('/company/apartments');
      dynamic admins = adminsRes['data'];
      if (admins is Map && admins.containsKey('data')) admins = admins['data'];
      dynamic apts = aptsRes['data'];
      if (apts is Map && apts.containsKey('data')) apts = apts['data'];
      setState(() {
        _admins = List.from(admins ?? []);
        _apartments = List.from(apts ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  void _showForm({Map? admin}) {
    final isEdit = admin != null;
    final nameCtrl = TextEditingController(text: admin?['name'] as String? ?? '');
    final emailCtrl = TextEditingController(text: admin?['email'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: admin?['phone'] as String? ?? '');
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final selectedApts = <int>{
      ...((admin?['managed_apartments'] as List?) ?? []).map((a) => a['id'] as int),
    };
    bool saving = false;
    String? formError;
    // Verify-before-create flow (item 2) - Company Admin only ever
    // verifies a new admin by Email (no Phone option).
    bool otpSent = false;
    String? otpToken;
    String? otpMessage;
    final otpCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: BrandingService.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.admin_panel_settings_outlined, color: BrandingService.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(isEdit ? LanguageService.t('edit_apartment_admin') : LanguageService.t('new_apartment_admin'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: appFieldDecoration(label: LanguageService.t('name'), icon: Icons.person_outline, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: appFieldDecoration(label: LanguageService.t('email_login'), icon: Icons.email_outlined, accent: BrandingService.secondary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: appFieldDecoration(label: LanguageService.t('phone'), icon: Icons.phone_outlined, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: appFieldDecoration(label: isEdit ? LanguageService.t('new_password_optional') : LanguageService.t('password'), icon: Icons.lock_outline, accent: BrandingService.secondary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: appFieldDecoration(label: LanguageService.t('confirm_password'), icon: Icons.lock_outline, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.apartment_outlined, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(LanguageService.t('assign_apartments'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _apartments.map((a) => FilterChip(
                label: Text(a['name'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                selected: selectedApts.contains(a['id']),
                selectedColor: BrandingService.primary.withOpacity(0.15),
                checkmarkColor: BrandingService.primary,
                onSelected: (v) => setS(() => v ? selectedApts.add(a['id'] as int) : selectedApts.remove(a['id'])),
              )).toList(),
            ),
            const SizedBox(height: 20),
            if (!isEdit && otpSent) ...[
              if (otpMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(otpMessage!, style: TextStyle(fontSize: 12.5, color: Colors.green.shade700)),
                ),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: appFieldDecoration(label: 'Enter OTP', icon: Icons.password_outlined, accent: BrandingService.secondary),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: saving ? null : () async {
                    try {
                      final res = await ApiService().post('/company/apt-admins/resend-otp', {'token': otpToken});
                      setS(() => otpMessage = res['message']?.toString());
                    } catch (e) {
                      setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                    }
                  },
                  child: const Text('Resend OTP'),
                ),
              ),
              const SizedBox(height: 6),
            ],
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isEdit ? Icons.save_outlined : (otpSent ? Icons.check_circle_outline : Icons.send_outlined)),
              label: Text(saving ? '' : (isEdit ? LanguageService.t('save') : (otpSent ? 'Create Admin' : 'Send OTP'))),
              style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                  if (passCtrl.text != confirmCtrl.text) {
                    setS(() => formError = LanguageService.t('passwords_do_not_match'));
                    return;
                  }
                  if (!isEdit && passCtrl.text.isEmpty) {
                    setS(() => formError = LanguageService.t('password_is_required'));
                    return;
                  }
                  if (selectedApts.isEmpty) {
                    setS(() => formError = LanguageService.t('select_at_least_one_apartment'));
                    return;
                  }
                  setS(() { saving = true; formError = null; });

                  if (isEdit) {
                    try {
                      final payload = {
                        'name': nameCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'apartment_ids': selectedApts.toList(),
                        if (passCtrl.text.isNotEmpty) ...{
                          'password': passCtrl.text,
                          'password_confirmation': confirmCtrl.text,
                        },
                      };
                      await ApiService().put('/company/apt-admins/${admin['id']}', payload);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    } catch (e) {
                      setS(() { saving = false; formError = e.toString().replaceAll('Exception: ', ''); });
                    }
                    return;
                  }

                  // Create flow: step 1 sends the OTP, step 2 (button now
                  // reads "Create Admin") verifies it and actually creates
                  // the account - see CompanyApiController::
                  // sendAptAdminOtp()/verifyAptAdminOtp().
                  try {
                    if (!otpSent) {
                      final res = await ApiService().post('/company/apt-admins/send-otp', {
                        'name': nameCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'password': passCtrl.text,
                        'password_confirmation': confirmCtrl.text,
                        'apartment_ids': selectedApts.toList(),
                      });
                      setS(() {
                        saving = false;
                        otpSent = true;
                        otpToken = res['token']?.toString();
                        otpMessage = res['message']?.toString();
                      });
                    } else {
                      if (otpCtrl.text.trim().length != 6) {
                        setS(() { saving = false; formError = 'Enter the 6-digit OTP.'; });
                        return;
                      }
                      await ApiService().post('/company/apt-admins/verify-otp', {
                        'token': otpToken,
                        'otp': otpCtrl.text.trim(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    }
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

  Future<void> _toggleActive(Map admin) async {
    try {
      await ApiService().post('/company/apt-admins/${admin['id']}/toggle', {});
      _load();
    } catch (e) {
      if (mounted) AmsDialog.info(context, title: LanguageService.t('error'), message: e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Turns ONE apartment assignment on/off for this admin, independent of
  /// their account-level active status (_toggleActive above) and without
  /// touching their other apartments - mirrors web's per-apartment toggle
  /// on the Apartment Admins page.
  Future<void> _toggleApartment(Map admin, Map apt) async {
    try {
      await ApiService().post('/company/apt-admins/${admin['id']}/toggle-apartment', {'apartment_id': apt['id']});
      _load();
    } catch (e) {
      if (mounted) AmsDialog.info(context, title: LanguageService.t('error'), message: e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _delete(Map admin) async {
    final confirmed = await AmsDialog.confirm(
      context, title: LanguageService.t('remove_admin'),
      message: 'Remove "${admin['name']}"? This cannot be undone.',
      icon: Icons.delete_outline, confirmText: LanguageService.t('remove'), danger: true,
    );
    if (confirmed != true) return;
    try {
      await ApiService().delete('/company/apt-admins/${admin['id']}');
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
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('apartment_admins'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('new_apartment_admin')),
        backgroundColor: primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _admins.isEmpty
                      ? ListView(children: [
                          Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.admin_panel_settings_outlined, color: BrandingService.primary, title: LanguageService.t('no_apartment_admins_yet_tap_to_add_one'))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _admins.length,
                          itemBuilder: (ctx, i) {
                            final a = _admins[i];
                            final apts = (a['managed_apartments'] as List? ?? []);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                              child: Column(children: [
                                ListTile(
                                  leading: CircleAvatar(backgroundColor: primary.withOpacity(0.12), child: Icon(Icons.person, color: primary)),
                                  title: Text(a['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text('${a['email'] ?? ''}\n${apts.map((x) => x['name']).join(', ')}'),
                                  isThreeLine: true,
                                  onTap: () => _showForm(admin: a as Map),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    GestureDetector(
                                      onTap: () => _toggleActive(a as Map),
                                      child: Icon(Icons.circle, size: 10, color: (a['is_active'] == true) ? Colors.green : Colors.grey),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                      onPressed: () => _delete(a as Map),
                                    ),
                                  ]),
                                ),
                                // Per-apartment on/off, only shown once there's
                                // more than one to distinguish between - see
                                // _toggleApartment() above.
                                if (apts.length > 1)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: apts.map<Widget>((apt) {
                                        final active = (apt['pivot']?['is_active'] ?? true) == true;
                                        return InputChip(
                                          label: Text(apt['name']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                                          avatar: Icon(Icons.circle, size: 9, color: active ? Colors.green : Colors.grey),
                                          onPressed: () => _toggleApartment(a as Map, apt as Map),
                                          backgroundColor: active ? Colors.green.withOpacity(0.06) : Colors.grey.withOpacity(0.10),
                                          side: BorderSide(color: active ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3)),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ]),
                            );
                          },
                        ),
                ),
    );
  }
}
