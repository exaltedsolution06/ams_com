import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';

class EmergencyNumbersScreen extends StatefulWidget {
  const EmergencyNumbersScreen({super.key});
  @override
  State<EmergencyNumbersScreen> createState() => _EmergencyNumbersScreenState();
}

class _EmergencyNumbersScreenState extends State<EmergencyNumbersScreen> {
  bool _loading = true;
  String? _error;
  List<Map> _contacts = [];
  final _searchCtrl = TextEditingController();
  String _search = '';
  int? _selectedCategoryId;

  // Apartment Admin only: whether this screen shows management controls,
  // and the full category list (independent of what's already been used by
  // a contact) for the Add/Edit form's category dropdown.
  bool _isAdmin = false;
  List<Map> _formCategories = [];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Apartment Admins manage contacts via /admin/emergency-numbers (full
      // CRUD API); residents get the read-only /emergency-numbers endpoint.
      // Same screen, role-appropriate data and controls.
      final role = await AuthService().effectiveRole();
      final isAdmin = role == 'apartment_admin';
      final endpoint = isAdmin ? '/admin/emergency-numbers' : '/emergency-numbers';
      final res = await ApiService().get(endpoint);

      List<Map> formCategories = _formCategories;
      if (isAdmin) {
        final catRes = await ApiService().get('/admin/general-categories');
        dynamic catData = catRes['data'];
        if (catData is Map) catData = catData['data'];
        formCategories = List<Map>.from(catData ?? []);
      }

      setState(() {
        _isAdmin = isAdmin;
        _formCategories = formCategories;
        // Already sorted newest-first from the API.
        _contacts = List<Map>.from(res['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open dialer for $phone")),
      );
    }
  }

  /// Distinct categories found in the loaded contacts, used to populate the filter dropdown.
  List<Map> get _categoryOptions {
    final seen = <int, Map>{};
    for (final c in _contacts) {
      final cat = c['category'] as Map?;
      if (cat != null && cat['id'] != null) seen[cat['id'] as int] = cat;
    }
    final list = seen.values.toList();
    list.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return list;
  }

  List<Map> get _filteredContacts {
    return _contacts.where((c) {
      final category = c['category'] as Map?;

      if (_selectedCategoryId != null && category?['id'] != _selectedCategoryId) return false;

      if (_search.isNotEmpty) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        final categoryName = (category?['name'] ?? '').toString().toLowerCase();
        if (!name.contains(_search) && !categoryName.contains(_search)) return false;
      }
      return true;
    }).toList();
  }

  void _showForm({Map? contact}) {
    final nameCtrl = TextEditingController(text: contact?['name'] as String? ?? '');
    final descCtrl = TextEditingController(text: contact?['description'] as String? ?? '');
    int? categoryId = (contact?['category'] as Map?)?['id'] as int?;
    final phoneCtrls = <TextEditingController>[
      for (final p in List<String>.from(contact?['phones'] ?? [])) TextEditingController(text: p),
    ];
    if (phoneCtrls.isEmpty) phoneCtrls.add(TextEditingController());
    bool saving = false;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.contact_phone_outlined, color: BrandingService.primary),
              ),
              const SizedBox(width: 12),
              Text(contact == null ? LanguageService.t('add_contact') : LanguageService.t('edit_contact'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: appFieldDecoration(label: LanguageService.t('contact_name'), icon: Icons.badge_outlined, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: DropdownButtonFormField<int?>(
                value: categoryId,
                decoration: appFieldDecoration(label: LanguageService.t('category'), icon: Icons.category_outlined, accent: BrandingService.secondary),
                hint: Text(LanguageService.t('select_category')),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(LanguageService.t('select_category'))),
                  ..._formCategories.map((c) => DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['name'] ?? ''))),
                ],
                onChanged: (v) => setS(() => categoryId = v),
              ),
            ),
            const SizedBox(height: 12),
            Text(LanguageService.t('phone_number'), style: TextStyle(fontSize: 12.5, color: Colors.grey[700], fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...phoneCtrls.asMap().entries.map((entry) {
              final i = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: entry.value,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: LanguageService.t('phone_number'),
                        prefixIcon: const Icon(Icons.call_outlined, size: 20),
                      ),
                    ),
                  ),
                  if (phoneCtrls.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () => setS(() => phoneCtrls.removeAt(i)),
                    ),
                ]),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setS(() => phoneCtrls.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 18),
                label: Text(LanguageService.t('add_phone_number')),
              ),
            ),
            const SizedBox(height: 6),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: BrandingService.primary).copyWith(alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(contact == null ? Icons.add : Icons.save_outlined),
              label: Text(saving ? '' : (contact == null ? LanguageService.t('add_contact') : LanguageService.t('save'))),
              style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: saving ? null : () async {
                final phones = phoneCtrls.map((c) => c.text.trim()).where((p) => p.isNotEmpty).toList();
                if (nameCtrl.text.trim().isEmpty) {
                  setS(() => formError = LanguageService.t('name_required'));
                  return;
                }
                if (phones.isEmpty) {
                  setS(() => formError = LanguageService.t('at_least_one_phone_number_required'));
                  return;
                }
                setS(() { saving = true; formError = null; });
                try {
                  final body = {
                    'name': nameCtrl.text.trim(),
                    'expense_category_id': categoryId,
                    'phones': phones,
                    'description': descCtrl.text.trim(),
                  };
                  if (contact != null) {
                    await ApiService().put('/admin/emergency-numbers/${contact['id']}', body);
                  } else {
                    await ApiService().post('/admin/emergency-numbers', body);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(contact == null ? LanguageService.t('contact_added') : LanguageService.t('contact_updated')),
                      backgroundColor: Colors.green,
                    ));
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

  Future<void> _delete(Map contact) async {
    final ok = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_contact'),
      message: 'Delete "${contact['name']}"?',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (ok != true) return;
    try {
      await ApiService().delete('/admin/emergency-numbers/${contact['id']}');
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('contact_deleted')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final filtered = _filteredContacts;
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('emergency_numbers'))),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add),
              label: Text(LanguageService.t('add_contact')),
              backgroundColor: primary,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_error!, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                  ]),
                )
              : _contacts.isEmpty
                  ? EmptyState(icon: Icons.contact_phone_outlined, title: LanguageService.t('no_emergency_contacts_added_yet'), color: primary)
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: LanguageService.t('search_name_or_category'),
                                prefixIcon: const Icon(Icons.search, size: 20),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primary, width: 1.6)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.category_outlined, size: 16, color: primary),
                              const SizedBox(width: 6),
                              DropdownButton<int?>(
                                value: _selectedCategoryId,
                                hint: Text(LanguageService.t('category'), style: const TextStyle(fontSize: 13)),
                                underline: const SizedBox.shrink(),
                                items: [
                                  DropdownMenuItem<int?>(value: null, child: Text(LanguageService.t('all_categories'))),
                                  ..._categoryOptions.map((c) => DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['name'] ?? ''))),
                                ],
                                onChanged: (v) => setState(() => _selectedCategoryId = v),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? EmptyState(icon: Icons.search_off, title: LanguageService.t('no_emergency_contacts_added_yet'), color: primary)
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding: EdgeInsets.fromLTRB(14, 14, 14, _isAdmin ? 90 : 14),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final c = filtered[i];
                                    final category = c['category'] as Map?;
                                    final phones = List<String>.from(c['phones'] ?? []);
                                    return Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
                                      ),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          Container(
                                            width: 40, height: 40,
                                            decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                            child: Icon(Icons.contact_phone_outlined, color: primary, size: 20),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          ),
                                          if (_isAdmin)
                                            PopupMenuButton<String>(
                                              onSelected: (v) { if (v == 'edit') _showForm(contact: c); if (v == 'delete') _delete(c); },
                                              itemBuilder: (_) => [
                                                PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit_outlined, size: 18), const SizedBox(width: 10), Text(LanguageService.t('edit'))])),
                                                const PopupMenuDivider(),
                                                PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline, size: 18, color: Colors.red), const SizedBox(width: 10), Text(LanguageService.t('delete'), style: const TextStyle(color: Colors.red))])),
                                              ],
                                            ),
                                        ]),
                                        if (category != null) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                                            child: Text(category['name'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                                          ),
                                        ],
                                        if ((c['description'] as String?)?.isNotEmpty == true) ...[
                                          const SizedBox(height: 8),
                                          Text(c['description'], style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
                                        ],
                                        const SizedBox(height: 10),
                                        Wrap(spacing: 8, runSpacing: 8, children: phones.map((p) => OutlinedButton.icon(
                                          onPressed: () => _call(p),
                                          icon: const Icon(Icons.call, size: 16, color: Colors.green),
                                          label: Text(p, style: const TextStyle(fontSize: 13)),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: Colors.green.shade200),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          ),
                                        )).toList()),
                                      ]),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ]),
    );
  }
}
