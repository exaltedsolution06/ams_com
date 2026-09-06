import 'package:flutter/material.dart';
import '../../utils/type_helpers.dart';
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

class AdminFloorsScreen extends StatefulWidget {
  const AdminFloorsScreen({super.key});
  @override
  State<AdminFloorsScreen> createState() => _AdminFloorsScreenState();
}

class _AdminFloorsScreenState extends State<AdminFloorsScreen> {
  List _floors  = [];
  List _towers  = [];
  bool _loading = true;
  String? _error;
  int? _filterTowerId;

  @override
  void initState() { super.initState(); _loadAll(); }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api   = ApiService();
      final fRes  = await api.get('/admin/floors');
      final tRes  = await api.get('/admin/towers');
      dynamic raw = fRes['data'];
      if (raw is Map && raw.containsKey('data')) raw = raw['data'];
      dynamic tRaw = tRes['data'];
      if (tRaw is Map && tRaw.containsKey('data')) tRaw = tRaw['data'];
      setState(() {
        _floors  = List.from(raw  ?? []);
        _towers  = List.from(tRaw ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  List get _filtered => _filterTowerId == null
      ? _floors
      : _floors.where((f) {
          final towerId = (f['tower'] as Map?)?['id'] ?? f['tower_id'];
          return towerId == _filterTowerId;
        }).toList();

  // ── Add / Edit Form ────────────────────────────────────────────────────
  void _showForm({Map? floor}) {
    final floorNumCtrl = TextEditingController(
        text: floor?['floor_number']?.toString() ?? '');
    final labelCtrl = TextEditingController(
        text: floor?['label'] as String? ?? '');
    bool isActive   = floor != null ? (toBool(floor['is_active'])) : true;
    int? towerId    = floor != null
        ? ((floor['tower'] as Map?)?['id'] as int? ?? floor['tower_id'] as int?)
        : (_filterTowerId ?? (_towers.isNotEmpty ? _towers[0]['id'] as int : null));
    final isEdit    = floor != null;
    final hasTowers = BrandingService.hasTowers;
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
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            FormSheetHeader(
              icon: Icons.layers_outlined,
              title: isEdit ? 'Edit Floor' : 'Add Floor',
              accent: Colors.teal,
              onClose: () => Navigator.pop(ctx),
            ),
            FormErrorBanner(message: formError),

            // Tower selector (only when this apartment uses towers)
            if (hasTowers) ...[
              AppFieldShell(
                accent: BrandingService.primary,
                child: DropdownButtonFormField<int>(
                  value: towerId,
                  decoration: appFieldDecoration(label: LanguageService.t('tower_2'), icon: Icons.cell_tower_outlined, accent: BrandingService.primary),
                  items: _towers.map<DropdownMenuItem<int>>((t) => DropdownMenuItem(
                    value: t['id'] as int,
                    child: Text(t['name'] as String? ?? ''),
                  )).toList(),
                  onChanged: (v) => setS(() => towerId = v),
                  validator: (v) => v == null ? 'Select a tower' : null,
                ),
              ),
              const SizedBox(height: 14),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      LanguageService.t('this_apartment_doesnt_use_towers_the_floor_will'),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
                ]),
              ),

            // Floor number
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: floorNumCtrl,
                keyboardType: TextInputType.number,
                decoration: appFieldDecoration(
                  label: LanguageService.t('floor_number'),
                  hint: LanguageService.t('e_g_1_2_3_or_g_for_ground'),
                  icon: Icons.layers_outlined, accent: BrandingService.secondary,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Display label (optional)
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: labelCtrl,
                decoration: appFieldDecoration(
                  label: LanguageService.t('display_label_optional'),
                  hint: LanguageService.t('e_g_ground_floor_mezzanine'),
                  icon: Icons.label_outline, accent: BrandingService.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Active toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(children: [
                const Icon(Icons.toggle_on_outlined, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(child: Text(LanguageService.t('active'), style: TextStyle(fontSize: 15))),
                Switch(
                  value: isActive,
                  onChanged: (v) => setS(() => isActive = v),
                  activeColor: BrandingService.primary,
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Submit
            ElevatedButton.icon(
              icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
              label: Text(isEdit ? 'Save Changes' : 'Add Floor'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                setS(() => formError = null);
                final numText = floorNumCtrl.text.trim();
                if (numText.isEmpty) {
                  setS(() => formError = LanguageService.t('floor_number_is_required'));
                  return;
                }
                if (hasTowers && towerId == null) {
                  setS(() => formError = LanguageService.t('please_select_a_tower'));
                  return;
                }
                try {
                  final body = {
                    if (hasTowers) 'tower_id': towerId,
                    'floor_number': int.tryParse(numText) ?? numText,
                    'label':        labelCtrl.text.trim(),
                    'is_active':    isActive,
                  };
                  if (isEdit) {
                    await ApiService().put('/admin/floors/${floor!['id']}', body);
                  } else {
                    await ApiService().post('/admin/floors', body);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAll();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isEdit ? 'Floor updated!' : 'Floor added!'),
                      backgroundColor: Colors.green));
                } catch (e) {
                  setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                }
              },
            ),
          ],
        )),
      ),
    );
  }

