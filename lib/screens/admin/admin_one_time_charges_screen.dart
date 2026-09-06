// ── One-Time Charges ─────────────────────────────────────────────────────────
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

class AdminOneTimeChargesScreen extends StatefulWidget {
  const AdminOneTimeChargesScreen({super.key});
  @override State<AdminOneTimeChargesScreen> createState() => _OTCState();
}

class _OTCState extends State<AdminOneTimeChargesScreen> {
  List _charges = []; bool _loading = true; String? _error;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { final res = await ApiService().get('/admin/one-time-charges'); dynamic r = res['data']; if (r is Map) r = r['data']; setState(() { _charges = List.from(r ?? []); _loading = false; }); }
    catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; }); }
  }

  Future<void> _viewItems(Map c) async {
    List items = [];
    bool loading = true;
    String? err;

    Future<void> fetchItems(void Function(void Function()) setS) async {
      try {
        final res = await ApiService().get('/admin/one-time-charges/${c['id']}');
        dynamic charge = res['data'];
        setS(() { items = List.from(charge?['items'] ?? []); loading = false; err = null; });
      } catch (e) {
        setS(() { err = e.toString().replaceAll('Exception: ', ''); loading = false; });
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        if (loading && items.isEmpty && err == null) {
          fetchItems(setS);
        }
        return DraggableScrollableSheet(
          initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
          builder: (ctx, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(c['title'] as String? ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
              const Divider(),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : err != null
                        ? Center(child: Text(err!, style: const TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, i) {
                              final item = items[i] as Map;
                              final status = item['status']?.toString() ?? 'pending';
                              Color badgeColor; String badgeText;
                              switch (status) {
                                case 'paid': badgeColor = Colors.green; badgeText = 'PAID'; break;
                                case 'pending_approval': badgeColor = Colors.blue; badgeText = 'AWAITING CONFIRMATION'; break;
                                case 'rejected': badgeColor = Colors.red; badgeText = 'REJECTED'; break;
                                case 'partial': badgeColor = Colors.orange; badgeText = 'PARTIALLY PAID'; break;
                                default: badgeColor = Colors.orange; badgeText = 'PENDING';
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: Text('${(item['user'] as Map?)?['name'] ?? '—'}  ·  Flat ${(item['flat'] as Map?)?['flat_number'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                  const SizedBox(width: 8),
                                  Text(status == 'partial' ? '${BrandingService.currencySymbol}${item['outstanding']} / ${BrandingService.currencySymbol}${item['amount']}' : '${BrandingService.currencySymbol}${item['amount']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ]),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: badgeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                    child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const Spacer(),
                                  if (status == 'pending_approval') ...[
                                    IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.check_circle, color: Colors.green, size: 22), onPressed: () async {
                                      try { await ApiService().post('/admin/one-time-charges/items/${item['id']}/approve', {}); await fetchItems(setS); }
                                      catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')))); }
                                    }),
                                    IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.cancel, color: Colors.red, size: 22), onPressed: () async {
                                      final reason = await AmsDialog.promptText(
                                        ctx,
                                        title: LanguageService.t('reject_payment'),
                                        label: LanguageService.t('reason_shown_to_resident'),
                                        icon: Icons.receipt_long_rounded,
                                        danger: true,
                                        confirmText: LanguageService.t('reject'),
                                        cancelText: LanguageService.t('cancel'),
                                        maxLines: 2,
                                      );
                                      if (reason != null) {
                                        try { await ApiService().post('/admin/one-time-charges/items/${item['id']}/reject', {'reason': reason}); await fetchItems(setS); }
                                        catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')))); }
                                      }
                                    }),
                                  ] else if (status == 'pending' || status == 'rejected' || status == 'partial')
                                    TextButton(onPressed: () async {
                                      String method = 'cash';
                                      final txnCtrl = TextEditingController();
                                      final ok = await showDialog<bool>(context: ctx, builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) => AlertDialog(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        title: Row(children: [
                                          Container(
                                            width: 40, height: 40,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.12), shape: BoxShape.circle),
                                            child: Icon(Icons.payments_rounded, color: BrandingService.primary, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(child: Text(LanguageService.t('record_payment'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                                        ]),
                                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                                          AppFieldShell(
                                            accent: BrandingService.primary,
                                            child: DropdownButtonFormField<String>(
                                              initialValue: method,
                                              decoration: appFieldDecoration(label: LanguageService.t('payment_method'), icon: Icons.payments_outlined, accent: BrandingService.primary),
                                              items: [
                                                DropdownMenuItem(value: 'cash', child: Text(LanguageService.t('cash'))),
                                                DropdownMenuItem(value: 'upi', child: Text(LanguageService.t('upi'))),
                                                DropdownMenuItem(value: 'bank_transfer', child: Text(LanguageService.t('bank_transfer'))),
                                                DropdownMenuItem(value: 'cheque', child: Text(LanguageService.t('cheque'))),
                                              ],
                                              onChanged: (v) => setD(() => method = v ?? 'cash'),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          AppFieldShell(
                                            accent: BrandingService.secondary,
                                            child: TextField(
                                              controller: txnCtrl,
                                              decoration: appFieldDecoration(label: LanguageService.t('transaction_ref_id_optional'), icon: Icons.receipt_long_outlined, accent: BrandingService.secondary),
                                            ),
                                          ),
                                        ]),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(LanguageService.t('cancel'))),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: BrandingService.primary,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: Text(LanguageService.t('record')),
                                          ),
                                        ],
                                      )));
                                      if (ok == true) {
                                        try {
                                          await ApiService().post('/admin/one-time-charges/items/${item['id']}/record-payment', {
                                            'payment_method': method,
                                            if (txnCtrl.text.trim().isNotEmpty) 'transaction_id': txnCtrl.text.trim(),
                                          });
                                          await fetchItems(setS);
                                        } catch (e) {
                                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
                                        }
                                      }
                                    }, child: Text(LanguageService.t('record'))),
                                ]),
                              ]));
                            },
                          ),
              ),
            ]),
          ),
        );
      }),
    ).then((_) => _load());
  }

  void _showAdd() {
    final titleCtrl = TextEditingController();
    final amtCtrl   = TextEditingController();
    final descCtrl  = TextEditingController();
    final dateCtrl  = TextEditingController(text: DateTime.now().add(const Duration(days: 7)).toIso8601String().substring(0, 10));
    String applyType = 'all_same';
    List<Map> flats = [];
    bool flatsLoading = false;
    String? flatsError;
    final Map<dynamic, TextEditingController> flatAmountCtrls = {};
    String? formError;

    Future<void> loadFlats(void Function(void Function()) setS) async {
      setS(() { flatsLoading = true; flatsError = null; });
      try {
        final res = await ApiService().get('/admin/flats');
        var raw = res['data'];
        if (raw is Map && raw.containsKey('data')) raw = raw['data'];
        final occupied = List.from(raw ?? [])
            .where((f) => f['status'] != 'vacant' && f['resident'] != null)
            .toList();
        setS(() {
          flats = List<Map>.from(occupied);
          for (final f in flats) {
            flatAmountCtrls.putIfAbsent(f['id'], () => TextEditingController());
          }
          flatsLoading = false;
        });
      } catch (e) {
        setS(() { flatsError = e.toString().replaceAll('Exception: ', ''); flatsLoading = false; });
      }
    }

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) {
          if (applyType == 'individual' && flats.isEmpty && !flatsLoading && flatsError == null) {
            loadFlats(setS);
          }
          return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.event_note_outlined, color: Colors.deepOrange)), const SizedBox(width: 12), Text(LanguageService.t('add_one_time_charge'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
          const SizedBox(height: 18),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: titleCtrl, decoration: appFieldDecoration(label: LanguageService.t('title_2'), icon: Icons.title_rounded, accent: Colors.deepOrange))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: 'Default Amount (${BrandingService.currencySymbol}) *', icon: Icons.currency_rupee_rounded, accent: Colors.deepOrange)))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(onTap: () async { final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setS(() => dateCtrl.text = d.toIso8601String().substring(0, 10)); }, child: AbsorbPointer(child: AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: dateCtrl, decoration: appFieldDecoration(label: LanguageService.t('due_date_2'), icon: Icons.calendar_today_rounded, accent: Colors.deepOrange)))))),
          ]),
          const SizedBox(height: 16),
          Text(LanguageService.t('apply_to'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => setS(() => applyType = 'all_same'), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: applyType == 'all_same' ? Colors.deepOrange : Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: applyType == 'all_same' ? Colors.deepOrange : Colors.grey[300]!)), child: Column(children: [Icon(Icons.groups_outlined, color: applyType == 'all_same' ? Colors.white : Colors.deepOrange), const SizedBox(height: 4), Text(LanguageService.t('all_flats_n_same_amount'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: applyType == 'all_same' ? Colors.white : Colors.black87))])))),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(onTap: () => setS(() => applyType = 'individual'), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: applyType == 'individual' ? Colors.deepOrange : Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: applyType == 'individual' ? Colors.deepOrange : Colors.grey[300]!)), child: Column(children: [Icon(Icons.tune_outlined, color: applyType == 'individual' ? Colors.white : Colors.deepOrange), const SizedBox(height: 4), Text(LanguageService.t('individual_n_custom_amounts'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: applyType == 'individual' ? Colors.white : Colors.black87))])))),
          ]),
          if (applyType == 'individual') ...[
            const SizedBox(height: 14),
            Text(LanguageService.t('set_amount_per_flat'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(LanguageService.t('leave_blank_to_use_the_default_amount_for_tha'), style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            if (flatsLoading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()))
            else if (flatsError != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(flatsError!, style: const TextStyle(color: Colors.red, fontSize: 12)))
            else if (flats.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(LanguageService.t('no_occupied_flats_with_a_resident_found'), style: TextStyle(fontSize: 12, color: Colors.grey)))
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(10)),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: flats.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = flats[i];
                    final resident = f['resident'] as Map?;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(children: [
                        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(f['flat_number']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          Text(resident?['name'] ?? '—', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ])),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: TextField(
                          controller: flatAmountCtrls[f['id']],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.deepOrange, width: 1.6)),
                            hintText: '0.00',
                          ),
                        )),
                      ]),
                    );
                  },
                ),
              ),
          ],
          const SizedBox(height: 14),
          AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: descCtrl, maxLines: 2, decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: Colors.deepOrange).copyWith(alignLabelWithHint: true))),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Colors.deepOrange, Color(0xFFBF360C)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              boxShadow: [BoxShadow(color: Colors.deepOrange.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: ElevatedButton.icon(icon: const Icon(Icons.send_outlined), label: Text(LanguageService.t('create_apply_to_all_flats'), style: const TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () async {
              setS(() => formError = null);
              if (titleCtrl.text.trim().isEmpty || double.tryParse(amtCtrl.text.trim()) == null) { setS(() => formError = LanguageService.t('title_and_valid_amount_required')); return; }
              try {
                final Map<String, dynamic> body = {'title': titleCtrl.text.trim(), 'default_amount': double.parse(amtCtrl.text.trim()), 'due_date': dateCtrl.text, 'apply_type': applyType, 'description': descCtrl.text.trim()};
                if (applyType == 'individual') {
                  final flatAmounts = <String, double>{};
                  for (final entry in flatAmountCtrls.entries) {
                    final v = double.tryParse(entry.value.text.trim());
                    if (v != null) flatAmounts['${entry.key}'] = v;
                  }
                  body['flat_amounts'] = flatAmounts;
                }
                await ApiService().post('/admin/one-time-charges', body);
                if (ctx.mounted) Navigator.pop(ctx); _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('one_time_charge_created_and_applied')), backgroundColor: Colors.green));
              } catch (e) { setS(() => formError = e.toString().replaceAll('Exception: ', '')); }
            }),
          ),
        ]));
        }),
      ),
    );
  }

  void _showEdit(Map c) {
    final titleCtrl = TextEditingController(text: c['title'] as String? ?? '');
    final amtCtrl   = TextEditingController(text: '${c['default_amount'] ?? 0}');
    final descCtrl  = TextEditingController(text: c['description'] as String? ?? '');
    final dateCtrl  = TextEditingController(text: c['due_date'] as String? ?? DateTime.now().toIso8601String().substring(0, 10));
    String applyType = c['apply_type'] as String? ?? 'all_same';
    List<Map> items = [];
    bool itemsLoading = false;
    String? itemsError;
    final Map<dynamic, TextEditingController> flatAmountCtrls = {};
    String? formError;

    Future<void> loadItems(void Function(void Function()) setS) async {
      setS(() { itemsLoading = true; itemsError = null; });
      try {
        final res = await ApiService().get('/admin/one-time-charges/${c['id']}');
        final charge = res['data'];
        final raw = List.from(charge?['items'] ?? []);
        setS(() {
          items = List<Map>.from(raw);
          for (final item in items) {
            final flat = item['flat'] as Map?;
            final flatId = flat?['id'] ?? item['flat_id'];
            flatAmountCtrls.putIfAbsent(flatId, () => TextEditingController(text: '${item['amount'] ?? ''}'));
          }
          itemsLoading = false;
        });
      } catch (e) {
        setS(() { itemsError = e.toString().replaceAll('Exception: ', ''); itemsLoading = false; });
      }
    }

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) {
          if (applyType == 'individual' && items.isEmpty && !itemsLoading && itemsError == null) {
            loadItems(setS);
          }
          return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.edit_outlined, color: Colors.deepOrange)), const SizedBox(width: 12), Text(LanguageService.t('edit_one_time_charge'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
          const SizedBox(height: 12),
          Text(LanguageService.t('already_paid_flats_are_not_overwritten_a_lowe'), style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 16),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: titleCtrl, decoration: appFieldDecoration(label: LanguageService.t('title_2'), icon: Icons.title_rounded, accent: Colors.deepOrange))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: 'Default Amount (${BrandingService.currencySymbol}) *', icon: Icons.currency_rupee_rounded, accent: Colors.deepOrange)))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(onTap: () async { final d = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(dateCtrl.text) ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setS(() => dateCtrl.text = d.toIso8601String().substring(0, 10)); }, child: AbsorbPointer(child: AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: dateCtrl, decoration: appFieldDecoration(label: LanguageService.t('due_date_2'), icon: Icons.calendar_today_rounded, accent: Colors.deepOrange)))))),
          ]),
          const SizedBox(height: 16),
          Text(LanguageService.t('apply_to'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => setS(() => applyType = 'all_same'), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: applyType == 'all_same' ? Colors.deepOrange : Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: applyType == 'all_same' ? Colors.deepOrange : Colors.grey[300]!)), child: Column(children: [Icon(Icons.groups_outlined, color: applyType == 'all_same' ? Colors.white : Colors.deepOrange), const SizedBox(height: 4), Text(LanguageService.t('all_flats_n_same_amount'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: applyType == 'all_same' ? Colors.white : Colors.black87))])))),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(onTap: () => setS(() => applyType = 'individual'), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: applyType == 'individual' ? Colors.deepOrange : Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: applyType == 'individual' ? Colors.deepOrange : Colors.grey[300]!)), child: Column(children: [Icon(Icons.tune_outlined, color: applyType == 'individual' ? Colors.white : Colors.deepOrange), const SizedBox(height: 4), Text(LanguageService.t('individual_n_custom_amounts'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: applyType == 'individual' ? Colors.white : Colors.black87))])))),
          ]),
          if (applyType == 'individual') ...[
            const SizedBox(height: 14),
            Text(LanguageService.t('set_amount_per_flat'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(LanguageService.t('already_paid_flats_are_not_overwritten_a_lowe'), style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            if (itemsLoading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()))
            else if (itemsError != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(itemsError!, style: const TextStyle(color: Colors.red, fontSize: 12)))
            else if (items.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(LanguageService.t('no_occupied_flats_with_a_resident_found'), style: TextStyle(fontSize: 12, color: Colors.grey)))
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(10)),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final flat = item['flat'] as Map?;
                    final resident = item['user'] as Map?;
                    final flatId = flat?['id'] ?? item['flat_id'];
                    final status = item['status']?.toString() ?? 'pending';
                    final locked = status == 'pending_approval';
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(children: [
                        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(flat?['flat_number']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          Text(resident?['name'] ?? '—', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          if (status == 'paid')
                            Text(LanguageService.t('paid_lowered_refunds_raised_tops_up'), style: TextStyle(fontSize: 9, color: Colors.green))
                          else if (locked)
                            Text(LanguageService.t('awaiting_confirmation_resolve_first'), style: TextStyle(fontSize: 9, color: Colors.blue)),
                        ])),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: TextField(
                          controller: flatAmountCtrls[flatId],
                          enabled: !locked,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            filled: true,
                            fillColor: locked ? Colors.grey.shade100 : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.deepOrange, width: 1.6)),
                            hintText: '0.00',
                          ),
                        )),
                      ]),
                    );
                  },
                ),
              ),
          ],
          const SizedBox(height: 14),
          AppFieldShell(accent: Colors.deepOrange, child: TextField(controller: descCtrl, maxLines: 2, decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: Colors.deepOrange).copyWith(alignLabelWithHint: true))),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Colors.deepOrange, Color(0xFFBF360C)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              boxShadow: [BoxShadow(color: Colors.deepOrange.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: ElevatedButton.icon(icon: const Icon(Icons.save_outlined), label: Text(LanguageService.t('save_changes'), style: const TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () async {
              setS(() => formError = null);
              if (titleCtrl.text.trim().isEmpty || double.tryParse(amtCtrl.text.trim()) == null) { setS(() => formError = LanguageService.t('title_and_valid_amount_required')); return; }
              try {
                final Map<String, dynamic> body = {'title': titleCtrl.text.trim(), 'default_amount': double.parse(amtCtrl.text.trim()), 'due_date': dateCtrl.text, 'apply_type': applyType, 'description': descCtrl.text.trim()};
                if (applyType == 'individual') {
                  final flatAmounts = <String, double>{};
                  for (final entry in flatAmountCtrls.entries) {
                    final v = double.tryParse(entry.value.text.trim());
                    if (v != null) flatAmounts['${entry.key}'] = v;
                  }
                  body['flat_amounts'] = flatAmounts;
                }
                await ApiService().put('/admin/one-time-charges/${c['id']}', body);
                if (ctx.mounted) Navigator.pop(ctx); _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('charge_updated_paid_flats_reconciled_via_wall')), backgroundColor: Colors.green));
              } catch (e) { setS(() => formError = e.toString().replaceAll('Exception: ', '')); }
            }),
          ),
        ]));
        }),
      ),
    );
  }

  Future<void> _delete(Map c) async {
    final ok = await AmsDialog.confirm(context, title: LanguageService.t('delete_charge'), message: 'Delete "${c['title']}"? Already-paid flats will be refunded to their wallet; other items will be removed.', icon: Icons.delete_outline_rounded, confirmText: LanguageService.t('delete'), danger: true);
    if (ok == true) { try { await ApiService().delete('/admin/one-time-charges/${c['id']}'); _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('charge_deleted')), backgroundColor: Colors.red)); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); } }
  }

  @override
  Widget build(BuildContext context) {
    final sym = BrandingService.currencySymbol;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')), title: Text(LanguageService.t('one_time_charges')), actions: [
        IconButton(icon: const Icon(Icons.hourglass_bottom), tooltip: LanguageService.t('pending_approvals'), onPressed: () => context.push('/admin/approvals?tab=2')),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(onPressed: _showAdd, icon: const Icon(Icons.add), label: Text(LanguageService.t('create_charge')), backgroundColor: Colors.deepOrange),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, size: 48, color: Colors.grey), Text(_error!, style: const TextStyle(color: Colors.grey)), ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry')))]))
          : _charges.isEmpty ? EmptyState(icon: Icons.event_note_outlined, title: LanguageService.t('no_one_time_charges_yet'), subtitle: LanguageService.t('these_are_applied_once_to_all_occupied_flats'), color: Colors.deepOrange)
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: _charges.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) { final c = _charges[i] as Map; final items = c['items_count'] as int? ?? 0;
                return Card(child: InkWell(onTap: () => _viewItems(c), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.event_note_outlined, color: Colors.deepOrange, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['title'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Due: ${c['due_date'] != null ? BrandingService.formatDateString(c['due_date'].toString()) : '—'}  ·  $items flats', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Row(children: [Text('$sym${c['default_amount'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.deepOrange)), const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text(c['apply_type'] == 'all_same' ? 'All Same' : 'Individual', style: const TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)))]),
                  ])),
                  PopupMenuButton<String>(icon: const Icon(Icons.more_vert, color: Colors.grey), onSelected: (v) { if (v == 'edit') _showEdit(c); if (v == 'delete') _delete(c); }, itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: Colors.deepOrange), SizedBox(width: 10), Text(LanguageService.t('edit'))])),
                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text(LanguageService.t('delete'), style: TextStyle(color: Colors.red))])),
                  ]),
                ]))));
              })),
    );
  }
}
