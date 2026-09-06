// admin_branding_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminBrandingScreen extends StatefulWidget {
  const AdminBrandingScreen({super.key});
  @override
  State<AdminBrandingScreen> createState() => _BrandingState();
}

class _BrandingState extends State<AdminBrandingScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;

  final _appNameCtrl = TextEditingController();
  String _currencyCode = 'INR';
  final _currencySymbolCtrl = TextEditingController();
  final Map<String, String> _colors = {};
  String _fontFamily = 'Poppins';
  XFile? _pickedLogo;

  static const _colorFields = [
    ['primary_color', 'Primary'],
    ['accent_color', 'Accent'],
    ['secondary_color', 'Secondary'],
    ['sidebar_color', 'Sidebar'],
    ['app_banner_color', 'Banner'],
    ['card_bg_color', 'Card BG'],
    ['text_primary_color', 'Text'],
    ['success_color', 'Success'],
    ['warning_color', 'Warning'],
    ['danger_color', 'Danger'],
  ];

  // Same per-field fallbacks as the web branding page (admin/branding/index)
  // so a color left unset shows the same default in both places.
  static const _colorDefaults = {
    'primary_color': '#F97316',
    'accent_color': '#E8A010',
    'secondary_color': '#1D4ED8',
    'sidebar_color': '#F97316',
    'app_banner_color': '#F97316',
    'card_bg_color': '#FFFFFF',
    'text_primary_color': '#1A1A1A',
    'success_color': '#28A745',
    'warning_color': '#FFC107',
    'danger_color': '#DC3545',
  };

  static const _fontOptions = [
    'Poppins', 'Roboto', 'Lato', 'Nunito', 'Inter',
    'Montserrat', 'Open Sans', 'Raleway', 'DM Sans', 'Quicksand',
  ];

  // Same currency list as the web branding page (admin/branding/edit_apartment)
  // so both surfaces stay in sync.
  static const _currencyOptions = {
    'INR': '₹ — Indian Rupee',
    'USD': '\$ — US Dollar',
    'GBP': '£ — British Pound',
    'EUR': '€ — Euro',
    'AED': 'د.إ — UAE Dirham',
    'SAR': '﷼ — Saudi Riyal',
    'SGD': 'S\$ — Singapore Dollar',
    'MYR': 'RM — Malaysian Ringgit',
    'BDT': '৳ — Bangladeshi Taka',
    'NPR': '₨ — Nepalese Rupee',
    'PKR': '₨ — Pakistani Rupee',
    'AUD': 'A\$ — Australian Dollar',
    'CAD': 'C\$ — Canadian Dollar',
    'LKR': 'Rs — Sri Lankan Rupee',
  };

  static const _currencySymbols = {
    'INR': '₹', 'USD': '\$', 'GBP': '£', 'EUR': '€', 'AED': 'د.إ',
    'SAR': '﷼', 'SGD': 'S\$', 'MYR': 'RM', 'BDT': '৳', 'NPR': '₨',
    'PKR': '₨', 'AUD': 'A\$', 'CAD': 'C\$', 'LKR': 'Rs',
  };

  static const _presetSwatches = [
    '#1A3C5E', '#0F2A42', '#2563EB', '#0EA5E9', '#0D9488', '#16A34A',
    '#E8A010', '#F59E0B', '#EA580C', '#DC2626', '#DB2777', '#7C3AED',
    '#4B5563', '#111827', '#FFFFFF',
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/branding');
      final data = (res['data'] as Map?)?.cast<String, dynamic>();
      setState(() {
        _data = data;
        _loading = false;
        if (data != null) {
          _appNameCtrl.text = data['app_name'] ?? '';
          final code = data['currency_code'] as String?;
          _currencyCode = _currencyOptions.containsKey(code) ? code! : 'INR';
          _currencySymbolCtrl.text = data['currency_symbol'] ?? _currencySymbols[_currencyCode] ?? '₹';
          _fontFamily = _fontOptions.contains(data['font_family'])
              ? data['font_family'] as String
              : 'Poppins';
          for (final f in _colorFields) {
            _colors[f[0]] = data[f[0]] as String? ?? _colorDefaults[f[0]]!;
          }
        }
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _pickedLogo = picked);
  }

  Future<void> _editColor(String key, String label) async {
    final ctrl = TextEditingController(text: _colors[key]);
    Color parsed() {
      try { return Color(int.parse('FF${ctrl.text.replaceAll('#', '')}', radix: 16)); } catch (_) { return BrandingService.primary; }
    }
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: parsed().withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(Icons.palette_outlined, color: parsed(), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('$label Color', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppFieldShell(
            accent: parsed(),
            child: TextField(
              controller: ctrl,
              onChanged: (_) => setD(() {}),
              decoration: appFieldDecoration(label: LanguageService.t('hex_code'), hint: '#1A3C5E', icon: Icons.tag, accent: parsed()),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: _presetSwatches.map((hex) {
            Color c;
            try { c = Color(int.parse('FF${hex.substring(1)}', radix: 16)); } catch (_) { c = Colors.grey; }
            final selected = ctrl.text.toLowerCase() == hex.toLowerCase();
            return GestureDetector(
              onTap: () => setD(() => ctrl.text = hex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? c : Colors.grey.shade300, width: selected ? 3 : 1),
                  boxShadow: selected ? [BoxShadow(color: c.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))] : null,
                ),
                child: selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
              ),
            );
          }).toList()),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: parsed(),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(LanguageService.t('use')),
          ),
        ],
      )),
    );
    if (result != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(result)) {
      setState(() => _colors[key] = result);
    } else if (result != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('enter_a_valid_hex_code_like_1a3c5e')), backgroundColor: Colors.orange));
    }
  }

  Future<void> _save() async {
    if (_appNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('app_name_is_required')), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _saving = true);
    try {
      final fields = <String, String>{
        'app_name': _appNameCtrl.text.trim(),
        'currency_code': _currencyCode,
        'currency_symbol': _currencySymbolCtrl.text.trim(),
        'font_family': _fontFamily,
        ..._colors,
      };
      await ApiService().uploadMultipart('/admin/branding', fields, filePath: _pickedLogo?.path);
      await BrandingService.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('branding_updated')), backgroundColor: Colors.green));
      }
      _pickedLogo = null;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _hex(String? h) {
    if (h == null) return Colors.grey;
    try { return Color(int.parse('FF${h.substring(1)}', radix: 16)); } catch (_) { return Colors.grey; }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(LanguageService.t('branding')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? Center(child: Text(LanguageService.t('unable_to_load_branding'), style: TextStyle(color: Colors.grey)))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                  // Logo
                  Center(
                    child: GestureDetector(
                      onTap: _pickLogo,
                      child: Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _pickedLogo != null
                              ? Image.file(File(_pickedLogo!.path), height: 96, width: 96, fit: BoxFit.cover)
                              : (_data!['app_logo_url'] != null
                                  ? Image.network(_data!['app_logo_url'], height: 96, width: 96, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          height: 96, width: 96, color: Colors.grey[200],
                                          child: Icon(Icons.apartment_rounded, size: 40, color: primary)))
                                  : Container(
                                      height: 96, width: 96, color: Colors.grey[200],
                                      child: Icon(Icons.apartment_rounded, size: 40, color: primary))),
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(LanguageService.t('tap_logo_to_change'), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(LanguageService.t('app_identity'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  AppFieldShell(
                    accent: primary,
                    child: TextField(
                      controller: _appNameCtrl,
                      decoration: appFieldDecoration(label: LanguageService.t('app_name'), icon: Icons.badge_outlined, accent: primary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppFieldShell(
                    accent: primary,
                    child: DropdownButtonFormField<String>(
                      value: _fontFamily,
                      decoration: appFieldDecoration(label: LanguageService.t('font_family'), icon: Icons.font_download_outlined, accent: primary),
                      items: _fontOptions
                          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                          .toList(),
                      onChanged: (v) => setState(() => _fontFamily = v ?? _fontFamily),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: AppFieldShell(
                        accent: primary,
                        child: DropdownButtonFormField<String>(
                          value: _currencyCode,
                          isExpanded: true,
                          decoration: appFieldDecoration(label: LanguageService.t('currency_code'), icon: Icons.language_rounded, accent: primary),
                          items: _currencyOptions.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _currencyCode = v;
                              _currencySymbolCtrl.text = _currencySymbols[v] ?? v;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppFieldShell(
                        accent: primary,
                        child: TextField(
                          controller: _currencySymbolCtrl,
                          decoration: appFieldDecoration(label: LanguageService.t('currency_symbol'), hint: '₹', icon: Icons.currency_exchange_rounded, accent: primary),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 26),

                  Text(LanguageService.t('color_palette'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(LanguageService.t('tap_a_swatch_to_change_it'), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(spacing: 16, runSpacing: 16, children: _colorFields.map((f) {
                        final key = f[0], label = f[1];
                        return GestureDetector(
                          onTap: () => _editColor(key, label),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: _hex(_colors[key]),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.edit, size: 12, color: Colors.white70),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ]),
                        );
                      }).toList()),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [primary, primary.withOpacity(0.75)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                      boxShadow: [BoxShadow(color: primary.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
                    ),
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save Branding', style: const TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(LanguageService.t('changes_apply_to_this_apartment_s_app_and_web'),
                          style: TextStyle(color: Colors.blue[700], fontSize: 12, height: 1.3))),
                    ]),
                  ),
                ]),
    );
  }
}

// ── Admin Bulk Notify ─────────────────────────────────────────────────────────
class AdminBulkNotifyScreen extends StatefulWidget {
  const AdminBulkNotifyScreen({super.key});
  @override
  State<AdminBulkNotifyScreen> createState() => _BulkState();
}

class _BulkState extends State<AdminBulkNotifyScreen> {
  final _titleCtrl   = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _target     = 'all';
  bool   _sending    = false;

  Future<void> _send() async {
    if (_titleCtrl.text.trim().isEmpty || _messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('title_and_message_required')), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiService().post('/admin/notifications/bulk', {
        'title': _titleCtrl.text.trim(), 'message': _messageCtrl.text.trim(), 'target': _target,
      });
      _titleCtrl.clear(); _messageCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('notification_sent')), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ','')), backgroundColor: Colors.red));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(LanguageService.t('bulk_notify')),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(LanguageService.t('send_notification_to_residents'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(LanguageService.t('all_selected_residents_will_receive_a_push_no'), style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 22),
          AppFieldShell(
            accent: primary,
            child: DropdownButtonFormField<String>(
              value: _target,
              decoration: appFieldDecoration(label: LanguageService.t('send_to'), icon: Icons.group_outlined, accent: primary),
              items: [
                DropdownMenuItem(value: 'all',     child: Text(LanguageService.t('all_residents'))),
                DropdownMenuItem(value: 'owners',  child: Text(LanguageService.t('owners_only'))),
                DropdownMenuItem(value: 'tenants', child: Text(LanguageService.t('tenants_only'))),
              ],
              onChanged: (v) => setState(() => _target = v!),
            ),
          ),
          const SizedBox(height: 14),
          AppFieldShell(accent: primary, child: TextField(controller: _titleCtrl, decoration: appFieldDecoration(label: LanguageService.t('title_2'), icon: Icons.title_rounded, accent: primary))),
          const SizedBox(height: 14),
          AppFieldShell(accent: primary, child: TextField(controller: _messageCtrl, maxLines: 5, decoration: appFieldDecoration(label: LanguageService.t('message'), icon: Icons.message_outlined, accent: primary).copyWith(alignLabelWithHint: true))),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [primary, primary.withOpacity(0.75)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              boxShadow: [BoxShadow(color: primary.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: ElevatedButton.icon(
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Sending...' : 'Send Notification', style: const TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ]))),
      ),
    );
  }
}
