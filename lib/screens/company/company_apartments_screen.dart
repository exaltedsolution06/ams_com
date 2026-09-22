import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../utils/type_helpers.dart';

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

  // Item 8: same "Country" list (GET /countries/all) and "Plan" list (this
  // company's own plans, GET /company/plans) the website's Company Admin ->
  // Add Apartment form offers - loaded once up front so the Add/Edit sheet
  // can open instantly.
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCountries();
    _loadPlans();
  }

  Future<void> _loadCountries() async {
    try {
      final res = await ApiService().get('/countries/all');
      final list = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _countries = list);
    } catch (_) {/* Country dropdown just stays empty; form still works. */}
  }

  Future<void> _loadPlans() async {
    try {
      final res = await ApiService().get('/company/plans');
      final list = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _plans = list);
    } catch (_) {/* Plan section just stays empty/optional; form still works. */}
  }

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
    final contactNameCtrl = TextEditingController(text: apartment?['contact_name'] as String? ?? '');
    final contactPhoneCtrl = TextEditingController(text: apartment?['contact_phone'] as String? ?? '');
    final contactEmailCtrl = TextEditingController(text: apartment?['contact_email'] as String? ?? '');
    final amountPaidCtrl = TextEditingController(text: '0');
    final paymentRefCtrl = TextEditingController();
    String type = apartment?['apartment_type'] as String? ?? 'without_tower';
    String? country = apartment?['country'] as String?;
    if (country == null || country.isEmpty) {
      final india = _countries.firstWhere((c) => c['iso2'] == 'IN', orElse: () => <String, dynamic>{});
      country = (india['name'] as String?) ?? (_countries.isNotEmpty ? _countries.first['name'] as String? : null);
    }
    int? planId;
    XFile? pickedLogo;
    bool saving = false;
    String? formError;
    // Item 5: field -> error message, shown under that specific field
    // instead of one generic "Please fill all required fields" banner -
    // populated either by the client-side required check below, or from
    // ApiValidationException.errors when the server rejects the submit.
    Map<String, String> fieldErrors = {};

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
                decoration: appFieldDecoration(label: LanguageService.t('apartment_name'), icon: Icons.apartment, accent: BrandingService.primary).copyWith(errorText: fieldErrors['name']),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: DropdownButtonFormField<String>(
                value: type,
                items: _kAptTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setS(() => type = v ?? type),
                decoration: appFieldDecoration(label: LanguageService.t('structure'), icon: Icons.layers_outlined, accent: BrandingService.secondary).copyWith(errorText: fieldErrors['apartment_type']),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: addressCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('address'), icon: Icons.location_on_outlined, accent: BrandingService.primary).copyWith(alignLabelWithHint: true, errorText: fieldErrors['address']),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: DropdownButtonFormField<String>(
                value: _countries.any((c) => c['name'] == country) ? country : null,
                isExpanded: true,
                items: _countries
                    .map((c) => DropdownMenuItem(value: c['name'] as String, child: Text(c['name'] as String, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setS(() => country = v),
                decoration: appFieldDecoration(label: LanguageService.t('country'), icon: Icons.public_outlined, accent: BrandingService.secondary).copyWith(errorText: fieldErrors['country']),
              ),
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(controller: cityCtrl, decoration: appFieldDecoration(label: LanguageService.t('city'), icon: Icons.location_city_outlined, accent: BrandingService.secondary).copyWith(errorText: fieldErrors['city'])),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(controller: stateCtrl, decoration: appFieldDecoration(label: LanguageService.t('state'), icon: Icons.map_outlined, accent: BrandingService.primary).copyWith(errorText: fieldErrors['state'])),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: pincodeCtrl,
                keyboardType: TextInputType.number,
                decoration: appFieldDecoration(label: LanguageService.t('pincode'), icon: Icons.pin_drop_outlined, accent: BrandingService.secondary).copyWith(errorText: fieldErrors['pincode']),
              ),
            ),
            const SizedBox(height: 20),
            Text(LanguageService.t('contact_person'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 10),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(controller: contactNameCtrl, decoration: appFieldDecoration(label: LanguageService.t('contact_name'), icon: Icons.person_outline, accent: BrandingService.primary).copyWith(errorText: fieldErrors['contact_name'])),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(controller: contactPhoneCtrl, keyboardType: TextInputType.phone, decoration: appFieldDecoration(label: LanguageService.t('contact_phone'), icon: Icons.phone_outlined, accent: BrandingService.secondary).copyWith(errorText: fieldErrors['contact_phone'])),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(controller: contactEmailCtrl, keyboardType: TextInputType.emailAddress, decoration: appFieldDecoration(label: LanguageService.t('contact_email'), icon: Icons.email_outlined, accent: BrandingService.primary).copyWith(errorText: fieldErrors['contact_email'])),
            ),
            const SizedBox(height: 14),
            // Logo - optional, same as the website's Add Apartment form.
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (picked != null) setS(() => pickedLogo = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  if (pickedLogo != null)
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(pickedLogo!.path), width: 40, height: 40, fit: BoxFit.cover))
                  else
                    Icon(Icons.image_outlined, color: Colors.grey[500]),
                  const SizedBox(width: 10),
                  Expanded(child: Text(pickedLogo != null ? pickedLogo!.name : LanguageService.t('logo'), overflow: TextOverflow.ellipsis)),
                  Icon(Icons.upload_outlined, size: 18, color: Colors.grey[500]),
                ]),
              ),
            ),
            if (!isEdit && _plans.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('${LanguageService.t('subscription_plan')} (${LanguageService.t('optional')})', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[600])),
              const SizedBox(height: 10),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: DropdownButtonFormField<int>(
                  value: planId,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<int>(value: null, child: Text(LanguageService.t('no_plan_yet_free'))),
                    for (final p in _plans)
                      DropdownMenuItem<int>(
                        value: p['id'] as int,
                        child: Text(
                          '${p['name']} — ${toNum(p['price']) > 0 ? BrandingService.currencySymbol + toNum(p['price']).toString() : LanguageService.t('free')}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setS(() => planId = v),
                  decoration: appFieldDecoration(label: LanguageService.t('plan'), icon: Icons.card_membership_outlined, accent: BrandingService.secondary),
                ),
              ),
              if (planId != null) ...[
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(
                    controller: amountPaidCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: appFieldDecoration(label: '${LanguageService.t('amount_paid')} (${BrandingService.currencySymbol})', icon: Icons.payments_outlined, accent: BrandingService.primary),
                  ),
                ),
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(
                    controller: paymentRefCtrl,
                    decoration: appFieldDecoration(label: LanguageService.t('payment_reference'), icon: Icons.receipt_long_outlined, accent: BrandingService.secondary),
                  ),
                ),
              ],
            ],
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
                  // Item 5: per-field messages instead of one generic
                  // "Please fill all required fields" banner - only the
                  // fields that are actually empty get an error, under
                  // that field.
                  final required = <String, String>{
                    'name': nameCtrl.text.trim(),
                    'address': addressCtrl.text.trim(),
                    'country': country ?? '',
                    'city': cityCtrl.text.trim(),
                    'state': stateCtrl.text.trim(),
                    'pincode': pincodeCtrl.text.trim(),
                  };
                  final clientErrors = <String, String>{
                    for (final e in required.entries)
                      if (e.value.isEmpty) e.key: LanguageService.t('this_field_is_required'),
                  };
                  if (clientErrors.isNotEmpty) {
                    setS(() { fieldErrors = clientErrors; formError = LanguageService.t('please_fill_all_required_fields'); });
                    return;
                  }
                  setS(() { saving = true; formError = null; fieldErrors = {}; });
                  final fields = <String, String>{
                    'name': nameCtrl.text.trim(),
                    'apartment_type': type,
                    'address': addressCtrl.text.trim(),
                    'country': country ?? '',
                    'city': cityCtrl.text.trim(),
                    'state': stateCtrl.text.trim(),
                    'pincode': pincodeCtrl.text.trim(),
                    'contact_name': contactNameCtrl.text.trim(),
                    'contact_phone': contactPhoneCtrl.text.trim(),
                    'contact_email': contactEmailCtrl.text.trim(),
                    if (isEdit) 'is_active': (apartment['is_active'] ?? true).toString(),
                    if (!isEdit && planId != null) 'plan_id': planId.toString(),
                    if (!isEdit && planId != null) 'amount_paid': amountPaidCtrl.text.trim().isEmpty ? '0' : amountPaidCtrl.text.trim(),
                    if (!isEdit && planId != null) 'payment_reference': paymentRefCtrl.text.trim(),
                  };
                  try {
                    if (isEdit) {
                      await ApiService().uploadMultipart(
                        '/company/apartments/${apartment['id']}', fields,
                        filePath: pickedLogo?.path, fileField: 'logo', httpMethod: 'PUT',
                      );
                    } else {
                      await ApiService().uploadMultipart(
                        '/company/apartments', fields,
                        filePath: pickedLogo?.path, fileField: 'logo',
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  } catch (e) {
                    // Item 5: a server-side validation failure (422) shows
                    // each field's own message under that field, same as
                    // the client-side check above - not just the first one
                    // in a single generic banner.
                    if (e is ApiValidationException) {
                      setS(() {
                        saving = false;
                        fieldErrors = e.errors.map((k, v) => MapEntry(k, v.first));
                        formError = LanguageService.t('please_fill_all_required_fields');
                      });
                    } else {
                      setS(() { saving = false; formError = e.toString().replaceAll('Exception: ', ''); });
                    }
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
        'country': apt['country'],
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
