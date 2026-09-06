import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';

class AdminWalletLedgerScreen extends StatefulWidget {
  final Map resident;
  const AdminWalletLedgerScreen({super.key, required this.resident});
  @override
  State<AdminWalletLedgerScreen> createState() => _AdminWalletLedgerScreenState();
}

class _AdminWalletLedgerScreenState extends State<AdminWalletLedgerScreen> {
  Map? _wallet;
  List _flats = [];
  List _transactions = [];
  bool _loading = true;

  int get _residentId => int.parse(widget.resident['id'].toString());

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/admin/wallet/resident/$_residentId');
      setState(() {
        _wallet = res['wallet'];
        _flats = res['flats'] ?? [];
        _transactions = res['data']['data'] ?? res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = double.tryParse((_wallet?['balance'] ?? 0).toString()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('Wallet — ${widget.resident['name']}')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showAddFundSheet, icon: const Icon(Icons.add), label: Text(LanguageService.t('add_fund')), backgroundColor: BrandingService.primary),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Card(
                    color: BrandingService.secondary,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_flats.isNotEmpty ? 'Flats: ${_flats.map((f) => f['flat_number']).join(', ')}' : 'No flat linked', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('${BrandingService.currencySymbol}${balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        color: BrandingService.secondary,
                        title: LanguageService.t('no_advance_transactions_yet'),
                      ),
                    )
                  else
                    ..._transactions.map((t) => _LedgerTile(
                      t: t,
                      onApprove: () => _approve(t),
                      onReject: () => _reject(t),
                      onEdit: () => _showEditSheet(t),
                      onDelete: () => _delete(t),
                    )),
                ],
              ),
            ),
    );
  }

  Future<void> _approve(Map t) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('approve_advance_payment_q'),
      message: "Confirm ${BrandingService.currencySymbol}${t['amount']} claimed by ${t['user']?['name'] ?? ''}? It will be credited and auto-adjusted against any dues.",
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      confirmText: LanguageService.t('approve'),
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/admin/wallet/transactions/${t['id']}/approve', {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _reject(Map t) async {
    final reason = await AmsDialog.promptText(
      context,
      title: LanguageService.t('reject_advance_claim'),
      label: LanguageService.t('reason_shown_to_resident'),
      icon: Icons.notes_outlined,
      danger: true,
      confirmText: LanguageService.t('reject'),
      cancelText: LanguageService.t('cancel'),
      maxLines: 3,
    );
    if (reason == null) return;
    try {
      await ApiService().post('/admin/wallet/transactions/${t['id']}/reject', {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _delete(Map t) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_advance_entry_q'),
      message: LanguageService.t('this_cannot_be_undone_blocked_if_already_used'),
      icon: Icons.delete_outline_rounded,
      iconColor: Colors.red,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm != true) return;
    try {
      await ApiService().delete('/admin/wallet/transactions/${t['id']}');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _showAddFundSheet() => _showFundSheet(title: LanguageService.t('add_advance'), initial: null);
  Future<void> _showEditSheet(Map t) => _showFundSheet(title: LanguageService.t('edit_advance_entry'), initial: t);

  Future<void> _showFundSheet({required String title, Map? initial}) async {
    final amountCtrl = TextEditingController(text: initial != null ? initial['amount'].toString() : '');
    final txnCtrl = TextEditingController(text: initial?['transaction_id']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: initial?['notes']?.toString() ?? '');
    String method = initial?['payment_method']?.toString() ?? 'cash';
    String? formError;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormSheetHeader(
              icon: Icons.account_balance_wallet_outlined,
              title: title,
              accent: BrandingService.primary,
              onClose: () => Navigator.pop(ctx),
            ),
            if (initial == null) ...[
              const SizedBox(height: 2),
              Text(LanguageService.t('applied_immediately_no_approval_needed_auto_a'), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: appFieldDecoration(label: '${LanguageService.t('amount_2')} (${BrandingService.currencySymbol})', icon: Icons.currency_rupee, accent: BrandingService.primary)),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: DropdownButtonFormField<String>(
                initialValue: method,
                decoration: appFieldDecoration(label: LanguageService.t('payment_method'), icon: Icons.payments_outlined, accent: BrandingService.secondary),
                items: [
                  DropdownMenuItem(value: 'cash', child: Text(LanguageService.t('cash'))),
                  DropdownMenuItem(value: 'upi', child: Text(LanguageService.t('upi'))),
                  DropdownMenuItem(value: 'bank_transfer', child: Text(LanguageService.t('bank_transfer'))),
                  DropdownMenuItem(value: 'cheque', child: Text(LanguageService.t('cheque'))),
                  DropdownMenuItem(value: 'online', child: Text(LanguageService.t('online'))),
                ],
                onChanged: (v) => setS(() => method = v ?? 'cash'),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(controller: txnCtrl, decoration: appFieldDecoration(label: LanguageService.t('transaction_ref_id_optional'), icon: Icons.receipt_long_outlined, accent: BrandingService.primary)),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(controller: notesCtrl, maxLines: 2, decoration: appFieldDecoration(label: LanguageService.t('notes_optional'), icon: Icons.notes_outlined, accent: BrandingService.secondary)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(initial != null ? Icons.save_outlined : Icons.add_circle_outline),
              label: Text(initial != null ? 'Save Changes' : 'Add Advance'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                setS(() => formError = null);
                if (double.tryParse(amountCtrl.text.trim()) == null || double.parse(amountCtrl.text.trim()) <= 0) {
                  setS(() => formError = LanguageService.t('enter_a_valid_amount'));
                  return;
                }
                final payload = {
                  'amount': double.parse(amountCtrl.text.trim()),
                  'payment_method': method,
                  if (txnCtrl.text.trim().isNotEmpty) 'transaction_id': txnCtrl.text.trim(),
                  if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
                };
                try {
                  if (initial != null) {
                    await ApiService().put('/admin/wallet/transactions/${initial['id']}', payload);
                  } else {
                    await ApiService().post('/admin/wallet/resident/$_residentId', payload);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setS(() => formError = e.toString().replaceFirst('Exception: ', ''));
                }
              },
            ),
          ],
        ))),
      ),
    );

    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(initial != null ? 'Entry updated.' : 'Advance added.'), backgroundColor: Colors.green));
      _load();
    }
  }
}

