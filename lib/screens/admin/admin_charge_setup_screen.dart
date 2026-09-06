import 'package:flutter/material.dart';
import '../../utils/type_helpers.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminChargeSetupScreen extends StatefulWidget {
  const AdminChargeSetupScreen({super.key});
  @override
  State<AdminChargeSetupScreen> createState() => _AdminChargeSetupScreenState();
}

class _AdminChargeSetupScreenState extends State<AdminChargeSetupScreen> {
  List    _charges = [];
  bool    _loading = true;
  String? _error;

  final _frequencies = ['monthly', 'quarterly', 'yearly', 'one_time'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/maintenance-charges');
      dynamic raw = res['data'];
      if (raw is Map && raw.containsKey('data')) raw = raw['data'];
      setState(() { _charges = List.from(raw ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Color _freqColor(String? f) => switch (f) {
    'monthly'   => Colors.blue,
    'quarterly' => Colors.teal,
    'yearly'    => Colors.purple,
    'one_time'  => Colors.orange,
    _           => Colors.grey,
  };

  IconData _freqIcon(String? f) => switch (f) {
    'monthly'   => Icons.calendar_view_month,
    'quarterly' => Icons.calendar_view_week,
    'yearly'    => Icons.calendar_today,
    'one_time'  => Icons.event_note_outlined,
    _           => Icons.currency_rupee,
  };

  String _freqLabel(String? f) => switch (f) {
    'monthly'   => 'Monthly',
    'quarterly' => 'Quarterly',
    'yearly'    => 'Yearly',
    'one_time'  => 'One Time',
    _           => f ?? '',
  };

  // ── Add / Edit sheet ────────────────────────────────────────────────────
  void _showForm({Map? charge}) {
    final nameCtrl   = TextEditingController(text: charge?['name'] as String? ?? '');
    final amountCtrl = TextEditingController(text: charge?['amount']?.toString() ?? '');
    final descCtrl   = TextEditingController(text: charge?['description'] as String? ?? '');
    bool  isActive   = charge != null ? (toBool(charge['is_active'])) : true;
    String frequency = charge?['frequency'] as String? ?? 'monthly';
    final isEdit     = charge != null;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
              ),
            ),
            // Header
            FormSheetHeader(
              icon: Icons.currency_rupee,
              title: isEdit ? 'Edit Charge Type' : 'Add Charge Type',
              accent: Colors.orange,
              onClose: () => Navigator.pop(ctx),
            ),
            FormErrorBanner(message: formError),

            // Charge name
            AppFieldShell(
              accent: Colors.orange,
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: appFieldDecoration(
                  label: LanguageService.t('charge_name'),
                  hint: LanguageService.t('e_g_maintenance_water_lift'),
                  icon: Icons.label_outline, accent: Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Amount
            AppFieldShell(
              accent: Colors.orange,
              child: TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: appFieldDecoration(
                  label: 'Default Amount (${BrandingService.currencySymbol}) *',
                  hint: '0.00',
                  icon: Icons.currency_rupee_rounded, accent: Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Frequency
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(LanguageService.t('frequency'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 3.0,
                children: _frequencies.map((f) {
                  final sel = frequency == f;
                  final c   = _freqColor(f);
                  return GestureDetector(
                    onTap: () => setS(() => frequency = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                          color: sel ? c : Colors.grey[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: sel ? c : Colors.grey[300]!, width: sel ? 2 : 1)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_freqIcon(f), size: 14,
                            color: sel ? Colors.white : c),
                        const SizedBox(width: 6),
                        Text(_freqLabel(f), style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : Colors.black87)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ]),
            const SizedBox(height: 14),

            // Description
            AppFieldShell(
              accent: Colors.grey,
              child: TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(
                  label: LanguageService.t('description_optional'),
                  icon: Icons.notes_outlined, accent: Colors.grey[600]!,
                ).copyWith(alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: 14),

            // Active toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!)),
              child: Row(children: [
                const Icon(Icons.toggle_on_outlined, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LanguageService.t('active'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    Text(LanguageService.t('inactive_charges_will_not_appear_in_bill_gene'),
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                )),
                Switch(
                    value: isActive,
                    onChanged: (v) => setS(() => isActive = v),
                    activeColor: BrandingService.primary),
              ]),
            ),
            const SizedBox(height: 20),

            // Submit
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [Colors.orange, Color(0xFFE65100)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: ElevatedButton.icon(
              icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
              label: Text(isEdit ? 'Save Changes' : 'Add Charge Type', style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                setS(() => formError = null);
                if (nameCtrl.text.trim().isEmpty) {
                  setS(() => formError = LanguageService.t('charge_name_is_required'));
                  return;
                }
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null || amount < 0) {
                  setS(() => formError = LanguageService.t('enter_a_valid_amount'));
                  return;
                }
                try {
                  final body = {
                    'name':        nameCtrl.text.trim(),
                    'amount':      amount,
                    'frequency':   frequency,
                    'description': descCtrl.text.trim(),
                    'is_active':   isActive,
                  };
                  if (isEdit) {
                    await ApiService().put('/admin/maintenance-charges/${charge!['id']}', body);
                  } else {
                    await ApiService().post('/admin/maintenance-charges', body);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isEdit ? 'Charge type updated!' : 'Charge type added!'),
                      backgroundColor: Colors.green));
                } catch (e) {
                  setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                }
              },
            ),
            ),
          ]),
        )),
      ),
    );
  }

  // ── Delete ──────────────────────────────────────────────────────────────
  Future<void> _delete(Map charge) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_charge_type'),
      message: 'Delete "${charge['name']}"? Bills already generated with this charge will not be affected.',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm == true) {
      try {
        await ApiService().delete('/admin/maintenance-charges/${charge['id']}');
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('charge_type_deleted')), backgroundColor: Colors.red));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleActive(Map charge) async {
    try {
      await ApiService().put('/admin/maintenance-charges/${charge['id']}', {
        'name':      charge['name'],
        'amount':    charge['amount'],
        'frequency': charge['frequency'],
        'is_active': !(toBool(charge['is_active'])),
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym     = BrandingService.currencySymbol;
    final active  = _charges.where((c) => c['is_active'] == true).length;
    final monthly = _charges.where((c) => c['frequency'] == 'monthly' && c['is_active'] == true)
        .fold<double>(0, (s, c) => s + (double.tryParse(c['amount'].toString()) ?? 0));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard'),
        ),
        title: Text(LanguageService.t('charge_setup')),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_work_outlined),
            tooltip: LanguageService.t('flat_wise_overrides'),
            onPressed: () => context.push('/admin/flat-charges'),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('add_charge')),
        backgroundColor: Colors.orange,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(icon: const Icon(Icons.refresh), label: Text(LanguageService.t('retry')), onPressed: _load),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(children: [
                    // ── Summary bar ─────────────────────────────────────
                    Container(
                      color: Colors.orange.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Expanded(child: _SumCard('Total Types',   '${_charges.length}',         Icons.list_outlined,        Colors.blue)),
                        Expanded(child: _SumCard('Active',        '$active',                    Icons.check_circle_outline, Colors.green)),
                        Expanded(child: _SumCard('Monthly Total', '$sym${_fmt(monthly)}',        Icons.currency_rupee,       Colors.orange)),
                      ]),
                    ),

                    // ── Info banner ──────────────────────────────────────
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.withOpacity(0.2))),
                      child: Row(children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          LanguageService.t('active_charge_types_are_included_when_generat') +
                          'Tap the flat icon above to set per-flat fixed or per-sqft overrides.',
                          style: TextStyle(fontSize: 11, color: Colors.blue),
                        )),
                      ]),
                    ),

                    // ── List ─────────────────────────────────────────────
                    Expanded(child: _charges.isEmpty
                        ? EmptyState(
                            icon: Icons.currency_rupee,
                            title: LanguageService.t('no_charge_types_yet_ntap_to_add_one'),
                            color: Colors.teal,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                            itemCount: _charges.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final c      = _charges[i] as Map;
                              final active = toBool(c['is_active']);
                              final freq   = c['frequency'] as String? ?? 'monthly';
                              final fc     = _freqColor(freq);

                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(children: [
                                    // Icon
                                    Container(
                                      width: 48, height: 48,
                                      decoration: BoxDecoration(
                                          color: (active ? fc : Colors.grey).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10)),
                                      child: Icon(_freqIcon(freq),
                                          color: active ? fc : Colors.grey, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    // Info
                                    Expanded(child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Text(c['name'] as String? ?? '—',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold, fontSize: 15)),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                  color: (active ? fc : Colors.grey)
                                                      .withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(20)),
                                              child: Text(_freqLabel(freq),
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: active ? fc : Colors.grey)),
                                            ),
                                            if (!active) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                    color: Colors.grey.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(20)),
                                                child: Text(LanguageService.t('inactive'),
                                                    style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.grey)),
                                              ),
                                            ],
                                          ]),
                                          const SizedBox(height: 4),
                                          Text('$sym${_fmt(c['amount'])} / ${_freqLabel(freq)}',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: active ? fc : Colors.grey)),
                                          if ((c['description'] as String?)?.isNotEmpty == true)
                                            Text(c['description'] as String,
                                                style: const TextStyle(
                                                    fontSize: 11, color: Colors.grey)),
                                        ])),
                                    // 3-dot menu
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      onSelected: (val) {
                                        if (val == 'edit')   _showForm(charge: c);
                                        if (val == 'toggle') _toggleActive(c);
                                        if (val == 'delete') _delete(c);
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(value: 'edit',
                                            child: Row(children: [
                                              Icon(Icons.edit_outlined, size: 18),
                                              SizedBox(width: 10), Text(LanguageService.t('edit')),
                                            ])),
                                        PopupMenuItem(value: 'toggle',
                                            child: Row(children: [
                                              Icon(active
                                                  ? Icons.toggle_off_outlined
                                                  : Icons.toggle_on_outlined, size: 18),
                                              const SizedBox(width: 10),
                                              Text(active ? 'Set Inactive' : 'Set Active'),
                                            ])),
                                        const PopupMenuDivider(),
                                        PopupMenuItem(value: 'delete',
                                            child: Row(children: [
                                              Icon(Icons.delete_outline,
                                                  size: 18, color: Colors.red),
                                              SizedBox(width: 10),
                                              Text(LanguageService.t('delete'),
                                                  style: TextStyle(color: Colors.red)),
                                            ])),
                                      ],
                                    ),
                                  ]),
                                ),
                              );
                            },
                          )),
                  ]),
                ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final d = double.tryParse(v.toString()) ?? 0;
    if (d >= 100000) return '${(d / 100000).toStringAsFixed(1)}L';
    if (d >= 1000)   return '${(d / 1000).toStringAsFixed(1)}K';
    return d.toStringAsFixed(0);
  }
}

class _SumCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SumCard(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: color, size: 20),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
    Text(label,  style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}
