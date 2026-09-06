import 'package:flutter/material.dart';
import '../../utils/type_helpers.dart';
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

class AdminTowersScreen extends StatefulWidget {
  const AdminTowersScreen({super.key});
  @override
  State<AdminTowersScreen> createState() => _AdminTowersScreenState();
}

class _AdminTowersScreenState extends State<AdminTowersScreen> {
  List _towers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/towers');
      dynamic raw = res['data'];
      if (raw is Map && raw.containsKey('data')) raw = raw['data'];
      setState(() { _towers = List.from(raw ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  // ── Add / Edit Dialog ────────────────────────────────────────────────────
  void _showForm({Map? tower}) {
    final nameCtrl = TextEditingController(text: tower?['name'] as String? ?? '');
    final descCtrl = TextEditingController(text: tower?['description'] as String? ?? '');
    bool isActive  = tower != null ? (toBool(tower['is_active'])) : true;
    final isEdit   = tower != null;
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
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            FormSheetHeader(
              icon: Icons.cell_tower_outlined,
              title: isEdit ? 'Edit Tower' : 'Add Tower',
              accent: BrandingService.primary,
              onClose: () => Navigator.pop(ctx),
            ),
            FormErrorBanner(message: formError),
            // Name
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: appFieldDecoration(
                  label: LanguageService.t('tower_name'),
                  hint: LanguageService.t('e_g_tower_a_block_1'),
                  icon: Icons.cell_tower_outlined, accent: BrandingService.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Description
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: BrandingService.secondary).copyWith(alignLabelWithHint: true),
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
            // Submit button
            ElevatedButton.icon(
              icon: Icon(isEdit ? Icons.save_outlined : Icons.add_circle_outline),
              label: Text(isEdit ? 'Save Changes' : 'Add Tower'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                setS(() => formError = null);
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setS(() => formError = LanguageService.t('tower_name_is_required'));
                  return;
                }
                try {
                  if (isEdit) {
                    await ApiService().put('/admin/towers/${tower!['id']}', {
                      'name': name, 'description': descCtrl.text.trim(), 'is_active': isActive,
                    });
                  } else {
                    await ApiService().post('/admin/towers', {
                      'name': name, 'description': descCtrl.text.trim(), 'is_active': isActive,
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(isEdit ? 'Tower updated!' : 'Tower added!'),
                        backgroundColor: Colors.green));
                  }
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

  // ── Delete confirmation ───────────────────────────────────────────────────
  Future<void> _delete(Map tower) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_tower'),
      message: 'Delete "${tower['name']}"? This will also affect all floors and flats in this tower.',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm == true) {
      try {
        await ApiService().delete('/admin/towers/${tower['id']}');
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('tower_deleted')), backgroundColor: Colors.red));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Toggle active ─────────────────────────────────────────────────────────
  Future<void> _toggleActive(Map tower) async {
    try {
      await ApiService().put('/admin/towers/${tower['id']}', {
        'name': tower['name'], 'is_active': !(toBool(tower['is_active'])),
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
    final primary = BrandingService.primary;
    final totalFlats  = _towers.fold<int>(0, (s, t) => s + (t['total_flats'] as int? ?? 0));
    final totalFloors = _towers.fold<int>(0, (s, t) => s + (t['total_floors'] as int? ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: BrandingService.hasTowers
          ? FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add),
              label: Text(LanguageService.t('add_tower')),
              backgroundColor: primary,
            )
          : null,
      body: Column(children: [
        AdminScreenHeader(title: LanguageService.t('towers'), onRefresh: _load),
        Expanded(
          child: !BrandingService.hasTowers
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(LanguageService.t('this_apartment_is_set_up_without_towers'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(LanguageService.t('flats_are_added_directly_under_flats_no_tower'),
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ]),
            ))
          : _loading
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
                    // Summary row
                    if (_towers.isNotEmpty)
                      AdminStatRow(chips: [
                        AdminStatChip(label: LanguageService.t('towers'), value: '${_towers.length}', icon: Icons.cell_tower_outlined, color: primary),
                        AdminStatChip(label: LanguageService.t('floors'), value: '$totalFloors',       icon: Icons.layers_outlined,     color: Colors.teal),
                        AdminStatChip(label: LanguageService.t('flats'),  value: '$totalFlats',        icon: Icons.door_front_door_outlined, color: Colors.orange),
                        AdminStatChip(label: LanguageService.t('active'),
                            value: '${_towers.where((t) => t['is_active'] == true).length}',
                            icon: Icons.check_circle_outline, color: Colors.green),
                      ]),

                    // List
                    Expanded(
                      child: _towers.isEmpty
                          ? EmptyState(icon: Icons.cell_tower_outlined, title: LanguageService.t('no_towers_yet_tap_to_add_one'), color: primary)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                              itemCount: _towers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final t       = _towers[i] as Map;
                                final active  = toBool(t['is_active']);
                                final floors  = t['total_floors'] as int? ?? 0;
                                final flats   = t['total_flats']  as int? ?? 0;
                                final tColor  = active ? primary : Colors.grey;
                                return AdminListCard(
                                  color: tColor,
                                  child: Row(children: [
                                      // Icon
                                      AdminTileIcon(color: tColor, icon: Icons.cell_tower_outlined, size: 48),
                                      const SizedBox(width: 12),
                                      // Info
                                      Expanded(child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Text(t['name'] as String? ?? '—',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: (active ? Colors.green : Colors.grey).withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(active ? 'Active' : 'Inactive',
                                                  style: TextStyle(
                                                    fontSize: 10, fontWeight: FontWeight.bold,
                                                    color: active ? Colors.green : Colors.grey,
                                                  )),
                                            ),
                                          ]),
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            _InfoChip(Icons.layers_outlined, '$floors Floors', Colors.teal),
                                            const SizedBox(width: 8),
                                            _InfoChip(Icons.door_front_door_outlined, '$flats Flats', Colors.orange),
                                          ]),
                                          if ((t['description'] as String?)?.isNotEmpty == true)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(t['description'] as String,
                                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                            ),
                                        ],
                                      )),
                                      // Actions
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        onSelected: (val) {
                                          if (val == 'edit')   _showForm(tower: t);
                                          if (val == 'toggle') _toggleActive(t);
                                          if (val == 'delete') _delete(t);
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
                              },
                            ),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: color),
    const SizedBox(width: 3),
    Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
  ]);
}
