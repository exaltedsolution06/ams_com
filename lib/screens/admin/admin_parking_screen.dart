import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/admin_screen_header.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminParkingScreen extends StatefulWidget {
  const AdminParkingScreen({super.key});
  @override State<AdminParkingScreen> createState() => _PState();
}

class _PState extends State<AdminParkingScreen> {
  List    _slots     = [];
  List    _flats     = [];
  bool    _loading   = true;
  String? _error;
  int     _tabIdx    = 0;
  final   _statuses  = ['all', 'available', 'occupied', 'reserved'];

  @override void initState() { super.initState(); _loadAll(); }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    final s = _statuses[_tabIdx];
    final q = s == 'all' ? '' : '?status=$s';
    try {
      final api  = ApiService();
      final sRes = await api.get('/admin/parking$q');
      final fRes = await api.get('/admin/flats');
      dynamic sR = sRes['data']; if (sR is Map) sR = sR['data'];
      dynamic fR = fRes['data']; if (fR is Map) fR = fR['data'];
      setState(() {
        _slots = List.from(sR ?? []);
        // Only flats with a linked resident can receive a parking slot.
        _flats = List.from(fR ?? []).where((f) => (f as Map)['resident'] != null).toList();
        _loading = false;
      });
    } catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; }); }
  }

  Color  _sc(String? s) => switch (s) { 'available' => Colors.green, 'occupied' => Colors.red, 'reserved' => Colors.orange, _ => Colors.grey };
  IconData _si(String? s) => switch (s) { 'available' => Icons.check_circle_outline, 'occupied' => Icons.car_rental, 'reserved' => Icons.pending_outlined, _ => Icons.local_parking };

  // ── Add Slot ────────────────────────────────────────────────────────────
  void _showAddSlot({Map? slot}) {
    final numCtrl  = TextEditingController(text: slot?['slot_number'] as String? ?? '');
    final levelCtrl= TextEditingController(text: slot?['level'] as String? ?? 'B1');
    final chargeCtrl = TextEditingController(text: slot?['monthly_charge']?.toString() ?? '');
    String type    = slot?['slot_type'] as String? ?? 'car';
    final isEdit   = slot != null;
    String? formError;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)))),
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_parking_rounded, color: Colors.teal, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(isEdit ? 'Edit Parking Slot' : 'Add Parking Slot', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 20),
          FormErrorBanner(message: formError),
          Row(children: [
            Expanded(child: AppFieldShell(accent: Colors.teal, child: TextField(controller: numCtrl, autofocus: true,
                decoration: appFieldDecoration(label: LanguageService.t('slot_number'), hint: LanguageService.t('e_g_p_101'), icon: Icons.tag_outlined, accent: Colors.teal)))),
            const SizedBox(width: 12),
            Expanded(child: AppFieldShell(accent: Colors.teal, child: TextField(controller: levelCtrl,
                decoration: appFieldDecoration(label: LanguageService.t('level_floor'), hint: LanguageService.t('e_g_b1_g'), icon: Icons.layers_outlined, accent: Colors.teal)))),
          ]),
          const SizedBox(height: 16),
          Text(LanguageService.t('slot_type'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [
            _SlotTypeChip('Car',    'car',        Icons.directions_car,     type, (v) => setS(() => type = v)),
            const SizedBox(width: 8),
            _SlotTypeChip('Bike',   'bike',       Icons.two_wheeler,         type, (v) => setS(() => type = v)),
            const SizedBox(width: 8),
            _SlotTypeChip('EV',     'ev',         Icons.electric_car,        type, (v) => setS(() => type = v)),
            const SizedBox(width: 8),
            _SlotTypeChip('Truck',  'truck',      Icons.local_shipping,      type, (v) => setS(() => type = v)),
          ]),
          const SizedBox(height: 16),
          AppFieldShell(
            accent: Colors.teal,
            child: TextField(
              controller: chargeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: appFieldDecoration(
                label: LanguageService.t('monthly_maintenance_charge_optional'),
                hint: LanguageService.t('e_g_500'),
                icon: Icons.currency_rupee_rounded, accent: Colors.teal,
              ).copyWith(helperText: 'Added as its own line item on the resident\'s next bill, if set.'),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Colors.teal, Color(0xFF00695C)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: ElevatedButton.icon(
              icon: Icon(isEdit ? Icons.save_outlined : Icons.add),
              label: Text(isEdit ? 'Save Changes' : 'Add Slot', style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                setS(() => formError = null);
                if (numCtrl.text.trim().isEmpty) { setS(() => formError = LanguageService.t('slot_number_required')); return; }
                try {
                  final body = {
                    'slot_number': numCtrl.text.trim(),
                    'level': levelCtrl.text.trim(),
                    'slot_type': type,
                    if (chargeCtrl.text.trim().isNotEmpty) 'monthly_charge': double.tryParse(chargeCtrl.text.trim()),
                  };
                  if (isEdit) { await ApiService().put('/admin/parking/${slot!['id']}', body); }
                  else        { await ApiService().post('/admin/parking', body); }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAll();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Slot updated!' : 'Slot added!'), backgroundColor: Colors.green));
                } catch (e) { setS(() => formError = e.toString().replaceAll('Exception: ', '')); }
              },
            ),
          ),
        ])),
      ),
    );
  }

  // ── Assign to flat ──────────────────────────────────────────────────────
  void _showAssign(Map slot) {
    int?    selFlatId;
    String  status   = 'occupied';
    final   vNumCtrl = TextEditingController(text: slot['vehicle_number'] as String? ?? '');
    String? formError;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)))),
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.blue, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(LanguageService.t('assign_slot'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Slot ${slot['slot_number']}  ·  ${slot['level'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 20),
          FormErrorBanner(message: formError),
          AppFieldShell(
            accent: Colors.blue,
            child: DropdownButtonFormField<int>(
              value: selFlatId,
              decoration: appFieldDecoration(label: LanguageService.t('assign_to_flat'), icon: Icons.home_outlined, accent: Colors.blue),
              hint: Text(LanguageService.t('select_flat')),
              items: _flats.map<DropdownMenuItem<int>>((f) {
                final residentName = (f['resident'] as Map?)?['name'] as String? ?? '—';
                return DropdownMenuItem(value: f['id'] as int, child: Text('Flat ${f['flat_number']}  ·  $residentName'));
              }).toList(),
              onChanged: (v) => setS(() => selFlatId = v),
            ),
          ),
          const SizedBox(height: 16),
          Text(LanguageService.t('status'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _StatusChip('Occupied', 'occupied', Icons.car_rental, status, (v) => setS(() => status = v))),
            const SizedBox(width: 8),
            Expanded(child: _StatusChip('Reserved', 'reserved', Icons.pending_outlined, status, (v) => setS(() => status = v))),
          ]),
          const SizedBox(height: 16),
          AppFieldShell(
            accent: Colors.blue,
            child: TextField(controller: vNumCtrl, decoration: appFieldDecoration(label: LanguageService.t('vehicle_number_optional'), hint: LanguageService.t('e_g_mh_01_ab_1234'), icon: Icons.directions_car_outlined, accent: Colors.blue)),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Colors.blue, Color(0xFF1565C0)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: Text(LanguageService.t('assign_slot'), style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                setS(() => formError = null);
                if (selFlatId == null) { setS(() => formError = LanguageService.t('please_select_a_flat')); return; }
                try {
                  await ApiService().post('/admin/parking/${slot['id']}/assign', {'flat_id': selFlatId, 'vehicle_number': vNumCtrl.text.trim(), 'status': status});
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAll();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('slot_assigned')), backgroundColor: Colors.green));
                } catch (e) { setS(() => formError = e.toString().replaceAll('Exception: ', '')); }
              },
            ),
          ),
        ])),
      ),
    );
  }

  // ── Approve / reject resident-submitted request ────────────────────────
  Future<void> _approve(Map slot, String action) async {
    if (action == 'reject') {
      final ok = await AmsDialog.confirm(context, title: LanguageService.t('reject_request'), message: 'Reject the parking request for slot ${slot['slot_number']}?', icon: Icons.cancel_outlined, confirmText: 'Reject', danger: true);
      if (ok != true) return;
    }
    try {
      await ApiService().post('/admin/parking/${slot['id']}/approve', {'action': action});
      _loadAll();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'approve' ? 'Request approved!' : 'Request rejected.'), backgroundColor: action == 'approve' ? Colors.green : Colors.red));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
  }

  // ── Release slot ────────────────────────────────────────────────────────
  Future<void> _release(Map slot) async {
    final ok = await AmsDialog.confirm(context, title: LanguageService.t('release_parking_slot'), message: 'Release slot ${slot['slot_number']}? The resident will lose access.', icon: Icons.local_parking_outlined, confirmText: LanguageService.t('release'));
    if (ok == true) {
      try {
        await ApiService().post('/admin/parking/${slot['id']}/release', {});
        _loadAll();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('slot_released')), backgroundColor: Colors.orange));
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
    }
  }

  // ── Delete slot ─────────────────────────────────────────────────────────
  Future<void> _delete(Map slot) async {
    if (slot['status'] != 'available') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('release_the_slot_first_before_deleting')), backgroundColor: Colors.orange));
      return;
    }
    final ok = await AmsDialog.confirm(context, title: LanguageService.t('delete_slot'), message: 'Delete slot ${slot['slot_number']}?', icon: Icons.delete_outline_rounded, confirmText: LanguageService.t('delete'), danger: true);
    if (ok == true) {
      try {
        await ApiService().delete('/admin/parking/${slot['id']}');
        _loadAll();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('slot_deleted')), backgroundColor: Colors.red));
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total     = _slots.length;
    final available = _slots.where((s) => (s as Map)['status'] == 'available').length;
    final occupied  = _slots.where((s) => (s as Map)['status'] == 'occupied').length;
    final reserved  = _slots.where((s) => (s as Map)['status'] == 'reserved').length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')),
        title: Text(LanguageService.t('parking')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(44),
          child: SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: List.generate(_statuses.length, (i) {
              final sel = _tabIdx == i;
              final c   = [Colors.grey, Colors.green, Colors.red, Colors.orange][i];
              return GestureDetector(onTap: () { setState(() => _tabIdx = i); _loadAll(); },
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(color: sel ? c : Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? c : Colors.white.withOpacity(0.4))),
                  child: Text(LanguageService.t(_statuses[i]).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? Colors.white : Colors.white70))));
            }),
          )),
        ),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showAddSlot(), icon: const Icon(Icons.add), label: Text(LanguageService.t('add_slot')), backgroundColor: Colors.teal),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey), Text(_error!, style: const TextStyle(color: Colors.grey)), ElevatedButton(onPressed: _loadAll, child: Text(LanguageService.t('retry')))]))
          : Column(children: [
              // Summary bar
              Container(color: Colors.teal.withOpacity(0.05), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _Stat(LanguageService.t('total'),     '$total',     Colors.teal),
                  _Stat(LanguageService.t('available'), '$available', Colors.green),
                  _Stat(LanguageService.t('occupied'),  '$occupied',  Colors.red),
                  _Stat(LanguageService.t('reserved'),  '$reserved',  Colors.orange),
                ])),
              // Slots list
              Expanded(child: _slots.isEmpty
                  ? EmptyState(icon: Icons.local_parking_outlined, title: LanguageService.t('no_parking_slots_yet'), color: Colors.teal)
                  : RefreshIndicator(onRefresh: _loadAll, child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _slots.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final s      = _slots[i] as Map;
                        final status = s['status'] as String? ?? 'available';
                        final pending= s['approval_status'] == 'pending';
                        final c      = pending ? Colors.purple : _sc(status);
                        final resName= (s['user'] as Map?)?['name'] as String?;
                        final flatNo = (s['flat'] as Map?)?['flat_number'] as String? ?? (s['user'] as Map?)?['flat']?['flat_number'] as String?;
                        final level  = s['level'] as String?;
                        final slotType = (s['slot_type'] as String?) ?? 'car';
                        final subtitle = [
                          if (level != null && level.isNotEmpty) level,
                          LanguageService.t(slotType),
                        ].join('  ·  ');
                        return GestureDetector(
                          onTap: () => _showSlotMenu(s),
                          child: AdminListCard(
                            color: c,
                            child: Row(children: [
                              AdminTileIcon(color: c, icon: _si(status)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(s['slot_number'] as String? ?? '—',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(width: 6),
                                  _Badge(LanguageService.t(pending ? 'pending' : status).toUpperCase(), c),
                                ]),
                                const SizedBox(height: 3),
                                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if (resName != null || flatNo != null) ...[
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    const Icon(Icons.person_outline, size: 12, color: Colors.blueGrey),
                                    const SizedBox(width: 3),
                                    Expanded(child: Text(
                                      [if (resName != null) resName, if (flatNo != null) 'Flat $flatNo'].join('  ·  '),
                                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                      overflow: TextOverflow.ellipsis,
                                    )),
                                  ]),
                                ],
                                if (s['monthly_charge'] != null) ...[
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    const Icon(Icons.currency_rupee_rounded, size: 12, color: Colors.green),
                                    Text('${s['monthly_charge']}/mo', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                                  ]),
                                ],
                              ])),
                              if (pending)
                                Container(width: 9, height: 9, margin: const EdgeInsets.only(left: 4),
                                    decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle))
                              else
                                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                            ]),
                          ),
                        );
                      },
                    ))),
            ]),
    );
  }

  void _showSlotMenu(Map slot) {
    final status  = slot['status'] as String? ?? 'available';
    final pending = slot['approval_status'] == 'pending';
    showModalBottomSheet(context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 30), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: _sc(status).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(_si(status), color: _sc(status))), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${LanguageService.t('slot')} ${slot['slot_number']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text('${slot['level'] ?? ''}  ·  ${LanguageService.t((slot['slot_type'] ?? 'car').toString())}  ·  ${LanguageService.t(status).toUpperCase()}', style: const TextStyle(fontSize: 12, color: Colors.grey))])]),
        if ((slot['user'] as Map?) != null) ...[const SizedBox(height: 8), Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.person_outline, color: Colors.blue, size: 16), const SizedBox(width: 8), Text('${(slot['user'] as Map)?['name'] ?? '—'}  ·  ${slot['vehicle_number'] ?? LanguageService.t('no_vehicle_number')}', style: const TextStyle(fontSize: 13, color: Colors.blue))]))],
        if (slot['monthly_charge'] != null) ...[const SizedBox(height: 6), Row(children: [const Icon(Icons.currency_rupee, size: 14, color: Colors.green), const SizedBox(width: 4), Text('${slot['monthly_charge']}${LanguageService.t('month_maintenance_charge')}', style: const TextStyle(fontSize: 12.5, color: Colors.green, fontWeight: FontWeight.w600))])],
        if (pending) ...[const SizedBox(height: 6), Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.hourglass_top_outlined, color: Colors.purple, size: 16), const SizedBox(width: 8), Expanded(child: Text(LanguageService.t('resident_requested_awaiting_your_approval'), style: const TextStyle(fontSize: 12.5, color: Colors.purple)))]))],
        const SizedBox(height: 16),
        if (pending) ...[
          _MenuBtn('Approve Request', Icons.check_circle_outline, Colors.green, () { Navigator.pop(ctx); _approve(slot, 'approve'); }),
          const SizedBox(height: 8),
          _MenuBtn('Reject Request', Icons.cancel_outlined, Colors.red, () { Navigator.pop(ctx); _approve(slot, 'reject'); }),
        ] else if (status == 'available') ...[
          _MenuBtn('Edit Slot', Icons.edit_outlined, Colors.teal, () { Navigator.pop(ctx); _showAddSlot(slot: slot); }),
          const SizedBox(height: 8),
          _MenuBtn('Assign to Flat', Icons.person_add_outlined, Colors.blue, () { Navigator.pop(ctx); _showAssign(slot); }),
          const SizedBox(height: 8),
          _MenuBtn('Delete Slot', Icons.delete_outline, Colors.red, () { Navigator.pop(ctx); _delete(slot); }),
        ] else if (status == 'reserved') ...[
          _MenuBtn('Edit Slot', Icons.edit_outlined, Colors.teal, () { Navigator.pop(ctx); _showAddSlot(slot: slot); }),
          const SizedBox(height: 8),
          _MenuBtn('Assign to Flat', Icons.person_add_outlined, Colors.blue, () { Navigator.pop(ctx); _showAssign(slot); }),
          const SizedBox(height: 8),
          _MenuBtn('Release Slot', Icons.logout_outlined, Colors.orange, () { Navigator.pop(ctx); _release(slot); }),
        ] else ...[
          _MenuBtn('Edit Slot', Icons.edit_outlined, Colors.teal, () { Navigator.pop(ctx); _showAddSlot(slot: slot); }),
          const SizedBox(height: 8),
          _MenuBtn('Release Slot', Icons.logout_outlined, Colors.orange, () { Navigator.pop(ctx); _release(slot); }),
        ],
      ])),
    );
  }
}

