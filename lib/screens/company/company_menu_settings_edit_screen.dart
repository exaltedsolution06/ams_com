import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/menu_config_service.dart';
import '../../widgets/ams_dialog.dart';

class _QuickRow {
  final String key, label, icon;
  bool enabled;
  final TextEditingController orderCtrl;
  _QuickRow({required this.key, required this.label, required this.icon, required this.enabled, required int order})
      : orderCtrl = TextEditingController(text: '$order');
}

class _NavCatalogItem {
  final String key, label;
  final String icon;
  const _NavCatalogItem({required this.key, required this.label, required this.icon});
}

class _RoleMenu {
  List<_QuickRow> quick = [];
  List<_NavCatalogItem> navCatalog = [];
  String homeLabel = '';
  List<String?> flanking = [null, null, null]; // position1, position2, position3
  String? center;
}

/// "Configure Menus" editor for one apartment - same 3 roles (Resident,
/// Apartment Admin, Security) x 2 sections (Quick Action, Bottom Nav) as
/// the website's admin.menu-settings.edit page, talking to the same
/// underlying save logic via GET/PUT /company/menu-settings/{apartment}
/// (see Traits\ManagesMenuSettings on the backend). Presented here as 3
/// tabs (one per role) with both sections stacked in each, rather than the
/// website's 6 separate tabs, since scrolling one screen per role reads
/// more naturally on mobile - all the same fields are still here.
class CompanyMenuSettingsEditScreen extends StatefulWidget {
  final int apartmentId;
  final String? apartmentName;
  const CompanyMenuSettingsEditScreen({super.key, required this.apartmentId, this.apartmentName});
  @override
  State<CompanyMenuSettingsEditScreen> createState() => _CompanyMenuSettingsEditScreenState();
}

class _CompanyMenuSettingsEditScreenState extends State<CompanyMenuSettingsEditScreen> with SingleTickerProviderStateMixin {
  static const _roles = ['resident', 'apartment_admin', 'security'];

  late final TabController _tabController;
  final Map<String, _RoleMenu> _roleMenus = {};
  String? _apartmentName;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _apartmentName = widget.apartmentName;
    _tabController = TabController(length: _roles.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final rm in _roleMenus.values) {
      for (final q in rm.quick) { q.orderCtrl.dispose(); }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/menu-settings/${widget.apartmentId}');
      final data = res['data'] as Map<String, dynamic>;
      _apartmentName = (data['apartment'] as Map?)?['name'] as String? ?? _apartmentName;

      for (final role in _roles) {
        final roleData = data[role] as Map<String, dynamic>;
        final quickList = roleData['quick'] as List;
        final navData = roleData['nav'] as Map<String, dynamic>;
        final catalog = (navData['catalog'] as Map<String, dynamic>);
        final flankingKeys = List<String?>.from(navData['flankingKeys'] as List? ?? []);

        final rm = _RoleMenu()
          ..quick = quickList.map((e) {
            final m = e as Map<String, dynamic>;
            return _QuickRow(key: m['key'] as String, label: m['label'] as String, icon: m['icon'] as String? ?? '', enabled: m['enabled'] == true, order: (m['order'] as num).toInt());
          }).toList()
          ..navCatalog = catalog.entries.map((e) => _NavCatalogItem(key: e.key, label: (e.value as Map)['label'] as String, icon: (e.value as Map)['icon'] as String? ?? '')).toList()
          ..homeLabel = (navData['home'] as Map?)?['label'] as String? ?? LanguageService.t('home')
          ..flanking = [
              flankingKeys.isNotEmpty ? flankingKeys[0] : null,
              flankingKeys.length > 1 ? flankingKeys[1] : null,
              flankingKeys.length > 2 ? flankingKeys[2] : null,
            ]
          ..center = navData['centerKey'] as String?;
        _roleMenus[role] = rm;
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  bool _hasNavDuplicates(_RoleMenu rm) {
    final vals = rm.flanking.where((v) => v != null).toList();
    return vals.toSet().length != vals.length;
  }

  Future<void> _save() async {
    // Same "warn, don't block" duplicate-position check the website does
    // before submitting - a role with a duplicate silently falls back to
    // its default flanking layout server-side either way (see
    // ManagesMenuSettings::saveBottomNav), so this is just giving the
    // admin a chance to fix it first if that's not what they meant.
    final dupRoles = _roles.where((r) => _hasNavDuplicates(_roleMenus[r]!)).toList();
    if (dupRoles.isNotEmpty) {
      final proceed = await AmsDialog.confirm(
        context,
        title: LanguageService.t('nav_positions_duplicate_warning'),
        message: LanguageService.t('nav_duplicate_confirm'),
        confirmText: LanguageService.t('save_changes'),
        icon: Icons.warning_amber_rounded,
        danger: true,
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      final quick = <String, dynamic>{};
      final nav = <String, dynamic>{};
      for (final role in _roles) {
        final rm = _roleMenus[role]!;
        final enabled = <String, dynamic>{};
        final order = <String, dynamic>{};
        for (final row in rm.quick) {
          order[row.key] = int.tryParse(row.orderCtrl.text.trim()) ?? 999;
          if (row.enabled) enabled[row.key] = true;
        }
        quick[role] = {'enabled': enabled, 'order': order};
        nav[role] = {
          'position1': rm.flanking[0],
          'position2': rm.flanking[1],
          'position3': rm.flanking[2],
          'center': rm.center,
        };
      }

      await ApiService().put('/company/menu-settings/${widget.apartmentId}', {'quick': quick, 'nav': nav});
      setState(() => _saving = false);
      if (mounted) AmsDialog.info(context, title: LanguageService.t('saved'), message: LanguageService.t('app_menu_settings_updated'));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) AmsDialog.info(context, title: LanguageService.t('error'), message: e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        title: Text('${LanguageService.t('app_menu_settings')}${_apartmentName != null ? ' \u2014 $_apartmentName' : ''}', overflow: TextOverflow.ellipsis),
        bottom: _loading || _error != null ? null : TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: LanguageService.t('resident')),
            Tab(text: LanguageService.t('apartment_admin')),
            Tab(text: LanguageService.t('security')),
          ],
        ),
      ),
      floatingActionButton: _loading || _error != null ? null : FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: primary,
        icon: _saving
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check),
        label: Text(_saving ? '' : LanguageService.t('save_menu_settings')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : TabBarView(
                  controller: _tabController,
                  children: _roles.map((role) => _RoleMenuTab(role: role, roleMenu: _roleMenus[role]!, onChanged: () => setState(() {}))).toList(),
                ),
    );
  }
}

