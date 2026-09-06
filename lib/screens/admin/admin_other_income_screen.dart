import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

/// Apartment Admin > Other Income - non-maintenance revenue (mobile tower
/// rent, hall rental to outside parties, etc.). Mirrors
/// AdminExpensesScreen's shape exactly, on the income side.
class AdminOtherIncomeScreen extends StatefulWidget {
  const AdminOtherIncomeScreen({super.key});
  @override
  State<AdminOtherIncomeScreen> createState() => _State();
}

class _State extends State<AdminOtherIncomeScreen> {
  List    _incomes     = [];
  List    _categories  = [];
  bool    _loading     = true;
  String? _error;
  int?    _filterCatId;
  double  _total       = 0;

  final _payModes = ['cash', 'cheque', 'upi', 'bank_transfer', 'online'];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api   = ApiService();
      final iRes  = await api.get('/admin/other-incomes${_filterCatId != null ? '?category_id=$_filterCatId' : ''}');
      final cRes  = await api.get('/admin/general-categories');
      dynamic iRaw = iRes['data']; if (iRaw is Map) iRaw = iRaw['data'];
      dynamic cRaw = cRes['data']; if (cRaw is Map) cRaw = cRaw['data'];
      final list = List.from(iRaw ?? []);
      final tot  = list.fold<double>(0, (s, e) => s + (double.tryParse((e as Map)['amount']?.toString() ?? '0') ?? 0));
      setState(() { _incomes = list; _categories = List.from(cRaw ?? []); _total = tot; _loading = false; });
    } catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; }); }
  }

  void _showForm({Map? income}) {
    final titleCtrl = TextEditingController(text: income?['title'] as String? ?? '');
    final amtCtrl   = TextEditingController(text: income?['amount']?.toString() ?? '');
    final dateCtrl  = TextEditingController(text: income?['income_date'] as String? ?? DateTime.now().toIso8601String().substring(0, 10));
    final payerCtrl = TextEditingController(text: income?['payer_name'] as String? ?? '');
    final descCtrl  = TextEditingController(text: income?['description'] as String? ?? '');
    final refCtrl   = TextEditingController(text: income?['reference_no'] as String? ?? '');
    int?    catId   = income?['expense_category_id'] as int?;
    String payMode  = income?['payment_mode'] as String? ?? 'cash';
    final isEdit    = income != null;
    String? formError;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormSheetHeader(icon: Icons.trending_up, title: isEdit ? 'Edit Income' : 'Add Income', accent: Colors.green, onClose: () => Navigator.pop(ctx)),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: titleCtrl, decoration: appFieldDecoration(label: LanguageService.t('title_2'), icon: Icons.short_text_rounded, accent: BrandingService.primary))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: amtCtrl, keyboardType: TextInputType.number,
                decoration: appFieldDecoration(label: 'Amount (${BrandingService.currencySymbol}) *', icon: Icons.currency_rupee, accent: BrandingService.secondary)))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(dateCtrl.text) ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setS(() => dateCtrl.text = d.toIso8601String().substring(0, 10));
              },
              child: AbsorbPointer(child: AppFieldShell(accent: BrandingService.primary, child: TextField(controller: dateCtrl,
                  decoration: appFieldDecoration(label: LanguageService.t('date'), icon: Icons.calendar_today, accent: BrandingService.primary)))),
            )),
          ]),
          const SizedBox(height: 14),
          AppFieldShell(
            accent: BrandingService.secondary,
            child: DropdownButtonFormField<int>(
              value: catId,
              decoration: appFieldDecoration(label: LanguageService.t('category'), icon: Icons.tag, accent: BrandingService.secondary),
              hint: Text(LanguageService.t('select_category')),
              items: [DropdownMenuItem<int>(value: null, child: Text(LanguageService.t('no_category'))),
                ..._categories.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String? ?? '')))],
              onChanged: (v) => setS(() => catId = v),
            ),
          ),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: payerCtrl,
              decoration: appFieldDecoration(label: LanguageService.t('payer_name_e_g_tower_company_hall_renter'), icon: Icons.person_outline, accent: BrandingService.primary))),
          const SizedBox(height: 14),
          AppFieldShell(
            accent: BrandingService.primary,
            child: DropdownButtonFormField<String>(
              value: payMode,
              decoration: appFieldDecoration(label: LanguageService.t('payment_mode'), icon: Icons.payment_outlined, accent: BrandingService.primary),
              items: _payModes.map((m) => DropdownMenuItem(value: m, child: Text(LanguageService.t(m)))).toList(),
              onChanged: (v) => setS(() => payMode = v!),
            ),
          ),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: refCtrl, decoration: appFieldDecoration(label: LanguageService.t('reference_no_optional'), icon: Icons.numbers, accent: BrandingService.secondary))),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: descCtrl, maxLines: 2, decoration: appFieldDecoration(label: LanguageService.t('notes_optional'), icon: Icons.notes_outlined, accent: BrandingService.primary).copyWith(alignLabelWithHint: true))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
            label: Text(isEdit ? 'Save Changes' : 'Add Income'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              setS(() => formError = null);
              if (titleCtrl.text.trim().isEmpty || double.tryParse(amtCtrl.text.trim()) == null) {
                setS(() => formError = LanguageService.t('title_and_valid_amount_required'));
                return;
              }
              try {
                final body = {'title': titleCtrl.text.trim(), 'amount': double.parse(amtCtrl.text.trim()),
                  'income_date': dateCtrl.text, 'payment_mode': payMode,
                  'expense_category_id': catId, 'payer_name': payerCtrl.text.trim(),
                  'reference_no': refCtrl.text.trim(), 'description': descCtrl.text.trim()};
                if (isEdit) { await ApiService().put('/admin/other-incomes/${income!['id']}', body); }
                else        { await ApiService().post('/admin/other-incomes', body); }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Income updated!' : 'Income added!'), backgroundColor: Colors.green));
              } catch (e) {
                setS(() => formError = e.toString().replaceAll('Exception: ', ''));
              }
            },
          ),
        ]))),
      ),
    );
  }

  Future<void> _delete(Map income) async {
    final ok = await AmsDialog.confirm(context, title: LanguageService.t('delete_income'), message: 'Delete "${income['title']}"?', icon: Icons.delete_outline_rounded, confirmText: LanguageService.t('delete'), danger: true);
    if (ok == true) {
      try { await ApiService().delete('/admin/other-incomes/${income['id']}'); _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('income_deleted')), backgroundColor: Colors.red));
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = BrandingService.currencySymbol;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')),
        title: Text(LanguageService.t('other_income')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showForm(), icon: const Icon(Icons.add), label: Text(LanguageService.t('add_income')), backgroundColor: Colors.green),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey), const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.grey)), const SizedBox(height: 12), ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry')))]))
          : Column(children: [
              // Summary + filter
              Container(color: Colors.green.withOpacity(0.05), padding: const EdgeInsets.all(12), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _S('Total Entries', '${_incomes.length}', Icons.receipt_long, Colors.green),
                  _S('Total Amount', '$sym${_fmt(_total)}', Icons.currency_rupee, Colors.teal),
                ]),
                const SizedBox(height: 8),
                SizedBox(height: 30, child: ListView(scrollDirection: Axis.horizontal, children: [
                  _Ch('All', _filterCatId == null, () => setState(() { _filterCatId = null; _load(); }), Colors.grey),
                  ..._categories.map((c) => _Ch(c['name'] as String? ?? '', _filterCatId == c['id'], () => setState(() { _filterCatId = c['id'] as int; _load(); }), BrandingService.primary)),
                ])),
              ])),
              Expanded(child: _incomes.isEmpty
                  ? EmptyState(icon: Icons.savings_outlined, title: LanguageService.t('no_other_income_recorded_yet'), color: Colors.green)
                  : RefreshIndicator(onRefresh: _load, child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _incomes.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e    = _incomes[i] as Map;
                        final cat  = (e['category'] as Map?)?['name'] as String?;
                        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                          Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.trending_up, color: Colors.green, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e['title'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${e['income_date'] != null ? BrandingService.formatDateString(e['income_date'].toString()) : '—'}${cat != null ? '  ·  $cat' : ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(LanguageService.t((e['payment_mode'] as String? ?? '')).toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('$sym${_fmt(e['amount'])}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                          ]),
                          PopupMenuButton<String>(icon: const Icon(Icons.more_vert, color: Colors.grey),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (v) { if (v == 'edit') _showForm(income: e); if (v == 'delete') _delete(e); },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text(LanguageService.t('edit'))])),
                              const PopupMenuDivider(),
                              PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text(LanguageService.t('delete'), style: TextStyle(color: Colors.red))])),
                            ]),
                        ])));
                      },
                    ))),
            ]),
    );
  }

  String _fmt(dynamic v) { if (v == null) return '0'; final d = double.tryParse(v.toString()) ?? 0; if (d >= 100000) return '${(d/100000).toStringAsFixed(1)}L'; if (d >= 1000) return '${(d/1000).toStringAsFixed(1)}K'; return d.toStringAsFixed(0); }
}

class _S extends StatelessWidget {
  final String l, v; final IconData i; final Color c;
  const _S(this.l, this.v, this.i, this.c);
  @override Widget build(BuildContext context) => Row(children: [Icon(i, color: c, size: 16), const SizedBox(width: 4), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))])]);
}

class _Ch extends StatelessWidget {
  final String label; final bool sel; final VoidCallback onTap; final Color c;
  const _Ch(this.label, this.sel, this.onTap, this.c);
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 180), margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sel ? c : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? c : Colors.grey[300]!)), child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.grey[700]))));
}
