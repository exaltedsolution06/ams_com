// ── Admin Facilities Screen ───────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../utils/type_helpers.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';

class AdminFacilitiesScreen extends StatefulWidget {
  const AdminFacilitiesScreen({super.key});
  @override State<AdminFacilitiesScreen> createState() => _FState();
}

class _FState extends State<AdminFacilitiesScreen> {
  List _facilities = []; bool _loading = true; String? _error;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { final res = await ApiService().get('/admin/facilities'); dynamic r = res['data']; if (r is Map) r = r['data']; setState(() { _facilities = List.from(r ?? []); _loading = false; }); }
    catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; }); }
  }

  IconData _icon(String? t) => switch (t) { 'gym' => Icons.fitness_center, 'pool' => Icons.pool, 'clubhouse' => Icons.celebration_outlined, 'playground' => Icons.sports_basketball, 'garden' => Icons.park, 'hall' => Icons.meeting_room_outlined, _ => Icons.meeting_room_outlined };

  void _showForm({Map? facility}) {
    final nameCtrl  = TextEditingController(text: facility?['name'] as String? ?? '');
    final capCtrl   = TextEditingController(text: facility?['capacity']?.toString() ?? '');
    final feeCtrl   = TextEditingController(text: facility?['booking_fee']?.toString() ?? '0');
    final descCtrl  = TextEditingController(text: facility?['description'] as String? ?? '');
    TimeOfDay openTime  = parseTimeOfDay(facility?['open_time'] as String?, fallback: const TimeOfDay(hour: 6, minute: 0));
    TimeOfDay closeTime = parseTimeOfDay(facility?['close_time'] as String?, fallback: const TimeOfDay(hour: 22, minute: 0));
    String type     = facility?['type'] as String? ?? 'gym';
    bool   active   = facility != null ? (toBool(facility['is_active'])) : true;
    final  isEdit   = facility != null;
    String? formError;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(_icon(type), color: BrandingService.primary)), const SizedBox(width: 12), Text(isEdit ? LanguageService.t('edit_facility') : LanguageService.t('add_facility'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
          const SizedBox(height: 16),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: nameCtrl, decoration: appFieldDecoration(label: LanguageService.t('facility_name'), icon: Icons.meeting_room_outlined, accent: BrandingService.primary))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppFieldShell(accent: BrandingService.secondary, child: DropdownButtonFormField<String>(value: type, decoration: appFieldDecoration(label: LanguageService.t('type'), icon: Icons.category_outlined, accent: BrandingService.secondary), items: ['gym','pool','clubhouse','playground','garden','hall','other'].map((t) => DropdownMenuItem(value: t, child: Text(LanguageService.t(t)))).toList(), onChanged: (v) => setS(() => type = v!)))),
            const SizedBox(width: 12),
            Expanded(child: AppFieldShell(accent: BrandingService.primary, child: TextField(controller: capCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: LanguageService.t('capacity'), icon: Icons.people_outline, accent: BrandingService.primary)))),
          ]),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: feeCtrl, keyboardType: TextInputType.number, decoration: appFieldDecoration(label: '${LanguageService.t('booking_fee')} (${BrandingService.currencySymbol})', icon: Icons.currency_rupee, accent: BrandingService.secondary))),
          const SizedBox(height: 20),
          Text(LanguageService.t('timings'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: TimeFieldPicker(
                label: LanguageService.t('open'),
                icon: Icons.access_time,
                accent: BrandingService.secondary,
                time: openTime,
                onChanged: (t) => setS(() => openTime = t),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward, size: 18, color: Colors.grey[500]),
            ),
            Expanded(
              child: TimeFieldPicker(
                label: LanguageService.t('close'),
                icon: Icons.access_time_filled,
                accent: BrandingService.secondary,
                time: closeTime,
                onChanged: (t) => setS(() => closeTime = t),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: descCtrl, maxLines: 2, decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: BrandingService.primary).copyWith(alignLabelWithHint: true))),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[300]!)),
            child: Row(children: [Expanded(child: Text(LanguageService.t('active_available_for_booking'))), Switch(value: active, onChanged: (v) => setS(() => active = v), activeColor: BrandingService.primary)])),
          const SizedBox(height: 20),
          ElevatedButton.icon(icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline), label: Text(isEdit ? 'Save Changes' : 'Add Facility'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              setS(() => formError = null);
              if (nameCtrl.text.trim().isEmpty) { setS(() => formError = LanguageService.t('facility_name_required')); return; }
              try {
                final body = {'name': nameCtrl.text.trim(), 'type': type, 'capacity': int.tryParse(capCtrl.text.trim()) ?? 0, 'booking_fee': double.tryParse(feeCtrl.text.trim()) ?? 0, 'description': descCtrl.text.trim(), 'open_time': formatTimeOfDay24(openTime), 'close_time': formatTimeOfDay24(closeTime), 'is_active': active};
                if (isEdit) { await ApiService().put('/admin/facilities/${facility!['id']}', body); } else { await ApiService().post('/admin/facilities', body); }
                if (ctx.mounted) Navigator.pop(ctx); _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Facility updated!' : 'Facility added!'), backgroundColor: Colors.green));
              } catch (e) { setS(() => formError = e.toString().replaceAll('Exception: ', '')); }
            }),
        ]))),
      ),
    );
  }

  Future<void> _delete(Map f) async {
    final ok = await AmsDialog.confirm(context, title: LanguageService.t('delete_facility'), message: 'Delete "${f['name']}"? All bookings for this facility will also be deleted.', icon: Icons.delete_outline_rounded, confirmText: LanguageService.t('delete'), danger: true);
    if (ok == true) { try { await ApiService().delete('/admin/facilities/${f['id']}'); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); } }
  }

  Future<void> _toggleActive(Map f) async {
    try { await ApiService().put('/admin/facilities/${f['id']}', {'name': f['name'], 'type': f['type'], 'capacity': f['capacity'], 'is_active': !(toBool(f['is_active']))}); _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final sym = BrandingService.currencySymbol;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')), title: Text(LanguageService.t('facilities')), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showForm(), icon: const Icon(Icons.add), label: Text(LanguageService.t('add_facility')), backgroundColor: BrandingService.primary),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey), Text(_error!, style: const TextStyle(color: Colors.grey)), ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry')))]))
          : _facilities.isEmpty ? EmptyState(icon: Icons.meeting_room_outlined, title: LanguageService.t('no_facilities_yet'), color: BrandingService.primary)
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: _facilities.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) { final f = _facilities[i] as Map; final active = toBool(f['is_active']); final fee = double.tryParse(f['booking_fee']?.toString() ?? '0') ?? 0;
                return Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: (active ? BrandingService.primary : Colors.grey).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(_icon(f['type'] as String?), color: active ? BrandingService.primary : Colors.grey, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Text(f['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: (active ? Colors.green : Colors.grey).withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Text(active ? 'Active' : 'Inactive', style: TextStyle(fontSize: 9, color: active ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)))]),
                    Row(children: [Icon(Icons.people_outline, size: 12, color: Colors.grey[500]), const SizedBox(width: 3), Text('Cap: ${f['capacity'] ?? '—'}', style: const TextStyle(fontSize: 11, color: Colors.grey)), const SizedBox(width: 10), if (fee > 0) ...[Icon(Icons.currency_rupee, size: 12, color: Colors.orange[600]), Text('$sym${fee.toStringAsFixed(0)}/booking', style: TextStyle(fontSize: 11, color: Colors.orange[700]))] else Text(LanguageService.t('free'), style: TextStyle(fontSize: 11, color: Colors.green))]),
                    if (f['open_time'] != null) Text('${f['open_time']} - ${f['close_time'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                  ])),
                  PopupMenuButton<String>(icon: const Icon(Icons.more_vert, color: Colors.grey), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (v) { if (v == 'edit') _showForm(facility: f); if (v == 'toggle') _toggleActive(f); if (v == 'delete') _delete(f); },
                    itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text(LanguageService.t('edit'))])), PopupMenuItem(value: 'toggle', child: Row(children: [Icon(active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, size: 18), const SizedBox(width: 10), Text(active ? 'Set Inactive' : 'Set Active')])), const PopupMenuDivider(), PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text(LanguageService.t('delete'), style: TextStyle(color: Colors.red))]))]),
                ])));
              })),
    );
  }
}