class _Stat extends StatelessWidget {
  final String l, v; final Color c;
  const _Stat(this.l, this.v, this.c);
  @override Widget build(BuildContext context) => Column(children: [Text(v, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
}

class _StatusChip extends StatelessWidget {
  final String label, value; final IconData icon; final String selected; final ValueChanged<String> onTap;
  const _StatusChip(this.label, this.value, this.icon, this.selected, this.onTap);
  @override Widget build(BuildContext context) { final sel = selected == value; final c = value == 'reserved' ? Colors.orange : Colors.blue; return GestureDetector(onTap: () => onTap(value), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: sel ? c : Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? c : Colors.grey[300]!)), child: Column(children: [Icon(icon, color: sel ? Colors.white : c, size: 20), const SizedBox(height: 3), Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.black87))])));  }
}

class _SlotTypeChip extends StatelessWidget {
  final String label, value; final IconData icon; final String selected; final ValueChanged<String> onTap;
  const _SlotTypeChip(this.label, this.value, this.icon, this.selected, this.onTap);
  @override Widget build(BuildContext context) { final sel = selected == value; return Expanded(child: GestureDetector(onTap: () => onTap(value), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: sel ? Colors.teal : Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? Colors.teal : Colors.grey[300]!)), child: Column(children: [Icon(icon, color: sel ? Colors.white : Colors.teal, size: 20), const SizedBox(height: 3), Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.black87))]))));  }
}

class _MenuBtn extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _MenuBtn(this.label, this.icon, this.color, this.onTap);
  @override Widget build(BuildContext context) => Material(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 12), Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 14))]))));
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
  );
}
