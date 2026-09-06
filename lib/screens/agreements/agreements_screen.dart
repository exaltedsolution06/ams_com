import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../utils/type_helpers.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';

class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});
  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<AgreementsScreen> {
  bool _loading = true;
  String? _error;
  List<Map> _agreements = [];
  final _searchCtrl = TextEditingController();
  String _search = '';
  int? _selectedCategoryId;

  // Apartment Admin only: whether this screen shows management controls,
  // and the vendor/category lists for the Add/Edit form's dropdowns.
  bool _isAdmin = false;
  List<Map> _formVendors = [];
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
      // Apartment Admins manage agreements via /admin/agreements (full CRUD
      // API); residents get the read-only /agreements endpoint. Same screen,
      // role-appropriate data and controls.
      final role = await AuthService().effectiveRole();
      final isAdmin = role == 'apartment_admin';
      final endpoint = isAdmin ? '/admin/agreements' : '/agreements';
      final res = await ApiService().get(endpoint);

      List<Map> formVendors = _formVendors;
      List<Map> formCategories = _formCategories;
      if (isAdmin) {
        final vRes = await ApiService().get('/admin/vendors');
        dynamic vData = vRes['data'];
        if (vData is Map) vData = vData['data'];
        formVendors = List<Map>.from(vData ?? []).where((v) => toBool(v['is_active'])).toList();

        final cRes = await ApiService().get('/admin/general-categories');
        dynamic cData = cRes['data'];
        if (cData is Map) cData = cData['data'];
        formCategories = List<Map>.from(cData ?? []);
      }

      setState(() {
        _isAdmin = isAdmin;
        _formVendors = formVendors;
        _formCategories = formCategories;
        // Already sorted by expire date (newest/farthest expiry first) from the API.
        _agreements = List<Map>.from(res['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  int _daysLeft(String expireDate) {
    final expiry = DateTime.parse(expireDate);
    return expiry.difference(DateTime.now()).inDays;
  }

  /// Distinct categories found in the loaded agreements, used to populate the filter dropdown.
  List<Map> get _categoryOptions {
    final seen = <int, Map>{};
    for (final a in _agreements) {
      final cat = a['category'] as Map?;
      if (cat != null && cat['id'] != null) seen[cat['id'] as int] = cat;
    }
    final list = seen.values.toList();
    list.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return list;
  }

  List<Map> get _filteredAgreements {
    return _agreements.where((a) {
      final vendor = a['vendor'] as Map? ?? {};
      final category = a['category'] as Map?;

      if (_selectedCategoryId != null && category?['id'] != _selectedCategoryId) return false;

      if (_search.isNotEmpty) {
        final vendorName = (vendor['name'] ?? '').toString().toLowerCase();
        final categoryName = (category?['name'] ?? '').toString().toLowerCase();
        if (!vendorName.contains(_search) && !categoryName.contains(_search)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickDate(BuildContext ctx, DateTime? initial, void Function(DateTime) onPicked) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  String _fmt(DateTime? d) => d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _showForm({Map? agreement}) {
    int? vendorId = (agreement?['vendor'] as Map?)?['id'] as int?;
    int? categoryId = (agreement?['category'] as Map?)?['id'] as int?;
    DateTime? renewDate = DateTime.tryParse(agreement?['renew_date']?.toString() ?? '');
    DateTime? expireDate = DateTime.tryParse(agreement?['expire_date']?.toString() ?? '');
    final amountCtrl = TextEditingController(text: agreement?['amount']?.toString() ?? '');
    String? pickedFilePath;
    String? pickedFileName;
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
                child: Icon(Icons.file_present_outlined, color: BrandingService.primary),
              ),
              const SizedBox(width: 12),
              Text(agreement == null ? LanguageService.t('add_agreement') : LanguageService.t('edit_agreement'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: DropdownButtonFormField<int?>(
                value: vendorId,
                decoration: appFieldDecoration(label: LanguageService.t('vendor'), icon: Icons.store_outlined, accent: BrandingService.primary),
                hint: Text(LanguageService.t('select_vendor')),
                items: _formVendors.map((v) => DropdownMenuItem<int?>(value: v['id'] as int, child: Text(v['name'] ?? ''))).toList(),
                onChanged: (v) => setS(() => vendorId = v),
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
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(ctx, renewDate, (d) => setS(() => renewDate = d)),
                  child: AppFieldShell(
                    accent: BrandingService.primary,
                    child: InputDecorator(
                      decoration: appFieldDecoration(label: LanguageService.t('renew_date'), icon: Icons.event_outlined, accent: BrandingService.primary),
                      child: Text(renewDate == null ? '—' : _fmt(renewDate)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(ctx, expireDate, (d) => setS(() => expireDate = d)),
                  child: AppFieldShell(
                    accent: BrandingService.secondary,
                    child: InputDecorator(
                      decoration: appFieldDecoration(label: LanguageService.t('expire_date'), icon: Icons.event_busy_outlined, accent: BrandingService.secondary),
                      child: Text(expireDate == null ? '—' : _fmt(expireDate)),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: appFieldDecoration(label: LanguageService.t('amount_optional'), icon: Icons.currency_rupee, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png']);
                if (result != null && result.files.single.path != null) {
                  setS(() {
                    pickedFilePath = result.files.single.path;
                    pickedFileName = result.files.single.name;
                  });
                }
              },
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(pickedFileName ?? (agreement?['file_url'] != null ? LanguageService.t('replace_document') : LanguageService.t('upload_document_optional'))),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(agreement == null ? Icons.add : Icons.save_outlined),
              label: Text(agreement == null ? LanguageService.t('add_agreement') : LanguageService.t('save')),
              style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                setS(() => formError = null);
                if (vendorId == null) {
                  setS(() => formError = LanguageService.t('vendor_required'));
                  return;
                }
                if (renewDate == null || expireDate == null) {
                  setS(() => formError = LanguageService.t('dates_required'));
                  return;
                }
                if (!expireDate!.isAfter(renewDate!)) {
                  setS(() => formError = LanguageService.t('expire_date_must_be_after_renew_date'));
                  return;
                }
                try {
                  final fields = <String, String>{
                    'vendor_id': vendorId.toString(),
                    'renew_date': _fmt(renewDate),
                    'expire_date': _fmt(expireDate),
                  };
                  if (categoryId != null) fields['expense_category_id'] = categoryId.toString();
                  if (amountCtrl.text.trim().isNotEmpty) fields['amount'] = amountCtrl.text.trim();

                  if (agreement != null) {
                    await ApiService().uploadMultipart(
                      '/admin/agreements/${agreement['id']}',
                      fields,
                      filePath: pickedFilePath,
                      fileField: 'file',
                      httpMethod: 'PUT',
                    );
                  } else {
                    await ApiService().uploadMultipart(
                      '/admin/agreements',
                      fields,
                      filePath: pickedFilePath,
                      fileField: 'file',
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(agreement == null ? LanguageService.t('agreement_added') : LanguageService.t('agreement_updated')),
                      backgroundColor: Colors.green,
                    ));
                  }
                } catch (e) {
                  setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                }
              },
            ),
          ]),
        )),
      ),
    );
  }

  Future<void> _delete(Map agreement) async {
    final vendor = agreement['vendor'] as Map? ?? {};
    final ok = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_agreement'),
      message: 'Delete agreement with "${vendor['name'] ?? ''}"?',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (ok != true) return;
    try {
      await ApiService().delete('/admin/agreements/${agreement['id']}');
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('agreement_deleted')), backgroundColor: Colors.green));
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
    final filtered = _filteredAgreements;
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('agreements'))),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add),
              label: Text(LanguageService.t('add_agreement')),
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
              : _agreements.isEmpty
                  ? EmptyState(icon: Icons.description_outlined, title: LanguageService.t('no_agreements_added_yet'), color: primary)
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: LanguageService.t('search_vendor_or_category'),
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
                            ? EmptyState(icon: Icons.search_off, title: LanguageService.t('no_agreements_added_yet'), color: primary)
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding: EdgeInsets.fromLTRB(14, 14, 14, _isAdmin ? 90 : 14),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final a = filtered[i];
                                    final vendor = a['vendor'] as Map? ?? {};
                                    final category = a['category'] as Map?;
                                    final daysLeft = _daysLeft(a['expire_date']);
                                    final isExpired = daysLeft < 0;
                                    final isExpiringSoon = !isExpired && daysLeft <= 15;
                                    final statusColor = isExpired ? Colors.red : (isExpiringSoon ? Colors.orange : Colors.green);
                                    final statusText = isExpired ? 'Expired' : (isExpiringSoon ? 'Expiring in ${daysLeft}d' : 'Active');

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
                                            child: Icon(Icons.file_present_outlined, color: primary, size: 20),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(vendor['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                                            child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
                                          ),
                                          if (_isAdmin)
                                            PopupMenuButton<String>(
                                              onSelected: (v) { if (v == 'edit') _showForm(agreement: a); if (v == 'delete') _delete(a); },
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
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          Expanded(child: _kv('Renew', _displayDate(a['renew_date']))),
                                          Expanded(child: _kv('Expire', _displayDate(a['expire_date']))),
                                          if (a['amount'] != null) Expanded(child: _kv('Amount', '${BrandingService.currencySymbol}${a['amount']}')),
                                        ]),
                                        if (a['file_url'] != null) ...[
                                          const SizedBox(height: 10),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final uri = Uri.parse(a['file_url']);
                                              if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                                            },
                                            icon: const Icon(Icons.download_outlined, size: 16),
                                            label: Text(LanguageService.t('view_document'), style: TextStyle(fontSize: 12.5)),
                                            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                          ),
                                        ],
                                      ]),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ]),
    );
  }

  // Card display only - the raw yyyy-MM-dd value from the API keeps being
  // used everywhere else (_daysLeft() parsing, form submission via _fmt())
  // so nothing about what's sent to/read from the backend changes.
  // Delegates to BrandingService so this respects each apartment's own
  // Date Format choice (Profile > Settings > Date Format) instead of a
  // format hardcoded into this one screen.
  String _displayDate(String? raw) => BrandingService.formatDateString(raw);

  Widget _kv(String label, String? value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(value ?? '—', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]);
}
