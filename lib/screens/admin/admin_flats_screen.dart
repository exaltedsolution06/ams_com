import 'package:flutter/material.dart';
import '../../utils/type_helpers.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/admin_screen_header.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminFlatsScreen extends StatefulWidget {
  const AdminFlatsScreen({super.key});
  @override
  State<AdminFlatsScreen> createState() => _AdminFlatsScreenState();
}

class _AdminFlatsScreenState extends State<AdminFlatsScreen> {
  List    _flats   = [];
  List    _towers  = [];
  List    _floors  = [];
  bool    _loading = true;
  String? _error;
  String? _filterStatus;
  int?    _filterTowerId;

  final _statuses = ['vacant', 'owner_occupied', 'tenant_occupied', 'under_maintenance'];

  @override
  void initState() { super.initState(); _loadAll(); }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api  = ApiService();
      final fRes = await api.get('/admin/flats');
      final tRes = await api.get('/admin/towers');
      final lRes = await api.get('/admin/floors');

      dynamic fRaw = fRes['data']; if (fRaw is Map) fRaw = fRaw['data'];
      dynamic tRaw = tRes['data']; if (tRaw is Map) tRaw = tRaw['data'];
      dynamic lRaw = lRes['data']; if (lRaw is Map) lRaw = lRaw['data'];

