import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../services/language_service.dart';

class AdminBillsScreen extends StatefulWidget {
  const AdminBillsScreen({super.key});
  @override
  State<AdminBillsScreen> createState() => _AdminBillsScreenState();
}

class _AdminBillsScreenState extends State<AdminBillsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _statuses = ['all', 'pending', 'partial', 'paid', 'overdue'];
  List _bills   = [];
  bool _loading = true;
  int _tabIdx   = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging) {
          setState(() => _tabIdx = _tabs.index);
          _load();
        }
      });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final status = _statuses[_tabIdx];
    final q      = status == 'all' ? '' : '?status=$status';
    try {
      final res = await ApiService().get('/admin/bills$q');
      setState(() {
        _bills   = res['data']['data'] ?? res['data'] ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List _flatsList(Map r) {
    final flats = r['flats'];
    if (flats is List && flats.isNotEmpty) return flats;
    final single = r['flat'];
    return single is Map ? [single] : [];
  }

  String _flatsLabel(Map r) {
    final flats = _flatsList(r);
    if (flats.isEmpty) return r['flat_number']?.toString() ?? '';
    return flats.map((f) => (f as Map)['flat_number']?.toString() ?? '').join(', ');
  }

  void _showGenerateBills() async {
    List residents = [];
    try {
      final res = await ApiService().get('/admin/residents');
      residents = res['data']['data'] ?? res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final now = DateTime.now();
    int fromMonth = now.month, fromYear = now.year;
    int toMonth = now.month, toYear = now.year;
    String scope = 'all';
    final Set<int> selectedIds = {};
    String? formError;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(Icons.receipt_long_rounded, color: BrandingService.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(LanguageService.t('generate_bills'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: LanguageService.t('close'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              FormErrorBanner(message: formError),
              Text(LanguageService.t('period'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700])),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: AppFieldShell(accent: BrandingService.primary, child: DropdownButtonFormField<int>(
                  value: fromMonth, decoration: appFieldDecoration(label: LanguageService.t('from_month'), icon: Icons.calendar_today_rounded, accent: BrandingService.primary),
                  items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                  onChanged: (v) => setS(() => fromMonth = v!),
                ))),
                const SizedBox(width: 8),
                Expanded(child: AppFieldShell(accent: BrandingService.primary, child: DropdownButtonFormField<int>(
                  value: fromYear, decoration: appFieldDecoration(label: LanguageService.t('year'), icon: Icons.event_outlined, accent: BrandingService.primary),
                  items: List.generate(4, (i) => DropdownMenuItem(value: now.year - 1 + i, child: Text('${now.year - 1 + i}'))),
                  onChanged: (v) => setS(() => fromYear = v!),
                ))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: AppFieldShell(accent: BrandingService.primary, child: DropdownButtonFormField<int>(
                  value: toMonth, decoration: appFieldDecoration(label: LanguageService.t('to_month'), icon: Icons.calendar_today_rounded, accent: BrandingService.primary),
                  items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                  onChanged: (v) => setS(() => toMonth = v!),
                ))),
                const SizedBox(width: 8),
                Expanded(child: AppFieldShell(accent: BrandingService.primary, child: DropdownButtonFormField<int>(
                  value: toYear, decoration: appFieldDecoration(label: LanguageService.t('year'), icon: Icons.event_outlined, accent: BrandingService.primary),
                  items: List.generate(4, (i) => DropdownMenuItem(value: now.year - 1 + i, child: Text('${now.year - 1 + i}'))),
                  onChanged: (v) => setS(() => toYear = v!),
                ))),
              ]),
              Text(LanguageService.t('select_the_same_month_twice_for_a_single_mont'),
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 18),
              Text(LanguageService.t('residents'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700])),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  RadioListTile<String>(
                    dense: true, activeColor: BrandingService.primary,
                    title: Text(LanguageService.t('all_residents')), value: 'all', groupValue: scope,
                    onChanged: (v) => setS(() => scope = v!),
                  ),
                  RadioListTile<String>(
                    dense: true, activeColor: BrandingService.primary,
                    title: Text(LanguageService.t('selected_residents')), value: 'selected', groupValue: scope,
                    onChanged: (v) => setS(() => scope = v!),
                  ),
                ]),
              ),
              if (scope == 'selected') ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: residents.isEmpty
                      ? Text(LanguageService.t('no_residents_found'), style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))
                      : SingleChildScrollView(
                          child: Column(children: residents.map<Widget>((r) {
                            final id = r['id'] as int;
                            final selected = selectedIds.contains(id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => setS(() => selected ? selectedIds.remove(id) : selectedIds.add(id)),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: selected ? BrandingService.primary.withOpacity(0.10) : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected ? BrandingService.primary : Colors.grey.shade300,
                                      width: selected ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Row(children: [
                                    Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                                        size: 17, color: selected ? BrandingService.primary : Colors.grey[400]),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        '${r['name']} - Flat${_flatsList(r).length > 1 ? 's' : ''} ${_flatsLabel(r)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                          color: selected ? BrandingService.primary : Colors.grey[800],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          }).toList()),
                        ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.15)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.blueGrey[400]),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    LanguageService.t('bills_that_come_to_0_or_that_already_exist_fo'),
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey[700], height: 1.3),
                  )),
                ]),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('cancel'))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandingService.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: Text(LanguageService.t('generate')),
            onPressed: (scope == 'selected' && selectedIds.isEmpty) ? null : () async {
              setS(() => formError = null);
              try {
                final res = await ApiService().post('/admin/bills/generate', {
                  'from_month': fromMonth, 'from_year': fromYear,
                  'to_month': toMonth, 'to_year': toYear,
                  'scope': scope,
                  if (scope == 'selected') 'user_ids': selectedIds.toList(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res['message'] ?? 'Bills generated'), backgroundColor: Colors.green),
                  );
                  _load();
                }
              } catch (e) {
                setS(() => formError = e.toString().replaceAll('Exception: ',''));
              }
            },
          ),
        ],
      )),
    );
  }

  void _showCatchUpBills() async {
    List residents = [];
    try {
      final res = await ApiService().get('/admin/residents');
      residents = res['data']['data'] ?? res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final now = DateTime.now();
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);
    int? selUserId;
    int? selFlatId;
    String? formError;
    int fromMonth = threeMonthsAgo.month, fromYear = threeMonthsAgo.year;
    int toMonth = now.month, toYear = now.year;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: BrandingService.secondary.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(Icons.event_repeat_rounded, color: BrandingService.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(LanguageService.t('catch_up_bills'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: LanguageService.t('close'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            FormErrorBanner(message: formError),
            Text(LanguageService.t('generates_one_bill_per_month_for_a_resident_w'),
                style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.3)),
            const SizedBox(height: 16),
            AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<int>(
              value: selUserId,
              decoration: appFieldDecoration(label: LanguageService.t('resident'), icon: Icons.person_outline_rounded, accent: BrandingService.secondary),
              items: residents.map<DropdownMenuItem<int>>((r) => DropdownMenuItem(
                value: r['id'] as int,
                child: Text('${r['name']} - Flat${_flatsList(r).length > 1 ? 's' : ''} ${_flatsLabel(r)}', overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setS(() { selUserId = v; selFlatId = null; }),
            )),
            if (selUserId != null && _flatsList(residents.firstWhere((r) => r['id'] == selUserId)).length > 1) ...[
              const SizedBox(height: 12),
              AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<int?>(
                value: selFlatId,
                decoration: appFieldDecoration(label: LanguageService.t('flat'), icon: Icons.home_outlined, accent: BrandingService.secondary),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(LanguageService.t('all_of_this_resident_s_flats'))),
                  ..._flatsList(residents.firstWhere((r) => r['id'] == selUserId)).map<DropdownMenuItem<int?>>((f) =>
                    DropdownMenuItem<int?>(value: (f as Map)['id'] as int, child: Text('Flat ${f['flat_number'] ?? ''}'))),
                ],
                onChanged: (v) => setS(() => selFlatId = v),
              )),
              const SizedBox(height: 4),
              Text(LanguageService.t('this_resident_has_more_than_one_flat_leave_as'),
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            Text(LanguageService.t('from'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<int>(
                value: fromMonth,
                decoration: appFieldDecoration(label: LanguageService.t('month'), icon: Icons.calendar_today_rounded, accent: BrandingService.secondary),
                items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                onChanged: (v) => setS(() => fromMonth = v!),
              ))),
              const SizedBox(width: 12),
              Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<int>(
                value: fromYear,
                decoration: appFieldDecoration(label: LanguageService.t('year'), icon: Icons.event_outlined, accent: BrandingService.secondary),
                items: List.generate(4, (i) => DropdownMenuItem(value: now.year - 3 + i, child: Text('${now.year - 3 + i}'))),
                onChanged: (v) => setS(() => fromYear = v!),
              ))),
            ]),
            const SizedBox(height: 12),
            Text(LanguageService.t('to'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<int>(
                value: toMonth,
                decoration: appFieldDecoration(label: LanguageService.t('month'), icon: Icons.calendar_today_rounded, accent: BrandingService.secondary),
                items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                onChanged: (v) => setS(() => toMonth = v!),
              ))),
              const SizedBox(width: 12),
              Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<int>(
                value: toYear,
                decoration: appFieldDecoration(label: LanguageService.t('year'), icon: Icons.event_outlined, accent: BrandingService.secondary),
                items: List.generate(4, (i) => DropdownMenuItem(value: now.year - 3 + i, child: Text('${now.year - 3 + i}'))),
                onChanged: (v) => setS(() => toYear = v!),
              ))),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('cancel'))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandingService.secondary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: Text(LanguageService.t('generate')),
            onPressed: selUserId == null ? null : () async {
              setS(() => formError = null);
              try {
                final res = await ApiService().post('/admin/bills/generate-catchup', {
                  'user_id': selUserId,
                  if (selFlatId != null) 'flat_id': selFlatId,
                  'from_month': fromMonth, 'from_year': fromYear,
                  'to_month': toMonth, 'to_year': toYear,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res['message'] ?? 'Catch-up bills generated'), backgroundColor: Colors.green));
                  _load();
                }
              } catch (e) {
                setS(() => formError = e.toString().replaceFirst('Exception: ', ''));
              }
            },
          ),
        ],
      )),
    );
  }

  Future<void> _deleteBill(Map bill) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_bill_q'),
      message: 'Delete bill ${bill['bill_number'] ?? ''}? This cannot be undone.',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm != true) return;
    try {
      final res = await ApiService().delete('/admin/bills/${bill['id']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Bill deleted'), backgroundColor: Colors.green));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  static const Map<String, IconData> _paymentMethodIcons = {
    'cash': Icons.payments_outlined,
    'bank_transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_long_outlined,
    'upi': Icons.qr_code_scanner_rounded,
  };

  void _showRecordPayment(Map bill) {
    final amtCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String method = 'cash';
    const accent = Colors.green;
    final outstanding = _fmt(bill['outstanding']);
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.payments_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${LanguageService.t('record_payment')} — ${bill['bill_number'] ?? ''}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${LanguageService.t('total')}: ${BrandingService.currencySymbol}${_fmt(bill['total_amount'])}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accent.withOpacity(0.12), accent.withOpacity(0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(0.2)),
              ),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_outlined, color: accent.withOpacity(0.8), size: 18),
                const SizedBox(width: 10),
                Text(LanguageService.t('outstanding'), style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                const Spacer(),
                Text('${BrandingService.currencySymbol}$outstanding',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent.withOpacity(0.9))),
              ]),
            ),
            const SizedBox(height: 18),
            AppFieldShell(
              accent: accent,
              child: TextField(
                controller: amtCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: appFieldDecoration(
                  label: '${LanguageService.t('amount_2')} (${BrandingService.currencySymbol})',
                  icon: Icons.currency_rupee_rounded,
                  accent: accent,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: accent,
              child: DropdownButtonFormField<String>(
                value: method,
                decoration: appFieldDecoration(label: LanguageService.t('payment_method'), icon: _paymentMethodIcons[method], accent: accent),
                items: ['cash','bank_transfer','cheque','upi'].map((m) =>
                  DropdownMenuItem(value: m, child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_paymentMethodIcons[m], size: 17, color: accent),
                    const SizedBox(width: 8),
                    Text(LanguageService.t(m)),
                  ]))
                ).toList(),
                onChanged: (v) => setS(() => method = v!),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: Colors.grey,
              child: TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('notes_optional'), icon: Icons.note_outlined, accent: Colors.grey[600]!)
                    .copyWith(alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [accent, Color(0xFF2E7D32)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: Text(LanguageService.t('record_payment'), style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  setS(() => formError = null);
                  final amt = double.tryParse(amtCtrl.text.trim());
                  if (amt == null || amt <= 0) {
                    setS(() => formError = LanguageService.t('enter_a_valid_amount'));
                    return;
                  }
                  try {
                    await ApiService().post('/admin/bills/${bill['id']}/record-payment', {
                      'amount':         amt,
                      'payment_method': method,
                      'notes':          notesCtrl.text.trim(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(LanguageService.t('payment_recorded')), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                  }
                },
              ),
            ),
          ],
        )),
      ),
    );
  }


  String _fmt(dynamic v) {
    if (v == null) return '0';
    final d = double.tryParse(v.toString()) ?? 0;
    return d.toStringAsFixed(2);
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'paid':    return Colors.green;
      case 'partial': return Colors.orange;
      case 'overdue': return Colors.red;
      default:        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('bills')),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onSelected: (v) => v == 'generate' ? _showGenerateBills() : _showCatchUpBills(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'generate', child: Text(LanguageService.t('generate_bills_this_apartment'))),
              PopupMenuItem(value: 'catchup', child: Text(LanguageService.t('catch_up_bills_missed_months_one_resident'))),
            ],
          ),
        ],
        bottom: pillTabBar(_tabs, _statuses.map((s) => LanguageService.t(s).toUpperCase()).toList()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bills.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long,
                  color: BrandingService.primary,
                  title: LanguageService.t('no_bills_found'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _bills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final b       = _bills[i] as Map;
                      final status  = b['status'] as String? ?? 'pending';
                      final color   = _statusColor(status);
                      final months  = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                      final period  = '${months[b['billing_month'] ?? 1]} ${b['billing_year']}';
                      final flatNo  = b['flat']?['flat_number'] ?? '—';
                      final resName = b['user']?['name'] ?? '—';
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withOpacity(0.05)),
                          boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(children: [
                            Row(children: [
                              Container(
                                width: 40, height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: [BoxShadow(color: color.withOpacity(0.32), blurRadius: 7, offset: const Offset(0, 3))],
                                ),
                                child: const Icon(Icons.receipt_long, color: Colors.white, size: 19),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(resName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Text('${LanguageService.t('flat_label')} $flatNo  ·  $period', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(LanguageService.t(status).toUpperCase(),
                                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              if ((double.tryParse(b['paid_amount']?.toString() ?? '0') ?? 0) <= 0) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: LanguageService.t('delete_bill'),
                                  onPressed: () => _deleteBill(b),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                Expanded(child: _AmtTile(label: LanguageService.t('total'), value: '${BrandingService.currencySymbol}${_fmt(b['total_amount'])}')),
                                Expanded(child: _AmtTile(label: LanguageService.t('paid'),  value: '${BrandingService.currencySymbol}${_fmt(b['paid_amount'])}', color: Colors.green)),
                                Expanded(child: _AmtTile(label: LanguageService.t('due'),   value: '${BrandingService.currencySymbol}${_fmt(b['outstanding'])}',  color: status == 'paid' ? Colors.green : Colors.red)),
                              ]),
                            ),
                            if (status != 'paid') ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.add_circle_outline, size: 16),
                                  label: Text(LanguageService.t('record_payment')),
                                  onPressed: () => _showRecordPayment(b),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)),
                                ),
                              ),
                            ],
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _AmtTile extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _AmtTile({required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}