  // ── Delete ──────────────────────────────────────────────────────────────
  Future<void> _delete(Map floor) async {
    final floorNum  = floor['floor_number']?.toString() ?? 'this floor';
    final towerName = (floor['tower'] as Map?)?['name'] as String? ?? '';
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_floor'),
      message: 'Delete Floor $floorNum${towerName.isNotEmpty ? ' in $towerName' : ''}? All flats on this floor will also be affected.',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm == true) {
      try {
        await ApiService().delete('/admin/floors/${floor['id']}');
        _loadAll();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('floor_deleted')), backgroundColor: Colors.red));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Toggle active ────────────────────────────────────────────────────────
  Future<void> _toggleActive(Map floor) async {
    try {
      final towerId = (floor['tower'] as Map?)?['id'] ?? floor['tower_id'];
      await ApiService().put('/admin/floors/${floor['id']}', {
        if (towerId != null) 'tower_id': towerId,
        'floor_number': floor['floor_number'],
        'is_active':    !(toBool(floor['is_active'])),
      });
      _loadAll();
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
            else context.go('/admin/dashboard');
          },
        ),
        title: Text(LanguageService.t('floors')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: (BrandingService.hasTowers && _towers.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add),
              label: Text(LanguageService.t('add_floor')),
              backgroundColor: Colors.teal,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(icon: const Icon(Icons.refresh), label: Text(LanguageService.t('retry')), onPressed: _loadAll),
                ]))
              : (BrandingService.hasTowers && _towers.isEmpty)
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.cell_tower_outlined, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(LanguageService.t('add_a_tower_first_before_adding_floors'),
                          style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cell_tower_outlined),
                        label: Text(LanguageService.t('go_to_towers')),
                        onPressed: () => context.push('/admin/towers'),
                      ),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: Column(children: [
                        // Summary + Tower filter
                        Container(
                          color: Colors.teal.withOpacity(0.05),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(children: [
                            // Stats row
                            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                              _Stat('Floors', '${_floors.length}', Icons.layers_outlined, Colors.teal),
                              _Stat('Showing', '${filtered.length}', Icons.filter_list, primary),
                              _Stat('Active',
                                  '${_floors.where((f) => f['is_active'] == true).length}',
                                  Icons.check_circle_outline, Colors.green),
                            ]),
                            const SizedBox(height: 10),
                            // Tower filter chips
                            SizedBox(
                              height: 32,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _FilterChip(
                                    label: LanguageService.t('all_towers'),
                                    selected: _filterTowerId == null,
                                    onTap: () => setState(() => _filterTowerId = null),
                                    color: primary,
                                  ),
                                  ...(_towers.map((t) => _FilterChip(
                                    label: t['name'] as String? ?? '',
                                    selected: _filterTowerId == t['id'],
                                    onTap: () => setState(() => _filterTowerId = t['id'] as int),
                                    color: Colors.teal,
                                  ))),
                                ],
                              ),
                            ),
                          ]),
                        ),

                        // List
                        Expanded(child: filtered.isEmpty
                            ? EmptyState(
                                icon: Icons.layers_outlined,
                                color: primary,
                                title: LanguageService.t('no_floors_found'),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final f      = filtered[i] as Map;
                                  final active = toBool(f['is_active']);
                                  final tower  = (f['tower'] as Map?)?['name'] as String? ?? '';
                                  final flatCount = f['total_flats'] as int? ?? 0;
                                  final label  = f['label'] as String?;
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(children: [
                                        // Icon
                                        Container(
                                          width: 48, height: 48,
                                          decoration: BoxDecoration(
                                            color: (active ? Colors.teal : Colors.grey).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                            Icon(Icons.layers_outlined,
                                                color: active ? Colors.teal : Colors.grey, size: 18),
                                            Text(f['floor_number']?.toString() ?? '?',
                                                style: TextStyle(
                                                    fontSize: 11, fontWeight: FontWeight.bold,
                                                    color: active ? Colors.teal : Colors.grey)),
                                          ]),
                                        ),
                                        const SizedBox(width: 12),
                                        // Info
                                        Expanded(child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(
                                                label != null && label.isNotEmpty
                                                    ? label
                                                    : 'Floor ${f['floor_number'] ?? '—'}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: (active ? Colors.green : Colors.grey).withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(active ? 'Active' : 'Inactive',
                                                    style: TextStyle(
                                                        fontSize: 9, fontWeight: FontWeight.bold,
                                                        color: active ? Colors.green : Colors.grey)),
                                              ),
                                            ]),
                                            const SizedBox(height: 3),
                                            Row(children: [
                                              if (tower.isNotEmpty) ...[
                                                Icon(Icons.cell_tower_outlined, size: 12, color: Colors.grey[500]),
                                                const SizedBox(width: 3),
                                                Text(tower, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                                const SizedBox(width: 10),
                                              ],
                                              Icon(Icons.door_front_door_outlined, size: 12, color: Colors.orange[400]),
                                              const SizedBox(width: 3),
                                              Text('$flatCount flats',
                                                  style: TextStyle(fontSize: 12, color: Colors.orange[700])),
                                            ]),
                                          ],
                                        )),
                                        // 3-dot menu
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          onSelected: (val) {
                                            if (val == 'edit')   _showForm(floor: f);
                                            if (val == 'toggle') _toggleActive(f);
                                            if (val == 'delete') _delete(f);
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(value: 'edit',
                                                child: Row(children: [
                                                  Icon(Icons.edit_outlined, size: 18),
                                                  SizedBox(width: 10), Text(LanguageService.t('edit')),
                                                ])),
                                            PopupMenuItem(value: 'toggle',
                                                child: Row(children: [
                                                  Icon(active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, size: 18),
                                                  const SizedBox(width: 10),
                                                  Text(active ? 'Set Inactive' : 'Set Active'),
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
                                    ),
                                  );
                                },
                              )),
                      ]),
                    ),
    );
  }
}

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
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    ]),
  ]);
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _FilterChip({required this.label, required this.selected, required this.onTap, required this.color});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.grey[300]!),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: selected ? Colors.white : Colors.grey[700],
      )),
    ),
  );
}
