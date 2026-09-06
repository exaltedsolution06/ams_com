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

Map<String, String> get _kAllModules => {
  'dashboard': LanguageService.t('dashboard'), 'billing': LanguageService.t('billing'), 'expenses': LanguageService.t('expenses'),
  'complaints': LanguageService.t('complaints'), 'visitors': LanguageService.t('visitors'), 'notices': LanguageService.t('notices'),
  'facilities': LanguageService.t('facilities'), 'parking': LanguageService.t('parking'), 'agreements': LanguageService.t('agreements'),
  'emergency_numbers': LanguageService.t('emergency_numbers'), 'reports': LanguageService.t('reports'),
  'bulk_notify': LanguageService.t('bulk_notify'), 'branding': LanguageService.t('branding'), 'chat': LanguageService.t('chat'),
};

class CompanyPlansScreen extends StatefulWidget {
  const CompanyPlansScreen({super.key});
  @override
  State<CompanyPlansScreen> createState() => _CompanyPlansScreenState();
}

class _CompanyPlansScreenState extends State<CompanyPlansScreen> {
  List _plans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/plans');
      setState(() { _plans = List.from(res['data'] as List? ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  String _money(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '0') ?? 0;
    return '₹${d.toStringAsFixed(0)}';
  }

  void _showForm({Map? plan}) {
    final isEdit = plan != null;
    final nameCtrl = TextEditingController(text: plan?['name'] as String? ?? '');
    final slugCtrl = TextEditingController(text: plan?['slug'] as String? ?? '');
    final priceCtrl = TextEditingController(text: (plan?['price'] ?? 0).toString());
    final durationCtrl = TextEditingController(text: (plan?['duration_days'] ?? 365).toString());
    final maxFlatsCtrl = TextEditingController(text: (plan?['max_flats'] ?? 0).toString());
    final descCtrl = TextEditingController(text: plan?['description'] as String? ?? '');
    final selectedModules = <String>{...(plan?['modules'] as List? ?? []).map((m) => m.toString())};
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
                child: Icon(Icons.card_membership_rounded, color: BrandingService.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(isEdit ? LanguageService.t('edit_plan') : LanguageService.t('new_apartment_plan'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: appFieldDecoration(label: LanguageService.t('plan_name'), icon: Icons.card_membership_rounded, accent: BrandingService.primary),
              ),
            ),
            if (!isEdit) ...[
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: TextField(
                  controller: slugCtrl,
                  decoration: appFieldDecoration(label: LanguageService.t('slug_e_g_yearly_pro'), icon: Icons.tag, accent: BrandingService.secondary),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: LanguageService.t('price_currency'), icon: Icons.currency_rupee, accent: BrandingService.primary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(controller: durationCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: LanguageService.t('duration_days'), icon: Icons.event_repeat_outlined, accent: BrandingService.secondary)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(controller: maxFlatsCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: LanguageService.t('max_flats_0_unlimited'), icon: Icons.door_front_door_outlined, accent: BrandingService.primary)),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('description'), icon: Icons.notes_outlined, accent: BrandingService.secondary).copyWith(alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.extension_outlined, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(LanguageService.t('included_modules'), style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800], fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _kAllModules.entries.map((e) => FilterChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: selectedModules.contains(e.key),
                selectedColor: BrandingService.primary.withOpacity(0.15),
                checkmarkColor: BrandingService.primary,
                onSelected: (v) => setS(() => v ? selectedModules.add(e.key) : selectedModules.remove(e.key)),
              )).toList(),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
              label: Text(saving ? '' : (isEdit ? LanguageService.t('save') : LanguageService.t('create_plan'))),
              style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                  setS(() { saving = true; formError = null; });
                  try {
                    final payload = {
                      'name': nameCtrl.text.trim(),
                      'price': double.tryParse(priceCtrl.text) ?? 0,
                      'duration_days': int.tryParse(durationCtrl.text) ?? 0,
                      'max_flats': int.tryParse(maxFlatsCtrl.text) ?? 0,
                      'description': descCtrl.text.trim(),
                      'modules': selectedModules.toList(),
                    };
                    if (isEdit) {
                      await ApiService().put('/company/plans/${plan['id']}', payload);
                    } else {
                      await ApiService().post('/company/plans', {...payload, 'slug': slugCtrl.text.trim()});
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

  void _showAssignDialog(Map plan) async {
    List apartments = [];
    try {
      final res = await ApiService().get('/admin/apartments');
      apartments = List.from(res['data'] as List? ?? []);
    } catch (_) {}
    if (!mounted) return;
    if (apartments.isEmpty) {
      AmsDialog.info(context, title: LanguageService.t('no_apartments'), message: LanguageService.t('no_apartments_to_assign_plan_own'));
      return;
    }
    int? selectedAptId = apartments.first['id'] as int?;
    final amountCtrl = TextEditingController(text: (plan['price'] ?? 0).toString());
    bool saving = false;
    String? formError;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(Icons.card_membership_rounded, color: BrandingService.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('${LanguageService.t('assign')} "${plan['name']}"', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        FormErrorBanner(message: formError),
        AppFieldShell(
          accent: BrandingService.primary,
          child: DropdownButtonFormField<int>(
            value: selectedAptId,
            items: apartments.map<DropdownMenuItem<int>>((a) => DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? ''))).toList(),
            onChanged: (v) => setS(() => selectedAptId = v),
            decoration: appFieldDecoration(label: LanguageService.t('apartment'), icon: Icons.apartment_rounded, accent: BrandingService.primary),
          ),
        ),
        const SizedBox(height: 14),
        AppFieldShell(
          accent: BrandingService.secondary,
          child: TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: appFieldDecoration(label: LanguageService.t('amount_received_currency'), icon: Icons.payments_outlined, accent: BrandingService.secondary),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('cancel'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: BrandingService.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: saving ? null : () async {
            setS(() { saving = true; formError = null; });
            try {
              await ApiService().post('/company/plans/assign', {
                'apartment_id': selectedAptId,
                'plan_id': plan['id'],
                'amount_paid': double.tryParse(amountCtrl.text) ?? 0,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) AmsDialog.info(context, title: LanguageService.t('done'), message: LanguageService.t('plan_assigned'));
            } catch (e) {
              setS(() { saving = false; formError = e.toString().replaceAll('Exception: ', ''); });
            }
          },
          child: saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(LanguageService.t('assign')),
        ),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('my_plans'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('new_plan')),
        backgroundColor: primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _plans.isEmpty
                      ? ListView(children: [
                          Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.card_membership_outlined, color: BrandingService.primary, title: LanguageService.t('no_plans_yet_tap_to_create_one'))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _plans.length,
                          itemBuilder: (ctx, i) {
                            final p = _plans[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(p['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                    Icon(Icons.circle, size: 9, color: (p['is_active'] == true) ? Colors.green : Colors.grey),
                                  ]),
                                  Text('${_money(p['price'])} · ${p['duration_days']} ${LanguageService.t('days_lc')} · ${LanguageService.t('max_lc')} ${p['max_flats'] == 0 ? '∞' : p['max_flats']} ${LanguageService.t('flats_lc')}',
                                      style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showForm(plan: p),
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      label: Text(LanguageService.t('edit')),
                                      style: OutlinedButton.styleFrom(foregroundColor: primary, side: BorderSide(color: primary.withOpacity(0.4))),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () => _showAssignDialog(p),
                                      icon: const Icon(Icons.send_outlined, size: 16),
                                      label: Text(LanguageService.t('assign_to_apartment')),
                                      style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
                                    ),
                                  ]),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