class _RoleMenuTab extends StatelessWidget {
  final String role;
  final _RoleMenu roleMenu;
  final VoidCallback onChanged;
  const _RoleMenuTab({required this.role, required this.roleMenu, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Quick Action ────────────────────────────────────────────────
        Text(LanguageService.t('quick_action'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(LanguageService.t('quick_action_hidden_hint'), style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: Column(children: [
            for (final row in roleMenu.quick)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  Checkbox(
                    value: row.enabled,
                    activeColor: primary,
                    onChanged: (v) { row.enabled = v ?? false; onChanged(); },
                  ),
                  Icon(MenuConfigService.iconFor(row.icon), size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 10),
                  Expanded(child: Text(row.label, style: const TextStyle(fontSize: 13.5))),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: row.orderCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
          ]),
        ),
        const SizedBox(height: 24),

        // ── Bottom Nav ──────────────────────────────────────────────────
        Text(LanguageService.t('bottom_nav'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.home, size: 13),
                    const SizedBox(width: 4),
                    Text(roleMenu.homeLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(LanguageService.t('always_shown_first_hint'), style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
              ]),
              const SizedBox(height: 14),
              Text(LanguageService.t('flanking_icon_positions'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              for (var pos = 0; pos < 3; pos++) ...[
                Text('${LanguageService.t('position_label')} ${pos + 1}', style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: roleMenu.flanking[pos],
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                  items: roleMenu.navCatalog.map((c) => DropdownMenuItem(value: c.key, child: Text(c.label, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) { roleMenu.flanking[pos] = v; onChanged(); },
                ),
                const SizedBox(height: 10),
              ],
              const Divider(height: 20),
              Text(LanguageService.t('centre_raised_button_pick_one'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: roleMenu.navCatalog.map((c) {
                final selected = roleMenu.center == c.key;
                return ChoiceChip(
                  label: Text(c.label, style: TextStyle(fontSize: 12.5, color: selected ? Colors.white : Colors.black87)),
                  selected: selected,
                  selectedColor: primary,
                  backgroundColor: Colors.grey.shade100,
                  onSelected: (_) { roleMenu.center = c.key; onChanged(); },
                );
              }).toList()),
            ]),
          ),
        ),
        const SizedBox(height: 90), // clears the FAB
      ],
    );
  }
}