class _LedgerTile extends StatelessWidget {
  final Map t;
  final VoidCallback onApprove, onReject, onEdit, onDelete;
  const _LedgerTile({required this.t, required this.onApprove, required this.onReject, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isCredit = t['type'] == 'credit';
    final amount = double.tryParse(t['amount'].toString()) ?? 0;
    final status = t['status']?.toString() ?? 'approved';
    final date = t['created_at'] != null ? BrandingService.formatDateTimeString(t['created_at'].toString()) : '';

    String label = isCredit
        ? (t['source'] == 'admin_deposit' ? 'Admin Added' : 'Resident Deposit')
        : (t['source'] == 'bill_adjustment' ? 'Applied to Bill' : 'Applied to Charge');

    Color statusColor;
    String statusText;
    switch (status) {
      case 'pending_approval': statusColor = Colors.orange; statusText = 'PENDING APPROVAL'; break;
      case 'rejected':         statusColor = Colors.red;    statusText = 'REJECTED'; break;
      default:                 statusColor = Colors.green;  statusText = 'APPROVED';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
            Text('${isCredit ? '+' : '-'}${BrandingService.currencySymbol}${amount.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: isCredit ? Colors.green : Colors.red)),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Text(date, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ]),
          if (t['notes'] != null && t['notes'].toString().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(t['notes'], style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic))),
          if (isCredit && status != 'rejected') ...[
            const SizedBox(height: 8),
            Row(children: [
              if (status == 'pending_approval') ...[
                Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.red), onPressed: onReject, child: Text(LanguageService.t('reject')))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: onApprove, child: Text(LanguageService.t('approve')))),
              ] else ...[
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 19), visualDensity: VisualDensity.compact),
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 19, color: Colors.red), visualDensity: VisualDensity.compact),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}
