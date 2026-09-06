import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminFlatChargeOverridesScreen extends StatefulWidget {
  const AdminFlatChargeOverridesScreen({super.key});
  @override
  State<AdminFlatChargeOverridesScreen> createState() => _AdminFlatChargeOverridesScreenState();
}

class _AdminFlatChargeOverridesScreenState extends State<AdminFlatChargeOverridesScreen> {
  List _flats = [];
  List _charges = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService().get('/admin/flats'),
        ApiService().get('/admin/maintenance-charges'),
      ]);
      var flatsRaw = results[0]['data'];
      if (flatsRaw is Map && flatsRaw.containsKey('data')) flatsRaw = flatsRaw['data'];
      var chargesRaw = results[1]['data'];
      if (chargesRaw is Map && chargesRaw.containsKey('data')) chargesRaw = chargesRaw['data'];
      setState(() {
        _flats = List.from(flatsRaw ?? []).where((f) => f['status'] != 'vacant').toList();
        _charges = List.from(chargesRaw ?? []).where((c) => c['is_active'] == true).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Map? _overrideFor(Map flat, int chargeId) {
    final list = (flat['flat_maintenance_charges'] as List?) ?? [];
    for (final o in list) {
      if (o['maintenance_charge_id'] == chargeId) return o as Map;
    }
    return null;
  }

  double _totalFor(Map flat) {
    double total = 0;
    final area = double.tryParse(flat['area_sqft']?.toString() ?? '0') ?? 0;
    for (final c in _charges) {
      final ov = _overrideFor(flat, c['id'] as int);
      if (ov == null) {
        total += double.tryParse(c['amount'].toString()) ?? 0;
      } else if (ov['charge_type'] == 'per_sqft') {
        total += area * (double.tryParse(ov['per_sqft_rate']?.toString() ?? '0') ?? 0);
      } else {
        total += double.tryParse(ov['override_amount']?.toString() ?? '') ?? (double.tryParse(c['amount'].toString()) ?? 0);
      }
    }
    return total;
  }

  void _openOverrideSheet(Map flat) {
    final sym = BrandingService.currencySymbol;
    final area = double.tryParse(flat['area_sqft']?.toString() ?? '0') ?? 0;
    final Map<int, String> chargeType = {};
    final Map<int, TextEditingController> fixedCtrl = {};
    final Map<int, TextEditingController> sqftCtrl = {};

    for (final c in _charges) {
      final id = c['id'] as int;
      final ov = _overrideFor(flat, id);
      chargeType[id] = ov?['charge_type'] ?? 'fixed';
      fixedCtrl[id] = TextEditingController(text: ov?['override_amount']?.toString() ?? '');
      sqftCtrl[id]  = TextEditingController(text: ov?['per_sqft_rate']?.toString() ?? '');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) {
          bool saving = false;
          String? formError;
          return SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.tune_rounded, color: Colors.orange, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Flat ${flat['flat_number']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(area > 0 ? '${area.toStringAsFixed(0)} sqft' : 'Area not set', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              FormErrorBanner(message: formError),
              if (_charges.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(children: [
                    Icon(Icons.currency_rupee_outlined, size: 34, color: Colors.grey[400]),
                    const SizedBox(height: 10),
                    Text(LanguageService.t('add_a_charge_type_first_from_the_main_charge'),
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
                  ]),
                )
              else
                ..._charges.map((c) {
                  final id = c['id'] as int;
                  final isPerSqft = chargeType[id] == 'per_sqft';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.receipt_long_outlined, size: 15, color: BrandingService.primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                      ]),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Text('Default: $sym${c['amount']}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text(LanguageService.t('fixed')),
                            selected: !isPerSqft,
                            selectedColor: BrandingService.primary,
                            labelStyle: TextStyle(color: !isPerSqft ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 12.5),
                            backgroundColor: Colors.grey[100],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: !isPerSqft ? BrandingService.primary : Colors.grey.shade300)),
                            onSelected: (_) => setS(() => chargeType[id] = 'fixed'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Text(LanguageService.t('per_sqft')),
                            selected: isPerSqft,
                            selectedColor: BrandingService.primary,
                            labelStyle: TextStyle(color: isPerSqft ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 12.5),
                            backgroundColor: Colors.grey[100],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isPerSqft ? BrandingService.primary : Colors.grey.shade300)),
                            onSelected: (_) => setS(() => chargeType[id] = 'per_sqft'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (!isPerSqft)
                        AppFieldShell(
                          accent: BrandingService.primary,
                          child: TextField(
                            controller: fixedCtrl[id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: appFieldDecoration(
                              label: 'Override amount ($sym) — blank uses default',
                              icon: Icons.currency_rupee_rounded, accent: BrandingService.primary,
                            ),
                          ),
                        )
                      else
                        AppFieldShell(
                          accent: BrandingService.primary,
                          child: TextField(
                            controller: sqftCtrl[id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: appFieldDecoration(
                              label: 'Rate per sqft ($sym)',
                              icon: Icons.square_foot_rounded, accent: BrandingService.primary,
                            ).copyWith(
                              helperText: area > 0
                                  ? '= $sym${(area * (double.tryParse(sqftCtrl[id]!.text) ?? 0)).toStringAsFixed(2)} for $area sqft'
                                  : 'Set the flat\'s area first to compute total',
                            ),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                    ]),
                  );
                }),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(colors: [Colors.orange, Color(0xFFE65100)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
                ),
                child: ElevatedButton.icon(
                icon: saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'Saving...' : 'Save Overrides', style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: _charges.isEmpty ? null : () async {
                  setS(() { saving = true; formError = null; });
                  try {
                    final payload = _charges.map((c) {
                      final id = c['id'] as int;
                      return {
                        'charge_id': id,
                        'charge_type': chargeType[id],
                        'override_amount': chargeType[id] == 'fixed' && fixedCtrl[id]!.text.trim().isNotEmpty
                            ? double.tryParse(fixedCtrl[id]!.text.trim()) : null,
                        'per_sqft_rate': chargeType[id] == 'per_sqft' && sqftCtrl[id]!.text.trim().isNotEmpty
                            ? double.tryParse(sqftCtrl[id]!.text.trim()) : null,
                      };
                    }).toList();
                    await ApiService().put('/admin/flats/${flat['id']}/charges', {'charges': payload});
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Charges updated for Flat ${flat['flat_number']}.'), backgroundColor: Colors.green));
                  } catch (e) {
                    setS(() { saving = false; formError = e.toString().replaceAll('Exception: ', ''); });
                  }
                },
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sym = BrandingService.currencySymbol;
    final filtered = _search.isEmpty
        ? _flats
        : _flats.where((f) => (f['flat_number'] ?? '').toString().toLowerCase().contains(_search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard'),
        ),
        title: Text(LanguageService.t('flat_wise_charge_overrides')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
              : Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.06)),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        LanguageService.t('set_a_fixed_override_or_a_per_sqft_rate_for_a'),
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      )),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: AppFieldShell(
                      accent: BrandingService.primary,
                      child: TextField(
                        decoration: appFieldDecoration(
                          label: LanguageService.t('search_flat_number'),
                          icon: Icons.search_rounded, accent: BrandingService.primary,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? EmptyState(
                            icon: Icons.door_front_door_outlined,
                            color: BrandingService.primary,
                            title: LanguageService.t('no_occupied_flats_found'),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final f = filtered[i];
                                final total = _totalFor(f);
                                return Card(
                                  child: ListTile(
                                    onTap: () => _openOverrideSheet(f),
                                    leading: CircleAvatar(
                                      backgroundColor: BrandingService.primary.withOpacity(0.1),
                                      child: Text(f['flat_number']?.toString().substring(0, 1) ?? '?',
                                          style: TextStyle(color: BrandingService.primary, fontWeight: FontWeight.bold)),
                                    ),
                                    title: Text('Flat ${f['flat_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(f['area_sqft'] != null ? '${f['area_sqft']} sqft' : 'Area not set',
                                        style: const TextStyle(fontSize: 12)),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('$sym${total.toStringAsFixed(0)}',
                                            style: TextStyle(fontWeight: FontWeight.bold, color: BrandingService.primary)),
                                        Text(LanguageService.t('month_2'), style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ]),
    );
  }
}
