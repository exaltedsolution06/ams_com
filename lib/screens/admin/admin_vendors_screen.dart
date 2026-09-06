import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/type_helpers.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/admin_screen_header.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminVendorsScreen extends StatefulWidget {
  const AdminVendorsScreen({super.key});
  @override
  State<AdminVendorsScreen> createState() => _VState();
}

class _VState extends State<AdminVendorsScreen> {
  List    _vendors    = [];
  List    _categories = [];
  bool    _loading    = true;
  String? _error;
  final   _searchCtrl = TextEditingController();
  String  _search     = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final vRes = await api.get('/admin/vendors?search=$_search');
      final cRes = await api.get('/admin/general-categories');
      dynamic vR = vRes['data'];
      if (vR is Map) vR = vR['data'];
      dynamic cR = cRes['data'];
      if (cR is Map) cR = cR['data'];
      setState(() {
        _vendors = List.from(vR ?? []);
        _categories = List.from(cR ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _showForm({Map? vendor}) {
    final nameCtrl = TextEditingController(text: vendor?['name'] as String? ?? '');
    final emailCtrl = TextEditingController(text: vendor?['email'] as String? ?? '');
    final gstCtrl = TextEditingController(text: vendor?['gst_number'] as String? ?? '');
    final addrCtrl = TextEditingController(text: vendor?['address'] as String? ?? '');
    final phoneCtrls = <TextEditingController>[
      for (final p in List<String>.from(vendor?['phones'] ?? [])) TextEditingController(text: p),
    ];
    if (phoneCtrls.isEmpty) phoneCtrls.add(TextEditingController());
    bool active = vendor != null ? (toBool(vendor['is_active'])) : true;
    int? catId = vendor?['expense_category_id'] as int?;
    final isEdit = vendor != null;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(
          builder: (ctx, setS) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormSheetHeader(
                  icon: Icons.business_outlined,
                  title: isEdit ? 'Edit Vendor' : 'Add Vendor',
                  accent: BrandingService.primary,
                  onClose: () => Navigator.pop(ctx),
                ),
                FormErrorBanner(message: formError),
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: appFieldDecoration(label: LanguageService.t('vendor_name'), icon: Icons.business_outlined, accent: BrandingService.primary),
                  ),
                ),
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: appFieldDecoration(label: LanguageService.t('email'), icon: Icons.email_outlined, accent: BrandingService.secondary),
                  ),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: DropdownButtonFormField<int>(
                    value: catId,
                    decoration: appFieldDecoration(label: LanguageService.t('category'), icon: Icons.tag, accent: BrandingService.secondary),
                    hint: Text(LanguageService.t('select_category')),
                    items: [
                      DropdownMenuItem<int>(value: null, child: Text(LanguageService.t('no_category'))),
                      ..._categories.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(
                          value: c['id'] as int, child: Text(c['name'] as String? ?? ''))),
                    ],
                    onChanged: (v) => setS(() => catId = v),
                  ),
                ),
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(
                    controller: gstCtrl,
                    decoration: appFieldDecoration(label: LanguageService.t('gst_number_optional'), icon: Icons.numbers, accent: BrandingService.primary),
                  ),
                ),
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(
                    controller: addrCtrl,
                    maxLines: 2,
                    decoration: appFieldDecoration(label: LanguageService.t('address_optional'), icon: Icons.location_on_outlined, accent: BrandingService.secondary)
                        .copyWith(alignLabelWithHint: true),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!)),
                  child: Row(children: [
                    Expanded(child: Text(LanguageService.t('active'))),
                    Switch(
                        value: active,
                        onChanged: (v) => setS(() => active = v),
                        activeColor: BrandingService.primary),
                  ]),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
                  label: Text(isEdit ? 'Save Changes' : 'Add Vendor'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: BrandingService.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    setS(() => formError = null);
                    if (nameCtrl.text.trim().isEmpty) {
                      setS(() => formError = LanguageService.t('vendor_name_required'));
                      return;
                    }
                    try {
                      final phones = phoneCtrls.map((c) => c.text.trim()).where((p) => p.isNotEmpty).toList();
                      final body = {
                        'name': nameCtrl.text.trim(),
                        'phones': phones,
                        'email': emailCtrl.text.trim(),
                        'gst_number': gstCtrl.text.trim(),
                        'address': addrCtrl.text.trim(),
                        'expense_category_id': catId,
                        'is_active': active,
                      };
                      if (isEdit) {
                        await ApiService().put('/admin/vendors/${vendor!['id']}', body);
                      } else {
                        await ApiService().post('/admin/vendors', body);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(isEdit ? 'Vendor updated!' : 'Vendor added!'),
                            backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  Future<void> _delete(Map v) async {
    final ok = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_vendor'),
      message: 'Delete "${v['name']}"?',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (ok == true) {
      try {
        await ApiService().delete('/admin/vendors/${v['id']}');
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _toggleActive(Map v) async {
    try {
      await ApiService().put('/admin/vendors/${v['id']}',
          {'name': v['name'], 'is_active': !(toBool(v['is_active']))});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total    = _vendors.length;
    final active   = _vendors.where((v) => toBool((v as Map)['is_active'])).length;
    final inactive = total - active;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('add_vendor')),
        backgroundColor: Colors.indigo,
      ),
      body: Column(children: [
        AdminScreenHeader(title: LanguageService.t('vendors_payees'), onRefresh: _load),
        if (!_loading && _error == null && _vendors.isNotEmpty)
          AdminStatRow(chips: [
            AdminStatChip(label: LanguageService.t('total'),    value: '$total',    icon: Icons.business_outlined,        color: Colors.indigo),
            AdminStatChip(label: LanguageService.t('active'),   value: '$active',   icon: Icons.check_circle_outline,     color: Colors.green),
            AdminStatChip(label: LanguageService.t('inactive'), value: '$inactive', icon: Icons.pause_circle_outline,     color: Colors.grey),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: LanguageService.t('search_vendors'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                        _load();
                      })
                  : null,
              fillColor: Colors.white,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BrandingService.primary, width: 1.4)),
            ),
            onSubmitted: (v) {
              setState(() => _search = v);
              _load();
            },
            onChanged: (v) {
              if (v.isEmpty) {
                setState(() => _search = '');
                _load();
              }
            },
          ),
        ),
        Expanded(
          child: _buildBody(),
        ),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
          ],
        ),
      );
    }
    if (_vendors.isEmpty) {
      return EmptyState(icon: Icons.business_outlined, title: LanguageService.t('no_vendors_found'), color: BrandingService.primary);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
        itemCount: _vendors.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final v = _vendors[i] as Map;
          final active = toBool(v['is_active']);
          final cat = (v['category'] as Map?)?['name'] as String?;
          final vColor = active ? Colors.indigo : Colors.grey;
          return AdminListCard(
            color: vColor,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
                AdminTileIcon(color: vColor, icon: Icons.business_outlined, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(v['name'] as String? ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        if (!active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(LanguageService.t('inactive'),
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ),
                      ]),
                      if ((v['phones'] as List?)?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 3, bottom: 2),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: List<String>.from(v['phones']).map((p) => InkWell(
                              onTap: () => _call(p),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.call, size: 12, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(p, style: const TextStyle(fontSize: 11.5, color: Colors.green)),
                                ]),
                              ),
                            )).toList(),
                          ),
                        ),
                      if (cat != null)
                        Text(cat, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'edit') _showForm(vendor: v);
                    if (val == 'toggle') _toggleActive(v);
                    if (val == 'delete') _delete(v);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text(LanguageService.t('edit')),
                        ])),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Row(children: [
                          Icon(active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, size: 18),
                          const SizedBox(width: 10),
                          Text(active ? 'Set Inactive' : 'Set Active'),
                        ])),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 10),
                          Text(LanguageService.t('delete'), style: TextStyle(color: Colors.red)),
                        ])),
                  ],
                ),
              ]),
          );
        },
      ),
    );
  }
}