// ── Admin Bookings Screen ─────────────────────────────────────────────────────
class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});
  @override State<AdminBookingsScreen> createState() => _BkState();
}

class _BkState extends State<AdminBookingsScreen> {
  List _bookings = []; bool _loading = true; String? _error;
  int  _tabIdx   = 0;
  final _statuses = ['all', 'pending', 'approved', 'rejected', 'cancelled'];

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final s = _statuses[_tabIdx];
    final q = s == 'all' ? '' : '?status=$s';
    try { final res = await ApiService().get('/admin/bookings$q'); dynamic r = res['data']; if (r is Map) r = r['data']; setState(() { _bookings = List.from(r ?? []); _loading = false; }); }
    catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; }); }
  }

  Future<void> _action(int id, String action, {String? reason}) async {
    try {
      await ApiService().post('/admin/bookings/$id/action', {'action': action, if (reason != null) 'rejection_reason': reason});
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking ${action}d!'), backgroundColor: Colors.green));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
  }

  Color _sc(String? s) => switch(s) { 'approved' => Colors.green, 'rejected' => Colors.red, 'cancelled' => Colors.grey, _ => Colors.orange };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _statuses.length,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')),
          title: Text(LanguageService.t('facility_bookings')),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
          bottom: TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: Colors.white, isScrollable: true, tabAlignment: TabAlignment.start,
            onTap: (i) { setState(() => _tabIdx = i); _load(); },
            tabs: _statuses.map((s) => Tab(text: LanguageService.t(s).toUpperCase())).toList()),
        ),
        drawer: const AppDrawer(),
        onDrawerChanged: DrawerVisibility.onChanged,
        body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey), Text(_error!, style: const TextStyle(color: Colors.grey)), ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry')))]))
            : _bookings.isEmpty ? EmptyState(icon: Icons.calendar_month_outlined, title: LanguageService.t('no_bookings_found'), color: Colors.teal)
            : RefreshIndicator(onRefresh: _load, child: ListView.separated(padding: const EdgeInsets.fromLTRB(12, 12, 12, 20), itemCount: _bookings.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) { final b = _bookings[i] as Map; final status = b['status'] as String? ?? 'pending'; final sc = _sc(status);
                  final fee = toNum((b['facility'] as Map?)?['booking_fee']);
                  final feeNotCharged = status == 'approved' && fee > 0 && b['charge_item'] == null;
                  return Card(child: InkWell(
                    onTap: () => context.push('/admin/bookings/${b['id']}'),
                    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text((b['facility'] as Map?)?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Text(LanguageService.t(status).toUpperCase(), style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.bold)))]),
                    const SizedBox(height: 6),
                    Row(children: [Icon(Icons.person_outline, size: 13, color: Colors.grey[600]), const SizedBox(width: 3), Text((b['user'] as Map?)?['name'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(width: 12), Icon(Icons.calendar_today, size: 13, color: Colors.grey[600]), const SizedBox(width: 3), Text(friendlyDate(b['booking_date']), style: const TextStyle(fontSize: 12, color: Colors.grey)), if (fee > 0) ...[const SizedBox(width: 12), Icon(Icons.currency_rupee, size: 13, color: Colors.orange[600]), Text(fee.toStringAsFixed(0), style: TextStyle(fontSize: 12, color: Colors.orange[700]))]]),
                    if (feeNotCharged) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.amber),
                        const SizedBox(width: 4),
                        Expanded(child: Text(LanguageService.t('approved_but_fee_not_charged_no_flat_linked'), style: TextStyle(fontSize: 11, color: Colors.amber[800], fontWeight: FontWeight.w600))),
                      ]),
                    ],
                    if (status == 'pending') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.close, size: 14, color: Colors.red), label: Text(LanguageService.t('reject'), style: TextStyle(color: Colors.red)), onPressed: () => _action(b['id'] as int, 'reject'), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 8)))),
                        const SizedBox(width: 10),
                        Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.check, size: 14), label: Text(LanguageService.t('approve')), onPressed: () => _action(b['id'] as int, 'approve'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 8)))),
                      ]),
                    ],
                  ]))));
                })),
      ),
    );
  }
}