      setState(() {
        _flats   = List.from(fRaw  ?? []);
        _towers  = List.from(tRaw  ?? []);
        _floors  = List.from(lRaw  ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  List get _filtered {
    return _flats.where((f) {
      if (_filterStatus != null && f['status'] != _filterStatus) return false;
      if (_filterTowerId != null) {
        final towerId = (f['tower'] as Map?)?['id'] ?? f['tower_id'];
        if (towerId != _filterTowerId) return false;
      }
      return true;
    }).toList();
  }

  // ── Colors / labels ────────────────────────────────────────────────────
  Color _statusColor(String? s) => switch (s) {
    'owner_occupied'      => Colors.blue,
    'tenant_occupied'     => Colors.teal,
    'under_maintenance'   => Colors.orange,
    'vacant'              => Colors.green,
    _                     => Colors.grey,
  };

  String _statusLabel(String? s) => switch (s) {
    'owner_occupied'      => 'Owner',
    'tenant_occupied'     => 'Tenant',
    'under_maintenance'   => 'Maintenance',
    'vacant'              => 'Vacant',
    _                     => s ?? 'Unknown',
  };

  // ── Add / Edit sheet ────────────────────────────────────────────────────
  void _showForm({Map? flat}) {
    final flatNumCtrl  = TextEditingController(text: flat?['flat_number'] as String? ?? '');
    final areaCtrl     = TextEditingController(text: flat?['area_sqft']?.toString() ?? '');
    bool  isActive     = flat != null ? (toBool(flat['is_active'])) : true;
    String flatType    = flat?['type'] as String? ?? '2BHK';
    String flatStatus  = flat?['status'] as String? ?? 'vacant';
    final isEdit       = flat != null;

    final hasTowers = BrandingService.hasTowers;

    // Cascade: selected tower → filtered floors
    int? selTowerId = flat != null
        ? ((flat['tower'] as Map?)?['id'] as int? ?? flat['tower_id'] as int?)
        : (_towers.isNotEmpty ? _towers[0]['id'] as int : null);
    int? selFloorId = flat != null
        ? ((flat['floor'] as Map?)?['id'] as int? ?? flat['floor_id'] as int?)
        : null;

    List<Map> floorsForTower() => _floors
        .where((fl) => (fl['tower'] as Map?)?['id'] == selTowerId || fl['tower_id'] == selTowerId)
        .map((fl) => fl as Map).toList();

    List<Map> towerlessFloors() => _floors
        .where((fl) => fl['tower'] == null && fl['tower_id'] == null)
        .map((fl) => fl as Map).toList();

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
        child: StatefulBuilder(builder: (ctx, setS) {
          final towerFloors = floorsForTower();
          // If current floor not in new list, reset
          if (selFloorId != null &&
              !towerFloors.any((fl) => fl['id'] == selFloorId)) {
            selFloorId = towerFloors.isNotEmpty ? towerFloors[0]['id'] as int : null;
          }

          return SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Header
              FormSheetHeader(
                icon: Icons.door_front_door_outlined,
                title: isEdit ? 'Edit Flat' : 'Add Flat',
                accent: BrandingService.primary,
                onClose: () => Navigator.pop(ctx),
              ),
              FormErrorBanner(message: formError),

              // ── Tower / Floor selectors (only for apartments that use towers) ──
              if (hasTowers) ...[
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: DropdownButtonFormField<int>(
                    value: selTowerId,
                    decoration: appFieldDecoration(label: LanguageService.t('tower_2'), icon: Icons.cell_tower_outlined, accent: BrandingService.primary),
                    items: _towers.map<DropdownMenuItem<int>>((t) =>
                        DropdownMenuItem(
                            value: t['id'] as int,
                            child: Text(t['name'] as String? ?? ''))).toList(),
                    onChanged: (v) => setS(() { selTowerId = v; selFloorId = null; }),
                  ),
                ),
                const SizedBox(height: 14),

                // Floor selector (cascades from tower)
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: DropdownButtonFormField<int>(
                    value: selFloorId,
                    decoration: appFieldDecoration(label: LanguageService.t('floor_2'), icon: Icons.layers_outlined, accent: BrandingService.secondary),
                    hint: Text(LanguageService.t('select_floor')),
                    items: towerFloors.map<DropdownMenuItem<int>>((fl) {
                      final label = fl['label'] as String?;
                      final num   = fl['floor_number']?.toString() ?? '';
                      return DropdownMenuItem(
                          value: fl['id'] as int,
                          child: Text(label != null && label.isNotEmpty
                              ? '$label (Floor $num)' : 'Floor $num'));
                    }).toList(),
                    onChanged: (v) => setS(() => selFloorId = v),
                  ),
                ),
                const SizedBox(height: 14),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.2))),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                        LanguageService.t('this_apartment_doesnt_use_towers_the_flat_will'),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
                  ]),
                ),
                if (towerlessFloors().isNotEmpty) ...[
                  AppFieldShell(
                    accent: BrandingService.secondary,
                    child: DropdownButtonFormField<int>(
                      value: selFloorId,
                      decoration: appFieldDecoration(label: "${LanguageService.t('floor_2')} (optional)", icon: Icons.layers_outlined, accent: BrandingService.secondary),
                      hint: Text(LanguageService.t('select_floor')),
                      items: [
                        DropdownMenuItem<int>(value: null, child: Text(LanguageService.t('none'))),
                        ...towerlessFloors().map((fl) {
                          final label = fl['label'] as String?;
                          final num   = fl['floor_number']?.toString() ?? '';
                          return DropdownMenuItem<int>(
                              value: fl['id'] as int,
                              child: Text(label != null && label.isNotEmpty
                                  ? '$label (Floor $num)' : 'Floor $num'));
                        }),
                      ],
                      onChanged: (v) => setS(() => selFloorId = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],

              // ── Flat number ───────────────────────────────────────────
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextField(
                  controller: flatNumCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: appFieldDecoration(
                      label: LanguageService.t('flat_number_2'),
                      hint: LanguageService.t('e_g_101_a_12'),
                      icon: Icons.tag_outlined, accent: BrandingService.primary),
                ),
              ),
              const SizedBox(height: 14),

              // ── Type + Area (side by side) ────────────────────────────
              Row(children: [
                Expanded(child: AppFieldShell(
                  accent: BrandingService.secondary,
                  child: DropdownButtonFormField<String>(
                    value: flatType,
                    decoration: appFieldDecoration(label: LanguageService.t('type'), icon: Icons.home_outlined, accent: BrandingService.secondary),
                    items: ['Studio','1BHK','2BHK','3BHK','4BHK','Penthouse']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setS(() => flatType = v!),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: AppFieldShell(
                  accent: BrandingService.primary,
                  child: TextField(
                    controller: areaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: appFieldDecoration(label: LanguageService.t('area_sq_ft'), icon: Icons.square_foot_outlined, accent: BrandingService.primary),
                  ),
                )),
              ]),
              const SizedBox(height: 14),

              // ── Status ────────────────────────────────────────────────
              AppFieldShell(
                accent: BrandingService.secondary,
                child: DropdownButtonFormField<String>(
                  value: flatStatus,
                  decoration: appFieldDecoration(label: LanguageService.t('status'), icon: Icons.info_outline, accent: BrandingService.secondary),
                  items: _statuses.map((s) => DropdownMenuItem(
                      value: s,
                      child: Row(children: [
                        Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                                color: _statusColor(s),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(_statusLabel(s)),
                      ]))).toList(),
                  onChanged: (v) => setS(() => flatStatus = v!),
                ),
              ),
              const SizedBox(height: 12),

              // ── Active toggle ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!)),
                child: Row(children: [
                  const Icon(Icons.toggle_on_outlined, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(child: Text(LanguageService.t('active'), style: TextStyle(fontSize: 15))),
                  Switch(
                      value: isActive,
                      onChanged: (v) => setS(() => isActive = v),
                      activeColor: BrandingService.primary),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Submit ────────────────────────────────────────────────
              ElevatedButton.icon(
                icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
                label: Text(isEdit ? 'Save Changes' : 'Add Flat'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  setS(() => formError = null);
                  if (flatNumCtrl.text.trim().isEmpty) {
                    setS(() => formError = LanguageService.t('flat_number_is_required'));
                    return;
                  }
                  if (hasTowers && (selTowerId == null || selFloorId == null)) {
                    setS(() => formError = LanguageService.t('please_select_tower_and_floor'));
                    return;
                  }
                  try {
                    final body = {
                      if (hasTowers) 'tower_id': selTowerId,
                      if (hasTowers) 'floor_id': selFloorId,
                      if (!hasTowers && selFloorId != null) 'floor_id': selFloorId,
                      'flat_number': flatNumCtrl.text.trim(),
                      'type':        flatType,
                      'status':      flatStatus,
                      'is_active':   isActive,
                      if (areaCtrl.text.trim().isNotEmpty)
                        'area_sqft': double.tryParse(areaCtrl.text.trim()),
                    };
                    if (isEdit) {
                      await ApiService().put('/admin/flats/${flat!['id']}', body);
                    } else {
                      await ApiService().post('/admin/flats', body);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadAll();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(isEdit ? 'Flat updated!' : 'Flat added!'),
                            backgroundColor: Colors.green));
                  } catch (e) {
                    setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                  }
                },
              ),
            ]),
          );
        }),
      ),
    );
  }

  // ── Delete ──────────────────────────────────────────────────────────────
  Future<void> _delete(Map flat) async {
    if (flat['status'] != 'vacant') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('cannot_delete_an_occupied_flat_change_status')),
          backgroundColor: Colors.orange));
      return;
    }
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_flat'),
      message: 'Delete Flat ${flat['flat_number']}? This cannot be undone.',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm == true) {
      try {
        await ApiService().delete('/admin/flats/${flat['id']}');
        _loadAll();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('flat_deleted')), backgroundColor: Colors.red));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleActive(Map flat) async {
    try {
      await ApiService().put('/admin/flats/${flat['id']}', {
        'tower_id':    (flat['tower'] as Map?)?['id'] ?? flat['tower_id'],
        'floor_id':    (flat['floor'] as Map?)?['id'] ?? flat['floor_id'],
        'flat_number': flat['flat_number'],
        'type':        flat['type'],
        'status':      flat['status'],
        'is_active':   !(toBool(flat['is_active'])),
      });
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red));
    }
  }

  // Resident is selling/handing off this flat: flag it (or clear the flag)
  // so Add/Edit Resident can pick it up as available even though it isn't
  // vacant yet. Flipping it OFF here just cancels the in-progress change -
  // the moment a new resident is actually linked to the flat, the backend
  // clears this flag automatically and detaches the previous occupant
  // (their own history stays intact on their own account).
  Future<void> _toggleOwnershipChange(Map flat) async {
    final turningOn = !(toBool(flat['ownership_change']));
    if (turningOn && (flat['status'] == 'vacant')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('this_flat_is_already_vacant_no_ownership_change')),
          backgroundColor: Colors.orange));
      return;
    }
    try {
      await ApiService().put('/admin/flats/${flat['id']}', {
        'ownership_change': turningOn,
      });
      _loadAll();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(turningOn
              ? 'Flat ${flat['flat_number']} flagged for ownership change.'
              : 'Ownership change flag cleared for Flat ${flat['flat_number']}.'),
          backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary  = BrandingService.primary;
    final filtered = _filtered;

    // Summary stats
    final total    = _flats.length;
    final vacant   = _flats.where((f) => f['status'] == 'vacant').length;
    final occupied = total - vacant;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (BrandingService.hasTowers && _towers.isEmpty) ? null : () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('add_flat')),
        backgroundColor: (BrandingService.hasTowers && _towers.isEmpty) ? Colors.grey : primary,
      ),
      body: Column(children: [
        AdminScreenHeader(title: LanguageService.t('flats'), onRefresh: _loadAll),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(icon: const Icon(Icons.refresh), label: Text(LanguageService.t('retry')), onPressed: _loadAll),
                    ]))
                  : Column(children: [
                  // ── Summary row ──────────────────────────────────────────
                  AdminStatRow(chips: [
                    AdminStatChip(label: LanguageService.t('total'),    value: '$total',              icon: Icons.door_front_door_outlined, color: primary),
                    AdminStatChip(label: LanguageService.t('occupied'), value: '$occupied',           icon: Icons.people_outline,           color: Colors.blue),
                    AdminStatChip(label: LanguageService.t('vacant'),   value: '$vacant',             icon: Icons.check_circle_outline,     color: Colors.green),
                    AdminStatChip(label: LanguageService.t('showing'),  value: '${filtered.length}',  icon: Icons.filter_list,              color: Colors.deepOrange),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _Chip('All', _filterStatus == null && _filterTowerId == null,
                                () => setState(() { _filterStatus = null; _filterTowerId = null; }), Colors.grey),
                            _Chip('Vacant',      _filterStatus == 'vacant',              () => setState(() => _filterStatus = 'vacant'),            Colors.green),
                            _Chip('Owner',       _filterStatus == 'owner_occupied',      () => setState(() => _filterStatus = 'owner_occupied'),     Colors.blue),
                            _Chip('Tenant',      _filterStatus == 'tenant_occupied',     () => setState(() => _filterStatus = 'tenant_occupied'),    Colors.teal),
                            _Chip('Maintenance', _filterStatus == 'under_maintenance',   () => setState(() => _filterStatus = 'under_maintenance'),  Colors.orange),
                            const VerticalDivider(width: 16),
                            ..._towers.map((t) => _Chip(
                              t['name'] as String? ?? '',
                              _filterTowerId == t['id'],
                              () => setState(() => _filterTowerId = _filterTowerId == t['id'] ? null : t['id'] as int),
                              primary,
                            )),
                          ],
                        ),
                      ),
                  ),

                  // ── Flat list ────────────────────────────────────────────
                  Expanded(child: _flats.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.door_front_door_outlined, size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(LanguageService.t('no_flats_yet_tap_to_add_one'), style: TextStyle(color: Colors.grey)),
                          if (BrandingService.hasTowers && _towers.isEmpty) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                                onPressed: () => context.push('/admin/towers'),
                                icon: const Icon(Icons.add_business_outlined, size: 16),
                                label: Text(LanguageService.t('add_tower_first')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                )),
                          ],
                        ]))
                      : filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.search_off_rounded,
                              color: primary,
                              title: LanguageService.t('no_flats_match_this_filter'),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadAll,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) => _buildFlatCard(filtered[i] as Map),
                              ),
                            )),
                ]),
        ),
      ]),
    );
  }

  Widget _buildFlatCard(Map flat) {
    final active    = toBool(flat['is_active']);
    final status    = flat['status'] as String? ?? 'vacant';
    final sColor    = _statusColor(status);
    final towerName = (flat['tower'] as Map?)?['name'] as String? ?? '';
    final floorNum  = (flat['floor'] as Map?)?['floor_number']?.toString() ?? '';
    final resident  = (flat['resident'] as Map?)?['name'] as String?;

    final locationParts = [
      if (towerName.isNotEmpty) towerName,
      if (floorNum.isNotEmpty) 'Floor $floorNum',
    ];
    final subtitle = [
      if (locationParts.isNotEmpty) locationParts.join('  ·  '),
      if (flat['type'] != null) flat['type'].toString(),
    ].join('  ·  ');

    return AdminListCard(
      color: sColor,
      child: Row(children: [
          // Status indicator
          AdminTileIcon(
            color: sColor,
            icon: Icons.door_front_door_outlined,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.door_front_door_outlined, color: Colors.white, size: 20),
              Text(flat['flat_number'] as String? ?? '?',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Flat ${flat['flat_number'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(width: 6),
              _Badge(_statusLabel(status), sColor),
              const SizedBox(width: 4),
              if (!active) _Badge('Inactive', Colors.grey),
              if (toBool(flat['ownership_change'])) ...[
                const SizedBox(width: 4),
                _Badge('Ownership Change', Colors.orange),
              ],
            ]),
            const SizedBox(height: 3),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (resident != null)
              Row(children: [
                const Icon(Icons.person_outline, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 3),
                Text(resident, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ]),
            if (flat['area_sqft'] != null)
              Text('${flat['area_sqft']} sq ft',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          // 3-dot menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'edit')   _showForm(flat: flat);
              if (val == 'toggle') _toggleActive(flat);
              if (val == 'ownership') _toggleOwnershipChange(flat);
              if (val == 'delete') _delete(flat);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit',
                  child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text(LanguageService.t('edit'))])),
              PopupMenuItem(value: 'toggle',
                  child: Row(children: [
                    Icon(active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(active ? 'Set Inactive' : 'Set Active'),
                  ])),
              if (status != 'vacant' || toBool(flat['ownership_change']))
              PopupMenuItem(value: 'ownership',
                  child: Row(children: [
                    const Icon(Icons.swap_horiz_outlined, size: 18, color: Colors.orange),
                    const SizedBox(width: 10),
                    Text(toBool(flat['ownership_change']) ? 'Cancel Ownership Change' : 'Mark Ownership Change'),
                  ])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 10),
                    Text(LanguageService.t('delete'), style: TextStyle(color: Colors.red)),
                  ])),
            ],
          ),
        ]),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────
class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 15),
    const SizedBox(width: 4),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
      Text(label,  style: const TextStyle(fontSize: 10, color: Colors.grey)),
    ]),
  ]);
}

class _Chip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  final Color  color;
  const _Chip(this.label, this.selected, this.onTap, this.color);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color:  selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey[300]!)),
      child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : Colors.grey[700])),
    ),
  );
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
