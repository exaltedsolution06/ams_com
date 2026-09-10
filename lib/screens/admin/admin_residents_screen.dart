import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/type_helpers.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';

class AdminResidentsScreen extends StatefulWidget {
  const AdminResidentsScreen({super.key});
  @override
  State<AdminResidentsScreen> createState() => _AdminResidentsScreenState();
}

class _AdminResidentsScreenState extends State<AdminResidentsScreen> {
  List _residents = [];
  List _flats     = [];
  // Standalone Apartment Admins (added by Super Admin, not yet also a
  // resident) that Add Resident can link to a flat instead of re-entering
  // their email/phone - see _showAddResident()'s "Link Existing Apartment
  // Admin" dropdown.
  List _linkableAdmins = [];
  bool _loading   = true;
  String _search  = '';
  final _searchCtrl = TextEditingController();
  // Cached so the edit sheet can tell "am I editing my own account?" without
  // an extra async round-trip every time it opens.
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
    AuthService().getUser().then((u) {
      if (mounted) setState(() => _currentUserId = u?['id']?.toString());
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api   = ApiService();
      final res   = await api.get('/admin/residents?search=$_search');
      final fRes  = await api.get('/admin/flats?status=vacant&include_ownership_change=1');
      final aRes  = await api.get('/admin/residents/linkable-apartment-admins');
      setState(() {
        _residents = res['data']['data'] ?? res['data'] ?? [];
        _flats     = fRes['data'] ?? [];
        _linkableAdmins = aRes['data'] ?? [];
        _loading   = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _showAddResident() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    String? selectedFlatId;
    final Set<String> additionalFlatIds = {};
    String occupancyType = 'owner';
    bool isDualRoleAdmin = false;
    String? formError;
    // "Link Existing Apartment Admin" - picking one autofills+locks
    // name/email/phone (this person already has a login) and skips the
    // password/"Mark as Apartment Admin" fields, instead of trying to
    // create a second account with the same email/phone.
    Map? linkedAdmin;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(builder: (ctx, setS) => Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormSheetHeader(
                icon: Icons.person_add_alt_1_outlined,
                title: LanguageService.t('add_resident'),
                accent: BrandingService.primary,
                onClose: () => Navigator.pop(ctx),
              ),
              FormErrorBanner(message: formError),
              if (_linkableAdmins.isNotEmpty) ...[
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: DropdownButtonFormField<Map>(
                    value: linkedAdmin,
                    isExpanded: true,
                    decoration: appFieldDecoration(label: LanguageService.t('link_existing_apartment_admin'), icon: Icons.admin_panel_settings_outlined, accent: BrandingService.secondary),
                    items: [
                      DropdownMenuItem<Map>(value: null, child: Text(LanguageService.t('none_new_resident'))),
                      ..._linkableAdmins.map<DropdownMenuItem<Map>>((a) => DropdownMenuItem(
                        value: a as Map,
                        child: Text('${a['name']} (${a['email'] ?? a['phone'] ?? ''})', overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) => setS(() {
                      linkedAdmin = v;
                      if (v != null) {
                        nameCtrl.text  = v['name']  ?? '';
                        emailCtrl.text = v['email'] ?? '';
                        phoneCtrl.text = v['phone'] ?? '';
                        isDualRoleAdmin = false;
                      }
                    }),
                  ),
                ),
                if (linkedAdmin != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(LanguageService.t('linked_admin_keeps_login'),
                        style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                  ),
                const SizedBox(height: 14),
              ],
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextFormField(
                  controller: nameCtrl,
                  enabled: linkedAdmin == null,
                  decoration: appFieldDecoration(label: LanguageService.t('full_name'), icon: Icons.person_outline, accent: BrandingService.primary),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: TextFormField(
                  controller: emailCtrl,
                  enabled: linkedAdmin == null,
                  keyboardType: TextInputType.emailAddress,
                  decoration: appFieldDecoration(label: LanguageService.t('email'), icon: Icons.email_outlined, accent: BrandingService.secondary),
                  validator: (v) => linkedAdmin != null ? null : (v!.isEmpty ? 'Required' : null),
                ),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextFormField(
                  controller: phoneCtrl,
                  enabled: linkedAdmin == null,
                  keyboardType: TextInputType.phone,
                  decoration: appFieldDecoration(label: LanguageService.t('phone'), icon: Icons.phone_outlined, accent: BrandingService.primary),
                  validator: (v) => linkedAdmin != null ? null : (v!.isEmpty ? 'Required' : null),
                ),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: DropdownButtonFormField<String>(
                  value: selectedFlatId,
                  decoration: appFieldDecoration(label: LanguageService.t('primary_flat'), icon: Icons.home_outlined, accent: BrandingService.secondary),
                  items: _flats.map<DropdownMenuItem<String>>((f) => DropdownMenuItem(
                    value: f['id'].toString(),
                    child: Text('Flat ${f['flat_number']}${toBool(f['ownership_change']) ? ' (Ownership Change)' : ''}'),
                  )).toList(),
                  onChanged: (v) => setS(() {
                    selectedFlatId = v;
                    additionalFlatIds.remove(v);
                  }),
                  validator: (v) => v == null ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(LanguageService.t('additional_flats'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 3),
              Text(LanguageService.t('check_any_other_flats_this_resident_also_owns'),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              const SizedBox(height: 8),
              AdditionalFlatsSelector(
                flats: _flats,
                excludeId: selectedFlatId,
                selectedIds: additionalFlatIds,
                accent: BrandingService.secondary,
                emptyLabel: LanguageService.t('no_other_vacant_flats_available'),
                onToggle: (id) => setS(() =>
                    additionalFlatIds.contains(id) ? additionalFlatIds.remove(id) : additionalFlatIds.add(id)),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.primary,
                child: DropdownButtonFormField<String>(
                  value: occupancyType,
                  decoration: appFieldDecoration(label: LanguageService.t('occupancy_type'), icon: Icons.key_outlined, accent: BrandingService.primary),
                  items: [
                    DropdownMenuItem(value: 'owner',  child: Text(LanguageService.t('owner'))),
                    DropdownMenuItem(value: 'tenant', child: Text(LanguageService.t('tenant'))),
                  ],
                  onChanged: (v) => setS(() => occupancyType = v!),
                ),
              ),
              if (linkedAdmin == null) ...[
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextFormField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: appFieldDecoration(label: LanguageService.t('set_password'), icon: Icons.lock_outlined, accent: BrandingService.secondary),
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  value: isDualRoleAdmin,
                  onChanged: (v) => setS(() => isDualRoleAdmin = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(LanguageService.t('mark_as_apartment_admin'), style: TextStyle(fontSize: 14)),
                  subtitle: Text(LanguageService.t('not_permanent_can_be_handed_to_someone_else_a'), style: TextStyle(fontSize: 11)),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(LanguageService.t('add_resident')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  setS(() => formError = null);
                  if (!formKey.currentState!.validate()) return;
                  try {
                    await ApiService().post('/admin/residents', {
                      if (linkedAdmin != null) 'existing_admin_user_id': linkedAdmin!['id'],
                      if (linkedAdmin == null) 'name':     nameCtrl.text.trim(),
                      if (linkedAdmin == null) 'email':    emailCtrl.text.trim(),
                      if (linkedAdmin == null) 'phone':    phoneCtrl.text.trim(),
                      if (linkedAdmin == null) 'password': passCtrl.text,
                      if (linkedAdmin == null) 'is_apartment_admin': isDualRoleAdmin,
                      'flat_id':        int.parse(selectedFlatId!),
                      'additional_flat_ids': additionalFlatIds.map((e) => int.parse(e)).toList(),
                      'occupancy_type': occupancyType,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(LanguageService.t('resident_added_successfully')), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                  }
                },
              ),
            ]),
          ),
        )),
      ),
    );
  }

  void _showEditResident(Map r) {
    final formKey  = GlobalKey<FormState>();
    final nameCtrl  = TextEditingController(text: r['name'] as String? ?? '');
    final emailCtrl = TextEditingController(text: r['email'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: r['phone'] as String? ?? '');
    final passCtrl  = TextEditingController();
    String? selectedFlatId = r['flat_id']?.toString();
    String occupancyType = r['occupancy_type'] as String? ?? 'owner';
    bool isActive = toBool(r['is_active']);
    bool isDualRoleAdmin = r['role'] == 'apartment_admin';
    String? formError;
    final isSecurity = r['role'] == 'security';
    // "Editing my own account, and it currently IS apartment_admin" — the
    // only combination where unchecking the toggle and saving demotes the
    // account I'm logged in as, which forces a logout afterwards.
    final isSelf   = _currentUserId != null && r['id'].toString() == _currentUserId;
    final wasAdmin = r['role'] == 'apartment_admin';

    // Vacant flats + any flat already linked to this resident (primary or
    // additional) - so they all still show up in the pickers, same as web.
    final linkedFlats = (r['flats'] as List?) ?? const [];
    final flatOptions = [..._flats];
    for (final f in [if (r['flat'] != null) r['flat'], ...linkedFlats]) {
      if (!flatOptions.any((existing) => existing['id'].toString() == f['id'].toString())) {
        flatOptions.add(f);
      }
    }
    final Set<String> additionalFlatIds = linkedFlats
        .map<String>((f) => f['id'].toString())
        .where((id) => id != selectedFlatId)
        .toSet();

    // Freeze the checklist order now (already-linked flats first) so it
    // doesn't jump around later as the admin checks/unchecks boxes.
    final displayFlatOptions = [...flatOptions]
      ..sort((a, b) {
        final aChecked = additionalFlatIds.contains(a['id'].toString());
        final bChecked = additionalFlatIds.contains(b['id'].toString());
        if (aChecked == bChecked) return 0;
        return aChecked ? -1 : 1;
      });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (ctx, setS) => Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormSheetHeader(
                icon: Icons.edit_outlined,
                title: 'Edit ${r['name']}',
                accent: BrandingService.primary,
                onClose: () => Navigator.pop(ctx),
              ),
              FormErrorBanner(message: formError),
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextFormField(
                  controller: nameCtrl,
                  decoration: appFieldDecoration(label: LanguageService.t('full_name'), icon: Icons.person_outline, accent: BrandingService.primary),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: appFieldDecoration(label: LanguageService.t('email'), icon: Icons.email_outlined, accent: BrandingService.secondary),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: appFieldDecoration(label: LanguageService.t('phone'), icon: Icons.phone_outlined, accent: BrandingService.primary),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
              ),
              if (!isSecurity) ...[
                const SizedBox(height: 14),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: DropdownButtonFormField<String>(
                    value: selectedFlatId,
                    decoration: appFieldDecoration(label: LanguageService.t('primary_flat'), icon: Icons.home_outlined, accent: BrandingService.secondary),
                    items: flatOptions.map<DropdownMenuItem<String>>((f) => DropdownMenuItem(
                      value: f['id'].toString(),
                      child: Text('Flat ${f['flat_number']}${toBool(f['ownership_change']) && f['id'].toString() != r['flat_id']?.toString() ? ' (Ownership Change)' : ''}'),
                    )).toList(),
                    onChanged: (v) => setS(() {
                      selectedFlatId = v;
                      additionalFlatIds.remove(v);
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                Text(LanguageService.t('additional_flats'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 3),
                Text(LanguageService.t('check_any_other_flats_this_resident_also_owns'),
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                const SizedBox(height: 8),
                AdditionalFlatsSelector(
                  flats: displayFlatOptions,
                  excludeId: selectedFlatId,
                  selectedIds: additionalFlatIds,
                  accent: BrandingService.secondary,
                  emptyLabel: LanguageService.t('no_other_vacant_flats_available'),
                  onToggle: (id) => setS(() =>
                      additionalFlatIds.contains(id) ? additionalFlatIds.remove(id) : additionalFlatIds.add(id)),
                ),
                const SizedBox(height: 16),
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: DropdownButtonFormField<String>(
                    value: occupancyType,
                    decoration: appFieldDecoration(label: LanguageService.t('occupancy_type'), icon: Icons.key_outlined, accent: BrandingService.primary),
                    items: [
                      DropdownMenuItem(value: 'owner',  child: Text(LanguageService.t('owner'))),
                      DropdownMenuItem(value: 'tenant', child: Text(LanguageService.t('tenant'))),
                    ],
                    onChanged: (v) => setS(() => occupancyType = v!),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: TextFormField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: appFieldDecoration(label: LanguageService.t('reset_password_optional'), icon: Icons.lock_outlined, accent: BrandingService.secondary, hint: LanguageService.t('leave_blank_to_keep_current_password')),
                  validator: (v) => (v != null && v.isNotEmpty && v.length < 6) ? 'Min 6 characters' : null,
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: isActive,
                onChanged: (v) => setS(() => isActive = v),
                contentPadding: EdgeInsets.zero,
                title: Text(LanguageService.t('active'), style: TextStyle(fontSize: 14)),
              ),
              if (!isSecurity)
                SwitchListTile(
                  value: isDualRoleAdmin,
                  onChanged: (v) => setS(() => isDualRoleAdmin = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(LanguageService.t('mark_as_apartment_admin'), style: TextStyle(fontSize: 14)),
                  subtitle: Text(LanguageService.t('not_permanent_can_be_handed_to_someone_else_a'), style: TextStyle(fontSize: 11)),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(LanguageService.t('save_changes')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  setS(() => formError = null);
                  if (!formKey.currentState!.validate()) return;

                  // Self-demotion: I'm editing my own account, it's
                  // currently apartment_admin, and I've unchecked the
                  // toggle. Saving this will log me out — confirm first so
                  // it never happens as a surprise mid-save.
                  if (isSelf && wasAdmin && !isDualRoleAdmin) {
                    final confirmed = await AmsDialog.confirm(
                      ctx,
                      title: LanguageService.t('confirm'),
                      message: LanguageService.t('you_are_not_now_apartment_admin_if_you_submit'),
                      icon: Icons.logout_rounded,
                      confirmText: LanguageService.t('yes'),
                      cancelText: LanguageService.t('cancel'),
                      danger: true,
                    );
                    if (confirmed != true) return; // Cancel → do nothing, sheet stays open
                  }

                  try {
                    final res = await ApiService().put('/admin/residents/${r['id']}', {
                      'name':     nameCtrl.text.trim(),
                      'email':    emailCtrl.text.trim(),
                      'phone':    phoneCtrl.text.trim(),
                      if (!isSecurity) 'occupancy_type': occupancyType,
                      if (!isSecurity && selectedFlatId != null) 'flat_id': int.parse(selectedFlatId!),
                      if (!isSecurity) 'additional_flat_ids': additionalFlatIds.map((e) => int.parse(e)).toList(),
                      if (passCtrl.text.isNotEmpty) 'password': passCtrl.text,
                      'is_active': isActive,
                      if (!isSecurity) 'is_apartment_admin': isDualRoleAdmin,
                    });

                    // Backend confirmed this update demoted the account I'm
                    // currently logged in as — close the sheet, clear the
                    // session, and bounce to login (message shown first,
                    // while this screen is still mounted, so it's not lost
                    // mid-navigation).
                    if (res['force_logout'] == true) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['message']?.toString() ??
                                'You are no longer an Apartment Admin, so you have been logged out.'),
                            backgroundColor: Colors.orange,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      await AuthService().logout();
                      if (mounted) context.go('/login');
                      return;
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(LanguageService.t('resident_updated_successfully')), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                  }
                },
              ),
            ]),
          ),
        )),
      ),
    );
  }

  void _toggleActive(Map r) async {
    try {
      await ApiService().put('/admin/residents/${r['id']}', {'is_active': !(toBool(r['is_active']))});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Remove resident ────────────────────────────────────────────────────
  // Permanently deletes the resident and ALL of their related data (bills,
  // payments, wallet, complaints, family members, vehicles, chat messages,
  // etc. - see AdminApiController::destroyResident() on the backend, which
  // cascade-deletes everything at the DB level). Confirmed here first so
  // it never happens as a surprise mid-tap.
  Future<void> _deleteResident(Map r) async {
    final confirmed = await AmsDialog.confirm(
      context,
      title: LanguageService.t('remove_resident'),
      message: '${LanguageService.t('confirm_remove_resident')} ${r['name']}? '
          '${LanguageService.t('remove_resident_warning')}',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('yes_remove'),
      cancelText: LanguageService.t('cancel'),
      danger: true,
    );
    if (confirmed != true) return;

    try {
      await ApiService().delete('/admin/residents/${r['id']}');
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('resident_removed')), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('residents')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddResident,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(LanguageService.t('add')),
        backgroundColor: primary,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: primary.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: LanguageService.t('search_by_name_phone_or_email'),
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13.5),
                prefixIcon: Icon(Icons.search, color: primary),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                        _load();
                      })
                    : null,
                fillColor: Colors.white,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: primary, width: 1.4)),
              ),
              onSubmitted: (v) { setState(() => _search = v); _load(); },
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _residents.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outline,
                      color: primary,
                      title: LanguageService.t('no_residents_found'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                      itemCount: _residents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r        = _residents[i] as Map;
                        final isActive = toBool(r['is_active']);
                        final flatNo   = r['flat']?['flat_number'] ?? '—';
                        final avatarColor = r['occupancy_type'] == 'owner' ? Colors.blue : Colors.teal;
                        return Card(
                          child: ListTile(
                            onTap: () => _showEditResident(r),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            leading: Container(
                              width: 44, height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [avatarColor, avatarColor.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: avatarColor.withOpacity(0.32), blurRadius: 8, offset: const Offset(0, 3))],
                              ),
                              child: Text(
                                (r['name'] as String? ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            title: Text(r['name'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${LanguageService.t('flat_label')} $flatNo  ·  ${r['phone'] ?? ''}',
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: avatarColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                  LanguageService.t(r['occupancy_type'] as String? ?? '').toUpperCase(),
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: avatarColor),
                                ),
                              ),
                            ]),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: isActive,
                                  onChanged: (_) => _toggleActive(r),
                                  activeColor: BrandingService.primary,
                                ),
                                // Can't remove your own account from here.
                                if (_currentUserId == null || r['id'].toString() != _currentUserId)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                    color: Colors.red[400],
                                    tooltip: LanguageService.t('remove_resident'),
                                    onPressed: () => _deleteResident(r),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
