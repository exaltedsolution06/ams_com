import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/empty_state.dart';

/// Company Admin > Send Email - compose a one-off email and broadcast it
/// to selected apartments' registered contact_email. Mirrors the web's
/// admin/apartment-email/index.blade.php for a company_admin: no "email
/// other Company Admins" option (Super Admin only there), and every
/// apartment shown/sent to is hard-scoped server-side to this company
/// (see CompanyApiController::sendEmail).
class CompanySendEmailScreen extends StatefulWidget {
  const CompanySendEmailScreen({super.key});
  @override
  State<CompanySendEmailScreen> createState() => _CompanySendEmailScreenState();
}

class _CompanySendEmailScreenState extends State<CompanySendEmailScreen> {
  List _apartments = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _sending = false;
  String? _error;

  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/apartment-email/recipients');
      final list = List.from(res['data'] as List? ?? []);
      setState(() {
        _apartments = list;
        _selected
          ..clear()
          ..addAll(list.where((a) => a['has_contact_email'] == true).map((a) => a['id'] as int));
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _send() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('select_at_least_one_apartment')), backgroundColor: Colors.red));
      return;
    }
    if (_subjectCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('subject_and_message_required')), backgroundColor: Colors.red));
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await ApiService().post('/company/apartment-email/send', {
        'apartment_ids': _selected.toList(),
        'subject': _subjectCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] as String? ?? LanguageService.t('email_sent')), backgroundColor: Colors.green));
        _subjectCtrl.clear();
        _bodyCtrl.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
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
        title: Text(LanguageService.t('send_email')),
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
              : _apartments.isEmpty
                  ? EmptyState(icon: Icons.mail_outline, title: LanguageService.t('no_apartments_yet'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(LanguageService.t('recipients'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(children: _apartments.map((a) {
                            final id = a['id'] as int;
                            final hasEmail = a['has_contact_email'] == true;
                            return CheckboxListTile(
                              dense: true,
                              value: _selected.contains(id),
                              onChanged: hasEmail ? (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)) : null,
                              activeColor: primary,
                              title: Text(a['name'] as String? ?? '', style: const TextStyle(fontSize: 13.5)),
                              subtitle: hasEmail
                                  ? null
                                  : Text(LanguageService.t('no_contact_email_on_file'), style: const TextStyle(fontSize: 11, color: Colors.red)),
                            );
                          }).toList()),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_selected.length} ${LanguageService.t('apartments_selected')}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 20),
                        AppFieldShell(accent: primary, child: TextField(
                          controller: _subjectCtrl,
                          decoration: appFieldDecoration(label: LanguageService.t('subject'), icon: Icons.short_text, accent: primary),
                        )),
                        const SizedBox(height: 14),
                        AppFieldShell(accent: BrandingService.secondary, child: TextField(
                          controller: _bodyCtrl,
                          maxLines: 8,
                          decoration: appFieldDecoration(label: LanguageService.t('message'), icon: Icons.notes, accent: BrandingService.secondary),
                        )),
                        const SizedBox(height: 22),
                        ElevatedButton.icon(
                          icon: _sending
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_outlined),
                          label: Text(_sending ? '' : LanguageService.t('send_email')),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: _sending ? null : _send,
                        ),
                      ]),
                    ),
    );
  }
}
