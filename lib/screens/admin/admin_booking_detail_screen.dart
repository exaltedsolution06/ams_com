// ── Admin Booking Detail Screen ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/type_helpers.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/ams_dialog.dart';

class AdminBookingDetailScreen extends StatefulWidget {
  final int bookingId;
  const AdminBookingDetailScreen({super.key, required this.bookingId});
  @override State<AdminBookingDetailScreen> createState() => _AdminBookingDetailScreenState();
}

class _AdminBookingDetailScreenState extends State<AdminBookingDetailScreen> {
  Map<String, dynamic>? _booking;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  static const _statusColors = {
    'pending': Colors.orange, 'approved': Colors.green,
    'rejected': Colors.red, 'cancelled': Colors.grey,
  };

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/bookings/${widget.bookingId}');
      setState(() { _booking = (res['data'] as Map).cast<String, dynamic>(); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _act(String action, {String? reason}) async {
    setState(() => _acting = true);
    try {
      final res = await ApiService().post('/admin/bookings/${widget.bookingId}/action',
          {'action': action, if (reason != null) 'rejection_reason': reason});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Booking updated!'), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reject() async {
    final reason = await AmsDialog.promptText(
      context,
      title: LanguageService.t('reject'),
      label: 'Reason (shown to resident, optional)',
      icon: Icons.event_busy_rounded,
      danger: true,
      confirmText: LanguageService.t('reject'),
      cancelText: LanguageService.t('cancel'),
      maxLines: 2,
    );
    if (reason == null) return; // dialog dismissed / cancelled
    _act('reject', reason: reason.isEmpty ? null : reason);
  }

  @override
  Widget build(BuildContext context) {
    final sym = BrandingService.currencySymbol;
    final b = _booking;
    final status = b?['status'] as String? ?? 'pending';
    final sc = _statusColors[status] ?? Colors.grey;
    final facility = b?['facility'] as Map?;
    final user = b?['user'] as Map?;
    final chargeItem = b?['charge_item'] as Map?;
    final fee = toNum(facility?['booking_fee']);
    final feeNotCharged = status == 'approved' && fee > 0 && chargeItem == null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/bookings')),
        title: Text(LanguageService.t('booking_details')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  Text(_error!, style: const TextStyle(color: Colors.grey)),
                  ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                ]))
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
                  // Status banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(Icons.circle, size: 10, color: sc),
                      const SizedBox(width: 8),
                      Text(LanguageService.t(status).toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: sc, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  if (feeNotCharged) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Fee not charged. This booking was approved, but ${user?['name'] ?? 'the resident'} has no flat linked to their account, so the $sym${fee.toStringAsFixed(2)} fee could not be charged. Link a flat to their profile, then charge it manually from One-Time Charges.',
                            style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _sectionCard(title: LanguageService.t('booking_details'), icon: Icons.event_note_outlined, children: [
                    _row(Icons.meeting_room_outlined, LanguageService.t('facility'), facility?['name']?.toString() ?? '—'),
                    _row(Icons.person_outline, LanguageService.t('resident'), '${user?['name'] ?? '—'} ${user?['phone'] != null ? '(${user?['phone']})' : ''}'),
                    _row(Icons.home_outlined, LanguageService.t('flat'), (user?['flat'] as Map?)?['flat_number']?.toString() ?? '—'),
                    _row(Icons.calendar_today_outlined, LanguageService.t('date'), friendlyDate(b?['booking_date'])),
                    _row(Icons.schedule_outlined, LanguageService.t('time'), '${_hm(b?['start_time'])} - ${_hm(b?['end_time'])}'),
                    _row(Icons.people_outline, LanguageService.t('attendees'), '${b?['attendees'] ?? '—'}'),
                    if ((b?['purpose'] as String?)?.isNotEmpty == true) _row(Icons.notes_outlined, LanguageService.t('purpose'), b!['purpose'].toString()),
                    if (status == 'rejected' && (b?['rejection_reason'] as String?)?.isNotEmpty == true)
                      _row(Icons.info_outline, LanguageService.t('rejection_reason'), b!['rejection_reason'].toString(), valueColor: Colors.red),
                  ]),

                  const SizedBox(height: 16),

                  _sectionCard(title: LanguageService.t('fee_payment_status'), icon: Icons.currency_rupee, children: [
                    if (fee <= 0)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(LanguageService.t('free'), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)))
                    else if (chargeItem == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          feeNotCharged
                              ? 'Not charged - see the notice above.'
                              : 'A fee of $sym${fee.toStringAsFixed(2)} will be charged to the resident\'s flat automatically once this booking is approved.',
                          style: TextStyle(color: feeNotCharged ? Colors.red : Colors.grey, fontSize: 13),
                        ),
                      )
                    else ...[
                      _row(Icons.receipt_long_outlined, LanguageService.t('amount'), '$sym${toNum(chargeItem['amount']).toStringAsFixed(2)}'),
                      _row(Icons.check_circle_outline, LanguageService.t('paid'), '$sym${toNum(chargeItem['paid_amount']).toStringAsFixed(2)}', valueColor: Colors.green),
                      _row(Icons.pending_outlined, LanguageService.t('outstanding'), '$sym${toNum(chargeItem['outstanding']).toStringAsFixed(2)}', valueColor: toNum(chargeItem['outstanding']) > 0 ? Colors.red : Colors.green),
                      const SizedBox(height: 8),
                      _chargeStatusBadge(chargeItem['status']?.toString()),
                      if ((chargeItem['payments'] as List?)?.isNotEmpty == true) ...[
                        const Divider(height: 24),
                        Text(LanguageService.t('payment_history'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ...((chargeItem['payments'] as List).map((p) {
                          final pm = p as Map;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Icon(pm['payment_method'] == 'wallet' ? Icons.account_balance_wallet_outlined : Icons.payments_outlined, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 8),
                              Expanded(child: Text('$sym${toNum(pm['amount']).toStringAsFixed(2)} · ${pm['payment_method'] ?? ''}', style: const TextStyle(fontSize: 12.5))),
                              Text(friendlyDate(pm['paid_at']), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ]),
                          );
                        })),
                      ],
                    ],
                  ]),

                  if (status == 'pending') ...[
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        label: Text(LanguageService.t('reject'), style: const TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _acting ? null : _reject,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton.icon(
                        icon: _acting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 16),
                        label: Text(LanguageService.t('approve')),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _acting ? null : () => _act('approve'),
                      )),
                    ]),
                  ],
                ])),
    );
  }

  String _hm(dynamic value) {
    final s = (value ?? '').toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  Widget _chargeStatusBadge(String? status) {
    final map = {
      'paid': ('Paid', Colors.green),
      'partial': ('Partially Paid', Colors.orange),
      'pending_approval': ('Awaiting Confirmation', Colors.blue),
      'rejected': ('Rejected', Colors.red),
      'pending': ('Pending', Colors.orange),
    };
    final (label, color) = map[status] ?? ('Pending', Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: BrandingService.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ]),
      const Divider(height: 20),
      ...children,
    ])));
  }

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: Colors.grey[500]),
        const SizedBox(width: 8),
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.grey))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor))),
      ]),
    );
  }
}
