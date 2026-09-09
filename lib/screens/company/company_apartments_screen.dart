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

Map<String, String> get _kAptTypes => {
  'with_tower': LanguageService.t('with_towers'),
  'without_tower': LanguageService.t('without_towers_direct_flats'),
};

class CompanyApartmentsScreen extends StatefulWidget {
  const CompanyApartmentsScreen({super.key});
  @override
  State<CompanyApartmentsScreen> createState() => _CompanyApartmentsScreenState();
}

class _CompanyApartmentsScreenState extends State<CompanyApartmentsScreen> {
  List _apartments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/apartments');
      setState(() { _apartments = List.from(res['data'] as List? ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  void _showForm({Map? apartment}) {
    final isEdit = apartment != null;
    final nameCtrl = TextEditingController(text: apartment?['name'] as String? ?? '');
    final addressCtrl = TextEditingController(text: apartment?['address'] as String? ?? '');
    final cityCtrl = TextEditingController(text: apartment?['city'] as String? ?? '');
    final stateCtrl = TextEditingController(text: apartment?['state'] as String? ?? '');
    final pincodeCtrl = TextEditingController(text: apartment?['pincode'] as String? ?? '');
    String type = apartment?['apartment_type'] as String? ?? 'without_tower';
    bool saving = false;
    String? formError;

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
                child: Icon(Icons.apartment, color: BrandingService.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(isEdit ? LanguageService.t('edit_apartment') : LanguageService.t('new_apartment'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: appFieldDecoration(label: LanguageService.t('apartment_name'), icon: Icons.apartment, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: DropdownButtonFormField<String>(
                value: type,
                items: _kAptTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setS(() => type = v ?? type),
                decoration: appFieldDecoration(label: LanguageService.t('structure'), icon: Icons.layers_outlined, accent: BrandingService.secondary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: addressCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('address'), icon: Icons.location_on_outlined, accent: BrandingService.primary).copyWith(alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(controller: cityCtrl, decoration: appFieldDecoration(label: LanguageService.t('city'), icon: Icons.location_city_outlined, accent: BrandingService.secondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(controller: stateCtrl, decoration: appFieldDecoration(label: LanguageService.t('state'), icon: Icons.map_outlined, accent: BrandingService.primary)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: pincodeCtrl,
                keyboardType: TextInputType.number,
                decoration: appFieldDecoration(label: LanguageService.t('pincode'), icon: Icons.pin_drop_outlined, accent: BrandingService.secondary),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isEdit ? Icons.save_outlined : Icons.add_business_outlined),
              label: Text(saving ? '' : (isEdit ? LanguageService.t('save') : LanguageService.t('create_apartment'))),
              style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                  if (nameCtrl.text.trim().isEmpty || addressCtrl.text.trim().isEmpty ||
                      cityCtrl.text.trim().isEmpty || stateCtrl.text.trim().isEmpty || pincodeCtrl.text.trim().isEmpty) {
                    setS(() => formError = LanguageService.t('please_fill_all_required_fields'));
                    return;
                  }
                  setS(() { saving = true; formError = null; });
                  final payload = {
                    'name': nameCtrl.text.trim(),
                    'apartment_type': type,
                    'address': addressCtrl.text.trim(),
                    'city': cityCtrl.text.trim(),
                    'state': stateCtrl.text.trim(),
                    'pincode': pincodeCtrl.text.trim(),
                  };
                  try {
                    if (isEdit) {
                      await ApiService().put('/company/apartments/${apartment['id']}', {...payload, 'is_active': apartment['is_active'] ?? true});
                    } else {
                      await ApiService().post('/company/apartments', payload);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
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

  Future<void> _toggleActive(Map apt) async {
    try {
      await ApiService().put('/company/apartments/${apt['id']}', {
        'name': apt['name'],
        'apartment_type': apt['apartment_type'],
        'address': apt['address'],
        'city': apt['city'],
        'state': apt['state'],
        'pincode': apt['pincode'],
        'is_active': !(apt['is_active'] == true),
      });
      _load();
    } catch (e) {
      if (mounted) AmsDialog.info(context, title: LanguageService.t('error'), message: e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _delete(Map apt) async {
    final confirmed = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_apartment'),
      message: LanguageService.t('delete_apartment_confirm'),
      confirmText: LanguageService.t('delete'),
      icon: Icons.delete_outline,
      danger: true,
    );
    if (confirmed != true) return;
    try {
      await ApiService().delete('/company/apartments/${apt['id']}');
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
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('apartments'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('new_apartment')),
        backgroundColor: primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _apartments.isEmpty
                      ? ListView(children: [
                          Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.apartment_outlined, color: BrandingService.primary, title: LanguageService.t('no_apartments_yet_tap_to_add_one'))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _apartments.length,
                          itemBuilder: (ctx, i) {
                            final a = _apartments[i];
                            final sub = a['active_subscription'] as Map?;
                            final code = a['apartment_code'] as String?;
                            final address = [a['address'], a['city']].where((v) => v != null && (v as String).isNotEmpty).join(', ');
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                  Expanded(
                                    child: ListTile(
                                      leading: CircleAvatar(backgroundColor: primary.withOpacity(0.12), child: Icon(Icons.apartment, color: primary)),
                                      title: Row(children: [
                                        Flexible(child: Text(a['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                        if (code != null && code.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text('· $code', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                        ],
                                      ]),
                                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        if (address.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                                            child: Text(address, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ),
                                        Text(
                                          '${a['flats_count'] ?? 0} ${LanguageService.t('flats')} · ${a['residents_count'] ?? 0} ${LanguageService.t('residents')} · ${a['towers_count'] ?? 0} ${LanguageService.t('towers')}'
                                          '${sub != null ? ' · ${(sub['plan'] as Map?)?['name'] ?? ''}' : ' · ${LanguageService.t('no_plan')}'}',
                                        ),
                                      ]),
                                      onTap: () => _showForm(apartment: a as Map),
                                      trailing: GestureDetector(
                                        onTap: () => _toggleActive(a as Map),
                                        child: Icon(Icons.circle, size: 12, color: (a['is_active'] == true) ? Colors.green : Colors.grey),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: LanguageService.t('delete_apartment'),
                                    onPressed: () => _delete(a as Map),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
